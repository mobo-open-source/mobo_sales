import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/reset_password_service.dart';

/// Stands in for the part of Odoo the reset flow talks to.
///
/// [postBody] is what the reset POST answers with, which is where every
/// interesting outcome shows up: Odoo re-renders the same form and reports
/// what happened in an alert banner.
Future<HttpServer> _fakeOdoo({required String postBody}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(
    server.forEach((req) async {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.html;
      req.response.write(
        req.method == 'POST'
            ? postBody
            : '<!DOCTYPE html><html><body><form>'
                  '<input name="csrf_token" value="tok123"/>'
                  '<input name="login" type="email"/>'
                  '</form></body></html>',
      );
      await req.response.close();
    }),
  );
  return server;
}

Future<Map<String, dynamic>> _reset(HttpServer server) =>
    ResetPasswordService.sendResetPasswordEmail(
      serverUrl: 'http://127.0.0.1:${server.port}',
      database: 'mobo2',
      login: 'ada@example.com',
    );

void main() {
  test('a mail server that cannot send is reported, not called sent', () async {
    // The case that reached a user: outgoing mail was disabled in Odoo, the
    // reset POST still came back 200, and the app announced "Email Sent!".
    // Odoo flags it in an alert banner whose wording matches no phrase list,
    // so the banner's class is what has to be read.
    final server = await _fakeOdoo(
      postBody: '<!DOCTYPE html><html><body>'
          '<p class="alert alert-danger" role="alert">'
          'Connection refused by smtp.gmail.com'
          '</p></body></html>',
    );
    try {
      final result = await _reset(server);
      expect(result['success'], isFalse, reason: '${result['message']}');
      expect(result['message'], contains('smtp.gmail.com'));
    } finally {
      await server.close(force: true);
    }
  });

  test('an unknown login surfaces Odoo\'s own wording', () async {
    final server = await _fakeOdoo(
      postBody: '<!DOCTYPE html><html><body>'
          '<p class="alert alert-danger" role="alert">'
          'No account found for this login'
          '</p></body></html>',
    );
    try {
      final result = await _reset(server);
      expect(result['success'], isFalse);
      expect(result['message'], contains('No account found'));
    } finally {
      await server.close(force: true);
    }
  });

  test('a success banner is a success', () async {
    final server = await _fakeOdoo(
      postBody: '<!DOCTYPE html><html><body>'
          '<p class="alert alert-success" role="alert">'
          'An email has been sent with instructions'
          '</p></body></html>',
    );
    try {
      final result = await _reset(server);
      expect(result['success'], isTrue, reason: '${result['message']}');
    } finally {
      await server.close(force: true);
    }
  });

  test('a page confirming nothing is not treated as sent', () async {
    final server = await _fakeOdoo(
      postBody: '<!DOCTYPE html><html><body><p>ok</p></body></html>',
    );
    try {
      final result = await _reset(server);
      expect(result['success'], isFalse);
      expect(result['message'], isNot(contains('sent successfully')));
    } finally {
      await server.close(force: true);
    }
  });

  test('a server that cannot be reached fails with a message', () async {
    final server = await _fakeOdoo(postBody: '');
    final url = 'http://127.0.0.1:${server.port}';
    await server.close(force: true);

    final result = await ResetPasswordService.sendResetPasswordEmail(
      serverUrl: url,
      database: 'mobo2',
      login: 'ada@example.com',
    );
    expect(result['success'], isFalse);
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
