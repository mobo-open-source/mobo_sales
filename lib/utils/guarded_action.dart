import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/custom_snackbar.dart';
import '../widgets/loading_dialog.dart';

/// Upper bound on a single user-triggered server action.
const Duration kActionTimeout = Duration(seconds: 30);

/// Runs [action] behind a modal progress dialog and guarantees the dialog
/// closes, whatever happens.
///
/// Every hand-rolled version of this in the app got at least one of three
/// things wrong:
///
///   * the awaited work had no timeout, so a stalled request left a
///     non-dismissible dialog on screen for good;
///   * dismissal called `Navigator.of(screenContext).pop()`, which pops
///     whatever route is on top of the *nearest* navigator — not necessarily
///     this dialog, and `showDialog` pushes onto the root navigator by
///     default, so the two can disagree and the page gets popped instead;
///   * the result message was raised while the dialog was still up, where a
///     snackbar renders behind it and is never seen.
///
/// Returns the action's value, or null when it failed or timed out.
Future<T?> runGuardedAction<T>({
  required BuildContext context,
  required String message,
  required Future<T> Function() action,
  String? subtitle,
  String? successMessage,
  String failurePrefix = 'Action failed',
  Duration timeout = kActionTimeout,
}) async {
  // The app's one loading popup. Its handle closes this dialog's own route,
  // once, so a late `finally` can never pop the page underneath.
  final loading = LoadingDialog.open(
    context,
    message: message,
    subtitle: subtitle ?? LoadingCard.defaultSubtitle,
  );

  try {
    final result = await action().timeout(timeout);
    loading.close();
    if (context.mounted && successMessage != null) {
      CustomSnackbar.showSuccess(context, successMessage);
    }
    return result;
  } catch (error) {
    loading.close();
    if (context.mounted) {
      CustomSnackbar.showError(
        context,
        describeActionFailure(error, failurePrefix),
      );
    }
    return null;
  } finally {
    loading.close();
  }
}

/// A short, accurate reason for a failed action.
String describeActionFailure(Object error, String fallbackPrefix) {
  if (error is TimeoutException) {
    return 'The server did not respond in time. Please check your connection '
        'and try again.';
  }
  final message = error.toString().toLowerCase();
  if (message.contains('session expired') ||
      message.contains('session invalid')) {
    return 'Session expired. Please log in again.';
  }
  return '$fallbackPrefix: $error';
}
