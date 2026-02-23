import 'package:flutter/material.dart';

enum SnackbarType { info, success, warning, error }

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

  static void _showOverlaySnackbar(
    BuildContext context,
    String title,
    String message,
    SnackbarType type,
    Duration duration,
  ) {
    try {
      if (!context.mounted) {
        return;
      }

      bool isDark = false;
      try {
        isDark = Theme.of(context).brightness == Brightness.dark;
      } catch (e) {}

      final colors = _getColorsForType(type, isDark);

      showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(0.1),
        builder: (dialogContext) {
          Future.delayed(duration, () {
            if (dialogContext.mounted) {
              try {
                Navigator.of(dialogContext).pop();
              } catch (e) {}
            }
          });

          return Material(
            type: MaterialType.transparency,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Dismissible(
                key: UniqueKey(),
                direction: DismissDirection.horizontal,
                onDismissed: (direction) {
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(
                    bottom: 100,
                    left: 16,
                    right: 16,
                  ),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
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
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                message,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey[300]
                                      : Colors.grey[100],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        },
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
          );
        },
      );
    } catch (e) {}
  }

  static _SnackbarColors _getColorsForType(SnackbarType type, bool isDark) {
    switch (type) {
      case SnackbarType.info:
        return _SnackbarColors(
          icon: Icons.info_outline,
          iconColor: Colors.blue[300]!,
          iconBackgroundColor: Colors.blue.withOpacity(0.2),
          backgroundColor: isDark
              ? const Color(0xFF2D3748)
              : const Color(0xFF4A5568),
        );
      case SnackbarType.success:
        return _SnackbarColors(
          icon: Icons.check_circle_outline,
          iconColor: Colors.green[300]!,
          iconBackgroundColor: Colors.green.withOpacity(0.2),
          backgroundColor: isDark
              ? const Color(0xFF2D4A3D)
              : const Color(0xFF4A6B5A),
        );
      case SnackbarType.warning:
        return _SnackbarColors(
          icon: Icons.warning_outlined,
          iconColor: Colors.orange[300]!,
          iconBackgroundColor: Colors.orange.withOpacity(0.2),
          backgroundColor: isDark
              ? const Color(0xFF4A3D2D)
              : const Color(0xFF6B5A4A),
        );
      case SnackbarType.error:
        return _SnackbarColors(
          icon: Icons.error_outline,
          iconColor: Colors.red[300]!,
          iconBackgroundColor: Colors.red.withOpacity(0.2),
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
