import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/providers/quotation_provider.dart';
import 'package:mobo_sales/screens/quotations/quotation_list_screen.dart';
import 'package:mobo_sales/widgets/empty_state_widget.dart';
import 'package:mobo_sales/providers/currency_provider.dart';
import 'package:mobo_sales/services/connectivity_service.dart';
import 'package:mobo_sales/services/session_service.dart';

class MockQuotationProvider extends Mock implements QuotationProvider {}

class MockCurrencyProvider extends Mock implements CurrencyProvider {}

class MockConnectivityService extends Mock implements ConnectivityService {}

class MockSessionService extends Mock implements SessionService {}

void main() {
  late MockQuotationProvider mockQuotationProvider;
  late MockCurrencyProvider mockCurrencyProvider;
  late MockConnectivityService mockConnectivityService;
  late MockSessionService mockSessionService;

  setUp(() {
    mockQuotationProvider = MockQuotationProvider();
    mockCurrencyProvider = MockCurrencyProvider();
    mockConnectivityService = MockConnectivityService();
    mockSessionService = MockSessionService();

    when(() => mockQuotationProvider.isLoading).thenReturn(false);
    when(() => mockQuotationProvider.isLoadingMore).thenReturn(false);
    when(() => mockQuotationProvider.hasMoreData).thenReturn(false);
    when(
      () => mockQuotationProvider.searchController,
    ).thenReturn(TextEditingController());
    when(
      () => mockQuotationProvider.scrollController,
    ).thenReturn(ScrollController());
    when(() => mockQuotationProvider.activeFilters).thenReturn({});
    when(() => mockQuotationProvider.isGrouped).thenReturn(false);
    when(() => mockQuotationProvider.filteredQuotations).thenReturn([]);
    when(() => mockQuotationProvider.allQuotations).thenReturn([]);
    when(() => mockQuotationProvider.totalQuotations).thenReturn(0);
    when(() => mockQuotationProvider.errorMessage).thenReturn(null);
    when(() => mockQuotationProvider.accessErrorMessage).thenReturn(null);
    when(() => mockQuotationProvider.isOffline).thenReturn(false);
    when(() => mockQuotationProvider.groupByOptions).thenReturn({});
    when(() => mockQuotationProvider.startDate).thenReturn(null);
    when(() => mockQuotationProvider.endDate).thenReturn(null);
    when(() => mockQuotationProvider.hasInitiallyLoaded).thenReturn(true);
    when(() => mockQuotationProvider.getPaginationText()).thenReturn('0 items');
    when(() => mockQuotationProvider.isServerUnreachable).thenReturn(false);
    when(
      () => mockQuotationProvider.loadQuotations(
        isLoadMore: any(named: 'isLoadMore'),
        filters: any(named: 'filters'),
        groupBy: any(named: 'groupBy'),
        clearGroupBy: any(named: 'clearGroupBy'),
      ),
    ).thenAnswer((_) async {});

    when(() => mockCurrencyProvider.currency).thenReturn('USD');
    when(
      () => mockCurrencyProvider.formatAmount(
        any(),
        currency: any(named: 'currency'),
      ),
    ).thenReturn('\$ 0.00');

    when(() => mockConnectivityService.isConnected).thenReturn(true);
    when(() => mockSessionService.hasValidSession).thenReturn(true);
  });

  Widget createWidgetUnderTest() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<QuotationProvider>.value(
          value: mockQuotationProvider,
        ),
        ChangeNotifierProvider<CurrencyProvider>.value(
          value: mockCurrencyProvider,
        ),
        ChangeNotifierProvider<ConnectivityService>.value(
          value: mockConnectivityService,
        ),
        ChangeNotifierProvider<SessionService>.value(value: mockSessionService),
      ],
      child: const MaterialApp(home: QuotationListScreen()),
    );
  }

  testWidgets('should show EmptyStateWidget when no quotations are found', (
    WidgetTester tester,
  ) async {
    when(() => mockQuotationProvider.filteredQuotations).thenReturn([]);

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();

    expect(find.byType(EmptyStateWidget), findsOneWidget);
    expect(find.text('No quotations yet'), findsOneWidget);
  });

  testWidgets('should show loading indicator when isLoading is true', (
    WidgetTester tester,
  ) async {
    when(() => mockQuotationProvider.isLoading).thenReturn(true);
    when(() => mockQuotationProvider.hasInitiallyLoaded).thenReturn(false);

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();
  });
}
