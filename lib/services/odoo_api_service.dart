import 'dart:convert';
import 'package:http/http.dart' as http;
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
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': {},
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return [];
      }

      final data = jsonDecode(response.body);
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
      final sessionUri = Uri.parse('$baseUrl/web/session/get_session_info');
      final sessionResponse = await http
          .post(
            sessionUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': {},
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (sessionResponse.statusCode == 200) {
        final sessionData = jsonDecode(sessionResponse.body);
        final db = sessionData['result']?['db'];
        if (db != null && db is String && db.isNotEmpty) {
          return db;
        }
      }

      final loginUri = Uri.parse('$baseUrl/web/login');
      final loginResponse = await http
          .get(loginUri)
          .timeout(const Duration(seconds: 10));

      if (loginResponse.statusCode == 200) {
        final html = loginResponse.body;

        final patterns = [
          RegExp(r'"db"\s*:\s*"([^"]+)"'),
          RegExp(r'data-database="([^"]+)"'),
          RegExp(r'<input[^>]*name="db"[^>]*value="([^"]+)"'),
        ];

        for (final pattern in patterns) {
          final match = pattern.firstMatch(html);
          if (match != null && match.group(1) != null) {
            final db = match.group(1)!;
            return db;
          }
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}
