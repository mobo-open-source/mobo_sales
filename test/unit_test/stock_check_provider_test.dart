import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobo_sales/providers/stock_check_provider.dart';
import '../mocks/mock_services.dart';

void main() {
  late StockCheckProvider provider;
  late MockStockService mockStockService;
  late MockConnectivityService mockConnectivityService;
  late MockSessionService mockSessionService;

  setUpAll(() {
    registerFallbackValue(Uri.parse('http://localhost'));
  });

  setUp(() {
    mockStockService = MockStockService();
    mockConnectivityService = MockConnectivityService();
    mockSessionService = MockSessionService();

    provider = StockCheckProvider(
      stockService: mockStockService,
      connectivityService: mockConnectivityService,
      sessionService: mockSessionService,
    );

    when(() => mockConnectivityService.isConnected).thenReturn(true);
    when(() => mockSessionService.hasValidSession).thenReturn(true);
  });

  group('StockCheckProvider Tests', () {
    test('initial state', () {
      expect(provider.stockList, isEmpty);
      expect(provider.isLoading, false);
      expect(provider.error, isNull);
    });

    test('fetchInitialStock success', () async {
      final mockStocks = [
        {'id': 1, 'name': 'Product A'},
        {'id': 2, 'name': 'Product B'},
      ];

      when(() => mockStockService.getCompanyId()).thenAnswer((_) async => 1);
      when(
        () => mockStockService.fetchStockTemplates(
          domain: any(named: 'domain'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
          companyId: any(named: 'companyId'),
        ),
      ).thenAnswer((_) async => mockStocks);
      when(
        () => mockStockService.getStockCount(
          domain: any(named: 'domain'),
          companyId: any(named: 'companyId'),
        ),
      ).thenAnswer((_) async => 2);

      await provider.fetchInitialStock();

      expect(provider.stockList, equals(mockStocks));
      expect(provider.isLoading, false);
      expect(provider.error, isNull);
      verify(
        () => mockStockService.fetchStockTemplates(
          domain: any(named: 'domain'),
          limit: any(named: 'limit'),
          offset: 0,
          companyId: 1,
        ),
      ).called(1);
    });

    test('fetchInitialStock no connection', () async {
      when(() => mockConnectivityService.isConnected).thenReturn(false);

      await provider.fetchInitialStock();

      expect(provider.stockList, isEmpty);
      expect(provider.error, contains('No internet connection'));
      expect(provider.isLoading, false);
    });

    test('fetchInitialStock invalid session', () async {
      when(() => mockSessionService.hasValidSession).thenReturn(false);

      await provider.fetchInitialStock();

      expect(provider.stockList, isEmpty);
      expect(provider.error, contains('No active Odoo session'));
      expect(provider.isLoading, false);
    });

    test('fetchNextPage success', () async {
      final initialStocks = [
        {'id': 1, 'name': 'A'},
      ];
      final nextStocks = [
        {'id': 2, 'name': 'B'},
      ];

      when(() => mockStockService.getCompanyId()).thenAnswer((_) async => 1);
      when(
        () => mockStockService.fetchStockTemplates(
          domain: any(named: 'domain'),
          limit: any(named: 'limit'),
          offset: 0,
          companyId: 1,
        ),
      ).thenAnswer((_) async => initialStocks);
      when(
        () => mockStockService.getStockCount(
          domain: any(named: 'domain'),
          companyId: 1,
        ),
      ).thenAnswer((_) async => 2);

      await provider.fetchInitialStock();

      when(
        () => mockStockService.fetchStockTemplates(
          domain: any(named: 'domain'),
          limit: any(named: 'limit'),
          offset: 20,
          companyId: 1,
        ),
      ).thenAnswer((_) async => nextStocks);

      await provider.fetchNextPage();

      expect(provider.stockList.length, 2);
      expect(provider.currentPage, 1);
    });

    test('fetchInventoryDetails success', () async {
      final mockLocations = [
        {'complete_name': 'Loc A', 'usage': 'internal'},
      ];
      final mockQuants = [
        {
          'location_id': [1, 'Loc A'],
          'quantity': 10.0,
          'reserved_quantity': 2.0,
        },
      ];
      final mockProductInfo = {
        'qty_available': 10.0,
        'virtual_available': 15.0,
      };

      when(
        () =>
            mockStockService.fetchLocations(companyId: any(named: 'companyId')),
      ).thenAnswer((_) async => mockLocations);
      when(
        () => mockStockService.fetchStockQuants(
          any(),
          companyId: any(named: 'companyId'),
        ),
      ).thenAnswer((_) async => mockQuants);
      when(
        () => mockStockService.fetchProductStockInfo(
          any(),
          companyId: any(named: 'companyId'),
        ),
      ).thenAnswer((_) async => mockProductInfo);
      when(
        () => mockStockService.fetchStockMoves(
          productId: any(named: 'productId'),
          domain: any(named: 'domain'),
          companyId: any(named: 'companyId'),
        ),
      ).thenAnswer((_) async => []);

      final details = await provider.fetchInventoryDetails(1);

      expect(details['totalInStock'], 10.0);
      expect(details['totalAvailable'], 8.0);
      expect(details['totalReserved'], 2.0);
    });
  });
}
