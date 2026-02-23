import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/permission_service.dart';
import '../services/odoo_error_handler.dart';
import '../services/invoice_details_service.dart';
import '../models/invoice.dart';

class InvoiceDetailsProvider extends ChangeNotifier {
  Invoice? _invoice;
  bool _isLoading = false;
  bool _isProcessing = false;
  String _errorMessage = '';
  late NumberFormat currencyFormat;

  final InvoiceDetailsService _invoiceDetailsService;
  final PermissionService _permissionService;

  InvoiceDetailsProvider({
    InvoiceDetailsService? invoiceDetailsService,
    PermissionService? permissionService,
  }) : _invoiceDetailsService =
           invoiceDetailsService ?? InvoiceDetailsService(),
       _permissionService = permissionService ?? PermissionService.instance {
    currencyFormat = NumberFormat.currency(locale: 'en_US', decimalDigits: 2);
  }

  Future<void> clearData() async {
    _invoice = null;
    _isLoading = false;
    _errorMessage = '';
    notifyListeners();
  }

  void resetState() => clearData();

  Invoice? get invoice => _invoice;
  Map<String, dynamic> get invoiceData => _invoice?.toJson() ?? {};
  bool get isLoading => _isLoading;
  bool get isProcessing => _isProcessing;
  String get errorMessage => _errorMessage;

  String get invoiceNumber => _invoice?.name ?? 'Draft';

  DateTime? get invoiceDate => _invoice?.invoiceDate;

  DateTime? get dueDate => _invoice?.dueDate;

  String get invoiceState => _invoice?.status ?? 'draft';
  String get paymentState => _invoice?.paymentState ?? 'not_paid';
  double get invoiceAmount => _invoice?.total ?? 0.0;
  double get amountResidual => _invoice?.amountResidual ?? invoiceAmount;
  bool get isFullyPaid => _invoice?.isFullyPaid ?? false;

  List<Map<String, dynamic>> get invoiceLines =>
      _invoice?.lines.map((l) => l.toJson()).toList() ?? [];

  String get customerName => _invoice?.customerName ?? 'Unknown Customer';

  String get customerReference => _invoice?.reference ?? '';

  String get paymentTerms => _invoice?.paymentTerm ?? '';

  String get salesperson => _invoice?.salesperson ?? '';

  String get currency {
    if (_invoice?.currencyId != null && _invoice!.currencyId!.length > 1) {
      return _invoice!.currencyId![1].toString();
    }
    return 'USD';
  }

  String get invoiceOrigin => _invoice?.origin ?? '';

  double get amountUntaxed => _invoice?.subtotal ?? 0.0;
  double get amountTax => _invoice?.taxAmount ?? 0.0;

  void setInvoiceData(Map<String, dynamic> data) {
    _invoice = Invoice.fromJson(data);

    String currencyCode = 'USD';
    String locale = 'en_US';

    if (_invoice?.currencyId != null && _invoice!.currencyId!.length > 1) {
      currencyCode = _invoice!.currencyId![1].toString();
      locale = _getLocaleForCurrency(currencyCode);
    }

    currencyFormat = NumberFormat.currency(
      locale: locale,
      symbol: '',
      decimalDigits: 2,
    );

    notifyListeners();
  }

  String _getLocaleForCurrency(String currencyCode) {
    final Map<String, String> currencyToLocale = {
      'USD': 'en_US',
      'EUR': 'de_DE',
      'GBP': 'en_GB',
      'INR': 'en_IN',
      'JPY': 'ja_JP',
      'CNY': 'zh_CN',
      'AUD': 'en_AU',
      'CAD': 'en_CA',
      'CHF': 'de_CH',
      'SGD': 'en_SG',
      'AED': 'ar_AE',
      'SAR': 'ar_SA',
      'QAR': 'ar_QA',
      'KWD': 'ar_KW',
      'BHD': 'ar_BH',
      'OMR': 'ar_OM',
      'MYR': 'ms_MY',
      'THB': 'th_TH',
      'IDR': 'id_ID',
      'PHP': 'fil_PH',
      'VND': 'vi_VN',
      'KRW': 'ko_KR',
      'TWD': 'zh_TW',
      'HKD': 'zh_HK',
      'NZD': 'en_NZ',
      'ZAR': 'en_ZA',
      'BRL': 'pt_BR',
      'MXN': 'es_MX',
      'ARS': 'es_AR',
      'CLP': 'es_CL',
      'COP': 'es_CO',
      'PEN': 'es_PE',
      'UYU': 'es_UY',
      'TRY': 'tr_TR',
      'ILS': 'he_IL',
      'EGP': 'ar_EG',
      'PKR': 'ur_PK',
      'BDT': 'bn_BD',
      'LKR': 'si_LK',
      'NPR': 'ne_NP',
      'MMK': 'my_MM',
      'KHR': 'km_KH',
      'LAK': 'lo_LA',
    };
    return currencyToLocale[currencyCode] ?? 'en_US';
  }

  String formatInvoiceState(String state, bool isFullyPaid) {
    if (isFullyPaid) return 'Paid';
    switch (state.toLowerCase()) {
      case 'draft':
        return 'Draft';
      case 'posted':
        return 'Posted';
      case 'cancel':
        return 'Cancelled';
      default:
        return state;
    }
  }

  Color getInvoiceStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return Colors.green[700]!;
      case 'posted':
        return Colors.orange[700]!;
      case 'draft':
        return Colors.blue[700]!;
      case 'cancelled':
        return Colors.red[700]!;
      default:
        return Colors.grey[700]!;
    }
  }

  Future<void> fetchInvoiceDetails(
    BuildContext context,
    String invoiceId,
  ) async {
    if (invoiceId.isEmpty) {
      _errorMessage = 'Invalid invoice ID';
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = '';
    _invoice = null;
    notifyListeners();

    try {
      int parsedInvoiceId = int.parse(invoiceId);
      if (parsedInvoiceId <= 0) {
        throw FormatException('Invoice ID must be a positive integer');
      }

      final invoiceData = await _invoiceDetailsService.fetchInvoiceDetails(
        parsedInvoiceId,
      );

      if (invoiceData.isNotEmpty) {
        final partnerId = invoiceData['partner_id'] is List
            ? invoiceData['partner_id'][0]
            : null;
        if (partnerId != null) {
          try {
            final partnerData = await _invoiceDetailsService
                .fetchPartnerDetails(partnerId);
            if (partnerData.isNotEmpty) {
              invoiceData['partner_email'] =
                  partnerData['email']?.toString() ?? '';
              invoiceData['partner_phone'] =
                  partnerData['phone']?.toString() ?? '';

              final addressParts = [
                partnerData['street']?.toString() ?? '',
                partnerData['city']?.toString() ?? '',
                partnerData['zip']?.toString() ?? '',
                partnerData['country_id'] is List &&
                        partnerData['country_id'].length > 1
                    ? partnerData['country_id'][1].toString()
                    : '',
              ].where((part) => part.isNotEmpty && part != 'false').toList();

              invoiceData['partner_address'] = addressParts.isNotEmpty
                  ? addressParts.join(', ')
                  : '-';
            }
          } catch (e) {}
        }

        final lineIds = List<int>.from(invoiceData['invoice_line_ids'] ?? []);
        if (lineIds.isNotEmpty) {
          try {
            final lines = await _invoiceDetailsService.fetchInvoiceLines(
              lineIds,
            );

            for (var line in lines) {
              if (line['product_id'] is List && line['product_id'].isNotEmpty) {
                try {
                  final productId = line['product_id'][0];
                  final productData = await _invoiceDetailsService
                      .fetchProductDetails(productId);
                  if (productData.isNotEmpty) {
                    line['name'] =
                        productData['name'] ?? line['name'] ?? 'Unknown';
                  }
                } catch (e) {}
              }

              if (line['tax_ids'] is List &&
                  (line['tax_ids'] as List).isNotEmpty) {
                try {
                  final taxIds = List<int>.from(line['tax_ids']);
                  final taxData = await _invoiceDetailsService.fetchTaxDetails(
                    taxIds,
                  );
                  if (taxData.isNotEmpty) {
                    line['tax_details'] = taxData;
                  }
                } catch (e) {}
              }
            }
            invoiceData['line_details'] = lines;
          } catch (e) {}
        }

        setInvoiceData(invoiceData);
      } else {
        _errorMessage = 'Invoice with ID $parsedInvoiceId not found';
      }
    } catch (e) {
      _errorMessage = OdooErrorHandler.toUserMessage(e);
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> postInvoice(BuildContext context, String invoiceId) async {
    if (_isProcessing) {
      return false;
    }

    _isProcessing = true;
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      int parsedInvoiceId = int.parse(invoiceId);

      String currentState = invoiceState;
      if (currentState != 'draft') {
        _errorMessage =
            "Cannot confirm invoice: Invoice must be in 'draft' state (current state: $currentState).";
        notifyListeners();
        _isProcessing = false;
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final canWriteMove = await _permissionService.canWrite('account.move');
      if (!canWriteMove) {
        _errorMessage = 'You do not have permission to post invoices.';
        notifyListeners();
        _isProcessing = false;
        _isLoading = false;
        notifyListeners();
        return false;
      }

      await _invoiceDetailsService.postInvoice(parsedInvoiceId);

      await fetchInvoiceDetails(context, invoiceId);
      return true;
    } catch (e) {
      _errorMessage = OdooErrorHandler.toUserMessage(e);
      return false;
    } finally {
      _isProcessing = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> resetToDraft(BuildContext context, String invoiceId) async {
    if (_isProcessing) {
      return false;
    }

    _isProcessing = true;
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      int parsedInvoiceId = int.parse(invoiceId);

      String currentState = invoiceState;
      if (!['cancel', 'posted'].contains(currentState)) {
        _errorMessage =
            "Cannot reset to draft: Invoice must be in 'cancel' or 'posted' state (current state: $currentState).";
        notifyListeners();
        _isProcessing = false;
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (currentState == 'posted') {
        bool cancelled = await cancelInvoice(context, invoiceId);
        if (!cancelled) {
          _errorMessage = 'Failed to cancel invoice before resetting to draft';
          notifyListeners();
          _isProcessing = false;
          _isLoading = false;
          notifyListeners();
          return false;
        }

        currentState = invoiceState;
        if (currentState != 'cancel') {
          _errorMessage =
              "Failed to cancel invoice before resetting to draft (current state: $currentState).";
          notifyListeners();
          _isProcessing = false;
          _isLoading = false;
          notifyListeners();
          return false;
        }
      }

      final canWriteMove = await _permissionService.canWrite('account.move');
      if (!canWriteMove) {
        _errorMessage =
            'You do not have permission to reset invoices to draft.';
        notifyListeners();
        _isProcessing = false;
        _isLoading = false;
        notifyListeners();
        return false;
      }

      await _invoiceDetailsService.resetToDraft(parsedInvoiceId);

      await fetchInvoiceDetails(context, invoiceId);
      return true;
    } catch (e) {
      _errorMessage = OdooErrorHandler.toUserMessage(e);
      return false;
    } finally {
      _isProcessing = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> cancelInvoice(BuildContext context, String invoiceId) async {
    if (_isProcessing) {
      return false;
    }

    _isProcessing = true;
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      int parsedInvoiceId = int.parse(invoiceId);

      String currentState = invoiceState;
      if (!['draft', 'posted'].contains(currentState)) {
        _errorMessage =
            "Cannot cancel invoice: Invoice must be in 'draft' or 'posted' state (current state: $currentState).";
        notifyListeners();
        _isProcessing = false;
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final canWriteMove = await _permissionService.canWrite('account.move');
      if (!canWriteMove) {
        _errorMessage = 'You do not have permission to cancel invoices.';
        notifyListeners();
        _isProcessing = false;
        _isLoading = false;
        notifyListeners();
        return false;
      }

      await _invoiceDetailsService.cancelInvoice(parsedInvoiceId);

      await fetchInvoiceDetails(context, invoiceId);
      return true;
    } catch (e) {
      _errorMessage = OdooErrorHandler.toUserMessage(e);
      return false;
    } finally {
      _isProcessing = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteInvoice(BuildContext context, String invoiceId) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      int parsedInvoiceId = int.parse(invoiceId);

      final canUnlinkMove = await _permissionService.canUnlink('account.move');
      if (!canUnlinkMove) {
        _errorMessage = 'You do not have permission to delete invoices.';
        notifyListeners();
        _isLoading = false;
        notifyListeners();
        return false;
      }

      await _invoiceDetailsService.deleteInvoice(parsedInvoiceId);

      return true;
    } catch (e) {
      _errorMessage = OdooErrorHandler.toUserMessage(e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updateInvoiceData(Map<String, dynamic> updatedData) {
    if (_invoice != null) {
      final json = _invoice!.toJson();
      json.addAll(updatedData);
      _invoice = Invoice.fromJson(json);
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> recordPayment({
    required BuildContext context,
    required int invoiceId,
    required double amount,
    required String paymentMethod,
    required DateTime paymentDate,
    required String paymentDifference,
    int? writeoffAccountId,
    String? writeoffLabel,
  }) async {
    return {};
  }
}
