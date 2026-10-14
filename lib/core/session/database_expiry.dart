import '../../main.dart';
import '../../services/odoo_session_manager.dart';
import '../../services/session_service.dart';
import '../../widgets/custom_snackbar.dart';

/// Raised when the Odoo database behind a session has passed its expiry date.
class DatabaseExpiredException implements Exception {
  const DatabaseExpiredException();

  /// Wording shown to the user. Deliberately names who can fix it, since
  /// nothing the user does in the app will clear the condition.
  static const String message =
      'This database has expired. Please contact your administrator or '
      'Odoo to renew the subscription.';

  /// Returns the user-facing wording.
  ///
  /// Account switching and re-authentication surface failures by stringifying
  /// whatever was thrown, so this has to read correctly on its own rather
  /// than as a developer label.
  @override
  String toString() => message;
}

/// Keeps an expired Odoo database out of the app.
///
/// A subscription that has lapsed still answers requests, so a stored session
/// keeps working and the user carries on as if nothing happened. The date is
/// read from the server and checked at the points where it matters: signing
/// in, cold start, and each time the app comes back to the foreground.
class DatabaseExpiry {
  DatabaseExpiry._();

  /// How long a check is trusted before the server is asked again.
  ///
  /// Without this the app pays a round-trip every time it is resumed, for a
  /// value that moves once a year.
  static const Duration _recheckInterval = Duration(minutes: 30);

  static DateTime? _lastCheck;
  static bool _enforcing = false;

  /// Whether the database behind this session has expired.
  ///
  /// Answers false whenever the date cannot be established — an unreachable
  /// server, a user without rights to read the parameter, or an on-premise
  /// database with no expiry at all. Locking someone out because a check
  /// failed would be far worse than letting an expired database through.
  static Future<bool> isExpired({
    required String serverUrl,
    required String sessionId,
  }) async {
    if (serverUrl.isEmpty || sessionId.isEmpty) return false;

    final raw = await _expirationDate(serverUrl, sessionId);
    return isExpiredDate(raw);
  }

  /// Whether [raw], an Odoo `database.expiration_date`, is in the past.
  ///
  /// Pure and separated from the network so the decision itself can be
  /// tested. Odoo reports the value as a naive UTC timestamp, for example
  /// `2026-10-04 08:39:25`.
  ///
  /// Rounds to whole days the way the Odoo web client does, so the app and
  /// the browser agree on which day is the last usable one.
  static bool isExpiredDate(String? raw, {DateTime? now}) {
    if (raw == null || raw.trim().isEmpty) return false;

    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}):(\d{2}))?',
    ).firstMatch(raw.trim());
    if (match == null) return false;

    final parts = [
      for (var i = 1; i <= 6; i++) int.tryParse(match.group(i) ?? '') ?? 0,
    ];
    final expiry = DateTime.utc(
      parts[0],
      parts[1],
      parts[2],
      parts[3],
      parts[4],
      parts[5],
    );

    final reference = (now ?? DateTime.now()).toUtc();
    final daysLeft = expiry.difference(reference).inSeconds / 86400;
    return daysLeft.round() <= 0;
  }

  /// The server's `database.expiration_date`, or null when it cannot be read.
  ///
  /// Tries the session info first and `ir.config_parameter` second: an
  /// ordinary user usually has no rights on that parameter and the read
  /// raises for them, so it cannot be the primary source. Both failing means
  /// no date is available, which the caller treats as "not expired" rather
  /// than locking someone out over a failed check.
  static Future<String?> _expirationDate(
    String serverUrl,
    String sessionId,
  ) async {
    final url = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');

    try {
      final info = await OdooSessionManager.getSessionInfo(url, sessionId);
      final value = info['expiration_date'];
      if (value is String && value.isNotEmpty) return value;
    } catch (_) {}

    try {
      final value = await OdooSessionManager.callKwWithSession(
        url: url,
        sessionId: sessionId,
        payload: {
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'ir.config_parameter',
            'method': 'get_param',
            'args': ['database.expiration_date'],
            'kwargs': {},
          },
          'id': 1,
        },
      );
      if (value is String && value.isNotEmpty) return value;
    } catch (_) {}
    return null;
  }

  /// Signs the user out and returns them to the login screen when the stored
  /// session's database has expired. Returns whether it acted.
  ///
  /// Safe to call often: concurrent calls are ignored, and the server is only
  /// asked again once [_recheckInterval] has passed.
  static Future<bool> enforceOnStoredSession({bool force = false}) async {
    if (_enforcing) return false;

    final last = _lastCheck;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _recheckInterval) {
      return false;
    }

    _enforcing = true;
    try {
      final session = await OdooSessionManager.getCurrentSession();
      if (session == null) return false;

      final expired = await isExpired(
        serverUrl: session.serverUrl,
        sessionId: session.sessionId,
      );
      _lastCheck = DateTime.now();
      if (!expired) return false;

      await SessionService.instance.logout(showNotice: false);

      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );

      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        CustomSnackbar.showError(context, DatabaseExpiredException.message);
      }
      return true;
    } finally {
      _enforcing = false;
    }
  }

  /// Forgets the last check, so the next call asks the server again.
  static void reset() => _lastCheck = null;
}
