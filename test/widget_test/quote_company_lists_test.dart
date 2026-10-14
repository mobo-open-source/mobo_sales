import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobo_sales/screens/quotations/create_quote_screen.dart';
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

void main() {
  setUpAll(() => HttpOverrides.global = null);
  late MockCreateInvoiceProvider mockInvoiceProvider;
  late MockCurrencyProvider mockCurrencyProvider;
  late MockContactProvider mockContactProvider;
  late MockConnectivityService mockConnectivityService;
  late MockSessionService mockSessionService;

  setUp(() {
    mockInvoiceProvider = MockCreateInvoiceProvider();
    mockCurrencyProvider = MockCurrencyProvider();
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
        ChangeNotifierProvider<CurrencyProvider>.value(
          value: mockCurrencyProvider,
        ),
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

  /// An Odoo that records what it is asked and answers what the form needs.
  late HttpServer server;
  final asked = <Map<String, dynamic>>[];
  int orderCompany = 3;

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
          result = [
            {
              'id': 9,
              'company_id': [orderCompany, 'Company $orderCompany'],
              'order_line': [],
            },
          ];
        } else if (model == 'product.pricelist') {
          result = [
            {
              'id': 1,
              'name': 'Public Pricelist',
              'currency_id': [1, 'USD'],
            },
          ];
        } else if (model == 'account.payment.term') {
          result = [
            {'id': 1, 'name': 'Immediate Payment'},
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

  Future<void> signInTo({required int company, int user = 2}) async {
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
      'selected_company_id': company,
      'selected_allowed_company_ids': ['1', '2', '3', '4'],
      'expiresAt': DateTime.now()
          .add(const Duration(hours: 5))
          .toIso8601String(),
    });
    OdooSessionManager.clearClientCache();
  }

  Future<void> openQuote(
    WidgetTester tester, {
    Map<String, dynamic>? edit,
  }) async {
    // A fresh screen each time, not the previous one carried over.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      withProviders(CreateQuoteScreen(quotationToEdit: edit)),
    );
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Map<String, dynamic> request(String model) => asked.lastWhere(
    (p) => p['model'] == model && p['method'] == 'search_read',
  );

  setUp(() async {
    asked.clear();
    orderCompany = 3;
  });

  List<dynamic> domainFor(int company) => [
    '|',
    ['company_id', '=', false],
    ['company_id', '=', company],
  ];

  testWidgets('a new quotation lists only the selected company\'s pricelists '
      'and payment terms (and those with no company)', (tester) async {
    await tester.runAsync(startServer);
    addTearDown(() => tester.runAsync(() => server.close(force: true)));
    await signInTo(company: 2, user: 21);

    await openQuote(tester);

    final pricelists = request('product.pricelist');
    expect(pricelists['args'], [domainFor(2)]);
    expect(pricelists['kwargs']['context'], {
      'allowed_company_ids': [2],
      'company_id': 2,
    });
    final terms = request('account.payment.term');
    expect(terms['args'], [domainFor(2)]);
    expect(terms['kwargs']['context']['company_id'], 2);
  });

  testWidgets('an edited quotation keeps the company it was made in', (
    tester,
  ) async {
    await tester.runAsync(startServer);
    addTearDown(() => tester.runAsync(() => server.close(force: true)));
    await signInTo(company: 2, user: 22);
    orderCompany = 3;

    await openQuote(tester, edit: {'id': 9, 'name': 'S00009'});

    expect(request('product.pricelist')['args'], [domainFor(3)]);
    expect(request('account.payment.term')['args'], [domainFor(3)]);
    expect(
      request('product.pricelist')['kwargs']['context']['company_id'],
      3,
      reason: 'the order\'s company, not the one selected in the app',
    );
  });

  testWidgets('another company asks again: a cached list is never reused', (
    tester,
  ) async {
    await tester.runAsync(startServer);
    addTearDown(() => tester.runAsync(() => server.close(force: true)));

    await signInTo(company: 2, user: 23);
    await openQuote(tester);
    expect(request('product.pricelist')['args'], [domainFor(2)]);

    asked.clear();
    await signInTo(company: 4, user: 23);
    await openQuote(tester);
    expect(
      request('product.pricelist')['args'],
      [domainFor(4)],
      reason: 'company 2\'s cached list must not be shown for company 4',
    );
  });
}
