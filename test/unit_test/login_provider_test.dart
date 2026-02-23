import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/providers/login_provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../mocks/mock_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LoginProvider loginProvider;
  late MockAuthService mockAuthService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockAuthService = MockAuthService();
    loginProvider = LoginProvider(authService: mockAuthService);
  });

  group('LoginProvider Tests', () {
    test('Initial state should be correct', () {
      expect(loginProvider.isLoading, isFalse);
      expect(loginProvider.errorMessage, isNull);
      expect(loginProvider.database, isNull);
    });

    test('clearForm should reset all controllers and states', () {
      loginProvider.urlController.text = 'test.com';
      loginProvider.emailController.text = 'test@test.com';
      loginProvider.passwordController.text = 'password';
      loginProvider.database = 'test_db';
      loginProvider.errorMessage = 'error';
      loginProvider.isLoading = true;

      loginProvider.clearForm();

      expect(loginProvider.urlController.text, isEmpty);
      expect(loginProvider.emailController.text, isEmpty);
      expect(loginProvider.passwordController.text, isEmpty);
      expect(loginProvider.database, isNull);
      expect(loginProvider.errorMessage, isNull);
      expect(loginProvider.isLoading, isFalse);
    });

    test('isFormReady should return true only when all fields are filled', () {
      expect(loginProvider.isFormReady, isFalse);

      loginProvider.urlController.text = 'test.com';
      expect(loginProvider.isFormReady, isFalse);

      loginProvider.emailController.text = 'test@test.com';
      expect(loginProvider.isFormReady, isFalse);

      loginProvider.passwordController.text = 'password';
      expect(loginProvider.isFormReady, isFalse);

      loginProvider.database = 'test_db';
      expect(loginProvider.isFormReady, isTrue);
    });

    test('login returns true on success', () async {
      loginProvider.urlController.text = 'test.com';
      loginProvider.emailController.text = 'test@test.com';
      loginProvider.passwordController.text = 'password';
      loginProvider.database = 'test_db';

      when(
        () => mockAuthService.loginAndSaveSession(
          serverUrl: any(named: 'serverUrl'),
          database: any(named: 'database'),
          userLogin: any(named: 'userLogin'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => true);

      final result = await loginProvider.login(FakeEmptyContext());

      expect(result, isTrue);
      expect(loginProvider.isLoading, isFalse);
      expect(loginProvider.errorMessage, isNull);
    });

    test('login returns false and sets error message on failure', () async {
      loginProvider.urlController.text = 'test.com';
      loginProvider.emailController.text = 'test@test.com';
      loginProvider.passwordController.text = 'password';
      loginProvider.database = 'test_db';

      when(
        () => mockAuthService.loginAndSaveSession(
          serverUrl: any(named: 'serverUrl'),
          database: any(named: 'database'),
          userLogin: any(named: 'userLogin'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => false);

      final result = await loginProvider.login(FakeEmptyContext());

      expect(result, isFalse);
      expect(loginProvider.isLoading, isFalse);
      expect(loginProvider.errorMessage, contains('Login failed'));
    });

    test('fetchDatabaseList success', () async {
      loginProvider.urlController.text = 'test.com';
      when(
        () => mockAuthService.fetchDatabaseList(any()),
      ).thenAnswer((_) async => ['db1', 'db2']);

      await loginProvider.fetchDatabaseList();

      expect(loginProvider.dropdownItems, ['db1', 'db2']);
      expect(loginProvider.urlCheck, isTrue);
      expect(loginProvider.database, 'db1');
    });

    test('fetchDatabaseList failure', () async {
      loginProvider.urlController.text = 'test.com';
      when(
        () => mockAuthService.fetchDatabaseList(any()),
      ).thenThrow(Exception('error'));

      await loginProvider.fetchDatabaseList();

      expect(loginProvider.urlCheck, isFalse);
      expect(loginProvider.errorMessage, isNotNull);
    });
  });
}

class FakeEmptyContext extends Fake implements BuildContext {}
