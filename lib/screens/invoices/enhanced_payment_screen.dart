import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:shimmer/shimmer.dart';
import '../../models/invoice.dart';
import '../../models/payment.dart';
import '../../services/payment_service.dart';
import '../../services/odoo_session_manager.dart';
import '../../widgets/custom_date_picker.dart';
import '../../widgets/custom_dropdown.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/enhanced_payment_status_badge.dart';
import '../../widgets/custom_snackbar.dart';
import '../../utils/date_picker_utils.dart';

class EnhancedPaymentScreen extends StatefulWidget {
  final Invoice invoice;
  final List<Payment>? existingPayments;

  const EnhancedPaymentScreen({
    super.key,
    required this.invoice,
    this.existingPayments,
  });

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
  List<Payment> _existingPayments = [];
  bool _isLoadingExistingPayments = true;

  static final Map<int, List<Payment>> _paymentCache = {};
  static final Map<int, DateTime> _cacheTimestamps = {};
  static const Duration _cacheValidDuration = Duration(minutes: 2);

  static void clearAllPaymentCaches() {
    _paymentCache.clear();
    _cacheTimestamps.clear();
  }

  static void clearPaymentCache(int invoiceId) {
    _paymentCache.remove(invoiceId);
    _cacheTimestamps.remove(invoiceId);
  }

  static void clearAllPaymentCache() {
    _paymentCache.clear();
    _cacheTimestamps.clear();
  }

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

    if (widget.existingPayments != null) {
      _existingPayments = widget.existingPayments!;
      _isLoadingExistingPayments = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadExistingPayments();
      });
    }

    _detectOdooEdition();
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

  Future<void> _loadExistingPayments() async {
    if (widget.invoice.id == null) {
      if (mounted) {
        setState(() {
          _isLoadingExistingPayments = false;
        });
      }
      return;
    }

    final invoiceId = widget.invoice.id!;

    try {
      final cachedPayments = _paymentCache[invoiceId];
      final cacheTime = _cacheTimestamps[invoiceId];

      if (cachedPayments != null &&
          cacheTime != null &&
          DateTime.now().difference(cacheTime) < _cacheValidDuration) {
        if (mounted) {
          setState(() {
            _existingPayments = cachedPayments;
            _isLoadingExistingPayments = false;
          });
        }
        return;
      }

      final payments = await _getBasicInvoicePayments(invoiceId);

      _paymentCache[invoiceId] = payments;
      _cacheTimestamps[invoiceId] = DateTime.now();

      if (mounted) {
        setState(() {
          _existingPayments = payments;
          _isLoadingExistingPayments = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingExistingPayments = false;
        });
      }
    }
  }

  Future<List<Payment>> _getBasicInvoicePayments(int invoiceId) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        return [];
      }

      final invoiceResult = await client
          .callKw({
            'model': 'account.move',
            'method': 'search_read',
            'args': [
              [
                ['id', '=', invoiceId],
              ],
              ['partner_id', 'name'],
            ],
            'kwargs': {},
          })
          .timeout(const Duration(seconds: 10));

      if (invoiceResult.isEmpty) {
        return [];
      }

      final partnerId = invoiceResult[0]['partner_id'] is List
          ? invoiceResult[0]['partner_id'][0]
          : invoiceResult[0]['partner_id'];
      final invoiceName = invoiceResult[0]['name'] ?? '';

      if (partnerId == null) {
        return [];
      }

      final paymentResults = await client
          .callKw({
            'model': 'account.payment',
            'method': 'search_read',
            'args': [
              [
                ['partner_id', '=', partnerId],
                [
                  'state',
                  'in',
                  ['posted', 'sent', 'reconciled'],
                ],
                ['payment_type', '=', 'inbound'],
              ],
              [
                'id',
                'name',
                'amount',
                'state',
                'date',
                'payment_method_line_id',
                'journal_id',
                'is_reconciled',
                'create_date',
              ],
            ],
            'kwargs': {'order': 'create_date desc', 'limit': 10},
          })
          .timeout(const Duration(seconds: 10));

      List<Payment> payments = [];
      final now = DateTime.now();

      for (var paymentData in paymentResults) {
        try {
          final createDate = paymentData['create_date'] != null
              ? DateTime.parse(paymentData['create_date'])
              : now;

          final daysDiff = now.difference(createDate).inDays;
          final paymentName = paymentData['name']?.toString() ?? '';

          if (daysDiff <= 30 ||
              paymentName.contains(invoiceName) ||
              paymentName.contains(invoiceId.toString())) {
            paymentData['reconciliation_lines'] = [];
            paymentData['reconciliation_status'] =
                paymentData['is_reconciled'] == true ? 'complete' : 'pending';
            paymentData['requires_manual_reconciliation'] =
                paymentData['state'] == 'posted' &&
                paymentData['is_reconciled'] != true;
            paymentData['reconciled_amount'] =
                paymentData['is_reconciled'] == true
                ? paymentData['amount']
                : 0.0;

            final payment = Payment.fromJson(paymentData);
            payments.add(payment);
          }
        } catch (e) {}
      }

      return payments;
    } catch (e) {
      return [];
    }
  }

  void _checkPaymentDifference() {
    final paymentAmount = double.tryParse(_amountController.text) ?? 0.0;
    final remainingBalance = widget.invoice.amountResidual;
    final difference = paymentAmount - remainingBalance;

    setState(() {
      if (paymentAmount > 0 && difference.abs() > 0.01) {
        _differenceAmount = difference.abs();
        _showPaymentDifference = true;

        _isOverpayment = difference > 0;
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

    final confirmed = await _showPaymentConfirmationDialog(
      context: context,
      paymentAmount: paymentAmount,
      paymentMethod: _paymentMethod == 'bank' ? 'Bank Transfer' : 'Cash',
      invoice: widget.invoice,
      showDifference: _showPaymentDifference,
      differenceAmount: _differenceAmount,
      isOverpayment: _isOverpayment,
    );

    if (!confirmed) return;

    setState(() => _isLoading = true);

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
        memo: _memoController.text.isNotEmpty
            ? _memoController.text
            : 'Payment for ${widget.invoice.name}',
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

        if (mounted && !_isDisposed) {
          HapticFeedback.lightImpact();

          if (result.success) {
            if (widget.invoice.id != null) {
              _paymentCache.remove(widget.invoice.id!);
              _cacheTimestamps.remove(widget.invoice.id!);
            }

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
                Navigator.pop(context, {'success': true, 'forceRefresh': true});
              }
            } else {
              _showErrorSnackBar(result.errorMessage ?? 'Payment failed');
            }
          }
        }
      } catch (paymentError) {
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
      if (mounted && !_isDisposed) {
        setState(() => _isLoading = false);
      }
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
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
      ),
      body: _isLoading
          ? _buildLoadingScreen()
          : FadeTransition(
              opacity: _fadeAnimation,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInvoiceInfoCard(isDark),
                      const SizedBox(height: 20),

                      if (_isLoadingExistingPayments) ...[
                        _buildExistingPaymentsShimmer(isDark),
                        const SizedBox(height: 20),
                      ] else if (_existingPayments.isNotEmpty) ...[
                        _buildExistingPaymentsCard(isDark),
                        const SizedBox(height: 20),
                      ],

                      _buildPaymentDetailsCard(isDark),
                      const SizedBox(height: 20),

                      if (_showPaymentDifference)
                        _buildPaymentDifferenceCard(isDark),

                      const SizedBox(height: 30),

                      SizedBox(
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
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildLoadingScreen() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Recording payment...'),
        ],
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
              ),
            ],
          ),
          const SizedBox(height: 16),
          PaymentStatusCard(invoice: widget.invoice),
        ],
      ),
    );
  }

  Widget _buildExistingPaymentsShimmer(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  HugeIcons.strokeRoundedPayment01,
                  color: Colors.green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Existing Payments',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _buildPaymentItemShimmer(isDark),
        ],
      ),
    );
  }

  Widget _buildPaymentItemShimmer(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Shimmer.fromColors(
        baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
        highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 100,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 60,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExistingPaymentsCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  HugeIcons.strokeRoundedPayment01,
                  color: Colors.green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Existing Payments',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._existingPayments.map(
            (payment) => _buildPaymentItem(payment, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentItem(Payment payment, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            payment.isInPayment
                ? HugeIcons.strokeRoundedLoading03
                : HugeIcons.strokeRoundedCheckmarkCircle02,
            color: payment.isInPayment ? Colors.blue : Colors.green,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  payment.statusDisplay,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Text(
            payment.amount.toStringAsFixed(2),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentDetailsCard(bool isDark) {
    List<DropdownMenuItem<String>> paymentItems = [
      DropdownMenuItem(
        value: 'bank',
        child: Row(
          children: [
            Icon(
              HugeIcons.strokeRoundedCreditCard,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              size: 20,
            ),
            const SizedBox(width: 8),
            const Text('Bank Transfer'),
          ],
        ),
      ),
      DropdownMenuItem(
        value: 'cash',
        child: Row(
          children: [
            Icon(
              HugeIcons.strokeRoundedMoney01,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              size: 20,
            ),
            const SizedBox(width: 8),
            const Text('Cash'),
          ],
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

          CustomDropdownField(
            showBorder: false,
            value: _paymentMethod,
            labelText: 'Payment Method',
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
            items: paymentItems,
            isDark: false,
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
            '${_isOverpayment ? "Excess" : "Shortage"}: \$${_differenceAmount.toStringAsFixed(2)}',
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
                            '\$${paymentAmount.toStringAsFixed(2)}',
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
                                          '${isOverpayment ? "Excess" : "Shortage"}: \$${differenceAmount.toStringAsFixed(2)}',
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

                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.grey[600]!
                                      : Colors.grey[300]!,
                                ),
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[700],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            child: Text(
                              'Confirm',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
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
