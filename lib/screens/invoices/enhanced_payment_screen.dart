import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:hugeicons/hugeicons.dart';
import '../../models/invoice.dart';
import '../../providers/currency_provider.dart';
import '../../services/payment_service.dart';
import '../../services/odoo_error_handler.dart';
import '../../services/odoo_session_manager.dart';
import 'invoice_payments_sheet.dart';
import '../../widgets/custom_date_picker.dart';
import '../../shared/widgets/mobo/mobo_bottom_action_bar.dart';
import '../../shared/widgets/mobo/mobo_dialog_buttons.dart';
import '../../shared/widgets/mobo/mobo_select_form_field.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/enhanced_payment_status_badge.dart';
import '../../widgets/custom_snackbar.dart';
import '../../widgets/loading_dialog.dart';
import '../../utils/date_picker_utils.dart';
import '../../utils/invoice_payment_rules.dart';

class EnhancedPaymentScreen extends StatefulWidget {
  final Invoice invoice;

  const EnhancedPaymentScreen({super.key, required this.invoice});

  @override
  State<EnhancedPaymentScreen> createState() => _EnhancedPaymentScreenState();
}

class _EnhancedPaymentScreenState extends State<EnhancedPaymentScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();
  final _writeoffLabelController = TextEditingController();

  DateTime _paymentDate = DateTime.now();
  String _paymentMethod = 'bank';
  String _paymentDifferenceHandling = 'open';
  int? _writeoffAccountId;
  bool _isEnterpriseEdition = false;

  bool _isLoading = false;
  bool _showPaymentDifference = false;
  double _differenceAmount = 0.0;
  bool _isOverpayment = false;

  /// What Odoo's own Pay wizard proposes for this invoice: the amount, the
  /// memo, its alerts ("There are payments in progress...") and, as the
  /// amount changes, the payment difference. Null until it has loaded.
  PaymentPreview? _preview;

  /// Why the preview could not be loaded (in Odoo's words when Odoo refused).
  String? _previewError;
  Future<void>? _previewLoad;

  Timer? _differenceDebounce;
  int _differenceRequest = 0;

  Future<void> _detectOdooEdition() async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return;

      final moduleResults = await client
          .callKw({
            'model': 'ir.module.module',
            'method': 'search_count',
            'args': [
              [
                '|',
                ['name', '=', 'account_enterprise'],
                '|',
                ['name', '=', 'enterprise_theme'],
                '|',
                ['name', '=', 'web_enterprise'],
                ['name', '=', 'account_payment_writeoff'],
              ],
            ],
            'kwargs': {},
          })
          .timeout(const Duration(seconds: 5));

      bool hasWriteoffFields = false;
      try {
        final fieldResults = await client
            .callKw({
              'model': 'account.payment.register',
              'method': 'fields_get',
              'args': [
                ['writeoff_account_id', 'writeoff_label'],
              ],
              'kwargs': {},
            })
            .timeout(const Duration(seconds: 5));

        hasWriteoffFields =
            fieldResults is Map &&
            fieldResults.containsKey('writeoff_account_id') &&
            fieldResults.containsKey('writeoff_label');
      } catch (e) {}

      if (mounted) {
        setState(() {
          _isEnterpriseEdition = false;
        });

        (
          'Odoo Edition detected: ${_isEnterpriseEdition ? "Enterprise" : "Community"}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isEnterpriseEdition = false;
        });
      }
    }
  }

  Future<int> _getDefaultWriteoffAccount() async {
    final client = await OdooSessionManager.getClient();
    if (client == null) {
      throw Exception('No active Odoo session');
    }

    try {
      final accountResults = await client
          .callKw({
            'model': 'account.account',
            'method': 'search_read',
            'args': [
              [
                '|',
                ['code', 'ilike', 'writeoff'],
                '|',
                ['code', 'ilike', 'write-off'],
                '|',
                ['name', 'ilike', 'writeoff'],
                '|',
                ['name', 'ilike', 'write-off'],
                '|',
                ['name', 'ilike', 'payment difference'],
                ['account_type', '=', 'expense'],
              ],
              ['id', 'name', 'code'],
            ],
            'kwargs': {'limit': 1},
          })
          .timeout(const Duration(seconds: 10));

      if (accountResults.isNotEmpty) {
        final accountId = accountResults[0]['id'] as int;

        return accountId;
      }

      final expenseResults = await client
          .callKw({
            'model': 'account.account',
            'method': 'search_read',
            'args': [
              [
                ['account_type', '=', 'expense'],
              ],
              ['id', 'name', 'code'],
            ],
            'kwargs': {'limit': 1},
          })
          .timeout(const Duration(seconds: 10));

      if (expenseResults.isNotEmpty) {
        final accountId = expenseResults[0]['id'] as int;

        return accountId;
      }

      throw Exception('No suitable write-off account found');
    } catch (e) {
      rethrow;
    }
  }

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _setupAnimations();

    _previewLoad = _loadPreview();

    _detectOdooEdition();
    _loadCurrencyDecimals();
  }

  /// Decimal places of the invoice's currency (3 for KWD, 0 for JPY...), which
  /// decide what counts as a difference and how amounts are shown.
  int _currencyDecimals = 2;

  Future<void> _loadCurrencyDecimals() async {
    final currency = widget.invoice.currencyId;
    final id = currency != null && currency.isNotEmpty && currency.first is int
        ? currency.first as int
        : null;
    final decimals = await PaymentService.currencyDecimals(id);
    if (!mounted || decimals == _currencyDecimals) return;
    final untouched =
        _amountController.text ==
        widget.invoice.amountResidual.toStringAsFixed(_currencyDecimals);
    setState(() => _currencyDecimals = decimals);
    if (untouched) {
      _amountController.text = widget.invoice.amountResidual.toStringAsFixed(
        decimals,
      );
    }
  }

  /// [amount] in the invoice's own currency.
  String _money(double amount) {
    final currency = widget.invoice.currencyId;
    final code = currency != null && currency.length > 1
        ? currency[1].toString()
        : '';
    var symbol = code;
    try {
      symbol = context.read<CurrencyProvider>().getCurrencySymbol(code);
    } catch (_) {}
    final gap = symbol.length > 1 ? ' ' : '';
    return '$symbol$gap${amount.toStringAsFixed(_currencyDecimals)}';
  }

  void _initializeControllers() {
    _amountController.text = widget.invoice.amountResidual.toStringAsFixed(2);
    _memoController.text = widget.invoice.name;
    _writeoffLabelController.text = 'Payment Difference';
    _amountController.addListener(_checkPaymentDifference);
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposed) {
        _animationController.forward();
      }
    });
  }

  /// Opens Odoo's Pay wizard for this invoice without paying, as Odoo's Pay
  /// button does, and takes what Odoo proposes: the amount (Odoo does not
  /// take payments in progress off it, it warns about them instead), the
  /// memo, and the alerts. Fields the user already changed are left alone.
  Future<void> _loadPreview() async {
    final invoiceId = widget.invoice.id;
    if (invoiceId == null) return;
    if (mounted && !_isDisposed) setState(() => _previewError = null);

    final amountBefore = _amountController.text;
    final memoBefore = _memoController.text;
    try {
      final preview = await PaymentService.previewPayment(invoiceId);
      if (!mounted || _isDisposed) return;
      final decimals = await PaymentService.currencyDecimals(
        _invoiceCurrencyId,
      );
      if (!mounted || _isDisposed) return;
      setState(() {
        _preview = preview;
        _currencyDecimals = decimals;
      });
      // Untouched: as it was, or still the amount due in other formatting
      // (the currency's decimals may have arrived in the meantime).
      final typed = double.tryParse(_amountController.text);
      final amountUntouched =
          _amountController.text == amountBefore ||
          (typed != null &&
              !isPaymentDifference(
                typed - widget.invoice.amountResidual,
                decimals,
              ));
      if (preview.amount != null && amountUntouched) {
        _amountController.text = preview.amount!.toStringAsFixed(decimals);
      }
      if (preview.memo != null &&
          preview.memo!.trim().isNotEmpty &&
          (_memoController.text == memoBefore ||
              _memoController.text == widget.invoice.name)) {
        _memoController.text = preview.memo!;
      }
      await _refreshDifference();
    } catch (e) {
      if (!mounted || _isDisposed) return;
      setState(() {
        _preview = null;
        _previewError = OdooErrorHandler.toUserMessage(e);
      });
    }
  }

  int? get _invoiceCurrencyId {
    final currency = widget.invoice.currencyId;
    return currency != null && currency.isNotEmpty && currency.first is int
        ? currency.first as int
        : null;
  }

  /// Called on every change of the amount: shows the difference at once
  /// from what is known, then asks Odoo for its own figure.
  void _checkPaymentDifference() {
    final paymentAmount = double.tryParse(_amountController.text) ?? 0.0;
    // Until Odoo answers: the amount due less the amount, as Odoo computes
    // it when there are no installments or early payment discount.
    _applyDifference(
      paymentAmount,
      widget.invoice.amountResidual - paymentAmount,
    );

    _differenceDebounce?.cancel();
    if (_preview == null) return;
    _differenceDebounce = Timer(const Duration(milliseconds: 400), () {
      _refreshDifference();
    });
  }

  /// Asks Odoo's wizard for the payment difference of the current amount.
  Future<void> _refreshDifference() async {
    final preview = _preview;
    if (preview == null) return;
    final paymentAmount = double.tryParse(_amountController.text) ?? 0.0;
    if (paymentAmount <= 0) return;
    final request = ++_differenceRequest;
    try {
      final difference = await PaymentService.previewDifference(
        preview,
        paymentAmount,
      );
      if (!mounted || _isDisposed || request != _differenceRequest) return;
      if (difference != null) _applyDifference(paymentAmount, difference);
    } catch (_) {
      // The figure shown so far stays; the payment itself is checked by Odoo
      // when it is recorded.
    }
  }

  /// [difference] as Odoo states it: still to pay when positive, paid too
  /// much when negative.
  void _applyDifference(double paymentAmount, double difference) {
    if (!mounted || _isDisposed) return;
    setState(() {
      if (paymentAmount > 0 &&
          isPaymentDifference(difference, _currencyDecimals)) {
        _differenceAmount = difference.abs();
        _showPaymentDifference = true;
        _isOverpayment = difference < 0;
      } else {
        _showPaymentDifference = false;
        _paymentDifferenceHandling = 'open';
        _writeoffAccountId = null;
        _isOverpayment = false;
      }

      if (_paymentDifferenceHandling == 'reconcile' && !_isEnterpriseEdition) {
        _paymentDifferenceHandling = 'open';
        _writeoffAccountId = null;
      }
    });
  }

  Future<void> _selectDate() async {
    final date = await DatePickerUtils.showStandardDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date != null && mounted) {
      setState(() => _paymentDate = date);
    }
  }

  Future<void> _recordQuickPayment() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.invoice.id == null) return;

    final paymentAmount = double.tryParse(_amountController.text) ?? 0.0;
    if (paymentAmount <= 0) {
      _showErrorSnackBar('Please enter a valid payment amount');
      return;
    }

    // Odoo's alerts (payments in progress) and its difference for this
    // amount have to be on screen before the payment is confirmed.
    await _previewLoad;
    _differenceDebounce?.cancel();
    await _refreshDifference();
    if (!mounted || _isDisposed) return;

    final confirmed = await _showPaymentConfirmationDialog(
      context: context,
      paymentAmount: paymentAmount,
      paymentMethod: _paymentMethod == 'bank' ? 'Bank Transfer' : 'Cash',
      invoice: widget.invoice,
      showDifference: _showPaymentDifference,
      differenceAmount: _differenceAmount,
      isOverpayment: _isOverpayment,
    );

    if (!confirmed || !mounted || _isDisposed) return;

    if (_isLoading) return;
    _isLoading = true;

    // The app's one loading popup — the same card Confirm, Reset and Delete
    // show. It is pushed on the root navigator, so it has to be closed before
    // this screen pops: a `Navigator.pop` taken with the dialog still up would
    // close the dialog and leave the user on the payment form.
    final loading = LoadingDialog.open(
      context,
      message: 'Recording payment...',
      subtitle: 'Please wait while we record your payment.',
    );

    try {
      if (_paymentDifferenceHandling == 'reconcile') {
        if (!_isEnterpriseEdition) {
          _showErrorSnackBar(
            'Write-off functionality is only available in Odoo Enterprise Edition. Please choose "Keep Open" instead.',
          );
          return;
        }

        if (_writeoffAccountId == null) {
          try {
            _writeoffAccountId = await _getDefaultWriteoffAccount();
          } catch (e) {
            _showErrorSnackBar(
              'Write-off requires an account. Please choose "Keep Open" instead or contact your administrator.',
            );
            return;
          }
        }
      }

      final paymentMethod = PaymentMethodData(
        id: _paymentMethod == 'bank' ? 1 : 2,
        name: _paymentMethod == 'bank' ? 'Bank Transfer' : 'Cash',
        type: _paymentMethod,
      );

      final options = PaymentOptions(
        // Empty stays empty: Odoo then fills in its own memo.
        memo: _memoController.text.trim(),
        differenceHandling: _paymentDifferenceHandling == 'reconcile'
            ? PaymentDifferenceHandling.writeOff
            : PaymentDifferenceHandling.keepOpen,
        writeOffConfig:
            _paymentDifferenceHandling == 'reconcile' &&
                _writeoffAccountId != null
            ? WriteOffConfig(
                accountId: _writeoffAccountId!,
                label: _writeoffLabelController.text,
              )
            : null,
      );

      try {
        final result = await PaymentService.createPaymentWithOdooFlow(
          invoiceId: widget.invoice.id!,
          amount: paymentAmount,
          paymentMethod: paymentMethod,
          paymentDate: _paymentDate,

          options: options,
        );

        // Before any `Navigator.pop` below.
        loading.close();

        if (mounted && !_isDisposed) {
          HapticFeedback.lightImpact();

          if (result.success) {
            if (mounted && !_isDisposed) {
              Navigator.pop(context, {
                'success': true,
                'forceRefresh': true,
                'updatedInvoice': result.updatedInvoice,
              });
            }
          } else {
            if (result.warnings.contains('timeout_but_processing')) {
              _showWarningSnackBar(
                'Payment is being processed. Please check the invoice status in a moment.',
              );

              if (mounted && !_isDisposed) {
                // Not "success": the payment may not have gone through, so the
                // invoice page must reload and report what it finds, not
                // announce a recorded payment. The warning above is not a
                // route, so it stays up over the page this pops back to.
                Navigator.pop(context, {
                  'success': false,
                  'forceRefresh': true,
                  'processing': true,
                });
              }
            } else {
              _showErrorSnackBar(result.errorMessage ?? 'Payment failed');
            }
          }
        }
      } catch (paymentError) {
        loading.close();
        if (mounted && !_isDisposed) {
          String errorMessage;
          if (paymentError is PaymentError) {
            errorMessage = paymentError.message;
          } else {
            errorMessage =
                'Failed to record payment: ${paymentError.toString()}';
          }

          try {
            _showErrorSnackBar(errorMessage);
          } catch (e) {}
        }
      }
    } catch (e) {
      loading.close();
      if (mounted && !_isDisposed) {
        String errorMessage;
        if (e is PaymentError) {
          errorMessage = e.message;
        } else {
          errorMessage = 'Failed to record payment: ${e.toString()}';
        }

        try {
          _showErrorSnackBar(errorMessage);
        } catch (snackBarError) {}
      }
    } finally {
      // Idempotent: whichever path got here, the popup is gone.
      loading.close();
      _isLoading = false;
    }
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted || _isDisposed) {
      return;
    }
    _showSafeSnackBar(message, backgroundColor: Colors.green);
  }

  void _showWarningSnackBar(String message) {
    if (!mounted || _isDisposed) {
      return;
    }
    _showSafeSnackBar(message, backgroundColor: Colors.orange);
  }

  void _showErrorSnackBar(String message) {
    if (!mounted || _isDisposed) {
      return;
    }
    _showSafeSnackBar(message, backgroundColor: Colors.red);
  }

  void _showSafeSnackBar(String message, {Color? backgroundColor}) {
    if (!mounted || _isDisposed) {
      return;
    }

    try {
      if (!mounted || _isDisposed) {
        return;
      }

      final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
      if (scaffoldMessenger == null) {
        return;
      }

      if (backgroundColor == Colors.red) {
        CustomSnackbar.showError(context, message);
      } else if (backgroundColor == Colors.green) {
        CustomSnackbar.showSuccess(context, message);
      } else if (backgroundColor == Colors.orange) {
        CustomSnackbar.showWarning(context, message);
      } else {
        CustomSnackbar.showInfo(context, message);
      }
    } catch (e) {}
  }

  @override
  void dispose() {
    _isDisposed = true;
    _differenceDebounce?.cancel();
    _amountController.removeListener(_checkPaymentDifference);
    _amountController.dispose();
    _memoController.dispose();
    _writeoffLabelController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: isDark
            ? const Color(0xFF121212)
            : const Color(0xFFF8F9FA),
        foregroundColor: isDark ? Colors.white : theme.primaryColor,
        elevation: 0,
        title: Text(
          'Record Payment',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
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
      body: SafeArea(
        top: false,
        left: false,
        right: false,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final alert
                      in _preview?.alerts ?? const <PaymentAlert>[]) ...[
                    _buildOdooAlert(alert, isDark),
                    const SizedBox(height: 16),
                  ],
                  if (_previewError != null) ...[
                    _buildPreviewFailed(isDark),
                    const SizedBox(height: 16),
                  ],
                  _buildInvoiceInfoCard(isDark),
                  const SizedBox(height: 20),

                  _buildPaymentDetailsCard(isDark),
                  const SizedBox(height: 20),

                  if (_showPaymentDifference)
                    _buildPaymentDifferenceCard(isDark),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: MoboBottomActionBar(
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _recordQuickPayment,
            icon: const Icon(HugeIcons.strokeRoundedPayment02),
            label: Text(
              'Record Payment',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInvoiceInfoCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black26
                : Color(0xff000000).withOpacity(0.05),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Invoice Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              EnhancedPaymentStatusBadge(
                invoice: widget.invoice,
                showIcon: true,
                showReconciliationIndicator: false,
              ),
            ],
          ),
          const SizedBox(height: 16),
          PaymentStatusCard(invoice: widget.invoice),
        ],
      ),
    );
  }

  /// One of Odoo's Pay wizard alerts, in Odoo's words and level. The
  /// payments-in-progress alert keeps Odoo's "Check them" link, which lists
  /// those payments.
  Widget _buildOdooAlert(PaymentAlert alert, bool isDark) {
    final MaterialColor color = switch (alert.level) {
      'danger' => Colors.red,
      'info' => Colors.blue,
      _ => Colors.orange,
    };
    final invoiceId = widget.invoice.id;
    return _buildNotice(
      isDark: isDark,
      color: color,
      message: alert.message,
      actionLabel: alert.isPaymentsInProgress && invoiceId != null
          ? (alert.actionText ?? 'Check them')
          : null,
      onAction: () => showInvoicePaymentsSheet(
        context,
        invoiceId: invoiceId!,
        inProgressOnly: true,
      ),
    );
  }

  /// Shown when Odoo's Pay wizard could not be opened: either Odoo refused
  /// (its reason is shown) or it could not be reached. Its alerts, such as
  /// payments in progress, are then unknown, and the notice says so.
  Widget _buildPreviewFailed(bool isDark) {
    return _buildNotice(
      isDark: isDark,
      color: Colors.orange,
      message: _previewError ?? 'Could not load the payment details.',
      detail:
          "Odoo's checks for this invoice, such as payments already in "
          "progress, could not be shown.",
      actionLabel: 'Retry',
      onAction: () => setState(() => _previewLoad = _loadPreview()),
    );
  }

  /// The app's notice style (as on the quotation and delivery pages): a
  /// tinted box with an icon, a short message and an optional link.
  Widget _buildNotice({
    required bool isDark,
    required MaterialColor color,
    required String message,
    String? detail,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final textColor = isDark ? color[200] : color[900];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.1) : color[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? color[200]!.withValues(alpha: 0.3) : color[200]!,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(HugeIcons.strokeRoundedAlert02, color: color[700], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    detail,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: onAction,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        actionLabel,
                        style: TextStyle(
                          color: isDark ? color[200] : color[800],
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                          decorationColor: isDark ? color[200] : color[800],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentDetailsCard(bool isDark) {
    final paymentItems = <MoboOption<String>>[
      MoboOption<String>(
        value: 'bank',
        label: 'Bank Transfer',
        leading: Icon(
          HugeIcons.strokeRoundedCreditCard,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
          size: 20,
        ),
      ),
      MoboOption<String>(
        value: 'cash',
        label: 'Cash',
        leading: Icon(
          HugeIcons.strokeRoundedMoney01,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
          size: 20,
        ),
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black26
                : Color(0xff000000).withOpacity(0.05),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Payment Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 20),

          CustomTextField(
            showBorder: false,
            controller: _amountController,
            labelText: 'Payment Amount',
            isRequired: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter an amount';
              }
              final amount = double.tryParse(value);
              if (amount == null || amount <= 0) {
                return 'Please enter a valid amount';
              }
              return null;
            },
            isDark: false,
          ),
          const SizedBox(height: 16),

          MoboSelectFormField<String>(
            value: _paymentMethod,
            label: 'Payment Method',
            isRequired: true,
            onChanged: (value) {
              if (value != null) {
                setState(() => _paymentMethod = value);
              }
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please select a payment method';
              }
              return null;
            },
            options: paymentItems,
          ),
          const SizedBox(height: 16),

          CustomDateSelector(
            onTap: _selectDate,
            selectedDate: _paymentDate,
            labelText: 'Payment Date',
            isDark: false,
            showBorder: false,
          ),
          const SizedBox(height: 16),

          CustomTextField(
            controller: _memoController,
            labelText: 'Memo (Optional)',
            showBorder: false,
            isDark: false,
            validator: (String? p1) {
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentDifferenceCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),

        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black26
                : Color(0xff000000).withOpacity(0.05),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isOverpayment ? 'Overpayment' : 'Underpayment',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_isOverpayment ? "Excess" : "Shortage"}: ${_money(_differenceAmount)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: _isOverpayment ? Colors.green : Colors.orange,
            ),
          ),
          if (_isOverpayment)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Payment amount exceeds invoice balance',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
          const SizedBox(height: 8),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioListTile<String>(
                title: Text(
                  'Keep Open',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                subtitle: Text(
                  _isOverpayment
                      ? 'Keep excess as customer credit for future invoices'
                      : 'Leave the remaining balance as unpaid',
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                value: 'open',
                groupValue: _paymentDifferenceHandling,
                activeColor: Colors.orange,
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _paymentDifferenceHandling = value;
                      _writeoffAccountId = null;
                    });
                  }
                },
              ),

              if (_isEnterpriseEdition)
                RadioListTile<String>(
                  title: Text(
                    'Write Off',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    'Write off the difference amount (uses default account)',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  value: 'reconcile',
                  groupValue: _paymentDifferenceHandling,
                  activeColor: Colors.orange,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _paymentDifferenceHandling = value);
                    }
                  },
                ),

              if (!_isEnterpriseEdition && _showPaymentDifference)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.blue.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isOverpayment
                                ? 'Excess amount will be kept as customer credit'
                                : 'Only "Keep Open" option available in Community Edition',
                            style: TextStyle(color: Colors.blue, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          if (_paymentDifferenceHandling == 'reconcile' &&
              _isEnterpriseEdition) ...[
            const SizedBox(height: 16),
            CustomTextField(
              controller: _writeoffLabelController,
              labelText: 'Write-off Label',
              validator: (String? p1) {
                return null;
              },
              isDark: false,
              showBorder: false,
            ),
          ],
        ],
      ),
    );
  }

  Future<bool> _showPaymentConfirmationDialog({
    required BuildContext context,
    required double paymentAmount,
    required String paymentMethod,
    required Invoice invoice,
    required bool showDifference,
    required double differenceAmount,
    required bool isOverpayment,
  }) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 16,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Confirm Payment',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Text(
                      'Please review the payment details below',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.grey[900]?.withOpacity(0.3)
                            : Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            'Invoice',
                            invoice.name,
                            HugeIcons.strokeRoundedInvoice,
                            isDark,
                          ),
                          const SizedBox(height: 12),

                          _buildDetailRow(
                            'Payment Amount',
                            _money(paymentAmount),
                            HugeIcons.strokeRoundedDollar01,
                            isDark,
                            valueColor: theme.primaryColor,
                            isBold: true,
                          ),
                          const SizedBox(height: 12),

                          _buildDetailRow(
                            'Payment Method',
                            paymentMethod,
                            paymentMethod == 'Bank Transfer'
                                ? HugeIcons.strokeRoundedBank
                                : HugeIcons.strokeRoundedCash01,
                            isDark,
                          ),

                          if (showDifference) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    (isOverpayment
                                            ? Colors.green
                                            : Colors.orange)
                                        .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      (isOverpayment
                                              ? Colors.green
                                              : Colors.orange)
                                          .withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isOverpayment
                                        ? HugeIcons.strokeRoundedArrowUp01
                                        : HugeIcons.strokeRoundedArrowDown01,
                                    size: 16,
                                    color: isOverpayment
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isOverpayment
                                              ? 'Overpayment'
                                              : 'Underpayment',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isOverpayment
                                                ? Colors.green
                                                : Colors.orange,
                                          ),
                                        ),
                                        Text(
                                          '${isOverpayment ? "Excess" : "Shortage"}: ${_money(differenceAmount)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? Colors.grey[400]
                                                : Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    MoboDialogButtons(
                      secondaryLabel: 'Cancel',
                      onSecondary: () => Navigator.of(context).pop(false),
                      primaryLabel: 'Confirm',
                      onPrimary: () => Navigator.of(context).pop(true),
                    ),
                  ],
                ),
              ),
            );
          },
        ) ??
        false;
  }

  Widget _buildDetailRow(
    String label,
    String value,
    IconData icon,
    bool isDark, {
    Color? valueColor,
    bool isBold = false,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.w500,
            color: valueColor ?? (isDark ? Colors.white : Colors.black87),
          ),
        ),
      ],
    );
  }
}
