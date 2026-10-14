import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/quiet_reload_gate.dart';

void main() {
  const debounce = Duration(milliseconds: 350);

  late DateTime now;
  late int reloads;
  late QuietReloadGate gate;
  late Completer<void> release;

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    reloads = 0;
    release = Completer<void>();
    gate = QuietReloadGate(() async {
      reloads++;
    }, clock: () => now);
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a change when nothing is running reloads once', () async {
    gate.changed(debounce: debounce);
    await settle();
    expect(reloads, 1);
    expect(gate.isRunning, isFalse);
  });

  test('changes while a load runs add one follow-up, not one each', () async {
    final loading = gate.run(() => release.future); // starts at 12:00:00.000

    // The listener calls back `debounce` after the last change: delivered at
    // 12:00:01.000, these were announced at 12:00:00.650, after the load above
    // had started, so what it reads may predate them.
    now = DateTime(2026, 1, 1, 12, 0, 1);
    gate.changed(debounce: debounce);
    gate.changed(debounce: debounce);
    gate.changed(debounce: debounce);
    expect(gate.rerunPending, isTrue);
    expect(reloads, 0);

    release.complete();
    await loading;
    await settle();
    expect(reloads, 1);
    expect(gate.rerunPending, isFalse);
  });

  test('a change the running load already covers is dropped', () async {
    final loading = gate.run(() => release.future); // starts at 12:00:00.000

    // Delivered at 12:00:00.350, so announced at 12:00:00.000: the load began
    // no earlier than that and has read (or will read) the changed state.
    now = DateTime(2026, 1, 1, 12, 0, 0, 350);
    gate.changed(debounce: debounce);
    expect(gate.rerunPending, isFalse);

    release.complete();
    await loading;
    await settle();
    expect(reloads, 0);
  });

  test(
    'a change announced after the running load began is followed up',
    () async {
      final loading = gate.run(() => release.future); // starts at 12:00:00.000

      // Delivered at 12:00:01.350, so announced at 12:00:01.000.
      now = DateTime(2026, 1, 1, 12, 0, 1, 350);
      gate.changed(debounce: debounce);
      expect(gate.rerunPending, isTrue);

      release.complete();
      await loading;
      await settle();
      expect(reloads, 1);
    },
  );

  test(
    'a load run through the gate is not repeated for its own caller',
    () async {
      var own = 0;
      await gate.run(() async {
        own++;
      });
      expect(own, 1);
      expect(reloads, 0);
    },
  );

  test('a quiet reload that throws does not escape', () async {
    final failing = QuietReloadGate(() async => throw StateError('offline'));
    failing.changed(debounce: debounce);
    await settle();
    expect(failing.isRunning, isFalse);
  });

  test('nothing runs once it is disposed', () async {
    gate.dispose();
    gate.changed(debounce: debounce);
    await settle();
    expect(reloads, 0);

    final loading = gate.run(() => release.future);
    now = DateTime(2026, 1, 1, 12, 0, 5);
    gate.changed(debounce: debounce);
    release.complete();
    await loading;
    await settle();
    expect(reloads, 0);
  });
}
