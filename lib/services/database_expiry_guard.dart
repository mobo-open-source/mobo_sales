import 'dart:async';

import 'package:flutter/widgets.dart';

import '../main.dart' show navigatorKey;
import '../utils/database_expiry.dart';
import '../widgets/custom_snackbar.dart';
import 'odoo_session_manager.dart';
import 'session_service.dart';

/// Looks again at the database's subscription each time the app comes back to
/// the foreground, so one that ran out while the app was in the background does
/// not go on being used.
///
/// A small guard, not a poller: it runs on the return to the app only, skips
/// itself when nobody is signed in, when a check is already running and when
/// the last one was under [minInterval] ago, and lets the user be on any
/// failure — only a definite "expired" signs anyone out.
class DatabaseExpiryGuard with WidgetsBindingObserver {
  DatabaseExpiryGuard({
    Future<bool> Function()? expiryCheck,
    Future<void> Function()? signOut,
    Future<bool> Function()? hasSession,
    DateTime Function()? clock,
  }) : _expiryCheck =
           expiryCheck ?? OdooSessionManager.currentSessionDatabaseExpired,
       _signOut = signOut ?? _signOutAndExplain,
       _hasSession = hasSession ?? _someoneIsSignedIn,
       _clock = clock ?? DateTime.now;

  /// The one the app runs.
  static final DatabaseExpiryGuard instance = DatabaseExpiryGuard();

  /// How soon after a check another is skipped.
  static const Duration minInterval = Duration(seconds: 30);

  /// Whether the database has expired: the saved session's probe. A test
  /// poses as any answer through the constructor.
  final Future<bool> Function() _expiryCheck;

  /// What happens when it has: the sign-out, the sign-in screen and the message.
  final Future<void> Function() _signOut;
  final Future<bool> Function() _hasSession;
  final DateTime Function() _clock;

  bool _running = false;
  DateTime? _lastCheckedAt;
  bool _started = false;

  /// Starts watching the app's lifecycle. Safe to call twice.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(checkNow());
  }

  /// Checks now, unless nobody is signed in, a check is running or one ran under
  /// [minInterval] ago ([ignoreRecentCheck] skips that last rule). Signs the
  /// current account out when its database has expired; does nothing on any error.
  Future<void> checkNow({bool ignoreRecentCheck = false}) async {
    if (_running) return;
    final last = _lastCheckedAt;
    if (!ignoreRecentCheck &&
        last != null &&
        _clock().difference(last) < minInterval) {
      return;
    }

    _running = true;
    try {
      if (!await _hasSession()) return;
      _lastCheckedAt = _clock();
      if (await _expiryCheck()) await _signOut();
    } catch (_) {
      // Fail open: a check that cannot be made lets the user stay.
    } finally {
      _running = false;
    }
  }

  static Future<bool> _someoneIsSignedIn() async =>
      await OdooSessionManager.getCurrentSession() != null;

  /// Ends the current account's session — the other saved accounts stay — and
  /// lands on the sign-in screen with the message, shown once its first frame
  /// is up.
  static Future<void> _signOutAndExplain() async {
    await OdooSessionManager.logout();
    await SessionService.instance.clearSession();
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/login',
      (route) => false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = navigatorKey.currentContext;
      if (target != null && target.mounted) {
        CustomSnackbar.showError(target, DatabaseExpiredException.message);
      }
    });
  }
}
