import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;
import '../utils/odoo_binary.dart';
import '../utils/odoo_version.dart';
import '../utils/database_expiry.dart';
import 'sales_access.dart';

/// Value object that holds all data for an active Odoo user session.
class OdooSessionModel {
  final String sessionId;
  final String userLogin;
  final String password;
  final String serverUrl;
  final String database;
  final int? userId;
  final String? userName;
  final DateTime? expiresAt;
  final int? selectedCompanyId;
  final List<int> allowedCompanyIds;
  final String? serverVersion;

  OdooSessionModel({
    required this.sessionId,
    required this.userLogin,
    required this.password,
    required this.serverUrl,
    required this.database,
    this.userId,
    this.userName,
    this.expiresAt,
    this.selectedCompanyId,
    this.allowedCompanyIds = const [],
    this.serverVersion,
  });

  OdooSession get odooSession {
    return OdooSession(
      id: sessionId,
      userId: userId ?? 0,
      partnerId: 0,
      userLogin: userLogin,
      userName: userName ?? '',
      userLang: '',
      userTz: '',
      isSystem: false,
      dbName: database,
      serverVersion: serverVersion ?? '',
      companyId: selectedCompanyId ?? 0,
      allowedCompanies: allowedCompanyIds
          .map((id) => Company(id: id, name: 'Company $id'))
          .toList(),
    );
  }

  factory OdooSessionModel.fromOdooSession(
    OdooSession session,
    String userLogin,
    String password,
    String serverUrl,
    String database,
  ) {
    return OdooSessionModel(
      sessionId: session.id,
      userLogin: userLogin,
      password: password,
      serverUrl: serverUrl,
      database: database,
      userId: session.userId,
      userName: session.userName,

      expiresAt: DateTime.now().add(const Duration(hours: 24)),
      serverVersion: session.serverVersion,
    );
  }

  /// Returns a copy of this session with the specified fields replaced.
  OdooSessionModel copyWith({
    String? sessionId,
    String? userLogin,
    String? password,
    String? serverUrl,
    String? database,
    int? userId,
    String? userName,
    DateTime? expiresAt,
    int? selectedCompanyId,
    List<int>? allowedCompanyIds,
    String? serverVersion,
  }) {
    return OdooSessionModel(
      sessionId: sessionId ?? this.sessionId,
      userLogin: userLogin ?? this.userLogin,
      password: password ?? this.password,
      serverUrl: serverUrl ?? this.serverUrl,
      database: database ?? this.database,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      expiresAt: expiresAt ?? this.expiresAt,
      selectedCompanyId: selectedCompanyId ?? this.selectedCompanyId,
      allowedCompanyIds: allowedCompanyIds ?? this.allowedCompanyIds,
      serverVersion: serverVersion ?? this.serverVersion,
    );
  }

  /// Persists this session to `SharedPreferences`.
  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final biometricEnabled = prefs.getBool('biometric_enabled');

    await prefs.setString('sessionId', sessionId);
    await prefs.setString('userLogin', userLogin);
    await prefs.setString('password', password);
    await prefs.setString('database', database);
    await prefs.setString('serverUrl', serverUrl);
    if (userId != null) {
      await prefs.setInt('userId', userId!);
    } else {
      await prefs.remove('userId');
    }
    if (userName != null) {
      await prefs.setString('userName', userName!);
    }
    if (expiresAt != null) {
      await prefs.setString('expiresAt', expiresAt!.toIso8601String());
    }
    if (serverVersion != null) {
      await prefs.setString('serverVersion', serverVersion!);
    }
    if (selectedCompanyId != null) {
      await prefs.setInt('selected_company_id', selectedCompanyId!);
    }
    await prefs.setStringList(
      'selected_allowed_company_ids',
      allowedCompanyIds.map((e) => e.toString()).toList(),
    );
    await prefs.setBool('isLoggedIn', true);

    if (biometricEnabled != null) {
      await prefs.setBool('biometric_enabled', biometricEnabled);
    }
  }

  /// Restores a session from `SharedPreferences`, or returns `null` if none exists.
  static Future<OdooSessionModel?> fromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (!isLoggedIn) {
      return null;
    }

    final sessionId = prefs.getString('sessionId');
    final userLogin = prefs.getString('userLogin');
    final password = prefs.getString('password');
    final rawServerUrl = prefs.getString('serverUrl');
    final database = prefs.getString('database');
    final userId = prefs.getInt('userId');
    final userName = prefs.getString('userName');
    final expiresAtStr = prefs.getString('expiresAt');
    final serverVersion = prefs.getString('serverVersion');
    final selectedCompanyId = prefs.getInt('selected_company_id');
    final allowedCompanyIds =
        prefs
            .getStringList('selected_allowed_company_ids')
            ?.map((e) => int.tryParse(e) ?? -1)
            .where((e) => e > 0)
            .toList() ??
        [];

    if ([
      sessionId,
      userLogin,
      password,
      rawServerUrl,
      database,
    ].contains(null)) {
      return null;
    }

    String serverUrl = rawServerUrl!.trim();
    while (serverUrl.endsWith('/')) {
      serverUrl = serverUrl.substring(0, serverUrl.length - 1);
    }
    if (!serverUrl.startsWith('http://') && !serverUrl.startsWith('https://')) {
      serverUrl = 'https://$serverUrl';
    }

    final model = OdooSessionModel(
      sessionId: sessionId!,
      userLogin: userLogin!,
      password: password!,
      serverUrl: serverUrl,
      database: database!,
      userId: userId,
      userName: userName,
      expiresAt: expiresAtStr != null ? DateTime.tryParse(expiresAtStr) : null,
      selectedCompanyId: selectedCompanyId,
      allowedCompanyIds: allowedCompanyIds,
      serverVersion: serverVersion,
    );

    return model;
  }
}

/// HTTP client wrapper that enforces an overall timeout on every request,
/// bounding the wait for the server's response (which `connectionTimeout`
/// alone does not) so a stalled response can never hang the UI indefinitely.
class _TimeoutHttpClient extends http.BaseClient {
  _TimeoutHttpClient(this._inner, this._timeout);

  final http.Client _inner;
  final Duration _timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (OdooSessionManager.shouldSkipSessionRotation(
      OdooSessionManager.cachedServerGeneration,
    )) {
      request.headers.putIfAbsent(
        OdooSessionManager.skipSessionRotationHeader,
        () => '1',
      );
    }

    final response = await _inner.send(request).timeout(_timeout);

    final guarded = http.StreamedResponse(
      response.stream.timeout(
        _timeout,
        onTimeout: (sink) => sink.addError(
          TimeoutException('The server stopped responding', _timeout),
        ),
      ),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );

    // Every RPC of the app, whichever helper makes it, passes through here, so
    // this is the one place where Odoo 20's image objects can be turned back
    // into the base64 text the rest of the app reads. See odoo_binary.dart.
    if (_mayCarryBinaryObjects(request, response)) {
      return flattenOdooBinaryResponse(guarded);
    }
    return guarded;
  }

  static bool _mayCarryBinaryObjects(
    http.BaseRequest request,
    http.StreamedResponse response,
  ) {
    return odooResponseMayCarryBinaryObjects(
      method: request.method,
      url: request.url,
      statusCode: response.statusCode,
      generation: OdooSessionManager.cachedServerGeneration,
    );
  }

  /// Deliberately does nothing.
  ///
  /// [OdooSessionManager.ioClient] is a single process-wide transport shared
  /// by every `OdooClient` the app builds, and `OdooClient.close()` closes
  /// whatever http client it was handed. Closing it on behalf of one
  /// discarded client would disable every other caller for the rest of the
  /// process, with each later request failing as
  /// `ClientException: HTTP request failed. Client is already closed.` — a
  /// message that reads like a transport fault and sends everyone off to
  /// check a healthy network. The shared transport's lifetime is the
  /// process's. Clients that build their own http client still close it;
  /// only this shared one is exempt.
  @override
  void close() {}
}

/// Manages the low-level Odoo RPC client, session caching, and authentication.
class OdooSessionManager {
  static final http.BaseClient ioClient = _getHttpClient();

  /// Maximum time to wait for a server response before failing with a
  /// [TimeoutException]. Kept generous because creating a `sale.order` is a
  /// heavy server-side operation, but bounded so the UI never hangs forever.
  static const Duration _requestTimeout = Duration(seconds: 60);

  /// Maximum time to wait while establishing the TCP connection.
  static const Duration _connectionTimeout = Duration(seconds: 30);

  static http.BaseClient _getHttpClient() {
    final HttpClient client = HttpClient()
      ..connectionTimeout = _connectionTimeout
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true);
    return _TimeoutHttpClient(IOClient(client), _requestTimeout);
  }

  /// The header with which an Odoo 20 client opts out of session rotation.
  ///
  /// Odoo 19 and 20 move a logged-in session to a new id every three hours and
  /// delete the old one two minutes later (`SESSION_ROTATION_INTERVAL` and
  /// `SESSION_DELETION_TIMER`). The new id arrives only in a `Set-Cookie` that
  /// this app, which keeps its own copy of the id, never reads, so the session
  /// would die three hours after login and need a fresh sign-in, which a user
  /// with two-factor authentication cannot do silently. Odoo 20 added this
  /// request header for exactly such clients
  /// (`SESSION_ROTATION_INTERVAL_HEADER_SKIP` in odoo/http/session.py,
  /// "used by the mobile app", per its test). Odoo 19 and older ignore it.
  static const String skipSessionRotationHeader =
      'X-Odoo-Skip-Session-Rotation-Interval';

  /// Whether requests to a server of [generation] should carry
  /// [skipSessionRotationHeader]: Odoo 20 and later, and a server whose version
  /// is not known yet (the header is ignored where it means nothing).
  static bool shouldSkipSessionRotation(int generation) =>
      generation == 0 || generation >= 20;

  static const String USER_AGENT =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36";
  static const int _maxAttempts = 3;
  static const Duration _baseDelay = Duration(milliseconds: 500);

  static Completer<bool>? _refreshCompleter;

  static OdooClient? _cachedClient;
  static OdooSessionModel? _cachedSession;
  static DateTime? _lastAuthTime;
  static const Duration _cacheValidDuration = Duration(minutes: 5);

  static Function(OdooSessionModel)? _onSessionUpdated;
  static Function()? _onSessionCleared;

  static bool _isRetryableError(Object e) {
    if (e is SocketException) return true;
    if (e is TimeoutException) return true;
    if (e is http.ClientException) return true;

    final es = e.toString().toLowerCase();
    return es.contains('connection reset') ||
        es.contains('timed out') ||
        es.contains('connection refused');
  }

  /// Registers callbacks for session update and clear events.
  static void setSessionCallbacks({
    Function(OdooSessionModel)? onSessionUpdated,
    Function()? onSessionCleared,
  }) {
    _onSessionUpdated = onSessionUpdated;
    _onSessionCleared = onSessionCleared;
  }

  /// Returns the in-memory session without touching `SharedPreferences`.
  ///
  /// Null until a session has been loaded, so callers that need certainty must
  /// still use [getCurrentSession]; this exists for widgets that have to render
  /// synchronously and can fall back gracefully.
  static OdooSessionModel? get cachedSession => _cachedSession;

  /// Returns the current session from cache or `SharedPreferences`.
  static Future<OdooSessionModel?> getCurrentSession() async {
    if (_cachedSession != null) return _cachedSession;
    _cachedSession = await OdooSessionModel.fromPrefs();
    return _cachedSession;
  }

  /// The Odoo generation of the connected server (see [odooGeneration]), or 0
  /// when there is no session or the version cannot be read.
  ///
  /// This is what a capability check such as `odooUsesFormattedReadGroup`
  /// wants: it counts an Odoo 20 pre-release (`19.5a1`) as 20.
  static Future<int> serverGeneration() async {
    final session = await getCurrentSession();
    return odooGeneration(session?.serverVersion);
  }

  /// [serverGeneration] from the session already in memory, for code that
  /// cannot await. 0 until a session has been loaded.
  static int get cachedServerGeneration =>
      odooGeneration(_cachedSession?.serverVersion);

  /// Returns an authenticated `OdooClient`, building one from the cached session if needed.
  static Future<OdooClient?> getClient() async {
    final session = await getCurrentSession();
    if (session == null) {
      return null;
    }

    if (_cachedClient != null &&
        _lastAuthTime != null &&
        DateTime.now().difference(_lastAuthTime!) < _cacheValidDuration) {
      return _cachedClient;
    }

    final client = OdooClient(
      session.serverUrl,
      httpClient: ioClient,
      sessionId: session.odooSession,
    );

    bool sessionRestored = session.sessionId.isNotEmpty;
    if (sessionRestored) {}

    try {
      if (!sessionRestored && session.sessionId.isEmpty) {
        for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
          try {
            await client.authenticate(
              session.database,
              session.userLogin,
              session.password,
            );
            break;
          } catch (e) {
            if (e is FormatException && e.toString().contains('<html>')) {
              throw Exception(
                'Server returned HTML instead of JSON. Please check server URL and ensure Odoo is running.',
              );
            }

            if (attempt >= _maxAttempts || !_isRetryableError(e)) rethrow;
            final delay = _baseDelay * attempt;
            await Future.delayed(delay);
          }
        }
      } else {
        if (!sessionRestored) {
        } else {}
      }

      if (client.sessionId != null) {}

      _cachedClient = client;
      _lastAuthTime = DateTime.now();

      return client;
    } catch (e) {
      _cachedClient = null;
      _lastAuthTime = null;

      if (e.toString().contains(
        "type 'Null' is not a subtype of type 'Map<String, dynamic>'",
      )) {
        return client;
      }

      rethrow;
    }
  }

  /// Authenticates with credentials and saves the session to preferences.
  static Future<bool> loginAndSaveSession({
    required String serverUrl,
    required String database,
    required String userLogin,
    required String password,
  }) async {
    if (!serverUrl.startsWith('http://') && !serverUrl.startsWith('https://')) {
      throw Exception(
        'Invalid server URL format. Please include http:// or https://',
      );
    }

    try {
      final sessionModel = await authenticate(
        serverUrl: serverUrl,
        database: database,
        username: userLogin,
        password: password,
      );

      if (sessionModel == null) {
        return false;
      }

      await sessionModel.saveToPrefs();
      _cachedSession = sessionModel;

      if (_onSessionUpdated != null) {
        _onSessionUpdated!(sessionModel);
      }

      return true;
    } on DatabaseExpiredException {
      rethrow;
    } catch (e) {
      if (e is DatabaseExpiredException) rethrow;

      if (e is FormatException && e.toString().contains('<html>')) {
        throw Exception(
          'Server returned HTML instead of JSON. Please check server URL and ensure Odoo is running.',
        );
      }

      if (e is SalesAccessException) rethrow;

      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('mfa') ||
          errorStr.contains('two factor') ||
          errorStr.contains('2fa') ||
          errorStr.contains('totp') ||
          errorStr.contains('verification code required')) {
        rethrow;
      }

      return false;
    }
  }

  /// Clears all session preferences and invalidates the cached client.
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();

    const keysToRemove = <String>[
      'isLoggedIn',
      'sessionId',
      'userLogin',
      'password',
      'serverUrl',
      'database',
      'userId',
      'userName',
      'expiresAt',
      'serverVersion',
    ];
    for (final k in keysToRemove) {
      await prefs.remove(k);
    }

    try {
      await webview.CookieManager.instance().deleteAllCookies().timeout(
        const Duration(seconds: 3),
      );
    } catch (e) {}

    clearClientCache();
    _cachedSession = null;

    if (_onSessionCleared != null) {
      _onSessionCleared!();
    }
  }

  /// Invalidates the in-memory client and session cache.
  static void clearClientCache() {
    _cachedClient = null;
    _lastAuthTime = null;
    _cachedSession = null;
  }

  /// Saves [sessionModel] to preferences and resets the client cache.
  static Future<void> updateSession(OdooSessionModel sessionModel) async {
    try {
      await sessionModel.saveToPrefs();

      _cachedSession = sessionModel;

      clearClientCache();

      if (_onSessionUpdated != null) {
        _onSessionUpdated!(sessionModel);
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Authenticates using an existing [sessionId] without re-entering credentials.
  static Future<bool> loginWithSessionId({
    required String serverUrl,
    required String database,
    required String userLogin,
    required String password,
    required String sessionId,
    Map<String, dynamic>? sessionInfo,
  }) async {
    try {
      String normalizedUrl = serverUrl.trim();
      if (!normalizedUrl.startsWith('http://') &&
          !normalizedUrl.startsWith('https://')) {
        normalizedUrl = 'https://$normalizedUrl';
      }
      if (normalizedUrl.endsWith('/')) {
        normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 1);
      }
      if (normalizedUrl.endsWith('/odoo')) {
        normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 5);
      }

      final Map<String, dynamic> info =
          sessionInfo ?? await getSessionInfo(normalizedUrl, sessionId);

      if (info['uid'] == null || info['uid'] is bool) {
        throw Exception('Failed to get valid session info');
      }

      // The session info is in hand (the web view's, after a code was
      // accepted, or the one just fetched): the expiry is read from it, with no
      // request of its own, before anything is saved or cached.
      if (DatabaseExpiry.hasExpired(info['expiration_date'])) {
        throw const DatabaseExpiredException();
      }

      final int userId = info['uid'] is int
          ? info['uid']
          : int.parse(info['uid'].toString());
      final String serverVersion = info['server_version']?.toString() ?? '17.0';

      // Before a session is saved: a user without Sales access leaves no trace.
      await requireSalesAccess(
        url: normalizedUrl,
        sessionId: sessionId,
        database: database,
        userId: userId,
        serverVersion: serverVersion,
      );

      final userInfo = await _fetchUserCompanies(
        userId,
        url: normalizedUrl,
        sessionId: sessionId,
        database: database,
      );
      int? selectedCompanyId = userInfo['company_id'];
      List<int> allowedCompanyIds =
          (userInfo['company_ids'] as List<int>?) ?? [];

      selectedCompanyId ??= info['company_id'];
      if (allowedCompanyIds.isEmpty) {
        allowedCompanyIds = [selectedCompanyId ?? 1];
      }

      final client = OdooClient(
        normalizedUrl,
        httpClient: ioClient,
        sessionId: OdooSession(
          id: sessionId,
          userId: userId,
          partnerId: 0,
          userLogin: userLogin,
          userName: info['name'] ?? userLogin,
          userLang: '',
          userTz: '',
          isSystem: false,
          dbName: database,
          serverVersion: serverVersion,
          companyId: selectedCompanyId ?? 0,
          allowedCompanies: [],
        ),
      );

      final sessionModel = OdooSessionModel(
        sessionId: sessionId,
        userLogin: userLogin,
        password: password,
        serverUrl: normalizedUrl,
        database: database,
        userId: userId,
        userName: info['name'] ?? userLogin,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        selectedCompanyId: selectedCompanyId,
        allowedCompanyIds: allowedCompanyIds,
        serverVersion: serverVersion,
      );

      await sessionModel.saveToPrefs();
      _cachedSession = sessionModel;
      _cachedClient = client;
      _lastAuthTime = DateTime.now();

      _onSessionUpdated?.call(sessionModel);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);

      return true;
    } catch (e) {
      if (e is DatabaseExpiredException) rethrow;
      if (e is SalesAccessException) rethrow;
      return false;
    }
  }

  /// A [SalesRpc] that talks to [url] as [sessionId]: one POST per call, the
  /// whole JSON-RPC reply handed back — including an `error`, which carries the
  /// server's own exception name and message — and a throw only when the server
  /// cannot be reached.
  static SalesRpc _salesRpc(String url, String sessionId) {
    return (model, method, args) async {
      final res = await ioClient
          .post(
            Uri.parse('$url/web/dataset/call_kw'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'X-Requested-With': 'XMLHttpRequest',
              'User-Agent': USER_AGENT,
              'Origin': url,
              'Referer': '$url/web',
              'Cookie': 'session_id=$sessionId',
              'X-Openerp-Session-Id': sessionId,
            },
            body: jsonEncode(
              jsonRpcEnvelope({
                'model': model,
                'method': method,
                'args': args,
                'kwargs': <String, dynamic>{},
              }),
            ),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw Exception('RPC Session Error ${res.statusCode}');
      }
      final body = jsonDecode(res.body);
      return body is Map<String, dynamic> ? body : <String, dynamic>{};
    };
  }

  /// Throws a [SalesAccessException] unless the Sales module is installed on
  /// the server and the user [userId], signed in with [sessionId], belongs to
  /// the Sales group (see [SalesAccess]).
  ///
  /// [SalesAccessStatus.unverified] throws too, so an account is never let in
  /// on a guess.
  static Future<void> requireSalesAccess({
    required String url,
    required String sessionId,
    required String database,
    required int userId,
    required String serverVersion,
  }) async {
    final status = await SalesAccess.check(
      majorVersion: parseMajorVersion(serverVersion),
      userId: userId,
      rpc: _salesRpc(url, sessionId),
    ).catchError((_) => SalesAccessStatus.unverified);
    final problem = SalesAccessException.from(status);
    if (problem != null) throw problem;
  }

  /// Why the session saved on this device may no longer use the app, or null
  /// when it may.
  ///
  /// For the app start, where a user whose Sales access was taken away since
  /// the last sign-in — or whose database lost the Sales module — must not
  /// walk straight back in. Only a definite answer is a problem: no network,
  /// an expired session or a server error returns null and leaves the user
  /// where they were, as the app does offline everywhere else.
  static Future<SalesAccessException?> currentSessionAccessProblem({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final session = await getCurrentSession();
      final userId = session?.userId;
      if (session == null || userId == null) return null;
      final status = await SalesAccess.check(
        majorVersion: parseMajorVersion(session.serverVersion ?? ''),
        userId: userId,
        rpc: _salesRpc(session.serverUrl, session.sessionId),
      ).timeout(timeout);
      if (status == SalesAccessStatus.unverified) return null;
      return SalesAccessException.from(status);
    } catch (_) {
      return null;
    }
  }

  /// Whether the database behind the session saved on this device has expired.
  ///
  /// For the app start and the return to the app, where a subscription that
  /// ran out since the last sign-in must not be walked straight back into. Only
  /// a definite "expired" is true: no session, no network, a slow server or an
  /// answer nobody expected is false and leaves the user where they were.
  static Future<bool> currentSessionDatabaseExpired({
    Duration timeout = DatabaseExpiry.probeTimeout,
  }) async {
    try {
      final session = await getCurrentSession();
      final userId = session?.userId;
      if (session == null || userId == null) return false;
      final client = OdooClient(
        session.serverUrl,
        httpClient: ioClient,
        sessionId: OdooSession(
          id: session.sessionId,
          userId: userId,
          partnerId: 0,
          userLogin: session.userLogin,
          userName: session.userName ?? session.userLogin,
          userLang: '',
          userTz: '',
          isSystem: false,
          dbName: session.database,
          serverVersion: session.serverVersion ?? '',
          companyId: session.selectedCompanyId ?? 0,
          allowedCompanies: [],
        ),
      );
      return await DatabaseExpiry.isExpired(client, timeout: timeout);
    } catch (_) {
      return false;
    }
  }

  /// Fetches session metadata from the Odoo server for the given [sessionId].
  static Future<Map<String, dynamic>> getSessionInfo(
    String url,
    String sessionId,
  ) async {
    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final response = await ioClient.post(
          Uri.parse('$url/web/session/get_session_info'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'User-Agent': USER_AGENT,
            'Origin': url,
            'Referer': '$url/web',
            'Cookie': 'session_id=$sessionId',
          },
          body: jsonEncode({
            "jsonrpc": "2.0",
            "method": "call",
            "params": {},
            "id": 1,
          }),
        );

        if (response.statusCode != 200) {
          throw Exception('Failed to get session info: ${response.statusCode}');
        }

        final data = jsonDecode(response.body);
        if (data['error'] != null) {
          throw Exception(data['error']['message'] ?? 'Session info error');
        }
        return Map<String, dynamic>.from(data['result']);
      } catch (e) {
        if (attempt >= _maxAttempts || !_isRetryableError(e)) rethrow;
        await Future.delayed(_baseDelay * attempt);
      }
    }
    throw Exception('getSessionInfo failed after $_maxAttempts attempts');
  }

  /// Executes an RPC `call_kw` request authenticated by [sessionId].
  /// [payload] as the body Odoo's `/web/dataset/call_kw` accepts.
  ///
  /// The route reads its arguments from the `params` of a JSON-RPC request, so
  /// a bare `{model, method, args, kwargs}` reaches it with no arguments at all
  /// and fails. A payload that already carries `params` is a whole request and
  /// is sent as it is.
  @visibleForTesting
  static Map<String, dynamic> jsonRpcEnvelope(Map<String, dynamic> payload) {
    if (payload.containsKey('params')) return payload;
    return {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': payload,
      'id': DateTime.now().millisecondsSinceEpoch,
    };
  }

  static Future<dynamic> callKwWithSession({
    required String url,
    required String sessionId,
    required Map<String, dynamic> payload,
  }) async {
    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final res = await ioClient.post(
          Uri.parse('$url/web/dataset/call_kw'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'User-Agent': USER_AGENT,
            'Origin': url,
            'Referer': '$url/web',
            'Cookie': 'session_id=$sessionId',
            'X-Openerp-Session-Id': sessionId,
          },
          body: jsonEncode(jsonRpcEnvelope(payload)),
        );

        if (res.statusCode != 200) {
          throw Exception('RPC Session Error ${res.statusCode}: ${res.body}');
        }

        final data = jsonDecode(res.body);
        if (data['error'] != null) {
          throw Exception(data['error']['message'] ?? 'RPC Session Error');
        }
        return data['result'];
      } catch (e) {
        if (attempt >= _maxAttempts || !_isRetryableError(e)) rethrow;
        await Future.delayed(_baseDelay * attempt);
      }
    }
    throw Exception('callKwWithSession failed after $_maxAttempts attempts');
  }

  /// Parses the major version number from an Odoo [version] string.
  static int parseMajorVersion(String version) => odooMajorVersion(version);

  /// Whether the version odoo_rpc [reported] has lost what [odooGeneration]
  /// needs.
  ///
  /// `OdooSession.serverVersion` is only the first element of the server's
  /// `server_version_info`, as text. An Odoo 20 pre-release, which identifies
  /// itself as `19.5a1`, therefore arrives as `19` and would be taken for Odoo
  /// 19. Only 19 is ambiguous: 17 and 18 have no point release that changes what
  /// the app may call, and 20 and later report themselves whole.
  static bool serverVersionNeedsRefinement(String reported) =>
      odooMajorVersion(reported) == 19 && !reported.contains('.');

  /// The version string in a `/web/webclient/version_info` reply (`19.5a1`),
  /// the release series (`19.5`) when the string is missing, or null.
  static String? parseVersionInfoReply(dynamic reply) {
    final result = reply is Map ? reply['result'] : null;
    if (result is! Map) return null;
    for (final key in const ['server_version', 'server_serie']) {
      final value = result[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  /// The server's full version string, or [reported] when it is already good
  /// enough or the server does not say. See [serverVersionNeedsRefinement].
  ///
  /// `/web/webclient/version_info` needs no session and exists, unchanged, from
  /// Odoo 17 to 20.
  static Future<String> _refineServerVersion(
    String url,
    String reported,
  ) async {
    if (!serverVersionNeedsRefinement(reported)) return reported;
    try {
      final response = await ioClient
          .post(
            Uri.parse('$url/web/webclient/version_info'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': USER_AGENT,
            },
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': {},
              'id': 1,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final full = parseVersionInfoReply(jsonDecode(response.body));
        if (full != null) return full;
      }
    } catch (_) {}
    return reported;
  }

  /// Authenticates against Odoo and returns a populated [OdooSessionModel].
  ///
  /// The database-expiry check lives here rather than in
  /// `loginAndSaveSession`, because adding and switching accounts
  /// authenticate directly; guarding only the former would let an expired
  /// database back in through the account switcher.
  static Future<OdooSessionModel?> authenticate({
    required String serverUrl,
    required String database,
    required String username,
    required String password,
    bool autoLoadCompanies = true,
  }) async {
    if (serverUrl.isEmpty || database.isEmpty || username.isEmpty) {
      throw Exception('Invalid login parameters');
    }

    String normalizedUrl = serverUrl.trim();
    if (!normalizedUrl.startsWith('http://') &&
        !normalizedUrl.startsWith('https://')) {
      normalizedUrl = 'https://$normalizedUrl';
    }
    if (normalizedUrl.endsWith('/')) {
      normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 1);
    }
    if (normalizedUrl.endsWith('/odoo')) {
      normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 5);
    }

    final client = OdooClient(normalizedUrl, httpClient: ioClient);

    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        OdooSession? odooSession;
        try {
          odooSession = await client.authenticate(database, username, password);
        } catch (e) {
          if (e.toString().contains(
            "type 'Null' is not a subtype of type 'Map<String, dynamic>'",
          )) {
            try {
              // Reached when odoo_rpc cannot read the reply: Odoo answers
              // `{'uid': None}` (no `user_context`) to a user who still owes a
              // second factor, which is Odoo 19 and 20 behaviour alike. Goes
              // through ioClient like every other call, so a self-signed
              // certificate that the first attempt accepted is accepted here.
              final uri = Uri.parse('$normalizedUrl/web/session/authenticate');
              final response = await ioClient
                  .post(
                    uri,
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'jsonrpc': '2.0',
                      'method': 'call',
                      'params': {
                        'db': database,
                        'login': username,
                        'password': password,
                      },
                      'id': DateTime.now().millisecondsSinceEpoch,
                    }),
                  )
                  .timeout(_requestTimeout);

              if (response.statusCode == 200) {
                final authBody = jsonDecode(response.body);
                final result = authBody['result'];
                final error = authBody['error'];

                if (error != null) {
                  throw Exception(error['message'] ?? 'Authentication error');
                }

                if (result != null) {
                  var uid = result['uid'];
                  if (uid is bool) uid = null;

                  // No uid, and no error: the password was right but the user
                  // still owes a second factor. Said before looking for a
                  // session cookie, so the login screens always get the
                  // "two factor" signal they route to the TOTP page on.
                  if (uid == null) {
                    throw Exception('two factor authentication required');
                  }

                  String? sessionId;
                  if (result['session_id'] != null) {
                    sessionId = result['session_id'];
                  } else if (response.headers['set-cookie'] != null) {
                    final cookies = response.headers['set-cookie']!;
                    final sessionMatch = RegExp(
                      r'session_id=([^;]+)',
                    ).firstMatch(cookies);
                    sessionId = sessionMatch?.group(1);
                  }

                  if (sessionId != null) {
                    odooSession = OdooSession(
                      id: sessionId,
                      userId: uid,
                      partnerId: result['partner_id'] ?? 0,
                      userLogin: result['username'] ?? username,
                      userName: result['name'] ?? '',
                      userLang: result['user_context']?['lang'] ?? 'en_US',
                      userTz: result['user_context']?['tz'] ?? 'UTC',
                      isSystem: result['is_system'] ?? false,
                      dbName: result['db'] ?? database,
                      serverVersion: result['server_version'] ?? '',
                      companyId: result['company_id'] ?? 0,
                      allowedCompanies: [],
                    );
                  } else {
                    throw Exception('No session_id found in auth response');
                  }
                } else {
                  throw Exception('Authentication returned null result');
                }
              }
            } catch (manualEx) {
              rethrow;
            }
          }

          if (odooSession == null) rethrow;
        }

        // The first thing after the password is accepted: an expired database
        // is refused before a company is loaded, a session is built or the
        // caller can store, save or switch to anything.
        final signedIn = OdooClient(
          normalizedUrl,
          httpClient: ioClient,
          sessionId: odooSession,
        );
        if (await DatabaseExpiry.isExpired(signedIn)) {
          throw const DatabaseExpiredException();
        }

        int? selectedCompanyId;
        List<int> allowedCompanyIds = [];

        if (autoLoadCompanies) {
          try {
            final userInfo = await _fetchUserCompanies(
              odooSession.userId,
              url: normalizedUrl,
              sessionId: odooSession.id,
              database: database,
            );
            selectedCompanyId = userInfo['company_id'];
            allowedCompanyIds = (userInfo['company_ids'] as List<int>?) ?? [];

            if (selectedCompanyId != null &&
                !allowedCompanyIds.contains(selectedCompanyId)) {
              allowedCompanyIds.add(selectedCompanyId);
            }
          } catch (e) {
            selectedCompanyId = odooSession.companyId;
            allowedCompanyIds = [selectedCompanyId ?? 1];
          }
        }

        // odoo_rpc keeps only the major number; the generation checks need the
        // whole string (see serverVersionNeedsRefinement).
        final serverVersion = await _refineServerVersion(
          normalizedUrl,
          odooSession.serverVersion,
        );

        // Nothing leaves here for an account that may not use the app: no
        // session model for the caller to store, switch to or save.
        await requireSalesAccess(
          url: normalizedUrl,
          sessionId: odooSession.id,
          database: database,
          userId: odooSession.userId,
          serverVersion: serverVersion,
        );

        final sessionData = OdooSessionModel(
          sessionId: odooSession.id,
          userLogin: username,
          password: password,
          serverUrl: normalizedUrl,
          database: database,
          userId: odooSession.userId,
          userName: odooSession.userName,
          expiresAt: DateTime.now().add(const Duration(hours: 24)),
          selectedCompanyId: selectedCompanyId,
          allowedCompanyIds: allowedCompanyIds,
          serverVersion: serverVersion,
        );

        return sessionData;
      } on DatabaseExpiredException {
        rethrow;
      } catch (e) {
        // Neither retried nor read as anything else: it is a definite answer.
        if (e is DatabaseExpiredException) rethrow;
        if (e is SalesAccessException) rethrow;

        if (e is FormatException && e.toString().contains('<html>')) {
          throw Exception(
            'Server returned HTML instead of JSON. Please check server URL.',
          );
        }

        if (e.toString().toLowerCase().contains('access denied') ||
            e.toString().toLowerCase().contains('wrong login/password') ||
            e.toString().toLowerCase().contains('invalid database')) {
          rethrow;
        }

        if (attempt < _maxAttempts && _isRetryableError(e)) {
          final delay = _baseDelay * attempt;
          await Future.delayed(delay);
          continue;
        }

        rethrow;
      }
    }
    throw Exception('Authentication failed after $_maxAttempts attempts');
  }

  /// Executes an RPC call with the current company context injected into kwargs.
  ///
  /// A failure is reported with the detail Odoo nests under
  /// `error.data.message`. The top-level message is the generic
  /// "Odoo Server Error", which hides what actually went wrong.
  static Future<dynamic> callKwWithCompany(Map<String, dynamic> payload) async {
    final session = await getCurrentSession();
    if (session == null) {
      throw StateError('No Odoo session available. Please login.');
    }

    final kwargs = Map<String, dynamic>.from(payload['kwargs'] ?? {});
    final context = Map<String, dynamic>.from(kwargs['context'] ?? {});

    final selectedCompany = session.selectedCompanyId;
    final hasSelection = selectedCompany != null && selectedCompany != 0;

    if (hasSelection) {
      context['company_id'] = selectedCompany;
    }

    if (session.allowedCompanyIds.isNotEmpty) {
      if (hasSelection && session.allowedCompanyIds.contains(selectedCompany)) {
        final rest = {...session.allowedCompanyIds}..remove(selectedCompany);
        context['allowed_company_ids'] = <int>[selectedCompany, ...rest];
      } else {
        context['allowed_company_ids'] = session.allowedCompanyIds;
      }
    }

    context['db'] = session.database;

    kwargs['context'] = context;
    final newPayload = Map<String, dynamic>.from(payload);
    newPayload['kwargs'] = kwargs;

    Future<http.Response> post() async {
      final current = await getCurrentSession();
      final effective = current ?? session;
      final primaryUri = Uri.parse(
        '${effective.serverUrl}/web/dataset/call_kw',
      );
      final fallbackUri = Uri.parse(
        '${effective.serverUrl}/odoo/web/dataset/call_kw',
      );

      for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
        try {
          http.Response response = await ioClient.post(
            primaryUri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'X-Requested-With': 'XMLHttpRequest',
              'User-Agent': USER_AGENT,
              'Origin': effective.serverUrl,
              'Referer': '${effective.serverUrl}/web',
              'Cookie': 'session_id=${effective.sessionId}',
              'X-Openerp-Session-Id': effective.sessionId,
            },
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': newPayload,
              'id': DateTime.now().millisecondsSinceEpoch,
            }),
          );
          if (response.statusCode == 404) {
            response = await ioClient.post(
              fallbackUri,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'X-Requested-With': 'XMLHttpRequest',
                'User-Agent': USER_AGENT,
                'Origin': effective.serverUrl,
                'Referer': '${effective.serverUrl}/odoo/web',
                'Cookie': 'session_id=${effective.sessionId}',
                'X-Openerp-Session-Id': effective.sessionId,
              },
              body: jsonEncode({
                'jsonrpc': '2.0',
                'method': 'call',
                'params': newPayload,
                'id': DateTime.now().millisecondsSinceEpoch,
              }),
            );
          }
          return response;
        } catch (e) {
          if (attempt >= _maxAttempts || !_isRetryableError(e)) rethrow;
          await Future.delayed(_baseDelay * attempt);
        }
      }
      throw Exception(
        'RPC callKwWithCompany failed after $_maxAttempts attempts',
      );
    }

    http.Response response = await post();
    if (response.statusCode != 200) {
      throw Exception(
        '${response.statusCode}: ${response.reasonPhrase} - ${response.body}',
      );
    }

    final data = jsonDecode(response.body);
    if (data['error'] != null) {
      final message = data['error']['message']?.toString() ?? 'RPC Error';
      final lower = message.toLowerCase();
      if (lower.contains('session expired') ||
          lower.contains('session_expired')) {
        try {
          await getSessionInfo(session.serverUrl, session.sessionId);
          response = await post();
          if (response.statusCode != 200) {
            throw Exception('${response.statusCode}: ${response.reasonPhrase}');
          }
          final retryData = jsonDecode(response.body);
          if (retryData.containsKey('error')) {
            final error = retryData['error'];
            final msg = error['message']?.toString() ?? 'RPC Error';
            final dataMsg =
                error['data']?['message']?.toString() ??
                error['data']?.toString() ??
                '';
            throw Exception('$msg${dataMsg.isNotEmpty ? ': $dataMsg' : ''}');
          }
          return retryData['result'];
        } catch (_) {
          try {
            final refreshed = await refreshSession();
            if (refreshed) {
              response = await post();
              if (response.statusCode != 200) {
                throw Exception(
                  '${response.statusCode}: ${response.reasonPhrase}',
                );
              }
              final retryData = jsonDecode(response.body);
              if (retryData.containsKey('error')) {
                final error = retryData['error'];
                final msg = error['message']?.toString() ?? 'RPC Error';
                final dataMsg =
                    error['data']?['message']?.toString() ??
                    error['data']?.toString() ??
                    '';
                throw Exception(
                  '$msg${dataMsg.isNotEmpty ? ': $dataMsg' : ''}',
                );
              }
              return retryData['result'];
            }
          } catch (_) {}
        }
      }
      final dataMsg = data['error']['data']?['message']?.toString() ?? '';
      throw Exception('$message${dataMsg.isNotEmpty ? ': $dataMsg' : ''}');
    }
    return data['result'];
  }

  /// Executes a safe RPC call with company context injected (alias for [callKwWithCompany]).
  static Future<dynamic> safeCallKw(Map<String, dynamic> payload) {
    return callKwWithCompany(payload);
  }

  static Future<dynamic> safeCallKwWithoutCompany(
    Map<String, dynamic> payload,
  ) async {
    final session = await getCurrentSession();
    if (session == null) {
      throw StateError('No Odoo session available. Please login.');
    }

    Future<http.Response> post() async {
      final current = await getCurrentSession();
      final effective = current ?? session;
      final primaryUri = Uri.parse(
        '${effective.serverUrl}/web/dataset/call_kw',
      );
      final fallbackUri = Uri.parse(
        '${effective.serverUrl}/odoo/web/dataset/call_kw',
      );

      for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
        try {
          http.Response response = await ioClient.post(
            primaryUri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'X-Requested-With': 'XMLHttpRequest',
              'User-Agent': USER_AGENT,
              'Origin': effective.serverUrl,
              'Referer': '${effective.serverUrl}/web',
              'Cookie': 'session_id=${effective.sessionId}',
              'X-Openerp-Session-Id': effective.sessionId,
            },
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': payload,
              'id': DateTime.now().millisecondsSinceEpoch,
            }),
          );
          if (response.statusCode == 404) {
            response = await ioClient.post(
              fallbackUri,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'X-Requested-With': 'XMLHttpRequest',
                'User-Agent': USER_AGENT,
                'Origin': effective.serverUrl,
                'Referer': '${effective.serverUrl}/odoo/web',
                'Cookie': 'session_id=${effective.sessionId}',
                'X-Openerp-Session-Id': effective.sessionId,
              },
              body: jsonEncode({
                'jsonrpc': '2.0',
                'method': 'call',
                'params': payload,
                'id': DateTime.now().millisecondsSinceEpoch,
              }),
            );
          }
          return response;
        } catch (e) {
          if (attempt >= _maxAttempts || !_isRetryableError(e)) rethrow;
          await Future.delayed(_baseDelay * attempt);
        }
      }
      throw Exception(
        'RPC safeCallKwWithoutCompany failed after $_maxAttempts attempts',
      );
    }

    http.Response response = await post();
    if (response.statusCode != 200) {
      throw Exception(
        'RPC HTTP ${response.statusCode}: ${response.reasonPhrase} - ${response.body}',
      );
    }

    final data = jsonDecode(response.body);
    if (data.containsKey('error')) {
      final error = data['error'];
      final message = error['message']?.toString() ?? 'RPC Error';
      if (message.toLowerCase().contains('session expired')) {
        final refreshed = await refreshSession();
        if (refreshed) {
          response = await post();
          final retryData = jsonDecode(response.body);
          if (retryData.containsKey('error')) {
            final retryError = retryData['error'];
            final retryMsg = retryError['message']?.toString() ?? 'RPC Error';
            final retryDataMsg =
                retryError['data']?['message']?.toString() ??
                retryError['data']?.toString() ??
                '';
            throw Exception(
              '$retryMsg${retryDataMsg.isNotEmpty ? ': $retryDataMsg' : ''}',
            );
          }
          return retryData['result'];
        }
      }
      final dataMsg =
          error['data']?['message']?.toString() ??
          error['data']?.toString() ??
          '';
      throw Exception('$message${dataMsg.isNotEmpty ? ': $dataMsg' : ''}');
    }
    return data['result'];
  }

  /// Updates the active company selection in the session and persists the change.
  static Future<void> updateCompanySelection({
    required int companyId,
    required List<int> allowedCompanyIds,
  }) async {
    final session = await getCurrentSession();
    if (session == null) return;

    final updatedSession = session.copyWith(
      selectedCompanyId: companyId,
      allowedCompanyIds: allowedCompanyIds,
    );

    await updatedSession.saveToPrefs();
    _cachedSession = updatedSession;
    _onSessionUpdated?.call(updatedSession);
  }

  static Future<bool> restoreSession({required int companyId}) async {
    final session = await getCurrentSession();
    if (session == null) return false;

    await refreshSession();
    return true;
  }

  static Future<List<Map<String, dynamic>>> getAllowedCompaniesList() async {
    final session = await getCurrentSession();
    if (session == null) return [];

    int effectiveUserId = session.userId ?? 0;

    if (effectiveUserId == 0) {
      try {
        final info = await getSessionInfo(session.serverUrl, session.sessionId);
        if (info['uid'] != null) {
          final recoveredId = info['uid'] is int
              ? info['uid']
              : int.tryParse(info['uid'].toString()) ?? 0;
          if (recoveredId > 0) {
            effectiveUserId = recoveredId;

            await updateSession(session.copyWith(userId: effectiveUserId));
          }
        }
      } catch (e) {}
    }

    final info = await _fetchUserCompanies(effectiveUserId);
    final ids = (info['company_ids'] as List<int>? ?? []);
    if (ids.isEmpty) return [];

    final companiesRes = await safeCallKwWithoutCompany({
      'model': 'res.company',
      'method': 'search_read',
      'args': [
        [
          ['id', 'in', ids],
        ],
      ],
      'kwargs': {
        'fields': ['id', 'name'],
        'order': 'name asc',
      },
    });

    if (companiesRes is List) {
      return companiesRes.cast<Map<String, dynamic>>();
    }
    return [];
  }

  static Future<Map<String, dynamic>> _fetchUserCompanies(
    int userId, {
    String? url,
    String? sessionId,
    String? database,
  }) async {
    try {
      dynamic result;
      if (url != null && sessionId != null) {
        result = await callKwWithSession(
          url: url,
          sessionId: sessionId,
          payload: {
            'jsonrpc': '2.0',
            'method': 'call',
            'params': {
              'db': database,
              'model': 'res.users',
              'method': 'read',
              'args': [
                [userId],
                ['company_id', 'company_ids'],
              ],
              'kwargs': {},
            },
            'id': DateTime.now().millisecondsSinceEpoch,
          },
        );
      } else {
        result = await safeCallKwWithoutCompany({
          'model': 'res.users',
          'method': 'read',
          'args': [
            [userId],
            ['company_id', 'company_ids'],
          ],
          'kwargs': {},
        });
      }

      if (result is List && result.isNotEmpty) {
        final userData = result[0];

        int? companyId;
        if (userData['company_id'] is int) {
          companyId = userData['company_id'];
        } else if (userData['company_id'] is List &&
            userData['company_id'].isNotEmpty) {
          companyId = userData['company_id'][0];
        }

        List<int> companyIds = [];
        if (userData['company_ids'] is List) {
          companyIds = (userData['company_ids'] as List)
              .map((e) => e is int ? e : null)
              .whereType<int>()
              .toList();
        }

        return {'company_id': companyId, 'company_ids': companyIds};
      }

      return {};
    } catch (e) {
      return {};
    }
  }

  static Future<bool> refreshSession() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<bool>();

    try {
      final session = await getCurrentSession();
      if (session == null) {
        _refreshCompleter?.complete(false);
        _refreshCompleter = null;
        return false;
      }

      try {
        final info = await getSessionInfo(session.serverUrl, session.sessionId);
        if (info['uid'] != null &&
            (info['uid'] is int || info['uid'] is String)) {
          _lastAuthTime = DateTime.now();
          _refreshCompleter?.complete(true);
          _refreshCompleter = null;
          return true;
        }
      } catch (e) {}

      final newSession = await authenticate(
        serverUrl: session.serverUrl,
        database: session.database,
        username: session.userLogin,
        password: session.password,
      );

      if (newSession != null) {
        OdooSessionModel updatedSession = newSession;
        if (session.selectedCompanyId != null &&
            newSession.allowedCompanyIds.contains(session.selectedCompanyId)) {
          updatedSession = newSession.copyWith(
            selectedCompanyId: session.selectedCompanyId,
          );
        }
        await updatedSession.saveToPrefs();
        _cachedSession = updatedSession;
        _onSessionUpdated?.call(updatedSession);

        _refreshCompleter?.complete(true);
        _refreshCompleter = null;
        return true;
      }

      _refreshCompleter?.complete(false);
      _refreshCompleter = null;
      return false;
    } catch (e) {
      _refreshCompleter?.complete(false);
      _refreshCompleter = null;
      return false;
    }
  }

  static Future<OdooClient?> getClientEnsured() async {
    return getClient();
  }

  static Future<http.Response> makeAuthenticatedRequest(
    String url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    int maxRetries = 3,
  }) async {
    final session = await getCurrentSession();
    if (session == null) {
      throw StateError('No active session');
    }

    await getClientEnsured();

    final uri = Uri.parse(url);
    final requestHeaders = {
      'Cookie': 'session_id=${session.sessionId}',
      if (shouldSkipSessionRotation(odooGeneration(session.serverVersion)))
        skipSessionRotationHeader: '1',
      ...?headers,
    };

    Exception? lastError;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final client = http.Client();
        try {
          final response = await client
              .get(uri, headers: requestHeaders)
              .timeout(timeout ?? const Duration(seconds: 30));

          return response;
        } finally {
          client.close();
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        if (attempt < maxRetries && _isRetryableError(e)) {
          await Future.delayed(_baseDelay * attempt);
          continue;
        }
        rethrow;
      }
    }

    throw lastError ?? Exception('Request failed');
  }
}
