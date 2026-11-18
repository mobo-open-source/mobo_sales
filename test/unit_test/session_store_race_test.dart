import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A session is saved one preference at a time. Anything that read storage
/// part-way through a save after signing in got the new session id without its
/// user, company or Odoo version, kept that, and saved it over the complete
/// one: the company picker then failed and the app treated the server as an
/// unknown Odoo. Seen on a phone with a 2FA sign-in right after a logout.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => HttpOverrides.global = null);

  late HttpServer server;
  late Map<String, dynamic> sessionInfo;
  late int infoCalls;
  Completer<void>? holdInfo;

  setUp(() async {
    infoCalls = 0;
    holdInfo = null;
    sessionInfo = {
      'uid': 7,
      'name': 'Repaired User',
      'server_version': '19.0+e',
      'user_companies': {'current_company': 3},
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        if (request.uri.path == '/web/session/get_session_info') {
          infoCalls++;
          await holdInfo?.future;
        }
        request.response
          ..persistentConnection = false
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': sessionInfo,
            }),
          );
        await request.response.close();
      }),
    );
    OdooSessionManager.clearClientCache();
  });

  tearDown(() => server.close(force: true));

  String url() => 'http://127.0.0.1:${server.port}';

  OdooSessionModel complete() => OdooSessionModel(
    sessionId: 'new-session',
    userLogin: 'admin',
    password: 'x',
    serverUrl: url(),
    database: 'shop',
    userId: 2,
    userName: 'Admin',
    expiresAt: DateTime.now().add(const Duration(hours: 24)),
    selectedCompanyId: 1,
    allowedCompanyIds: const [1],
    serverVersion: '19.0+e',
  );

  /// Storage as a half-finished save leaves it after a logout: the session id
  /// and server, nothing about the user or the Odoo version.
  Map<String, Object> halfWritten() => {
    'isLoggedIn': true,
    'sessionId': 'new-session',
    'userLogin': 'admin',
    'password': 'x',
    'database': 'shop',
    'serverUrl': url(),
  };

  test(
    'a read while a sign-in is being saved gets the whole session',
    () async {
      SharedPreferences.setMockInitialValues({});
      final saving = OdooSessionManager.updateSession(complete());
      final read = await OdooSessionManager.getCurrentSession();
      await saving;

      expect(read?.userId, 2);
      expect(read?.serverVersion, '19.0+e');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('userId'), 2);
      expect(prefs.getString('serverVersion'), '19.0+e');
    },
  );

  test(
    'saving a session without its user never erases the stored user',
    () async {
      SharedPreferences.setMockInitialValues({'userId': 2});
      await OdooSessionModel(
        sessionId: 'new-session',
        userLogin: 'admin',
        password: 'x',
        serverUrl: url(),
        database: 'shop',
      ).saveToPrefs();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('userId'), 2);
    },
  );

  test(
    'a session stored without its user is completed from the server',
    () async {
      SharedPreferences.setMockInitialValues(halfWritten());

      final session = await OdooSessionManager.getCurrentSession();

      expect(session?.userId, 7);
      expect(session?.userName, 'Repaired User');
      expect(session?.serverVersion, '19.0+e');
      expect(session?.selectedCompanyId, 3);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('userId'), 7, reason: 'repaired for the next start');
      expect(prefs.getString('serverVersion'), '19.0+e');
    },
  );

  test(
    'a company already chosen is kept when the session is repaired',
    () async {
      SharedPreferences.setMockInitialValues({
        ...halfWritten(),
        'selected_company_id': 14,
      });

      final session = await OdooSessionManager.getCurrentSession();

      expect(session?.selectedCompanyId, 14);
    },
  );

  test(
    'when the server cannot say, the stored session is used as before',
    () async {
      sessionInfo = {'uid': false};
      SharedPreferences.setMockInitialValues(halfWritten());

      final session = await OdooSessionManager.getCurrentSession();

      expect(session, isNotNull);
      expect(session?.sessionId, 'new-session');
      expect(session?.userId, isNull);
    },
  );

  test('a complete stored session is used without asking the server', () async {
    SharedPreferences.setMockInitialValues({
      ...halfWritten(),
      'userId': 2,
      'serverVersion': '18.0',
    });

    final session = await OdooSessionManager.getCurrentSession();

    expect(session?.userId, 2);
    expect(infoCalls, 0);
  });

  test(
    'a load that started before a sign-in does not bring back the old session',
    () async {
      SharedPreferences.setMockInitialValues(halfWritten());
      holdInfo = Completer<void>();

      final loading = OdooSessionManager.getCurrentSession();
      while (infoCalls == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      await OdooSessionManager.updateSession(complete());
      holdInfo!.complete();
      await loading;

      final now = await OdooSessionManager.getCurrentSession();
      expect(now?.userId, 2, reason: 'the sign-in, not the repaired old read');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('userId'), 2);
    },
  );
}
