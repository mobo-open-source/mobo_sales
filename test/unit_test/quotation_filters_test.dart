import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/providers/quotation_provider.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_sale_order_odoo.dart';
import '../mocks/mock_services.dart';

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

  Future<void> boot({bool withDeliveryStatus = true}) async {
    odoo = FakeSaleOrderOdoo(withDeliveryStatus: withDeliveryStatus);
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
    final connectivity = MockConnectivityService();
    when(() => connectivity.isConnected).thenReturn(true);
    provider = QuotationProvider(
      quotationService: MockQuotationService(),
      connectivityService: connectivity,
      bus: DataChangeBus.forTesting(),
    );
  }

  tearDown(() async {
    provider.dispose();
    await odoo.stop();
  });

  Future<List<int>> shownWith(
    Set<String> filters, {
    DateTime? start,
    DateTime? end,
  }) async {
    provider.setDateRange(start, end);
    await provider.loadQuotations(filters: filters);
    return provider.allQuotations.map((q) => q.id!).toList()..sort();
  }

  group('each filter shows what Odoo means by it', () {
    setUp(() => boot());

    test('no filter shows every order', () async {
      expect(await shownWith({}), [1, 2, 3, 4, 5, 6]);
    });

    test('Quotations: draft and sent', () async {
      expect(await shownWith({'quotation'}), [1, 2]);
    });

    test('Sale Orders: confirmed and locked ones', () async {
      expect(await shownWith({'sale'}), [3, 4, 5]);
    });

    test('My Quotations: the signed-in user only', () async {
      expect(await shownWith({'user_quotations'}), [1, 3, 5, 6]);
    });

    test('Invoiced', () async {
      expect(await shownWith({'invoiced'}), [4, 5]);
    });

    test('To Invoice', () async {
      expect(await shownWith({'to_invoice'}), [3]);
    });

    test('Delivered', () async {
      expect(await shownWith({'delivered'}), [4, 5]);
    });

    test('To Deliver', () async {
      expect(await shownWith({'to_deliver'}), [3]);
    });

    test('Expired Quotes: still a quotation, past its validity', () async {
      expect(await shownWith({'expired'}), [1]);
    });
  });

  group('filters together', () {
    setUp(() => boot());

    test('Sale Orders and Invoiced narrow each other', () async {
      expect(await shownWith({'sale', 'invoiced'}), [4, 5]);
    });

    test('Sale Orders, Invoiced and Delivered', () async {
      expect(await shownWith({'sale', 'invoiced', 'delivered'}), [4, 5]);
    });

    test('My Quotations with Sale Orders', () async {
      expect(await shownWith({'user_quotations', 'sale'}), [3, 5]);
    });

    test('Sale Orders, To Invoice and To Deliver', () async {
      expect(await shownWith({'sale', 'to_invoice', 'to_deliver'}), [3]);
    });

    test('a filter with a date range', () async {
      final ids = await shownWith(
        {'sale'},
        start: DateTime(2026, 10, 5),
        end: DateTime(2026, 10, 31),
      );
      expect(ids, [3, 5]);
    });

    test('a date range alone is not served from the unfiltered list', () async {
      expect(await shownWith({}), [1, 2, 3, 4, 5, 6]);
      expect(
        await shownWith(
          {},
          start: DateTime(2026, 10, 5),
          end: DateTime(2026, 10, 31),
        ),
        [3, 5],
      );
    });

    test('clearing the filters brings every order back', () async {
      expect(await shownWith({'sale', 'invoiced'}), [4, 5]);
      expect(await shownWith({}), [1, 2, 3, 4, 5, 6]);
    });
  });

  group('a database without delivery tracking', () {
    setUp(() => boot(withDeliveryStatus: false));

    test('its delivery filters match nothing instead of everything', () async {
      expect(await shownWith({}), [1, 2, 3, 4, 5, 6]);
      expect(provider.supportsDeliveryFilters, isFalse);
      expect(await shownWith({'delivered'}), isEmpty);
      expect(await shownWith({'to_deliver'}), isEmpty);
    });
  });

  group('applying a filter while another read is running', () {
    setUp(() => boot());

    test('the newer filter wins and the list stops loading', () async {
      await provider.loadQuotations();
      expect(provider.allQuotations, hasLength(6));

      odoo.gate = Completer<void>();
      final slow = provider.loadQuotations(filters: {'quotation'});
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final fast = provider.loadQuotations(filters: {'invoiced'});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      odoo.gate!.complete();
      await Future.wait([slow, fast]);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(provider.activeFilters, {'invoiced'});
      expect(provider.allQuotations.map((q) => q.id).toList()..sort(), [4, 5]);
      expect(provider.isLoading, isFalse);
    });
  });

  group('searching by quotation ID and clearing it', () {
    setUp(() => boot());

    Future<void> settle([int ms = 900]) =>
        Future<void>.delayed(Duration(milliseconds: ms));

    test('the X button reloads the list once', () async {
      await provider.loadQuotations();
      provider.searchController.text = 'S00003';
      await settle();
      expect(provider.allQuotations.map((q) => q.name), ['S00003']);

      odoo.searchReads.clear();
      // What the page's clear button does.
      provider.clearSearch();
      await provider.loadQuotations(filters: provider.activeFilters);
      await settle();

      expect(odoo.searchReads, hasLength(1));
      expect(provider.allQuotations, hasLength(6));
    });

    test('deleting the text reloads the list once', () async {
      await provider.loadQuotations();
      provider.searchController.text = 'S00003';
      await settle();

      odoo.searchReads.clear();
      provider.searchController.clear();
      await settle();

      expect(odoo.searchReads, hasLength(1));
      expect(provider.allQuotations, hasLength(6));
    });
  });
}
