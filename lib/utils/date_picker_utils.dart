import 'package:flutter/material.dart';

/// Utility class for showing themed date and time pickers.
class DatePickerUtils {
  /// Displays a themed Material date picker.
  static Future<DateTime?> showStandardDatePicker({
    required BuildContext context,
    DateTime? initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    String? helpText,
    String? cancelText,
    String? confirmText,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: firstDate ?? DateTime(2020),
      lastDate: lastDate ?? DateTime(2030),
      helpText: helpText,
      cancelText: cancelText,
      confirmText: confirmText,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: primaryColor,
              onPrimary: Colors.white,
              surface: isDark ? Colors.grey[850] : Colors.white,
              onSurface: isDark ? Colors.white : Colors.black,
              surfaceContainerHighest: isDark
                  ? Colors.grey[800]
                  : Colors.grey[100],
              onSurfaceVariant: isDark ? Colors.grey[300] : Colors.grey[700],
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: primaryColor,
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: isDark ? Colors.grey[850] : Colors.white,
              headerBackgroundColor: primaryColor,
              headerForegroundColor: Colors.white,
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return isDark ? Colors.white : Colors.black;
              }),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return primaryColor;
                }
                return Colors.transparent;
              }),
              todayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return primaryColor;
              }),
              todayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return primaryColor;
                }
                return Colors.transparent;
              }),
              todayBorder: BorderSide(color: primaryColor, width: 1),
              yearForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return isDark ? Colors.white : Colors.black;
              }),
              yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return primaryColor;
                }
                return Colors.transparent;
              }),
              rangePickerBackgroundColor: isDark
                  ? Colors.grey[850]
                  : Colors.white,
              rangePickerHeaderBackgroundColor: primaryColor,
              rangePickerHeaderForegroundColor: Colors.white,
              rangeSelectionBackgroundColor: primaryColor.withOpacity(0.1),
              rangeSelectionOverlayColor: WidgetStateProperty.all(
                primaryColor.withOpacity(0.1),
              ),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: isDark ? Colors.grey[850] : Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
  }

  /// Displays a themed Material time picker.
  static Future<TimeOfDay?> showStandardTimePicker({
    required BuildContext context,
    TimeOfDay? initialTime,
    String? helpText,
    String? cancelText,
    String? confirmText,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return await showTimePicker(
      context: context,
      initialTime: initialTime ?? TimeOfDay.now(),
      helpText: helpText,
      cancelText: cancelText,
      confirmText: confirmText,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: primaryColor,
              onPrimary: Colors.white,
              surface: isDark ? Colors.grey[850] : Colors.white,
              onSurface: isDark ? Colors.white : Colors.black,
              surfaceContainerHighest: isDark
                  ? Colors.grey[800]
                  : Colors.grey[100],
              onSurfaceVariant: isDark ? Colors.grey[300] : Colors.grey[700],
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: primaryColor,
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: isDark ? Colors.grey[850] : Colors.white,
              hourMinuteTextColor: isDark ? Colors.white : Colors.black,
              hourMinuteColor: isDark ? Colors.grey[800] : Colors.grey[100],
              dayPeriodTextColor: isDark ? Colors.white : Colors.black,
              dayPeriodColor: isDark ? Colors.grey[800] : Colors.grey[100],
              dialHandColor: primaryColor,
              dialBackgroundColor: isDark ? Colors.grey[800] : Colors.grey[100],
              dialTextColor: isDark ? Colors.white : Colors.black,
              entryModeIconColor: isDark ? Colors.white : Colors.black,
              hourMinuteTextStyle: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
              dayPeriodTextStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: isDark ? Colors.grey[850] : Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
  }
}
