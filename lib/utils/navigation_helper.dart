import 'package:flutter/material.dart';
import '../screens/invoices/invoice_details_screen.dart';
import '../screens/quotations/quotation_details_screen.dart';
import '../models/quote.dart';
import '../widgets/custom_snackbar.dart';

/// Central helper for handling deep-linking and relative navigation between Odoo documents.
class NavigationHelper {
  /// Navigates to a specific Odoo document based on [documentType] and [documentData].
  static void navigateToRelatedDocument(
    BuildContext context, {
    required String documentType,
    required Map<String, dynamic> documentData,
    bool replaceCurrentPage = true,
    bool fromLeft = false,
  }) {
    Widget targetPage;

    switch (documentType.toLowerCase()) {
      case 'invoice':
        final invoiceId = documentData['id'];
        if (invoiceId == null) {
          _showNavigationError(context, 'Invalid invoice ID');
          return;
        }
        targetPage = InvoiceDetailsPage(
          invoiceId: invoiceId.toString(),
          fromQuotationDetails: documentData['fromQuotationDetails'] ?? false,
        );
        break;

      case 'sale_order':
      case 'quotation':
        targetPage = QuotationDetailScreen(
          quotation: Quote.fromJson(documentData),
          fromInvoiceDetails: documentData['fromInvoiceDetails'] ?? false,
        );
        break;

      default:
        _showNavigationError(context, 'Unknown document type: $documentType');
        return;
    }

    if (replaceCurrentPage) {
      Navigator.pushReplacement(
        context,

        MaterialPageRoute(builder: (context) => targetPage),
      );
    } else {
      Navigator.push(
        context,

        MaterialPageRoute(builder: (context) => targetPage),
      );
    }
  }

  static void navigateToInvoice(
    BuildContext context,
    String invoiceId, {
    bool replaceCurrentPage = true,
    bool fromLeft = false,
    bool fromQuotationDetails = false,
  }) {
    navigateToRelatedDocument(
      context,
      documentType: 'invoice',
      documentData: {
        'id': invoiceId,
        'fromQuotationDetails': fromQuotationDetails,
      },
      replaceCurrentPage: replaceCurrentPage,
      fromLeft: fromLeft,
    );
  }

  static void navigateToSaleOrder(
    BuildContext context,
    Map<String, dynamic> saleOrderData, {
    bool replaceCurrentPage = true,
    bool fromLeft = false,
    bool fromInvoiceDetails = false,
  }) {
    final updatedData = Map<String, dynamic>.from(saleOrderData);
    updatedData['fromInvoiceDetails'] = fromInvoiceDetails;

    navigateToRelatedDocument(
      context,
      documentType: 'sale_order',
      documentData: updatedData,
      replaceCurrentPage: replaceCurrentPage,
      fromLeft: fromLeft,
    );
  }

  static void navigateToQuotation(
    BuildContext context,
    Map<String, dynamic> quotationData, {
    bool replaceCurrentPage = true,
    bool fromLeft = false,
    bool fromInvoiceDetails = false,
  }) {
    final updatedData = Map<String, dynamic>.from(quotationData);
    updatedData['fromInvoiceDetails'] = fromInvoiceDetails;

    navigateToRelatedDocument(
      context,
      documentType: 'quotation',
      documentData: updatedData,
      replaceCurrentPage: replaceCurrentPage,
      fromLeft: fromLeft,
    );
  }

  static void navigateAndClearStack(
    BuildContext context, {
    required String documentType,
    required Map<String, dynamic> documentData,
    bool fromLeft = false,
  }) {
    Widget targetPage;

    switch (documentType.toLowerCase()) {
      case 'invoice':
        final invoiceId = documentData['id'];
        if (invoiceId == null) {
          _showNavigationError(context, 'Invalid invoice ID');
          return;
        }
        targetPage = InvoiceDetailsPage(
          invoiceId: invoiceId.toString(),
          fromQuotationDetails: documentData['fromQuotationDetails'] ?? false,
        );
        break;

      case 'sale_order':
      case 'quotation':
        targetPage = QuotationDetailScreen(
          quotation: Quote.fromJson(documentData),
          fromInvoiceDetails: documentData['fromInvoiceDetails'] ?? false,
        );
        break;

      default:
        _showNavigationError(context, 'Unknown document type: $documentType');
        return;
    }

    Navigator.pushAndRemoveUntil(
      context,

      MaterialPageRoute(builder: (context) => targetPage),
      (route) => route.isFirst,
    );
  }

  static void _showNavigationError(BuildContext context, String message) {
    CustomSnackbar.showError(context, 'Navigation Error: $message');
  }

  static bool isInRelatedDocumentChain(BuildContext context) {
    final modalRoute = ModalRoute.of(context);
    if (modalRoute == null) return false;

    int pageCount = 0;
    Navigator.of(context).popUntil((route) {
      pageCount++;
      return route.isFirst;
    });

    return pageCount > 2;
  }

  /// Shows a dialog for the user to choose their navigation strategy (Replace, Add, or Clear).
  static void showNavigationOptionsDialog(
    BuildContext context, {
    required String documentType,
    required Map<String, dynamic> documentData,
    required String documentName,
    bool fromLeft = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          title: Text(
            'Navigate to $documentName',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'How would you like to navigate to this document?',
                style: TextStyle(
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 16),
              _buildNavigationOption(
                context: dialogContext,
                icon: Icons.swap_horiz,
                title: 'Replace Current Page',
                subtitle: 'Navigate without adding to history',
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  navigateToRelatedDocument(
                    context,
                    documentType: documentType,
                    documentData: documentData,
                    replaceCurrentPage: true,
                    fromLeft: fromLeft,
                  );
                },
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _buildNavigationOption(
                context: dialogContext,
                icon: Icons.add,
                title: 'Add to History',
                subtitle: 'Keep current page in navigation stack',
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  navigateToRelatedDocument(
                    context,
                    documentType: documentType,
                    documentData: documentData,
                    replaceCurrentPage: false,
                    fromLeft: fromLeft,
                  );
                },
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _buildNavigationOption(
                context: dialogContext,
                icon: Icons.clear_all,
                title: 'Start Fresh',
                subtitle: 'Clear all navigation history',
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  navigateAndClearStack(
                    context,
                    documentType: documentType,
                    documentData: documentData,
                    fromLeft: fromLeft,
                  );
                },
                isDark: isDark,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static Widget _buildNavigationOption({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDark ? Colors.white : Colors.grey[700],
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
