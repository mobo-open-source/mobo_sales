import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobo_sales/screens/login/credentials_screen.dart';
import 'package:mobo_sales/screens/login/server_setup_screen.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/utils/database_expiry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An Odoo with one database, whose subscription has expired.
class _Server {
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
    final response = request.response
      ..persistentConnection = false
      ..headers.contentType = ContentType.json;

    dynamic result = [];
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
      case '/web/session/get_session_info':
        result = {'uid': 7, 'expiration_date': '2020-01-01 00:00:00'};
    }
    response.write(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': json is Map ? json['id'] : null,
        'result': result,
      }),
    );
    await response.close();
  }
}

/// The sign-in is refused on the credentials screen — the server only says so
/// once the password is accepted — but it is the server and the database that
/// are at fault, so the user is taken back to the server screen and told there.
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

  testWidgets('an expired database is said on the server screen, not on the '
      'credentials screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    OdooSessionManager.clearClientCache();
    final server = _Server();
    await tester.runAsync(server.start);
    addTearDown(() => tester.runAsync(server.stop));

    Future<void> scenario() async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ServerSetupScreen()));

      // The server screen: the address, then the database it lists.
      await tester.enterText(find.byType(TextField).first, server.url);
      await pumpFor(tester, const Duration(seconds: 3));
      await tester.tap(find.text('Next'));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(CredentialsScreen), findsOneWidget);

      // The credentials screen: a right password.
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'light');
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'secret',
      );
      await tester.pump();
      // "Sign In" is the title and the button: the button is the last.
      await tester.tap(find.text('Sign In').last);
      await pumpFor(tester, const Duration(seconds: 3));
    }

    // The typeface is asked of Google Fonts, which a test cannot reach; those
    // errors are set aside, any other fails the test. A failure in the scenario
    // itself is kept and rethrown here: inside the guarded zone it would leave
    // the test waiting for ever.
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

    // Back on the server screen, with the message under the address and database.
    expect(find.byType(CredentialsScreen), findsNothing);
    expect(find.byType(ServerSetupScreen), findsOneWidget);
    expect(find.text(DatabaseExpiredException.message), findsOneWidget);
    // And the keyboard is shut: no field of the server screen was handed the
    // focus again on the way back.
    expect(
      tester.testTextInput.isVisible,
      isFalse,
      reason: 'the keyboard is closed',
    );
    final focused = find.byWidgetPredicate(
      (w) => w is EditableText && w.focusNode.hasFocus,
    );
    expect(focused, findsNothing, reason: 'no field has the focus');

    // Nothing was kept.
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    expect(prefs.getBool('isLoggedIn'), isNot(true));
    expect(prefs.getString('sessionId'), isNull);
  });
}
