import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/providers/login_provider.dart';
import 'package:mobo_sales/services/auth_service.dart';
import 'package:mobo_sales/services/sales_access.dart';
import 'package:mobo_sales/widgets/access_denied_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An [AuthService] whose sign-in ends the way the test says.
class _FakeAuth extends AuthService {
  _FakeAuth({this.refuse, this.succeed = false});

  final SalesAccessException? refuse;
  final bool succeed;
  int attempts = 0;

  @override
  Future<bool> loginAndSaveSession({
    required String serverUrl,
    required String database,
    required String userLogin,
    required String password,
  }) async {
    attempts++;
    if (refuse != null) throw refuse!;
    return succeed;
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

  testWidgets('a user without Sales access gets the popup and stays on login', (
    tester,
  ) async {
    await pumpHost(tester);
    final provider = providerWith(
      _FakeAuth(refuse: const SalesAccessException.denied()),
    );

    late Future<bool> result;
    await tester.runAsync(() async {
      result = provider.login(host);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.text('Access Denied'), findsOneWidget);
    expect(provider.isLoading, isFalse, reason: 'the button is free again');
    expect(provider.errorMessage, isNull, reason: 'the popup is the message');

    await tester.tap(find.text('Back to Login'));
    await tester.pumpAndSettle();
    expect(
      await tester.runAsync(() => result),
      isFalse,
      reason: 'no navigation into the app',
    );
    expect(
      provider.accessRefused,
      isTrue,
      reason: 'the sign-in screen goes back to the URL screen on this',
    );

    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    expect(
      prefs.getInt('lastSuccessfulAuth'),
      isNull,
      reason: 'a refused sign-in is not recorded as a success',
    );
    expect(prefs.getBool('isLoggedIn'), isNot(true));
  });

  testWidgets('a database without the Sales module is named in the popup', (
    tester,
  ) async {
    await pumpHost(tester);
    final provider = providerWith(
      _FakeAuth(refuse: const SalesAccessException.moduleMissing()),
    );

    late Future<bool> result;
    await tester.runAsync(() async {
      result = provider.login(host);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.text('Module Missing'), findsOneWidget);
    expect(find.byType(AccessDeniedDialog), findsOneWidget);
    await tester.tap(find.text('Back to Login'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => result), isFalse);
  });

  testWidgets('an account that could not be checked is not let in either', (
    tester,
  ) async {
    await pumpHost(tester);
    final provider = providerWith(
      _FakeAuth(refuse: const SalesAccessException.unverified()),
    );

    late Future<bool> result;
    await tester.runAsync(() async {
      result = provider.login(host);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.text('Unable to Verify Access'), findsOneWidget);
    await tester.tap(find.text('Back to Login'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => result), isFalse);
  });

  testWidgets('an account with access still signs in, with no popup', (
    tester,
  ) async {
    await pumpHost(tester);
    final auth = _FakeAuth(succeed: true);
    final provider = providerWith(auth);

    late bool ok;
    await tester.runAsync(() async {
      ok = await provider.login(host);
    });
    await tester.pump();

    expect(ok, isTrue);
    expect(auth.attempts, 1);
    expect(find.byType(AccessDeniedDialog), findsNothing);
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    expect(prefs.getInt('lastSuccessfulAuth'), isNotNull);
  });

  testWidgets('a portal user gets the portal message', (tester) async {
    await pumpHost(tester);
    final provider = providerWith(
      _FakeAuth(refuse: const SalesAccessException.portalUser()),
    );

    late Future<bool> result;
    await tester.runAsync(() async {
      result = provider.login(host);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.text('Portal Access Not Allowed'), findsOneWidget);
    expect(find.textContaining('portal user'), findsOneWidget);
    await tester.tap(find.text('Back to Login'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => result), isFalse);
  });
}
