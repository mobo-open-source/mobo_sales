import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobo_sales/providers/product_provider.dart';
import '../mocks/mock_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProductProvider provider;
  late MockProductService mockProductService;
  late MockConnectivityService mockConnectivityService;
  late MockSessionService mockSessionService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockProductService = MockProductService();
    mockConnectivityService = MockConnectivityService();
    mockSessionService = MockSessionService();

    provider = ProductProvider(
      productService: mockProductService,
      connectivityService: mockConnectivityService,
      sessionService: mockSessionService,
    );

    when(() => mockConnectivityService.isConnected).thenReturn(true);
    when(() => mockSessionService.hasValidSession).thenReturn(true);
  });

  group('ProductProvider Tests', () {
    test('Initial state should be empty', () {
      expect(provider.products, isEmpty);
      expect(provider.isLoading, false);
      expect(provider.error, isNull);
    });

    test('fetchProducts success', () async {
      final mockProductData = [
        {
          'id': '1',
          'name': 'Product 1',
          'list_price': 100.0,
          'qty_available': 10,
          'product_variant_count': 1,
          'default_code': 'P001',
        },
      ];

      when(
        () => mockProductService.getProductCount(any()),
      ).thenAnswer((_) async => 1);
      when(
        () => mockProductService.fetchProducts(
          domain: any(named: 'domain'),
          fields: any(named: 'fields'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => mockProductData);

      await provider.fetchProducts();

      expect(provider.products.length, 1);
      expect(provider.products[0].name, 'Product 1');
      expect(provider.isLoading, false);
      expect(provider.error, isNull);
    });

    test('fetchProducts failure', () async {
      when(
        () => mockProductService.getProductCount(any()),
      ).thenThrow(Exception('Fetch error'));

      await provider.fetchProducts();

      expect(provider.products, isEmpty);
      expect(provider.error, contains('Fetch error'));
      expect(provider.isLoading, false);
    });

    test('fetchProducts no connection', () async {
      when(() => mockConnectivityService.isConnected).thenReturn(false);

      await provider.fetchProducts();

      expect(provider.error, contains('No internet connection'));
      expect(provider.isLoading, false);
    });

    test('fetchCategories success', () async {
      final mockCategories = [
        {'value': '1', 'label': 'Category 1'},
        {'value': '2', 'label': 'Category 2'},
      ];

      when(
        () => mockProductService.fetchCategoryOptions(),
      ).thenAnswer((_) async => mockCategories);

      await provider.fetchCategories();

      expect(provider.categories.contains('Category 1'), true);
      expect(provider.categories.contains('Category 2'), true);
      expect(provider.categories.contains('All Products'), true);
    });

    test('clearFilters should reset all filters', () {
      provider.setFilterState(
        showInStockOnly: true,
        showServicesOnly: true,
        showConsumablesOnly: true,
        showStorableOnly: true,
        showAvailableOnly: true,
        priceMin: 10.0,
      );

      expect(provider.showInStockOnly, true);
      expect(provider.showServicesOnly, true);
      expect(provider.showConsumablesOnly, true);
      expect(provider.showStorableOnly, true);
      expect(provider.showAvailableOnly, true);
      expect(provider.priceMin, 10.0);

      provider.clearFilters();

      expect(provider.showInStockOnly, false);
      expect(provider.showServicesOnly, false);
      expect(provider.showConsumablesOnly, false);
      expect(provider.showStorableOnly, false);
      expect(provider.showAvailableOnly, false);
      expect(provider.priceMin, isNull);
    });

    test('setFilterState should update new flags', () {
      provider.setFilterState(showServicesOnly: true);
      expect(provider.showServicesOnly, true);

      provider.setFilterState(showServicesOnly: false, showStorableOnly: true);
      expect(provider.showServicesOnly, false);
      expect(provider.showStorableOnly, true);
    });
  });
}
