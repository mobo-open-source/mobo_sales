import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobo_sales/screens/login/add_account_screen.dart';
import 'package:mobo_sales/screens/login/credentials_screen.dart';
import 'package:mobo_sales/screens/login/server_setup_screen.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An Odoo with one database, that signs anyone in as user 7 and answers the
/// two access questions the way the test sets them up.
class _Server {
  _Server({this.moduleInstalled = true, this.inGroup = true});

  final bool moduleInstalled;
  final bool inGroup;

  late HttpServer _http;
  String get url => 'http://127.0.0.1:${_http.port}';

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_http.forEach(_handle));
  }

  Future<void> stop() => _http.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final json = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    final params = (json is Map ? json['params'] : null) as Map? ?? {};
    final response = request.response
      ..persistentConnection = false
      ..headers.contentType = ContentType.json;

    dynamic result = [];
    Map<String, dynamic>? error;
    switch (request.uri.path) {
      case '/web/database/list':
        result = ['shop'];
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
      case '/web/dataset/call_kw':
        final model = params['model'];
        final method = params['method'];
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
          final asked = (params['args'] as List).last;
          result = asked == 'base.group_user' ? true : inGroup;
        }
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

/// Where the popup that refuses an account leaves the user.
///
/// Sign in: server (URL) screen → credentials. The button on the popup takes
/// the user back to the server screen.
/// Add Account: Configuration → Add Account (server, credentials). OK on the
/// popup takes the user back to Configuration.
void main() {
  setUpAll(() {
    HttpOverrides.global = null;
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpFor(WidgetTester tester, Duration total) async {
    var elapsed = Duration.zero;
    while (elapsed < total) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      elapsed += const Duration(milliseconds: 100);
    }
  }

  /// Runs [scenario], setting aside the errors from Google Fonts (a test cannot
  /// reach it) and failing on any other. A failure in the scenario itself is
  /// kept and rethrown outside the guarded zone, where it would leave the test
  /// waiting for ever.
  Future<void> guarded(Future<void> Function() scenario) async {
    final otherErrors = <Object>[];
    Object? scenarioFailure;
    await runZonedGuarded(
      () async {
        try {
          await scenario();
        } catch (error) {
          scenarioFailure = error;
        }
      },
      (error, stack) {
        final text = error.toString();
        if (!text.contains('google_fonts') && !text.contains('GoogleFonts')) {
          otherErrors.add(error);
        }
      },
    );
    if (scenarioFailure != null) throw scenarioFailure!;
    expect(otherErrors, isEmpty);
  }

  Future<void> addAccountAgainst(WidgetTester tester, _Server server) async {
    SharedPreferences.setMockInitialValues({});
    OdooSessionManager.clearClientCache();
    await tester.runAsync(server.start);
    addTearDown(() => tester.runAsync(server.stop));

    await guarded(() async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('Configuration')),
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddAccountScreen(),
                    ),
                  ),
                  child: const Text('Open Add Account'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Add Account'));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(AddAccountScreen), findsOneWidget);

      // The server step: the address, then the database it lists.
      await tester.enterText(find.byType(TextField).first, server.url);
      await pumpFor(tester, const Duration(seconds: 3));
      await tester.tap(find.text('Next'));
      await pumpFor(tester, const Duration(seconds: 1));

      // The credentials step.
      await tester.enterText(
        find.widgetWithText(TextField, 'Email / Username'),
        'light',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'secret',
      );
      await tester.pump();
      // "Add Account" is the title and the button: the button is the last.
      await tester.tap(find.text('Add Account').last);
      await pumpFor(tester, const Duration(seconds: 3));
    });
  }

  testWidgets('no Sales module: OK on the popup goes back to Configuration', (
    tester,
  ) async {
    await addAccountAgainst(tester, _Server(moduleInstalled: false));

    // The popup is up over the credentials step, and nothing has moved yet.
    expect(find.text('Module Missing'), findsOneWidget);
    expect(find.byType(AddAccountScreen), findsOneWidget);

    await guarded(() async {
      await tester.tap(find.text('OK'));
      await pumpFor(tester, const Duration(seconds: 1));
    });

    expect(find.text('Module Missing'), findsNothing);
    expect(find.byType(AddAccountScreen), findsNothing);
    expect(find.text('Configuration'), findsOneWidget);

    // Nothing was kept.
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    expect(prefs.getBool('isLoggedIn'), isNot(true));
    expect(prefs.getString('sessionId'), isNull);
  });

  testWidgets('no Sales access: OK on the popup goes back to Configuration', (
    tester,
  ) async {
    await addAccountAgainst(tester, _Server(inGroup: false));

    expect(find.text('Access Denied'), findsOneWidget);
    expect(find.byType(AddAccountScreen), findsOneWidget);

    await guarded(() async {
      await tester.tap(find.text('OK'));
      await pumpFor(tester, const Duration(seconds: 1));
    });

    expect(find.text('Access Denied'), findsNothing);
    expect(find.byType(AddAccountScreen), findsNothing);
    expect(find.text('Configuration'), findsOneWidget);
  });

  /// The server (URL) screen, then the credentials screen, signing in.
  Future<void> signInAgainst(WidgetTester tester, _Server server) async {
    SharedPreferences.setMockInitialValues({});
    OdooSessionManager.clearClientCache();
    await tester.runAsync(server.start);
    addTearDown(() => tester.runAsync(server.stop));

    await guarded(() async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: ServerSetupScreen()));
      await tester.enterText(find.byType(TextField).first, server.url);
      await pumpFor(tester, const Duration(seconds: 3));
      await tester.tap(find.text('Next'));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(CredentialsScreen), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'light');
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'secret',
      );
      await tester.pump();
      // "Sign In" is the title and the button: the button is the last.
      await tester.tap(find.text('Sign In').last);
      await pumpFor(tester, const Duration(seconds: 3));
    });
  }

  testWidgets('sign in, no Sales module: the button goes back to the URL '
      'screen', (tester) async {
    await signInAgainst(tester, _Server(moduleInstalled: false));

    // The popup is up over the credentials screen, and nothing has moved yet.
    expect(find.text('Module Missing'), findsOneWidget);
    expect(find.byType(CredentialsScreen), findsOneWidget);

    await guarded(() async {
      await tester.tap(find.text('Back to Login'));
      await pumpFor(tester, const Duration(seconds: 1));
    });

    expect(find.text('Module Missing'), findsNothing);
    expect(find.byType(CredentialsScreen), findsNothing);
    expect(find.byType(ServerSetupScreen), findsOneWidget);

    // Nothing was kept.
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    expect(prefs.getBool('isLoggedIn'), isNot(true));
    expect(prefs.getString('sessionId'), isNull);
  });

  testWidgets('sign in, no Sales access: the button goes back to the URL '
      'screen', (tester) async {
    await signInAgainst(tester, _Server(inGroup: false));

    expect(find.text('Access Denied'), findsOneWidget);
    expect(find.byType(CredentialsScreen), findsOneWidget);

    await guarded(() async {
      await tester.tap(find.text('Back to Login'));
      await pumpFor(tester, const Duration(seconds: 1));
    });

    expect(find.text('Access Denied'), findsNothing);
    expect(find.byType(CredentialsScreen), findsNothing);
    expect(find.byType(ServerSetupScreen), findsOneWidget);
  });
}
