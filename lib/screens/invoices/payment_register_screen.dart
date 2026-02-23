import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../providers/currency_provider.dart';
import '../../providers/invoice_details_provider_enterprise.dart';
import '../../services/session_service.dart';
import '../../utils/date_picker_utils.dart';
import '../../widgets/custom_snackbar.dart';

class PaymentRegisterScreen extends StatefulWidget {
  final Map<String, dynamic> invoiceData;

  const PaymentRegisterScreen({super.key, required this.invoiceData});

  @override
  State<PaymentRegisterScreen> createState() => _PaymentRegisterScreenState();
}

class _PaymentRegisterScreenState extends State<PaymentRegisterScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();
  final _writeoffLabelController = TextEditingController();

  DateTime _paymentDate = DateTime.now();
  Map<String, dynamic>? _selectedJournal;
  Map<String, dynamic>? _selectedPaymentMethodLine;
  String _paymentDifferenceHandling = 'open';
  Map<String, dynamic>? _selectedWriteoffAccount;

  bool _isLoading = false;
  bool _isLoadingJournals = true;
  bool _isLoadingAccounts = false;
  bool _showPaymentDifference = false;
  double _differenceAmount = 0.0;

  List<Map<String, dynamic>> _journals = [];
  List<Map<String, dynamic>> _paymentMethodLines = [];
  List<Map<String, dynamic>> _writeoffAccounts = [];

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _setupAnimations();
    _loadInitialData();
  }

  void _initializeControllers() {
    final remainingBalance =
        widget.invoiceData['amount_residual'] as double? ?? 0.0;
    _amountController.text = remainingBalance.toStringAsFixed(2);
    _memoController.text = widget.invoiceData['name']?.toString() ?? '';
    _writeoffLabelController.text = 'Payment Difference';
    _amountController.addListener(_checkPaymentDifference);
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animationController.forward();
    });
  }

  Future<void> _loadInitialData() async {
    await Future.wait([_loadJournals(), _loadWriteoffAccounts()]);
  }

  Future<void> _loadJournals() async {
    setState(() => _isLoadingJournals = true);

    try {
      final sessionService = Provider.of<SessionService>(
        context,
        listen: false,
      );
      final client = await sessionService.client;
      if (client == null) throw Exception('No active session');

      final companyId = widget.invoiceData['company_id'] is List
          ? widget.invoiceData['company_id'][0]
          : widget.invoiceData['company_id'] ?? 1;

      final journalsResult = await client
          .callKw({
            'model': 'account.journal',
            'method': 'search_read',
            'args': [
              [
                [
                  'type',
                  'in',
                  ['cash', 'bank'],
                ],
                ['active', '=', true],
                ['company_id', '=', companyId],
              ],
              ['id', 'name', 'type', 'code', 'currency_id', 'company_id'],
            ],
            'kwargs': {
              'order': 'type desc, name asc',
              'context': {
                'company_id': companyId,
                'allowed_company_ids': [companyId],
              },
            },
          })
          .timeout(const Duration(seconds: 15));

      if (mounted) {
        setState(() {
          _journals = List<Map<String, dynamic>>.from(journalsResult);

          if (_journals.isNotEmpty) {
            _selectedJournal = _journals.first;
            _loadPaymentMethodLines();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Failed to load payment journals: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingJournals = false);
      }
    }
  }

  Future<void> _loadPaymentMethodLines() async {
    if (_selectedJournal == null) return;

    try {
      final sessionService = Provider.of<SessionService>(
        context,
        listen: false,
      );
      final client = await sessionService.client;
      if (client == null) return;

      final companyId = widget.invoiceData['company_id'] is List
          ? widget.invoiceData['company_id'][0]
          : widget.invoiceData['company_id'] ?? 1;

      final methodLinesResult = await client
          .callKw({
            'model': 'account.payment.method.line',
            'method': 'search_read',
            'args': [
              [
                ['journal_id', '=', _selectedJournal!['id']],
                ['payment_type', '=', 'inbound'],
              ],
              ['id', 'name', 'payment_method_id', 'payment_type'],
            ],
            'kwargs': {
              'context': {
                'company_id': companyId,
                'allowed_company_ids': [companyId],
              },
            },
          })
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        setState(() {
          _paymentMethodLines = List<Map<String, dynamic>>.from(
            methodLinesResult,
          );

          if (_paymentMethodLines.isNotEmpty) {
            _selectedPaymentMethodLine = _paymentMethodLines.first;
          }
        });
      }
    } catch (e) {}
  }

  Future<void> _loadWriteoffAccounts() async {
    setState(() => _isLoadingAccounts = true);

    try {
      final sessionService = Provider.of<SessionService>(
        context,
        listen: false,
      );
      final client = await sessionService.client;
      if (client == null) return;

      final companyId = widget.invoiceData['company_id'] is List
          ? widget.invoiceData['company_id'][0]
          : widget.invoiceData['company_id'] ?? 1;

      final accountsResult = await client
          .callKw({
            'model': 'account.account',
            'method': 'search_read',
            'args': [
              [
                ['company_id', '=', companyId],
                [
                  'account_type',
                  'in',
                  ['expense', 'asset_current', 'income_other'],
                ],
                ['deprecated', '=', false],
              ],
              ['id', 'name', 'code', 'account_type'],
            ],
            'kwargs': {
              'limit': 50,
              'order': 'code, name',
              'context': {
                'company_id': companyId,
                'allowed_company_ids': [companyId],
              },
            },
          })
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        setState(() {
          _writeoffAccounts = List<Map<String, dynamic>>.from(accountsResult);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingAccounts = false);
      }
    }
  }

  void _checkPaymentDifference() {
    final remainingBalance =
        widget.invoiceData['amount_residual'] as double? ?? 0.0;
    final paymentAmount = double.tryParse(_amountController.text) ?? 0.0;

    setState(() {
      if (paymentAmount > 0 &&
          (paymentAmount - remainingBalance).abs() > 0.01) {
        _differenceAmount = (paymentAmount - remainingBalance).abs();
        _showPaymentDifference = true;
      } else {
        _showPaymentDifference = false;
        _paymentDifferenceHandling = 'open';
        _selectedWriteoffAccount = null;
      }
    });
  }

  Future<void> _selectDate(BuildContext context) async {
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

  Future<void> _registerPayment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedJournal == null || _selectedPaymentMethodLine == null) {
      CustomSnackbar.showError(
        context,
        'Please select a payment journal and method',
      );
      return;
    }

    final paymentAmount = double.tryParse(_amountController.text) ?? 0.0;
    if (paymentAmount <= 0) {
      CustomSnackbar.showError(context, 'Please enter a valid payment amount');
      return;
    }

    if (_paymentDifferenceHandling == 'reconcile' &&
        _selectedWriteoffAccount == null) {
      CustomSnackbar.showError(context, 'Please select a write-off account');
      return;
    }

    final confirmed = await _showConfirmationDialog();
    if (!confirmed) return;

    setState(() => _isLoading = true);

    try {
      final provider = Provider.of<InvoiceDetailsProvider>(
        context,
        listen: false,
      );

      final updatedInvoiceData = await provider.recordPayment(
        context: context,
        invoiceId: widget.invoiceData['id'] as int,
        amount: paymentAmount,
        paymentMethod: _selectedJournal!['type'] == 'cash' ? 'cash' : 'bank',
        paymentDate: _paymentDate,
        paymentDifference: _paymentDifferenceHandling,
        writeoffAccountId: _selectedWriteoffAccount != null
            ? _selectedWriteoffAccount!['id'] as int
            : null,
        writeoffLabel: _paymentDifferenceHandling == 'reconcile'
            ? _writeoffLabelController.text
            : null,
      );

      if (mounted) {
        HapticFeedback.lightImpact();
        Navigator.pop(context, updatedInvoiceData);
      }
    } catch (e) {
      if (mounted) {
        if (e.toString().contains('multi-company') ||
            e.toString().contains('company_ids')) {
          CustomSnackbar.showError(
            context,
            'Enterprise multi-company configuration issue: ${e.toString()}',
          );
        } else {
          CustomSnackbar.showError(
            context,
            'Failed to register payment: ${e.toString()}',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<Map<String, dynamic>> _recordPaymentOdoo18(
    InvoiceDetailsProvider provider,
  ) async {
    final sessionService = Provider.of<SessionService>(context, listen: false);
    final client = await sessionService.client;
    if (client == null) throw Exception('No active session');

    final invoiceId = widget.invoiceData['id'] as int;
    final paymentAmount = double.tryParse(_amountController.text) ?? 0.0;
    final companyId = widget.invoiceData['company_id'] is List
        ? widget.invoiceData['company_id'][0]
        : widget.invoiceData['company_id'] ?? 1;
    final partnerId = widget.invoiceData['partner_id'] is List
        ? widget.invoiceData['partner_id'][0]
        : widget.invoiceData['partner_id'];

    try {
      final wizardData = {
        'amount': paymentAmount,
        'payment_date': DateFormat('yyyy-MM-dd').format(_paymentDate),
        'journal_id': _selectedJournal!['id'],
        'payment_method_line_id': _selectedPaymentMethodLine!['id'],
        'communication': _memoController.text.isNotEmpty
            ? _memoController.text
            : widget.invoiceData['name']?.toString() ?? '',
        'partner_id': partnerId,
        'partner_type': 'customer',
        'payment_type': 'inbound',
        'company_id': companyId,
        'group_payment': false,
        'payment_difference_handling': _paymentDifferenceHandling,
      };

      if (_paymentDifferenceHandling == 'reconcile' &&
          _selectedWriteoffAccount != null) {
        wizardData['writeoff_account_id'] = _selectedWriteoffAccount!['id'];
        wizardData['writeoff_label'] = _writeoffLabelController.text.isNotEmpty
            ? _writeoffLabelController.text
            : 'Payment Difference';
      }

      final wizardId = await client
          .callKw({
            'model': 'account.payment.register',
            'method': 'create',
            'args': [wizardData],
            'kwargs': {
              'context': {
                'active_model': 'account.move',
                'active_ids': [invoiceId],
                'default_payment_type': 'inbound',
                'default_partner_type': 'customer',
                'company_id': companyId,
                'allowed_company_ids': [companyId],
              },
            },
          })
          .timeout(const Duration(seconds: 30));

      final result = await client
          .callKw({
            'model': 'account.payment.register',
            'method': 'action_create_payments',
            'args': [
              [wizardId],
            ],
            'kwargs': {
              'context': {
                'active_model': 'account.move',
                'active_ids': [invoiceId],
                'company_id': companyId,
                'allowed_company_ids': [companyId],
              },
            },
          })
          .timeout(const Duration(seconds: 30));

      await Future.delayed(const Duration(milliseconds: 500));

      await client
          .callKw({
            'model': 'account.move',
            'method': 'invalidate_cache',
            'args': [
              [invoiceId],
            ],
            'kwargs': {},
          })
          .timeout(const Duration(seconds: 10));

      final updatedInvoiceResult = await client
          .callKw({
            'model': 'account.move',
            'method': 'search_read',
            'args': [
              [
                ['id', '=', invoiceId],
              ],
              [
                'amount_residual',
                'amount_total',
                'state',
                'payment_state',
                'amount_residual_signed',
              ],
            ],
            'kwargs': {
              'context': {
                'company_id': companyId,
                'allowed_company_ids': [companyId],
              },
            },
          })
          .timeout(const Duration(seconds: 10));

      if (updatedInvoiceResult.isEmpty) {
        throw Exception('Failed to fetch updated invoice data');
      }

      final updatedInvoice = updatedInvoiceResult[0];
      final newAmountResidual =
          updatedInvoice['amount_residual'] as double? ?? 0.0;
      updatedInvoice['is_fully_paid'] = newAmountResidual <= 0.01;

      return updatedInvoice;
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> _showConfirmationDialog() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final paymentAmount = double.tryParse(_amountController.text) ?? 0.0;
    final currencyProvider = Provider.of<CurrencyProvider>(
      context,
      listen: false,
    );
    final currencyCode = widget.invoiceData['currency_id'] is List
        ? widget.invoiceData['currency_id'][1].toString()
        : null;

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    HugeIcons.strokeRoundedPayment02,
                    color: theme.primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Confirm Payment',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildConfirmationRow(
                  'Amount',
                  currencyProvider.formatAmount(
                    paymentAmount,
                    currency: currencyCode,
                  ),
                ),
                _buildConfirmationRow('Journal', _selectedJournal!['name']),
                _buildConfirmationRow(
                  'Method',
                  _selectedPaymentMethodLine!['name'],
                ),
                _buildConfirmationRow(
                  'Date',
                  DateFormat('MMM dd, yyyy').format(_paymentDate),
                ),
                if (_memoController.text.isNotEmpty)
                  _buildConfirmationRow('Memo', _memoController.text),
                if (_showPaymentDifference) ...[
                  const Divider(height: 24),
                  _buildConfirmationRow(
                    'Difference',
                    currencyProvider.formatAmount(
                      _differenceAmount,
                      currency: currencyCode,
                    ),
                    valueColor: Colors.orange,
                  ),
                  _buildConfirmationRow(
                    'Handling',
                    _paymentDifferenceHandling == 'open'
                        ? 'Keep Open'
                        : 'Write Off',
                  ),
                  if (_paymentDifferenceHandling == 'reconcile' &&
                      _selectedWriteoffAccount != null)
                    _buildConfirmationRow(
                      'Write-off Account',
                      _selectedWriteoffAccount!['name'],
                    ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: theme.primaryColor),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Register Payment'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildConfirmationRow(
    String label,
    String value, {
    Color? valueColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? (isDark ? Colors.white : Colors.black87),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _amountController.removeListener(_checkPaymentDifference);
    _amountController.dispose();
    _memoController.dispose();
    _writeoffLabelController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Widget _buildLoadingShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
      highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
      child: Column(
        children: List.generate(
          6,
          (index) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
    IconData? icon,
    Color? iconColor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (iconColor ?? theme.primaryColor).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      color: iconColor ?? theme.primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ] else ...[
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
            ],
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final remainingBalance =
        widget.invoiceData['amount_residual'] as double? ?? 0.0;

    return Consumer<CurrencyProvider>(
      builder: (context, currencyProvider, _) {
        final currencyCode = widget.invoiceData['currency_id'] is List
            ? widget.invoiceData['currency_id'][1].toString()
            : null;

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
              'Register Payment',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : theme.primaryColor,
              ),
            ),
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(HugeIcons.strokeRoundedArrowLeft01),
            ),
          ),
          body: _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: theme.primaryColor),
                      const SizedBox(height: 16),
                      Text(
                        'Registering payment...',
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionCard(
                              title: 'Invoice Information',
                              icon: HugeIcons.strokeRoundedInvoice03,
                              iconColor: Colors.blue,
                              children: [
                                _buildInfoRow(
                                  'Invoice',
                                  widget.invoiceData['name'] ?? 'Draft',
                                ),
                                _buildInfoRow(
                                  'Outstanding Amount',
                                  currencyProvider.formatAmount(
                                    remainingBalance,
                                    currency: currencyCode,
                                  ),
                                ),
                                _buildInfoRow(
                                  'Customer',
                                  widget.invoiceData['partner_id'] is List
                                      ? widget.invoiceData['partner_id'][1]
                                            .toString()
                                      : 'Unknown',
                                ),
                              ],
                            ),

                            _buildSectionCard(
                              title: 'Payment Details',
                              icon: HugeIcons.strokeRoundedPayment02,
                              iconColor: Colors.green,
                              children: [
                                TextFormField(
                                  controller: _amountController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Payment Amount',
                                    prefixText:
                                        '${currencyProvider.getCurrencySymbol(currencyCode ?? 'USD')} ',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: isDark
                                        ? const Color(0xFF2A2A2A)
                                        : Colors.grey[50],
                                  ),
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
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
                                ),
                                const SizedBox(height: 16),

                                if (_isLoadingJournals)
                                  Container(
                                    height: 56,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.grey[300]!,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      color: isDark
                                          ? const Color(0xFF2A2A2A)
                                          : Colors.grey[50],
                                    ),
                                    child: const Center(
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Text('Loading journals...'),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  SizedBox(
                                    width: double.infinity,
                                    child: DropdownButtonFormField<Map<String, dynamic>>(
                                      initialValue: _selectedJournal,
                                      decoration: InputDecoration(
                                        labelText: 'Payment Journal',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        filled: true,
                                        fillColor: isDark
                                            ? const Color(0xFF2A2A2A)
                                            : Colors.grey[50],
                                      ),
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                      dropdownColor: isDark
                                          ? const Color(0xFF2A2A2A)
                                          : Colors.white,
                                      isExpanded: true,
                                      items: _journals.map((journal) {
                                        return DropdownMenuItem<
                                          Map<String, dynamic>
                                        >(
                                          value: journal,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                journal['type'] == 'cash'
                                                    ? HugeIcons
                                                          .strokeRoundedCash01
                                                    : HugeIcons
                                                          .strokeRoundedCreditCard,
                                                size: 16,
                                                color: isDark
                                                    ? Colors.grey[400]
                                                    : Colors.grey[600],
                                              ),
                                              const SizedBox(width: 8),
                                              Flexible(
                                                child: Text(
                                                  '${journal['name']} (${journal['code'] ?? ''})',
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedJournal = value;
                                          _selectedPaymentMethodLine = null;
                                        });
                                        if (value != null) {
                                          _loadPaymentMethodLines();
                                        }
                                      },
                                      validator: (value) {
                                        if (value == null) {
                                          return 'Please select a payment journal';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                const SizedBox(height: 16),

                                if (_selectedJournal != null)
                                  SizedBox(
                                    width: double.infinity,
                                    child:
                                        DropdownButtonFormField<
                                          Map<String, dynamic>
                                        >(
                                          initialValue:
                                              _selectedPaymentMethodLine,
                                          decoration: InputDecoration(
                                            labelText: 'Payment Method',
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            filled: true,
                                            fillColor: isDark
                                                ? const Color(0xFF2A2A2A)
                                                : Colors.grey[50],
                                          ),
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                          dropdownColor: isDark
                                              ? const Color(0xFF2A2A2A)
                                              : Colors.white,
                                          isExpanded: true,
                                          items: _paymentMethodLines.map((
                                            method,
                                          ) {
                                            return DropdownMenuItem<
                                              Map<String, dynamic>
                                            >(
                                              value: method,
                                              child: Text(
                                                method['name'],
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (value) {
                                            setState(
                                              () => _selectedPaymentMethodLine =
                                                  value,
                                            );
                                          },
                                          validator: (value) {
                                            if (value == null) {
                                              return 'Please select a payment method';
                                            }
                                            return null;
                                          },
                                        ),
                                  ),
                                const SizedBox(height: 16),

                                InkWell(
                                  onTap: () => _selectDate(context),
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: 'Payment Date',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      filled: true,
                                      fillColor: isDark
                                          ? const Color(0xFF2A2A2A)
                                          : Colors.grey[50],
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          DateFormat(
                                            'MMM dd, yyyy',
                                          ).format(_paymentDate),
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                        ),
                                        Icon(
                                          HugeIcons.strokeRoundedCalendar01,
                                          color: theme.primaryColor,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                TextFormField(
                                  controller: _memoController,
                                  decoration: InputDecoration(
                                    labelText: 'Memo (Optional)',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: isDark
                                        ? const Color(0xFF2A2A2A)
                                        : Colors.grey[50],
                                  ),
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ],
                            ),

                            if (_showPaymentDifference)
                              _buildSectionCard(
                                title: 'Payment Difference',
                                icon: HugeIcons.strokeRoundedCalculate,
                                iconColor: Colors.orange,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.orange.withOpacity(0.3),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          HugeIcons.strokeRoundedAlert02,
                                          color: Colors.orange,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Payment Difference Detected',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.orange[800],
                                                ),
                                              ),
                                              Text(
                                                'Difference: ${currencyProvider.formatAmount(_differenceAmount, currency: currencyCode)}',
                                                style: TextStyle(
                                                  color: Colors.orange[700],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  RadioListTile<String>(
                                    title: const Text('Keep Open'),
                                    subtitle: const Text(
                                      'Keep the invoice open with remaining balance',
                                    ),
                                    value: 'open',
                                    groupValue: _paymentDifferenceHandling,
                                    activeColor: theme.primaryColor,
                                    onChanged: (value) {
                                      setState(() {
                                        _paymentDifferenceHandling = value!;
                                        _selectedWriteoffAccount = null;
                                      });
                                    },
                                  ),
                                  RadioListTile<String>(
                                    title: const Text('Write Off'),
                                    subtitle: const Text(
                                      'Write off the difference to an account',
                                    ),
                                    value: 'reconcile',
                                    groupValue: _paymentDifferenceHandling,
                                    activeColor: theme.primaryColor,
                                    onChanged: (value) {
                                      setState(
                                        () =>
                                            _paymentDifferenceHandling = value!,
                                      );
                                    },
                                  ),

                                  if (_paymentDifferenceHandling ==
                                      'reconcile') ...[
                                    const SizedBox(height: 16),
                                    if (_isLoadingAccounts)
                                      Container(
                                        height: 56,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.grey[300]!,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          color: isDark
                                              ? const Color(0xFF2A2A2A)
                                              : Colors.grey[50],
                                        ),
                                        child: const Center(
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                              SizedBox(width: 8),
                                              Text('Loading accounts...'),
                                            ],
                                          ),
                                        ),
                                      )
                                    else
                                      SizedBox(
                                        width: double.infinity,
                                        child:
                                            DropdownButtonFormField<
                                              Map<String, dynamic>
                                            >(
                                              initialValue:
                                                  _selectedWriteoffAccount,
                                              decoration: InputDecoration(
                                                labelText: 'Write-off Account',
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                filled: true,
                                                fillColor: isDark
                                                    ? const Color(0xFF2A2A2A)
                                                    : Colors.grey[50],
                                              ),
                                              style: TextStyle(
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black87,
                                              ),
                                              dropdownColor: isDark
                                                  ? const Color(0xFF2A2A2A)
                                                  : Colors.white,
                                              isExpanded: true,
                                              items: _writeoffAccounts.map((
                                                account,
                                              ) {
                                                return DropdownMenuItem<
                                                  Map<String, dynamic>
                                                >(
                                                  value: account,
                                                  child: Text(
                                                    '${account['code']} - ${account['name']}',
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                );
                                              }).toList(),
                                              onChanged: (value) {
                                                setState(
                                                  () =>
                                                      _selectedWriteoffAccount =
                                                          value,
                                                );
                                              },
                                              validator: (value) {
                                                if (_paymentDifferenceHandling ==
                                                        'reconcile' &&
                                                    value == null) {
                                                  return 'Please select a write-off account';
                                                }
                                                return null;
                                              },
                                            ),
                                      ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _writeoffLabelController,
                                      decoration: InputDecoration(
                                        labelText: 'Write-off Label',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        filled: true,
                                        fillColor: isDark
                                            ? const Color(0xFF2A2A2A)
                                            : Colors.grey[50],
                                      ),
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ],
                              ),

                            const SizedBox(height: 32),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () => Navigator.pop(context),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      side: BorderSide(
                                        color: theme.primaryColor,
                                      ),
                                    ),
                                    child: Text(
                                      'Cancel',
                                      style: TextStyle(
                                        color: theme.primaryColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: ElevatedButton(
                                    onPressed: _isLoading
                                        ? null
                                        : _registerPayment,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: theme.primaryColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 2,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if (_isLoading) ...[
                                          const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Colors.white,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ] else ...[
                                          const Icon(
                                            HugeIcons
                                                .strokeRoundedCheckmarkCircle01,
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Text(
                                          _isLoading
                                              ? 'Processing...'
                                              : 'Register Payment',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
