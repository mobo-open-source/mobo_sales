import 'package:odoo_rpc/odoo_rpc.dart';

/// Thrown when the Odoo database behind a sign-in has expired. The
/// message is the one the sign-in screens and the snackbars show.
class DatabaseExpiredException implements Exception {
  const DatabaseExpiredException();

  static const String message =
      'This database has expired. Please contact your administrator or Odoo '
      'to renew the subscription.';

  @override
  String toString() => message;
}

/// Whether an Odoo Enterprise database's subscription has expired.
///
/// Enterprise's `web_enterprise` module adds `expiration_date` to the session
/// info of internal users (Odoo 16 to 20); Community never sends it, so a
/// Community database is never expired. The server tells only a signed-in user,
/// so this runs right after a password or code is accepted, not when the
/// database is picked.
///
/// Only a definite "expired" blocks anyone: a date that cannot be read, a
/// server that cannot be reached or an answer nobody expected lets the user in.
class DatabaseExpiry {
  const DatabaseExpiry._();

  static final RegExp _date = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}):(\d{2}))?',
  );

  /// How long the probe may take before the user is let in.
  static const Duration probeTimeout = Duration(seconds: 10);

  /// Whether [value], an `expiration_date` as Odoo sends it (`YYYY-MM-DD` or
  /// `YYYY-MM-DD HH:MM:SS`, UTC), is today or past.
  ///
  /// The rule is the Odoo web client's: `Math.round(daysLeft) <= 0`, with
  /// `daysLeft` the seconds until the date divided by 86400. That is "less than
  /// half a day left": exactly twelve hours is still valid, one second short of
  /// it is not. [now] stands in for the clock in tests.
  static bool hasExpired(Object? value, {DateTime? now}) {
    if (value is! String) return false;
    final match = _date.firstMatch(value);
    if (match == null) return false;

    int part(int group) => int.parse(match.group(group) ?? '0');
    final month = part(2);
    final day = part(3);
    final hour = part(4);
    final minute = part(5);
    final second = part(6);
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31 ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      return false;
    }

    final expiry = DateTime.utc(part(1), month, day, hour, minute, second);
    final daysLeft =
        expiry.difference((now ?? DateTime.now()).toUtc()).inMicroseconds /
        Duration.microsecondsPerDay;
    // JavaScript's Math.round: halves go up.
    return (daysLeft + 0.5).floor() <= 0;
  }

  /// Reads `expiration_date` from the session info and says whether it has
  /// passed.
  ///
  /// [readSessionInfo] answers `/web/session/get_session_info`.
  /// [readParameter] answers `ir.config_parameter.get_param(
  /// 'database.expiration_date')`; it is asked only when the session info
  /// could not be read at all, never when it was read and the key is simply
  /// missing (Community). Any failure is "not expired".
  static Future<bool> check({
    required Future<dynamic> Function() readSessionInfo,
    required Future<dynamic> Function() readParameter,
    DateTime? now,
  }) async {
    try {
      final dynamic info;
      try {
        info = await readSessionInfo();
      } catch (_) {
        return hasExpired(await readParameter(), now: now);
      }
      return info is Map && hasExpired(info['expiration_date'], now: now);
    } catch (_) {
      return false;
    }
  }

  /// [check] through [client], which must already be signed in.
  static Future<bool> isExpired(
    OdooClient client, {
    Duration timeout = probeTimeout,
  }) {
    return check(
      readSessionInfo: () =>
          client.callRPC('/web/session/get_session_info', 'call', {}),
      readParameter: () => client.callKw({
        'model': 'ir.config_parameter',
        'method': 'get_param',
        'args': ['database.expiration_date'],
        'kwargs': <String, dynamic>{},
      }),
    ).timeout(timeout, onTimeout: () => false);
  }
}
