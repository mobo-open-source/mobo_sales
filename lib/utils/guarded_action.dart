import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/custom_snackbar.dart';

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
  String? successMessage,
  String failurePrefix = 'Action failed',
  Duration timeout = kActionTimeout,
}) async {
  BuildContext? dialogContext;
  var dialogOpen = true;

  void dismiss() {
    if (!dialogOpen) return;
    dialogOpen = false;
    final ctx = dialogContext;
    dialogContext = null;
    if (ctx == null) return;
    final navigator = Navigator.of(ctx);
    if (navigator.canPop()) navigator.pop();
  }

  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return _ProgressDialog(message: message);
      },
    ).whenComplete(() {
      dialogOpen = false;
      dialogContext = null;
    }),
  );

  try {
    final result = await action().timeout(timeout);
    dismiss();
    if (context.mounted && successMessage != null) {
      CustomSnackbar.showSuccess(context, successMessage);
    }
    return result;
  } catch (error) {
    dismiss();
    if (context.mounted) {
      CustomSnackbar.showError(
        context,
        describeActionFailure(error, failurePrefix),
      );
    }
    return null;
  } finally {
    dismiss();
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

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: isDark ? Theme.of(context).primaryColor : null,
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Text(
                message,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
