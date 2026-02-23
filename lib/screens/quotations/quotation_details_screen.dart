import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:mobo_sales/screens/invoices/invoice_details_screen.dart';
import 'package:mobo_sales/screens/invoices/invoice_list_screen.dart';
import 'package:mobo_sales/screens/deliveries/delivery_list_screen.dart';
import 'package:mobo_sales/providers/invoice_creation_provider.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import 'package:mobo_sales/widgets/custom_snackbar.dart';
import 'package:mobo_sales/utils/navigation_helper.dart';
import 'package:shimmer/shimmer.dart';
import '../../widgets/list_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';
import '../../models/attachment.dart';
import '../../providers/currency_provider.dart';
import '../../providers/quotation_provider.dart';
import '../../providers/last_opened_provider.dart';
import '../../models/contact.dart';
import '../../models/quote.dart';
import '../../services/odoo_session_manager.dart';
import 'package:flutter/foundation.dart';
import '../../services/quotation_service.dart';
import '../../widgets/attachment_card.dart';
import '../../widgets/pdf_widget.dart';
import '../../widgets/full_image_screen.dart';
import '../../widgets/signature_widget.dart';
import '../deliveries/delivery_details_screen.dart';
import '../quotations/create_quote_screen.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

String _safeString(dynamic value) {
  if (value == null || value == false) return '';
  if (value is bool) return '';
  if (value is List && value.isNotEmpty) {
    return value[1]?.toString() ?? '';
  }
  return value.toString();
}

String _getPaymentTerms(Quote quotation) {
  final paymentTermId =
      (quotation.extraData != null &&
          quotation.extraData!['payment_term_id'] is List)
      ? quotation.extraData!['payment_term_id'] as List<dynamic>?
      : null;
  if (paymentTermId != null && paymentTermId.length > 1) {
    return paymentTermId[1].toString();
  }
  return '30 Days';
}

bool _isValidBase64(String base64String) {
  try {
    final validChars = RegExp(r'^[A-Za-z0-9+/]*={0,2}$');
    if (!validChars.hasMatch(base64String)) {
      return false;
    }

    return base64String.length % 4 == 0;
  } catch (e) {
    return false;
  }
}

String getCustomerName(dynamic partnerId) {
  if (partnerId is List && partnerId.length > 1) {
    final name = partnerId[1];
    if (name is String && name.isNotEmpty && name != 'false') {
      return name;
    }
    if (partnerId[0] is int) {
      return 'Customer #${partnerId[0]}';
    }
  }
  if (partnerId is String && partnerId.isNotEmpty && partnerId != 'false') {
    return partnerId;
  }
  if (partnerId is int) {
    return 'Customer #$partnerId';
  }
  return 'Unknown Customer';
}

class QuotationDetailScreen extends StatefulWidget {
  final Quote quotation;
  final bool fromInvoiceDetails;

  const QuotationDetailScreen({
    super.key,
    required this.quotation,
    this.fromInvoiceDetails = false,
  });

  @override
  State<QuotationDetailScreen> createState() => _QuotationDetailScreenState();
}

class _QuotationDetailScreenState extends State<QuotationDetailScreen>
    with TickerProviderStateMixin {
  late Quote _localQuotation;

  void _showSnackSafe(String message, {bool error = false}) {
    if (!mounted) return;
    if (error) {
      CustomSnackbar.showError(context, message);
    } else {
      CustomSnackbar.showSuccess(context, message);
    }
  }

  void _showPrintBottomSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      builder: (bottomSheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(
              HugeIcons.strokeRoundedCatalogue,
              color: isDark ? Colors.white : Colors.grey[800],
              size: 20,
            ),
            title: Text(
              'PDF Quote',
              style: TextStyle(color: isDark ? Colors.white : Colors.grey[800]),
            ),
            onTap: () async {
              Navigator.pop(bottomSheetContext);
              await _generatePdfWithDialog(
                ({onBeforeOpen}) => PDFGenerator.generatePdfQuote(
                  context,
                  widget.quotation,
                  onBeforeOpen: onBeforeOpen,
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(
              HugeIcons.strokeRoundedNote04,
              color: isDark ? Colors.white : Colors.grey[800],
              size: 20,
            ),
            title: Text(
              'Quotation / Order',
              style: TextStyle(color: isDark ? Colors.white : Colors.grey[800]),
            ),
            onTap: () async {
              Navigator.pop(bottomSheetContext);
              await _generatePdfWithDialog(
                ({onBeforeOpen}) => PDFGenerator.generateAndSavePdf(
                  context,
                  widget.quotation,
                  onBeforeOpen: onBeforeOpen,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _generatePdfWithDialog(
    Future<void> Function({VoidCallback? onBeforeOpen}) pdfGenerator,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    iconSize: 20,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Theme.of(context).primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: LoadingAnimationWidget.fourRotatingDots(
                    color: isDark
                        ? Colors.white
                        : Theme.of(context).primaryColor,
                    size: 35,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Generating PDF',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please wait while we prepare your document',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.grey[300] : Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );

    void dismissDialog() {
      if (mounted) {
        try {
          final navigator = Navigator.of(context, rootNavigator: true);
          if (navigator.canPop()) {
            navigator.pop();
          }
        } catch (e) {}
      }
    }

    try {
      await pdfGenerator(onBeforeOpen: dismissDialog);
    } catch (e) {
      dismissDialog();
      _showSnackSafe('PDF generation failed: ${e.toString()}', error: true);
    }
  }

  Future<void> _deleteQuotation() async {
    final quotationProvider = Provider.of<QuotationProvider>(
      context,
      listen: false,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Theme.of(context).primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: LoadingAnimationWidget.fourRotatingDots(
                    color: isDark
                        ? Colors.white
                        : Theme.of(context).primaryColor,
                    size: 35,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Deleting Quotation',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please wait while we process your request',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[300]
                        : Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await quotationProvider.deleteQuotation(widget.quotation.id!);
      if (!mounted) return;

      Navigator.pop(context);
      Navigator.pop(context, true);

      CustomSnackbar.showSuccess(context, 'Quotation deleted successfully');
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      CustomSnackbar.showError(context, 'Failed to delete quotation: $e');
    }
  }

  Future<void> _navigateToCreateInvoice(Quote saleOrder) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: isDark ? Colors.grey[900] : Colors.white,
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Theme.of(context).primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: LoadingAnimationWidget.fourRotatingDots(
                      color: isDark
                          ? Colors.white
                          : Theme.of(context).primaryColor,
                      size: 35,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Checking Sale Order',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please wait while we prepare the invoice',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.grey[300] : Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      );

      final draftInvoicesInfo = await _checkForDraftInvoices(saleOrder);

      if (!mounted) return;

      Navigator.pop(context);

      final invoiceOptions = await _showInvoiceCreationDialog(
        saleOrder,
        draftInvoicesInfo['hasDraftInvoices'] as bool,
        draftInvoicesInfo['draftCount'] as int,
        draftInvoicesInfo['amountInvoiced'] as double,
      );

      if (invoiceOptions == null) {
        return;
      }

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: isDark ? Colors.grey[900] : Colors.white,
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Theme.of(context).primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: LoadingAnimationWidget.fourRotatingDots(
                      color: isDark
                          ? Colors.white
                          : Theme.of(context).primaryColor,
                      size: 35,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Loading Sale Order',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Preparing invoice data...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.grey[300] : Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      );

      final invoiceProvider = Provider.of<CreateInvoiceProvider>(
        context,
        listen: false,
      );

      await invoiceProvider.setSelectedSaleOrder(saleOrder);

      if (!mounted) return;

      Navigator.pop(context);

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: isDark ? Colors.grey[900] : Colors.white,
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Theme.of(context).primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: LoadingAnimationWidget.fourRotatingDots(
                      color: isDark
                          ? Colors.white
                          : Theme.of(context).primaryColor,
                      size: 35,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Creating Draft Invoice',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please wait...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.grey[300] : Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      );

      await invoiceProvider.createInvoice(
        context,
        invoiceType: invoiceOptions['type'] as String,
        downPaymentPercentage: invoiceOptions['percentage'] as double?,
        downPaymentAmount: invoiceOptions['fixedAmount'] as double?,
      );

      if (!mounted) return;

      Navigator.pop(context);

      if (invoiceProvider.errorMessage.isEmpty &&
          invoiceProvider.lastCreatedInvoiceName != null &&
          invoiceProvider.lastCreatedInvoiceId != null) {
        await _fetchRelatedInvoices();

        if (mounted) {
          CustomSnackbar.showSuccess(
            context,
            'Draft invoice ${invoiceProvider.lastCreatedInvoiceName} created successfully',
          );
        }

        if (mounted) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            NavigationHelper.navigateToInvoice(
              context,
              invoiceProvider.lastCreatedInvoiceId.toString(),
              replaceCurrentPage: false,
              fromQuotationDetails: true,
            );
          }
        }
      } else if (invoiceProvider.errorMessage.isNotEmpty) {
        if (mounted) {
          _showErrorDialog(
            'Invoice Creation Failed',
            invoiceProvider.errorMessage,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        try {
          Navigator.pop(context);
        } catch (_) {}

        String errorMessage = e.toString();
        if (errorMessage.contains('Exception: ')) {
          errorMessage = errorMessage.split('Exception: ')[1];
        }
        _showErrorDialog('Error', errorMessage);
      }
    }
  }

  Future<Map<String, dynamic>> _checkForDraftInvoices(Quote saleOrder) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        return {
          'hasDraftInvoices': false,
          'draftCount': 0,
          'amountInvoiced': 0.0,
        };
      }

      final saleOrderResult = await client.callKw({
        'model': 'sale.order',
        'method': 'read',
        'args': [
          [saleOrder.id],
        ],
        'kwargs': {
          'fields': ['amount_invoiced', 'invoice_ids'],
        },
      });

      double amountInvoiced = 0.0;
      if (saleOrderResult != null &&
          saleOrderResult is List &&
          saleOrderResult.isNotEmpty) {
        amountInvoiced =
            (saleOrderResult[0]['amount_invoiced'] as num?)?.toDouble() ?? 0.0;
        amountInvoiced =
            (saleOrderResult[0]['amount_invoiced'] as num?)?.toDouble() ?? 0.0;
      }

      final result = await client.callKw({
        'model': 'account.move',
        'method': 'search_read',
        'args': [
          [
            ['invoice_origin', '=', saleOrder.name],
            ['move_type', '=', 'out_invoice'],
          ],
        ],
        'kwargs': {
          'fields': ['id', 'name', 'state', 'invoice_origin'],
        },
      });

      if (result == null || result is! List) {
        return {
          'hasDraftInvoices': false,
          'draftCount': 0,
          'amountInvoiced': amountInvoiced,
        };
      }

      final invoices = result;

      int draftCount = 0;
      for (final invoice in invoices) {
        final state = invoice['state']?.toString() ?? '';

        if (state == 'draft') {
          draftCount++;
        }
      }

      return {
        'hasDraftInvoices': draftCount > 0,
        'draftCount': draftCount,
        'amountInvoiced': amountInvoiced,
      };
    } catch (e) {
      return {
        'hasDraftInvoices': false,
        'draftCount': 0,
        'amountInvoiced': 0.0,
      };
    }
  }

  Future<Map<String, dynamic>?> _showInvoiceCreationDialog(
    Quote saleOrder,
    bool hasDraftInvoices,
    int draftCount,
    double amountInvoiced,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currencyProvider = Provider.of<CurrencyProvider>(
      context,
      listen: false,
    );
    final formKey = GlobalKey<FormState>();

    final currencyId =
        (saleOrder.extraData != null &&
            saleOrder.extraData!['currency_id'] is List)
        ? saleOrder.extraData!['currency_id'] as List<dynamic>?
        : null;
    final String? currencyCode = (currencyId != null && currencyId.length > 1)
        ? currencyId[1].toString()
        : null;
    final orderTotal = saleOrder.total;

    String invoiceType = 'regular';
    final percentageController = TextEditingController();
    final fixedAmountController = TextEditingController();

    return showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: isDark ? 0 : 8,
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  'Create Invoice',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasDraftInvoices) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange[50]?.withOpacity(
                          isDark ? 0.1 : 1.0,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange[200]!.withOpacity(
                            isDark ? 0.3 : 1.0,
                          ),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                HugeIcons.strokeRoundedAlert02,
                                color: Colors.orange[700],
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'There ${draftCount == 1 ? 'is' : 'are'} $draftCount existing Draft Invoice${draftCount == 1 ? '' : 's'} for this Sale Order.',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.orange[200]
                                        : Colors.orange[900],
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (invoiceType == 'regular') ...[
                            const SizedBox(height: 8),
                            Text(
                              'The new invoice will deduct draft invoices linked to this sale order.',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.orange[200]
                                    : Colors.orange[900],
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  if (amountInvoiced > 0) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[850] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Already invoiced',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[700],
                            ),
                          ),
                          Text(
                            currencyProvider.formatAmount(
                              amountInvoiced,
                              currency: currencyCode,
                            ),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Text(
                    'Select Invoice Type',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 12),

                  _buildInvoiceTypeOption(
                    context: context,
                    isDark: isDark,
                    title: 'Regular Invoice',
                    subtitle: 'Invoice for delivered/ordered quantities',
                    value: 'regular',
                    groupValue: invoiceType,
                    onChanged: (value) {
                      setState(() {
                        invoiceType = value!;
                        percentageController.clear();
                        fixedAmountController.clear();
                      });
                    },
                  ),
                  const SizedBox(height: 10),

                  _buildInvoiceTypeOption(
                    context: context,
                    isDark: isDark,
                    title: 'Down Payment (Percentage)',
                    subtitle: 'Create down payment based on %',
                    value: 'percentage',
                    groupValue: invoiceType,
                    onChanged: (value) {
                      setState(() {
                        invoiceType = value!;
                        fixedAmountController.clear();
                      });
                    },
                  ),
                  const SizedBox(height: 10),

                  _buildInvoiceTypeOption(
                    context: context,
                    isDark: isDark,
                    title: 'Down Payment (Fixed Amount)',
                    subtitle: 'Create down payment with fixed amount',
                    value: 'fixed',
                    groupValue: invoiceType,
                    onChanged: (value) {
                      setState(() {
                        invoiceType = value!;
                        percentageController.clear();
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  if (invoiceType == 'percentage') ...[
                    TextFormField(
                      controller: percentageController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Percentage',
                        hintText: 'Enter percentage (e.g., 20 for 20%)',
                        suffixText: '%',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.grey[850] : Colors.grey[50],
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a percentage';
                        }
                        final parsed = double.tryParse(value);
                        if (parsed == null) {
                          return 'Enter a valid number';
                        }
                        if (parsed <= 0 || parsed > 100) {
                          return 'Enter a value between 0 and 100';
                        }
                        return null;
                      },
                    ),
                  ] else if (invoiceType == 'fixed') ...[
                    TextFormField(
                      controller: fixedAmountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Fixed Amount',
                        hintText: 'Enter fixed amount',
                        prefixText: currencyProvider.getCurrencySymbol(
                          currencyCode ?? 'USD',
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.grey[850] : Colors.grey[50],
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a fixed amount';
                        }
                        final parsed = double.tryParse(value);
                        if (parsed == null) {
                          return 'Enter a valid number';
                        }
                        if (parsed <= 0) {
                          return 'Amount must be greater than 0';
                        }
                        if (parsed > orderTotal) {
                          return 'Amount cannot exceed order total';
                        }
                        return null;
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(null),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark
                          ? Colors.grey[400]
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (formKey.currentState!.validate()) {
                        Navigator.of(ctx).pop({
                          'type': invoiceType,
                          'percentage': invoiceType == 'percentage'
                              ? double.tryParse(percentageController.text)
                              : null,
                          'fixedAmount': invoiceType == 'fixed'
                              ? double.tryParse(fixedAmountController.text)
                              : null,
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      elevation: isDark ? 0 : 3,
                    ),
                    child: const Text(
                      'Create Draft',
                      style: TextStyle(fontWeight: FontWeight.w600),
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

  Widget _buildInvoiceTypeOption({
    required BuildContext context,
    required bool isDark,
    required String title,
    required String subtitle,
    required String value,
    required String groupValue,
    required Function(String?) onChanged,
  }) {
    final isSelected = groupValue == value;

    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryColor
                : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
          color: isSelected
              ? AppTheme.primaryColor.withOpacity(0.05)
              : (isDark ? Colors.grey[850] : Colors.white),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: groupValue,
              onChanged: onChanged,
              activeColor: AppTheme.primaryColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 2),
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

  Future<void> _confirmDelete() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final quotationName = widget.quotation.name;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: Text(
          'Delete Quotation',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Are you sure you want to delete $quotationName? This action cannot be undone.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isDark
                ? Colors.grey[300]
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark
                        ? Colors.grey[400]
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    elevation: isDark ? 0 : 3,
                  ),
                  child: const Text(
                    'Delete',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteQuotation();
    }
  }

  Future<void> _confirmCancelQuotation() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final quotationName = widget.quotation.name;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: Text(
          'Cancel Quotation',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Are you sure you want to cancel $quotationName? This action cannot be undone.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isDark
                ? Colors.grey[300]
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark
                        ? Colors.grey[400]
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Back',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    elevation: isDark ? 0 : 3,
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _cancelQuotation();
    }
  }

  Future<void> _cancelQuotation() async {
    final quotationProvider = Provider.of<QuotationProvider>(
      context,
      listen: false,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LoadingAnimationWidget.fourRotatingDots(
                  color: Theme.of(context).colorScheme.primary,
                  size: 50,
                ),
                const SizedBox(height: 20),
                Text(
                  'Cancelling Quotation',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please wait...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.grey[300] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      await quotationProvider.cancelQuotation(widget.quotation.id!);
      if (!mounted) return;

      Navigator.pop(context);

      _showSnackSafe('Quotation cancelled successfully');

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      CustomSnackbar.showError(context, 'Failed to cancel quotation: $e');
    }
  }

  Future<void> _convertToOrder() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final quotationName = widget.quotation.name;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: Text(
          'Convert to Sale Order',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Are you sure you want to convert $quotationName to a sale order? This action cannot be undone.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isDark
                ? Colors.grey[300]
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark
                        ? Colors.grey[400]
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? AppTheme.primaryColor
                        : AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    elevation: isDark ? 0 : 3,
                  ),
                  child: const Text(
                    'Convert',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _performConversion();
    } else {}
  }

  Future<void> _performConversion() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final quotationProvider = Provider.of<QuotationProvider>(
      context,
      listen: false,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Theme.of(context).primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: LoadingAnimationWidget.fourRotatingDots(
                    color: isDark
                        ? Colors.white
                        : Theme.of(context).primaryColor,
                    size: 35,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Converting to Sale Order',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please wait while we process your request',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.grey[300] : Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      await quotationProvider
          .convertQuotationToOrder(widget.quotation.id!)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException(
              'The server took too long to respond. Please try again.',
            ),
          );

      if (mounted) {
        Navigator.of(context).pop();

        _showSnackSafe('Quotation converted to sale order successfully');

        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();

        String msg = e.toString();
        String? details;
        if (e is TimeoutException) {
          msg = 'Request timed out';
          details =
              'The server took too long to respond. Please check your internet connection and try again.';
        } else {
          final regex = RegExp(r'message: ([^,}]+)');
          final match = regex.firstMatch(msg);
          if (match != null) {
            msg = match.group(1)!;
            details = e.toString();
          } else {
            details = e.toString();
          }
        }

        _showErrorDialog('Conversion Failed', msg, details: details);
      }
    }
  }

  final TextEditingController _termsController = TextEditingController();
  final bool _isSavingTerms = false;
  final bool _editingTerms = false;
  Contact? _customerDetails;
  bool _isLoadingCustomer = false;
  final Map<int, Uint8List?> _productImages = {};
  final Set<int> _loadingProductImages = {};
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late TabController _tabController;
  QuotationProvider? _quotationProvider;
  Map<String, dynamic>? _companyInfo;
  Uint8List? _companyLogo;
  bool _isLoadingCompany = false;
  bool _isMounted = false;
  final List<Attachment> _attachments = [];
  final bool _isLoadingAttachments = false;

  List<Map<String, dynamic>> _relatedInvoices = [];
  bool _isLoadingRelatedInvoices = false;

  List<Map<String, dynamic>> _relatedDeliveries = [];
  bool _isLoadingRelatedDeliveries = false;

  Map<String, dynamic> _additionalInfo = {};
  bool _isLoadingAdditionalInfo = false;

  Map<String, dynamic> _quoteBuilderData = {};
  bool _isLoadingQuoteBuilder = false;
  bool _isQuoteBuilderEditMode = false;
  bool _isSavingQuoteBuilder = false;
  final Set<int> _selectedHeaderIds = {};
  final Set<int> _selectedFooterIds = {};
  final Map<int, Set<int>> _selectedProductDocs = {};
  final Map<String, TextEditingController> _headerFieldControllers = {};
  final Map<String, TextEditingController> _footerFieldControllers = {};
  final Map<String, TextEditingController> _productFieldControllers = {};

  bool _isLoadingInitialData = true;

  String? _serverBaseUrl;
  final GlobalKey<RefreshIndicatorState> _refreshKey =
      GlobalKey<RefreshIndicatorState>();
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    _quotationProvider = Provider.of<QuotationProvider>(context, listen: false);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _tabController = TabController(length: 4, vsync: this);

    _localQuotation = widget.quotation;
    _trackQuotationAccess();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _quotationProvider?.loadOrderLines(widget.quotation.id!);
      _termsController.text = _safeString(widget.quotation.notes);
      _quotationProvider?.addListener(_fetchProductImagesForOrderLines);

      _loadInitialData();
    });

    OdooSessionManager.getCurrentSession().then((session) {
      final raw = session?.serverUrl.trim() ?? '';
      var base = raw;
      if (base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }
      _serverBaseUrl = base.isNotEmpty ? base : null;
    });
  }

  void _trackQuotationAccess() {
    try {
      final lastOpenedProvider = Provider.of<LastOpenedProvider>(
        context,
        listen: false,
      );
      final quotationId = widget.quotation.id?.toString() ?? '';
      final quotationName = widget.quotation.name;

      String customerName = widget.quotation.customerName ?? 'Customer';

      lastOpenedProvider.trackQuotationAccess(
        quotationId: quotationId,
        quotationName: quotationName,
        customerName: customerName,
        quotationData: widget.quotation.toJson(),
      );
    } catch (e) {}
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;

    try {
      await Future.wait([
        _fetchCustomerDetails(),
        _fetchCompanyInfoAndLogo(),
        _fetchRelatedInvoices(),
        _fetchRelatedDeliveries(),
        _fetchAdditionalInfo(),
        _fetchQuoteBuilderData(),
        if (widget.quotation.status == 'sale') _loadAttachments(),
      ]);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingInitialData = false;
        });

        _animationController.forward();
      }
    }
  }

  Future<void> _loadAttachments() async {
    try {
      await Provider.of<QuotationProvider>(
        context,
        listen: false,
      ).loadAttachments(widget.quotation.id!);
    } catch (e) {
      if (e.toString().contains('Server returned HTML instead of JSON')) {
      } else if (e.toString().contains('SocketException') ||
          e.toString().contains('TimeoutException')) {}
    }
  }

  Future<void> _uploadAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'jpg',
        'jpeg',
        'png',
      ],
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;

    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      try {
        bytes = await File(file.path!).readAsBytes();
      } catch (e) {
        if (mounted) {
          CustomSnackbar.showError(context, 'Unable to read selected file: $e');
        }
        return;
      }
    }
    if (bytes == null) {
      if (mounted) {
        CustomSnackbar.showError(context, 'Unable to read selected file');
      }
      return;
    }

    final String? description = null;

    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Theme.of(context).primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: LoadingAnimationWidget.fourRotatingDots(
                    color: isDark
                        ? Colors.white
                        : Theme.of(context).primaryColor,
                    size: 35,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Uploading Attachment',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please wait while we process your request',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[300]
                        : Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      String ext = (file.extension ?? '').toLowerCase();
      String computedMime = 'application/octet-stream';
      switch (ext) {
        case 'pdf':
          computedMime = 'application/pdf';
          break;
        case 'doc':
          computedMime = 'application/msword';
          break;
        case 'docx':
          computedMime =
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
          break;
        case 'xls':
          computedMime = 'application/vnd.ms-excel';
          break;
        case 'xlsx':
          computedMime =
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
          break;
        case 'jpg':
        case 'jpeg':
          computedMime = 'image/jpeg';
          break;
        case 'png':
          computedMime = 'image/png';
          break;
      }

      await _quotationProvider?.uploadAttachment(
        widget.quotation.id!,
        bytes,
        file.name,
        computedMime,
        description: description,
      );
      if (!mounted) return;
      await _loadAttachments();
    } catch (e) {
      if (!mounted) return;
      CustomSnackbar.showError(context, 'Failed to upload attachment: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  void _viewAttachment(Attachment attachment) {
    final String? downloadUrl = attachment.getDownloadUrl();

    if (downloadUrl == null || downloadUrl.isEmpty) {
      CustomSnackbar.showError(context, 'No file available to preview.');
      return;
    }

    if (attachment.type == 'url') {
      final resolvedUrl = _resolveUrl(downloadUrl);

      final uri = Uri.parse(resolvedUrl);
      launchUrl(uri)
          .then((ok) {
            if (!ok && mounted) {
              CustomSnackbar.showError(
                context,
                'Unable to open the link. Please try again.',
              );
            }
          })
          .catchError((e) {
            if (mounted) {
              CustomSnackbar.showError(context, 'Failed to launch the URL.');
            }
          });
      return;
    }

    if (attachment.isImage) {
      _openImageFromAuthenticatedUrl(_resolveUrl(downloadUrl), attachment.name);
      return;
    }

    if (attachment.isPdf) {
      _downloadAndOpenFile(
        _resolveUrl(downloadUrl),
        suggestedName: attachment.name,
        mimetype: 'application/pdf',
      );
      return;
    }

    _downloadAndOpenFile(
      _resolveUrl(downloadUrl),
      suggestedName: attachment.name,
      mimetype: attachment.mimetype,
    );
  }

  String _resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    final base = _serverBaseUrl;
    if (base == null || base.isEmpty) {
      OdooSessionManager.getCurrentSession().then((session) {
        if (session?.serverUrl != null) {
          final rawBase = session!.serverUrl.trim();
          final cleanBase = rawBase.endsWith('/')
              ? rawBase.substring(0, rawBase.length - 1)
              : rawBase;
          _serverBaseUrl = cleanBase;
        }
      });
      return url;
    }

    final resolved = url.startsWith('/') ? '$base$url' : '$base/$url';

    return resolved;
  }

  String _guessFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      return 'image/*';
    }
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  Widget _buildLinkifiedSelectableText(String text, bool isDark) {
    final baseStyle = TextStyle(
      color: isDark ? Colors.grey[300] : Colors.grey[800],
      fontSize: 14,
    );
    final linkStyle = baseStyle.copyWith(
      color: isDark ? Colors.blue[300] : Colors.blue[700],
      decoration: TextDecoration.underline,
    );

    final spans = _linkifyToSpans(text, baseStyle, linkStyle);

    return SelectionArea(
      child: RichText(text: TextSpan(children: spans)),
    );
  }

  List<TextSpan> _linkifyToSpans(
    String text,
    TextStyle baseStyle,
    TextStyle linkStyle,
  ) {
    final pattern = RegExp(
      r'((https?:\/\/[^\s]+)|(www\.[^\s]+)|([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}))',
      caseSensitive: false,
    );
    final spans = <TextSpan>[];
    int cursor = 0;
    final matches = pattern.allMatches(text).toList();

    const trailing = '.,;:)]}>"\'';

    for (final m in matches) {
      if (m.start > cursor) {
        spans.add(
          TextSpan(text: text.substring(cursor, m.start), style: baseStyle),
        );
      }

      String raw = text.substring(m.start, m.end);

      String trailingPunct = '';
      while (raw.isNotEmpty && trailing.contains(raw.characters.last)) {
        trailingPunct = raw.characters.last + trailingPunct;
        raw = raw.characters.skipLast(1).toString();
      }

      Uri? launchUri;
      String display = raw;
      if (raw.toLowerCase().startsWith('http://') ||
          raw.toLowerCase().startsWith('https://')) {
        launchUri = Uri.parse(raw);
      } else if (raw.toLowerCase().startsWith('www.')) {
        launchUri = Uri.parse('https://$raw');
      } else if (raw.contains('@')) {
        launchUri = Uri.parse('mailto:$raw');
      }

      if (launchUri != null) {
        spans.add(
          TextSpan(
            text: display,
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () async {
                if (await canLaunchUrl(launchUri!)) {
                  await launchUrl(
                    launchUri,
                    mode: LaunchMode.externalApplication,
                  );
                } else {
                  CustomSnackbar.showError(context, 'Could not open the link');
                }
              },
          ),
        );
        if (trailingPunct.isNotEmpty) {
          spans.add(TextSpan(text: trailingPunct, style: baseStyle));
        }
      } else {
        spans.add(
          TextSpan(text: text.substring(m.start, m.end), style: baseStyle),
        );
      }

      cursor = m.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }
    return spans;
  }

  Future<void> _openImageFromAuthenticatedUrl(String url, String name) async {
    bool isDialogOpen = false;

    if (mounted) {
      isDialogOpen = true;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: isDark ? Colors.grey[900] : Colors.white,
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Theme.of(context).primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: LoadingAnimationWidget.fourRotatingDots(
                      color: isDark
                          ? Colors.white
                          : Theme.of(context).primaryColor,
                      size: 35,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Fetching Attachment',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please wait while we process your request',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[300]
                          : Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    try {
      final response = await OdooSessionManager.makeAuthenticatedRequest(url);
      final contentType = response.headers['content-type'];

      if (contentType != null &&
          contentType.toLowerCase().startsWith('text/html')) {}
      if (response.statusCode != 200) {
        if (mounted) {
          CustomSnackbar.showError(
            context,
            'Failed to load image (${response.statusCode})',
          );
        }
        return;
      }
      final bytes = response.bodyBytes;

      if (!mounted) return;
      if (isDialogOpen) {
        Navigator.of(context).pop();
        isDialogOpen = false;
      }
      Navigator.push(
        context,

        MaterialPageRoute(
          builder: (context) => FullImageScreen(imageBytes: bytes, title: name),
        ),
      );
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(context, 'Error opening image');
      }
    } finally {
      if (isDialogOpen && mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _downloadAndOpenFile(
    String url, {
    String? suggestedName,
    String? mimetype,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Theme.of(context).primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: LoadingAnimationWidget.fourRotatingDots(
                    color: isDark
                        ? Colors.white
                        : Theme.of(context).primaryColor,
                    size: 35,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Fetching Attachment',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please wait while we process your request',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[300]
                        : Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      final http.Response response =
          await OdooSessionManager.makeAuthenticatedRequest(url);
      final contentType = response.headers['content-type'];

      if (contentType != null &&
          contentType.toLowerCase().startsWith('text/html')) {}
      if (response.statusCode != 200) {
        throw Exception('Download failed with status ${response.statusCode}');
      }

      final dir = await getTemporaryDirectory();
      final safeName =
          (suggestedName ??
                  'attachment_${DateTime.now().millisecondsSinceEpoch}')
              .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
      final filePath = '${dir.path}/$safeName';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      final result = await OpenFile.open(filePath);

      if (result.type != ResultType.done) {
        if (!mounted) return;
        CustomSnackbar.showError(
          context,
          'Downloaded but failed to open: ${result.message}',
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(context, 'Failed to open attachment: $e');
      }
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _deleteAttachment(
    BuildContext dialogContext,
    Attachment attachment,
  ) async {
    final isDark = Theme.of(dialogContext).brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: isDark ? Colors.red[300] : Colors.red[600],
              size: 28,
            ),
            const SizedBox(width: 8),
            Text(
              'Delete Attachment',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete ${attachment.name}?',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This action is permanent and cannot be undone.',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
            },
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? Colors.red[400] : Colors.red[600],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text(
              'Delete',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Theme.of(context).primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: LoadingAnimationWidget.fourRotatingDots(
                    color: isDark
                        ? Colors.white
                        : Theme.of(context).primaryColor,
                    size: 35,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Deleting attachment',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please wait while we process your request',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[300]
                        : Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await _quotationProvider?.deleteAttachment(attachment.id);
      if (!mounted) return;
      await _loadAttachments();
    } catch (e) {
      if (!mounted) return;
      CustomSnackbar.showError(context, 'Failed to delete attachment: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _fetchRelatedInvoices() async {
    if (!mounted) return;
    setState(() {
      _isLoadingRelatedInvoices = true;
      _relatedInvoices = [];
    });
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');

      final saleOrderId = widget.quotation.id;

      final saleOrderResult = await client.callKw({
        'model': 'sale.order',
        'method': 'read',
        'args': [
          [saleOrderId],
        ],
        'kwargs': {
          'fields': ['invoice_ids'],
        },
      });

      List<int> invoiceIds = [];
      if (saleOrderResult is List && saleOrderResult.isNotEmpty) {
        final invoiceIdsField = saleOrderResult[0]['invoice_ids'];
        if (invoiceIdsField is List) {
          invoiceIds = invoiceIdsField.cast<int>();
        }
      }

      List<Map<String, dynamic>> invoices = [];

      if (invoiceIds.isNotEmpty) {
        final result = await client.callKw({
          'model': 'account.move',
          'method': 'search_read',
          'args': [
            [
              ['id', 'in', invoiceIds],
              [
                'move_type',
                'in',
                ['out_invoice', 'out_refund'],
              ],
            ],
          ],
          'kwargs': {
            'fields': [
              'id',
              'name',
              'state',
              'invoice_date',
              'amount_total',
              'currency_id',
              'move_type',
            ],
            'order': 'invoice_date desc',
          },
        });

        invoices = (result is List)
            ? List<Map<String, dynamic>>.from(result)
            : [];
      }

      if (!mounted) return;
      setState(() {
        _relatedInvoices = invoices;
        _isLoadingRelatedInvoices = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _relatedInvoices = [];
        _isLoadingRelatedInvoices = false;
      });
    }
  }

  Future<void> _fetchRelatedDeliveries() async {
    if (!mounted) return;
    setState(() {
      _isLoadingRelatedDeliveries = true;
      _relatedDeliveries = [];
    });
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');

      final originName = widget.quotation.name;
      if (originName == 'N/A') {
        setState(() {
          _isLoadingRelatedDeliveries = false;
          _relatedDeliveries = [];
        });
        return;
      }

      final result = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [
          [
            ['picking_type_code', '=', 'outgoing'],
            ['origin', '=', originName],
          ],
        ],
        'kwargs': {
          'fields': ['id', 'name', 'state', 'scheduled_date', 'partner_id'],
          'order': 'scheduled_date desc',
          'limit': 50,
        },
      });

      final List<Map<String, dynamic>> deliveries = (result is List)
          ? List<Map<String, dynamic>>.from(result)
          : [];

      if (!mounted) return;
      setState(() {
        _relatedDeliveries = deliveries;
        _isLoadingRelatedDeliveries = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _relatedDeliveries = [];
        _isLoadingRelatedDeliveries = false;
      });
    }
  }

  Future<void> _fetchAdditionalInfo({
    List<String>? invalidFields,
    int retryCount = 0,
  }) async {
    if (!mounted) return;

    if (retryCount > 10) {
      if (mounted) {
        setState(() {
          _isLoadingAdditionalInfo = false;
        });
      }
      return;
    }

    setState(() {
      _isLoadingAdditionalInfo = true;
    });

    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        return;
      }

      final List<String> fieldsToFetch = [
        'user_id',
        'team_id',
        'campaign_id',
        'medium_id',
        'source_id',
        'require_signature',
        'require_payment',

        'payment_term_id',
        'fiscal_position_id',

        'incoterm_id',
        'picking_policy',
        'warehouse_id',
        'commitment_date',

        'pricelist_id',
        'client_order_ref',
        'tag_ids',
        'origin',
        'opportunity_id',

        'create_date',
        'create_uid',
        'write_date',
        'write_uid',

        'signed_by',
        'signed_on',
        'signature',
      ];

      if (invalidFields != null) {
        fieldsToFetch.removeWhere((field) => invalidFields.contains(field));
      }

      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'read',
        'args': [
          [widget.quotation.id],
        ],
        'kwargs': {'fields': fieldsToFetch},
      });

      if (result != null && result is List && result.isNotEmpty) {
        if (mounted) {
          setState(() {
            _additionalInfo = Map<String, dynamic>.from(result[0]);
          });
        }
      }
    } catch (e) {
      if (e.toString().contains('Invalid field') &&
          e.toString().contains('sale.order')) {
        final fieldMatch = RegExp(
          r"Invalid field '([^']+)'",
        ).firstMatch(e.toString());
        if (fieldMatch != null) {
          final invalidField = fieldMatch.group(1);

          final List<String> allInvalidFields = List<String>.from(
            invalidFields ?? [],
          );
          if (invalidField != null &&
              !allInvalidFields.contains(invalidField)) {
            allInvalidFields.add(invalidField);
          }

          return _fetchAdditionalInfo(
            invalidFields: allInvalidFields,
            retryCount: retryCount + 1,
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAdditionalInfo = false;
        });
      }
    }
  }

  Future<void> _fetchQuoteBuilderData() async {
    if (!mounted) return;

    setState(() {
      _isLoadingQuoteBuilder = true;
    });

    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        return;
      }

      _selectedHeaderIds.clear();
      _selectedFooterIds.clear();
      _selectedProductDocs.clear();
      _headerFieldControllers.clear();
      _footerFieldControllers.clear();
      _productFieldControllers.clear();

      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'get_update_included_pdf_params',
        'args': [
          [widget.quotation.id],
        ],
        'kwargs': {
          'context': {'active_id': widget.quotation.id},
        },
      });

      if (result != null && result is Map) {
        if (mounted) {
          setState(() {
            _quoteBuilderData = Map<String, dynamic>.from(result);

            if (_quoteBuilderData['headers'] != null &&
                _quoteBuilderData['headers']['files'] != null) {
              for (var file in _quoteBuilderData['headers']['files']) {
                if (file['is_selected'] == true) {
                  _selectedHeaderIds.add(file['id']);
                }
              }
            }

            if (_quoteBuilderData['footers'] != null &&
                _quoteBuilderData['footers']['files'] != null) {
              for (var file in _quoteBuilderData['footers']['files']) {
                if (file['is_selected'] == true) {
                  _selectedFooterIds.add(file['id']);
                }
              }
            }

            if (_quoteBuilderData['lines'] != null) {
              for (var line in _quoteBuilderData['lines']) {
                final lineId = line['id'];
                if (line['files'] != null) {
                  for (var file in line['files']) {
                    if (file['is_selected'] == true) {
                      _selectedProductDocs.putIfAbsent(lineId, () => {});
                      _selectedProductDocs[lineId]!.add(file['id']);
                    }
                  }
                }
              }
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _quoteBuilderData = {};
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingQuoteBuilder = false;
        });
      }
    }
  }

  Future<void> _saveQuoteBuilderSelections() async {
    if (!mounted) return;

    setState(() {
      _isSavingQuoteBuilder = true;
    });

    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No Odoo client available');
      }

      final saleOrderId = widget.quotation.id;

      final Map<String, dynamic> selectedPdf = {
        'header': _selectedHeaderIds.toList(),
        'lines': _selectedProductDocs.map(
          (key, value) => MapEntry(key.toString(), value.toList()),
        ),
        'footer': _selectedFooterIds.toList(),
      };

      final List<int> orderLineList = (selectedPdf['lines'] as Map).keys
          .map((key) => int.parse(key.toString()))
          .toList();

      await client.callKw({
        'model': 'sale.order',
        'method': 'write',
        'args': [
          [saleOrderId],
          {'quotation_document_ids': null},
        ],
        'kwargs': {},
      });

      if (orderLineList.isNotEmpty) {
        await client.callKw({
          'model': 'sale.order.line',
          'method': 'write',
          'args': [
            orderLineList,
            {'product_document_ids': null},
          ],
          'kwargs': {},
        });
      }

      await client.callKw({
        'model': 'sale.order',
        'method': 'save_included_pdf',
        'args': [
          [saleOrderId],
          selectedPdf,
        ],
        'kwargs': {
          'context': {'active_id': saleOrderId},
        },
      });

      Map<String, dynamic> jsonData = {"header": {}, "line": {}, "footer": {}};

      for (int headerId in _selectedHeaderIds) {
        var header = (_quoteBuilderData['headers']?['files'] as List?)
            ?.firstWhere((file) => file['id'] == headerId, orElse: () => {});

        if (header != null && header.isNotEmpty) {
          jsonData["header"]["$headerId"] = {
            "document_name": header['name']?.toString() ?? "Unknown",
            "custom_form_fields": {},
          };

          if (header['custom_form_fields'] != null) {
            for (var field in header['custom_form_fields']) {
              final controllerKey = "${headerId}_${field['name']}";
              jsonData["header"]["$headerId"]["custom_form_fields"][field["name"]] =
                  _headerFieldControllers[controllerKey]?.text ?? "";
            }
          }
        }
      }

      for (int footerId in _selectedFooterIds) {
        var footer = (_quoteBuilderData['footers']?['files'] as List?)
            ?.firstWhere((file) => file['id'] == footerId, orElse: () => {});

        if (footer != null && footer.isNotEmpty) {
          jsonData["footer"]["$footerId"] = {
            "document_name": footer['name']?.toString() ?? "Unknown",
            "custom_form_fields": {},
          };

          if (footer['custom_form_fields'] != null) {
            for (var field in footer['custom_form_fields']) {
              final controllerKey = "${footerId}_${field['name']}";
              jsonData["footer"]["$footerId"]["custom_form_fields"][field["name"]] =
                  _footerFieldControllers[controllerKey]?.text ?? "";
            }
          }
        }
      }

      _selectedProductDocs.forEach((lineId, docIds) {
        if (!jsonData["line"].containsKey("$lineId")) {
          jsonData["line"]["$lineId"] = {};
        }

        for (int docId in docIds) {
          var line = (_quoteBuilderData['lines'] as List?)?.firstWhere(
            (l) => l['id'] == lineId,
            orElse: () => {},
          );

          var productFile = (line?['files'] as List?)?.firstWhere(
            (file) => file['id'] == docId,
            orElse: () => {},
          );

          if (productFile != null && productFile.isNotEmpty) {
            jsonData["line"]["$lineId"]["$docId"] = {
              "document_name": productFile['name']?.toString() ?? "Unknown",
              "custom_form_fields": {},
            };

            if (productFile['custom_form_fields'] != null) {
              for (var field in productFile['custom_form_fields']) {
                final controllerKey = "${docId}_${field['name']}";
                jsonData["line"]["$lineId"]["$docId"]["custom_form_fields"][field["name"]] =
                    _productFieldControllers[controllerKey]?.text ?? "";
              }
            }
          }
        }
      });

      await client.callKw({
        'model': 'sale.order',
        'method': 'write',
        'args': [
          [saleOrderId],
          {'customizable_pdf_form_fields': jsonEncode(jsonData)},
        ],
        'kwargs': {},
      });

      await _fetchQuoteBuilderData();

      if (mounted) {
        setState(() {
          _isQuoteBuilderEditMode = false;
        });

        CustomSnackbar.showSuccess(
          context,
          'Quote Builder selections saved successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Failed to save Quote Builder selections: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingQuoteBuilder = false;
        });
      }
    }
  }

  Widget _buildRelatedInvoicesSectionDynamic(bool isDark) {
    if (_isLoadingRelatedInvoices || _relatedInvoices.isEmpty) {
      return const SizedBox.shrink();
    }

    final saleOrderName = widget.quotation.name;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: IconButton(
        onPressed: () async {
          if (_relatedInvoices.length == 1) {
            final invoiceId = _relatedInvoices.first['id'].toString();

            try {
              final client = await OdooSessionManager.getClient();
              if (client != null) {
                final exists = await client.callKw({
                  'model': 'account.move',
                  'method': 'search_count',
                  'args': [
                    [
                      ['id', '=', int.parse(invoiceId)],
                    ],
                  ],
                  'kwargs': {},
                });

                if (exists > 0) {
                  if (mounted) {
                    if (widget.fromInvoiceDetails) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => InvoiceDetailsPage(
                            invoiceId: invoiceId,
                            fromQuotationDetails: true,
                          ),
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => InvoiceDetailsPage(
                            invoiceId: invoiceId,
                            fromQuotationDetails: true,
                          ),
                        ),
                      );
                    }
                  } else {}
                } else {}
              } else {}
            } catch (e) {}
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    InvoiceListScreen(saleOrderName: saleOrderName),
              ),
            );
          }
        },
        icon: Badge(
          backgroundColor: isDark ? Colors.white : AppTheme.primaryColor,
          label: Text('${_relatedInvoices.length}'),
          child: Icon(
            HugeIcons.strokeRoundedInvoice03,
            size: 24,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[400]
                : Colors.grey[600],
          ),
        ),
        tooltip: 'Invoices (${_relatedInvoices.length})',
      ),
    );
  }

  Widget _buildRelatedDeliveriesSectionDynamic(bool isDark) {
    if (_isLoadingRelatedDeliveries || _relatedDeliveries.isEmpty) {
      return const SizedBox.shrink();
    }

    final saleOrderName = widget.quotation.name;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: IconButton(
        onPressed: () async {
          if (_relatedDeliveries.length == 1) {
            final deliveryId = _relatedDeliveries.first['id'].toString();

            try {
              final client = await OdooSessionManager.getClient();
              if (client != null) {
                final exists = await client.callKw({
                  'model': 'stock.picking',
                  'method': 'search_count',
                  'args': [
                    [
                      ['id', '=', int.parse(deliveryId)],
                    ],
                  ],
                  'kwargs': {},
                });

                if (exists > 0) {
                  if (mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DeliveryDetailsScreen(
                          deliveryId: int.parse(deliveryId),
                        ),
                      ),
                    );
                  }
                } else {
                  if (mounted) {
                    CustomSnackbar.showError(
                      context,
                      'Delivery not found. It may have been deleted.',
                    );
                  }
                }
              }
            } catch (e) {
              if (mounted) {
                CustomSnackbar.showError(
                  context,
                  'Unable to access delivery. Please try again.',
                );
              }
            }
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    DeliveryListScreen(saleOrderName: saleOrderName),
              ),
            );
          }
        },
        icon: Badge(
          backgroundColor: isDark ? Colors.white : AppTheme.primaryColor,
          label: Text('${_relatedDeliveries.length}'),
          child: Icon(
            HugeIcons.strokeRoundedPackageDelivered,
            size: 24,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[400]
                : Colors.grey[600],
          ),
        ),
        tooltip: 'Deliveries (${_relatedDeliveries.length})',
      ),
    );
  }

  Widget _buildAttachmentsSection(bool isDark) {
    return _buildProfessionalCard(
      title: 'Attachments',
      icon: HugeIcons.strokeRoundedFileAttachment,
      children: [
        if (_isLoadingAttachments)
          Center(
            child: LoadingAnimationWidget.horizontalRotatingDots(
              color: isDark ? Colors.white : Theme.of(context).primaryColor,
              size: 35,
            ),
          )
        else if (_attachments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No attachments found.',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          Column(
            children: _attachments
                .map(
                  (attachment) => AttachmentCard(
                    attachment: attachment,
                    onDelete: () => _deleteAttachment(context, attachment),
                    onView: () => _viewAttachment(attachment),
                  ),
                )
                .toList(),
          ),

        SizedBox(
          width: double.infinity,

          child: TextButton(
            onPressed: _uploadAttachment,

            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  HugeIcons.strokeRoundedFolderUpload,
                  size: 20,
                  color: isDark ? Colors.white : null,
                ),
                SizedBox(width: 8),
                Text(
                  'Add Attachment',
                  style: TextStyle(color: isDark ? Colors.white : null),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _tabController.dispose();
    _termsController.dispose();
    _quotationProvider?.removeListener(_fetchProductImagesForOrderLines);

    for (var controller in _headerFieldControllers.values) {
      controller.dispose();
    }
    for (var controller in _footerFieldControllers.values) {
      controller.dispose();
    }
    for (var controller in _productFieldControllers.values) {
      controller.dispose();
    }
    _isMounted = false;
    super.dispose();
  }

  void _fetchProductImagesForOrderLines() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _quotationProvider == null) return;
      final orderLines = _quotationProvider!.orderLines;

      final Set<int> productIdsToFetch = {};
      for (final line in orderLines) {
        final productId =
            (line['product_id'] is List && line['product_id'].isNotEmpty)
            ? line['product_id'][0]
            : null;
        if (productId is int &&
            !_productImages.containsKey(productId) &&
            !_loadingProductImages.contains(productId)) {
          productIdsToFetch.add(productId);
          _loadingProductImages.add(productId);
        }
      }
      if (productIdsToFetch.isEmpty) return;
      try {
        final client = await OdooSessionManager.getClient();
        if (client != null) {
          final result = await client.callKw({
            'model': 'product.product',
            'method': 'search_read',
            'args': [
              [
                ['id', 'in', productIdsToFetch.toList()],
              ],
            ],
            'kwargs': {
              'fields': ['id', 'image_1920'],
              'limit': productIdsToFetch.length,
            },
          });
          if (result is List) {
            final Map<int, Uint8List?> fetchedImages = {};
            for (final prod in result) {
              final id = prod['id'];
              final imageStr = prod['image_1920'];
              if (id is int &&
                  imageStr is String &&
                  imageStr.isNotEmpty &&
                  imageStr != 'false') {
                try {
                  final base64String = imageStr.contains(',')
                      ? imageStr.split(',').last
                      : imageStr;

                  if (base64String.isEmpty || !_isValidBase64(base64String)) {
                    fetchedImages[id] = null;
                    continue;
                  }

                  final decodedBytes = base64Decode(base64String);

                  if (decodedBytes.isNotEmpty && decodedBytes.length > 10) {
                    fetchedImages[id] = decodedBytes;
                  } else {
                    fetchedImages[id] = null;
                  }
                } catch (e) {
                  fetchedImages[id] = null;
                }
              } else if (id is int) {
                fetchedImages[id] = null;
              }
            }
            if (!mounted) return;
            setState(() {
              for (final id in productIdsToFetch) {
                _productImages[id] = fetchedImages[id];
                _loadingProductImages.remove(id);
              }
            });
          }
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          for (final id in productIdsToFetch) {
            _productImages[id] = null;
            _loadingProductImages.remove(id);
          }
        });
      }
    });
  }

  Future<void> _fetchCustomerDetails() async {
    try {
      final partnerId = widget.quotation.customerId;
      if (partnerId == null) {
        return;
      }

      final customerId = partnerId;

      final client = await OdooSessionManager.getClient();
      if (client == null) {
        return;
      }

      List<String> fieldsToFetch = [
        'name',
        'email',
        'phone',
        'mobile',
        'street',
        'street2',
        'city',
        'state_id',
        'zip',
        'country_id',
        'vat',
        'website',
        'category_id',
        'is_company',
        'parent_id',
        'child_ids',

        'customer_rank',
        'image_1920',
      ];

      dynamic result;

      try {
        result = await client.callKw({
          'model': 'res.partner',
          'method': 'search_read',
          'args': [
            [
              ['id', '=', customerId],
            ],
          ],
          'kwargs': {'fields': fieldsToFetch},
        });
      } catch (fieldError) {
        if (fieldError.toString().contains('mobile')) {
          fieldsToFetch.remove('mobile');

          result = await client.callKw({
            'model': 'res.partner',
            'method': 'search_read',
            'args': [
              [
                ['id', '=', customerId],
              ],
            ],
            'kwargs': {'fields': fieldsToFetch},
          });
        } else {
          rethrow;
        }
      }

      if (!mounted) return;
      if (result is List && result.isNotEmpty) {
        final customerData = result[0];

        final contact = Contact.fromJson(customerData);

        setState(() {
          _customerDetails = contact;
          _isLoadingCustomer = false;
          _animationController.forward();
        });
      } else {
        setState(() {
          _isLoadingCustomer = false;
          _animationController.forward();
        });
      }
    } catch (e) {
      if (!mounted) return;

      if (e.toString().contains('credit_limit') ||
          e.toString().contains('AccessError')) {}

      setState(() {
        _isLoadingCustomer = false;
        _animationController.forward();
      });

      if (mounted) {
        CustomSnackbar.showError(context, 'Unable to load customer details');
      }
    }
  }

  String _formatDate(dynamic dateString) {
    if (dateString == null || dateString == false) return 'Not specified';

    if (dateString is bool) return 'Not specified';

    String? dateStr;
    if (dateString is String) {
      dateStr = dateString;
    } else {
      dateStr = dateString.toString();
    }

    if (dateStr.isEmpty || dateStr == 'false' || dateStr == 'true') {
      return 'Not specified';
    }

    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  int _calculateDaysUntilExpiry(dynamic validityDate) {
    if (validityDate == null) return 0;

    String? dateString;
    if (validityDate is String) {
      dateString = validityDate;
    } else {
      dateString = validityDate.toString();
    }

    if (dateString.isEmpty ||
        dateString.toLowerCase() == 'false' ||
        dateString.toLowerCase() == 'true') {
      return 0;
    }

    try {
      final expiry = DateTime.parse(dateString);
      final now = DateTime.now();
      return expiry.difference(now).inDays;
    } catch (e) {
      return 0;
    }
  }

  bool _isExpired(Quote quotation) {
    if (quotation.validityDate == null) return false;
    return quotation.validityDate!.isBefore(DateTime.now());
  }

  bool _canConvertToOrder(Quote quotation) {
    final isSaleOrder = quotation.status == 'sale';
    final isExpired =
        quotation.validityDate != null &&
        quotation.validityDate!.isBefore(DateTime.now());
    final canConvert =
        !isSaleOrder && quotation.status != 'cancel' && !isExpired;
    return canConvert;
  }

  bool _canCreateInvoice(Quote quotation) {
    if (quotation.status != 'sale') {
      return false;
    }

    final invoiceStatus = quotation.invoiceStatus ?? '';
    final amountTotal = quotation.total;
    final amountInvoiced = (quotation.extraData != null)
        ? (quotation.extraData!['amount_invoiced'] as num?)?.toDouble() ?? 0.0
        : 0.0;
    final remainingAmount = amountTotal - amountInvoiced;

    if (invoiceStatus != 'no' && invoiceStatus.isNotEmpty) {
      return true;
    }

    if (remainingAmount > 0.01) {
      return true;
    }

    return false;
  }

  bool _canEditQuotation(Quote quotation) {
    final state = quotation.status;

    if (state == 'cancel' || state == 'done') {
      return false;
    }

    if (state == 'draft' || state == 'sent') {
      return true;
    }

    if (state == 'sale') {
      final invoiceStatus = quotation.invoiceStatus ?? '';
      final deliveryStatus =
          quotation.extraData?['delivery_status']?.toString() ?? '';

      if (invoiceStatus == 'invoiced' || deliveryStatus == 'done') {
        return true;
      }

      return true;
    }

    return false;
  }

  Widget _buildProfessionalCard({
    required String title,
    required List<Widget> children,
    IconData? icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.18)
                : Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.only(left: 12, right: 12, top: 12),

            child: Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.grey[900],
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    bool isDark, {
    bool isImportant = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isImportant
                    ? (isDark ? Colors.white : Colors.grey[900])
                    : (isDark ? Colors.grey[200] : Colors.grey[800]),
                fontSize: 14,
                fontWeight: isImportant ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(
    String label,
    String value,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.transparent : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white : color.withOpacity(0.3),
          width: 1.2,
        ),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    String title,
    List<Widget> children,
    bool isDark, {
    IconData? icon,
  }) {
    _calculateDaysUntilExpiry(_localQuotation.validityDate?.toIso8601String());
    final c = _customerDetails;
    bool isReal(String? v) =>
        v != null && v.trim().isNotEmpty && v.trim().toLowerCase() != 'false';
    final companyName =
        (c != null && c.isCompany == true && isReal(c.companyName))
        ? c.companyName
        : null;
    final partnerName = getCustomerName([
      _localQuotation.customerId,
      _localQuotation.customerName,
    ]);
    final displayName =
        companyName ??
        (c != null && isReal(c.name) && c.name != 'Unnamed Contact'
            ? c.name
            : partnerName);
    final addressParts = c != null
        ? [
            c.street,
            c.street2,
            c.city,
            c.state,
            c.zip,
          ].where((part) => isReal(part)).toList()
        : [];
    final phone = c != null && isReal(c.phone)
        ? c.phone
        : (c != null && isReal(c.mobile) ? c.mobile : null);
    final email = c != null && isReal(c.email) ? c.email : null;

    return _buildProfessionalCard(
      title: title,
      icon: icon,
      children: [
        if (title == 'Quotation Summary') ...[
          _buildDetailRow(
            'Quotation No.',
            _localQuotation.name,
            isDark,
            isImportant: true,
          ),
          _buildDetailRow(
            'Date',
            _formatDate(_localQuotation.dateOrder?.toIso8601String()),
            isDark,
          ),
          _buildDetailRow(
            'Expiry',
            _formatDate(_localQuotation.validityDate?.toIso8601String()),
            isDark,
          ),
          _buildDetailRow('Customer', displayName, isDark),
          if (email != null) _buildDetailRow('Email', email, isDark),
          if (phone != null) _buildDetailRow('Phone', phone, isDark),
        ] else if (title == 'Order Lines') ...[
          if (_quotationProvider == null ||
              _quotationProvider!.orderLines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No order lines found.',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...?_quotationProvider?.orderLines.map(
              (line) => _buildOrderLineCard(line, isDark, _quotationProvider!),
            ),
        ] else if (title == 'Terms & Conditions') ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
            child: Text(
              (_localQuotation.notes == null ||
                      _localQuotation.notes!.trim().isEmpty ||
                      _localQuotation.notes!.trim().toLowerCase() == 'false')
                  ? 'No Terms & Conditions Provided'
                  : _htmlToPlainText(_safeString(_localQuotation.notes)),
              style: TextStyle(
                color: isDark ? Colors.grey[300] : Colors.grey[800],
                fontSize: 14,
                fontStyle:
                    (_localQuotation.notes == null ||
                        _localQuotation.notes!.trim().isEmpty ||
                        _localQuotation.notes!.trim().toLowerCase() == 'false')
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAmountSummary(
    Quote quotation,
    QuotationProvider provider,
    bool isDark,
  ) {
    final discountAmount = (quotation.extraData != null)
        ? (quotation.extraData!['amount_discount'] as num?)?.toDouble() ?? 0.0
        : 0.0;
    final shippingAmount = (quotation.extraData != null)
        ? (quotation.extraData!['amount_delivery'] as num?)?.toDouble() ?? 0.0
        : 0.0;

    double deliveryFromLines = 0.0;
    if (shippingAmount == 0.0) {
      final orderLines = provider.orderLines;
      for (final line in orderLines) {
        final productName = line['name']?.toString().toLowerCase() ?? '';
        if (productName.contains('delivery') ||
            productName.contains('shipping') ||
            productName.contains('freight')) {
          deliveryFromLines +=
              (line['price_subtotal'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }

    final totalShipping = shippingAmount > 0
        ? shippingAmount
        : deliveryFromLines;
    final currencyId =
        (quotation.extraData != null &&
            quotation.extraData!['currency_id'] is List)
        ? quotation.extraData!['currency_id'] as List<dynamic>?
        : null;
    final String? currencyCode = (currencyId != null && currencyId.length > 1)
        ? currencyId[1].toString()
        : null;
    final subtotal = quotation.subtotal;
    final tax = quotation.taxAmount;
    final total = quotation.total;

    return Consumer<CurrencyProvider>(
      builder: (context, currencyProvider, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TOTAL AMOUNT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                letterSpacing: 1,
              ),
            ),
            SizedBox(height: 8),
            Text(
              currencyProvider.formatAmount(total, currency: currencyCode),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Theme.of(context).primaryColor,
              ),
            ),
            SizedBox(height: 12),
            _buildAmountRow('Subtotal', subtotal, provider, currencyId, isDark),
            _buildAmountRow('Tax', tax, provider, currencyId, isDark),
            if (discountAmount > 0)
              _buildAmountRow(
                'Discount',
                -discountAmount,
                provider,
                currencyId,
                isDark,
                isDiscount: true,
              ),
            if (totalShipping > 0)
              _buildAmountRow(
                'Shipping',
                totalShipping,
                provider,
                currencyId,
                isDark,
              ),
            Divider(color: isDark ? Colors.grey[600] : Colors.grey[300]),
            _buildAmountRow(
              'Total',
              total,
              provider,
              currencyId,
              isDark,
              isTotal: true,
            ),
          ],
        );
      },
    );
  }

  Widget _buildAmountRow(
    String label,
    double amount,
    QuotationProvider provider,
    List<dynamic>? currencyId,
    bool isDark, {
    bool isTotal = false,
    bool isDiscount = false,
  }) {
    final String? currencyCode = (currencyId != null && currencyId.length > 1)
        ? currencyId[1].toString()
        : null;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.w600 : FontWeight.w500,
              color: isDiscount
                  ? (isDark ? Colors.red[300] : Colors.red[700])
                  : (isDark ? Colors.grey[300] : Colors.grey[700]),
            ),
          ),
          Consumer<CurrencyProvider>(
            builder: (context, currencyProvider, _) {
              final formattedAmount = currencyProvider.formatAmount(
                amount.abs(),
                currency: currencyCode,
              );

              return Text(
                (isDiscount ? '-' : '') + formattedAmount,
                style: TextStyle(
                  fontSize: isTotal ? 16 : 14,
                  fontWeight: isTotal ? FontWeight.w600 : FontWeight.w500,
                  color: isTotal
                      ? (isDark ? Colors.white : Colors.black87)
                      : isDiscount
                      ? (isDark ? Colors.red[300] : Colors.red[700])
                      : (isDark ? Colors.grey[300] : Colors.grey[700]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOrderLineCard(
    Map<String, dynamic> line,
    bool isDark,
    QuotationProvider provider,
  ) {
    String product;
    if (line['product_id'] is List && (line['product_id'] as List).length > 1) {
      product = (line['product_id'][1] ?? '').toString();
    } else {
      final rawName = line['name']?.toString().trim() ?? '';
      if (rawName.isNotEmpty) {
        String firstLine = rawName.split('\n').first;
        if (firstLine.contains(' - ')) {
          firstLine = firstLine.split(' - ').first;
        }
        product = firstLine.isNotEmpty ? firstLine : 'Custom Line';
      } else {
        product = 'Custom Line';
      }
    }
    final productId =
        line['product_id'] is List && line['product_id'].isNotEmpty
        ? line['product_id'][0]
        : null;
    final quantity = (line['product_uom_qty'] as num?)?.toDouble() ?? 0.0;
    final unitPrice = (line['price_unit'] as num?)?.toDouble() ?? 0.0;
    final subtotal = (line['price_subtotal'] as num?)?.toDouble() ?? 0.0;

    String description = line['name']?.toString() ?? '';
    if (description.startsWith(product)) {
      description = description.substring(product.length).trim();
    }
    final sku = line['default_code']?.toString();
    final barcode = line['barcode']?.toString();
    final currencyId = _localQuotation.currencyId;
    final String? currencyCode = (currencyId != null && currencyId.length > 1)
        ? currencyId[1].toString()
        : null;
    final imageBytes = (productId is int) ? _productImages[productId] : null;
    final isLoadingImage = (productId is int)
        ? _loadingProductImages.contains(productId)
        : false;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: isLoadingImage
                    ? Container(
                        width: 50,
                        height: 50,
                        color: isDark ? Colors.grey[800] : Colors.grey[200],
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : (imageBytes != null)
                    ? _FadeInMemoryImage(bytes: imageBytes)
                    : Container(
                        width: 50,
                        height: 50,
                        color: isDark ? Colors.grey[800] : Colors.grey[200],
                        child: const Icon(
                          HugeIcons.strokeRoundedImage03,
                          color: Colors.grey,
                          size: 30,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.grey[900],
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          height: 1.4,
                        ),
                      ),
                    ],

                    if (sku != null && sku.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            'SKU:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            ' $sku',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],

                    if (barcode != null && barcode.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            'Barcode:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            ' $barcode',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'QUANTITY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      quantity.toStringAsFixed(
                        quantity.truncateToDouble() == quantity ? 0 : 1,
                      ),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.grey[900],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UNIT PRICE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Consumer<CurrencyProvider>(
                      builder: (context, currencyProvider, _) {
                        return Text(
                          currencyProvider.formatAmount(
                            unitPrice,
                            currency: currencyCode,
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.grey[900],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'SUBTOTAL',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Consumer<CurrencyProvider>(
                      builder: (context, currencyProvider, _) {
                        return Text(
                          currencyProvider.formatAmount(
                            subtotal,
                            currency: currencyCode,
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.grey[900],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message, {String? details}) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[900]
            : Colors.white,
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[300]
                      : Colors.grey[800],
                  fontSize: 15,
                ),
              ),
              if (details != null && details.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[850]
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: Text(
                      details,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.red[200]
                            : Colors.red[800],
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _htmlToPlainText(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&');
  }

  String _safeString(dynamic value) {
    if (value == null || value == false) return '';
    if (value is bool) return '';
    if (value is List && value.isNotEmpty) {
      return value[1]?.toString() ?? '';
    }
    return value.toString();
  }

  Future<Uint8List?> fetchCompanyLogo() async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return null;

      final session = await OdooSessionManager.getCurrentSession();
      if (session == null) return null;
      final userResult = await client.callKw({
        'model': 'res.users',
        'method': 'search_read',
        'args': [
          [
            ['login', '=', session.userLogin],
          ],
          ['company_id'],
        ],
        'kwargs': {},
      });
      if (userResult == null || userResult.isEmpty) return null;
      final companyId = userResult[0]['company_id'][0];
      final companyResult = await client.callKw({
        'model': 'res.company',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', companyId],
          ],
          [
            'name',
            'street',
            'street2',
            'city',
            'state_id',
            'zip',
            'country_id',
            'phone',
            'email',
            'website',
            'image_1920',
          ],
        ],
        'kwargs': {},
      });
      if (companyResult == null || companyResult.isEmpty) return null;
      final company = companyResult[0];
      final imageStr = company['image_1920'];
      if (imageStr is String && imageStr.isNotEmpty && imageStr != 'false') {
        final base64String = imageStr.contains(',')
            ? imageStr.split(',').last
            : imageStr;
        return base64Decode(base64String);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _fetchCompanyInfoAndLogo() async {
    setState(() {
      _isLoadingCompany = true;
    });
    try {
      final client = await OdooSessionManager.getClient();
      if (client != null) {
        final session = await OdooSessionManager.getCurrentSession();

        if (session != null) {
          final userResult = await client.callKw({
            'model': 'res.users',
            'method': 'search_read',
            'args': [
              [
                ['login', '=', session.userLogin],
              ],
              ['company_id'],
            ],
            'kwargs': {},
          });
          if (userResult != null && userResult.isNotEmpty) {
            final fallbackCompanyId = userResult[0]['company_id'][0];
            final companyResult = await client.callKw({
              'model': 'res.company',
              'method': 'search_read',
              'args': [
                [
                  ['id', '=', fallbackCompanyId],
                ],
                [
                  'name',
                  'street',
                  'street2',
                  'city',
                  'state_id',
                  'zip',
                  'country_id',
                  'phone',
                  'email',
                  'website',
                ],
              ],
              'kwargs': {},
            });
            if (companyResult != null && companyResult.isNotEmpty) {
              final companyInfo = companyResult[0];
              Uint8List? companyLogo;
              final imageStr = companyInfo['image_1920'];
              if (imageStr is String &&
                  imageStr.isNotEmpty &&
                  imageStr != 'false') {
                try {
                  final base64String = imageStr.contains(',')
                      ? imageStr.split(',').last
                      : imageStr;

                  if (base64String.isNotEmpty && _isValidBase64(base64String)) {
                    final decodedBytes = base64Decode(base64String);

                    if (decodedBytes.isNotEmpty && decodedBytes.length > 10) {
                      companyLogo = decodedBytes;
                    }
                  }
                } catch (e) {
                  companyLogo = null;
                }
              }
              setState(() {
                _companyInfo = companyInfo;
                _companyLogo = companyLogo;
                _isLoadingCompany = false;
              });
              return;
            } else {}
          } else {}
        }
      }
    } catch (e) {
      setState(() {
        _isLoadingCompany = false;
      });
    }
    setState(() {
      _isLoadingCompany = false;
    });
  }

  Future<void> _refreshAll() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await _refreshQuotationData();

      await _quotationProvider?.loadOrderLines(_localQuotation.id!);

      await _fetchCustomerDetails();
      await _fetchCompanyInfoAndLogo();

      if (_localQuotation.status == 'sale') {
        await _loadAttachments();

        await _fetchRelatedInvoices();
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(context, 'Refresh failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _refreshQuotationData() async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client != null) {
        List<String> coreFields = [
          'id',
          'name',
          'partner_id',
          'date_order',
          'validity_date',
          'amount_total',
          'amount_untaxed',
          'amount_tax',
          'amount_invoiced',
          'invoice_status',
          'state',
          'note',
          'currency_id',
          'pricelist_id',
          'payment_term_id',
          'order_line',
        ];

        List<List<String>> fieldCombinations = [
          [...coreFields, 'amount_discount', 'amount_delivery'],

          [...coreFields, 'amount_discount'],

          [...coreFields, 'amount_delivery'],

          coreFields,
        ];

        Map<String, dynamic>? updatedQuotationData;

        for (int i = 0; i < fieldCombinations.length; i++) {
          try {
            final result = await client.callKw({
              'model': 'sale.order',
              'method': 'read',
              'args': [
                [_localQuotation.id!],
              ],
              'kwargs': {'fields': fieldCombinations[i]},
            });

            if (result is List && result.isNotEmpty) {
              updatedQuotationData = result[0];

              break;
            }
          } catch (e) {
            if (i == fieldCombinations.length - 1) {
              throw Exception(
                'Failed to refresh quotation with any field combination: $e',
              );
            }
          }
        }

        if (updatedQuotationData != null) {
          setState(() {
            _localQuotation = Quote.fromJson(updatedQuotationData!);
          });
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  String _getCurrencySymbol() {
    final currencyId =
        (widget.quotation.extraData != null &&
            widget.quotation.extraData!['currency_id'] is List)
        ? widget.quotation.extraData!['currency_id'] as List<dynamic>?
        : null;
    final String? currencyCode = (currencyId != null && currencyId.length > 1)
        ? currencyId[1].toString()
        : null;

    final currencyProvider = Provider.of<CurrencyProvider>(
      context,
      listen: false,
    );
    return currencyProvider.getCurrencySymbol(currencyCode!) ?? '\$';
  }

  Widget _buildTopSection(
    Quote quotation,
    String displayName,
    String? address,
    String? phone,
    String? email,
    bool isDark,
    Color primaryColor,
    bool isSaleOrder,
    int? daysUntilExpiry,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                quotation.name,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF28A745).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isSaleOrder ? 'Sale Order' : 'Quotation',
                  style: TextStyle(
                    color: const Color(0xFF28A745),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          Text(
            displayName,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),

          if (address != null && address.isNotEmpty)
            Text(
              address,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Color(0xff8C8A93),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

          if (_customerDetails?.vat != null &&
              _customerDetails!.vat!.isNotEmpty &&
              _customerDetails!.vat! != 'false') ...[
            const SizedBox(height: 4),
            Text(
              '${_customerDetails?.country ?? 'Country'} – ${_customerDetails!.vat}',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Color(0xff8C8A93),
              ),
            ),
          ],

          const SizedBox(height: 8),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Payment Terms : ${_getPaymentTerms(quotation)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[300] : Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatDate(quotation.dateOrder?.toIso8601String()),
                style: TextStyle(
                  fontSize: 14,
                  color: const Color(0xff0095FF),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(String text, int index, bool isDark) {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, child) {
        final isCurrentlySelected = _tabController.index == index;

        final isClickable = true;
        return GestureDetector(
          onTap: isClickable
              ? () {
                  _tabController.animateTo(index);
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: isCurrentlySelected
                  ? Colors.black
                  : (isDark ? Colors.grey[800] : Colors.white),
              border: Border.all(
                color: isCurrentlySelected
                    ? Colors.black
                    : (isDark ? Colors.grey[600]! : Colors.grey[300]!),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: isCurrentlySelected
                    ? Colors.white
                    : (isDark ? Colors.grey[400] : Colors.grey[700]),
                fontSize: 15,
                fontWeight: isCurrentlySelected
                    ? FontWeight.bold
                    : FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }

  double _calculateTableHeight(int lineCount) {
    const double baseHeight = 120;

    const double rowHeight = 60;

    const double minHeight = 280;

    const double maxHeight = 400;

    double calculatedHeight = baseHeight + (lineCount * rowHeight);

    return calculatedHeight.clamp(minHeight, maxHeight);
  }

  Widget _buildTabsSection(QuotationProvider provider, bool isDark) {
    return Container(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: Container(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTabItem(
                      'Order Lines ${provider.orderLines.length}',
                      0,
                      isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildTabItem('Quote Builder', 1, isDark),
                    const SizedBox(width: 8),
                    _buildTabItem('Other Info', 2, isDark),
                    const SizedBox(width: 8),
                    _buildTabItem('Signature', 3, isDark),
                  ],
                ),
              ),
            ),
          ),

          Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[850] : Colors.white,
              borderRadius: BorderRadius.circular(16),
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
            height: _calculateTableHeight(provider.orderLines.length),
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOrderLinesTable(provider, isDark),

                _buildQuoteBuilderContent(isDark),

                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [_buildOtherInfoContent(isDark)],
                  ),
                ),

                SignatureWidget(
                  quotation: widget.quotation,
                  onSignatureUpdated: (signatureData) {
                    if (mounted) {
                      setState(() {
                        if (widget.quotation.extraData != null) {
                          widget.quotation.extraData!.addAll(signatureData);
                        }
                        _additionalInfo.addAll(signatureData);
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final quotation = widget.quotation;
    final isSaleOrder = quotation.status == 'sale';
    final daysUntilExpiry = quotation.validityDate
        ?.difference(DateTime.now())
        .inDays;
    final c = _customerDetails;
    bool isReal(String? v) =>
        v != null && v.trim().isNotEmpty && v.trim().toLowerCase() != 'false';
    final companyName =
        (c != null && c.isCompany == true && isReal(c.companyName))
        ? c.companyName
        : null;
    final displayName =
        companyName ??
        (c != null && isReal(c.name)
            ? c.name
            : quotation.customerName ?? 'Unknown Customer');

    final addressParts = c != null
        ? [
            c.street,
            c.street2,
            c.city,
            c.state,
            c.zip,
          ].where((part) => isReal(part)).toList()
        : [];
    final address = addressParts.isNotEmpty ? addressParts.join(', ') : null;
    final phone = c != null && isReal(c.phone)
        ? c.phone
        : (c != null && isReal(c.mobile) ? c.mobile : null);
    final email = c != null && isReal(c.email) ? c.email : null;
    final primaryColor = Theme.of(context).primaryColor;

    if (_isLoadingInitialData) {
      return Scaffold(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        appBar: AppBar(
          backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
          foregroundColor: isDark ? Colors.white : primaryColor,
          elevation: 0,
          title: Text(
            isSaleOrder ? 'Sale Order' : 'Quotation',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              HugeIcons.strokeRoundedArrowLeft01,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
        body: ListShimmer.buildQuotationDetailsShimmer(context),
      );
    }

    try {
      if (_isLoadingCustomer) {
        if (_animationController.value != 0.0) {
          _animationController.value = 0.0;
        }
      } else {
        if (_animationController.status != AnimationStatus.forward &&
            _animationController.value != 1.0) {
          _animationController.forward();
        }
      }
    } catch (_) {}

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        foregroundColor: isDark ? Colors.white : primaryColor,
        elevation: 0,
        title: Text(
          isSaleOrder ? 'Sale Order' : 'Quotation',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        actions: [
          _buildRelatedInvoicesSectionDynamic(isDark),
          _buildRelatedDeliveriesSectionDynamic(isDark),

          if (_canEditQuotation(quotation))
            Container(
              margin: const EdgeInsets.only(right: 0),
              child: IconButton(
                icon: Icon(
                  HugeIcons.strokeRoundedPencilEdit02,

                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[400]
                      : Colors.grey[600],
                ),
                tooltip: 'Edit Quotation',
                onPressed: _isLoadingCustomer
                    ? null
                    : () async {
                        Map<String, dynamic>? completeQuotation;
                        try {
                          final client = await OdooSessionManager.getClient();
                          if (client != null) {
                            final quotationData = await client.callKw({
                              'model': 'sale.order',
                              'method': 'read',
                              'args': [
                                [quotation.id],
                              ],
                              'kwargs': {
                                'fields': [
                                  'id',
                                  'name',
                                  'partner_id',
                                  'date_order',
                                  'validity_date',
                                  'amount_total',
                                  'amount_untaxed',
                                  'amount_tax',
                                  'state',
                                  'note',
                                  'currency_id',
                                  'pricelist_id',
                                  'payment_term_id',
                                  'order_line',
                                ],
                              },
                            });

                            if (quotationData is List &&
                                quotationData.isNotEmpty) {
                              completeQuotation = Map<String, dynamic>.from(
                                quotationData[0],
                              );
                            }
                          }
                        } catch (e) {
                          completeQuotation = quotation.toJson();
                        }

                        final result = await Navigator.push(
                          context,

                          MaterialPageRoute(
                            builder: (context) => CreateQuoteScreen(
                              quotationToEdit:
                                  completeQuotation ?? quotation.toJson(),
                            ),
                          ),
                        );

                        if (result == true && mounted) {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (dialogContext) => WillPopScope(
                              onWillPop: () async => false,

                              child: Center(
                                child: Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(),
                                        SizedBox(height: 16),
                                        Text('Updating quotation...'),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );

                          try {
                            final client = await OdooSessionManager.getClient();
                            if (client != null) {
                              final updatedQuotation = await client.callKw({
                                'model': 'sale.order',
                                'method': 'read',
                                'args': [
                                  [_localQuotation.id!],
                                ],
                                'kwargs': {
                                  'fields': [
                                    'id',
                                    'name',
                                    'partner_id',
                                    'date_order',
                                    'validity_date',
                                    'amount_total',
                                    'amount_untaxed',
                                    'amount_tax',
                                    'state',
                                    'note',
                                    'currency_id',
                                    'pricelist_id',
                                    'payment_term_id',
                                    'order_line',
                                  ],
                                },
                              });

                              if (updatedQuotation is List &&
                                  updatedQuotation.isNotEmpty) {
                                setState(() {
                                  _localQuotation = Quote.fromJson(
                                    updatedQuotation[0],
                                  );
                                });
                              }
                            }

                            await _quotationProvider?.loadOrderLines(
                              _localQuotation.id!,
                            );

                            await _fetchCustomerDetails();

                            await _fetchRelatedInvoices();

                            if (mounted && Navigator.of(context).canPop()) {
                              Navigator.of(context).pop();

                              await Future.delayed(Duration(milliseconds: 300));

                              if (mounted) {
                                final state = _localQuotation.status ?? '';
                                final documentType = (state == 'sale')
                                    ? 'Sale Order'
                                    : 'Quotation';

                                CustomSnackbar.showSuccess(
                                  context,
                                  '$documentType updated successfully',
                                );
                              }
                            }
                          } catch (e) {
                            if (mounted && Navigator.of(context).canPop()) {
                              Navigator.of(context).pop();
                            }

                            if (mounted) {
                              CustomSnackbar.showError(
                                context,
                                'Failed to refresh quotation',
                              );
                            }
                          }
                        } else {}
                      },
              ),
            ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[400]
                  : Colors.grey[600],
              size: 20,
            ),
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[900]
                : Colors.white,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            enabled: !_isLoadingCustomer,
            itemBuilder: (context) {
              final canCreateInvoice = _canCreateInvoice(quotation);
              return [
                if (isSaleOrder && canCreateInvoice) ...[
                  PopupMenuItem<String>(
                    value: 'create_invoice',
                    child: Row(
                      children: [
                        Icon(
                          HugeIcons.strokeRoundedInvoice03,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Create Invoice',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_canConvertToOrder(quotation))
                  PopupMenuItem<String>(
                    value: 'convert_to_order',
                    child: Row(
                      children: [
                        Icon(
                          HugeIcons.strokeRoundedRecycle03,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Convert to Sale Order',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_localQuotation.status == 'draft' ||
                    _localQuotation.status == 'cancel')
                  PopupMenuItem<String>(
                    value: 'cancel',
                    child: Row(
                      children: [
                        Icon(
                          HugeIcons.strokeRoundedCancel01,
                          color: isDark ? Colors.white : Colors.black87,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Cancel Quotation',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                PopupMenuItem<String>(
                  value: 'print_quotation',
                  child: Row(
                    children: [
                      Icon(
                        HugeIcons.strokeRoundedFileDownload,
                        color: isDark ? Colors.grey[300] : Colors.grey[800],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _localQuotation.status == 'sale'
                            ? 'Print Sale Order'
                            : 'Print Quotation',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  enabled:
                      _localQuotation.status == 'draft' ||
                      _localQuotation.status == 'cancel',
                  child: Row(
                    children: [
                      Icon(
                        HugeIcons.strokeRoundedDelete02,
                        color:
                            (_localQuotation.status == 'draft' ||
                                _localQuotation.status == 'cancel')
                            ? Colors.red[400]
                            : Colors.grey[500],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Delete',
                        style: TextStyle(
                          color:
                              (_localQuotation.status == 'draft' ||
                                  _localQuotation.status == 'cancel')
                              ? Colors.red[400]
                              : Colors.grey[500],
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'send_quotation',
                  child: Row(
                    children: [
                      Icon(
                        HugeIcons.strokeRoundedShare08,
                        color: isDark ? Colors.grey[300] : Colors.grey[800],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Send by Email',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'send_whatsapp',
                  child: Row(
                    children: [
                      Icon(
                        HugeIcons.strokeRoundedWhatsapp,
                        color: isDark ? Colors.grey[300] : Colors.grey[800],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Share via WhatsApp',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ];
            },
            onSelected: (value) async {
              if (!_isLoadingCustomer) {
                if (value == 'convert_to_order') {
                  await _convertToOrder();
                  return;
                }

                if (value == 'cancel') {
                  await _confirmCancelQuotation();
                  return;
                }

                if (value == 'print_quotation') {
                  _showPrintBottomSheet();
                  return;
                }
                if (value == 'create_invoice') {
                  _navigateToCreateInvoice(quotation);
                  return;
                }

                if (value == 'delete') {
                  await _confirmDelete();
                  return;
                }
                final isDark = Theme.of(context).brightness == Brightness.dark;
                final dialogContext = context;

                showDialog(
                  context: dialogContext,
                  useRootNavigator: true,
                  barrierDismissible: false,
                  barrierColor: isDark
                      ? Colors.black.withOpacity(0.6)
                      : Colors.black.withOpacity(0.3),
                  builder: (ctx) {
                    return Dialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
                      elevation: isDark ? 4 : 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 32,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[900] : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: isDark
                              ? Border.all(color: Colors.grey[800]!, width: 1)
                              : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withOpacity(0.1)
                                    : Theme.of(
                                        context,
                                      ).primaryColor.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: LoadingAnimationWidget.fourRotatingDots(
                                color: isDark
                                    ? Colors.white
                                    : Theme.of(context).primaryColor,
                                size: 35,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              value == 'send_quotation'
                                  ? 'Sending Quotation'
                                  : value == 'send_whatsapp'
                                  ? 'Sharing via WhatsApp'
                                  : 'Generating PDF',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.grey[800],
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              value == 'send_quotation'
                                  ? 'Please wait while we send your quotation'
                                  : value == 'send_whatsapp'
                                  ? 'Please wait while we prepare to share via WhatsApp'
                                  : 'Please wait while we prepare your document',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: isDark
                                        ? Colors.grey[300]
                                        : Colors.grey[600],
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );

                var didCloseDialog = false;
                void closeDialogOnce() {
                  if (didCloseDialog) return;
                  if (!dialogContext.mounted) return;

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (didCloseDialog) return;
                    try {
                      final rootNav = Navigator.of(
                        dialogContext,
                        rootNavigator: true,
                      );
                      if (rootNav.canPop()) {
                        rootNav.pop();
                        didCloseDialog = true;
                      }
                    } catch (_) {}
                  });
                }

                try {
                  if (value == 'send_quotation') {
                    await QuotationService.sendQuotation(
                      dialogContext,
                      _localQuotation.id!,
                      closeLoadingDialog: () {
                        closeDialogOnce();
                      },
                    );
                  } else if (value == 'print_quotation') {
                    closeDialogOnce();
                    _showPrintBottomSheet();
                  } else if (value == 'send_whatsapp') {
                    try {
                      await PDFGenerator.sendQuotationViaWhatsApp(
                        context,
                        _localQuotation,
                      );
                    } catch (e) {
                      _showSnackSafe(
                        'WhatsApp sharing failed: ${e.toString()}',
                        error: true,
                      );
                    } finally {
                      closeDialogOnce();
                    }
                  }
                } catch (e) {
                  _showSnackSafe(
                    'Operation failed: ${e.toString()}',
                    error: true,
                  );
                }
              } else {
                _showSnackSafe(
                  'Please wait for the current operation to complete',
                  error: true,
                );
              }
            },
          ),
        ],
      ),
      body: _isLoadingCustomer
          ? ListShimmer.buildQuotationDetailsShimmer(context)
          : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    key: _refreshKey,
                    color: primaryColor,
                    onRefresh: _refreshAll,
                    child: Consumer<QuotationProvider>(
                      builder: (context, provider, child) {
                        return FadeTransition(
                          opacity: _fadeAnimation,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildTopSection(
                                  quotation,
                                  displayName,
                                  address,
                                  phone,
                                  email,
                                  isDark,
                                  primaryColor,
                                  isSaleOrder,
                                  daysUntilExpiry,
                                ),
                                const SizedBox(height: 12),

                                _buildTabsSection(provider, isDark),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                Consumer<QuotationProvider>(
                  builder: (context, provider, child) {
                    return buildTicketAmountSummaryQuote(
                      provider,
                      _localQuotation.toJson(),
                      isDark,
                    );
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shimmerBase = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final shimmerHighlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Shimmer.fromColors(
        baseColor: shimmerBase,
        highlightColor: shimmerHighlight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: isDark
                        ? Colors.grey[800]
                        : Colors.grey[300],
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 22,
                          color: isDark ? Colors.grey[800] : Colors.white,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 120,
                          height: 14,
                          color: isDark ? Colors.grey[800] : Colors.white,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 24,
                                color: isDark ? Colors.grey[800] : Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 24,
                                color: isDark ? Colors.grey[800] : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 120,
                    height: 16,
                    color: isDark ? Colors.grey[800] : Colors.white,
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(
                    4,
                    (index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        width: double.infinity,
                        height: 14,
                        color: isDark ? Colors.grey[800] : Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    height: 32,
                    color: isDark ? Colors.grey[800] : Colors.white,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(
                  2,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[800] : Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: double.infinity,
                                height: 14,
                                color: isDark ? Colors.grey[800] : Colors.white,
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: 120,
                                height: 12,
                                color: isDark ? Colors.grey[800] : Colors.white,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 60,
                          height: 20,
                          color: isDark ? Colors.grey[800] : Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: List.generate(
                2,
                (index) => Expanded(
                  child: Container(
                    height: 44,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[900] : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 120,
                    height: 16,
                    color: isDark ? Colors.grey[800] : Colors.white,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    height: 40,
                    color: isDark ? Colors.grey[800] : Colors.white,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtherInfoContent(bool isDark) {
    if (_isLoadingAdditionalInfo) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: LoadingAnimationWidget.staggeredDotsWave(
            color: const Color(0xFFC03355),
            size: 50,
          ),
        ),
      );
    }

    if (_additionalInfo.isEmpty) {
      if (!_isLoadingAdditionalInfo) {
        Future.microtask(() => _fetchAdditionalInfo());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: LoadingAnimationWidget.staggeredDotsWave(
            color: const Color(0xFFC03355),
            size: 50,
          ),
        ),
      );
    }

    final data = {..._localQuotation.toJson(), ..._additionalInfo};

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoSectionQuotation('SALES', isDark, [
            ('Salesperson', _safeString(data['user_id'])),
            ('Sales Team', _safeString(data['team_id'])),
            ('Online Signature', _formatBoolean(data['require_signature'])),
            ('Online Payment', _formatBoolean(data['require_payment'])),
            ('Reference', _safeString(data['client_order_ref'])),
            ('Tags', _formatTags(data['tag_ids'])),
          ]),
          const SizedBox(height: 20),

          _buildInfoSectionQuotation('INVOICING', isDark, [
            ('Payment Terms', _safeString(data['payment_term_id'])),
            ('Fiscal Position', _safeString(data['fiscal_position_id'])),
          ]),
          const SizedBox(height: 20),

          _buildInfoSectionQuotation('SHIPPING', isDark, [
            ('Incoterm', _safeString(data['incoterm_id'])),
            ('Warehouse', _safeString(data['warehouse_id'])),
            ('Delivery Date', _formatDate(data['commitment_date'])),
          ]),
          const SizedBox(height: 20),

          _buildInfoSectionQuotation('TRACKING', isDark, [
            ('Source Document', _safeString(data['origin'])),
            ('Opportunity', _safeString(data['opportunity_id'])),
            ('Campaign', _safeString(data['campaign_id'])),
            ('Source', _safeString(data['source_id'])),
            ('Medium', _safeString(data['medium_id'])),
          ]),
        ],
      ),
    );
  }

  Widget _buildInfoSectionQuotation(
    String title,
    bool isDark,
    List<(String, String)> fields,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[850] : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
            ),
          ),
          child: Column(
            children: [
              for (int i = 0; i < fields.length; i++)
                _buildOtherInfoRowQuotation(
                  fields[i].$1,
                  fields[i].$2,
                  isDark,
                  isLast: i == fields.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOtherInfoRowQuotation(
    String label,
    String value,
    bool isDark, {
    bool isLast = false,
  }) {
    final displayValue = value.isEmpty ? 'Not specified' : value;
    final isNotSpecified = value.isEmpty;

    return InkWell(
      onTap: () {
        if (!isNotSpecified) {
          _showFieldInfoQuotation(label, value);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                    width: 1,
                  ),
                ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[400] : Colors.grey[700],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: Text(
                displayValue,
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: isNotSpecified
                      ? (isDark ? Colors.grey[600] : Colors.grey[400])
                      : (isDark ? Colors.grey[200] : Colors.grey[900]),
                  fontStyle: isNotSpecified
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFieldInfoQuotation(String label, String value) {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? Colors.grey[850] : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          content: SelectableText(
            value,
            style: GoogleFonts.montserrat(
              fontSize: 15,
              color: isDark ? Colors.grey[300] : Colors.grey[800],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Close',
                style: GoogleFonts.montserrat(
                  color: const Color(0xFFC03355),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatTags(dynamic tags) {
    if (tags == null || tags == false) return '';
    if (tags is List) {
      final tagNames = tags.map((tag) {
        if (tag is List && tag.length > 1) {
          return tag[1].toString();
        }
        return tag.toString();
      }).toList();
      return tagNames.join(', ');
    }
    return tags.toString();
  }

  String _formatBoolean(dynamic value) {
    if (value == null || value == false) return '';
    if (value == true) return 'Yes';
    return value.toString();
  }

  Widget _buildQuoteBuilderContent(bool isDark) {
    if (_isLoadingQuoteBuilder) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: CircularProgressIndicator(
            color: Theme.of(context).primaryColor,
          ),
        ),
      );
    }

    if (_quoteBuilderData.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 64,
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                ),
                const SizedBox(height: 24),
                Text(
                  'Quote Builder',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This feature is only available in Odoo 18',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Quote Builder allows you to manage PDF documents\n(headers, footers, and product documents)\nfor your quotations',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[500] : Colors.grey[500],
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Quote Builder',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.grey[800],
                ),
              ),
              const Spacer(),
              if (_isSavingQuoteBuilder)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).primaryColor,
                  ),
                )
              else
                IconButton(
                  icon: Icon(
                    _isQuoteBuilderEditMode ? Icons.save : Icons.edit,
                    color: Theme.of(context).primaryColor,
                  ),
                  onPressed: () {
                    if (_isQuoteBuilderEditMode) {
                      _saveQuoteBuilderSelections();
                    } else {
                      setState(() {
                        _isQuoteBuilderEditMode = true;
                      });
                    }
                  },
                  tooltip: _isQuoteBuilderEditMode ? 'Save' : 'Edit',
                ),
            ],
          ),
          const SizedBox(height: 16),

          _buildQuoteBuilderSection(
            'Headers',
            _quoteBuilderData['headers']?['files'] ?? [],
            'header',
            isDark,
          ),
          const SizedBox(height: 24),

          _buildQuoteBuilderSection(
            'Footers',
            _quoteBuilderData['footers']?['files'] ?? [],
            'footer',
            isDark,
          ),
          const SizedBox(height: 24),

          _buildProductDocumentsSection(
            _quoteBuilderData['lines'] ?? [],
            isDark,
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget _buildQuoteBuilderSection(
    String title,
    List<dynamic> files,
    String section,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.grey[800],
          ),
        ),
        const SizedBox(height: 12),
        if (files.isEmpty)
          _buildEmptySection('No documents available', isDark)
        else
          ...files.map(
            (file) => _buildDocumentTile(file, section, isDark, null),
          ),
      ],
    );
  }

  Widget _buildProductDocumentsSection(List<dynamic> lines, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Product Documents',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.grey[800],
          ),
        ),
        const SizedBox(height: 12),
        if (lines.isEmpty)
          _buildEmptySection('No product documents available', isDark)
        else
          ...lines.map((line) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line['name'] ?? '',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...((line['files'] ?? []) as List).map(
                    (file) =>
                        _buildDocumentTile(file, 'lines', isDark, line['id']),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildEmptySection(String message, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 48,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentTile(
    Map<String, dynamic> file,
    String section,
    bool isDark,
    int? lineId,
  ) {
    bool isSelected =
        section == 'header' && _selectedHeaderIds.contains(file['id']) ||
        section == 'footer' && _selectedFooterIds.contains(file['id']) ||
        (section == 'lines' &&
            lineId != null &&
            _selectedProductDocs[lineId]?.contains(file['id']) == true);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isQuoteBuilderEditMode
                  ? () {
                      _toggleDocumentSelection(file['id'], section, lineId);
                    }
                  : null,
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).primaryColor.withOpacity(0.15)
                      : (isDark ? Colors.grey[850] : Colors.white),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        file['name'] ?? '',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected
                              ? Theme.of(context).primaryColor
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : Colors.transparent,
                        border: Border.all(
                          color: isSelected
                              ? Theme.of(context).primaryColor
                              : (isDark
                                    ? Colors.grey[600]!
                                    : Colors.grey[400]!),
                        ),
                      ),
                      child: Icon(
                        isSelected ? Icons.check : Icons.add,
                        size: 16,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.grey[600] : Colors.grey[400]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (isSelected &&
              file['custom_form_fields'] != null &&
              (file['custom_form_fields'] as List).isNotEmpty)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[850] : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Custom Fields',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...(file['custom_form_fields'] as List).map((field) {
                      String controllerKey = "${file['id']}_${field['name']}";
                      TextEditingController controller;

                      if (section == 'header') {
                        controller = _headerFieldControllers.putIfAbsent(
                          controllerKey,
                          () => TextEditingController(
                            text: field['value']?.toString() ?? '',
                          ),
                        );
                      } else if (section == 'footer') {
                        controller = _footerFieldControllers.putIfAbsent(
                          controllerKey,
                          () => TextEditingController(
                            text: field['value']?.toString() ?? '',
                          ),
                        );
                      } else {
                        controller = _productFieldControllers.putIfAbsent(
                          controllerKey,
                          () => TextEditingController(
                            text: field['value']?.toString() ?? '',
                          ),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextFormField(
                          controller: controller,
                          enabled: _isQuoteBuilderEditMode,
                          decoration: InputDecoration(
                            labelText: field['name']?.toString() ?? '',
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: isDark ? Colors.grey[800] : Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _toggleDocumentSelection(int fileId, String section, int? lineId) {
    setState(() {
      if (section == 'header') {
        if (_selectedHeaderIds.contains(fileId)) {
          _selectedHeaderIds.remove(fileId);
        } else {
          _selectedHeaderIds.add(fileId);
        }
      } else if (section == 'footer') {
        if (_selectedFooterIds.contains(fileId)) {
          _selectedFooterIds.remove(fileId);
        } else {
          _selectedFooterIds.add(fileId);
        }
      } else if (section == 'lines' && lineId != null) {
        if (_selectedProductDocs[lineId] == null) {
          _selectedProductDocs[lineId] = {};
        }
        if (_selectedProductDocs[lineId]!.contains(fileId)) {
          _selectedProductDocs[lineId]!.remove(fileId);
        } else {
          _selectedProductDocs[lineId]!.add(fileId);
        }
      }
    });
  }

  Widget _buildInfoSection(
    String title,
    bool isDark,
    List<(String, String)> items,
  ) {
    final validItems = items
        .where((item) => item.$2.isNotEmpty && item.$2 != 'false')
        .toList();
    if (validItems.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.grey[800],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[850] : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
              width: 1,
            ),
          ),
          child: Column(
            children: validItems
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 130,
                          child: Text(
                            item.$1,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            item.$2,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderLinesTable(QuotationProvider provider, bool isDark) {
    if (provider.orderLines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'No order lines found.',
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    final ScrollController verticalController = ScrollController();
    final ScrollController horizontalController = ScrollController();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Theme(
        data: Theme.of(context).copyWith(
          scrollbarTheme: ScrollbarThemeData(
            thumbVisibility: WidgetStateProperty.all(true),
            trackVisibility: WidgetStateProperty.all(true),
            thickness: WidgetStateProperty.all(6),
            radius: const Radius.circular(5),
            thumbColor: WidgetStateProperty.all(
              isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            trackColor: WidgetStateProperty.all(
              isDark ? Colors.grey[800] : Colors.grey[100],
            ),
            trackBorderColor: WidgetStateProperty.all(
              isDark ? Colors.grey[700] : Colors.grey[100],
            ),
            interactive: true,
            crossAxisMargin: 4,
            mainAxisMargin: 8,
          ),
        ),
        child: Scrollbar(
          controller: verticalController,
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          thickness: 6,
          radius: const Radius.circular(5),
          child: SingleChildScrollView(
            controller: verticalController,
            scrollDirection: Axis.vertical,
            padding: const EdgeInsets.only(right: 12),
            child: SingleChildScrollView(
              controller: horizontalController,
              scrollDirection: Axis.horizontal,
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black26
                          : Colors.grey.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Table(
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                        width: 1,
                      ),
                    ),
                    columnWidths: const {
                      0: FixedColumnWidth(200),
                      1: FixedColumnWidth(135),
                      2: FixedColumnWidth(120),
                      3: FixedColumnWidth(120),
                      4: FixedColumnWidth(120),
                      5: FixedColumnWidth(100),
                      6: FixedColumnWidth(140),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF3A3A3A)
                              : const Color(0xFFF8F9FA),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
                          ),
                        ),
                        children: [
                          TableCell(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Text(
                                'Product',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.grey[800],
                                ),
                              ),
                            ),
                          ),
                          TableCell(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Text(
                                'Quantity',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.grey[800],
                                ),
                              ),
                            ),
                          ),
                          TableCell(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Text(
                                'Delivered',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.grey[800],
                                ),
                              ),
                            ),
                          ),
                          TableCell(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Text(
                                'Invoiced',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.grey[800],
                                ),
                              ),
                            ),
                          ),
                          TableCell(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Text(
                                'Unit Price',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.grey[800],
                                ),
                              ),
                            ),
                          ),
                          TableCell(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Text(
                                'Taxes',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.grey[800],
                                ),
                              ),
                            ),
                          ),
                          TableCell(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Text(
                                'Total Amount',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.grey[800],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      ...provider.orderLines.asMap().entries.map((entry) {
                        final index = entry.key;
                        final line = entry.value;

                        String productName = 'Unknown Product';
                        final productId = line['product_id'];
                        if (productId is List && productId.length > 1) {
                          productName = productId[1].toString();
                        } else if (productId is String) {
                          productName = productId;
                        } else {
                          productName = _safeString(productId);
                        }

                        final quantity =
                            (line['product_uom_qty'] as num?)?.toDouble() ??
                            0.0;
                        final delivered =
                            (line['qty_delivered'] as num?)?.toDouble() ?? 0.0;
                        final invoiced =
                            (line['qty_invoiced'] as num?)?.toDouble() ?? 0.0;
                        final unitPrice =
                            (line['price_unit'] as num?)?.toDouble() ?? 0.0;
                        final taxAmount =
                            (line['price_tax'] as num?)?.toDouble() ?? 0.0;
                        final totalAmount =
                            (line['price_subtotal'] as num?)?.toDouble() ?? 0.0;

                        return TableRow(
                          children: [
                            TableCell(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      child: Text(
                                        '${index + 1}.',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? Colors.grey[300]
                                              : Colors.grey[700],
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        productName,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? Colors.grey[300]
                                              : Colors.grey[700],
                                          height: 1.3,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            TableCell(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                      quantity.toStringAsFixed(2),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            TableCell(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    delivered.toStringAsFixed(2),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: isDark
                                          ? Colors.grey[300]
                                          : Colors.grey[700],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            TableCell(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    invoiced.toStringAsFixed(2),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: isDark
                                          ? Colors.grey[300]
                                          : Colors.grey[700],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            TableCell(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Consumer<CurrencyProvider>(
                                    builder:
                                        (context, currencyProvider, child) {
                                          return Text(
                                            currencyProvider.formatAmount(
                                              unitPrice,
                                            ),
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              color: isDark
                                                  ? Colors.grey[300]
                                                  : Colors.grey[700],
                                            ),
                                          );
                                        },
                                  ),
                                ),
                              ),
                            ),

                            TableCell(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    provider.buildTaxPercentLabel(
                                      line['tax_id'],
                                    ),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: isDark
                                          ? Colors.grey[300]
                                          : Colors.grey[700],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            TableCell(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Consumer<CurrencyProvider>(
                                    builder:
                                        (context, currencyProvider, child) {
                                          return Text(
                                            currencyProvider.formatAmount(
                                              totalAmount,
                                            ),
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.grey[800],
                                            ),
                                          );
                                        },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FadeInMemoryImage extends StatefulWidget {
  final Uint8List bytes;

  const _FadeInMemoryImage({required this.bytes});

  @override
  State<_FadeInMemoryImage> createState() => _FadeInMemoryImageState();
}

class _FadeInMemoryImageState extends State<_FadeInMemoryImage> {
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _opacity = 1.0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeIn,
      child: Image.memory(
        widget.bytes,
        fit: BoxFit.cover,
        width: 48,
        height: 48,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 48,
            height: 48,
            color: Colors.grey[200],
            child: Icon(
              Icons.image_not_supported,
              color: Colors.grey,
              size: 28,
            ),
          );
        },
      ),
    );
  }
}

class DashedLinePainter extends CustomPainter {
  final Color color;
  final double dashHeight;
  final double dashSpace;

  DashedLinePainter({
    required this.color,
    this.dashHeight = 5,
    this.dashSpace = 5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    double y = 0;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(0, y + dashHeight), paint);
      y += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

Widget _buildTicketRow(
  String label,
  double amount,
  CurrencyProvider currencyProvider,
  String? currencyCode, {
  bool isTotal = false,
  bool isDiscount = false,
}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: isTotal ? 16 : 14,
          fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
          color: Colors.white.withOpacity(isTotal ? 1.0 : 0.9),
        ),
      ),
      Text(
        currencyProvider.formatAmount(amount.abs(), currency: currencyCode),
        style: TextStyle(
          fontSize: isTotal ? 18 : 15,
          fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
          color: isDiscount ? Colors.greenAccent : Colors.white,
        ),
      ),
    ],
  );
}

Widget buildTicketAmountSummaryQuote(
  QuotationProvider provider,
  Map<String, dynamic> quotation,
  bool isDark,
) {
  final currencyId = quotation['currency_id'] as List<dynamic>?;
  final String? currencyCode = (currencyId != null && currencyId.length > 1)
      ? currencyId[1].toString()
      : null;

  final untaxedAmount =
      (quotation['amount_untaxed'] as num?)?.toDouble() ?? 0.0;
  final taxAmount = (quotation['amount_tax'] as num?)?.toDouble() ?? 0.0;
  final totalAmount = (quotation['amount_total'] as num?)?.toDouble() ?? 0.0;

  return Consumer<CurrencyProvider>(
    builder: (context, currencyProvider, _) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF000000) : const Color(0xFFFAE6E8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Untaxed Amount',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: isDark
                              ? const Color(0xFFFFFFFF)
                              : const Color(0xFF000000),
                        ),
                      ),
                      Text(
                        currencyProvider.formatAmount(
                          untaxedAmount,
                          currency: currencyCode,
                        ),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: isDark
                              ? const Color(0xFFFFFFFF)
                              : const Color(0xFF000000),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Tax',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: isDark
                              ? const Color(0xFFFFFFFF)
                              : const Color(0xFF000000),
                        ),
                      ),
                      Text(
                        currencyProvider.formatAmount(
                          taxAmount,
                          currency: currencyCode,
                        ),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: isDark
                              ? const Color(0xFFFFFFFF)
                              : const Color(0xFF000000),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Container(
              color: const Color(0xFFC03355),
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                bottom: true,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 12,
                    bottom: 24,
                  ),
                  decoration: const BoxDecoration(color: Color(0xFFC03355)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFFFFF),
                        ),
                      ),
                      Text(
                        currencyProvider.formatAmount(
                          totalAmount,
                          currency: currencyCode,
                        ),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
