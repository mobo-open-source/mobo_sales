import 'dart:convert';
import 'package:http/http.dart' as http;

class ResetPasswordService {
  static Future<Map<String, dynamic>> sendResetPasswordEmail({
    required String serverUrl,
    required String database,
    required String login,
  }) async {
    try {
      String cleanUrl = serverUrl.trim();
      if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
        cleanUrl = 'https://$cleanUrl';
      }
      if (cleanUrl.endsWith('/')) {
        cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
      }

      final webFlowResult = await _tryWebInterfaceReset(
        cleanUrl,
        database,
        login,
      );

      if (webFlowResult['success'] == true) {
        return webFlowResult;
      }

      final possibleEndpoints = [
        '/web/reset_password',
        '/auth_signup/reset_password',
        '/web/signup',
        '/web/database/reset_password',
        '/auth_signup/signup',
      ];

      String? workingEndpoint;
      String? responseBody;
      Map<String, String>? cookies;
      bool requiresRecaptcha = false;

      for (final endpoint in possibleEndpoints) {
        try {
          final response = await http
              .get(
                Uri.parse('$cleanUrl$endpoint?db=$database'),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
                  'Accept':
                      'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
                  'Accept-Language': 'en-US,en;q=0.5',
                },
              )
              .timeout(Duration(seconds: 10));

          if (response.statusCode == 200) {
            final body = response.body.toLowerCase();

            bool isValidResetForm = false;

            if (body.contains('password') &&
                (body.contains('reset') || body.contains('forgot'))) {
              if (!body.contains('400 |') &&
                  !body.contains('404 |') &&
                  !body.contains('error')) {
                if (body.contains('<form') &&
                    (body.contains('name="login"') ||
                        body.contains('type="email"'))) {
                  isValidResetForm = true;
                }
              }
            }

            if (isValidResetForm) {
              workingEndpoint = endpoint;
              responseBody = response.body;

              requiresRecaptcha = _detectRecaptcha(response.body);

              final cookieHeader = response.headers['set-cookie'];
              if (cookieHeader != null) {
                cookies = _parseCookies(cookieHeader);
              }
              break;
            }
          }
        } catch (e) {
          continue;
        }
      }

      if (workingEndpoint == null) {
        return await _tryDirectApiReset(cleanUrl, database, login);
      }

      if (requiresRecaptcha) {
        return {
          'success': false,
          'message':
              'Unable to reset automatically due to server security (reCAPTCHA). Please try again later or contact your administrator.',
        };
      }

      final Map<String, String> formData = _extractAllFormData(
        responseBody!,
        login,
        database,
      );

      final headers = {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Accept-Encoding': 'gzip, deflate',
        'Origin': cleanUrl,
        'Referer': '$cleanUrl$workingEndpoint',
        'Upgrade-Insecure-Requests': '1',
      };

      if (cookies != null) {
        headers['Cookie'] = cookies.values.join('; ');
      }

      var response = await http
          .post(
            Uri.parse('$cleanUrl$workingEndpoint'),
            headers: headers,
            body: Uri(queryParameters: formData).query,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 400) {
        final simpleFormData = {
          'login': login,
          if (database.isNotEmpty) 'db': database,
          'redirect': '/web/login',
        };

        response = await http
            .post(
              Uri.parse('$cleanUrl$workingEndpoint'),
              headers: headers,
              body: Uri(queryParameters: simpleFormData).query,
            )
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 400 && database.isNotEmpty) {
          final urlWithDb = '$cleanUrl$workingEndpoint?db=$database';
          final formDataWithoutDb = Map<String, String>.from(formData);
          formDataWithoutDb.remove('db');

          response = await http
              .post(
                Uri.parse(urlWithDb),
                headers: {...headers, 'Referer': urlWithDb},
                body: Uri(queryParameters: formDataWithoutDb).query,
              )
              .timeout(const Duration(seconds: 30));

          if (response.statusCode == 400) {
            final minimalData = {'login': login};

            response = await http
                .post(
                  Uri.parse(urlWithDb),
                  headers: {...headers, 'Referer': urlWithDb},
                  body: Uri(queryParameters: minimalData).query,
                )
                .timeout(const Duration(seconds: 30));
          }
        }
      }

      if (response.statusCode == 302 || response.statusCode == 303) {
        final location = response.headers['location'];

        if (location != null) {
          try {
            final redirectUrl = location.startsWith('http')
                ? location
                : '$cleanUrl$location';
            final redirectResponse = await http
                .get(
                  Uri.parse(redirectUrl),
                  headers: {
                    'User-Agent': headers['User-Agent']!,
                    'Accept': headers['Accept']!,
                    if (cookies != null)
                      'Cookie': cookies.entries
                          .map((e) => '${e.key}=${e.value}')
                          .join('; '),
                  },
                )
                .timeout(const Duration(seconds: 30));

            final responseBody = redirectResponse.body.toLowerCase();
            if (_containsSuccessIndicators(responseBody)) {
              return {
                'success': true,
                'message':
                    'Password reset email sent successfully. Please check your email for reset instructions.',
              };
            } else if (_containsErrorIndicators(responseBody)) {
              return {
                'success': false,
                'message': 'User not found or invalid email address.',
              };
            }
          } catch (_) {
            // Following the redirect is best-effort; on failure fall through
            // to the generic result below.
          }
        }

        // The redirect revealed nothing either way; do not call that sent.
        return {
          'success': false,
          'message':
              'The server did not confirm a reset email was sent. Please contact your administrator.',
        };
      }

      if (response.statusCode == 200) {
        final responseBody = response.body.toLowerCase();

        if (_containsSuccessIndicators(responseBody)) {
          return {
            'success': true,
            'message':
                'Password reset email sent successfully. Please check your email for reset instructions.',
          };
        } else if (_containsErrorIndicators(responseBody)) {
          return {
            'success': false,
            'message': 'User not found or invalid email address.',
          };
        } else {
          if (responseBody.contains('<form') &&
              responseBody.contains('reset') &&
              responseBody.contains('password')) {
            return {
              'success': false,
              'message':
                  'Unable to send reset email. Please verify the email address is correct.',
            };
          }

          return {
            'success': false,
            'message':
                'The server did not confirm a reset email was sent. Please contact your administrator.',
          };
        }
      } else if (response.statusCode == 400) {
        final errorBody = response.body.toLowerCase();
        if (errorBody.contains('user not found') ||
            errorBody.contains('no user found')) {
          return {
            'success': false,
            'message': 'No user found with this email address.',
          };
        } else if (errorBody.contains('invalid email') ||
            errorBody.contains('invalid login')) {
          return {
            'success': false,
            'message': 'Please enter a valid email address.',
          };
        }

        return {
          'success': false,
          'message':
              'Unable to send reset email. Please verify your email address and try again.',
        };
      } else if (response.statusCode == 404) {
        return {
          'success': false,
          'message': 'Reset password service not available on this server.',
        };
      } else {
        return {
          'success': false,
          'message':
              'Failed to send reset email. Server returned status: ${response.statusCode}',
        };
      }
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        return {
          'success': false,
          'message':
              'Request timeout. Please check your internet connection and try again.',
        };
      } else if (e.toString().contains('SocketException')) {
        return {
          'success': false,
          'message': 'Network error. Please check your internet connection.',
        };
      } else {
        return {
          'success': false,
          'message': 'An error occurred: ${e.toString()}',
        };
      }
    }
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

  static bool _containsSuccessIndicators(String responseBody) {
    return responseBody.contains('password reset') ||
        responseBody.contains('email sent') ||
        responseBody.contains('check your email') ||
        responseBody.contains('reset link') ||
        responseBody.contains('instructions sent') ||
        responseBody.contains('email has been sent');
  }

  static bool _containsErrorIndicators(String responseBody) {
    return responseBody.contains('user not found') ||
        responseBody.contains('invalid email') ||
        responseBody.contains('error') ||
        responseBody.contains('not found') ||
        responseBody.contains('invalid user');
  }

  static bool isValidEmail(String email) {
    return RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(email);
  }

  static Map<String, String> _extractAllFormData(
    String html,
    String login,
    String database,
  ) {
    final Map<String, String> formData = {};

    formData['login'] = login;

    if (database.isNotEmpty) {
      formData['db'] = database;
    }

    formData['redirect'] = '/web/login';

    final inputPattern = RegExp(
      r'<input[^>]*name=["\x27]([^"\x27]+)["\x27][^>]*(?:value=["\x27]([^"\x27]*)["\x27])?[^>]*>',
      caseSensitive: false,
    );

    final matches = inputPattern.allMatches(html);
    for (final match in matches) {
      final name = match.group(1);
      final value = match.group(2) ?? '';

      if (name != null && name.isNotEmpty) {
        if (name.toLowerCase() == 'login') continue;

        if (name.toLowerCase().contains('token') ||
            name.toLowerCase().contains('csrf') ||
            name.toLowerCase() == 'db' ||
            name.toLowerCase() == 'redirect') {
          formData[name] = value;
        }
      }
    }

    final metaCsrfPattern = RegExp(
      r'<meta[^>]*name=["\x27]csrf-token["\x27][^>]*content=["\x27]([^"\x27]*)["\x27]',
      caseSensitive: false,
    );
    final metaMatch = metaCsrfPattern.firstMatch(html);
    if (metaMatch != null && metaMatch.group(1) != null) {
      formData['csrf_token'] = metaMatch.group(1)!;
    }

    final jsTokenPatterns = [
      RegExp(
        r'csrf_token["\x27]?\s*:\s*["\x27]([^"\x27]+)["\x27]',
        caseSensitive: false,
      ),
      RegExp(r'"csrf_token"\s*:\s*"([^"]+)"', caseSensitive: false),
      RegExp(
        r'var\s+csrf_token\s*=\s*["\x27]([^"\x27]+)["\x27]',
        caseSensitive: false,
      ),
    ];

    for (final pattern in jsTokenPatterns) {
      final match = pattern.firstMatch(html);
      if (match != null &&
          match.group(1) != null &&
          match.group(1)!.isNotEmpty) {
        formData['csrf_token'] = match.group(1)!;
        break;
      }
    }

    return formData;
  }

  static String? _extractCsrfToken(String html) {
    final patterns = [
      RegExp(
        r'<input[^>]*name=["\x27]csrf_token["\x27][^>]*value=["\x27]([^"\x27]*)["\x27]',
      ),
      RegExp(
        r'<meta[^>]*name=["\x27]csrf-token["\x27][^>]*content=["\x27]([^"\x27]*)["\x27]',
      ),
      RegExp(r'csrf_token["\x27]?\s*:\s*["\x27]([^"\x27]*)'),
      RegExp(r'"csrf_token"\s*:\s*"([^"]*)"'),
      RegExp(
        r'name=["\x27]csrf_token["\x27]\s+value=["\x27]([^"\x27]*)["\x27]',
      ),
      RegExp(
        r'value=["\x27]([^"\x27]*)["\x27]\s+name=["\x27]csrf_token["\x27]',
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null &&
          match.group(1) != null &&
          match.group(1)!.isNotEmpty) {
        return match.group(1);
      }
    }

    return null;
  }

  static bool _detectRecaptcha(String responseBody) {
    final body = responseBody.toLowerCase();

    final recaptchaIndicators = [
      'recaptcha',
      'grecaptcha',
      'google.com/recaptcha',
      'recaptcha_token_response',
      'data-sitekey',
      'g-recaptcha',
    ];

    for (String indicator in recaptchaIndicators) {
      if (body.contains(indicator)) {
        return true;
      }
    }

    return false;
  }

  static Future<Map<String, dynamic>> _tryDirectApiReset(
    String cleanUrl,
    String database,
    String login,
  ) async {
    try {
      final signupUrl = '$cleanUrl/auth_signup/signup';

      final signupBody = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'dbname': database,
          'login': login,
          'name': login,
          'password': '',
          'confirm_password': '',
          'redirect': '/web',
          'token': '',
          'type': 'reset',
        },
        'id': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await http
          .post(
            Uri.parse(signupUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(signupBody),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        if (responseData['error'] == null) {
          return {
            'success': true,
            'message':
                'Password reset email sent successfully. Please check your email for reset instructions.',
          };
        }
      }

      return await _tryWebInterfaceReset(cleanUrl, database, login);
    } catch (e) {
      return await _tryWebInterfaceReset(cleanUrl, database, login);
    }
  }

  static Future<Map<String, dynamic>> _tryWebInterfaceReset(
    String cleanUrl,
    String database,
    String login,
  ) async {
    try {
      final loginUrl = '$cleanUrl/web/login';
      final resetUrl = '$cleanUrl/web/reset_password';
      final dbQuery = database.isNotEmpty ? '&db=$database' : '';

      final Map<String, String> cookies = {};

      // Bind the session to a database first.
      //
      // On a multi-database server Odoo issues no session_id until a database
      // is picked, and /web/reset_password answers 404 without one — which
      // reads exactly like the reset feature being uninstalled. The form's
      // CSRF token is derived from the session too, so the POST would be
      // rejected even once the form loaded. `/odoo?db=` is what Odoo's own
      // database selector links to, and it sets the cookie on its 302.
      if (database.trim().isNotEmpty) {
        try {
          await _getFollowingRedirects(
            '$cleanUrl/odoo?db=${Uri.encodeQueryComponent(database.trim())}',
            cookies,
          );
        } catch (_) {
          // Best effort: a single-database server needs no selection.
        }
      }

      // Called for its side effect: adds to `cookies`.
      await _getFollowingRedirects(
        '$loginUrl?redirect=/web/login$dbQuery',
        cookies,
      );

      final resetGet = await _getFollowingRedirects(
        '$resetUrl?redirect=/web/login$dbQuery',
        cookies,
        referer: '$loginUrl?redirect=/web/login$dbQuery',
      );

      if (resetGet.statusCode != 200) {
        return {
          'success': false,
          'message':
              'Unable to load reset form automatically (status ${resetGet.statusCode}). Please try again later.',
        };
      }

      final csrfToken = _extractCsrfToken(resetGet.body);
      final formData = _extractAllFormData(resetGet.body, login, database);
      if (csrfToken != null && csrfToken.isNotEmpty) {
        formData['csrf_token'] = csrfToken;
      }

      formData['login'] = login;
      formData['redirect'] = '/web/login';
      final postHeaders = {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Origin': cleanUrl,
        'Referer': '$resetUrl?redirect=/web/login$dbQuery',
        if (cookies.isNotEmpty)
          'Cookie': cookies.entries
              .map((e) => '${e.key}=${e.value}')
              .join('; '),
      };

      final postRequest =
          http.Request(
              'POST',
              Uri.parse('$resetUrl?redirect=/web/login$dbQuery'),
            )
            ..followRedirects = false
            ..headers.addAll(postHeaders)
            ..body = Uri(queryParameters: formData).query;

      final postClient = http.Client();
      final http.Response postResponse;
      try {
        final streamedResponse = await postClient
            .send(postRequest)
            .timeout(const Duration(seconds: 30));
        postResponse = await http.Response.fromStream(streamedResponse);
      } finally {
        postClient.close();
      }

      if (postResponse.statusCode == 302 || postResponse.statusCode == 303) {
        return {
          'success': true,
          'message':
              'Password reset email sent successfully. Please check your email for reset instructions.',
        };
      }

      if (postResponse.statusCode == 200) {
        // Odoo's own banner first: it catches failures no phrase list
        // anticipates, such as a mail server that cannot send, and carries
        // the server's wording so the user sees the real reason.
        final banner = _alertBanner(postResponse.body);
        if (banner != null) {
          if (banner.isError) {
            return {
              'success': false,
              'message': banner.message.isNotEmpty
                  ? banner.message
                  : 'The server rejected the password reset request.',
            };
          }
          return {
            'success': true,
            'message': banner.message.isNotEmpty
                ? banner.message
                : 'Password reset email sent successfully. Please check your email for reset instructions.',
          };
        }

        final body = postResponse.body.toLowerCase();
        if (_containsSuccessIndicators(body)) {
          return {
            'success': true,
            'message':
                'Password reset email sent successfully. Please check your email for reset instructions.',
          };
        }
        if (_containsErrorIndicators(body)) {
          return {
            'success': false,
            'message': 'No user found with this email address.',
          };
        }

        // Neither a banner nor a recognised phrase. Odoo re-renders the reset
        // form on failure, so silence is not evidence the mail went out.
        return {
          'success': false,
          'message':
              'The server did not confirm a reset email was sent. Please contact your administrator.',
        };
      }

      return {
        'success': false,
        'message':
            'Unable to reset password automatically. Please try again later or contact your administrator.',
      };
    } catch (e) {
      return {
        'success': false,
        'message':
            'Unable to reset password automatically. Please try again later or contact your administrator.',
      };
    }
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
