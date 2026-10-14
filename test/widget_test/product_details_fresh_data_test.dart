import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/models/product.dart';
import 'package:mobo_sales/providers/currency_provider.dart';
import 'package:mobo_sales/providers/last_opened_provider.dart';
import 'package:mobo_sales/screens/products/product_details_page.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The product's page shows what the server holds: when it opens (whatever copy
/// it was handed, or an earlier visit left), and when the product is edited,
/// archived or changed anywhere else while it is open.
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

  late HttpServer server;
  late String nameOnServer;
  late double priceOnServer;
  late List<String> asked;

  Future<void> startServer() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final params = Map<String, dynamic>.from(body['params'] as Map);
        final model = params['model'];
        final method = params['method'];
        asked.add('$model.$method');

        dynamic result = [];
        if (method == 'check_access_rights' || method == 'has_access') {
          result = true;
        } else if (model == 'product.product' && method == 'fields_get') {
          result = <String, dynamic>{};
        } else if (model == 'product.product' && method == 'read') {
          result = [
            {
              'id': 5,
              'name': nameOnServer,
              'list_price': priceOnServer,
              'default_code': 'D-100',
              'categ_id': [1, 'All / Office'],
              'product_tmpl_id': [3, nameOnServer],
              'product_variant_count': 1,
              'active': true,
              'type': 'consu',
              'taxes_id': <int>[],
              'seller_ids': <int>[],
              'product_template_attribute_value_ids': <int>[],
              'currency_id': [1, 'USD'],
            },
          ];
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

  Future<void> settle(WidgetTester tester, [int rounds = 12]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 60 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Opens the page for variant 5 (template 3), handed a copy that says
  /// [staleName].
  Future<void> open(WidgetTester tester, {required String staleName}) async {
    final expected = nameOnServer;
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      onError?.call(details);
    };
    addTearDown(() => FlutterError.onError = onError);

    asked = [];
    await tester.runAsync(startServer);
    addTearDown(() => tester.runAsync(() => server.close(force: true)));
    SharedPreferences.setMockInitialValues({
      'isLoggedIn': true,
      'sessionId': 'sess123',
      'userLogin': 'admin',
      'password': 'x',
      'database': 'shop',
      'serverUrl': 'http://127.0.0.1:${server.port}',
      'userId': 2,
      'userName': 'Admin',
      'serverVersion': '18.0',
      'expiresAt': DateTime.now()
          .add(const Duration(hours: 5))
          .toIso8601String(),
    });
    OdooSessionManager.clearClientCache();

    final currency = await tester.runAsync(() async => CurrencyProvider());
    addTearDown(() => currency!.dispose());

    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CurrencyProvider>.value(value: currency!),
          ChangeNotifierProvider<LastOpenedProvider>(
            create: (_) => LastOpenedProvider(),
          ),
        ],
        child: MaterialApp(
          home: ProductDetailsPage(
            product: Product(
              id: '5',
              name: staleName,
              listPrice: 1.0,
              qtyAvailable: 0,
              variantCount: 1,
              defaultCode: 'D-100',
              templateId: 3,
            ),
          ),
        ),
      ),
    );
    // The page reads the product and what hangs off it in several steps and
    // shows a skeleton until the last.
    // An earlier visit's copy may be on screen at once: wait for the name the
    // server holds.
    await until(
      tester,
      () =>
          find.byType(Shimmer).evaluate().isEmpty &&
          find.text(expected).evaluate().isNotEmpty,
    );
    await settle(tester, 6);
  }

  Future<void> close(WidgetTester tester) async {
    await settle(tester, 20);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  setUp(() {
    nameOnServer = 'Standing desk';
    priceOnServer = 250.0;
  });

  testWidgets('opened with an old copy, it shows what the server holds', (
    tester,
  ) async {
    await open(tester, staleName: 'Old desk name');
    expect(find.text('Standing desk'), findsWidgets);
    expect(find.text('Old desk name'), findsNothing);
    expect(asked, contains('product.product.read'));
    await close(tester);
  });

  testWidgets('a second visit does not trust what the first one left', (
    tester,
  ) async {
    await open(tester, staleName: 'Old desk name');
    expect(find.text('Standing desk'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => server.close(force: true));

    // The product was renamed while nobody was looking.
    nameOnServer = 'Renamed meanwhile';
    await open(tester, staleName: 'Old desk name');

    expect(find.text('Renamed meanwhile'), findsWidgets);
    expect(find.text('Standing desk'), findsNothing);
    await close(tester);
  });

  testWidgets('an edit made elsewhere shows without a pull-down', (
    tester,
  ) async {
    nameOnServer = 'Laptop stand';
    await open(tester, staleName: 'Laptop stand');
    expect(find.text('Laptop stand'), findsWidgets);

    nameOnServer = 'Laptop stand (new model)';
    DataChangeBus.instance.productChanged(3);
    await until(
      tester,
      () => find.text('Laptop stand (new model)').evaluate().isNotEmpty,
    );

    expect(find.text('Laptop stand (new model)'), findsWidgets);
    await close(tester);
  });

  testWidgets('another product\'s change is not this page\'s business', (
    tester,
  ) async {
    nameOnServer = 'Monitor arm';
    await open(tester, staleName: 'Monitor arm');
    final readsBefore = asked.where((c) => c == 'product.product.read').length;

    nameOnServer = 'Should not be read';
    DataChangeBus.instance.productChanged(99);
    await settle(tester, 8);

    expect(asked.where((c) => c == 'product.product.read').length, readsBefore);
    expect(find.text('Should not be read'), findsNothing);
    await close(tester);
  });

  testWidgets(
    'a change with no id (a product of unknown identity) reloads it',
    (tester) async {
      nameOnServer = 'Cable tray';
      await open(tester, staleName: 'Cable tray');

      nameOnServer = 'Cable tray XL';
      DataChangeBus.instance.productChanged(null);
      await until(
        tester,
        () => find.text('Cable tray XL').evaluate().isNotEmpty,
      );

      expect(find.text('Cable tray XL'), findsWidgets);
      await close(tester);
    },
  );
}
