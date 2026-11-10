import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart' show navigatorKey;
import '../screens/auth/app_lock_screen.dart';
import 'biometric_context_service.dart';
import 'biometric_service.dart';

/// Asks for the app lock again when the app comes back from the background.
///
/// `AuthCheck` decides the lock once, while the app is starting. Without
/// something to re-arm it, backgrounding the app and returning walks straight
/// back in. [DatabaseExpiryGuard] and [SalesAccessGuard] re-check on resume
/// for their own reasons; this is the same shape.
class AppLockGuard with WidgetsBindingObserver {
  AppLockGuard({
    Future<bool> Function()? isEnabled,
    Future<void> Function()? showLockScreen,
    DateTime Function()? clock,
  }) : _isEnabled = isEnabled ?? BiometricService.isBiometricEnabled,
       _showLockScreen = showLockScreen ?? _pushLockScreen,
       _clock = clock ?? DateTime.now;

  /// The one the app runs.
  static final AppLockGuard instance = AppLockGuard();

  /// How long the app may be away before it asks again.
  ///
  /// A moment out of the app is part of using it — the photo picker, the
  /// scanner, the biometric prompt itself all background it briefly, and
  /// locking on those would ask again and again without the user ever having
  /// left.
  static const Duration grace = Duration(seconds: 10);

  final Future<bool> Function() _isEnabled;
  final Future<void> Function() _showLockScreen;
  final DateTime Function() _clock;

  bool _started = false;
  bool _locking = false;
  DateTime? _leftAt;

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

  /// Forgets the time away, so the next resume does not lock.
  ///
  /// Used after the lock has just been satisfied: the prompt itself
  /// backgrounds the app, and that return must not ask again.
  void reset() => _leftAt = null;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _leftAt ??= _clock();
      case AppLifecycleState.resumed:
        unawaited(lockIfAway());
      case AppLifecycleState.inactive:
        // A notification shade or an incoming call, not leaving the app.
        break;
    }
  }

  /// Locks if the app was away longer than [grace] and the lock is on.
  Future<void> lockIfAway() async {
    final leftAt = _leftAt;
    _leftAt = null;

    if (_locking || leftAt == null) return;
    if (_clock().difference(leftAt) < grace) return;
    // Switching or adding an account backgrounds the app on purpose.
    if (BiometricContextService().shouldSkipBiometric) return;

    bool enabled;
    try {
      enabled = await _isEnabled();
    } catch (_) {
      // Unreadable settings must not lock the user out of their own app.
      return;
    }
    if (!enabled) return;

    _locking = true;
    try {
      await _showLockScreen();
    } finally {
      _locking = false;
      // The prompt backgrounded the app to show itself; that return is not
      // the user leaving.
      _leftAt = null;
    }
  }

  static Future<void> _pushLockScreen() async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => AppLockScreen(
          onAuthenticationSuccess: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
