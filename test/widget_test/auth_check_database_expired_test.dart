import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/auth/auth_check.dart';
import 'package:mobo_sales/main.dart' show navigatorKey;
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/utils/database_expiry.dart';
import 'package:mobo_sales/widgets/custom_snackbar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An Odoo whose session info says the subscription has expired, and which
/// notes what else was asked of it.
class _Server {
  final requests = <String>[];
  late HttpServer _http;

  String get url => 'http://127.0.0.1:${_http.port}';

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_http.forEach(_handle));
  }

  Future<void> stop() => _http.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
    final params = (body['params'] as Map?) ?? {};
    requests.add(request.uri.path);
    if (params['model'] != null)
      requests.add('${params['model']}.${params['method']}');

    dynamic result = [];
    if (request.uri.path == '/web/session/get_session_info') {
      result = {'uid': 7, 'expiration_date': '2020-01-01 00:00:00'};
    }
    request.response
      ..persistentConnection = false
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
      );
    await request.response.close();
  }
}

void main() {
  setUpAll(() => HttpOverrides.global = null);

  Widget app() => MaterialApp(
    navigatorKey: navigatorKey,
    home: const AuthCheck(),
    routes: {
      '/login': (_) => const Scaffold(body: Text('LOGIN SCREEN')),
      '/server_setup': (_) => const Scaffold(body: Text('SERVER SETUP')),
    },
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> signedInTo(_Server server, {bool withCredentials = true}) async {
    SharedPreferences.setMockInitialValues({
      'isLoggedIn': true,
      'hasSeenGetStarted': true,
      if (withCredentials) ...{
        'lastUrl': server.url,
        'lastDatabase': 'shop',
        'lastUsername': 'light',
      },
      'sessionId': 'sess123',
      'userLogin': 'light',
      'password': 'secret',
      'database': 'shop',
      'serverUrl': server.url,
      'userId': 7,
      'userName': 'Light',
      'serverVersion': '18.0',
      'expiresAt': DateTime.now()
          .add(const Duration(hours: 5))
          .toIso8601String(),
    });
    OdooSessionManager.clearClientCache();
  }

  testWidgets('a saved session whose database expired is signed out at the '
      'app start, and the sign-in screen says why, once', (tester) async {
    final server = _Server();
    await tester.runAsync(server.start);
    addTearDown(() => tester.runAsync(server.stop));
    await signedInTo(server);

    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('LOGIN SCREEN'), findsOneWidget);
    expect(find.text(DatabaseExpiredException.message), findsOneWidget);
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'a snackbar, not a dialog',
    );

    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    expect(prefs.getBool('isLoggedIn'), isNot(true), reason: 'signed out');
    expect(prefs.getString('sessionId'), isNull);
    // The first thing asked: the Sales access check never ran.
    expect(server.requests, contains('/web/session/get_session_info'));
    expect(server.requests, isNot(contains('res.users.has_group')));
    expect(
      server.requests,
      isNot(contains('ir.model.data.check_object_reference')),
    );

    CustomSnackbar.dismiss();
    await tester.pump();
  });

  testWidgets('with no saved sign-in details it lands on server setup', (
    tester,
  ) async {
    final server = _Server();
    await tester.runAsync(server.start);
    addTearDown(() => tester.runAsync(server.stop));
    await signedInTo(server, withCredentials: false);

    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('SERVER SETUP'), findsOneWidget);
    expect(find.text(DatabaseExpiredException.message), findsOneWidget);

    CustomSnackbar.dismiss();
    await tester.pump();
  });
}
