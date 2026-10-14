import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobo_sales/providers/stock_check_provider.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
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

    group('a product changed somewhere', () {
      late DataChangeBus bus;
      late StockCheckProvider listening;
      late List<Map<String, dynamic>> server;

      setUp(() {
        bus = DataChangeBus.forTesting();
        listening = StockCheckProvider(
          stockService: mockStockService,
          connectivityService: mockConnectivityService,
          sessionService: mockSessionService,
          bus: bus,
        );
        server = [
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
        ).thenAnswer((_) async => List<Map<String, dynamic>>.of(server));
        when(
          () => mockStockService.getStockCount(
            domain: any(named: 'domain'),
            companyId: any(named: 'companyId'),
          ),
        ).thenAnswer((_) async => server.length);
      });

      tearDown(() => listening.dispose());

      Future<void> settle() =>
          Future<void>.delayed(const Duration(milliseconds: 600));

      test('shows its new name in the stock list, with no loading state in '
          'between', () async {
        await listening.fetchInitialStock();
        expect(listening.stockList.first['name'], 'Product A');

        var everLoading = false;
        var everEmpty = false;
        listening.addListener(() {
          if (listening.isLoading) everLoading = true;
          if (listening.stockList.isEmpty) everEmpty = true;
        });

        server[0] = {'id': 1, 'name': 'Product A renamed'};
        bus.productChanged(1);
        await settle();

        expect(listening.stockList.first['name'], 'Product A renamed');
        expect(everLoading, isFalse);
        expect(
          everEmpty,
          isFalse,
          reason: 'the rows stayed until the new came',
        );
      });

      test('drops an archived product, and the count follows', () async {
        await listening.fetchInitialStock();
        server.removeAt(1);
        bus.productChanged(2, kind: DataChangeKind.deleted);
        await settle();

        expect(listening.stockList.map((p) => p['id']), [1]);
        expect(listening.totalProducts, 1);
      });

      test('forgets the copy kept for reopening the screen', () async {
        await listening.fetchInitialStock();
        server[0] = {'id': 1, 'name': 'Renamed'};
        bus.productChanged(1);
        await settle();

        // Reopening the screen within 30 seconds reads the server, not the old
        // copy.
        await listening.fetchInitialStock();
        expect(listening.stockList.first['name'], 'Renamed');
      });

      test('before anything was loaded there is nothing to reload', () async {
        clearInteractions(mockStockService);
        bus.productChanged(1);
        await settle();
        verifyNever(
          () => mockStockService.fetchStockTemplates(
            domain: any(named: 'domain'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            companyId: any(named: 'companyId'),
          ),
        );
      });
    });
  });
}
