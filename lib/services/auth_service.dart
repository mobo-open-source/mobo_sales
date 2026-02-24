import 'dart:io';
import 'package:http/io_client.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'odoo_session_manager.dart';

/// Handles authentication operations against the Odoo server.
class AuthService {
  /// Authenticates the user and persists the session.
  Future<bool> loginAndSaveSession({
    required String serverUrl,
    required String database,
    required String userLogin,
    required String password,
  }) {
    return OdooSessionManager.loginAndSaveSession(
      serverUrl: serverUrl,
      database: database,
      userLogin: userLogin,
      password: password,
    );
  }

  /// Authenticates using an existing session ID instead of credentials.
  Future<bool> loginWithSessionId({
    required String serverUrl,
    required String database,
    required String userLogin,
    required String password,
    required String sessionId,
    Map<String, dynamic>? sessionInfo,
  }) {
    return OdooSessionManager.loginWithSessionId(
      serverUrl: serverUrl,
      database: database,
      userLogin: userLogin,
      password: password,
      sessionId: sessionId,
      sessionInfo: sessionInfo,
    );
  }

  /// Fetches the list of available databases from the given [baseUrl].
  Future<List<String>> fetchDatabaseList(String baseUrl) async {
    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    final ioClient = IOClient(httpClient);
    final client = OdooClient(baseUrl, httpClient: ioClient);

    try {
      final response = await client.callRPC('/web/database/list', 'call', {});
      return (response as List<dynamic>).map((db) => db.toString()).toList();
    } finally {
      client.close();
      ioClient.close();
      httpClient.close();
    }
  }
}
