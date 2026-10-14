import 'dart:async';

/// Keeps a screen's background refresh, the one a [DataChangeBus] event
/// triggers, from piling up or repeating work.
///
/// A screen runs its own loads (the first one, a pull to refresh, the refresh
/// after an edit) and a quiet reload when the bus says something changed. This
/// puts all of them through one place, so that
///
///  * two loads never run side by side because of events: a change that arrives
///    while one is running is remembered, and one more quiet reload runs when
///    it ends, however many changes arrived;
///  * a change the running load already covers is dropped: the bus calls back
///    [debounce] after the *last* change of a burst, so a load that started
///    after that moment began after every change in the burst and read the new
///    state. The edit-then-return flow relies on it: the screen reloads itself
///    on return and the event for the same edit arrives while that reload runs.
class QuietReloadGate {
  QuietReloadGate(this._reload, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Future<void> Function() _reload;
  final DateTime Function() _clock;

  int _running = 0;
  bool _rerun = false;
  bool _disposed = false;
  DateTime? _lastStart;

  /// Whether a load is running right now.
  bool get isRunning => _running > 0;

  /// Whether one more quiet reload is waiting for the running load to end.
  bool get rerunPending => _rerun;

  /// Runs [load] as one of the screen's own loads (or the quiet reload itself),
  /// then the follow-up reload if a change arrived meanwhile that [load] does
  /// not cover.
  Future<void> run(Future<void> Function() load) async {
    _running++;
    _lastStart = _clock();
    try {
      await load();
    } finally {
      _running--;
    }
    if (_running == 0 && _rerun && !_disposed) {
      _rerun = false;
      // The follow-up is the gate's own: the caller does not wait for it, and
      // its failure is not the caller's.
      unawaited(run(_reload).catchError((Object _) {}));
    }
  }

  /// The bus reported a change; [debounce] is what the listener waited.
  void changed({required Duration debounce}) {
    if (_disposed) return;
    if (_running > 0) {
      final announcedAt = _clock().subtract(debounce);
      final start = _lastStart;
      if (start != null && !start.isBefore(announcedAt)) return;
      _rerun = true;
      return;
    }
    unawaited(run(_reload).catchError((Object _) {}));
  }

  /// Nothing runs after this; call it from `dispose`.
  void dispose() {
    _disposed = true;
    _rerun = false;
  }
}
