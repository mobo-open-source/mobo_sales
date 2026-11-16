import 'package:flutter/foundation.dart';

/// Thrown by [CancellationToken.throwIfCancelled] when the user gave up on a
/// long operation.
///
/// It is not a failure: nothing went wrong and the user already knows what
/// happened, so a caller that catches this should stay quiet rather than put an
/// error on screen.
class OperationCancelled implements Exception {
  const OperationCancelled();

  @override
  String toString() => 'Operation cancelled';
}

/// A one-way "the user wants out" flag, handed to work that can run long.
///
/// Document generation can sit through several minutes of server time per
/// attempt and try more than one report, so the only honest way to offer a
/// Cancel is to let the work itself notice. The token is checked at the points
/// where abandoning costs nothing — between attempts, and before anything is
/// shown — rather than trying to abort a request already in flight.
///
/// Cancelling does not undo work already done on the server. It stops this app
/// waiting on it, which is what the user asked for.
class CancellationToken {
  bool _cancelled = false;
  final List<VoidCallback> _listeners = <VoidCallback>[];

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Marks the operation cancelled and tells everyone listening. Calling it
  /// more than once does nothing, so a Cancel button and a back gesture can
  /// both be wired to it.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  /// Runs [listener] when the token is cancelled, or straight away when it
  /// already has been.
  void addListener(VoidCallback listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  /// Throws [OperationCancelled] when the user has given up, so a long method
  /// can bail out of a loop with one line.
  void throwIfCancelled() {
    if (_cancelled) throw const OperationCancelled();
  }
}
