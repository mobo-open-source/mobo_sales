import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

class CustomGenericDropdownField<T> extends StatelessWidget {
  final T? value;
  final String labelText;
  final String? hintText;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?) validator;
  final bool isDark;
  final List<DropdownMenuItem<T>> items;
  final bool showBorder;

  const CustomGenericDropdownField({
    required this.value,
    required this.labelText,
    required this.onChanged,
    required this.validator,
    required this.items,
    this.hintText,
    this.isDark = false,
    this.showBorder = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: TextStyle(
            fontWeight: FontWeight.w400,
            color: isDark ? Colors.white70 : Color(0xff7F7F7F),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<T>(
          isExpanded: true,
          initialValue: value,
          hint: hintText != null
              ? Text(
                  hintText!,
                  style: TextStyle(
                    fontWeight: FontWeight.w400,
                    color: isDark ? Colors.white54 : Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                )
              : null,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: showBorder
                    ? _getBorderColor(context)
                    : Colors.transparent,
                width: showBorder ? 2 : 0,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppTheme.primaryColor,
                width: showBorder ? 2 : 0,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: showBorder
                    ? _getBorderColor(context)
                    : Colors.transparent,
                width: showBorder ? 2 : 0,
              ),
            ),
            filled: true,
            fillColor: isDark ? const Color(0xFF2A2A2A) : Color(0xffF8FAFB),
            labelStyle: TextStyle(
              fontWeight: FontWeight.w400,
              color: isDark ? Colors.white70 : Color(0xff7F7F7F),
            ),
          ),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Color(0xff000000),
          ),
          dropdownColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          items: items,
          onChanged: onChanged,
          validator: validator,
        ),
      ],
    );
  }

  Color _getBorderColor(BuildContext context) {
    return isDark ? Colors.grey[700]! : Colors.grey[400]!;
  }
}
