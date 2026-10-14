import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/providers/login_provider.dart';
import 'package:mobo_sales/services/auth_service.dart';
import 'package:mobo_sales/utils/database_expiry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An [AuthService] whose sign-in ends the way the test says.
class _FakeAuth extends AuthService {
  _FakeAuth(this.error);

  final Object error;
  int attempts = 0;

  @override
  Future<bool> loginAndSaveSession({
    required String serverUrl,
    required String database,
    required String userLogin,
    required String password,
  }) async {
    attempts++;
    throw error;
  }
}

void main() {
  late BuildContext host;

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
  }

  LoginProvider providerWith(_FakeAuth auth) {
    final provider = LoginProvider(authService: auth)
      ..database = 'shop'
      ..urlController.text = 'https://erp.example.com'
      ..emailController.text = 'light'
      ..passwordController.text = 'secret';
    addTearDown(provider.dispose);
    return provider;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('an expired database is shown in the sign-in error row, as the '
      'expired message and as nothing else', (tester) async {
    await pumpHost(tester);
    final provider = providerWith(_FakeAuth(const DatabaseExpiredException()));

    final signedIn = await tester.runAsync(() => provider.login(host));

    expect(signedIn, isFalse);
    expect(
      provider.errorMessage,
      'This database has expired. Please contact your administrator or Odoo to '
      'renew the subscription.',
    );
    expect(provider.isLoading, isFalse, reason: 'the button is free again');
    expect(provider.disableFields, isFalse);
  });

  testWidgets('it is not read as a wrong database or a wrong password', (
    tester,
  ) async {
    await pumpHost(tester);
    final provider = providerWith(_FakeAuth(const DatabaseExpiredException()));

    await tester.runAsync(() => provider.login(host));

    final text = provider.errorMessage!.toLowerCase();
    // The message says "database"; the sign-in's wording rules for a missing
    // database ("not available") and a wrong password ("incorrect") must not
    // have claimed it.
    expect(text, isNot(contains('not available')));
    expect(text, isNot(contains('incorrect')));
    expect(text, isNot(contains('login failed')));
  });

  testWidgets('a wrong database is still a wrong database', (tester) async {
    await pumpHost(tester);
    final provider = providerWith(
      _FakeAuth(Exception('database "shop" not found')),
    );

    await tester.runAsync(() => provider.login(host));

    expect(provider.errorMessage, contains('not available'));
  });
}
