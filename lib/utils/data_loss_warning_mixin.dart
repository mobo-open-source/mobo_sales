import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import '../widgets/data_loss_warning_dialog.dart';

mixin DataLossWarningMixin<T extends StatefulWidget> on State<T> {
  bool get hasUnsavedData;

  String get dataLossTitle => 'Unsaved Changes';

  String get dataLossMessage =>
      'You have unsaved changes that will be lost if you leave this page. Are you sure you want to continue?';

  String get confirmButtonText => 'Leave';

  String get cancelButtonText => 'Stay';

  void onConfirmLeave() {}

  /// Set once the user has agreed to leave, so they are asked only once.
  ///
  /// [onConfirmLeave] resets the form for leaving, which can leave it looking
  /// changed — an edit form measures "unsaved" against what it loaded, and a
  /// reset form no longer matches that. And on Android the back press reaches
  /// [handleWillPop] twice, from `WillPopScope` and then from `PopScope`. The
  /// second look would find unsaved data and ask again straight after "Leave".
  bool _confirmedLeave = false;

  Future<bool> _showDataLossWarning() async {
    final result = await DataLossWarningDialog.show(
      context: context,
      title: dataLossTitle,
      message: dataLossMessage,
      confirmText: confirmButtonText,
      cancelText: cancelButtonText,
    );

    if (result == true) {
      _confirmedLeave = true;
      onConfirmLeave();
    }

    return result ?? false;
  }

  /// Whether this platform needs the `WillPopScope` back guard on top of the
  /// form's `PopScope`: Android. A test poses as Android through this.
  @visibleForTesting
  bool get needsWillPopScope => Platform.isAndroid;

  /// [child] (the form's `PopScope`) with the Android back guard around it.
  ///
  /// The wrapper depends on the platform and on nothing else. It must not
  /// depend on whether the form has unsaved changes: a wrapper that appears
  /// when the form first changes is a different widget at the root, so Flutter
  /// builds everything under it again from scratch — and the page, however far
  /// the user had scrolled, jumps back to the top (and the field they were
  /// typing in loses focus). [handleWillPop] lets a form with nothing to lose
  /// go straight through, so the guard costs a clean form nothing.
  Widget withBackGuard(Widget child) => needsWillPopScope
      ? WillPopScope(onWillPop: () => handleWillPop(), child: child)
      : child;

  Future<bool> handleWillPop() async {
    if (_confirmedLeave || !hasUnsavedData) {
      return true;
    }

    return await _showDataLossWarning();
  }

  Future<void> handleNavigation(VoidCallback navigationAction) async {
    if (_confirmedLeave || !hasUnsavedData) {
      navigationAction();
      return;
    }

    final shouldLeave = await _showDataLossWarning();
    if (shouldLeave) {
      navigationAction();
    }
  }
}
