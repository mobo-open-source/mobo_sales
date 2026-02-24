import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/screens/products/product_list_screen.dart';
import 'package:mobo_sales/providers/product_provider.dart';
import 'package:mobo_sales/providers/currency_provider.dart';
import 'package:mobo_sales/providers/contact_provider.dart';
import 'package:mobo_sales/providers/company_provider.dart';
import 'package:mobo_sales/services/connectivity_service.dart';
import 'package:mobo_sales/services/session_service.dart';
import 'package:mobo_sales/models/product.dart';
import 'package:intl/intl.dart';

class MockProductProvider extends Mock implements ProductProvider {}

class MockCurrencyProvider extends Mock implements CurrencyProvider {}

class MockContactProvider extends Mock implements ContactProvider {}

class MockCompanyProvider extends Mock implements CompanyProvider {}

class MockConnectivityService extends Mock implements ConnectivityService {}

class MockSessionService extends Mock implements SessionService {}

void main() {
  late MockProductProvider mockProductProvider;
  late MockCurrencyProvider mockCurrencyProvider;
  late MockContactProvider mockContactProvider;
  late MockCompanyProvider mockCompanyProvider;
  late MockConnectivityService mockConnectivityService;
  late MockSessionService mockSessionService;

  setUp(() {
    mockProductProvider = MockProductProvider();
    mockCurrencyProvider = MockCurrencyProvider();
    mockContactProvider = MockContactProvider();
    mockCompanyProvider = MockCompanyProvider();
    mockConnectivityService = MockConnectivityService();
    mockSessionService = MockSessionService();

    when(() => mockProductProvider.isLoading).thenReturn(false);
    when(() => mockProductProvider.products).thenReturn([]);
    when(() => mockProductProvider.totalProducts).thenReturn(0);
    when(() => mockProductProvider.hasMoreData).thenReturn(false);
    when(() => mockProductProvider.currentPage).thenReturn(0);
    when(() => mockProductProvider.canGoToNextPage).thenReturn(false);
    when(() => mockProductProvider.canGoToPreviousPage).thenReturn(false);
    when(() => mockProductProvider.getPaginationText()).thenReturn('0 items');
    when(() => mockProductProvider.groupByOptions).thenReturn({});
    when(() => mockProductProvider.selectedGroupBy).thenReturn(null);
    when(() => mockProductProvider.isGrouped).thenReturn(false);
    when(() => mockProductProvider.hasInitiallyLoaded).thenReturn(true);
    when(() => mockProductProvider.isServerUnreachable).thenReturn(false);
    when(() => mockProductProvider.error).thenReturn(null);
    when(() => mockProductProvider.categories).thenReturn(['All Products']);

    when(
      () => mockProductProvider.fetchGroupByOptions(),
    ).thenAnswer((_) async => <String, String>{});
    when(
      () => mockProductProvider.fetchProducts(
        searchQuery: any(named: 'searchQuery'),
        category: any(named: 'category'),
        filters: any(named: 'filters'),
      ),
    ).thenAnswer((_) async {});
    when(() => mockProductProvider.fetchCategories()).thenAnswer((_) async {});

    when(() => mockCurrencyProvider.currency).thenReturn('USD');
    when(
      () => mockCurrencyProvider.currencyFormat,
    ).thenReturn(NumberFormat.currency(symbol: '\$'));
    when(
      () => mockCurrencyProvider.formatAmount(
        any(),
        currency: any(named: 'currency'),
      ),
    ).thenReturn('\$0.00');

    when(() => mockContactProvider.contacts).thenReturn([]);
    when(() => mockContactProvider.isServerUnreachable).thenReturn(false);

    when(() => mockConnectivityService.isConnected).thenReturn(true);
    when(() => mockConnectivityService.isInitialized).thenReturn(true);
    when(() => mockCompanyProvider.isLoading).thenReturn(false);
    when(() => mockCompanyProvider.selectedCompanyId).thenReturn(1);
    when(
      () => mockCompanyProvider.selectedCompany,
    ).thenReturn({'id': 1, 'name': 'Test Company'});
    when(() => mockSessionService.hasValidSession).thenReturn(true);
    when(() => mockSessionService.isInitialized).thenReturn(true);
  });

  Widget createWidgetUnderTest() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ProductProvider>.value(
          value: mockProductProvider,
        ),
        ChangeNotifierProvider<CurrencyProvider>.value(
          value: mockCurrencyProvider,
        ),
        ChangeNotifierProvider<ContactProvider>.value(
          value: mockContactProvider,
        ),
        ChangeNotifierProvider<CompanyProvider>.value(
          value: mockCompanyProvider,
        ),
        ChangeNotifierProvider<ConnectivityService>.value(
          value: mockConnectivityService,
        ),
        ChangeNotifierProvider<SessionService>.value(value: mockSessionService),
      ],
      child: const MaterialApp(home: ProductListScreen()),
    );
  }

  testWidgets('should show empty state when no products found', (
    WidgetTester tester,
  ) async {
    when(() => mockProductProvider.products).thenReturn([]);
    when(() => mockProductProvider.totalProducts).thenReturn(0);

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('No products yet'), findsOneWidget);
  });

  testWidgets('should show product list when products are available', (
    WidgetTester tester,
  ) async {
    final List<Product> products = [
      Product(
        id: '1',
        name: 'Product 1',
        listPrice: 10.0,
        qtyAvailable: 5,
        variantCount: 0,
        defaultCode: '',
      ),
      Product(
        id: '2',
        name: 'Product 2',
        listPrice: 20.0,
        qtyAvailable: 0,
        variantCount: 0,
        defaultCode: '',
      ),
    ];
    when(() => mockProductProvider.products).thenReturn(products);
    when(() => mockProductProvider.totalProducts).thenReturn(2);

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Product 1'), findsOneWidget);
    expect(find.text('Product 2'), findsOneWidget);
  });
}
