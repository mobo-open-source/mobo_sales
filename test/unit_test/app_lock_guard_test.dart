import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/app_lock_guard.dart';
import 'package:mobo_sales/services/biometric_context_service.dart';

/// The app lock was decided once, while the app started, and nothing asked
/// again. A tester backgrounded the app, came back, and was already inside.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late int prompts;

  AppLockGuard guard({bool enabled = true}) => AppLockGuard(
    isEnabled: () async => enabled,
    showLockScreen: () async => prompts++,
    clock: () => now,
  );

  void away(AppLockGuard g, Duration d) {
    g.didChangeAppLifecycleState(AppLifecycleState.paused);
    now = now.add(d);
    g.didChangeAppLifecycleState(AppLifecycleState.resumed);
  }

  setUp(() {
    now = DateTime(2026, 11, 6, 9);
    prompts = 0;
    BiometricContextService().reset();
  });

  test('coming back after a while asks again', () async {
    final g = guard();
    away(g, AppLockGuard.grace + const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);

    expect(prompts, 1);
  });

  test('a moment away does not', () async {
    // The photo picker, the scanner and the prompt itself all background the
    // app briefly; asking every time would be unusable.
    final g = guard();
    away(g, const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);

    expect(prompts, 0);
  });

  test('with the lock off, nothing is asked', () async {
    final g = guard(enabled: false);
    away(g, const Duration(minutes: 5));
    await Future<void>.delayed(Duration.zero);

    expect(prompts, 0);
  });

  test('switching account is not leaving the app', () async {
    final g = guard();
    BiometricContextService().startAccountOperation('switch');
    away(g, const Duration(minutes: 5));
    await Future<void>.delayed(Duration.zero);

    expect(prompts, 0);
  });

  test('resuming without having left asks nothing', () async {
    final g = guard();
    g.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);

    expect(prompts, 0);
  });

  test('the prompt backgrounding the app does not ask twice', () async {
    final g = guard();
    away(g, const Duration(minutes: 5));
    await Future<void>.delayed(Duration.zero);
    expect(prompts, 1);

    // Satisfying the prompt brings the app back; that return is not a leave.
    g.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);

    expect(prompts, 1);
  });

  test('an unreadable setting never locks the user out', () async {
    final g = AppLockGuard(
      isEnabled: () async => throw Exception('no preferences'),
      showLockScreen: () async => prompts++,
      clock: () => now,
    );
    away(g, const Duration(minutes: 5));
    await Future<void>.delayed(Duration.zero);

    expect(prompts, 0);
  });
}
