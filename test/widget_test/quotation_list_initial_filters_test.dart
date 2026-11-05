import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/models/quote.dart';
import 'package:mobo_sales/providers/currency_provider.dart';
import 'package:mobo_sales/providers/quotation_provider.dart';
import 'package:mobo_sales/screens/quotations/quotation_list_screen.dart';
import 'package:mobo_sales/services/connectivity_service.dart';
import 'package:mobo_sales/services/session_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockQuotationProvider extends Mock implements QuotationProvider {}

class _MockCurrencyProvider extends Mock implements CurrencyProvider {}

class _MockConnectivityService extends Mock implements ConnectivityService {}

class _MockSessionService extends Mock implements SessionService {}

/// The dashboard's "Review expired quotations" card opens this screen with the
/// `expired` filter. When the quotations tab had already loaded the list, the
/// screen kept it and only hid, on the client, the rows of that first page that
/// were not expired: the dashboard counted every expired quotation, the list
/// showed the few that happened to sit on page one (none, often).
void main() {
  late _MockQuotationProvider provider;

  Quote quote(int id) => Quote(
    id: id,
    name: 'S0000$id',
    lines: const [],
    subtotal: 0,
    taxAmount: 0,
    total: 0,
    status: 'draft',
  );

  setUp(() {
    provider = _MockQuotationProvider();
    when(() => provider.isLoading).thenReturn(false);
    when(() => provider.isLoadingMore).thenReturn(false);
    when(() => provider.hasMoreData).thenReturn(false);
    when(() => provider.searchController).thenReturn(TextEditingController());
    when(() => provider.scrollController).thenReturn(ScrollController());
    when(() => provider.activeFilters).thenReturn({});
    when(() => provider.supportsDeliveryFilters).thenReturn(true);
    when(() => provider.isGrouped).thenReturn(false);
    when(() => provider.filteredQuotations).thenReturn([]);
    // The list another screen already loaded, unfiltered.
    when(() => provider.allQuotations).thenReturn([quote(1), quote(2)]);
    when(() => provider.totalQuotations).thenReturn(115);
    when(() => provider.errorMessage).thenReturn(null);
    when(() => provider.accessErrorMessage).thenReturn(null);
    when(() => provider.isOffline).thenReturn(false);
    when(() => provider.groupByOptions).thenReturn({});
    when(() => provider.startDate).thenReturn(null);
    when(() => provider.endDate).thenReturn(null);
    when(() => provider.hasInitiallyLoaded).thenReturn(true);
    when(() => provider.getPaginationText()).thenReturn('1-2/115');
    when(() => provider.isServerUnreachable).thenReturn(false);
    when(() => provider.canGoToPreviousPage).thenReturn(false);
    when(() => provider.canGoToNextPage).thenReturn(false);
    when(() => provider.currentPage).thenReturn(0);
    when(() => provider.totalPages).thenReturn(1);
    when(() => provider.currentStartIndex).thenReturn(1);
    when(() => provider.currentEndIndex).thenReturn(2);
    when(() => provider.pageSize).thenReturn(40);
    when(
      () => provider.loadQuotations(
        isLoadMore: any(named: 'isLoadMore'),
        filters: any(named: 'filters'),
        groupBy: any(named: 'groupBy'),
        clearGroupBy: any(named: 'clearGroupBy'),
      ),
    ).thenAnswer((_) async {});
  });

  Widget app(Widget screen) {
    final currency = _MockCurrencyProvider();
    when(() => currency.currency).thenReturn('USD');
    when(
      () => currency.formatAmount(any(), currency: any(named: 'currency')),
    ).thenReturn('\$ 0.00');
    final connectivity = _MockConnectivityService();
    when(() => connectivity.isConnected).thenReturn(true);
    final session = _MockSessionService();
    when(() => session.hasValidSession).thenReturn(true);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<QuotationProvider>.value(value: provider),
        ChangeNotifierProvider<CurrencyProvider>.value(value: currency),
        ChangeNotifierProvider<ConnectivityService>.value(value: connectivity),
        ChangeNotifierProvider<SessionService>.value(value: session),
      ],
      child: MaterialApp(home: screen),
    );
  }

  Future<void> open(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(screen));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'opened with the expired filter, the list is read again with it',
    (tester) async {
      await open(
        tester,
        const QuotationListScreen(initialFilters: {'expired'}),
      );

      final captured = verify(
        () => provider.loadQuotations(
          isLoadMore: any(named: 'isLoadMore'),
          filters: captureAny(named: 'filters'),
          groupBy: any(named: 'groupBy'),
          clearGroupBy: any(named: 'clearGroupBy'),
        ),
      ).captured;
      expect(captured, isNotEmpty);
      expect(captured.first, {'expired'});
    },
  );

  testWidgets(
    'opened with no filters, a list that is already loaded is kept as it is',
    (tester) async {
      await open(tester, const QuotationListScreen());

      verifyNever(
        () => provider.loadQuotations(
          isLoadMore: any(named: 'isLoadMore'),
          filters: any(named: 'filters'),
          groupBy: any(named: 'groupBy'),
          clearGroupBy: any(named: 'clearGroupBy'),
        ),
      );
    },
  );
}
