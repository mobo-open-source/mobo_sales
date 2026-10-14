import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/reset_password_service.dart';

/// A stand-in for the part of Odoo the reset flow talks to: a login page that
/// redirects and sets the session cookie, a reset form that only answers a
/// request carrying that cookie (and, on a multi-database server, `db`), and a
/// reset POST that wants the form's CSRF token.
class _FakeOdoo {
  final knownLogins = {'ada@example.com'};
  late final HttpServer _server;
  final requests = <String>[];
  String? postedBody;

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server.forEach(_handle));
  }

  Future<void> stop() => _server.close(force: true);

  bool _hasSession(HttpRequest r) =>
      (r.headers.value('cookie') ?? '').contains('session_id=s1');

  Future<void> _handle(HttpRequest r) async {
    requests.add('${r.method} ${r.uri}');
    final path = r.uri.path;

    if (r.method == 'GET' && path == '/web/login') {
      // The first hop redirects and hands out the session.
      r.response
        ..statusCode = HttpStatus.found
        ..headers.set(
          'location',
          '/web/login/page${r.uri.query.isEmpty ? '' : '?${r.uri.query}'}',
        )
        ..headers.add('set-cookie', 'session_id=s1; Path=/; HttpOnly');
      await r.response.close();
      return;
    }
    if (r.method == 'GET' && path == '/web/login/page') {
      r.response
        ..statusCode = HttpStatus.ok
        ..write('<html><body>login</body></html>');
      await r.response.close();
      return;
    }
    if (path == '/web/reset_password') {
      if (!_hasSession(r) || r.uri.queryParameters['db'] != 'mydb') {
        r.response.statusCode = HttpStatus.badRequest;
        await r.response.close();
        return;
      }
      if (r.method == 'GET') {
        r.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(
            '<form method="post"><input type="hidden" name="csrf_token" value="tok123"/>'
            '<input name="login"/></form> reset password',
          );
        await r.response.close();
        return;
      }
      postedBody = await utf8.decoder.bind(r).join();
      final fields = Uri.splitQueryString(postedBody!);
      final ok =
          fields['csrf_token'] == 'tok123' &&
          knownLogins.contains(fields['login']);
      if (!ok) {
        r.response
          ..statusCode = HttpStatus.ok
          ..write('<div>User not found</div>');
        await r.response.close();
        return;
      }
      r.response
        ..statusCode = HttpStatus.seeOther
        ..headers.set('location', '/web/login?reset=1');
      await r.response.close();
      return;
    }

    r.response.statusCode = HttpStatus.notFound;
    await r.response.close();
  }
}

void main() {
  late _FakeOdoo odoo;

  setUp(() async {
    odoo = _FakeOdoo();
    await odoo.start();
  });

  tearDown(() => odoo.stop());

  test(
    'follows the login redirect, keeps the session and sends the reset',
    () async {
      final result = await ResetPasswordService.sendResetPasswordEmail(
        serverUrl: odoo.url,
        database: 'mydb',
        login: 'ada@example.com',
      );

      expect(result['success'], isTrue, reason: '${result['message']}');
      expect(result['message'], contains('Password reset email sent'));

      // The redirect was followed, and the form was fetched with the database.
      expect(odoo.requests, contains(startsWith('GET /web/login/page')));
      expect(odoo.requests, contains(contains('GET /web/reset_password')));
      expect(odoo.requests.any((r) => r.contains('db=mydb')), isTrue);

      // The POST carried the login and the CSRF token read from the form.
      final fields = Uri.splitQueryString(odoo.postedBody!);
      expect(fields['login'], 'ada@example.com');
      expect(fields['csrf_token'], 'tok123');
    },
  );

  test('an unknown login is reported, not announced as sent', () async {
    final result = await ResetPasswordService.sendResetPasswordEmail(
      serverUrl: odoo.url,
      database: 'mydb',
      login: 'nobody@example.com',
    );

    expect(result['success'], isFalse);
  });

  test('a server that cannot be reached is a failure with a message', () async {
    final url = odoo.url;
    await odoo.stop();

    final result = await ResetPasswordService.sendResetPasswordEmail(
      serverUrl: url,
      database: 'mydb',
      login: 'ada@example.com',
    );

    expect(result['success'], isFalse);
    expect(result['message'], isA<String>());
    expect((result['message'] as String).isNotEmpty, isTrue);
  });

  group('isValidEmail', () {
    test('accepts an address and rejects the rest', () {
      expect(ResetPasswordService.isValidEmail('ada@example.com'), isTrue);
      expect(ResetPasswordService.isValidEmail('ada@example'), isFalse);
      expect(ResetPasswordService.isValidEmail(''), isFalse);
    });
  });
}
