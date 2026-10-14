import 'package:flutter/material.dart';

import '../services/sales_access.dart';
import '../shared/design/mobo_tokens.dart';

/// The popup a sign-in ends in when the account may not use the app, or that
/// could not be checked: a red ⓘ and the title on one line, a short paragraph
/// under it, and one full-width button.
///
/// One layout for every outcome — no Sales access, no Sales module, a portal
/// user, an access check that could not be made — with only the words changing.
/// At sign-in the button reads "Back to Login" and the Sign In screen closes
/// behind it, back to the server (URL) screen. In Add Account the button reads
/// "OK" and the screen closes behind it, back to Configuration. Either way the
/// user is not taken into the app.
class AccessDeniedDialog extends StatelessWidget {
  const AccessDeniedDialog({
    super.key,
    required this.title,
    required this.message,
    this.buttonLabel = defaultButtonLabel,
  });

  /// What the button says at sign-in. Where the user is already inside the app
  /// (adding a second account) "OK" is the honest label instead.
  static const String defaultButtonLabel = 'Back to Login';

  static const String deniedTitle = 'Access Denied';
  static const String deniedMessage =
      "Your account doesn't have access to the Sales app. "
      'Please contact your administrator to grant you Sales access.';

  static const String moduleMissingTitle = 'Module Missing';
  static const String moduleMissingMessage =
      'The required "Sales" module is not installed on this server. '
      'Please contact your administrator to enable it.';

  static const String portalTitle = 'Portal Access Not Allowed';
  static const String portalMessage =
      "This account is a portal user, and portal users can't use this app. "
      'Please sign in with an internal user account, or contact your '
      'administrator.';

  static const String unverifiedTitle = 'Unable to Verify Access';
  static const String unverifiedMessage =
      "We couldn't check whether your account has access to the Sales app. "
      'Please check your connection and try again.';

  final String title;
  final String message;
  final String buttonLabel;

  /// Shows the dialog for [error] if it is a [SalesAccessException], and says
  /// whether it was one. A caller puts this first in its `catch`, and treats
  /// `true` as "handled":
  ///
  /// ```dart
  /// } catch (e) {
  ///   if (await AccessDeniedDialog.showIfAccessError(context, e)) return;
  ///   ...
  /// }
  /// ```
  static Future<bool> showIfAccessError(
    BuildContext context,
    Object error, {
    String buttonLabel = defaultButtonLabel,
  }) async {
    if (error is! SalesAccessException) return false;
    if (context.mounted) {
      await showFor(context, error, buttonLabel: buttonLabel);
    }
    return true;
  }

  /// Shows the dialog worded for what [error] found.
  static Future<void> showFor(
    BuildContext context,
    SalesAccessException error, {
    String buttonLabel = defaultButtonLabel,
  }) {
    switch (error.status) {
      case SalesAccessStatus.moduleMissing:
        return show(
          context,
          title: moduleMissingTitle,
          message: moduleMissingMessage,
          buttonLabel: buttonLabel,
        );
      case SalesAccessStatus.portalUser:
        return show(
          context,
          title: portalTitle,
          message: portalMessage,
          buttonLabel: buttonLabel,
        );
      case SalesAccessStatus.unverified:
        return show(
          context,
          title: unverifiedTitle,
          message: unverifiedMessage,
          buttonLabel: buttonLabel,
        );
      case SalesAccessStatus.denied:
      case SalesAccessStatus.granted:
        return show(
          context,
          title: deniedTitle,
          message: deniedMessage,
          buttonLabel: buttonLabel,
        );
    }
  }

  static Future<void> show(
    BuildContext context, {
    String title = deniedTitle,
    String message = deniedMessage,
    String buttonLabel = defaultButtonLabel,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: AccessDeniedDialog(
          title: title,
          message: message,
          buttonLabel: buttonLabel,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = context.mobo;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      elevation: 8,
      child: ConstrainedBox(
        // A phone's width; on a tablet the card stays a card.
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, size: 28, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // The paragraph scrolls on a screen too short for it, so the button
              // below is never pushed out of the dialog.
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.45,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: MoboType.button().copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(buttonLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
