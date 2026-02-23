import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OdooSessionModel Tests', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('saveToPrefs saves session data correctly', () async {
      final session = OdooSessionModel(
        sessionId: 'test_session_123',
        userLogin: 'test@example.com',
        password: 'test_password',
        serverUrl: 'https://test.odoo.com',
        database: 'test_db',
        userId: 42,
      );

      await session.saveToPrefs();

      expect(prefs.getString('sessionId'), 'test_session_123');
      expect(prefs.getString('userLogin'), 'test@example.com');
      expect(prefs.getString('password'), 'test_password');
      expect(prefs.getString('serverUrl'), 'https://test.odoo.com');
      expect(prefs.getString('database'), 'test_db');
      expect(prefs.getInt('userId'), 42);
      expect(prefs.getBool('isLoggedIn'), true);
    });

    test('fromPrefs returns null when no session exists', () async {
      final session = await OdooSessionModel.fromPrefs();
      expect(session, isNull);
    });

    test('fromPrefs loads session data correctly', () async {
      await prefs.setString('sessionId', 'loaded_session_456');
      await prefs.setString('userLogin', 'loaded@example.com');
      await prefs.setString('password', 'loaded_password');
      await prefs.setString('serverUrl', 'https://loaded.odoo.com');
      await prefs.setString('database', 'loaded_db');
      await prefs.setInt('userId', 99);
      await prefs.setBool('isLoggedIn', true);

      final session = await OdooSessionModel.fromPrefs();

      expect(session, isNotNull);
      expect(session!.sessionId, 'loaded_session_456');
      expect(session.userLogin, 'loaded@example.com');
      expect(session.password, 'loaded_password');
      expect(session.serverUrl, 'https://loaded.odoo.com');
      expect(session.database, 'loaded_db');
      expect(session.userId, 99);
    });

    test('fromPrefs returns null when is_logged_in is false', () async {
      await prefs.setString('sessionId', 'test_session');
      await prefs.setBool('isLoggedIn', false);

      final session = await OdooSessionModel.fromPrefs();
      expect(session, isNull);
    });
  });

  group('OdooSessionManager Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      OdooSessionManager.clearClientCache();
    });

    test('getCurrentSession returns null when no session exists', () async {
      final session = await OdooSessionManager.getCurrentSession();
      expect(session, isNull);
    });

    test('getCurrentSession returns session when available', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sessionId', 'current_session');
      await prefs.setString('userLogin', 'current@example.com');
      await prefs.setString('password', 'current_password');
      await prefs.setString('serverUrl', 'https://current.odoo.com');
      await prefs.setString('database', 'current_db');
      await prefs.setInt('userId', 1);
      await prefs.setBool('isLoggedIn', true);

      final session = await OdooSessionManager.getCurrentSession();

      expect(session, isNotNull);
      expect(session!.sessionId, 'current_session');
      expect(session.userLogin, 'current@example.com');
    });

    test('clearClientCache clears the cached client', () {
      OdooSessionManager.clearClientCache();
    });

    test('logout clears session data from SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sessionId', 'logout_session');
      await prefs.setString('userLogin', 'logout@example.com');
      await prefs.setBool('isLoggedIn', true);

      await OdooSessionManager.logout();

      expect(prefs.getString('sessionId'), isNull);
      expect(prefs.getString('userLogin'), isNull);
      expect(prefs.getBool('isLoggedIn'), isNull);
    });

    test('updateSession saves session to preferences', () async {
      final session = OdooSessionModel(
        sessionId: 'update_session',
        userLogin: 'update@example.com',
        password: 'update_password',
        serverUrl: 'https://update.odoo.com',
        database: 'update_db',
        userId: 5,
      );

      await OdooSessionManager.updateSession(session);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sessionId'), 'update_session');
      expect(prefs.getString('userLogin'), 'update@example.com');
      expect(prefs.getBool('isLoggedIn'), true);
    });

    test('setSessionCallbacks sets callbacks without error', () {
      OdooSessionManager.setSessionCallbacks(
        onSessionUpdated: (session) {},
        onSessionCleared: () {},
      );
    });
  });
}
