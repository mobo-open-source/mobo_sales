import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/auth/auth_check.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/widgets/access_denied_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An Odoo that answers the two access questions, both with the same verdict.
class _Server {
  _Server({
    required this.inGroup,
    this.moduleInstalled = true,
    this.internal = true,
  });

  final bool inGroup;
  final bool internal;
  final bool moduleInstalled;
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
    dynamic result = [];
    Map<String, dynamic>? error;
    if (params['model'] == 'ir.model.data') {
      if (moduleInstalled) {
        result = ['ir.ui.menu', 1];
      } else {
        error = {
          'message': 'Odoo Server Error',
          'data': {
            'message':
                'External ID not found in the system: sale.sale_menu_root',
          },
        };
      }
    } else if (params['method'] == 'has_group') {
      final asked = (params['args'] as List).last;
      result = asked == 'base.group_user' ? internal : inGroup;
    }
    request.response
      // No kept-alive connection: its idle timer would outlive the test.
      ..persistentConnection = false
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': body['id'],
          if (error != null) 'error': error else 'result': result,
        }),
      );
    await request.response.close();
  }
}

void main() {
  setUpAll(() => HttpOverrides.global = null);

  Widget app() => MaterialApp(
    home: const AuthCheck(),
    routes: {
      '/login': (_) => const Scaffold(body: Text('LOGIN SCREEN')),
      '/server_setup': (_) => const Scaffold(body: Text('SERVER SETUP')),
    },
  );

  /// Lets the real network answer, then lets the app react to it. The app start
  /// asks the server twice, in turn: the subscription, then the Sales access.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> signedInTo(_Server server) async {
    SharedPreferences.setMockInitialValues({
      'isLoggedIn': true,
      'hasSeenGetStarted': true,
      'lastUrl': server.url,
      'lastDatabase': 'shop',
      'lastUsername': 'light',
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

  testWidgets('a saved session that lost Sales access never reaches the app', (
    tester,
  ) async {
    final server = _Server(inGroup: false);
    await tester.runAsync(server.start);
    addTearDown(() => tester.runAsync(server.stop));
    await signedInTo(server);

    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.byType(AccessDeniedDialog), findsOneWidget);
    expect(find.text('Access Denied'), findsOneWidget);
    expect(find.text('LOGIN SCREEN'), findsNothing, reason: 'not before OK');

    await tester.tap(find.text('Back to Login'));
    await settle(tester);

    expect(find.text('LOGIN SCREEN'), findsOneWidget);
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    expect(prefs.getBool('isLoggedIn'), isNot(true), reason: 'signed out');
    expect(prefs.getString('sessionId'), isNull);
  });

  testWidgets('a database that lost the Sales module says so', (tester) async {
    final server = _Server(inGroup: false, moduleInstalled: false);
    await tester.runAsync(server.start);
    addTearDown(() => tester.runAsync(server.stop));
    await signedInTo(server);

    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('Module Missing'), findsOneWidget);
    await tester.tap(find.text('Back to Login'));
    await settle(tester);
    expect(find.text('LOGIN SCREEN'), findsOneWidget);
  });

  testWidgets('a saved session of a portal user is refused as such', (
    tester,
  ) async {
    final server = _Server(inGroup: false, internal: false);
    await tester.runAsync(server.start);
    addTearDown(() => tester.runAsync(server.stop));
    await signedInTo(server);

    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('Portal Access Not Allowed'), findsOneWidget);
    expect(find.text('Back to Login'), findsOneWidget);
    await tester.tap(find.text('Back to Login'));
    await settle(tester);
    expect(find.text('LOGIN SCREEN'), findsOneWidget);
  });
}
