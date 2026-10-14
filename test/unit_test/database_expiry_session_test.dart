import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/utils/database_expiry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stand-in for an Odoo server that signs anyone in as user 7, answers the
/// session info the way the test sets it up, and notes every question asked, so
/// a test can say what was (and was not) asked of an expired database.
class _FakeOdoo {
  /// What `get_session_info` says: the key is left out for Community.
  Object? expirationDate = _absent;
  static const Object _absent = Object();

  bool sessionInfoFails = false;
  String? parameter;
  final requests = <String>[];

  late HttpServer _server;
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
    requests.add(request.uri.path);

    switch (request.uri.path) {
      case '/web/session/authenticate':
        response.headers.add('set-cookie', 'session_id=sess123; Path=/');
        result = {
          'uid': 7,
          'is_system': false,
          'user_context': {'lang': 'en_US', 'tz': 'UTC'},
          'db': 'shop',
          'server_version': '18.0',
          'server_version_info': [18, 0, 0],
          'name': 'Light',
          'username': 'light',
          'partner_id': 9,
          'company_id': 1,
        };
      case '/web/session/get_session_info':
        if (sessionInfoFails) {
          error = {
            'message': 'Odoo Server Error',
            'data': {'message': 'boom'},
          };
        } else {
          result = {
            'uid': 7,
            'name': 'Light',
            'server_version': '18.0',
            'company_id': 1,
            if (!identical(expirationDate, _absent))
              'expiration_date': expirationDate,
          };
        }
      case '/web/dataset/call_kw':
        final model = params['model'];
        final method = params['method'];
        requests.add('$model.$method');
        if (model == 'ir.config_parameter' && method == 'get_param') {
          result = parameter ?? false;
        } else if (model == 'ir.model.data') {
          result = ['ir.ui.menu', 42];
        } else if (model == 'res.users' && method == 'has_group') {
          result = true;
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
  setUpAll(() => HttpOverrides.global = null);

  const expired = '2020-01-01 00:00:00';
  const valid = '2099-01-01 00:00:00';

  late _FakeOdoo odoo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    OdooSessionManager.clearClientCache();
    odoo = _FakeOdoo();
    await odoo.start();
  });
  tearDown(() => odoo.stop());

  Future<dynamic> signIn() => OdooSessionManager.authenticate(
    serverUrl: odoo.url,
    database: 'shop',
    username: 'light',
    password: 'secret',
  );

  /// Nothing past the password check was asked of the server.
  void expectNothingElseWasAsked() {
    expect(
      odoo.requests,
      isNot(contains('res.users.read')),
      reason: 'companies',
    );
    expect(
      odoo.requests,
      isNot(contains('ir.model.data.check_object_reference')),
      reason: 'the Sales module check',
    );
    expect(odoo.requests, isNot(contains('res.users.has_group')));
  }

  group('signing in (login, Add Account and the account switches)', () {
    test(
      'an expired database is refused, before anything else is asked',
      () async {
        odoo.expirationDate = expired;
        await expectLater(signIn(), throwsA(isA<DatabaseExpiredException>()));
        expectNothingElseWasAsked();
      },
    );

    test('it is not retried: the server is asked once', () async {
      odoo.expirationDate = expired;
      await expectLater(signIn(), throwsA(isA<DatabaseExpiredException>()));
      expect(
        odoo.requests.where((r) => r == '/web/session/authenticate').length,
        1,
      );
      expect(
        odoo.requests.where((r) => r == '/web/session/get_session_info').length,
        1,
      );
    });

    test('a database with time left is let in', () async {
      odoo.expirationDate = valid;
      final session = await signIn();
      expect(session, isNotNull);
      expect(session.userId, 7);
    });

    test('a Community database (no expiration date) is let in, and the '
        'parameter is never read', () async {
      final session = await signIn();
      expect(session, isNotNull);
      expect(odoo.requests, isNot(contains('ir.config_parameter.get_param')));
    });

    test('a false date is let in', () async {
      odoo.expirationDate = false;
      expect(await signIn(), isNotNull);
    });

    test(
      'when the session info cannot be read, the parameter decides',
      () async {
        odoo.sessionInfoFails = true;
        odoo.parameter = expired;
        await expectLater(signIn(), throwsA(isA<DatabaseExpiredException>()));
        expect(odoo.requests, contains('ir.config_parameter.get_param'));
        expectNothingElseWasAsked();
      },
    );

    test('and lets the user in when neither can be read', () async {
      odoo.sessionInfoFails = true;
      expect(await signIn(), isNotNull);
    });
  });

  group('the sign-in saves nothing for an expired database', () {
    test(
      'loginAndSaveSession rethrows it and leaves the preferences empty',
      () async {
        odoo.expirationDate = expired;
        await expectLater(
          OdooSessionManager.loginAndSaveSession(
            serverUrl: odoo.url,
            database: 'shop',
            userLogin: 'light',
            password: 'secret',
          ),
          throwsA(isA<DatabaseExpiredException>()),
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('sessionId'), isNull);
        expect(prefs.getBool('isLoggedIn'), isNot(true));
        expect(prefs.getString('password'), isNull);
        expect(await OdooSessionManager.getCurrentSession(), isNull);
      },
    );

    test('a valid database is saved', () async {
      odoo.expirationDate = valid;
      expect(
        await OdooSessionManager.loginAndSaveSession(
          serverUrl: odoo.url,
          database: 'shop',
          userLogin: 'light',
          password: 'secret',
        ),
        isTrue,
      );
      expect(
        (await SharedPreferences.getInstance()).getString('sessionId'),
        'sess123',
      );
    });
  });

  group('the two-factor path and restoring a saved session', () {
    Future<bool> restore({Map<String, dynamic>? sessionInfo}) =>
        OdooSessionManager.loginWithSessionId(
          serverUrl: odoo.url,
          database: 'shop',
          userLogin: 'light',
          password: 'secret',
          sessionId: 'sess123',
          sessionInfo: sessionInfo,
        );

    test('reads the date from the session info it is handed, with no request '
        'of its own', () async {
      await expectLater(
        restore(
          sessionInfo: {
            'uid': 7,
            'server_version': '18.0',
            'name': 'Light',
            'expiration_date': expired,
          },
        ),
        throwsA(isA<DatabaseExpiredException>()),
      );
      expect(odoo.requests, isEmpty, reason: 'nothing was asked of the server');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sessionId'), isNull);
      expect(prefs.getBool('isLoggedIn'), isNot(true));
      expect(await OdooSessionManager.getCurrentSession(), isNull);
    });

    test(
      'reads it from the session info it fetches when none was handed',
      () async {
        odoo.expirationDate = expired;
        await expectLater(restore(), throwsA(isA<DatabaseExpiredException>()));
        expectNothingElseWasAsked();
        expect(
          (await SharedPreferences.getInstance()).getString('sessionId'),
          isNull,
        );
      },
    );

    test('lets a valid or Community database in', () async {
      expect(
        await restore(
          sessionInfo: {
            'uid': 7,
            'server_version': '18.0',
            'name': 'Light',
            'expiration_date': valid,
          },
        ),
        isTrue,
      );
      OdooSessionManager.clearClientCache();
      expect(
        await restore(
          sessionInfo: {'uid': 7, 'server_version': '18.0', 'name': 'Light'},
        ),
        isTrue,
      );
    });
  });

  group('the session saved on the device (app start, return to the app)', () {
    Future<void> saveSession() async {
      odoo.expirationDate = valid;
      final session = await signIn();
      await (session as dynamic).saveToPrefs();
      OdooSessionManager.clearClientCache();
      odoo.requests.clear();
    }

    test('expired since: true', () async {
      await saveSession();
      odoo.expirationDate = expired;
      expect(await OdooSessionManager.currentSessionDatabaseExpired(), isTrue);
    });

    test('still valid: false', () async {
      await saveSession();
      expect(await OdooSessionManager.currentSessionDatabaseExpired(), isFalse);
    });

    test('Community: false', () async {
      await saveSession();
      odoo.expirationDate = _FakeOdoo._absent;
      expect(await OdooSessionManager.currentSessionDatabaseExpired(), isFalse);
    });

    test('an unreachable server is not "expired"', () async {
      await saveSession();
      await odoo.stop();
      expect(
        await OdooSessionManager.currentSessionDatabaseExpired(
          timeout: const Duration(seconds: 3),
        ),
        isFalse,
      );
      odoo = _FakeOdoo();
      await odoo.start();
    });

    test('no saved session: false', () async {
      expect(await OdooSessionManager.currentSessionDatabaseExpired(), isFalse);
    });
  });
}
