import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/services/sales_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A small stand-in for an Odoo server: it signs anyone in as user 7 and
/// answers the access questions the way the test sets them up.
class _FakeOdoo {
  _FakeOdoo({
    this.moduleInstalled = true,
    this.inGroup = true,
    this.internal = true,
    this.hasGroupFails = false,
    this.version = '18.0',
  });

  bool moduleInstalled;
  bool inGroup;
  bool internal;
  bool hasGroupFails;
  String version;

  late HttpServer _server;
  final requests = <String>[];

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server.forEach(_handle));
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final json = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    final params = (json is Map ? json['params'] : null) as Map? ?? {};
    final response = request.response..headers.contentType = ContentType.json;

    dynamic result;
    Map<String, dynamic>? error;

    switch (request.uri.path) {
      case '/web/session/authenticate':
        response.headers.add('set-cookie', 'session_id=sess123; Path=/');
        result = {
          'uid': 7,
          'is_system': false,
          'user_context': {'lang': 'en_US', 'tz': 'UTC'},
          'db': 'shop',
          'server_version': version,
          'server_version_info': [int.parse(version.split('.').first), 0, 0],
          'name': 'Light',
          'username': 'light',
          'partner_id': 9,
          'company_id': 1,
        };
      case '/web/dataset/call_kw':
        final model = params['model'];
        final method = params['method'];
        requests.add('$model.$method');
        if (model == 'ir.model.data' && method == 'check_object_reference') {
          if (moduleInstalled) {
            result = ['ir.ui.menu', 42];
          } else {
            error = {
              'message': 'Odoo Server Error',
              'data': {
                'name': 'builtins.ValueError',
                'message':
                    'External ID not found in the system: sale.sale_menu_root',
              },
            };
          }
        } else if (model == 'res.users' && method == 'has_group') {
          if (hasGroupFails) {
            error = {
              'message': 'Odoo Server Error',
              'data': {'name': 'builtins.TypeError', 'message': 'boom'},
            };
          } else {
            final asked = (params['args'] as List).last;
            result = asked == 'base.group_user' ? internal : inGroup;
          }
        } else if (model == 'res.users' && method == 'read') {
          result = [
            {
              'id': 7,
              'company_id': [1, 'Co'],
              'company_ids': [1],
            },
          ];
        } else {
          result = [];
        }
      default:
        result = {};
    }

    response.write(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': json is Map ? json['id'] : null,
        if (error != null) 'error': error else 'result': result,
      }),
    );
    await response.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding answers every HTTP request with 400; these tests talk to a
  // server on the loopback interface.
  setUpAll(() => HttpOverrides.global = null);

  late _FakeOdoo odoo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    OdooSessionManager.clearClientCache();
    odoo = _FakeOdoo();
    await odoo.start();
  });
  tearDown(() => odoo.stop());

  Future<OdooSessionModel?> signIn() => OdooSessionManager.authenticate(
    serverUrl: odoo.url,
    database: 'shop',
    username: 'light',
    password: 'secret',
  );

  group('signing in (login and Add Account both come through here)', () {
    test('a user with Sales access is let in', () async {
      final session = await signIn();
      expect(session, isNotNull);
      expect(session!.userId, 7);
      expect(odoo.requests, contains('res.users.has_group'));
      expect(odoo.requests, contains('ir.model.data.check_object_reference'));
    });

    test('a user without Sales access is refused, with no session', () async {
      odoo.inGroup = false;
      await expectLater(
        signIn(),
        throwsA(
          isA<SalesAccessException>().having(
            (e) => e.status,
            'status',
            SalesAccessStatus.denied,
          ),
        ),
      );
    });

    test('a database without the Sales module is refused as such', () async {
      odoo.moduleInstalled = false;
      odoo.inGroup = false;
      await expectLater(
        signIn(),
        throwsA(
          isA<SalesAccessException>().having(
            (e) => e.status,
            'status',
            SalesAccessStatus.moduleMissing,
          ),
        ),
      );
    });

    test('a server that cannot answer is not let in on a guess', () async {
      odoo.hasGroupFails = true;
      await expectLater(
        signIn(),
        throwsA(
          isA<SalesAccessException>().having(
            (e) => e.status,
            'status',
            SalesAccessStatus.unverified,
          ),
        ),
      );
    });

    test('a portal user is refused as a portal user', () async {
      odoo.internal = false;
      odoo.inGroup = false;
      await expectLater(
        signIn(),
        throwsA(
          isA<SalesAccessException>().having(
            (e) => e.status,
            'status',
            SalesAccessStatus.portalUser,
          ),
        ),
      );
    });

    test('Odoo 17 is asked the way Odoo 17 is asked', () async {
      odoo.version = '17.0';
      expect(await signIn(), isNotNull);
    });
  });

  group('login saves nothing for a refused account', () {
    test(
      'loginAndSaveSession throws and leaves the preferences empty',
      () async {
        odoo.inGroup = false;
        await expectLater(
          OdooSessionManager.loginAndSaveSession(
            serverUrl: odoo.url,
            database: 'shop',
            userLogin: 'light',
            password: 'secret',
          ),
          throwsA(isA<SalesAccessException>()),
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('sessionId'), isNull);
        expect(prefs.getBool('isLoggedIn'), isNot(true));
        expect(prefs.getString('password'), isNull);
      },
    );

    test('an allowed account is saved', () async {
      final ok = await OdooSessionManager.loginAndSaveSession(
        serverUrl: odoo.url,
        database: 'shop',
        userLogin: 'light',
        password: 'secret',
      );
      expect(ok, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sessionId'), 'sess123');
    });

    test('the two-factor path refuses and saves nothing too', () async {
      odoo.inGroup = false;
      await expectLater(
        OdooSessionManager.loginWithSessionId(
          serverUrl: odoo.url,
          database: 'shop',
          userLogin: 'light',
          password: 'secret',
          sessionId: 'sess123',
          sessionInfo: {'uid': 7, 'server_version': '18.0', 'name': 'Light'},
        ),
        throwsA(isA<SalesAccessException>()),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sessionId'), isNull);
      expect(prefs.getBool('isLoggedIn'), isNot(true));
    });

    test('the two-factor path lets an allowed account in', () async {
      final ok = await OdooSessionManager.loginWithSessionId(
        serverUrl: odoo.url,
        database: 'shop',
        userLogin: 'light',
        password: 'secret',
        sessionId: 'sess123',
        sessionInfo: {'uid': 7, 'server_version': '18.0', 'name': 'Light'},
      );
      expect(ok, isTrue);
    });
  });

  group('the session saved on the device, at app start', () {
    Future<void> saveSession() async {
      final session = await signIn();
      await session!.saveToPrefs();
      OdooSessionManager.clearClientCache();
    }

    test('still allowed: no problem', () async {
      await saveSession();
      expect(await OdooSessionManager.currentSessionAccessProblem(), isNull);
    });

    test('access taken away since: denied', () async {
      await saveSession();
      odoo.inGroup = false;
      final problem = await OdooSessionManager.currentSessionAccessProblem();
      expect(problem?.status, SalesAccessStatus.denied);
    });

    test('turned into a portal user since: portalUser', () async {
      await saveSession();
      odoo.internal = false;
      odoo.inGroup = false;
      final problem = await OdooSessionManager.currentSessionAccessProblem();
      expect(problem?.status, SalesAccessStatus.portalUser);
    });

    test('module removed since: moduleMissing', () async {
      await saveSession();
      odoo.moduleInstalled = false;
      final problem = await OdooSessionManager.currentSessionAccessProblem();
      expect(problem?.status, SalesAccessStatus.moduleMissing);
    });

    test('server errors are not a refusal', () async {
      await saveSession();
      odoo.hasGroupFails = true;
      expect(await OdooSessionManager.currentSessionAccessProblem(), isNull);
    });

    test('an unreachable server is not a refusal either', () async {
      await saveSession();
      await odoo.stop();
      expect(
        await OdooSessionManager.currentSessionAccessProblem(
          timeout: const Duration(seconds: 3),
        ),
        isNull,
      );
      odoo = _FakeOdoo();
      await odoo.start();
    });

    test('no saved session: nothing to refuse', () async {
      expect(await OdooSessionManager.currentSessionAccessProblem(), isNull);
    });
  });
}
