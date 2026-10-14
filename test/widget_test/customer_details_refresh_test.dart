import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mobo_sales/models/contact.dart';
import 'package:mobo_sales/providers/contact_provider.dart';
import 'package:mobo_sales/providers/currency_provider.dart';
import 'package:mobo_sales/screens/customers/customer_details_screen.dart';
import 'package:mobo_sales/services/connectivity_service.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/services/session_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

import '../mocks/mock_services.dart';

class _MockCurrencyProvider extends Mock implements CurrencyProvider {}

class _MockContactProvider extends Mock implements ContactProvider {}

/// A customer's page follows the orders and invoices around it and the
/// customer's own record: when one changes anywhere in the app, the page that
/// is open reads it again in place, with no skeleton.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockOdooClient client;
  late MockSessionService session;
  late MockConnectivityService connectivity;
  late _MockCurrencyProvider currency;
  late _MockContactProvider contacts;

  // What the "server" holds, and how often each part was read.
  late String customerName;
  late int totalOrders;
  late int confirmedOrders;
  late int partnerReads;
  late int orderReads;

  Future<dynamic> server(Map<String, dynamic> payload) async {
    // The server takes a moment, so a loading state would be on screen for a
    // few frames if the page went back to one.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final model = payload['model'];
    final method = payload['method'];
    if (model == 'res.partner' && method == 'read') {
      partnerReads++;
      return [
        {
          'id': 1,
          'name': customerName,
          'email': 'ada@example.com',
          'phone': '555-0100',
          'is_company': false,
          'active': true,
        },
      ];
    }
    if (model == 'sale.order') {
      orderReads++;
      final domain = payload['args'][0].toString();
      if (method == 'search_count') {
        if (domain.contains('draft')) return totalOrders - confirmedOrders;
        if (domain.contains('sale')) return confirmedOrders;
        return totalOrders;
      }
      if (method == 'search_read') return <Map<String, dynamic>>[];
    }
    return <dynamic>[];
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    customerName = 'Ada Lovelace';
    totalOrders = 7;
    confirmedOrders = 5;
    partnerReads = 0;
    orderReads = 0;

    client = MockOdooClient();
    when(() => client.callKw(any())).thenAnswer(
      (invocation) => server(
        Map<String, dynamic>.from(invocation.positionalArguments.first as Map),
      ),
    );

    session = MockSessionService();
    when(() => session.client).thenAnswer((_) async => client);
    when(() => session.hasValidSession).thenReturn(true);
    when(() => session.isInitialized).thenReturn(true);
    when(() => session.isCheckingSession).thenReturn(false);
    when(() => session.isServerUnreachable).thenReturn(false);

    connectivity = MockConnectivityService();
    when(() => connectivity.isConnected).thenReturn(true);
    when(() => connectivity.isInitialized).thenReturn(true);

    currency = _MockCurrencyProvider();
    when(() => currency.currency).thenReturn('USD');
    when(
      () => currency.currencyFormat,
    ).thenReturn(NumberFormat.currency(symbol: '\$'));
    when(
      () => currency.formatAmount(any(), currency: any(named: 'currency')),
    ).thenReturn('\$0.00');

    contacts = _MockContactProvider();
  });

  Widget app() => MultiProvider(
    providers: [
      ChangeNotifierProvider<SessionService>.value(value: session),
      ChangeNotifierProvider<ConnectivityService>.value(value: connectivity),
      ChangeNotifierProvider<CurrencyProvider>.value(value: currency),
      ChangeNotifierProvider<ContactProvider>.value(value: contacts),
    ],
    child: MaterialApp(
      home: CustomerDetailsScreen(
        contact: Contact(id: 1, name: 'Ada Lovelace'),
      ),
    ),
  );

  Future<void> pumpFor(WidgetTester tester, Duration total) async {
    var elapsed = Duration.zero;
    while (elapsed < total) {
      await tester.pump(const Duration(milliseconds: 50));
      elapsed += const Duration(milliseconds: 50);
    }
  }

  Future<void> openPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await pumpFor(tester, const Duration(seconds: 2));
  }

  /// Pumps through [total] and says whether the loading skeleton was ever up.
  Future<bool> skeletonSeenWhilePumping(
    WidgetTester tester,
    Duration total,
  ) async {
    var seen = false;
    var elapsed = Duration.zero;
    while (elapsed < total) {
      await tester.pump(const Duration(milliseconds: 50));
      elapsed += const Duration(milliseconds: 50);
      if (find.byType(Shimmer).evaluate().isNotEmpty) seen = true;
    }
    return seen;
  }

  testWidgets('the first load shows the skeleton, then the figures', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    expect(find.byType(Shimmer), findsWidgets);

    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.byType(Shimmer), findsNothing);
    expect(find.text('Customer Statistics'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('a quotation change updates the counts in place', (tester) async {
    await openPage(tester);
    final partnerReadsBefore = partnerReads;

    totalOrders = 8;
    confirmedOrders = 6;
    DataChangeBus.instance.quotationChanged(10);
    final skeleton = await skeletonSeenWhilePumping(
      tester,
      const Duration(seconds: 2),
    );

    expect(skeleton, isFalse);
    expect(find.text('Customer Statistics'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    // Orders changed, not the customer: the record is not read again.
    expect(partnerReads, partnerReadsBefore);
  });

  testWidgets('an invoice or a payment change refreshes it too', (
    tester,
  ) async {
    await openPage(tester);
    final before = orderReads;

    DataChangeBus.instance.invoiceChanged(3, kind: DataChangeKind.created);
    DataChangeBus.instance.paymentChanged(4);
    await pumpFor(tester, const Duration(seconds: 2));

    expect(orderReads, greaterThan(before));
  });

  testWidgets('this customer edited elsewhere is read again, in place', (
    tester,
  ) async {
    await openPage(tester);
    expect(find.text('Ada Lovelace'), findsWidgets);
    final partnerReadsBefore = partnerReads;

    customerName = 'Ada King';
    DataChangeBus.instance.publish(
      DataEntity.customer,
      DataChangeKind.updated,
      id: 1,
    );
    final skeleton = await skeletonSeenWhilePumping(
      tester,
      const Duration(seconds: 2),
    );

    expect(skeleton, isFalse);
    expect(partnerReads, greaterThan(partnerReadsBefore));
    expect(find.text('Ada King'), findsWidgets);
    expect(find.text('Ada Lovelace'), findsNothing);
  });

  testWidgets('another customer, or a product, changes nothing', (
    tester,
  ) async {
    await openPage(tester);
    final partnerReadsBefore = partnerReads;
    final orderReadsBefore = orderReads;

    DataChangeBus.instance.publish(
      DataEntity.customer,
      DataChangeKind.updated,
      id: 99,
    );
    DataChangeBus.instance.publish(DataEntity.product, DataChangeKind.updated);
    await pumpFor(tester, const Duration(seconds: 1));

    expect(partnerReads, partnerReadsBefore);
    expect(orderReads, orderReadsBefore);
  });

  testWidgets('a burst of changes is one reload', (tester) async {
    await openPage(tester);
    final before = orderReads;

    DataChangeBus.instance.quotationChanged(1);
    DataChangeBus.instance.quotationChanged(2, kind: DataChangeKind.created);
    DataChangeBus.instance.invoiceChanged(3);
    await pumpFor(tester, const Duration(seconds: 2));

    // One reload asks the server for the orders four times (count, amounts
    // and counts of the confirmed and draft ones) and for the latest five.
    expect(orderReads - before, 5);
  });

  testWidgets('a page that is gone does not reload', (tester) async {
    await openPage(tester);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final before = orderReads;
    DataChangeBus.instance.quotationChanged(1);
    await pumpFor(tester, const Duration(seconds: 1));

    expect(orderReads, before);
    expect(tester.takeException(), isNull);
  });
}
