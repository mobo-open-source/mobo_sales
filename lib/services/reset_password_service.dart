import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Sends an Odoo "reset password" email through the server's own
/// `/web/reset_password` page, which is the same on Odoo 17 through 20.
///
/// The page is driven the way a browser does: bind a session to the database,
/// load the form for its CSRF token and hidden fields, post the login back,
/// and read Odoo's alert banner for the outcome.
class ResetPasswordService {
  static const _sent =
      'Password reset email sent successfully. Please check your email for '
      'reset instructions.';

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like '
      'Gecko) Chrome/114.0.0.0 Mobile Safari/537.36';

  static Future<Map<String, dynamic>> sendResetPasswordEmail({
    required String serverUrl,
    required String database,
    required String login,
  }) async {
    try {
      var cleanUrl = serverUrl.trim();
      if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
        cleanUrl = 'https://$cleanUrl';
      }
      while (cleanUrl.endsWith('/')) {
        cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
      }
      return await _resetThroughWebForm(
        cleanUrl,
        database.trim(),
        login.trim(),
      );
    } on TimeoutException {
      return _failure(
        'Request timeout. Please check your internet connection and try again.',
      );
    } on SocketException {
      return _failure('Network error. Please check your internet connection.');
    } on http.ClientException {
      return _failure(
        'Could not reach the server. Please check the server URL and your '
        'internet connection.',
      );
    } catch (_) {
      return _failure(
        'Unable to reset password automatically. Please try again later or '
        'contact your administrator.',
      );
    }
  }

  static Map<String, dynamic> _failure(String message) => {
    'success': false,
    'message': message,
  };

  static Future<Map<String, dynamic>> _resetThroughWebForm(
    String baseUrl,
    String database,
    String login,
  ) async {
    final dbQuery = database.isNotEmpty
        ? '&db=${Uri.encodeQueryComponent(database)}'
        : '';
    final loginUrl = '$baseUrl/web/login?redirect=/web/login$dbQuery';
    final resetUrl = '$baseUrl/web/reset_password?redirect=/web/login$dbQuery';
    final cookies = <String, String>{};

    // Bind the session to the database first. On a multi-database server Odoo
    // sets no session until one is picked, /web/reset_password then answers
    // 404, and the CSRF token it renders belongs to that session. Both
    // `/web/login?db=` and `/web?db=` select the database on 17 through 20
    // (`/odoo` exists only from 18, so it is not relied on).
    try {
      await _getFollowingRedirects(loginUrl, cookies);
      if (database.isNotEmpty && !cookies.containsKey('session_id')) {
        await _getFollowingRedirects(
          '$baseUrl/web?db=${Uri.encodeQueryComponent(database)}',
          cookies,
        );
      }
    } on http.ClientException {
      // Best effort: a single-database server needs no selection, and an
      // unreachable one fails on the form request below with a clear error.
    }

    final form = await _getFollowingRedirects(
      resetUrl,
      cookies,
      referer: loginUrl,
    );
    if (form.statusCode == 404) {
      return _failure(
        'Password reset is not enabled on this server. Please contact your '
        'administrator.',
      );
    }
    if (form.statusCode != 200) {
      return _failure(
        'Unable to load the reset form (status ${form.statusCode}). Please '
        'try again later.',
      );
    }

    final fields = _hiddenFields(form.body);
    final csrf = _extractCsrfToken(form.body);
    if (csrf != null) fields['csrf_token'] = csrf;
    fields['login'] = login;
    fields.putIfAbsent('redirect', () => '/web/login');

    final request = http.Request('POST', Uri.parse(resetUrl))
      ..followRedirects = false
      ..headers.addAll({
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': _userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Origin': baseUrl,
        'Referer': resetUrl,
        if (cookies.isNotEmpty)
          'Cookie': cookies.entries
              .map((e) => '${e.key}=${e.value}')
              .join('; '),
      })
      ..bodyFields = fields;

    final client = http.Client();
    http.Response response;
    try {
      response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 30)),
      );
    } finally {
      client.close();
    }

    final setCookie = response.headers['set-cookie'];
    if (setCookie != null) cookies.addAll(_parseCookies(setCookie));

    // A redirect after the POST is not a confirmation: Odoo answers a sent
    // reset with the form re-rendered (200) and redirects only to somewhere
    // else, such as the database selector. Read where it led.
    if (response.statusCode >= 300 && response.statusCode < 400) {
      final location = response.headers['location'];
      if (location == null) {
        return _failure(
          'The server did not confirm a reset email was sent. Please contact '
          'your administrator.',
        );
      }
      response = await _getFollowingRedirects(
        Uri.parse(resetUrl).resolve(location).toString(),
        cookies,
        referer: resetUrl,
      );
    }

    if (response.statusCode == 400) {
      return _failure(
        'The server rejected the request (session or security token '
        'expired). Please try again.',
      );
    }

    // Odoo's own banner carries every outcome — unknown login, a mail server
    // that cannot send, a captcha refusal, success — in the server's wording.
    final banner = _alertBanner(response.body);
    if (banner != null) {
      if (banner.isError) {
        return _failure(
          banner.message.isNotEmpty
              ? banner.message
              : 'The server rejected the password reset request.',
        );
      }
      return {'success': true, 'message': _sent};
    }

    // No banner: Odoo re-renders the form on failure, so silence is not
    // evidence the mail went out.
    return _failure(
      'The server did not confirm a reset email was sent. Please verify the '
      'email address and try again, or contact your administrator.',
    );
  }

  /// The `name -> value` of every hidden `<input>` on [html], whichever order
  /// its attributes come in.
  static Map<String, String> _hiddenFields(String html) {
    final fields = <String, String>{};
    for (final tag in RegExp(
      r'<input\b[^>]*>',
      caseSensitive: false,
    ).allMatches(html)) {
      final text = tag.group(0)!;
      String? attr(String name) {
        final m = RegExp(
          '\\b$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')',
          caseSensitive: false,
        ).firstMatch(text);
        return m == null ? null : (m.group(1) ?? m.group(2));
      }

      if (attr('type')?.toLowerCase() != 'hidden') continue;
      final name = attr('name');
      if (name == null || name.isEmpty || name == 'login') continue;
      fields[name] = _unescape(attr('value') ?? '');
    }
    return fields;
  }

  static String _unescape(String v) => v
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  static String? _extractCsrfToken(String html) {
    final patterns = [
      RegExp(
        r'<input[^>]*name=["\x27]csrf_token["\x27][^>]*value=["\x27]([^"\x27]*)["\x27]',
      ),
      RegExp(
        r'<input[^>]*value=["\x27]([^"\x27]*)["\x27][^>]*name=["\x27]csrf_token["\x27]',
      ),
      RegExp(
        r'<meta[^>]*name=["\x27]csrf-token["\x27][^>]*content=["\x27]([^"\x27]*)["\x27]',
      ),
      RegExp(r'"?csrf_token"?\s*[:=]\s*["\x27]([^"\x27]+)["\x27]'),
    ];
    for (final pattern in patterns) {
      final value = pattern.firstMatch(html)?.group(1);
      if (value != null && value.isNotEmpty) return _unescape(value);
    }
    return null;
  }

  /// Reads Odoo's own alert banner out of a reset response.
  ///
  /// Odoo reports every outcome the same way — unknown login, a mail server
  /// that will not send, success — as
  /// `<p class="alert alert-danger">reason</p>` or its `alert-success` twin.
  /// Keying on the class rather than on English phrases means an error nobody
  /// anticipated (an SMTP failure, say) is still recognised as an error, on a
  /// server in any language, and the server's own wording reaches the user.
  ///
  /// Returns `null` when the page carries no banner, which must not be read
  /// as success.
  static ({bool isError, String message})? _alertBanner(String html) {
    final match = RegExp(
      '<(?:p|div)[^>]*class=["\'][^"\']*alert-(danger|success)[^"\']*["\']'
      '[^>]*>(.*?)</(?:p|div)>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    if (match == null) return null;

    final text = match
        .group(2)!
        .replaceAll(RegExp('<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return (isError: match.group(1)!.toLowerCase() == 'danger', message: text);
  }

  static bool isValidEmail(String email) {
    return RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(email);
  }

  static Future<http.Response> _getFollowingRedirects(
    String url,
    Map<String, String> cookies, {
    String? referer,
    int maxHops = 5,
  }) async {
    var currentUrl = url;
    var currentReferer = referer;
    final visitedCookieState = <String, String>{};

    for (var hop = 0; hop <= maxHops; hop++) {
      final cookieHeaderNow = cookies.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');

      if (visitedCookieState[currentUrl] == cookieHeaderNow) {
        throw http.ClientException(
          'Redirect loop detected (same URL and cookies repeated)',
          Uri.parse(currentUrl),
        );
      }
      visitedCookieState[currentUrl] = cookieHeaderNow;

      final request = http.Request('GET', Uri.parse(currentUrl))
        ..followRedirects = false
        ..headers['User-Agent'] =
            'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36'
        ..headers['Accept'] =
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8';
      if (cookies.isNotEmpty) {
        request.headers['Cookie'] = cookies.entries
            .map((e) => '${e.key}=${e.value}')
            .join('; ');
      }
      if (currentReferer != null) {
        request.headers['Referer'] = currentReferer;
      }

      final client = http.Client();
      http.Response response;
      try {
        final streamedResponse = await client
            .send(request)
            .timeout(const Duration(seconds: 15));
        response = await http.Response.fromStream(streamedResponse);
      } finally {
        client.close();
      }

      final setCookie = response.headers['set-cookie'];
      if (setCookie != null) {
        cookies.addAll(_parseCookies(setCookie));
      }

      if (response.statusCode < 300 || response.statusCode >= 400) {
        return response;
      }

      final location = response.headers['location'];
      if (location == null) {
        return response;
      }

      currentReferer = currentUrl;
      currentUrl = location.startsWith('http')
          ? location
          : Uri.parse(currentUrl).resolve(location).toString();
    }

    throw http.ClientException('Too many redirects', Uri.parse(currentUrl));
  }

  static Map<String, String> _parseCookies(String cookieHeader) {
    final cookies = <String, String>{};
    final cookiePattern = RegExp(
      r'(?:(?<=^)|(?<=,\s))([^=;,\s]+)=([^;\r\n,]+)',
    );
    for (final match in cookiePattern.allMatches(cookieHeader)) {
      final name = match.group(1);
      final value = match.group(2);
      if (name != null && value != null) {
        cookies[name.trim()] = value.trim();
      }
    }
    return cookies;
  }
}
