import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:mobo_sales/providers/currency_provider.dart';
import 'package:mobo_sales/providers/quotation_provider.dart';
import 'package:mobo_sales/screens/quotations/quotation_list_screen.dart';
import 'package:mobo_sales/services/connectivity_service.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/services/session_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_sale_order_odoo.dart';
import '../mocks/mock_services.dart';

class _MockCurrency extends Mock implements CurrencyProvider {}

/// Searching for a quotation and clearing the search must read the list once
/// for the clear, not twice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (call) async => ['wifi'],
        );
  });

  late FakeSaleOrderOdoo odoo;
  late QuotationProvider provider;
  late ConnectivityService connectivity;
  late SessionService session;
  late _MockCurrency currency;

  setUp(() async {
    odoo = FakeSaleOrderOdoo();
    await odoo.start();
    SharedPreferences.setMockInitialValues({
      'isLoggedIn': true,
      'sessionId': 'sess123',
      'userLogin': 'admin',
      'password': 'x',
      'database': 'shop',
      'serverUrl': odoo.url,
      'userId': 2,
      'userName': 'Admin',
      'serverVersion': '18.0',
      'expiresAt': DateTime.now()
          .add(const Duration(hours: 5))
          .toIso8601String(),
    });
    OdooSessionManager.clearClientCache();
    connectivity = MockConnectivityService();
    when(() => connectivity.isConnected).thenReturn(true);
    session = MockSessionService();
    when(() => session.hasValidSession).thenReturn(true);
    currency = _MockCurrency();
    when(
      () => currency.formatAmount(any(), currency: any(named: 'currency')),
    ).thenReturn('\$ 0.00');
    when(() => currency.currency).thenReturn('USD');
    provider = QuotationProvider(
      quotationService: MockQuotationService(),
      connectivityService: connectivity,
      bus: DataChangeBus.forTesting(),
    );
  });

  tearDown(() async {
    provider.dispose();
    await odoo.stop();
  });

  Widget app() => MultiProvider(
    providers: [
      ChangeNotifierProvider<QuotationProvider>.value(value: provider),
      ChangeNotifierProvider<CurrencyProvider>.value(value: currency),
      ChangeNotifierProvider<ConnectivityService>.value(value: connectivity),
      ChangeNotifierProvider<SessionService>.value(value: session),
    ],
    child: const MaterialApp(home: QuotationListScreen()),
  );

  /// Lets real HTTP run while the test clock moves too, so the debounce and
  /// the delays inside the provider fire.
  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    for (var elapsed = 0; elapsed < ms; elapsed += 50) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void setUpScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('opening the page reads the list once', (tester) async {
    setUpScreen(tester);
    await tester.pumpWidget(app());
    await settle(tester);

    expect(odoo.searchReads, hasLength(1));
    expect(provider.allQuotations, hasLength(6));
  });

  testWidgets('clearing a quotation-ID search reads the list once', (
    tester,
  ) async {
    setUpScreen(tester);
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'S00003');
    await settle(tester);
    expect(provider.allQuotations.map((q) => q.name), ['S00003']);

    odoo.searchReads.clear();
    await tester.tap(find.byIcon(HugeIcons.strokeRoundedCancel01));
    await settle(tester, 1500);

    expect(
      odoo.searchReads,
      hasLength(1),
      reason: 'one read for the clear, none after it',
    );
    expect(provider.allQuotations, hasLength(6));
    expect(provider.isLoading, isFalse);
  });

  testWidgets('deleting the search text reads the list once', (tester) async {
    setUpScreen(tester);
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'S00003');
    await settle(tester);

    odoo.searchReads.clear();
    await tester.enterText(find.byType(TextField), '');
    await settle(tester, 1500);

    expect(odoo.searchReads, hasLength(1));
    expect(provider.allQuotations, hasLength(6));
  });

  testWidgets('clearing the search keeps the filters that were applied', (
    tester,
  ) async {
    setUpScreen(tester);
    await tester.pumpWidget(app());
    await settle(tester);

    // Applied from somewhere other than this screen's own sheet.
    unawaited(provider.loadQuotations(filters: {'sale'}));
    await settle(tester);
    expect(provider.allQuotations.map((q) => q.id).toList()..sort(), [3, 4, 5]);

    await tester.enterText(find.byType(TextField), 'S00003');
    await settle(tester);
    await tester.tap(find.byIcon(HugeIcons.strokeRoundedCancel01));
    await settle(tester, 1500);

    expect(provider.activeFilters, {'sale'});
    expect(provider.allQuotations.map((q) => q.id).toList()..sort(), [3, 4, 5]);
  });

  testWidgets('clearing a search on a grouped list refreshes its groups once', (
    tester,
  ) async {
    setUpScreen(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    provider.setGroupBy('state');
    await settle(tester);
    expect(provider.groupSummary, isNotEmpty);

    await tester.enterText(find.byType(TextField), 'S00003');
    await settle(tester);
    expect(provider.groupSummary.values.fold<int>(0, (a, b) => a + b), 1);

    odoo.searchReads.clear();
    odoo.readGroups.clear();
    await tester.tap(find.byIcon(HugeIcons.strokeRoundedCancel01));
    await settle(tester, 1500);

    expect(odoo.readGroups, hasLength(1), reason: 'the group counts, once');
    expect(odoo.searchReads, hasLength(1));
    expect(provider.groupSummary.values.fold<int>(0, (a, b) => a + b), 6);
  });

  testWidgets('applying a group-by reads the group counts once', (
    tester,
  ) async {
    setUpScreen(tester);
    await tester.pumpWidget(app());
    await settle(tester);

    odoo.readGroups.clear();
    unawaited(provider.loadQuotations(filters: const {}, groupBy: 'state'));
    await settle(tester);

    expect(odoo.readGroups, hasLength(1));
  });
}
