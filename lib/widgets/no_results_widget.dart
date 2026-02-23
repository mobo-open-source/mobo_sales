import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class NoResultsWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? suggestion;
  final List<Widget>? actions;

  const NoResultsWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.suggestion,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [
                          Colors.blue[900]!.withOpacity(0.3),
                          Colors.blue[800]!.withOpacity(0.1),
                        ]
                      : [Colors.blue[50]!, Colors.blue[100]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(
                icon,
                size: 64,
                color: isDark ? Colors.blue[300] : Colors.blue[600],
              ),
            ),
            const SizedBox(height: 24),

            Text(
              title,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.grey[800],
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            Text(
              message,
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),

            if (suggestion != null) ...[
              const SizedBox(height: 12),
              Text(
                suggestion!,
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: actions!.map((action) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: action,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class NoResultsPresets {
  static NoResultsWidget customers({
    required bool hasSearchQuery,
    required VoidCallback onClearFilters,
    required VoidCallback onRetry,
  }) {
    return NoResultsWidget(
      icon: Icons.person_off,
      title: 'No Customers Found',
      message: hasSearchQuery
          ? 'No customers match your search criteria'
          : 'No customers available',
      suggestion: hasSearchQuery ? 'Try a different search term' : null,
      actions: [
        OutlinedButton.icon(
          onPressed: onClearFilters,
          icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
          label: const Text('Clear Filters'),
        ),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Retry'),
        ),
      ],
    );
  }

  static NoResultsWidget products({
    required bool hasActiveFilters,
    required String? searchQuery,
    required VoidCallback onClearFilters,
    required VoidCallback onRetry,
  }) {
    String message;
    if (searchQuery != null && searchQuery.isNotEmpty) {
      message = 'No products found for "$searchQuery"';
    } else if (hasActiveFilters) {
      message = 'No products match the applied filters';
    } else {
      message = 'No products available';
    }

    return NoResultsWidget(
      icon: HugeIcons.strokeRoundedPackageOutOfStock,
      title: hasActiveFilters ? 'No Matching Products' : 'No Products Found',
      message: message,
      suggestion: hasActiveFilters
          ? 'Try adjusting your filters to see more results'
          : null,
      actions: [
        OutlinedButton.icon(
          onPressed: onClearFilters,
          icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
          label: const Text('Clear Filters'),
        ),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Retry'),
        ),
      ],
    );
  }

  static NoResultsWidget invoices({required VoidCallback onRetry}) {
    return NoResultsWidget(
      icon: Icons.receipt_long,
      title: 'No Invoices Found',
      message: 'No invoices available',
      actions: [
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  static NoResultsWidget quotations({
    required bool hasActiveFilters,
    required VoidCallback onClearFilters,
  }) {
    return NoResultsWidget(
      icon: HugeIcons.strokeRoundedNote02,
      title: hasActiveFilters
          ? 'No Matching Quotations'
          : 'No Quotations Found',
      message: hasActiveFilters
          ? 'No quotations match the applied filters'
          : 'Create your first quotation to get started',
      suggestion: hasActiveFilters
          ? 'Try adjusting your filters to see more results'
          : null,
      actions: hasActiveFilters
          ? [
              ElevatedButton.icon(
                onPressed: onClearFilters,
                icon: const Icon(Icons.clear_all, color: Colors.white),
                label: const Text('Clear Filters'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ]
          : null,
    );
  }
}
