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

  Future<bool> _showDataLossWarning() async {
    final result = await DataLossWarningDialog.show(
      context: context,
      title: dataLossTitle,
      message: dataLossMessage,
      confirmText: confirmButtonText,
      cancelText: cancelButtonText,
    );

    if (result == true) {
      onConfirmLeave();
    }

    return result ?? false;
  }

  Future<bool> handleWillPop() async {
    if (!hasUnsavedData) {
      return true;
    }

    return await _showDataLossWarning();
  }

  Future<void> handleNavigation(VoidCallback navigationAction) async {
    if (!hasUnsavedData) {
      navigationAction();
      return;
    }

    final shouldLeave = await _showDataLossWarning();
    if (shouldLeave) {
      navigationAction();
    }
  }
}
