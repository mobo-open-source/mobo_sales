import 'dart:convert' as convert;
import 'package:http/http.dart' as http;
import 'package:odoo_rpc/odoo_rpc.dart';
import 'odoo_session_manager.dart';

class OdooApiService {
  static final OdooApiService _instance = OdooApiService._internal();
  factory OdooApiService() => _instance;
  OdooApiService._internal();

  int? _uid;
  String? _sessionId;
  String? _baseUrl;
  String? _database;
  String? _password;

  int? get uid => _uid;

  void updateSession(OdooSessionModel session) {
    _uid = session.userId;
    _sessionId = session.sessionId;
    _baseUrl = session.serverUrl;
    _database = session.database;
    _password = session.password;
  }

  Future<List<String>> listDatabasesForUrl(String baseUrl) async {
    try {
      final uri = Uri.parse('$baseUrl/web/database/list');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: convert.jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': {},
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return [];
      }

      final data = convert.jsonDecode(response.body);
      if (data['result'] is List) {
        final databases = List<String>.from(data['result']);
        return databases;
      }

      return [];
    } catch (e) {
      if (e.toString().contains('ACCESS_DENIED') ||
          e.toString().contains('list_db')) {
        throw Exception('ACCESS_DENIED_DB_LIST');
      }
      return [];
    }
  }

  static Future<String?> getDefaultDatabase(String baseUrl) async {
    try {
      String cleanUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;

      if (cleanUrl.endsWith('/odoo')) {
        cleanUrl = cleanUrl.substring(0, cleanUrl.length - 5);
      }

      final client = http.Client();

      String cookieHeader = '';

      try {
        String _mergeCookies(String? setCookie, String current) {
          if (setCookie == null || setCookie.isEmpty) return current;

          final Map<String, String> cookiesMap = {};

          if (current.isNotEmpty) {
            final split = current.split(';');
            for (var part in split) {
              final pair = part.trim().split('=');
              if (pair.length >= 2) {
                cookiesMap[pair[0].trim()] = pair[1].trim();
              }
            }
          }

          final newCookies = setCookie.split(RegExp(r',(?=[^;]+?=)'));
          for (var cookie in newCookies) {
            final firstPart = cookie.split(';')[0].trim();
            final pair = firstPart.split('=');
            if (pair.length >= 2) {
              final name = pair[0].trim();
              final value = pair[1].trim();

              if (name == 'session_id' ||
                  name == 'db' ||
                  name == 'last_used_database') {
                cookiesMap[name] = value;
              }
            }
          }

          return cookiesMap.entries
              .map((e) => '${e.key}=${e.value}')
              .join('; ');
        }

        final warmRoot = await client.get(
          Uri.parse('$cleanUrl/'),
          headers: {'User-Agent': _userAgent},
        );

        cookieHeader = _mergeCookies(
          warmRoot.headers['set-cookie'],
          cookieHeader,
        );

        final dbFromRoot =
            _extractDbFromHtml(warmRoot.body) ??
            _extractDbFromCookies(warmRoot.headers['set-cookie']);
        if (dbFromRoot != null) return dbFromRoot;

        final warmOdoo = await client.get(
          Uri.parse('$cleanUrl/odoo'),
          headers: {'User-Agent': _userAgent},
        );

        cookieHeader = _mergeCookies(
          warmOdoo.headers['set-cookie'],
          cookieHeader,
        );

        final dbFromOdoo =
            _extractDbFromHtml(warmOdoo.body) ??
            _extractDbFromCookies(warmOdoo.headers['set-cookie']);
        if (dbFromOdoo != null) return dbFromOdoo;

        final warmLogin = await client.get(
          Uri.parse('$cleanUrl/web/login'),
          headers: {'User-Agent': _userAgent},
        );

        cookieHeader = _mergeCookies(
          warmLogin.headers['set-cookie'],
          cookieHeader,
        );

        final dbFromLogin =
            _extractDbFromHtml(warmLogin.body) ??
            _extractDbFromCookies(warmLogin.headers['set-cookie']);
        if (dbFromLogin != null) return dbFromLogin;

        Future<String?> _tryRedirectProbe(String path, String cookies) async {
          final uri = Uri.parse('$cleanUrl$path');

          final req = http.Request('GET', uri)
            ..followRedirects = false
            ..headers.addAll({
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'User-Agent': _userAgent,
            });
          final streamed = await client.send(req);
          final status = streamed.statusCode;
          final loc =
              streamed.headers['location'] ?? streamed.headers['Location'];

          if ((status == 302 ||
                  status == 303 ||
                  status == 307 ||
                  status == 308) &&
              loc != null) {
            try {
              final locUri = Uri.parse(
                loc.startsWith('http') ? loc : ('$cleanUrl$loc'),
              );
              final redirectParam = locUri.queryParameters['redirect'];
              if (redirectParam != null && redirectParam.isNotEmpty) {
                final inner = Uri.parse(redirectParam);
                final dbParam = inner.queryParameters['db'];
                if (dbParam != null && dbParam.isNotEmpty) {
                  return dbParam;
                }
              }

              final dbParam = locUri.queryParameters['db'];
              if (dbParam != null && dbParam.isNotEmpty) {
                return dbParam;
              }

              if (locUri.path.contains('/web/login')) {
                final loginResp = await client.get(
                  locUri,
                  headers: {
                    if (cookies.isNotEmpty) 'Cookie': cookies,
                    'Accept':
                        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                    'Accept':
                        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                    'User-Agent': _userAgent,
                  },
                );
                if (loginResp.statusCode >= 200 && loginResp.statusCode < 300) {
                  final body = loginResp.body;
                  final db = _extractDbFromHtml(body);
                  if (db != null) {
                    return db;
                  }
                }
              }
            } catch (_) {}
          } else if (status >= 200 && status < 300) {
            try {
              final resp = await http.Response.fromStream(streamed);
              final body = resp.body;

              final db = _extractDbFromHtml(body);
              if (db != null) {
                return db;
              }
            } catch (e) {}
          }
          return null;
        }

        final dbFromRedirect =
            await _tryRedirectProbe('/web/database/selector', cookieHeader) ??
            await _tryRedirectProbe('/odoo', cookieHeader) ??
            await _tryRedirectProbe('/', cookieHeader);
        if (dbFromRedirect != null && dbFromRedirect.isNotEmpty) {
          return dbFromRedirect;
        }

        Future<String?> _trySessionInfo(String base, String cookies) async {
          final uri = Uri.parse('$base/web/session/get_session_info');

          final resp = await client.post(
            uri,
            headers: {
              if (cookies.isNotEmpty) 'Cookie': cookies,
              'Content-Type': 'application/json',
              'Accept': 'application/json, text/javascript, */*; q=0.01',
              'X-Requested-With': 'XMLHttpRequest',
              'Referer': '$base/web/login',
              'User-Agent': _userAgent,
            },
            body: convert.jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': {},
            }),
          );

          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            try {
              final json = convert.jsonDecode(resp.body);
              if (json is Map) {
                final result = json['result'];
                final sessionInfo = (result is Map
                    ? (result['session_info'] ?? result)
                    : null);
                final direct = (sessionInfo is Map
                    ? sessionInfo['db']
                    : (json['db'] ?? json['session_info']?['db']));
                if (direct is String && direct.isNotEmpty) {
                  return direct;
                }

                final scraped = _extractDbFromHtml(resp.body);
                if (scraped != null) return scraped;
              }
            } catch (e) {
              final scraped = _extractDbFromHtml(resp.body);
              if (scraped != null) return scraped;
            }
          }
          return null;
        }

        String? dbFromSession = await _trySessionInfo(cleanUrl, cookieHeader);
        if (dbFromSession == null) {
          dbFromSession = await _trySessionInfo('$cleanUrl/odoo', cookieHeader);
        }
        if (dbFromSession == null) {
          Future<String?> trySessionInfoGet(String base, String cookies) async {
            final uri = Uri.parse('$base/web/session/get_session_info');

            final resp = await client.get(
              uri,
              headers: {
                if (cookies.isNotEmpty) 'Cookie': cookies,
                'Accept': 'application/json, text/javascript, */*; q=0.01',
                'X-Requested-With': 'XMLHttpRequest',
                'Referer': '$base/web/login',
                'User-Agent': _userAgent,
              },
            );

            if (resp.statusCode >= 200 && resp.statusCode < 300) {
              try {
                final json = convert.jsonDecode(resp.body);
                if (json is Map) {
                  final direct = (json['db'] ?? json['session_info']?['db']);
                  if (direct is String && direct.isNotEmpty) {
                    return direct;
                  }
                  final scraped = _extractDbFromHtml(resp.body);
                  if (scraped != null) return scraped;
                }
              } catch (e) {
                final scraped = _extractDbFromHtml(resp.body);
                if (scraped != null) return scraped;
              }
            }
            return null;
          }

          dbFromSession =
              await trySessionInfoGet(cleanUrl, cookieHeader) ??
              await trySessionInfoGet('$cleanUrl/odoo', cookieHeader);
        }
        if (dbFromSession != null && dbFromSession.isNotEmpty) {
          return dbFromSession;
        }
      } finally {
        client.close();
      }

      try {
        final rpcClient = OdooClient(cleanUrl);

        final info = await rpcClient.callRPC(
          '/web/session/get_session_info',
          'call',
          {},
        );
        if (info is Map &&
            info['db'] is String &&
            (info['db'] as String).isNotEmpty) {
          return info['db'] as String;
        }
      } catch (_) {}

      final probeDb = await _probeDbWithRpc(cleanUrl, cookies: cookieHeader);
      if (probeDb != null) return probeDb;
    } catch (e) {
      try {
        final probeDb = await _probeDbWithRpc(baseUrl);
        if (probeDb != null) return probeDb;
      } catch (_) {}
    }
    return null;
  }
  static String? _extractDbFromCookies(String? setCookie) {
    if (setCookie == null) return null;

    final matchLast = RegExp(
      r'last_used_database=([^;]+)',
    ).firstMatch(setCookie);
    if (matchLast != null) {
      final db = matchLast.group(1)?.trim();
      if (db != null && db.isNotEmpty && db != 'null' && db != 'false') {
        return db;
      }
    }

    final matchDb = RegExp(r'db=([^;]+)').firstMatch(setCookie);
    if (matchDb != null) {
      final db = matchDb.group(1)?.trim();
      if (db != null && db.isNotEmpty && db != 'null' && db != 'false') {
        return db;
      }
    }

    return null;
  }
  static String? _extractDbFromHtml(String body) {
    try {
      final assignmentMatch = RegExp(
        r'odoo\.__session_info__\s*=\s*(\{[\s\S]*?\});',
      ).firstMatch(body);
      if (assignmentMatch != null) {
        final jsonStr = assignmentMatch.group(1);
        if (jsonStr != null) {
          try {
            final data = convert.jsonDecode(jsonStr);
            if (data is Map) {
              if (data['db'] is String && (data['db'] as String).isNotEmpty) {
                return data['db'];
              }
            }
          } catch (e) {}
        }
      }

      final scriptRe = RegExp(r'<script[^>]*>([\s\S]*?)<\/script>');
      for (final match in scriptRe.allMatches(body)) {
        final content = match.group(1);
        if (content == null || content.isEmpty) continue;

        if (content.trim().startsWith('{')) {
          try {
            final data = convert.jsonDecode(content.trim());
            if (data is Map &&
                data['db'] is String &&
                (data['db'] as String).isNotEmpty) {
              return data['db'];
            }
          } catch (_) {}
        }

        final dbMatch = RegExp(
          r'''['"]db['"]\s*:\s*['"]([^'"]+)['"]''',
        ).firstMatch(content);
        if (dbMatch != null) {
          final db = dbMatch.group(1);
          if (db != null && db.isNotEmpty && db != 'null' && db != 'false') {
            return db;
          }
        }
      }

      final inputRe = RegExp(
        r'''<input[^>]*name=['"]db['"][^>]*value=['"]([^'"]+)['"]''',
        caseSensitive: false,
      );
      final inputMatch = inputRe.firstMatch(body);
      if (inputMatch != null) {
        final db = inputMatch.group(1);
        if (db != null && db.isNotEmpty) {
          return db;
        }
      }

      final inputRe2 = RegExp(
        r'''<input[^>]*value=['"]([^'"]+)['"][^>]*name=['"]db['"]''',
        caseSensitive: false,
      );
      final inputMatch2 = inputRe2.firstMatch(body);
      if (inputMatch2 != null) {
        final db = inputMatch2.group(1);
        if (db != null && db.isNotEmpty) {
          return db;
        }
      }

      final selectRe1 = RegExp(
        r'''<select[^>]*name=['"]db['"][\s\S]*?<option[^>]*selected[^>]*>([^<]+)</option>''',
        caseSensitive: false,
      );
      final selectMatch1 = selectRe1.firstMatch(body);
      if (selectMatch1 != null) {
        final db = selectMatch1.group(1)?.trim();
        if (db != null && db.isNotEmpty) {
          return db;
        }
      }

      final selectRe2 = RegExp(
        r'''<select[^>]*name=['"]db['"][\s\S]*?<option[^>]*value=['"]([^'"]+)['"][^>]*selected[^>]*>''',
        caseSensitive: false,
      );
      final selectMatch2 = selectRe2.firstMatch(body);
      if (selectMatch2 != null) {
        final db = selectMatch2.group(1)?.trim();
        if (db != null && db.isNotEmpty) {
          return db;
        }
      }

      final globalRe = RegExp(r'''['"]db['"]\s*:\s*['"]([^'"]+)['"]''');
      for (final match in globalRe.allMatches(body)) {
        final db = match.group(1);

        if (db != null &&
            db.isNotEmpty &&
            db != 'null' &&
            db != 'false' &&
            db.length < 64 &&
            !db.contains('{')) {
          return db;
        }
      }

      final hrefRe = RegExp(
        r'''href=['"]/web\?db=([^"&']+)['"]''',
        caseSensitive: false,
      );
      final hrefMatch = hrefRe.firstMatch(body);
      if (hrefMatch != null) {
        final db = hrefMatch.group(1)?.trim();
        if (db != null && db.isNotEmpty) {
          return db;
        }
      }

      final dataDbRe = RegExp(
        r'''data-db=['"]([^"']+)['"]''',
        caseSensitive: false,
      );
      final dataDbMatch = dataDbRe.firstMatch(body);
      if (dataDbMatch != null) {
        final db = dataDbMatch.group(1)?.trim();
        if (db != null && db.isNotEmpty) {
          return db;
        }
      }

      final sessionInfoIndex = body.indexOf('session_info');
      if (sessionInfoIndex != -1) {
        final start = (sessionInfoIndex - 200) < 0
            ? 0
            : (sessionInfoIndex - 200);
        final end = (sessionInfoIndex + 1000) > body.length
            ? body.length
            : (sessionInfoIndex + 1000);
      } else {}
    } catch (_) {}
    return null;
  }
  static Future<String?> _probeDbWithRpc(
    String baseUrl, {
    String? cookies,
  }) async {
    final client = http.Client();
    try {
      final uri = Uri.parse('$baseUrl/web/session/get_session_info');

      String? extractOdooCookies(String? setCookie, [String? current]) {
        if (setCookie == null) return current;

        final Map<String, String> cookiesMap = {};

        if (current != null && current.isNotEmpty) {
          for (var part in current.split(';')) {
            final pair = part.trim().split('=');
            if (pair.length >= 2) {
              cookiesMap[pair[0].trim()] = pair[1].trim();
            }
          }
        }

        final newCookies = setCookie.split(RegExp(r',(?=[^;]+?=)'));
        for (var cookie in newCookies) {
          final firstPart = cookie.split(';')[0].trim();
          final pair = firstPart.split('=');
          if (pair.length >= 2) {
            final name = pair[0].trim();
            final value = pair[1].trim();
            if (name == 'session_id' ||
                name == 'db' ||
                name == 'last_used_database') {
              cookiesMap[name] = value;
            }
          }
        }

        if (cookiesMap.isEmpty) return null;
        return cookiesMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
      }

      Future<http.Response> doPost([String? cookie]) async {
        final merged = extractOdooCookies(cookie, cookies);

        final headers = {
          'Content-Type': 'application/json',
          'Accept':
              'application/json,application/pdf,application/octet-stream,*/*;q=0.8',
          'User-Agent': _userAgent,
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '$baseUrl/web',
          'Origin': baseUrl,
        };
        if (merged != null) {
          headers['Cookie'] = merged;
        }

        return client.post(
          uri,
          headers: headers,
          body: convert.jsonEncode({
            "jsonrpc": "2.0",
            "method": "call",
            "params": {},
            "id": 1,
          }),
        );
      }

      var response = await doPost();

      bool isSessionExpired = false;
      if (response.statusCode == 200) {
        try {
          final json = convert.jsonDecode(response.body);
          if (json is Map && json.containsKey('error')) {
            final error = json['error'];
            if (error is Map) {
              final code = error['code'];
              if (code == 100 ||
                  code == '100' ||
                  error['message']?.toString().contains('Session Expired') ==
                      true) {
                isSessionExpired = true;
              }
            }
          }
        } catch (_) {}
      }

      if (isSessionExpired) {
        final setCookie = response.headers['set-cookie'];
        final mergedCookies = extractOdooCookies(setCookie, cookies);

        if (mergedCookies != null) {
          try {
            final warmUri = Uri.parse('$baseUrl/web');
            await client
                .get(
                  warmUri,
                  headers: {
                    'User-Agent': _userAgent,
                    'Cookie': mergedCookies,
                    'X-Requested-With': 'XMLHttpRequest',
                  },
                )
                .timeout(const Duration(seconds: 5));
          } catch (e) {}

          response = await doPost(mergedCookies);
        } else {
          final cleanHeaders = {
            'Content-Type': 'application/json',
            'Accept':
                'application/json,application/pdf,application/octet-stream,*/*;q=0.8',
            'User-Agent': _userAgent,
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': '$baseUrl/web',
            'Origin': baseUrl,
          };
          response = await client.post(
            uri,
            headers: cleanHeaders,
            body: convert.jsonEncode({
              "jsonrpc": "2.0",
              "method": "call",
              "params": {},
              "id": 1,
            }),
          );
        }
      }

      if (response.statusCode == 200) {
        final body = response.body;
        final json = convert.jsonDecode(body);

        if (json is Map) {
          if (json.containsKey('result') && json['result'] is Map) {
            final result = json['result'] as Map;
            if (result['db'] is String && (result['db'] as String).isNotEmpty) {
              return result['db'];
            }

            if (result['session_info'] is Map &&
                result['session_info']['db'] is String) {
              final db = result['session_info']['db'] as String;
              if (db.isNotEmpty) {
                return db;
              }
            }
          }

          if (json['db'] is String && (json['db'] as String).isNotEmpty) {
            return json['db'];
          }
        }

        final scraped = _extractDbFromHtml(body);
        if (scraped != null) {
          return scraped;
        }
      }
    } finally {
      client.close();
    }
    return null;
  }
  static const String _userAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36";
}
