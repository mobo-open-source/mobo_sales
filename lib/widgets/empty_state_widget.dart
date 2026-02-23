import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:lottie/lottie.dart';
import 'package:mobo_sales/utils/app_theme.dart';

class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final bool showRetry;
  final VoidCallback? onRetry;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.showRetry = false,
    this.onRetry,
  });

  factory EmptyStateWidget.customers({
    bool hasSearchQuery = false,
    bool hasFilters = false,
    VoidCallback? onClearFilters,
    VoidCallback? onRetry,
  }) {
    return EmptyStateWidget(
      icon: HugeIcons.strokeRoundedUserMultiple,
      title: hasSearchQuery || hasFilters
          ? 'No customers found'
          : 'No customers yet',
      message: hasSearchQuery
          ? 'No customers match your search criteria. Try different keywords.'
          : hasFilters
          ? 'No customers match your filters. Try adjusting your filter settings.'
          : 'Start by adding your first customer to begin managing your contacts.',
      actionLabel: hasFilters ? 'Clear Filters' : null,
      onAction: onClearFilters,
      showRetry: true,
      onRetry: onRetry,
    );
  }

  factory EmptyStateWidget.products({
    bool hasSearchQuery = false,
    bool hasFilters = false,
    VoidCallback? onClearFilters,
    VoidCallback? onRetry,
  }) {
    return EmptyStateWidget(
      icon: HugeIcons.strokeRoundedPackage,
      title: hasSearchQuery || hasFilters
          ? 'No products found'
          : 'No products yet',
      message: hasSearchQuery
          ? 'No products match your search criteria. Try different keywords.'
          : hasFilters
          ? 'No products match your filters. Try adjusting your filter settings.'
          : 'Start by adding your first product to begin managing your inventory.',
      actionLabel: hasFilters ? 'Clear Filters' : null,
      onAction: onClearFilters,
      showRetry: true,
      onRetry: onRetry,
    );
  }

  factory EmptyStateWidget.invoices({
    bool hasSearchQuery = false,
    bool hasFilters = false,
    VoidCallback? onClearFilters,
    VoidCallback? onRetry,
  }) {
    return EmptyStateWidget(
      icon: HugeIcons.strokeRoundedInvoice,
      title: hasSearchQuery || hasFilters
          ? 'No invoices found'
          : 'No invoices yet',
      message: hasSearchQuery
          ? 'No invoices match your search criteria. Try different keywords.'
          : hasFilters
          ? 'No invoices match your filters. Try adjusting your filter settings.'
          : 'Start by creating your first invoice to begin tracking payments.',
      actionLabel: hasFilters ? 'Clear Filters' : null,
      onAction: onClearFilters,
      showRetry: true,
      onRetry: onRetry,
    );
  }

  factory EmptyStateWidget.quotations({
    bool hasSearchQuery = false,
    bool hasFilters = false,
    VoidCallback? onClearFilters,
    VoidCallback? onRetry,
  }) {
    return EmptyStateWidget(
      icon: HugeIcons.strokeRoundedFileScript,
      title: hasSearchQuery || hasFilters
          ? 'No quotations found'
          : 'No quotations yet',
      message: hasSearchQuery
          ? 'No quotations match your search criteria. Try different keywords.'
          : hasFilters
          ? 'No quotations match your filters. Try adjusting your filter settings.'
          : 'Start by creating your first quotation to begin tracking sales opportunities.',
      actionLabel: hasFilters ? 'Clear Filters' : null,
      onAction: onClearFilters,
      showRetry: true,
      onRetry: onRetry,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final messageColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.asset(
              'assets/lotti/empty_ghost.json',
              width: 200,
              height: 200,
              fit: BoxFit.contain,
              repeat: true,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: titleColor,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(fontSize: 15, color: messageColor, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                if (actionLabel != null && onAction != null)
                  OutlinedButton(
                    onPressed: onAction,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      side: BorderSide(color: AppTheme.primaryColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      foregroundColor: AppTheme.primaryColor,
                    ),
                    child: Text(
                      actionLabel!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                if (showRetry && onRetry != null)
                  ElevatedButton(
                    onPressed: onRetry,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Retry',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                if (secondaryActionLabel != null && onSecondaryAction != null)
                  TextButton.icon(
                    onPressed: onSecondaryAction,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: Text(
                      secondaryActionLabel!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
