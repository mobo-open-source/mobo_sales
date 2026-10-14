import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/providers/quotation_provider.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks/mock_services.dart';

/// An Odoo holding a few quotations, which the test can change behind the
/// provider's back, as another screen (or another device) would.
class _Odoo {
  final Map<int, Map<String, dynamic>> orders = {
    1: _row(1, 'S00001', 100, 'draft'),
    2: _row(2, 'S00002', 200, 'sent'),
  };
  late HttpServer _http;
  final calls = <String>[];

  static Map<String, dynamic> _row(
    int id,
    String name,
    double total,
    String state,
  ) => {
    'id': id,
    'name': name,
    'partner_id': [7, 'Azure Interior'],
    'date_order': '2026-10-01 10:00:00',
    'state': state,
    'amount_total': total,
    'amount_untaxed': total,
    'amount_tax': 0.0,
    'currency_id': [1, 'USD'],
    'order_line': <int>[],
    'invoice_status': 'no',
    'delivery_status': 'pending',
  };

  void put(int id, String name, double total, String state) =>
      orders[id] = _row(id, name, total, state);

  /// The orders a domain keeps. Only the `state` leaves are honoured, which
  /// is what the list's filters use here.
  List<Map<String, dynamic>> _matching(List domain) {
    final states = <List>[
      for (final leaf in domain)
        if (leaf is List && leaf.length == 3 && leaf[0] == 'state')
          leaf[2] is List ? leaf[2] as List : [leaf[2]],
    ];
    return [
      for (final order in orders.values)
        if (states.every((allowed) => allowed.contains(order['state']))) order,
    ];
  }

  String get url => 'http://127.0.0.1:${_http.port}';

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      _http.forEach((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final params = (body['params'] as Map?) ?? {};
        final model = params['model'];
        final method = params['method'];
        calls.add('$model.$method');
        dynamic result = [];
        if (method == 'check_access_rights' || method == 'has_access') {
          result = true;
        } else if (model == 'sale.order') {
          switch (method) {
            case 'search_count':
              result = _matching(params['args'][0] as List).length;
            case 'search_read':
              result = _matching(params['args'][0] as List);
            case 'read':
              final ids = (params['args'][0] as List).cast<int>();
              result = [
                for (final id in ids)
                  if (orders[id] != null) orders[id],
              ];
            case 'action_cancel':
              final id = (params['args'][0] as List).first as int;
              orders[id]!['state'] = 'cancel';
              result = true;
          }
        }
        request.response
          ..persistentConnection = false
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
          );
        await request.response.close();
      }),
    );
  }

  Future<void> stop() => _http.close(force: true);
}

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

  late _Odoo odoo;
  late DataChangeBus bus;
  late QuotationProvider provider;

  /// The bus waits 350 ms for a burst to end before it tells a listener.
  Future<void> settle([int ms = 650]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  setUp(() async {
    odoo = _Odoo();
    await odoo.start();
    bus = DataChangeBus.forTesting();
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
      bus: bus,
    );
    await provider.loadQuotations();
    expect(provider.allQuotations.map((q) => q.name), ['S00001', 'S00002']);
  });

  tearDown(() async {
    provider.dispose();
    await odoo.stop();
  });

  double totalOf(int id) =>
      provider.allQuotations.firstWhere((q) => q.id == id).total;

  group('a change announced by another screen', () {
    test('an edited quotation is read again, in place', () async {
      odoo.put(1, 'S00001', 999, 'draft');
      var notified = 0;
      provider.addListener(() => notified++);

      bus.quotationChanged(1);
      await settle();

      expect(totalOf(1), 999, reason: 'the edit shows in the list');
      expect(totalOf(2), 200, reason: 'the others are untouched');
      expect(notified, greaterThan(0));
      expect(provider.isLoading, isFalse, reason: 'no shimmer, no reload');
    });

    test('a confirmed or cancelled one shows its new state', () async {
      odoo.put(2, 'S00002', 200, 'sale');
      bus.quotationChanged(2);
      await settle();
      expect(
        provider.allQuotations.firstWhere((q) => q.id == 2).status,
        'sale',
      );
    });

    test('a deleted one leaves the list, and the count drops', () async {
      final before = provider.totalQuotations;
      odoo.orders.remove(1);
      bus.quotationChanged(1, kind: DataChangeKind.deleted);
      await settle();
      expect(provider.allQuotations.map((q) => q.id), [2]);
      expect(provider.filteredQuotations.map((q) => q.id), [2]);
      expect(provider.totalQuotations, before - 1);
    });

    test(
      'a new quotation reloads the page without clearing it first',
      () async {
        odoo.put(3, 'S00003', 300, 'draft');
        var everLoading = false;
        var everEmpty = false;
        provider.addListener(() {
          if (provider.isLoading) everLoading = true;
          if (provider.allQuotations.isEmpty) everEmpty = true;
        });

        bus.quotationChanged(3, kind: DataChangeKind.created);
        await settle(900);

        expect(provider.allQuotations.map((q) => q.name).toSet(), {
          'S00001',
          'S00002',
          'S00003',
        });
        expect(everLoading, isFalse, reason: 'no loading state');
        expect(
          everEmpty,
          isFalse,
          reason: 'the old rows stayed until the new came',
        );
      },
    );

    test(
      'an invoice or a payment reloads the invoice status of the rows',
      () async {
        odoo.orders[1]!['invoice_status'] = 'invoiced';
        bus.invoiceChanged(5, kind: DataChangeKind.created);
        await settle(900);
        expect(
          provider.allQuotations.firstWhere((q) => q.id == 1).invoiceStatus,
          'invoiced',
        );
      },
    );

    test('a burst is read once', () async {
      odoo.calls.clear();
      bus.quotationChanged(1);
      bus.quotationChanged(1);
      bus.quotationChanged(1);
      await settle(900);
      expect(odoo.calls.where((c) => c == 'sale.order.search_read').length, 1);
    });

    test('a confirmed one leaves a list filtered to quotations, and the count '
        'follows', () async {
      await provider.loadQuotations(filters: {'quotation'});
      expect(provider.allQuotations.map((q) => q.id), [1, 2]);
      expect(provider.totalQuotations, 2);

      odoo.put(2, 'S00002', 200, 'sale');
      bus.quotationChanged(2);
      await settle(900);

      expect(provider.allQuotations.map((q) => q.id), [1]);
      expect(provider.filteredQuotations.map((q) => q.id), [1]);
      expect(provider.totalQuotations, 1);
    });

    test(
      'a cancelled one leaves the same list, however it was cancelled',
      () async {
        await provider.loadQuotations(filters: {'quotation'});
        await provider.cancelQuotation(1);
        await settle(900);

        expect(provider.allQuotations.map((q) => q.id), [2]);
        expect(provider.totalQuotations, 1);
      },
    );

    test('the quiet reload that a filter change overtook is dropped', () async {
      // A reload is in flight under the old filter when the filter changes:
      // the old list must not land on top of the new one.
      bus.quotationChanged(1);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await provider.loadQuotations(filters: {'sale'});
      await settle(900);

      expect(
        provider.allQuotations.every((q) => q.status == 'sale'),
        isTrue,
        reason: 'only sale orders under the sale filter',
      );
    });
  });

  group('the provider\'s own actions', () {
    test('cancelling announces it, updates its row, and is not re-read for '
        'its own announcement', () async {
      final heard = <DataChange>[];
      final sub = bus.listen(debounce: Duration.zero, onChange: heard.addAll);

      await provider.cancelQuotation(1);
      await settle();
      odoo.calls.clear();
      await settle(900);

      expect(
        provider.allQuotations.firstWhere((q) => q.id == 1).status,
        'cancel',
      );
      expect(heard.map((c) => c.id), contains(1));
      expect(heard.first.origin, provider, reason: 'it says who announced it');
      expect(
        odoo.calls.where((c) => c == 'sale.order.read'),
        isEmpty,
        reason: 'it ignores its own announcement',
      );
      sub.cancel();
    });

    test('deleting announces the deletion', () async {
      final heard = <DataChange>[];
      final sub = bus.listen(debounce: Duration.zero, onChange: heard.addAll);
      final service = MockQuotationService();
      when(
        () => service.deleteQuotationInstance(any()),
      ).thenAnswer((_) async {});
      final connectivity = MockConnectivityService();
      when(() => connectivity.isConnected).thenReturn(true);
      final other = QuotationProvider(
        quotationService: service,
        connectivityService: connectivity,
        bus: bus,
      );
      addTearDown(other.dispose);

      await other.deleteQuotation(2);
      await settle();
      expect(heard.single.kind, DataChangeKind.deleted);
      expect(heard.single.id, 2);
      sub.cancel();
    });
  });

  test('a provider that has not loaded yet ignores announcements', () async {
    final connectivity = MockConnectivityService();
    when(() => connectivity.isConnected).thenReturn(true);
    final fresh = QuotationProvider(
      quotationService: MockQuotationService(),
      connectivityService: connectivity,
      bus: bus,
    );
    addTearDown(fresh.dispose);
    odoo.calls.clear();
    bus.quotationChanged(1);
    await settle(900);
    expect(fresh.allQuotations, isEmpty);
  });
}
