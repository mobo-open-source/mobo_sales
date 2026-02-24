import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:shimmer/shimmer.dart';
import '../utils/tap_prevention.dart';

class RecentItemsWidget extends StatelessWidget {
  final List<Map<String, dynamic>> recentItems;
  final bool isLoading;
  final bool isDark;
  final VoidCallback? onViewAll;

  const RecentItemsWidget({
    super.key,
    required this.recentItems,
    required this.isLoading,
    required this.isDark,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Continue Working On',
          style: TextStyle(
            fontSize: 18,
            fontFamily: GoogleFonts.inter().fontFamily,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        if (isLoading)
          _buildLoadingState()
        else if (recentItems.isEmpty)
          _buildEmptyState()
        else
          _buildRecentItemsList(),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Column(
      children: List.generate(
        3,
        (index) => Container(
          constraints: const BoxConstraints(minHeight: 80),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[850] : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
                blurRadius: 16,
                spreadRadius: 2,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: _buildRecentItemShimmer(),
        ),
      ),
    );
  }

  Widget _buildRecentItemShimmer() {
    final shimmerBase = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final shimmerHighlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: shimmerBase,
      highlightColor: shimmerHighlight,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 14,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: shimmerBase,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  height: 12,
                  width: 120,
                  decoration: BoxDecoration(
                    color: shimmerBase,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 11,
            width: 50,
            decoration: BoxDecoration(
              color: shimmerBase,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              HugeIcons.strokeRoundedClock01,
              size: 32,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 8),
            Text(
              'No recent items',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your recently viewed items will appear here',
              style: TextStyle(
                color: isDark ? Colors.grey[500] : Colors.grey[500],
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentItemsList() {
    return Column(
      children: recentItems
          .take(5)
          .map(
            (item) => Container(
              constraints: const BoxConstraints(minHeight: 80),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black26
                        : Colors.black.withOpacity(0.05),
                    blurRadius: 16,
                    spreadRadius: 2,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: _buildRecentItem(item),
            ),
          )
          .toList(),
    );
  }

  Widget _buildRecentItem(Map<String, dynamic> item) {
    final type = item['type'] ?? '';
    final name = item['name'] ?? 'Unknown';
    final subtitle = item['subtitle'] ?? '';
    final lastModified = item['lastModified'] ?? '';
    final onTap = item['onTap'] as VoidCallback?;
    final itemId = item['id']?.toString() ?? name.hashCode.toString();

    return InkWell(
      onTap: () {
        if (onTap == null) return;
        final tapKey = 'continue_working_${type}_$itemId';
        TapPrevention.executeListItemTap(tapKey, onTap);
      },
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (lastModified.isNotEmpty)
            Text(
              lastModified,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[500] : Colors.grey[500],
              ),
            ),
        ],
      ),
    );
  }

  IconData _getTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'quotation':
        return HugeIcons.strokeRoundedFiles01;
      case 'invoice':
        return HugeIcons.strokeRoundedInvoice03;
      case 'customer':
        return HugeIcons.strokeRoundedContact01;
      case 'product':
        return HugeIcons.strokeRoundedPackageOpen;
      default:
        return HugeIcons.strokeRoundedFile02;
    }
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'quotation':
        return const Color(0xFF4CAF50);
      case 'invoice':
        return const Color(0xFFFF9800);
      case 'customer':
        return const Color(0xFF2196F3);
      case 'product':
        return const Color(0xFF9C27B0);
      default:
        return Colors.grey;
    }
  }
}

class SmartSuggestionsWidget extends StatelessWidget {
  final List<Map<String, dynamic>> suggestions;
  final bool isLoading;
  final bool isDark;

  const SmartSuggestionsWidget({
    super.key,
    required this.suggestions,
    required this.isLoading,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Smart Suggestions',
              style: TextStyle(
                fontSize: 18,
                fontFamily: GoogleFonts.inter().fontFamily,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isLoading)
          _buildLoadingState()
        else if (suggestions.isEmpty)
          _buildEmptyState()
        else
          _buildSuggestionsList(),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Column(
      children: List.generate(
        3,
        (index) => Container(
          constraints: const BoxConstraints(minHeight: 80),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[850] : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
                blurRadius: 16,
                spreadRadius: 2,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: _buildSuggestionShimmer(),
        ),
      ),
    );
  }

  Widget _buildSuggestionShimmer() {
    final shimmerBase = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final shimmerHighlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: shimmerBase,
      highlightColor: shimmerHighlight,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: shimmerBase,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      height: 14,
                      width: 120,
                      decoration: BoxDecoration(
                        color: shimmerBase,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Container(
                      height: 16,
                      width: 40,
                      decoration: BoxDecoration(
                        color: shimmerBase,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  height: 12,
                  width: 200,
                  decoration: BoxDecoration(
                    color: shimmerBase,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              HugeIcons.strokeRoundedBulb,
              size: 32,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 8),
            Text(
              'No suggestions available',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Smart suggestions will appear here based on your activity',
              style: TextStyle(
                color: isDark ? Colors.grey[500] : Colors.grey[500],
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return Column(
      children: suggestions
          .take(5)
          .map(
            (suggestion) => Container(
              constraints: const BoxConstraints(minHeight: 80),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.white,
                borderRadius: BorderRadius.circular(12),

                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black26
                        : Colors.black.withOpacity(0.05),
                    blurRadius: 16,
                    spreadRadius: 2,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: _buildSuggestion(suggestion),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSuggestion(Map<String, dynamic> suggestion) {
    final title = suggestion['title'] ?? '';
    final description = suggestion['description'] ?? '';
    final priority = suggestion['priority'] ?? 'medium';
    final onTap = suggestion['onTap'] as VoidCallback?;

    return InkWell(
      onTap: () {
        if (onTap == null) return;
        final tapKey = 'suggestion_${title.hashCode}';
        TapPrevention.executeNavigation(tapKey, onTap);
      },
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark
                  ? _getPriorityColor(priority).withValues(alpha: 0.7)
                  : _getPriorityColor(priority).withValues(alpha: 0.1),

              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getPriorityIcon(priority),
              color: isDark ? Colors.white : _getPriorityColor(priority),

              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? _getPriorityColor(priority).withValues(alpha: 0.7)
                            : _getPriorityColor(
                                priority,
                              ).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        priority.toUpperCase(),
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.white
                              : _getPriorityColor(priority),
                        ),
                      ),
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getPriorityIcon(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return HugeIcons.strokeRoundedAlert02;
      case 'medium':
        return HugeIcons.strokeRoundedInformationCircle;
      case 'low':
        return HugeIcons.strokeRoundedCheckmarkCircle02;
      default:
        return HugeIcons.strokeRoundedInformationCircle;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return const Color(0xFFE53E3E);
      case 'medium':
        return const Color(0xFFFF9800);
      case 'low':
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey;
    }
  }
}
