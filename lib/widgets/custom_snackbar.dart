import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart' show navigatorKey;

enum SnackbarType { info, success, warning, error }

/// The app's message bar: a card that slides up from the bottom, stays three
/// seconds, and goes on a swipe or a tap on its ✕.
///
/// It lives in the app's root overlay, not in a route of its own. That matters
/// in three ways the previous, dialog-based version got wrong:
///
/// * A `Navigator.pop` straight after showing it pops the *page*. As a dialog
///   route it was the top route, so the pop removed the message and the screen
///   stayed — the "success message never appears" bug on every
///   show-then-close flow.
/// * It does not dim or block the screen behind it; a tap passes through.
/// * It still shows when the screen that asked for it has just been popped,
///   which is how most "saved, going back" flows end.
///
/// Only one is on screen at a time; a new message replaces the old one.
class CustomSnackbar {
  /// Shows a custom snackbar with the specified [title], [message], and [type].
  static void show({
    required BuildContext context,
    required String title,
    required String message,
    SnackbarType type = SnackbarType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    _showOverlaySnackbar(context, title, message, type, duration);
  }

  static OverlayEntry? _current;
  static Timer? _timer;

  /// Removes the snackbar on screen, if any.
  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    final entry = _current;
    _current = null;
    if (entry != null && entry.mounted) entry.remove();
  }

  /// The root overlay: the app's own, so it outlives the screen that asked; the
  /// one above [context] when the app's navigator is not available (a test, or
  /// before the app is up).
  static OverlayState? _overlayFor(BuildContext context) {
    final root = navigatorKey.currentState?.overlay;
    if (root != null) return root;
    if (!context.mounted) return null;
    return Overlay.maybeOf(context, rootOverlay: true);
  }

  static void _showOverlaySnackbar(
    BuildContext context,
    String title,
    String message,
    SnackbarType type,
    Duration duration,
  ) {
    try {
      final overlay = _overlayFor(context);
      if (overlay == null) return;

      bool isDark = false;
      try {
        final themeContext = context.mounted
            ? context
            : (navigatorKey.currentContext ?? context);
        isDark = Theme.of(themeContext).brightness == Brightness.dark;
      } catch (e) {}

      dismiss();

      final colors = _getColorsForType(type, isDark);
      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (overlayContext) => Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _SnackbarCard(
            title: title,
            message: message,
            colors: colors,
            isDark: isDark,
            onDismiss: () {
              if (identical(_current, entry)) dismiss();
            },
          ),
        ),
      );
      _current = entry;
      overlay.insert(entry);

      _timer = Timer(duration, () {
        if (identical(_current, entry)) dismiss();
      });
    } catch (e) {}
  }

  static _SnackbarColors _getColorsForType(SnackbarType type, bool isDark) {
    switch (type) {
      case SnackbarType.info:
        return _SnackbarColors(
          icon: Icons.info_outline,
          iconColor: Colors.blue[300]!,
          iconBackgroundColor: Colors.blue.withValues(alpha: 0.2),
          backgroundColor: isDark
              ? const Color(0xFF2D3748)
              : const Color(0xFF4A5568),
        );
      case SnackbarType.success:
        return _SnackbarColors(
          icon: Icons.check_circle_outline,
          iconColor: Colors.green[300]!,
          iconBackgroundColor: Colors.green.withValues(alpha: 0.2),
          backgroundColor: isDark
              ? const Color(0xFF2D4A3D)
              : const Color(0xFF4A6B5A),
        );
      case SnackbarType.warning:
        return _SnackbarColors(
          icon: Icons.warning_outlined,
          iconColor: Colors.orange[300]!,
          iconBackgroundColor: Colors.orange.withValues(alpha: 0.2),
          backgroundColor: isDark
              ? const Color(0xFF4A3D2D)
              : const Color(0xFF6B5A4A),
        );
      case SnackbarType.error:
        return _SnackbarColors(
          icon: Icons.error_outline,
          iconColor: Colors.red[300]!,
          iconBackgroundColor: Colors.red.withValues(alpha: 0.2),
          backgroundColor: isDark
              ? const Color(0xFF4A2D2D)
              : const Color(0xFF6B4A4A),
        );
    }
  }

  static void showSuccess(BuildContext context, String message) {
    show(
      context: context,
      title: 'Success',
      message: message,
      type: SnackbarType.success,
    );
  }

  static void showError(BuildContext context, String message) {
    show(
      context: context,
      title: 'Error',
      message: message,
      type: SnackbarType.error,
      // An error is read, not glanced at: a second more for every ~35
      // characters, between three seconds and eight.
      duration: Duration(seconds: (3 + message.length ~/ 35).clamp(3, 8)),
    );
  }

  static void showInfo(BuildContext context, String message) {
    show(
      context: context,
      title: 'Info',
      message: message,
      type: SnackbarType.info,
    );
  }

  static void showWarning(BuildContext context, String message) {
    show(
      context: context,
      title: 'Warning',
      message: message,
      type: SnackbarType.warning,
    );
  }
}

/// The card itself: slides up and fades in, swipes away either way. Only the
/// card takes touches; the rest of the screen stays live.
class _SnackbarCard extends StatefulWidget {
  const _SnackbarCard({
    required this.title,
    required this.message,
    required this.colors,
    required this.isDark,
    required this.onDismiss,
  });

  final String title;
  final String message;
  final _SnackbarColors colors;
  final bool isDark;
  final VoidCallback onDismiss;

  @override
  State<_SnackbarCard> createState() => _SnackbarCardState();
}

class _SnackbarCardState extends State<_SnackbarCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final isDark = widget.isDark;
    final keyboard = MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0;

    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _in, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.4),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: _in, curve: Curves.easeOutCubic)),
            child: Dismissible(
              key: UniqueKey(),
              direction: DismissDirection.horizontal,
              onDismissed: (_) => widget.onDismiss(),
              child: Container(
                margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colors.iconBackgroundColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        colors.icon,
                        size: 16,
                        color: colors.iconColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 160),
                            child: SingleChildScrollView(
                              child: Text(
                                widget.message,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey[300]
                                      : Colors.grey[100],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: widget.onDismiss,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: isDark ? Colors.grey[300] : Colors.grey[100],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SnackbarColors {
  final IconData icon;
  final Color iconColor;
  final Color iconBackgroundColor;
  final Color backgroundColor;

  _SnackbarColors({
    required this.icon,
    required this.iconColor,
    required this.iconBackgroundColor,
    required this.backgroundColor,
  });
}
