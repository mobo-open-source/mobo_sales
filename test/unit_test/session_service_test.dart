import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/session_service.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SessionService sessionService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sessionService = SessionService();
    await sessionService.clearSession();
  });

  group('SessionService Basic State Tests', () {
    test('Initial state should be consistent', () {
      expect(sessionService.isInitialized, isFalse);
      expect(sessionService.hasValidSession, isFalse);
      expect(sessionService.storedAccounts, isEmpty);
    });

    test(
      'updateSession should update currentSession and notify listeners',
      () async {
        final session = OdooSessionModel(
          sessionId: 'test_id',
          userLogin: 'test_user',
          password: 'test_password',
          serverUrl: 'http://test.com',
          database: 'test_db',
        );

        bool notified = false;
        sessionService.addListener(() => notified = true);

        await sessionService.updateSession(session);

        expect(sessionService.currentSession, equals(session));
        expect(sessionService.hasValidSession, isTrue);
        expect(notified, isTrue);
      },
    );

    test('clearSession should reset session state', () async {
      final session = OdooSessionModel(
        sessionId: 'test_id',
        userLogin: 'test_user',
        password: 'test_password',
        serverUrl: 'http://test.com',
        database: 'test_db',
      );

      await sessionService.updateSession(session);
      expect(sessionService.hasValidSession, isTrue);

      await sessionService.clearSession();
      expect(sessionService.hasValidSession, isFalse);
    });
  });

  group('SessionService Account Storage Tests', () {
    test(
      'storeAccount should add account to storedAccounts and SharedPreferences',
      () async {
        final session = OdooSessionModel(
          sessionId: 'test_id',
          userLogin: 'user@test.com',
          password: 'password123',
          serverUrl: 'http://test.com',
          database: 'test_db',
          userId: 1,
        );

        await sessionService.storeAccount(session, 'password123');

        expect(sessionService.storedAccounts.length, 1);

        final prefs = await SharedPreferences.getInstance();
        final storedRaw = prefs.getStringList('stored_accounts');
        expect(storedRaw, isNotNull);
        expect(storedRaw!.length, 1);

        final decoded = jsonDecode(storedRaw[0]);
        expect(decoded['userId'], '1');
      },
    );

    test('removeStoredAccount should update state and persistence', () async {
      final session = OdooSessionModel(
        sessionId: 'test_id',
        userLogin: 'user@test.com',
        password: 'password123',
        serverUrl: 'http://test.com',
        database: 'test_db',
        userId: 1,
      );

      await sessionService.storeAccount(session, 'password123');
      expect(sessionService.storedAccounts.length, 1);

      await sessionService.removeStoredAccount(0);
      expect(sessionService.storedAccounts, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('stored_accounts'), isEmpty);
    });
  });

  group('SessionService Data Privacy Tests', () {
    test('logout should clear password caches', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('password_user1', 'pw1');
      await prefs.setString('other_key', 'value');

      await sessionService.logout();

      expect(prefs.getString('password_user1'), isNull);
      expect(prefs.getString('other_key'), 'value');
    });

    test('logout should preserve settings while clearing user data', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasSeenGetStarted', true);
      await prefs.setString('theme_mode', 'dark');

      await sessionService.logout();

      expect(prefs.getBool('hasSeenGetStarted'), isTrue);
      expect(prefs.getString('theme_mode'), 'dark');
    });
  });
}
