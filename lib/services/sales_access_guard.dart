import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show navigatorKey;
import '../widgets/access_denied_dialog.dart';
import 'odoo_session_manager.dart';
import 'sales_access.dart';
import 'session_service.dart';

/// Looks again at the Sales app and the user's Sales access each time the app
/// comes back to the foreground, so an app that was only minimised (and so did
/// not start over) cannot go on being used after the Sales app was uninstalled
/// on the server or the user lost Sales access.
///
/// The start of the app does the same in `AuthCheck`; this is the other half.
/// It runs on the return to the app only, skips itself when nobody is signed
/// in, when a check is already running and when the last one was under
/// [minInterval] ago, and only a definite answer signs anyone out: no network,
/// a slow server or an answer nobody expected leaves the user where they are.
class SalesAccessGuard with WidgetsBindingObserver {
  SalesAccessGuard({
    Future<SalesAccessException?> Function()? accessCheck,
    Future<void> Function(SalesAccessException problem)? signOut,
    Future<bool> Function()? hasSession,
    DateTime Function()? clock,
  }) : _accessCheck =
           accessCheck ?? OdooSessionManager.currentSessionAccessProblem,
       _signOut = signOut ?? _signOutAndExplain,
       _hasSession = hasSession ?? _someoneIsSignedIn,
       _clock = clock ?? DateTime.now;

  /// The one the app runs.
  static final SalesAccessGuard instance = SalesAccessGuard();

  /// How soon after a check another is skipped.
  static const Duration minInterval = Duration(seconds: 5);

  final Future<SalesAccessException?> Function() _accessCheck;
  final Future<void> Function(SalesAccessException problem) _signOut;
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
  /// current account out, with the reason, when Sales cannot be used; does
  /// nothing on any error.
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
      final problem = await _accessCheck();
      if (problem != null) await _signOut(problem);
    } catch (_) {
      // Fail open: a check that cannot be made lets the user stay.
    } finally {
      _running = false;
    }
  }

  static Future<bool> _someoneIsSignedIn() async =>
      await OdooSessionManager.getCurrentSession() != null;

  /// Ends the current account's session — the other saved accounts stay —
  /// lands on the sign-in screen and says why in the popup.
  static Future<void> _signOutAndExplain(SalesAccessException problem) async {
    await OdooSessionManager.logout();
    await SessionService.instance.clearSession();

    final prefs = await SharedPreferences.getInstance();
    final hasCredentials = [
      'lastUrl',
      'lastDatabase',
      'lastUsername',
    ].every((k) => (prefs.getString(k) ?? '').isNotEmpty);

    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      hasCredentials ? '/login' : '/server_setup',
      (route) => false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final target = navigatorKey.currentContext;
      if (target != null && target.mounted) {
        await AccessDeniedDialog.showFor(
          target,
          problem,
          buttonLabel: 'OK',
        );
      }
    });
  }
}
