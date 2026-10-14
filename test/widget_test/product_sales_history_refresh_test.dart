import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mobo_sales/models/product.dart';
import 'package:mobo_sales/providers/currency_provider.dart';
import 'package:mobo_sales/screens/products/product_sales_history_screen.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/widgets/loading_skeletons.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockCurrencyProvider extends Mock implements CurrencyProvider {}

/// The sales history of a product follows the quotations: when one is created,
/// edited, confirmed, cancelled or deleted anywhere in the app, the page that
/// is open re-reads its figures in place, without going back to the skeleton.
void main() {
  late _MockCurrencyProvider currency;
  late double revenue;
  late int lineReads;

  Product product() => Product(
    id: '5',
    name: 'Widget',
    listPrice: 10,
    qtyAvailable: 3,
    variantCount: 1,
    defaultCode: 'W-1',
  );

  Future<dynamic> callKw(Map<String, dynamic> payload) async {
    // The server takes a moment, so a loading state would be on screen for a
    // few frames if the page went back to one.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (payload['model'] == 'sale.order.line') {
      lineReads++;
      final isQuotationRead =
          payload['args'].toString().contains('draft') &&
          payload['kwargs']['limit'] == 100;
      if (isQuotationRead) return [];
      return [
        {
          'order_id': [1, 'S0001'],
          'product_uom_qty': 2.0,
          'price_unit': revenue / 2,
          'price_subtotal': revenue,
          'create_date': DateTime.now().toString().split('.').first,
          'state': 'sale',
        },
      ];
    }
    if (payload['model'] == 'sale.order') {
      return [
        {
          'id': 1,
          'name': 'S0001',
          'partner_id': [3, 'Ada'],
        },
      ];
    }
    return [];
  }

  setUp(() {
    revenue = 100;
    lineReads = 0;
    currency = _MockCurrencyProvider();
    when(() => currency.currency).thenReturn('USD');
    when(
      () => currency.currencyFormat,
    ).thenReturn(NumberFormat.currency(symbol: '\$'));
    when(
      () => currency.formatAmount(any(), currency: any(named: 'currency')),
    ).thenReturn('\$0.00');
  });

  Widget app() => ChangeNotifierProvider<CurrencyProvider>.value(
    value: currency,
    child: MaterialApp(
      home: ProductSalesHistoryScreen(product: product(), callKw: callKw),
    ),
  );

  /// Moves the clock on in small steps so each frame can be looked at.
  Future<void> pumpFor(WidgetTester tester, Duration total) async {
    var elapsed = Duration.zero;
    while (elapsed < total) {
      await tester.pump(const Duration(milliseconds: 50));
      elapsed += const Duration(milliseconds: 50);
    }
  }

  testWidgets('the first load shows the skeleton, then the figures', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    expect(find.byType(SalesHistorySkeleton), findsOneWidget);

    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.byType(SalesHistorySkeleton), findsNothing);
    expect(find.text('100.00'), findsOneWidget);
  });

  testWidgets('a quotation change refreshes in place, never via the skeleton', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('100.00'), findsOneWidget);
    final readsAfterFirstLoad = lineReads;

    revenue = 250;
    DataChangeBus.instance.quotationChanged(1);

    var skeletonSeen = false;
    var oldFiguresVanished = false;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(SalesHistorySkeleton).evaluate().isNotEmpty) {
        skeletonSeen = true;
      }
      // Until the new figures are in, the old ones stay on screen.
      if (find.text('100.00').evaluate().isEmpty &&
          find.text('250.00').evaluate().isEmpty) {
        oldFiguresVanished = true;
      }
    }

    expect(skeletonSeen, isFalse);
    expect(oldFiguresVanished, isFalse);
    expect(find.text('250.00'), findsOneWidget);
    expect(lineReads, greaterThan(readsAfterFirstLoad));
  });

  testWidgets('the scroll position survives a refresh', (tester) async {
    tester.view.physicalSize = const Size(600, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await pumpFor(tester, const Duration(milliseconds: 600));

    final scrollable = find.byType(SingleChildScrollView);
    await tester.drag(scrollable, const Offset(0, -250));
    await tester.pump();
    ScrollPosition position() =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final before = position().pixels;
    expect(before, greaterThan(0));

    revenue = 300;
    DataChangeBus.instance.quotationChanged(1);
    await pumpFor(tester, const Duration(milliseconds: 1500));

    expect(position().pixels, before);
  });

  testWidgets('a burst of changes is one read, other changes none', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await pumpFor(tester, const Duration(milliseconds: 600));

    final before = lineReads;
    DataChangeBus.instance.invoiceChanged(9);
    DataChangeBus.instance.paymentChanged(9);
    DataChangeBus.instance.publish(DataEntity.customer, DataChangeKind.updated);
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(lineReads, before);

    DataChangeBus.instance.quotationChanged(1);
    DataChangeBus.instance.quotationChanged(2, kind: DataChangeKind.created);
    DataChangeBus.instance.quotationChanged(1, kind: DataChangeKind.deleted);
    await pumpFor(tester, const Duration(milliseconds: 1500));
    // Two line reads (sales, quotations) make one refresh.
    expect(lineReads - before, 2);
  });

  testWidgets('a page that is gone does not refresh', (tester) async {
    await tester.pumpWidget(app());
    await pumpFor(tester, const Duration(milliseconds: 600));

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final before = lineReads;
    DataChangeBus.instance.quotationChanged(1);
    await pumpFor(tester, const Duration(milliseconds: 600));

    expect(lineReads, before);
    expect(tester.takeException(), isNull);
  });
}
