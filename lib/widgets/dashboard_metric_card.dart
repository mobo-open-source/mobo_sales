import 'package:flutter/material.dart';

class DashboardMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final String? tooltip;
  final bool isApproximate;
  final Color? accentColor;
  final bool isCompact;

  const DashboardMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    this.tooltip,
    this.isApproximate = false,
    this.accentColor,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        minWidth: isCompact ? 140 : 160,
        maxWidth: isCompact ? 200 : 240,
        minHeight: isCompact ? 90 : 120,
      ),
      margin: EdgeInsets.symmetric(
        vertical: isCompact ? 6 : 8,
        horizontal: isCompact ? 4 : 6,
      ),
      padding: EdgeInsets.all(isCompact ? 16 : 20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(isCompact ? 12 : 16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.08),
            blurRadius: isCompact ? 12 : 20,
            spreadRadius: 0,
            offset: Offset(0, isCompact ? 2 : 4),
          ),
        ],
        border: isDark
            ? Border.all(color: Colors.grey[800]!.withOpacity(0.5), width: 0.5)
            : null,
      ),
      child: isCompact ? _buildCompactLayout(isDark) : _buildFullLayout(isDark),
    );
  }

  Widget _buildFullLayout(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey[300] : Colors.grey[600],
            letterSpacing: 0.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 12),

        Tooltip(
          message: tooltip ?? value,
          triggerMode: TooltipTriggerMode.longPress,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (isApproximate)
                Text(
                  '≈ ',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    color: isDark ? Colors.grey[400] : Colors.grey[500],
                  ),
                ),
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.grey[900],
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        Text(
          subtitle,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.grey[400] : Colors.grey[500],
            height: 1.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),

        if (accentColor != null) ...[
          const SizedBox(height: 12),
          Container(
            height: 3,
            width: 40,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCompactLayout(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (isApproximate)
              Text(
                '≈ ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: isDark ? Colors.grey[400] : Colors.grey[500],
                ),
              ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.grey[900],
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),

        const SizedBox(height: 4),

        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey[300] : Colors.grey[600],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 2),

        Text(
          subtitle,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.grey[400] : Colors.grey[500],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

Widget buildMetricCard(
  BuildContext context,
  String title,
  String value,
  String subtitle, {
  String? tooltip,
  bool isApproximate = false,
  Color? accentColor,
  bool isCompact = false,
}) {
  return DashboardMetricCard(
    title: title,
    value: value,
    subtitle: subtitle,
    tooltip: tooltip,
    isApproximate: isApproximate,
    accentColor: accentColor,
    isCompact: isCompact,
  );
}
