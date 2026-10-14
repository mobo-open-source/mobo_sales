import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mobo_sales/widgets/list_search_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/providers/quotation_provider.dart';
import 'package:mobo_sales/screens/quotations/quotation_list_screen.dart';
import 'package:mobo_sales/shared/widgets/mobo/mobo_dialog_buttons.dart';
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

  testWidgets('the filter sheet ends in the Mobo Clear All / Apply buttons', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    when(
      () => mockQuotationProvider.fetchGroupByOptions(),
    ).thenAnswer((_) async => {});
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();

    await tester.tap(
      find
          .descendant(
            of: find.byType(ListSearchBar),
            matching: find.byType(SvgPicture),
          )
          .last,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final buttons = tester.widget<MoboDialogButtons>(
      find.byType(MoboDialogButtons),
    );
    expect(buttons.secondaryLabel, 'Clear All');
    expect(buttons.primaryLabel, 'Apply');
    // Equal-width, 48-high pair: the old Clear All (grey, 8-radius) and Apply
    // (flex 2) are gone.
    expect(find.widgetWithText(OutlinedButton, 'Clear All'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Apply'), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(ElevatedButton, 'Apply')).height,
      MoboDialogButtons.height,
    );
  });
}
