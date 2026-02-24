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
              if (requiresRecaptcha) {}

              final cookieHeader = response.headers['set-cookie'];
              if (cookieHeader != null) {
                cookies = _parseCookies(cookieHeader);
              }
              break;
            } else {}
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
          } catch (e) {}
        }

        return {
          'success': true,
          'message':
              'Password reset email sent successfully. Please check your email for reset instructions.',
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
            'success': true,
            'message':
                'Password reset email sent successfully. Please check your email for reset instructions.',
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

  static bool isValidUrl(String url) {
    try {
      final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
      return uri.hasScheme && uri.hasAuthority;
    } catch (e) {
      return false;
    }
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
        } else {}
      } else {}

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

      final initialGet = await http
          .get(
            Uri.parse('$loginUrl?redirect=/web/login'),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (initialGet.statusCode != 200) {}

      Map<String, String> cookies = {};
      final initialSetCookie = initialGet.headers['set-cookie'];
      if (initialSetCookie != null) {
        cookies.addAll(_parseCookies(initialSetCookie));
      }

      final resetGet = await http
          .get(
            Uri.parse('$resetUrl?redirect=/web/login'),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
              if (cookies.isNotEmpty)
                'Cookie': cookies.entries
                    .map((e) => '${e.key}=${e.value}')
                    .join('; '),
              'Referer': '$loginUrl?redirect=/web/login',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (resetGet.statusCode != 200) {
        return {
          'success': false,
          'message':
              'Unable to load reset form automatically (status ${resetGet.statusCode}). Please try again later.',
        };
      }

      final resetSetCookie = resetGet.headers['set-cookie'];
      if (resetSetCookie != null) {
        cookies.addAll(_parseCookies(resetSetCookie));
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
        'Referer': '$resetUrl?redirect=/web/login',
        if (cookies.isNotEmpty)
          'Cookie': cookies.entries
              .map((e) => '${e.key}=${e.value}')
              .join('; '),
      };

      final postResponse = await http
          .post(
            Uri.parse('$resetUrl?redirect=/web/login'),
            headers: postHeaders,
            body: Uri(queryParameters: formData).query,
          )
          .timeout(const Duration(seconds: 30));

      if (postResponse.statusCode == 302 || postResponse.statusCode == 303) {
        return {
          'success': true,
          'message':
              'Password reset email sent successfully. Please check your email for reset instructions.',
        };
      }

      if (postResponse.statusCode == 200) {
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

        return {
          'success': true,
          'message':
              'Password reset email sent successfully. Please check your email for reset instructions.',
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
