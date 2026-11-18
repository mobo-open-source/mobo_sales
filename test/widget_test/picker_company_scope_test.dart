import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/models/company_scope.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/widgets/customer_typeahead.dart';
import 'package:mobo_sales/widgets/product_typeahead.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A create form's pickers send the company scope Odoo's own form gives its
/// fields; every other use of the pickers sends the search it always sent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );

  late HttpServer http;

  /// The domain of each `search_read`, by model.
  final domains = <String, List<List<dynamic>>>{};

  setUpAll(() {
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (call) async => ['wifi'],
        );
  });

  setUp(() async {
    domains.clear();
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      http.forEach((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final params = (body['params'] as Map?) ?? {};
        dynamic result = [];
        if (params['method'] == 'check_access_rights' ||
            params['method'] == 'has_access') {
          result = true;
        } else if (params['method'] == 'fields_get') {
          result = <String, dynamic>{};
        } else if (params['method'] == 'search_read') {
          final args = params['args'] as List;
          domains
              .putIfAbsent(params['model'] as String, () => [])
              .add(List<dynamic>.from(args.first as List));
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
    SharedPreferences.setMockInitialValues({
      'isLoggedIn': true,
      'sessionId': 'sess123',
      'userLogin': 'admin',
      'password': 'x',
      'database': 'shop',
      'serverUrl': 'http://127.0.0.1:${http.port}',
      'userId': 2,
      'userName': 'Admin',
      'serverVersion': '19.0',
      'expiresAt': DateTime.now()
          .add(const Duration(hours: 5))
          .toIso8601String(),
    });
    OdooSessionManager.clearClientCache();
  });

  tearDown(() => http.close(force: true));

  Future<void> settle(WidgetTester tester, [int ms = 800]) async {
    for (var t = 0; t < ms; t += 50) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(WidgetTester tester, Widget field) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(field));
    await tester.tap(find.byType(TextField));
    await settle(tester);
    await tester.pump(const Duration(seconds: 16));
  }

  const scope = [
    '|',
    ['company_id', '=', false],
    ['company_id', '=', 14],
  ];

  group('ProductTypeAhead', () {
    testWidgets('without a scope it sends the search it always sent', (
      tester,
    ) async {
      await open(
        tester,
        ProductTypeAhead(labelText: 'Product', onProductSelected: (_) {}),
      );
      expect(domains['product.product']!.first, [
        ['sale_ok', '=', true],
        ['active', '=', true],
      ]);
    });

    testWidgets("a create form's scope is ANDed with the search", (
      tester,
    ) async {
      await open(
        tester,
        ProductTypeAhead(
          labelText: 'Product',
          onProductSelected: (_) {},
          extraDomain: () async => companyCheckDomain(14),
        ),
      );
      expect(domains['product.product']!.first, [
        ['sale_ok', '=', true],
        ['active', '=', true],
        ...scope,
      ]);
    });
  });

  group('CustomerTypeAhead', () {
    testWidgets('without a scope it sends the search it always sent', (
      tester,
    ) async {
      await open(
        tester,
        CustomerTypeAhead(labelText: 'Customer', onCustomerSelected: (_) {}),
      );
      expect(domains['res.partner']!.first, [
        ['active', '=', true],
      ]);
    });

    testWidgets("a create form's scope is ANDed with the search", (
      tester,
    ) async {
      await open(
        tester,
        CustomerTypeAhead(
          labelText: 'Customer',
          onCustomerSelected: (_) {},
          extraDomain: () async => companyCheckDomain(14),
        ),
      );
      expect(domains['res.partner']!.first, [
        ['active', '=', true],
        ...scope,
      ]);
    });
  });
}
