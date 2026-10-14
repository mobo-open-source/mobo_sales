import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:mobo_sales/providers/currency_provider.dart';
import 'package:mobo_sales/screens/invoices/invoice_list_screen.dart';
import 'package:mobo_sales/services/connectivity_service.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/services/session_service.dart';

class _MockCurrencyProvider extends Mock implements CurrencyProvider {}

class _MockConnectivityService extends Mock implements ConnectivityService {}

class _MockSessionService extends Mock implements SessionService {}

Map<String, dynamic> _invoice(int id, String name, {String state = 'draft'}) =>
    {
      'id': id,
      'name': name,
      'invoice_date': '2026-10-01',
      'invoice_date_due': '2026-10-31',
      'amount_total': 100.0,
      'amount_residual': 100.0,
      'state': state,
      'partner_id': [1, 'Acme'],
      'payment_state': 'not_paid',
      'currency_id': [1, 'USD'],
      'invoice_origin': false,
    };

/// A fake server: what the list reads, and how often it asked.
class _FakeServer {
  List<Map<String, dynamic>> rows = [_invoice(1, 'INV/0001')];
  final List<Map<String, dynamic>> readCalls = [];

  /// When set, a read waits for this before answering.
  Completer<void>? hold;

  Future<dynamic> call(Map<String, dynamic> payload) async {
    if (payload['method'] == 'search_read') readCalls.add(payload);
    final gate = hold;
    if (gate != null && payload['method'] == 'search_read') {
      await gate.future;
    }
    switch (payload['method']) {
      case 'search_count':
        return rows.length;
      case 'search_read':
        final kwargs = payload['kwargs'] as Map;
        final offset = kwargs['offset'] as int;
        final limit = kwargs['limit'] as int;
        return rows.skip(offset).take(limit).toList();
    }
    return null;
  }
}

void main() {
  late _FakeServer server;
  late _MockCurrencyProvider currency;
  late _MockConnectivityService connectivity;
  late _MockSessionService session;

  setUp(() {
    InvoiceListScreen.clearInvoiceCache();
    server = _FakeServer();
    currency = _MockCurrencyProvider();
    connectivity = _MockConnectivityService();
    session = _MockSessionService();
    when(
      () => currency.formatAmount(any(), currency: any(named: 'currency')),
    ).thenReturn('\$ 100.00');
    when(() => connectivity.isConnected).thenReturn(true);
    when(() => session.hasValidSession).thenReturn(true);
  });

  tearDown(InvoiceListScreen.clearInvoiceCache);

  Widget host({Widget? child}) => MultiProvider(
    providers: [
      ChangeNotifierProvider<CurrencyProvider>.value(value: currency),
      ChangeNotifierProvider<ConnectivityService>.value(value: connectivity),
      ChangeNotifierProvider<SessionService>.value(value: session),
    ],
    child: MaterialApp(home: child ?? InvoiceListScreen(callKw: server.call)),
  );

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Past the 350 ms the list waits for a burst of changes to end, and the
  /// refresh itself.
  Future<void> letTheListRefresh(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('an invoice created elsewhere appears, with no skeleton and no '
      'reload of what was there', (tester) async {
    await pumpList(tester);
    expect(find.text('INV/0001'), findsOneWidget);
    expect(server.readCalls, hasLength(1));

    server.rows = [_invoice(2, 'INV/0002'), _invoice(1, 'INV/0001')];
    server.hold = Completer<void>();
    DataChangeBus.instance.invoiceChanged(2, kind: DataChangeKind.created);
    await letTheListRefresh(tester);

    // The refresh is in flight: the list shows what it had, not a skeleton.
    expect(server.readCalls, hasLength(2));
    expect(find.text('INV/0001'), findsOneWidget);
    expect(find.byType(Shimmer), findsNothing);

    server.hold!.complete();
    server.hold = null;
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('INV/0002'), findsOneWidget);
    expect(find.text('INV/0001'), findsOneWidget);
    expect(find.byType(Shimmer), findsNothing);
  });

  testWidgets('a deleted invoice disappears', (tester) async {
    server.rows = [_invoice(1, 'INV/0001'), _invoice(2, 'INV/0002')];
    await pumpList(tester);
    expect(find.text('INV/0002'), findsOneWidget);

    server.rows = [_invoice(1, 'INV/0001')];
    DataChangeBus.instance.invoiceChanged(2, kind: DataChangeKind.deleted);
    await letTheListRefresh(tester);

    expect(find.text('INV/0002'), findsNothing);
    expect(find.text('INV/0001'), findsOneWidget);
  });

  testWidgets('a payment changes the status chip', (tester) async {
    await pumpList(tester);
    expect(find.text('Draft'), findsOneWidget);

    server.rows = [_invoice(1, 'INV/0001', state: 'cancel')];
    DataChangeBus.instance.paymentChanged(9);
    await letTheListRefresh(tester);

    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Draft'), findsNothing);
  });

  testWidgets('a burst of changes is one refresh', (tester) async {
    await pumpList(tester);
    expect(server.readCalls, hasLength(1));

    DataChangeBus.instance.quotationChanged(5);
    DataChangeBus.instance.invoiceChanged(1);
    DataChangeBus.instance.paymentChanged(3);
    await letTheListRefresh(tester);

    expect(server.readCalls, hasLength(2));
  });

  testWidgets('a change that is not about invoices does not refresh the list', (
    tester,
  ) async {
    await pumpList(tester);

    DataChangeBus.instance.publish(DataEntity.customer, DataChangeKind.updated);
    DataChangeBus.instance.publish(DataEntity.product, DataChangeKind.updated);
    await letTheListRefresh(tester);

    expect(server.readCalls, hasLength(1));
  });

  testWidgets('the refresh asks for the pages the list shows, not just the '
      'first', (tester) async {
    server.rows = [for (var i = 1; i <= 45; i++) _invoice(i, 'INV/$i')];
    await pumpList(tester);
    expect(server.readCalls.single['kwargs']['limit'], 40);
    expect(server.readCalls.single['kwargs']['offset'], 0);

    // The user opens the next page with the arrow.
    final state = tester.state<InvoiceListScreenState>(
      find.byType(InvoiceListScreen),
    );
    await state.goToNextPage();
    await tester.pump(const Duration(milliseconds: 50));
    expect(state.currentPage, 1);

    DataChangeBus.instance.invoiceChanged(1);
    await letTheListRefresh(tester);

    final refresh = server.readCalls.last['kwargs'];
    expect(refresh['offset'], 40, reason: 'still the page the user is on');
    expect(refresh['limit'], 40);
    expect(state.currentPage, 1);
  });

  testWidgets('a change that arrives during a load runs once more after it', (
    tester,
  ) async {
    await pumpList(tester);
    server.hold = Completer<void>();

    DataChangeBus.instance.invoiceChanged(1);
    await letTheListRefresh(tester);
    expect(server.readCalls, hasLength(2), reason: 'first refresh, held');

    // A second change while that one is still waiting for the server.
    DataChangeBus.instance.invoiceChanged(1);
    await letTheListRefresh(tester);
    expect(server.readCalls, hasLength(2), reason: 'no overlapping request');

    server.hold!.complete();
    server.hold = null;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(server.readCalls, hasLength(3));
  });

  testWidgets('a list that was left stops listening', (tester) async {
    await pumpList(tester);
    expect(server.readCalls, hasLength(1));

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    DataChangeBus.instance.invoiceChanged(1);
    await letTheListRefresh(tester);

    expect(server.readCalls, hasLength(1));
  });

  testWidgets('a refresh that fails leaves the list as it was, with no error', (
    tester,
  ) async {
    await pumpList(tester);

    final failing = _FakeServer()..rows = server.rows;
    var failNext = false;
    await tester.pumpWidget(
      host(
        child: InvoiceListScreen(
          key: const ValueKey('same'),
          callKw: (payload) {
            if (failNext) throw Exception('offline');
            return failing.call(payload);
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('INV/0001'), findsOneWidget);

    failNext = true;
    DataChangeBus.instance.invoiceChanged(1);
    await letTheListRefresh(tester);

    expect(find.text('INV/0001'), findsOneWidget);
    expect(find.textContaining('Failed to load invoices'), findsNothing);
  });
}
