import 'package:flutter/material.dart';
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
  setUpAll(() => SharedPreferences.setMockInitialValues({}));
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

  Widget createWidgetUnderTest() => withProviders(
    CreateInvoiceScreen(invoiceToEdit: {'id': 5, 'name': 'INV/2026/0005'}),
  );

  testWidgets('invoice edit: a skeleton from the first frame, then the form', (
    tester,
  ) async {
    await tester.pumpWidget(createWidgetUnderTest());

    // Before anything has loaded: the skeleton, not an empty form.
    expect(find.byType(Shimmer), findsWidgets);
    expect(find.text('Invoice Details'), findsNothing);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Shimmer), findsNothing, reason: 'skeleton is gone');
    expect(find.text('Invoice Details'), findsOneWidget);
  });

  testWidgets('quote edit: a skeleton from the first frame, never stuck', (
    tester,
  ) async {
    await tester.pumpWidget(
      withProviders(
        CreateQuoteScreen(quotationToEdit: {'id': 9, 'name': 'S00009'}),
      ),
    );

    expect(find.byType(Shimmer), findsWidgets, reason: 'first frame');
    expect(find.text('Customer Information'), findsNothing);

    // There is no server here, so every load fails; the form must still open.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.byType(Shimmer), findsNothing, reason: 'skeleton is gone');
    expect(find.text('Customer Information'), findsOneWidget);
  });

  testWidgets('quote create without a customer opens the form at once', (
    tester,
  ) async {
    await tester.pumpWidget(withProviders(const CreateQuoteScreen()));
    await tester.pump();
    expect(find.text('Customer Information'), findsOneWidget);
  });
}
