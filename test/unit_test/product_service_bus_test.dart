import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/services/permission_service.dart';
import 'package:mobo_sales/services/product_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks/mock_services.dart';

/// A product saved, archived or added is announced once the server has it, so
/// every list and page that shows products can read it again.
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
  late DataChangeBus bus;
  late ProductService service;
  late List<DataChange> heard;
  late DataChangeSubscription subscription;
  late PermissionService savedPermissions;
  late bool writeSucceeds;

  setUp(() async {
    heard = [];
    writeSucceeds = true;
    bus = DataChangeBus.forTesting();
    service = ProductService.forTesting(bus: bus);
    subscription = bus.listen(
      debounce: Duration.zero,
      onChange: (burst) => heard.addAll(burst),
    );

    savedPermissions = PermissionService.instance;
    final permissions = MockPermissionService();
    when(() => permissions.canCreate(any())).thenAnswer((_) async => true);
    when(() => permissions.canWrite(any())).thenAnswer((_) async => true);
    PermissionService.instance = permissions;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final params = Map<String, dynamic>.from(body['params'] as Map);
        dynamic result = [];
        final model = params['model'];
        final method = params['method'];
        if (model == 'product.template' && method == 'write') {
          result = writeSucceeds;
        } else if (model == 'product.template' && method == 'create') {
          result = 9;
        } else if (model == 'product.template' && method == 'read') {
          result = [
            {
              'id': 9,
              'name': 'Desk',
              'list_price': 10.0,
              'default_code': 'D1',
              'product_variant_count': 1,
            },
          ];
        } else if (model == 'product.product' && method == 'read') {
          result = [
            {
              'id': 7,
              'product_tmpl_id': [5, 'Desk'],
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
  });

  tearDown(() async {
    subscription.cancel();
    PermissionService.instance = savedPermissions;
    await server.close(force: true);
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('an edit that the server accepted is announced, by template', () async {
    final saved = await service.updateProduct('5', {'id': 5, 'name': 'Desk 2'});
    await settle();

    expect(saved, isTrue);
    expect(heard.map((c) => (c.entity, c.kind, c.id)), [
      (DataEntity.product, DataChangeKind.updated, 5),
    ]);
  });

  test(
    'an edit made through a variant id is announced under its template',
    () async {
      await service.updateProduct('7', {'name': 'Desk 2'});
      await settle();

      expect(heard.single.id, 5, reason: 'the template, not the variant');
    },
  );

  test('an edit the server did not accept announces nothing', () async {
    writeSucceeds = false;
    final saved = await service.updateProduct('5', {'id': 5, 'name': 'x'});
    await settle();

    expect(saved, isFalse);
    expect(heard, isEmpty);
  });

  test('a new product is announced as created', () async {
    final product = await service.createProduct({'name': 'Desk'});
    await settle();

    expect(product?.name, 'Desk');
    expect(heard.map((c) => (c.kind, c.id)), [(DataChangeKind.created, 9)]);
  });

  test('an archived product is announced as gone from the lists', () async {
    await service.archiveProduct(5);
    await settle();

    expect(heard.map((c) => (c.entity, c.kind, c.id)), [
      (DataEntity.product, DataChangeKind.deleted, 5),
    ]);
  });

  test(
    'an archive the server refused is an error and announces nothing',
    () async {
      writeSucceeds = false;
      await expectLater(service.archiveProduct(5), throwsException);
      await settle();
      expect(heard, isEmpty);
    },
  );
}
