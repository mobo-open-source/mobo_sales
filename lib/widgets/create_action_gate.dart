import 'package:flutter/material.dart';

import '../services/odoo_error_classifier.dart';
import 'custom_snackbar.dart';

/// Why a create action cannot be started right now, or null when it can.
///
/// The create screens in this app have no offline path: they open, read
/// customers, products, taxes and currencies from the server, and save
/// straight back. With no connection or no session they open to empty
/// dropdowns and lose whatever was typed at the save, which reads as a
/// different bug entirely.
///
/// [listError] is the failure the list behind the button is already showing,
/// so the button and the message on screen agree about what is wrong.
String? createBlockedReason({
  required bool isConnected,
  required bool hasSession,
  Object? listError,
}) {
  if (!isConnected) {
    return 'You are offline. Reconnect to add anything new.';
  }
  if (!hasSession || OdooErrorClassifier.isSessionExpired(listError)) {
    return 'Your session has expired. Please log in again.';
  }
  if (OdooErrorClassifier.isServerUnreachable(listError)) {
    return 'The server cannot be reached. Try again once it responds.';
  }
  return null;
}

/// A floating action button that will not open a form the app cannot fill in
/// or save.
///
/// When [blockedReason] is set the button dims and, on tap, says why rather
/// than doing nothing. A disabled control that gives no reason leaves the
/// user with two mysteries instead of one, so this never swallows the tap.
///
/// Only create actions take this. A scroll-to-top button has nothing to do
/// with the server and keeps working.
class CreateActionFab extends StatelessWidget {
  const CreateActionFab({
    super.key,
    required this.heroTag,
    required this.onPressed,
    required this.child,
    this.blockedReason,
    this.backgroundColor,
    this.tooltip,
  });

  final String heroTag;
  final VoidCallback onPressed;
  final Widget child;

  /// Null when the action is available.
  final String? blockedReason;

  final Color? backgroundColor;
  final String? tooltip;

  bool get _blocked => blockedReason != null;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _blocked ? 0.45 : 1,
      child: FloatingActionButton(
        heroTag: heroTag,
        backgroundColor: backgroundColor,
        tooltip: _blocked ? blockedReason : tooltip,
        onPressed: () {
          if (_blocked) {
            CustomSnackbar.showInfo(context, blockedReason!);
            return;
          }
          onPressed();
        },
        child: child,
      ),
    );
  }
}
