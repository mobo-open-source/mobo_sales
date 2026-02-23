import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/app_theme.dart';

class CustomDropdownField extends StatelessWidget {
  final String? value;
  final String labelText;
  final String? hintText;
  final ValueChanged<String?>? onChanged;
  final String? Function(String?) validator;
  final bool isDark;
  final List<DropdownMenuItem<String>> items;
  final bool showBorder;

  const CustomDropdownField({
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
            fontFamily: GoogleFonts.manrope(
              fontWeight: FontWeight.w400,
            ).fontFamily,
            color: isDark ? Colors.white70 : Color(0xff7F7F7F),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          hint: hintText != null
              ? Text(
                  hintText!,
                  style: TextStyle(
                    fontFamily: GoogleFonts.manrope(
                      fontWeight: FontWeight.w400,
                    ).fontFamily,
                    color: isDark ? Colors.white54 : Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                  overflow: TextOverflow.ellipsis,
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
              fontFamily: GoogleFonts.manrope(
                fontWeight: FontWeight.w400,
              ).fontFamily,
              color: isDark ? Colors.white70 : Color(0xff7F7F7F),
            ),
          ),
          style: TextStyle(
            fontFamily: GoogleFonts.manrope(
              fontWeight: FontWeight.w600,
            ).fontFamily,
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
