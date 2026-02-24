import 'dart:async';
import 'dart:io';
import '../models/invoice.dart';
import '../models/quote.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import '../services/odoo_session_manager.dart';
import 'custom_snackbar.dart';

class PDFGenerator {
  static const bool _debugMode = true;
  static const Duration _requestTimeout = Duration(minutes: 8);
  static const Duration _localTimeout = Duration(minutes: 15);
  static const int _maxRetryAttempts = 3;

  static void _log(String message, {String? method, String level = 'INFO'}) {
    if (_debugMode) {
      final timestamp = DateTime.now().toIso8601String();
    }
  }

  static Future<void> generateInvoicePdf(
    BuildContext context,
    Invoice invoice, {
    VoidCallback? onBeforeOpen,
  }) async {
    const methodName = 'generateInvoicePdf';
    _log('Starting Invoice PDF generation', method: methodName);

    final odooSession = await OdooSessionManager.getCurrentSession();
    final String odooUrl = odooSession?.serverUrl ?? '';
    final int? invoiceId = invoice.id;
    final String invoiceName = invoice.name;

    const reportNames = [
      'account.report_invoice_with_payments',
      'account.report_invoice',
      'account.account_invoices',

      'account.report_invoice_document',
      'account.account_invoice_report',
    ];

    if (odooUrl.isEmpty || invoiceId == null) {
      _log('Invalid parameters', method: methodName, level: 'ERROR');
      if (context.mounted) {
        _showErrorSnackBar(
          context,
          'Unable to generate PDF: Missing required information',
        );
      }
      return;
    }

    try {
      http.Response? successfulResponse;
      Exception? lastError;
      bool isLocalEnvironment = _isLocalEnvironment(odooUrl);
      Duration timeoutDuration = isLocalEnvironment
          ? _localTimeout
          : _requestTimeout;

      _log(
        'Detected ${isLocalEnvironment ? 'local' : 'remote'} environment, using ${timeoutDuration.inMinutes}min timeout',
        method: methodName,
      );

      for (final reportName in reportNames) {
        for (int attempt = 1; attempt <= _maxRetryAttempts; attempt++) {
          try {
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final pdfUrl =
                '$odooUrl/report/pdf/$reportName/$invoiceId?t=$timestamp';
            _log(
              'Attempt $attempt: Trying report $reportName at $pdfUrl',
              method: methodName,
            );

            final response = await _makeRequestWithRetry(
              context,
              () => OdooSessionManager.makeAuthenticatedRequest(pdfUrl),
              reportName: reportName,
              timeout: timeoutDuration,
            );

            if (response.statusCode == 200 &&
                _isPdfContent(response.bodyBytes)) {
              successfulResponse = response;
              _log(
                'Successfully generated Invoice PDF with report $reportName',
                method: methodName,
              );
              break;
            } else if (response.statusCode != 200) {
              _log(
                'Report $reportName returned status ${response.statusCode}',
                method: methodName,
                level: 'WARN',
              );
              lastError = Exception(
                'Report $reportName failed with status ${response.statusCode}',
              );
            }
          } on TimeoutException {
            _log(
              'Request timed out on attempt $attempt for report $reportName after ${timeoutDuration.inMinutes} minutes',
              method: methodName,
              level: 'WARN',
            );
            lastError = TimeoutException(
              'PDF generation is taking longer than expected',
              timeoutDuration,
            );
            if (attempt < _maxRetryAttempts) {
              _log('Waiting before retry...', method: methodName);
              await Future.delayed(Duration(seconds: 3 * attempt));
            }
          } catch (e) {
            _log(
              'Error with report $reportName (attempt $attempt): $e',
              method: methodName,
              level: 'WARN',
            );
            lastError = e is Exception ? e : Exception(e.toString());
            if (attempt < _maxRetryAttempts) {
              await Future.delayed(Duration(seconds: 2 * attempt));
            }
          }
        }
        if (successfulResponse != null) break;
      }

      if (successfulResponse == null) {
        _log(
          'All Invoice PDF generation attempts failed',
          method: methodName,
          level: 'ERROR',
        );
        throw lastError ??
            Exception(
              'Invoice PDF generation failed after multiple attempts. Please check your connection and try again.',
            );
      }

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'Invoice_${invoiceName}_${DateTime.now().millisecondsSinceEpoch}.pdf'
              .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
      final filePath = '${tempDir.path}/$fileName';

      await _cleanUpOldInvoicePdfFiles(tempDir, invoiceName);

      final file = File(filePath);
      await file.writeAsBytes(successfulResponse.bodyBytes);

      if (!await file.exists()) {
        throw Exception(
          'Invoice PDF was generated but failed to save to device',
        );
      }

      _log('Invoice PDF saved successfully: $filePath', method: methodName);

      if (onBeforeOpen != null) {
        onBeforeOpen();
      }

      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done && context.mounted) {
        _showErrorSnackBar(
          context,
          'Invoice PDF generated successfully but unable to open: ${result.message}',
        );
      } else if (context.mounted) {
        _showSuccessSnackBar(
          context,
          'Invoice PDF generated and opened successfully',
        );
      }
    } on TimeoutException {
      _log(
        'Invoice PDF generation timed out',
        method: methodName,
        level: 'ERROR',
      );
      if (context.mounted) {
        _showErrorSnackBar(
          context,
          'Invoice PDF generation is taking longer than expected. Please try again in a moment.',
        );
      }
    } on SocketException catch (e) {
      _log('Network error: $e', method: methodName, level: 'ERROR');
      if (context.mounted) {
        _showErrorSnackBar(
          context,
          'Network connection issue. Please check your internet connection and try again.',
        );
      }
    } catch (e, stackTrace) {
      _log(
        'Unexpected error: ${e.toString()}',
        method: methodName,
        level: 'ERROR',
      );
      _log('StackTrace: $stackTrace', method: methodName, level: 'ERROR');
      if (context.mounted) {
        _showErrorSnackBar(context, _getUserFriendlyError(e));
      }
    }
  }

  static Future<void> sendInvoiceViaWhatsApp(
    BuildContext context,
    Invoice invoice,
  ) async {
    const methodName = 'sendInvoiceViaWhatsApp';
    _log('Starting invoice sharing via WhatsApp', method: methodName);

    final odooSession = await OdooSessionManager.getCurrentSession();
    final String odooUrl = odooSession?.serverUrl ?? '';
    final int? invoiceId = invoice.id;
    final String invoiceName = invoice.name;

    const reportNames = [
      'account.report_invoice_with_payments',
      'account.report_invoice',
      'account.account_invoices',
    ];

    if (odooUrl.isEmpty || invoiceId == null) {
      _log(
        'Invalid parameters: missing URL or invoice ID',
        method: methodName,
        level: 'ERROR',
      );
      if (context.mounted) {
        _showErrorSnackBar(
          context,
          'Unable to send invoice: Missing required information',
        );
      }
      return;
    }

    try {
      final filePath = await _generateInvoicePdf(
        context,
        odooUrl,
        invoiceId,
        invoiceName,
        reportNames,
      );

      if (filePath == null) {
        throw Exception('Failed to generate PDF');
      }

      final xFile = XFile(filePath);
      final message =
          'Here is your invoice $invoiceName. Please review and let us know if you have any questions.';

      await _sharePdfWithFallback(context, xFile, message, isInvoice: true);
    } catch (e, stackTrace) {
      _log(
        'Unexpected error: ${e.toString()}',
        method: methodName,
        level: 'ERROR',
      );
      _log('StackTrace: $stackTrace', method: methodName, level: 'ERROR');
      if (context.mounted) {
        _showErrorSnackBar(context, _getUserFriendlyError(e));
      }
    }
  }

  static Future<void> _sharePdfWithFallback(
    BuildContext context,
    XFile file,
    String message, {
    bool isInvoice = false,
  }) async {
    try {
      await Share.shareXFiles(
        [file],
        text: message,
        subject: isInvoice ? 'Invoice' : 'Quotation',
        sharePositionOrigin: Rect.fromLTWH(
          0,
          0,
          MediaQuery.of(context).size.width,
          MediaQuery.of(context).size.height / 2,
        ),
      );

      if (context.mounted) {
        _showSuccessSnackBar(
          context,
          isInvoice
              ? 'Invoice shared successfully'
              : 'Quotation shared successfully',
        );
      }
    } catch (e) {
      _log('Error sharing with text: $e', level: 'WARN');

      try {
        await Share.shareXFiles(
          [file],
          sharePositionOrigin: Rect.fromLTWH(
            0,
            0,
            MediaQuery.of(context).size.width,
            MediaQuery.of(context).size.height / 2,
          ),
        );

        if (context.mounted) {
          _showSuccessSnackBar(
            context,
            isInvoice
                ? 'Invoice PDF shared successfully'
                : 'Quotation PDF shared successfully',
          );
        }
      } catch (e) {
        _log('Error sharing PDF only: $e', level: 'ERROR');
        if (context.mounted) {
          _showErrorSnackBar(
            context,
            isInvoice ? 'Failed to share invoice' : 'Failed to share quotation',
          );
        }
        rethrow;
      }
    }
  }

  static Future<String?> _generateInvoicePdf(
    BuildContext context,
    String odooUrl,
    int invoiceId,
    String invoiceName,
    List<String> reportNames,
  ) async {
    http.Response? successfulResponse;
    bool isLocalEnvironment = _isLocalEnvironment(odooUrl);
    Duration timeoutDuration = isLocalEnvironment
        ? _localTimeout
        : _requestTimeout;

    for (final reportName in reportNames) {
      for (int attempt = 1; attempt <= _maxRetryAttempts; attempt++) {
        try {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final pdfUrl =
              '$odooUrl/report/pdf/$reportName/$invoiceId?t=$timestamp';

          final response = await _makeRequestWithRetry(
            context,
            () => OdooSessionManager.makeAuthenticatedRequest(pdfUrl),
            reportName: reportName,
            timeout: timeoutDuration,
          );

          if (response.statusCode == 200 && _isPdfContent(response.bodyBytes)) {
            successfulResponse = response;
            break;
          }
        } catch (e) {
          if (attempt == _maxRetryAttempts) continue;
          await Future.delayed(Duration(seconds: 2 * attempt));
        }
      }
      if (successfulResponse != null) break;
    }

    if (successfulResponse == null) return null;

    final tempDir = await getTemporaryDirectory();
    final fileName =
        'Invoice_${invoiceName}_${DateTime.now().millisecondsSinceEpoch}.pdf'
            .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final filePath = '${tempDir.path}/$fileName';

    await _cleanUpOldInvoicePdfFiles(tempDir, invoiceName);

    final file = File(filePath);
    await file.writeAsBytes(successfulResponse.bodyBytes);

    return await file.exists() ? filePath : null;
  }

  static Future<void> _cleanUpOldInvoicePdfFiles(
    Directory tempDir,
    String invoiceName,
  ) async {
    try {
      final files = await tempDir.list().toList();
      final pattern = RegExp(
        'Invoice_${invoiceName}_\\d+\\.pdf'.replaceAll(
          RegExp(r'[^a-zA-Z0-9_.-]'),
          '_',
        ),
      );

      for (final file in files) {
        if (file is File && pattern.hasMatch(file.path)) {
          await file.delete();
        }
      }
    } catch (e) {
      _log('Error cleaning up old Invoice PDF files: $e', level: 'WARN');
    }
  }

  static Future<String?> _generateQuotationPdf(
    BuildContext context,
    String odooUrl,
    int saleOrderId,
    String quotationName,
    List<String> reportNames,
  ) async {
    http.Response? successfulResponse;
    bool isLocalEnvironment = _isLocalEnvironment(odooUrl);
    Duration timeoutDuration = isLocalEnvironment
        ? _localTimeout
        : _requestTimeout;

    for (final reportName in reportNames) {
      for (int attempt = 1; attempt <= _maxRetryAttempts; attempt++) {
        try {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final pdfUrl =
              '$odooUrl/report/pdf/$reportName/$saleOrderId?t=$timestamp';

          final response = await _makeRequestWithRetry(
            context,
            () => OdooSessionManager.makeAuthenticatedRequest(pdfUrl),
            reportName: reportName,
            timeout: timeoutDuration,
          );

          if (response.statusCode == 200 && _isPdfContent(response.bodyBytes)) {
            successfulResponse = response;
            break;
          }
        } catch (e) {
          if (attempt == _maxRetryAttempts) continue;
          await Future.delayed(Duration(seconds: 2 * attempt));
        }
      }
      if (successfulResponse != null) break;
    }

    if (successfulResponse == null) return null;

    final tempDir = await getTemporaryDirectory();
    final fileName =
        'Quotation_${quotationName}_${DateTime.now().millisecondsSinceEpoch}.pdf'
            .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final filePath = '${tempDir.path}/$fileName';

    await _cleanUpOldQuotationPdfFiles(tempDir, quotationName);

    final file = File(filePath);
    await file.writeAsBytes(successfulResponse.bodyBytes);

    return await file.exists() ? filePath : null;
  }

  static Future<void> _cleanUpOldQuotationPdfFiles(
    Directory tempDir,
    String quotationName,
  ) async {
    try {
      final files = await tempDir.list().toList();
      final pattern = RegExp(
        'Quotation_${quotationName}_\\d+\\.pdf'.replaceAll(
          RegExp(r'[^a-zA-Z0-9_.-]'),
          '_',
        ),
      );

      for (final file in files) {
        if (file is File && pattern.hasMatch(file.path)) {
          await file.delete();
        }
      }
    } catch (e) {
      _log('Error cleaning up old Quotation PDF files: $e', level: 'WARN');
    }
  }

  static Future<void> sendQuotationViaWhatsApp(
    BuildContext context,
    Quote quotation,
  ) async {
    const methodName = 'sendQuotationViaWhatsApp';
    _log('Starting quotation sharing via WhatsApp', method: methodName);

    final odooSession = await OdooSessionManager.getCurrentSession();
    final String odooUrl = odooSession?.serverUrl ?? '';
    final int? saleOrderId = quotation.id;
    final String quotationName = quotation.name;

    const reportNames = ['sale.report_saleorder_raw', 'sale.report_saleorder'];

    if (odooUrl.isEmpty || saleOrderId == null) {
      _log(
        'Invalid parameters: missing URL or sale order ID',
        method: methodName,
        level: 'ERROR',
      );
      if (context.mounted) {
        _showErrorSnackBar(
          context,
          'Unable to send quotation: Missing required information',
        );
      }
      return;
    }

    try {
      final filePath = await _generateQuotationPdf(
        context,
        odooUrl,
        saleOrderId,
        quotationName,
        reportNames,
      );

      if (filePath == null) {
        throw Exception('Failed to generate PDF');
      }

      final xFile = XFile(filePath);
      final message =
          'Here is your quotation $quotationName. Please review and let us know if you have any questions.';

      await _sharePdfWithFallback(context, xFile, message);
    } catch (e, stackTrace) {
      _log(
        'Unexpected error: ${e.toString()}',
        method: methodName,
        level: 'ERROR',
      );
      _log('StackTrace: $stackTrace', method: methodName, level: 'ERROR');
      if (context.mounted) {
        _showErrorSnackBar(context, _getUserFriendlyError(e));
      }
    }
  }

  static Future<void> generateAndSavePdf(
    BuildContext context,
    Quote quotation, {
    VoidCallback? onBeforeOpen,
  }) async {
    const methodName = 'generateAndSavePdf';
    _log('Starting PDF generation', method: methodName);

    final odooSession = await OdooSessionManager.getCurrentSession();
    final String odooUrl = odooSession?.serverUrl ?? '';
    final int? saleOrderId = quotation.id;
    final String quotationName = quotation.name;

    const reportNames = ['sale.report_saleorder_raw', 'sale.report_saleorder'];

    if (odooUrl.isEmpty || saleOrderId == null) {
      _log('Invalid parameters', method: methodName, level: 'ERROR');
      if (context.mounted) {
        _showErrorSnackBar(
          context,
          'Unable to generate PDF: Missing required information',
        );
      }
      return;
    }

    try {
      http.Response? successfulResponse;
      Exception? lastError;
      bool isLocalEnvironment = _isLocalEnvironment(odooUrl);
      Duration timeoutDuration = isLocalEnvironment
          ? _localTimeout
          : _requestTimeout;

      _log(
        'Detected ${isLocalEnvironment ? 'local' : 'remote'} environment, using ${timeoutDuration.inMinutes}min timeout',
        method: methodName,
      );

      for (final reportName in reportNames) {
        for (int attempt = 1; attempt <= _maxRetryAttempts; attempt++) {
          try {
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final pdfUrl =
                '$odooUrl/report/pdf/$reportName/$saleOrderId?t=$timestamp';
            _log(
              'Attempt $attempt: Trying report $reportName at $pdfUrl',
              method: methodName,
            );

            final response = await _makeRequestWithRetry(
              context,
              () => OdooSessionManager.makeAuthenticatedRequest(pdfUrl),
              reportName: reportName,
              timeout: timeoutDuration,
            );

            if (response.statusCode == 200 &&
                _isPdfContent(response.bodyBytes)) {
              successfulResponse = response;
              _log(
                'Successfully generated PDF with report $reportName',
                method: methodName,
              );
              break;
            } else if (response.statusCode != 200) {
              _log(
                'Report $reportName returned status ${response.statusCode}',
                method: methodName,
                level: 'WARN',
              );
              lastError = Exception(
                'Report $reportName failed with status ${response.statusCode}',
              );
            }
          } on TimeoutException {
            _log(
              'Request timed out on attempt $attempt for report $reportName after ${timeoutDuration.inMinutes} minutes',
              method: methodName,
              level: 'WARN',
            );
            lastError = TimeoutException(
              'PDF generation is taking longer than expected',
              timeoutDuration,
            );
            if (attempt < _maxRetryAttempts) {
              _log('Waiting before retry...', method: methodName);
              await Future.delayed(Duration(seconds: 3 * attempt));
            }
          } catch (e) {
            _log(
              'Error with report $reportName (attempt $attempt): $e',
              method: methodName,
              level: 'WARN',
            );
            lastError = e is Exception ? e : Exception(e.toString());
            if (attempt < _maxRetryAttempts) {
              await Future.delayed(Duration(seconds: 2 * attempt));
            }
          }
        }
        if (successfulResponse != null) break;
      }

      if (successfulResponse == null) {
        _log(
          'All PDF generation attempts failed',
          method: methodName,
          level: 'ERROR',
        );
        throw lastError ??
            Exception(
              'PDF generation failed after multiple attempts. Please check your connection and try again.',
            );
      }

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'Order_${quotationName}_${DateTime.now().millisecondsSinceEpoch}.pdf'
              .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
      final filePath = '${tempDir.path}/$fileName';

      await _cleanUpOldPdfFiles(tempDir, quotationName);

      final file = File(filePath);
      await file.writeAsBytes(successfulResponse.bodyBytes);

      if (!await file.exists()) {
        throw Exception('PDF was generated but failed to save to device');
      }

      _log('PDF saved successfully: $filePath', method: methodName);

      if (onBeforeOpen != null) {
        onBeforeOpen();
      }

      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done && context.mounted) {
        _showErrorSnackBar(
          context,
          'PDF generated successfully but unable to open: ${result.message}',
        );
      } else if (context.mounted) {
        _showSuccessSnackBar(context, 'PDF generated and opened successfully');
      }
    } on TimeoutException {
      _log('PDF generation timed out', method: methodName, level: 'ERROR');
      if (context.mounted) {
        _showErrorSnackBar(
          context,
          'PDF generation is taking longer than expected. Please try again in a moment.',
        );
      }
    } on SocketException catch (e) {
      _log('Network error: $e', method: methodName, level: 'ERROR');
      if (context.mounted) {
        _showErrorSnackBar(
          context,
          'Network connection issue. Please check your internet connection and try again.',
        );
      }
    } catch (e, stackTrace) {
      _log(
        'Unexpected error: ${e.toString()}',
        method: methodName,
        level: 'ERROR',
      );
      _log('StackTrace: $stackTrace', method: methodName, level: 'ERROR');
      if (context.mounted) {
        _showErrorSnackBar(context, _getUserFriendlyError(e));
      }
    }
  }

  static Future<void> generatePdfQuote(
    BuildContext context,
    Quote quotation, {
    VoidCallback? onBeforeOpen,
  }) async {
    const methodName = 'generatePdfQuote';
    _log('Starting PDF Quote generation', method: methodName);

    final odooSession = await OdooSessionManager.getCurrentSession();
    final String odooUrl = odooSession?.serverUrl ?? '';
    final int? saleOrderId = quotation.id;
    final String quotationName = quotation.name;

    if (odooUrl.isEmpty || saleOrderId == null) {
      _log('Invalid parameters', method: methodName, level: 'ERROR');
      if (context.mounted) {
        _showErrorSnackBar(
          context,
          'Unable to generate PDF: Missing required information',
        );
      }
      return;
    }

    try {
      bool isLocalEnvironment = _isLocalEnvironment(odooUrl);
      Duration timeoutDuration = isLocalEnvironment
          ? _localTimeout
          : _requestTimeout;

      _log(
        'Detected ${isLocalEnvironment ? 'local' : 'remote'} environment, using ${timeoutDuration.inMinutes}min timeout',
        method: methodName,
      );

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      const reportNames = ['sale.report_quotation', 'sale.report_saleorder'];

      http.Response? successfulResponse;
      Exception? lastError;

      for (final reportName in reportNames) {
        for (int attempt = 1; attempt <= _maxRetryAttempts; attempt++) {
          try {
            final pdfUrl =
                '$odooUrl/report/pdf/$reportName/$saleOrderId?t=$timestamp';
            _log(
              'Attempt $attempt: Trying report $reportName at $pdfUrl',
              method: methodName,
            );

            final response = await _makeRequestWithRetry(
              context,
              () => OdooSessionManager.makeAuthenticatedRequest(pdfUrl),
              reportName: reportName,
              timeout: timeoutDuration,
            );

            if (response.statusCode == 200 &&
                _isPdfContent(response.bodyBytes)) {
              successfulResponse = response;
              _log(
                'Successfully generated PDF quote with report $reportName',
                method: methodName,
              );
              break;
            } else if (response.statusCode != 200) {
              _log(
                'Report $reportName returned status ${response.statusCode}',
                method: methodName,
                level: 'WARN',
              );
              lastError = Exception(
                'Report $reportName failed with status ${response.statusCode}',
              );
            }
          } on TimeoutException {
            _log(
              'Request timed out on attempt $attempt for report $reportName after ${timeoutDuration.inMinutes} minutes',
              method: methodName,
              level: 'WARN',
            );
            lastError = TimeoutException(
              'PDF generation is taking longer than expected',
              timeoutDuration,
            );
            if (attempt < _maxRetryAttempts) {
              _log('Waiting before retry...', method: methodName);
              await Future.delayed(Duration(seconds: 3 * attempt));
            }
          } catch (e) {
            _log(
              'Error with report $reportName (attempt $attempt): $e',
              method: methodName,
              level: 'WARN',
            );
            lastError = e is Exception ? e : Exception(e.toString());
            if (attempt < _maxRetryAttempts) {
              await Future.delayed(Duration(seconds: 2 * attempt));
            }
          }
        }
        if (successfulResponse != null) break;
      }

      if (successfulResponse == null) {
        _log(
          'All PDF quote generation attempts failed',
          method: methodName,
          level: 'ERROR',
        );
        throw lastError ??
            Exception(
              'PDF generation failed after multiple attempts. Please check your connection and try again.',
            );
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = 'Quote_${quotationName}_$timestamp.pdf'.replaceAll(
        RegExp(r'[^a-zA-Z0-9_.-]'),
        '_',
      );
      final filePath = '${tempDir.path}/$fileName';

      await _cleanUpOldPdfFiles(tempDir, quotationName);

      final file = File(filePath);
      await file.writeAsBytes(successfulResponse.bodyBytes);

      if (!await file.exists()) {
        throw Exception('PDF was generated but failed to save to device');
      }

      _log('PDF quote saved successfully: $filePath', method: methodName);

      if (onBeforeOpen != null) {
        onBeforeOpen();
      }

      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done && context.mounted) {
        _showErrorSnackBar(
          context,
          'PDF generated successfully but unable to open: ${result.message}',
        );
      } else if (context.mounted) {
        _showSuccessSnackBar(
          context,
          'PDF quote generated and opened successfully',
        );
      }
    } on TimeoutException {
      _log(
        'PDF quote generation timed out',
        method: methodName,
        level: 'ERROR',
      );
      if (context.mounted) {
        _showErrorSnackBar(
          context,
          'PDF generation is taking longer than expected. Please try again in a moment.',
        );
      }
    } on SocketException catch (e) {
      _log('Network error: $e', method: methodName, level: 'ERROR');
      if (context.mounted) {
        _showErrorSnackBar(
          context,
          'Network connection issue. Please check your internet connection and try again.',
        );
      }
    } catch (e, stackTrace) {
      _log(
        'Unexpected error: ${e.toString()}',
        method: methodName,
        level: 'ERROR',
      );
      _log('StackTrace: $stackTrace', method: methodName, level: 'ERROR');
      if (context.mounted) {
        _showErrorSnackBar(context, _getUserFriendlyError(e));
      }
    }
  }

  static Future<String?> generatePdfForSharing(
    BuildContext context,
    Quote quotation,
  ) async {
    const methodName = 'generatePdfForSharing';
    _log('Starting PDF generation for sharing', method: methodName);

    final odooSession = await OdooSessionManager.getCurrentSession();
    final String odooUrl = odooSession?.serverUrl ?? '';
    final int? saleOrderId = quotation.id;
    final String quotationName = quotation.name;

    const reportNames = ['sale.report_saleorder_raw', 'sale.report_saleorder'];

    if (odooUrl.isEmpty || saleOrderId == null) {
      _log('Invalid parameters', method: methodName, level: 'ERROR');
      return null;
    }

    try {
      bool isLocalEnvironment = _isLocalEnvironment(odooUrl);
      Duration timeoutDuration = isLocalEnvironment
          ? _localTimeout
          : _requestTimeout;

      _log(
        'Detected ${isLocalEnvironment ? 'local' : 'remote'} environment for sharing, using ${timeoutDuration.inMinutes}min timeout',
        method: methodName,
      );

      http.Response? successfulResponse;

      for (final reportName in reportNames) {
        for (int attempt = 1; attempt <= _maxRetryAttempts; attempt++) {
          try {
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final pdfUrl =
                '$odooUrl/report/pdf/$reportName/$saleOrderId?t=$timestamp';
            _log(
              'Attempt $attempt: Trying report $reportName at $pdfUrl',
              method: methodName,
            );

            final response = await _makeRequestWithRetry(
              context,
              () => OdooSessionManager.makeAuthenticatedRequest(pdfUrl),
              reportName: reportName,
              timeout: timeoutDuration,
            );

            if (response.statusCode == 200 &&
                _isPdfContent(response.bodyBytes)) {
              successfulResponse = response;
              _log(
                'Successfully generated PDF for sharing with report $reportName',
                method: methodName,
              );
              break;
            } else if (response.statusCode != 200) {
              _log(
                'Report $reportName returned status ${response.statusCode}',
                method: methodName,
                level: 'WARN',
              );
            }
          } on TimeoutException {
            _log(
              'Request timed out on attempt $attempt for report $reportName after ${timeoutDuration.inMinutes} minutes',
              method: methodName,
              level: 'WARN',
            );
            if (attempt < _maxRetryAttempts) {
              await Future.delayed(Duration(seconds: 3 * attempt));
            }
          } catch (e) {
            _log(
              'Error with report $reportName (attempt $attempt): $e',
              method: methodName,
              level: 'WARN',
            );
            if (attempt < _maxRetryAttempts) {
              await Future.delayed(Duration(seconds: 2 * attempt));
            }
          }
        }
        if (successfulResponse != null) break;
      }

      if (successfulResponse == null) {
        _log(
          'All report attempts failed for sharing: ${reportNames.join(', ')}',
          method: methodName,
          level: 'ERROR',
        );
        return null;
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = 'Order_${quotationName.replaceAll('/', '_')}.pdf';
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);
      _log('Writing PDF to $filePath', method: methodName);
      await file.writeAsBytes(successfulResponse.bodyBytes);

      if (await file.exists()) {
        _log(
          'PDF file saved successfully for sharing: $filePath',
          method: methodName,
        );
        return filePath;
      } else {
        _log(
          'Failed to save PDF file for sharing: $filePath',
          method: methodName,
          level: 'ERROR',
        );
        return null;
      }
    } catch (e, stackTrace) {
      _log(
        'Error generating PDF for sharing: ${e.toString()}',
        method: methodName,
        level: 'ERROR',
      );
      _log('StackTrace: $stackTrace', method: methodName, level: 'ERROR');
      return null;
    }
  }

  static bool _isLocalEnvironment(String odooUrl) {
    return odooUrl.contains('localhost') ||
        odooUrl.contains('127.0.0.1') ||
        odooUrl.contains('192.168.') ||
        odooUrl.contains('10.') ||
        odooUrl.contains('172.') ||
        odooUrl.contains(':808') ||
        odooUrl.contains(':8069') ||
        odooUrl.contains(':8080') ||
        odooUrl.contains(':3000') ||
        odooUrl.toLowerCase().contains('local');
  }

  static Future<http.Response> _makeRequestWithRetry(
    BuildContext context,
    Future<http.Response> Function() requestFn, {
    required String reportName,
    Duration? timeout,
  }) async {
    const methodName = '_makeRequestWithRetry';
    final Duration requestTimeout = timeout ?? _requestTimeout;

    try {
      _log(
        'Making request with ${requestTimeout.inMinutes}min timeout',
        method: methodName,
      );

      final response = await requestFn().timeout(
        requestTimeout,
        onTimeout: () {
          _log(
            'Request timed out after ${requestTimeout.inMinutes} minutes',
            method: methodName,
            level: 'ERROR',
          );
          throw TimeoutException(
            'PDF generation timed out after ${requestTimeout.inMinutes} minutes. This may be due to server processing time.',
            requestTimeout,
          );
        },
      );

      return response;
    } on TimeoutException {
      _log(
        'Request timeout for $reportName after ${requestTimeout.inMinutes} minutes',
        method: methodName,
        level: 'ERROR',
      );
      rethrow;
    } catch (e) {
      _log(
        'Request failed for $reportName: $e',
        method: methodName,
        level: 'ERROR',
      );
      rethrow;
    }
  }

  static String _getUserFriendlyError(dynamic error) {
    if (error is TimeoutException) {
      return 'PDF generation is taking longer than expected. This is common with Odoo 18 local instances due to increased processing requirements. Please wait and try again.';
    } else if (error.toString().contains('All report attempts failed') ||
        error.toString().contains('PDF generation failed')) {
      return 'Unable to generate the PDF. This may be due to Odoo 18 compatibility issues. Please ensure your server is running properly and try again.';
    } else if (error is SocketException) {
      return 'Network connection issue. Please check your internet connection and ensure the Odoo server is accessible.';
    } else if (error.toString().contains('failed to save')) {
      return 'PDF was generated but could not be saved to your device. Please check available storage space.';
    } else if (error.toString().contains('status 500') ||
        error.toString().contains('Internal Server Error')) {
      return 'Server error occurred during PDF generation. This may be related to Odoo 18 report processing. Please try again or contact your system administrator.';
    }
    return 'An unexpected error occurred while generating the PDF. If using Odoo 18, this may be due to compatibility issues. Please try again or contact support.';
  }

  static void _showErrorSnackBar(BuildContext context, String message) {
    _log('Showing error SnackBar: $message', method: '_showSnackBar');
    CustomSnackbar.showError(context, message);
  }

  static void _showSuccessSnackBar(BuildContext context, String message) {
    _log('Showing success SnackBar: $message', method: '_showSnackBar');
    CustomSnackbar.showSuccess(context, message);
  }

  static Future<void> _cleanUpOldPdfFiles(
    Directory tempDir,
    String quotationName,
  ) async {
    try {
      final files = await tempDir.list().toList();
      final pattern = RegExp(
        'Order_${quotationName}_\\d+\\.pdf'.replaceAll(
          RegExp(r'[^a-zA-Z0-9_.-]'),
          '_',
        ),
      );

      for (final file in files) {
        if (file is File && pattern.hasMatch(file.path)) {
          await file.delete();
        }
      }
    } catch (e) {
      _log('Error cleaning up old PDF files: $e', level: 'WARN');
    }
  }

  static String _safeString(dynamic value) {
    final result = value?.toString() ?? '';
    _log(
      'SafeString conversion: input=$value, output=$result',
      method: '_safeString',
    );
    return result;
  }

  static bool _isPdfContent(List<int> bytes) {
    if (bytes.length < 4) return false;

    if (bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return true;
    }

    final contentStart = String.fromCharCodes(bytes.take(20));
    if (contentStart.contains('<html') || contentStart.contains('<!DOCTYPE')) {
      _log('Received HTML instead of PDF: $contentStart', level: 'ERROR');
      return false;
    }

    return false;
  }
}
