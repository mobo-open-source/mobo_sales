import 'package:flutter/material.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

class CustomDateSelector extends StatelessWidget {
  final VoidCallback onTap;
  final DateTime selectedDate;
  final String labelText;
  final bool isDark;
  final bool showBorder;
  final String? dateFormat;

  const CustomDateSelector({
    required this.onTap,
    required this.selectedDate,
    required this.labelText,
    this.isDark = false,
    this.showBorder = false,
    this.dateFormat,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final format = dateFormat ?? 'MMM dd, yyyy';

    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            labelText,
            style: TextStyle(
              fontWeight: FontWeight.w400,
              color: isDark ? Colors.white70 : Color(0xff7F7F7F),
            ),
          ),
          SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A2A) : Color(0xffF8FAFB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedCalendar01,
                  color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    DateFormat(format).format(selectedDate),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Color(0xff000000),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
