import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobo_sales/screens/quotations/create_quote_screen.dart';
import 'package:mobo_sales/shared/widgets/mobo/mobo_select_field.dart';
import 'package:mobo_sales/widgets/custom_date_picker.dart';
import 'package:mobo_sales/widgets/customer_typeahead.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:mobo_sales/screens/invoices/create_invoice_screen.dart';
import 'package:mobo_sales/providers/invoice_creation_provider.dart';
import 'package:mobo_sales/providers/currency_provider.dart';
import 'package:mobo_sales/providers/contact_provider.dart';
import 'package:mobo_sales/services/connectivity_service.dart';
import 'package:mobo_sales/services/session_service.dart';

class MockCreateInvoiceProvider extends Mock implements CreateInvoiceProvider {}

class MockCurrencyProvider extends Mock implements CurrencyProvider {}

class MockContactProvider extends Mock implements ContactProvider {}

class MockConnectivityService extends Mock implements ConnectivityService {}

class MockSessionService extends Mock implements SessionService {}

/// A widget test that always ends by taking the screen down and letting its
/// debounce timers run out, which the framework checks for.
void lockedTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    }
  });
}

void main() {
  setUpAll(() => HttpOverrides.global = null);
  late MockCreateInvoiceProvider mockInvoiceProvider;
  late MockCurrencyProvider mockCurrencyProvider;
  // The quote lines draw amounts, which a bare mock cannot format.
  late CurrencyProvider realCurrency;
  late MockContactProvider mockContactProvider;
  late MockConnectivityService mockConnectivityService;
  late MockSessionService mockSessionService;

  setUp(() {
    mockInvoiceProvider = MockCreateInvoiceProvider();
    mockCurrencyProvider = MockCurrencyProvider();
    realCurrency = CurrencyProvider();
    mockContactProvider = MockContactProvider();
    mockConnectivityService = MockConnectivityService();
    mockSessionService = MockSessionService();

    when(() => mockInvoiceProvider.isLoading).thenReturn(false);
    when(() => mockInvoiceProvider.customers).thenReturn([]);
    when(() => mockInvoiceProvider.selectedCustomer).thenReturn(null);
    when(() => mockInvoiceProvider.invoiceLines).thenReturn([]);
    when(() => mockInvoiceProvider.subtotal).thenReturn(0.0);
    when(() => mockInvoiceProvider.taxAmount).thenReturn(0.0);
    when(() => mockInvoiceProvider.total).thenReturn(0.0);
    when(() => mockInvoiceProvider.invoiceDate).thenReturn(DateTime.now());
    when(
      () => mockInvoiceProvider.dueDate,
    ).thenReturn(DateTime.now().add(const Duration(days: 30)));
    when(
      () => mockInvoiceProvider.customerSearchController,
    ).thenReturn(TextEditingController());
    when(
      () => mockInvoiceProvider.saleOrderSearchController,
    ).thenReturn(TextEditingController());
    when(() => mockInvoiceProvider.selectedSaleOrder).thenReturn(null);
    when(() => mockInvoiceProvider.filteredSaleOrders).thenReturn([]);
    when(() => mockInvoiceProvider.isLoadingSaleOrders).thenReturn(false);
    when(() => mockInvoiceProvider.isLoadingSaleOrderDetails).thenReturn(false);
    when(() => mockInvoiceProvider.isLoadingCustomers).thenReturn(false);
    when(() => mockInvoiceProvider.isCreatingInvoice).thenReturn(false);
    when(() => mockInvoiceProvider.taxTotals).thenReturn({});
    when(() => mockInvoiceProvider.isCalculatingTax).thenReturn(false);
    when(() => mockInvoiceProvider.paymentTerms).thenReturn([]);
    when(() => mockInvoiceProvider.selectedPaymentTerm).thenReturn(null);
    when(() => mockInvoiceProvider.errorMessage).thenReturn('');
    when(() => mockInvoiceProvider.isAddingLine).thenReturn(false);

    when(() => mockInvoiceProvider.fetchCustomers()).thenAnswer((_) async {});
    when(() => mockInvoiceProvider.fetchSaleOrders()).thenAnswer((_) async {});
    when(
      () => mockInvoiceProvider.fetchPaymentTerms(),
    ).thenAnswer((_) async {});
    when(() => mockInvoiceProvider.fetchProducts()).thenAnswer((_) async {});

    when(() => mockCurrencyProvider.currency).thenReturn('USD');
    when(
      () => mockCurrencyProvider.currencyFormat,
    ).thenReturn(NumberFormat.currency(symbol: '\$'));

    when(() => mockContactProvider.contacts).thenReturn([]);
    when(() => mockContactProvider.isServerUnreachable).thenReturn(false);

    when(() => mockConnectivityService.isConnected).thenReturn(true);
    when(() => mockSessionService.hasValidSession).thenReturn(true);
  });

  Widget withProviders(Widget home) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CreateInvoiceProvider>.value(
          value: mockInvoiceProvider,
        ),
        ChangeNotifierProvider<CurrencyProvider>.value(value: realCurrency),
        ChangeNotifierProvider<ContactProvider>.value(
          value: mockContactProvider,
        ),
        ChangeNotifierProvider<ConnectivityService>.value(
          value: mockConnectivityService,
        ),
        ChangeNotifierProvider<SessionService>.value(value: mockSessionService),
      ],
      child: MaterialApp(home: home),
    );
  }

  late HttpServer server;
  final asked = <Map<String, dynamic>>[];
  var orderState = 'draft';

  Future<void> startServer() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final params = (body['params'] as Map?) ?? {};
        final model = params['model'];
        final method = params['method'];
        asked.add(Map<String, dynamic>.from(params));

        dynamic result = [];
        if (model == 'sale.order' && method == 'read') {
          final args = params['args'] as List;
          final fields =
              (args.length > 1 ? args[1] : params['kwargs']?['fields'])
                  as List? ??
              const [];
          result = [
            {
              'id': 9,
              'company_id': [1, 'Company 1'],
              'state': orderState,
              'pricelist_id': [5, 'VIP Pricelist'],
              'payment_term_id': [3, '30 Days'],
              'order_line': [11],
              if (fields.contains('amount_total')) 'amount_total': 100.0,
            },
          ];
        } else if (model == 'sale.order' && method == 'default_get') {
          result = {'picking_policy': 'direct'};
        } else if (model == 'sale.order' && method == 'write') {
          result = true;
        } else if (model == 'sale.order.line' && method == 'read') {
          result = [
            {
              'id': 11,
              'product_id': [4, 'Desk'],
              'name': 'Desk',
              'product_uom_qty': 2.0,
              'price_unit': 50.0,
              'price_subtotal': 100.0,
              'product_uom': [1, 'Units'],
              'tax_id': [],
              'product_uom_id': [1, 'Units'],
              'tax_ids': [],
            },
          ];
        } else if (model == 'res.partner' && method == 'read') {
          result = [
            {
              'id': 7,
              'name': 'Azure Interior',
              // The customer's own defaults: what a NEW quotation would start
              // from, and what an edit used to wrongly show.
              'property_product_pricelist': [1, 'Public Pricelist'],
              'property_payment_term_id': [1, 'Immediate Payment'],
            },
          ];
        } else if (model == 'product.pricelist') {
          result = [
            {
              'id': 1,
              'name': 'Public Pricelist',
              'currency_id': [1, 'USD'],
            },
            {
              'id': 2,
              'name': 'Other Pricelist',
              'currency_id': [1, 'USD'],
            },
          ];
        } else if (model == 'account.payment.term') {
          result = [
            {'id': 1, 'name': 'Immediate Payment'},
            {'id': 3, 'name': '30 Days'},
          ];
        }
        request.response
          ..persistentConnection = false
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
          );
        await request.response.close();
      }),
    );
  }

  Future<void> signIn(int user) async {
    SharedPreferences.setMockInitialValues({
      'isLoggedIn': true,
      'sessionId': 'sess123',
      'userLogin': 'admin',
      'password': 'x',
      'database': 'shop',
      'serverUrl': 'http://127.0.0.1:${server.port}',
      'userId': user,
      'userName': 'Admin',
      'serverVersion': '18.0',
      'selected_company_id': 1,
      'selected_allowed_company_ids': ['1'],
      'expiresAt': DateTime.now()
          .add(const Duration(hours: 5))
          .toIso8601String(),
    });
    OdooSessionManager.clearClientCache();
  }

  Future<void> openEdit(WidgetTester tester, String state, int user) async {
    orderState = state;
    asked.clear();
    await signIn(user);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      withProviders(
        CreateQuoteScreen(
          quotationToEdit: {
            'id': 9,
            'name': 'S00009',
            'state': state,
            'partner_id': [7, 'Azure Interior'],
            'order_line': [11],
            'validity_date': '2026-12-01',
          },
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Lets the real network and the screen run until the write has gone out.
  Future<void> untilWritten(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      if (asked.any(
        (p) => p['model'] == 'sale.order' && p['method'] == 'write',
      )) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  MoboSelectField<String> pricelistField(WidgetTester tester) =>
      tester.widget<MoboSelectField<String>>(
        find.byWidgetPredicate(
          (w) => w is MoboSelectField<String> && w.label == 'Pricelist',
        ),
      );

  CustomerTypeAhead customerField(WidgetTester tester) =>
      tester.widget<CustomerTypeAhead>(find.byType(CustomerTypeAhead));

  group('a confirmed sale order, as in Odoo', () {
    lockedTest('customer and pricelist are read-only, expiration is hidden', (
      tester,
    ) async {
      await tester.runAsync(startServer);
      addTearDown(() => tester.runAsync(() => server.close(force: true)));
      await openEdit(tester, 'sale', 41);

      expect(customerField(tester).enabled, isFalse, reason: 'customer');
      expect(pricelistField(tester).enabled, isFalse, reason: 'pricelist');
      expect(pricelistField(tester).allowClear, isFalse);
      expect(
        find.byType(CustomDateSelector),
        findsNothing,
        reason: 'expiration',
      );
    });

    lockedTest('the form shows the ORDER\'s pricelist and term, not the '
        'customer\'s defaults', (tester) async {
      await tester.runAsync(startServer);
      addTearDown(() => tester.runAsync(() => server.close(force: true)));
      await openEdit(tester, 'sale', 42);

      expect(pricelistField(tester).value, '5');
      expect(find.text('VIP Pricelist'), findsOneWidget);
      expect(find.text('Public Pricelist'), findsNothing);
      expect(find.text('30 Days'), findsOneWidget);
      expect(find.text('Immediate Payment'), findsNothing);
    });

    lockedTest('saving does not send the customer, pricelist or expiration', (
      tester,
    ) async {
      await tester.runAsync(startServer);
      addTearDown(() => tester.runAsync(() => server.close(force: true)));
      await openEdit(tester, 'sale', 43);

      await tester.enterText(
        find.byType(TextFormField).first,
        'Deliver on Friday',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Update Quote'));
      await untilWritten(tester);

      final writes = asked
          .where((p) => p['model'] == 'sale.order' && p['method'] == 'write')
          .toList();
      expect(writes, isNotEmpty, reason: 'it saved');
      final values = writes.first['args'][1] as Map;
      expect(values['note'], 'Deliver on Friday');
      expect(values.containsKey('partner_id'), isFalse);
      expect(values.containsKey('pricelist_id'), isFalse);
      expect(values.containsKey('validity_date'), isFalse);
    });
  });

  group('a cancelled order', () {
    lockedTest('customer and pricelist are read-only too', (tester) async {
      await tester.runAsync(startServer);
      addTearDown(() => tester.runAsync(() => server.close(force: true)));
      await openEdit(tester, 'cancel', 44);

      expect(customerField(tester).enabled, isFalse);
      expect(pricelistField(tester).enabled, isFalse);
      expect(
        find.byType(CustomDateSelector),
        findsOneWidget,
        reason: 'shown, as Odoo shows it, but not editable',
      );
    });
  });

  group('a draft quotation stays fully editable', () {
    lockedTest('customer, pricelist and validity can be changed', (
      tester,
    ) async {
      await tester.runAsync(startServer);
      addTearDown(() => tester.runAsync(() => server.close(force: true)));
      await openEdit(tester, 'draft', 45);

      expect(customerField(tester).enabled, isTrue);
      expect(pricelistField(tester).enabled, isTrue);
      expect(pricelistField(tester).value, '5', reason: 'its own pricelist');
      expect(find.byType(CustomDateSelector), findsOneWidget);
    });

    lockedTest('saving sends them', (tester) async {
      await tester.runAsync(startServer);
      addTearDown(() => tester.runAsync(() => server.close(force: true)));
      await openEdit(tester, 'draft', 46);

      await tester.enterText(find.byType(TextFormField).first, 'Hello');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Update Quote'));
      await untilWritten(tester);

      final values =
          asked.firstWhere(
                (p) => p['model'] == 'sale.order' && p['method'] == 'write',
              )['args'][1]
              as Map;
      expect(values['partner_id'], 7);
      expect(
        values['pricelist_id'],
        5,
        reason: 'the order\'s own pricelist is kept, not the customer\'s',
      );
      expect(values['payment_term_id'], 3);
      expect(values.containsKey('validity_date'), isTrue);
    });
  });
}
