import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/models/product.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/shared/widgets/mobo/mobo_select_field.dart';
import 'package:mobo_sales/widgets/product_typeahead.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A product list longer than one page can be scrolled to its end, and every
/// product on it picked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The field at its natural height at the top, as in a form's column — a
  /// bare Scaffold body would stretch it over the whole screen.
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );

  group('MoboSelectField with pages', () {
    testWidgets('scrolling to the end asks for the next page', (tester) async {
      var loads = 0;
      var count = 30;
      String? picked;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => host(
            MoboSelectField<String>(
              value: null,
              options: [
                for (var i = 0; i < count; i++)
                  MoboOption<String>(value: 'p$i', label: 'Product $i'),
              ],
              hasMore: count < 75,
              onLoadMore: () {
                loads++;
                setState(() => count += 30);
              },
              onChanged: (v) => picked = v,
              onSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('Product 0'), findsOneWidget);

      // To the end of the first page, and again as pages arrive.
      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -2000));
        await tester.pumpAndSettle();
      }

      expect(loads, 2, reason: '30 -> 60 -> 90 holds all 75');
      expect(count, 90);
      expect(find.text('Product 74'), findsNothing, reason: 'only 75 exist');
      expect(picked, isNull);
    });

    testWidgets('the last option of the last page can be picked', (
      tester,
    ) async {
      String? picked;
      await tester.pumpWidget(
        host(
          MoboSelectField<String>(
            value: null,
            options: [
              for (var i = 0; i < 40; i++)
                MoboOption<String>(value: 'p$i', label: 'Product $i'),
            ],
            hasMore: false,
            onChanged: (v) => picked = v,
            onSearchChanged: (_) {},
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Product 39'));
      await tester.pumpAndSettle();

      expect(picked, 'p39');
    });

    testWidgets('no more pages: scrolling asks for nothing', (tester) async {
      var loads = 0;
      await tester.pumpWidget(
        host(
          MoboSelectField<String>(
            value: null,
            options: [
              for (var i = 0; i < 40; i++)
                MoboOption<String>(value: 'p$i', label: 'Product $i'),
            ],
            hasMore: false,
            onLoadMore: () => loads++,
            onChanged: (_) {},
            onSearchChanged: (_) {},
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();

      expect(loads, 0);
    });
  });

  group('ProductTypeAhead on a 75-product catalogue', () {
    late HttpServer http;
    final requests = <Map<String, dynamic>>[];

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
      requests.clear();
      http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(
        http.forEach((request) async {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          final params = (body['params'] as Map?) ?? {};
          dynamic result = [];
          if (params['method'] == 'check_access_rights' ||
              params['method'] == 'has_access') {
            result = true;
          } else if (params['model'] == 'product.product' &&
              params['method'] == 'search_read') {
            final kwargs = Map<String, dynamic>.from(params['kwargs'] as Map);
            requests.add(kwargs);
            final offset = (kwargs['offset'] as int?) ?? 0;
            final limit = kwargs['limit'] as int;
            result = [
              for (var i = offset; i < (offset + limit).clamp(0, 75); i++)
                {
                  'id': i + 1,
                  'name': 'Item ${(i + 1).toString().padLeft(2, '0')}',
                  'list_price': 10.0,
                  'qty_available': 1.0,
                  'default_code': false,
                  'barcode': false,
                  'product_variant_count': 1,
                  'uom_id': [1, 'Units'],
                  'taxes_id': <int>[],
                  'categ_id': [1, 'All'],
                  'description_sale': false,
                },
            ];
          }
          request.response
            ..persistentConnection = false
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': body['id'],
                'result': result,
              }),
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
        'serverVersion': '18.0',
        'expiresAt': DateTime.now()
            .add(const Duration(hours: 5))
            .toIso8601String(),
      });
      OdooSessionManager.clearClientCache();
    });

    tearDown(() => http.close(force: true));

    Future<void> settle(WidgetTester tester, [int ms = 600]) async {
      for (var t = 0; t < ms; t += 50) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('scrolling reaches the last product and picking it works', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Product? picked;
      await tester.pumpWidget(
        host(
          ProductTypeAhead(
            labelText: 'Product',
            onProductSelected: (p) => picked = p,
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await settle(tester);

      expect(requests, hasLength(1));
      expect(requests.first['limit'], 30);
      expect(requests.first['offset'], 0);
      await tester.pump(const Duration(seconds: 16)); // HTTP keep-alive timer

      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -3000));
        await settle(tester, 300);
      }

      expect(
        requests.map((r) => r['offset']).toList(),
        [0, 30, 60],
        reason: 'three pages cover all 75, then it stops asking',
      );

      await tester.tap(find.text('Item 75'));
      await settle(tester, 200);
      expect(picked?.name, 'Item 75');
      await tester.pump(const Duration(seconds: 16)); // HTTP keep-alive timer
    });

    testWidgets('a new search starts again from the first page', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(ProductTypeAhead(labelText: 'Product', onProductSelected: (_) {})),
      );
      await tester.tap(find.byType(TextField));
      await settle(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await settle(tester, 1000);
      expect(requests.length, greaterThan(1));

      requests.clear();
      await tester.enterText(find.byType(TextField), 'Item');
      await settle(tester, 800);

      expect(requests.first['offset'], 0);
    });
  });
}
