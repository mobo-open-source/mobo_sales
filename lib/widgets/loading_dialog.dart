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
    this.onCancel,
    this.cancelLabel = 'Cancel',
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

  /// Lets the user give up. When null the card shows no way out, which is right
  /// for work that finishes in a second or two; anything that can run for
  /// minutes — generating a document, sending one — should pass one, because a
  /// popup with no exit is indistinguishable from a frozen app.
  final VoidCallback? onCancel;

  /// The wording on that button.
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final line = subtitle;

    final content = Semantics(
      label: line == null ? message : '$message $line',
      liveRegion: true,
      child: Padding(
        // Unchanged without an action. With one, the foot comes in to 24 so
        // the button is not left sitting in a deep margin.
        padding: EdgeInsets.fromLTRB(28, 32, 28, onCancel == null ? 32 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // Dialog content is stretched (MOBO_UI §5.10), which is what gives
          // the action its full width; the circle keeps its own size.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
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
            if (onCancel != null) ...[
              const SizedBox(height: 24),
              // The outlined secondary of MOBO_UI §5.1 — height 48, radius 12,
              // a 1.5 primary border and a 16/w700 primary label — built to
              // the same numbers as `MoboDialogButtons`, so this Cancel reads
              // as the same control as every other Cancel in the app. A grey
              // text link read as a caption, not something to press.
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primary,
                    side: BorderSide(color: primary, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      cancelLabel,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
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
    this.onCancel,
    this.cancelLabel = 'Cancel',
  });

  final String message;
  final String? subtitle;

  /// Shows a Cancel button, and makes the system back gesture mean the same
  /// thing. Null keeps the old behaviour: no way out until the caller closes
  /// it.
  final VoidCallback? onCancel;

  /// The wording on that button.
  final String cancelLabel;

  /// Shows it above the current screen and returns the dialog's future.
  /// Dismiss with `Navigator.of(context, rootNavigator: true).pop()`, or
  /// `Navigator.pop(context)` from the screen that opened it.
  static Future<void> show(
    BuildContext context, {
    String message = LoadingCard.defaultMessage,
    String? subtitle = LoadingCard.defaultSubtitle,
    VoidCallback? onCancel,
    String cancelLabel = 'Cancel',
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LoadingDialog(
        message: message,
        subtitle: subtitle,
        onCancel: onCancel,
        cancelLabel: cancelLabel,
      ),
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
    VoidCallback? onCancel,
    String cancelLabel = 'Cancel',
  }) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LoadingDialog(
        message: message,
        subtitle: subtitle,
        onCancel: onCancel,
        cancelLabel: cancelLabel,
      ),
    );
    navigator.push(route);
    return LoadingDialogHandle._(navigator, route);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cancel = onCancel;

    // Still `canPop: false`: the dialog is never dismissed behind the work's
    // back. But when there is a Cancel, the back gesture has to mean it —
    // pressing back and having nothing happen is what makes this feel stuck.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) cancel?.call();
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        elevation: 8,
        child: LoadingCard(
          message: message,
          subtitle: subtitle,
          framed: false,
          onCancel: cancel,
          cancelLabel: cancelLabel,
        ),
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
