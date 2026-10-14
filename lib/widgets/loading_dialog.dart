import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

/// The one loading popup of the app: a white rounded card with the four
/// rotating dots in a pale brand-coloured circle, a title ("Creating
/// quotation...") and a line under it saying what is going on ("Please wait
/// while we create your quotation.").
///
/// Every screen that blocks on work — creating, saving, switching, deleting,
/// preparing a document — shows this and nothing else, so the wait always looks
/// the same.
///
/// There are two ways to put it on screen:
///
/// * [LoadingDialog] as the `builder` of `showDialog`, which keeps the usual
///   route: close it with `Navigator.pop`, as with any dialog.
/// * [LoadingCard] on its own, inside a `Stack` that already dims the page.
class LoadingCard extends StatelessWidget {
  const LoadingCard({
    super.key,
    this.message = defaultMessage,
    this.subtitle = defaultSubtitle,
    this.framed = true,
  });

  static const String defaultMessage = 'Processing...';
  static const String defaultSubtitle = 'Please wait a moment.';

  /// The title, one short line.
  final String message;

  /// The line under it. Null leaves it out.
  final String? subtitle;

  /// Draws the white rounded card around the content. On its own, over a dimmed
  /// page, it should; [LoadingDialog] sits it inside a `Dialog` that already is
  /// one.
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final line = subtitle;

    final content = Semantics(
      label: line == null ? message : '$message $line',
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(16),
              child: LoadingAnimationWidget.fourRotatingDots(
                color: primary,
                size: 50,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            if (line != null) ...[
              const SizedBox(height: 8),
              Text(
                line,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (!framed) return content;
    return Material(
      color: isDark ? Colors.grey[900] : Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
        child: IntrinsicWidth(child: content),
      ),
    );
  }
}

/// [LoadingCard] as a dialog, framed like the app's other dialogs and not
/// dismissible by the back button. The caller closes it, as it closed the
/// dialog it replaces.
class LoadingDialog extends StatelessWidget {
  const LoadingDialog({
    super.key,
    this.message = LoadingCard.defaultMessage,
    this.subtitle = LoadingCard.defaultSubtitle,
  });

  final String message;
  final String? subtitle;

  /// Shows it above the current screen and returns the dialog's future.
  /// Dismiss with `Navigator.of(context, rootNavigator: true).pop()`, or
  /// `Navigator.pop(context)` from the screen that opened it.
  static Future<void> show(
    BuildContext context, {
    String message = LoadingCard.defaultMessage,
    String? subtitle = LoadingCard.defaultSubtitle,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LoadingDialog(message: message, subtitle: subtitle),
    );
  }

  /// Opens it and hands back a [LoadingDialogHandle] that closes exactly this
  /// dialog, once, however often and whenever it is asked. The way to use it
  /// around work that can finish, fail and clean up in any order:
  ///
  /// ```dart
  /// final loading = LoadingDialog.open(context, message: 'Saving...');
  /// try {
  ///   await save();
  /// } finally {
  ///   loading.close();
  /// }
  /// ```
  static LoadingDialogHandle open(
    BuildContext context, {
    String message = LoadingCard.defaultMessage,
    String? subtitle = LoadingCard.defaultSubtitle,
  }) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LoadingDialog(message: message, subtitle: subtitle),
    );
    navigator.push(route);
    return LoadingDialogHandle._(navigator, route);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        elevation: 8,
        child: LoadingCard(message: message, subtitle: subtitle, framed: false),
      ),
    );
  }
}

/// Closes one [LoadingDialog] that [LoadingDialog.open] showed.
///
/// A bare `Navigator.pop` closes whatever is on top, and a `pop` in a `finally`
/// that runs after the success path has already closed the dialog and the
/// screen takes the screen underneath with it. This closes its own route and
/// nothing else, and closing again does nothing.
class LoadingDialogHandle {
  LoadingDialogHandle._(this._navigator, this._route);

  final NavigatorState _navigator;
  final Route<void> _route;

  /// Whether the dialog is still on screen.
  bool get isOpen => _route.isActive;

  void close() {
    if (!_route.isActive) return;
    if (_route.isCurrent) {
      _navigator.pop();
    } else {
      // Something was pushed above it (a snackbar route, a confirmation): take
      // the dialog out from under it rather than closing the thing on top.
      _navigator.removeRoute(_route);
    }
  }
}
