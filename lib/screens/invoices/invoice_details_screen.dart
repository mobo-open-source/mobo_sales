import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/screens/invoices/enhanced_payment_screen.dart';
import 'package:mobo_sales/widgets/reconciliation_indicator.dart';
import 'package:mobo_sales/widgets/reconciliation_status_bar.dart';
import 'package:mobo_sales/models/invoice.dart';
import 'package:mobo_sales/models/payment.dart';
import 'package:mobo_sales/models/contact.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import 'package:mobo_sales/utils/navigation_helper.dart';
import 'package:mobo_sales/widgets/pdf_widget.dart';
import 'package:mobo_sales/models/quote.dart';
import 'package:shimmer/shimmer.dart';
import '../../services/odoo_session_manager.dart';
import '../../widgets/list_shimmer.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../../providers/currency_provider.dart';
import '../../providers/invoice_details_provider_enterprise.dart';
import '../../providers/last_opened_provider.dart';
import '../../services/invoice_service.dart';
import '../../widgets/custom_snackbar.dart';
import '../../services/payment_status_synchronizer.dart';
import '../../services/session_service.dart';
import '../../services/payment_service.dart';
import '../../services/permission_service.dart';
import '../invoices/create_invoice_screen.dart';
import '../quotations/quotation_details_screen.dart';
import '../quotations/quotation_list_screen.dart';

class InvoiceDetailsPage extends StatefulWidget {
  final String invoiceId;
  final VoidCallback? onInvoiceUpdated;
  final bool fromQuotationDetails;

  const InvoiceDetailsPage({
    super.key,
    required this.invoiceId,
    this.onInvoiceUpdated,
    this.fromQuotationDetails = false,
  });

  @override
  State<InvoiceDetailsPage> createState() => _InvoiceDetailsPageState();
}

class _InvoiceDetailsPageState extends State<InvoiceDetailsPage>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  Timer? _paymentStatusTimer;
  final bool _isPaymentStatusLoading = false;
  String? _paymentStatus;
  String? _lastPaymentDate;
  double? _paidAmount;
  double? _dueAmount;
  String? _paymentMethod;
  final Map<int, Uint8List?> _productImages = {};
  final Set<int> _loadingProductImages = {};
  bool _hasChanges = false;
  late AnimationController _fadeController;

  List<Map<String, dynamic>> _relatedSaleOrders = [];
  bool _isLoadingRelatedSaleOrders = false;

  StreamSubscription<PaymentStatusUpdate>? _paymentStatusSubscription;
  bool _isRefreshingPaymentStatus = false;
  String? _lastPaymentState;
  Timer? _autoRefreshTimer;

  bool _isLoadingInvoiceData = false;
  bool _isLoadingPayments = false;
  bool _isLoadingInitialData = true;
  DateTime? _lastRefreshTime;
  DateTime? _lastManualRefreshTime;

  List<Payment> _invoicePayments = [];

  Map<String, dynamic> _additionalInfo = {};
  bool _isLoadingAdditionalInfo = false;

  bool _canWriteAccountMove = true;
  bool _canUnlinkAccountMove = true;
  bool _canCreatePaymentRegister = true;

  @override
  void initState() {
    super.initState();

    _fetchPermissions();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animationController.forward();
      _loadInvoiceData();
      _startPaymentStatusMonitoring();
    });
  }

  Future<void> _fetchPermissions() async {
    try {
      final perm = PermissionService.instance;
      final canWrite = await perm.canWrite('account.move');
      final canUnlink = await perm.canUnlink('account.move');
      final canCreatePayment = await perm.canCreate('account.payment.register');
      if (mounted) {
        setState(() {
          _canWriteAccountMove = canWrite;
          _canUnlinkAccountMove = canUnlink;
          _canCreatePaymentRegister = canCreatePayment;
        });
      }
    } catch (e) {}
  }

  void _showErrorDialog(String title, String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF212121) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        title: Text(
          title,
          style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white
                : Theme.of(dialogContext).colorScheme.onSurface,
          ),
        ),
        content: Text(
          message,
          style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
            color: isDark
                ? Colors.grey[300]
                : Theme.of(dialogContext).colorScheme.onSurfaceVariant,
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
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark
                        ? Colors.grey[400]
                        : Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    '',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
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
                    'Close',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSafeSnackBar(String message, {Color? backgroundColor}) {
    if (!mounted) {
      return;
    }

    try {
      if (!context.mounted) {
        return;
      }
      Theme.of(context);
    } catch (e) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      try {
        if (!context.mounted) {
          return;
        }
        Theme.of(context);

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
    });
  }

  Future<void> _loadInvoiceData({bool forceRefresh = false}) async {
    if (_isLoadingInvoiceData) {
      return;
    }

    if (!forceRefresh &&
        _lastRefreshTime != null &&
        DateTime.now().difference(_lastRefreshTime!) <
            const Duration(seconds: 2)) {
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingInvoiceData = true;
      });
    }

    try {
      final provider = Provider.of<InvoiceDetailsProvider>(
        context,
        listen: false,
      );
      provider.resetState();

      if (widget.invoiceId.isNotEmpty) {
        await provider.fetchInvoiceDetails(context, widget.invoiceId);

        if (provider.invoice != null) {
          await _fetchCustomerDetails(provider.invoice!);
        }

        if (mounted) {
          setState(() {
            _animationController.forward();
            _lastRefreshTime = DateTime.now();
            _isLoadingInitialData = false;
          });
          _trackInvoiceAccessFromProvider(provider);
          _fetchProductImagesForInvoiceLines();
          _fetchRelatedSaleOrders();
          _loadInvoicePayments();

          _fetchAdditionalInfo();
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingInvoiceData = false;
        });
      }
    }
  }

  void _trackInvoiceAccessFromProvider(InvoiceDetailsProvider provider) {
    try {
      final lastOpenedProvider = Provider.of<LastOpenedProvider>(
        context,
        listen: false,
      );
      final invoiceId = widget.invoiceId;
      final invoiceName = provider.invoiceNumber;
      final customerName = provider.customerName;

      lastOpenedProvider.trackInvoiceAccess(
        invoiceId: invoiceId,
        invoiceName: invoiceName,
        customerName: customerName,
        invoiceData: provider.invoiceData,
      );
    } catch (e) {}
  }

  void _fetchProductImagesForInvoiceLines() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final provider = Provider.of<InvoiceDetailsProvider>(
        context,
        listen: false,
      );
      final invoiceLines = provider.invoiceLines;

      final Set<int> productIdsToFetch = {};
      for (final line in invoiceLines) {
        final productId =
            (line['product_id'] is List && line['product_id'].isNotEmpty)
            ? line['product_id'][0]
            : null;
        if (productId is int &&
            !_productImages.containsKey(productId) &&
            !_loadingProductImages.contains(productId)) {
          productIdsToFetch.add(productId);
        }
      }

      for (final productId in productIdsToFetch) {
        _fetchProductImage(productId);
      }
    });
  }

  Future<void> _fetchProductImage(int productId) async {
    if (!mounted || _loadingProductImages.contains(productId)) return;

    setState(() {
      _loadingProductImages.add(productId);
    });

    try {
      final session = await OdooSessionManager.getCurrentSession();
      if (session == null) return;

      final imageUrl =
          '${session.serverUrl}/web/image/product.product/$productId/image_128';
      final response = await OdooSessionManager.makeAuthenticatedRequest(
        imageUrl,
      );

      if (response.statusCode == 200 && mounted) {
        setState(() {
          _productImages[productId] = response.bodyBytes;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingProductImages.remove(productId);
        });
      }
    }
  }

  Future<void> _fetchRelatedSaleOrders() async {
    if (!mounted) return;
    final provider = Provider.of<InvoiceDetailsProvider>(
      context,
      listen: false,
    );
    final originRaw = provider.invoiceOrigin.trim();
    if (originRaw.isEmpty || originRaw.toLowerCase() == 'false') {
      if (mounted) {
        setState(() {
          _relatedSaleOrders = [];
          _isLoadingRelatedSaleOrders = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _isLoadingRelatedSaleOrders = true;
        _relatedSaleOrders = [];
      });
    }
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final names = originRaw
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      List<dynamic> domain;
      if (names.length == 1) {
        domain = [
          ['name', '=', names.first],
        ];
      } else {
        domain = [
          ['name', 'in', names],
        ];
      }

      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [domain],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'partner_id',
            'date_order',
            'state',
            'amount_total',
            'amount_untaxed',
            'amount_tax',
            'currency_id',
          ],
          'limit': 50,
          'order': 'date_order desc',
        },
      });

      final List<Map<String, dynamic>> orders = (result is List)
          ? List<Map<String, dynamic>>.from(result)
          : [];

      if (!mounted) return;
      setState(() {
        _relatedSaleOrders = orders;
        _isLoadingRelatedSaleOrders = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _relatedSaleOrders = [];
        _isLoadingRelatedSaleOrders = false;
      });
    }
  }

  Future<void> _loadInvoicePayments() async {
    if (!mounted || _isLoadingPayments) return;

    final invoiceId = int.tryParse(widget.invoiceId);
    if (invoiceId == null) return;

    if (mounted) {
      setState(() {
        _isLoadingPayments = true;
      });
    }

    try {
      final payments = await _getBasicInvoicePayments(invoiceId);
      if (mounted) {
        setState(() {
          _invoicePayments = payments;
          _isLoadingPayments = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _invoicePayments = [];
          _isLoadingPayments = false;
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
              ],
              [
                'id',
                'name',
                'amount',
                'date',
                'state',
                'payment_type',
                'partner_id',
                'journal_id',
                'currency_id',
                'is_reconciled',
                'is_matched',
                'payment_method_id',
              ],
            ],
            'kwargs': {'limit': 50, 'order': 'date desc, id desc'},
          })
          .timeout(const Duration(seconds: 10));

      final List<Map<String, dynamic>> paymentsData = (paymentResults is List)
          ? List<Map<String, dynamic>>.from(paymentResults)
          : [];

      final payments = paymentsData.map((paymentData) {
        return Payment.fromJson(paymentData);
      }).toList();

      return payments;
    } catch (e) {
      return [];
    }
  }

  Widget _buildRelatedSaleOrdersAppBarAction(
    InvoiceDetailsProvider provider,
    bool isDark,
  ) {
    if (_isLoadingRelatedSaleOrders || _relatedSaleOrders.isEmpty) {
      return const SizedBox.shrink();
    }

    final invoiceOrigin = provider.invoiceOrigin.trim();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: IconButton(
        onPressed: () {
          if (_relatedSaleOrders.length == 1) {
            if (widget.fromQuotationDetails) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => QuotationDetailScreen(
                    quotation: Quote.fromJson(_relatedSaleOrders.first),
                    fromInvoiceDetails: true,
                  ),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => QuotationDetailScreen(
                    quotation: Quote.fromJson(_relatedSaleOrders.first),
                    fromInvoiceDetails: true,
                  ),
                ),
              );
            }
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => QuotationListScreen(
                  invoiceName: invoiceOrigin,
                  showForcedAppBar: true,
                ),
              ),
            );
          }
        },
        icon: Badge(
          label: Text('${_relatedSaleOrders.length}'),
          child: Icon(
            HugeIcons.strokeRoundedShoppingCart01,
            size: 24,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[400]
                : Colors.grey[600],
          ),
        ),
        tooltip: 'Sale Orders (${_relatedSaleOrders.length})',
      ),
    );
  }

  Widget _buildRelatedSaleOrdersSectionDynamic(
    InvoiceDetailsProvider provider,
    bool isDark,
  ) {
    if (_isLoadingRelatedSaleOrders || _relatedSaleOrders.isEmpty) {
      return const SizedBox.shrink();
    }

    final invoiceOrigin = provider.invoiceOrigin.trim();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton.icon(
          onPressed: () {
            Navigator.push(
              context,

              MaterialPageRoute(
                builder: (context) => QuotationListScreen(
                  invoiceName: invoiceOrigin,
                  showForcedAppBar: true,
                ),
              ),
            );
          },
          icon: Icon(
            HugeIcons.strokeRoundedShoppingCart01,
            size: 20,
            color: isDark ? Colors.white70 : AppTheme.primaryColor,
          ),
          label: Text(
            'Sale Orders (${_relatedSaleOrders.length})',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: isDark ? Colors.white70 : AppTheme.primaryColor,
            side: BorderSide(
              color: isDark
                  ? Colors.grey[700]!
                  : AppTheme.primaryColor.withOpacity(0.5),
              width: 1.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _fadeController.dispose();
    _tabController.dispose();
    _scrollController.dispose();
    _paymentStatusTimer?.cancel();
    super.dispose();
  }

  void _startPaymentStatusMonitoring() {
    final invoiceId = int.tryParse(widget.invoiceId);
    if (invoiceId == null) return;

    _paymentStatusSubscription =
        PaymentStatusSynchronizer.watchPaymentStatus(invoiceId).listen(
          (update) {
            _handlePaymentStatusUpdate(update);
          },
          onError: (error) {
            _showSafeSnackBar(
              'Payment status monitoring error: $error',
              backgroundColor: Colors.orange,
            );
          },
        );

    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _refreshPaymentStatusSilently();
      }
    });
  }

  void _stopPaymentStatusMonitoring() {
    try {
      final invoiceId = int.tryParse(widget.invoiceId);
      if (invoiceId != null) {
        PaymentStatusSynchronizer.stopWatchingPaymentStatus(invoiceId);
      }

      _paymentStatusSubscription?.cancel();
      _paymentStatusSubscription = null;

      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
    } catch (e) {}
  }

  void _handlePaymentStatusUpdate(PaymentStatusUpdate update) {
    if (!mounted) return;

    if (_lastManualRefreshTime != null &&
        DateTime.now().difference(_lastManualRefreshTime!) <
            const Duration(seconds: 10)) {
      if (update.previousPaymentState != update.currentPaymentState &&
          update.previousPaymentState != 'unknown') {
        _updatePaymentStateOptimistically(update);
      }

      _lastPaymentState = update.currentPaymentState;
      return;
    }

    if (update.previousPaymentState != update.currentPaymentState &&
        update.previousPaymentState != 'unknown') {
      _showPaymentStatusNotification(update);

      _updatePaymentStateOptimistically(update);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isLoadingInvoiceData) {
          try {
            Theme.of(context);
            _loadInvoiceData(forceRefresh: true);
          } catch (e) {}
        }
      });
    }

    _lastPaymentState = update.currentPaymentState;
  }

  void _showPaymentStatusNotification(PaymentStatusUpdate update) {
    String message;
    Color backgroundColor;

    switch (update.currentPaymentState) {
      case 'paid':
        message = 'Payment completed successfully!';
        backgroundColor = Colors.green;
        break;
      case 'in_payment':
        message = 'Payment is being processed';
        backgroundColor = Colors.blue;
        break;
      case 'partial':
        message = 'Partial payment received';
        backgroundColor = Colors.orange;
        break;
      case 'not_paid':
        message = 'Payment status updated';
        backgroundColor = Colors.grey;
        break;
      default:
        message = 'Payment status changed to ${update.currentPaymentState}';
        backgroundColor = Colors.blue;
    }

    _showSafeSnackBar(message, backgroundColor: backgroundColor);
  }

  void _updatePaymentStateOptimistically(PaymentStatusUpdate update) {
    if (!mounted) return;

    try {
      Theme.of(context);
      final provider = Provider.of<InvoiceDetailsProvider>(
        context,
        listen: false,
      );

      final updatedData = provider.invoiceData;
      updatedData['payment_state'] = update.currentPaymentState;

      double totalPaid = 0.0;
      double totalPending = 0.0;

      for (final payment in update.payments) {
        if (payment.isFullyReconciled) {
          totalPaid += payment.amount;
        } else if (payment.isInPayment || payment.state == 'posted') {
          totalPending += payment.amount;
        }
      }

      final totalAmount = updatedData['amount_total'] as double? ?? 0.0;

      if (update.currentPaymentState == 'paid') {
        updatedData['amount_residual'] = 0.0;
      } else if (update.currentPaymentState == 'partial') {
        updatedData['amount_residual'] = totalAmount - totalPaid;
      } else if (update.currentPaymentState == 'in_payment') {
        updatedData['amount_residual'] = totalAmount - totalPaid - totalPending;
      }

      final amountResidual = updatedData['amount_residual'] as double? ?? 0.0;
      if (amountResidual < 0) {
        updatedData['amount_residual'] = 0.0;
      }

      provider.updateInvoiceData(updatedData);

      if (mounted) {
        setState(() {
          _hasChanges = true;
        });
      }
    } catch (e) {}
  }

  Future<void> _refreshPaymentStatusSilently() async {
    if (!mounted || _isRefreshingPaymentStatus || _isLoadingInvoiceData) return;

    final invoiceId = int.tryParse(widget.invoiceId);
    if (invoiceId == null) return;

    try {
      if (mounted) {
        setState(() {
          _isRefreshingPaymentStatus = true;
        });
      }

      await PaymentStatusSynchronizer.syncInvoicePaymentStatus(invoiceId);
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingPaymentStatus = false;
        });
      }
    }
  }

  Future<void> _refreshPaymentStatus() async {
    if (!mounted) return;

    final invoiceId = int.tryParse(widget.invoiceId);
    if (invoiceId == null) return;

    if (_isRefreshingPaymentStatus || _isLoadingInvoiceData) {
      return;
    }

    try {
      if (mounted) {
        setState(() {
          _isRefreshingPaymentStatus = true;
        });
      }

      PaymentStatusSynchronizer.clearCache(invoiceId);
      OdooSessionManager.clearClientCache();
      PaymentService.clearBehaviorCache();

      await PaymentStatusSynchronizer.syncInvoicePaymentStatus(invoiceId);

      if (mounted) {
        await _loadInvoiceData(forceRefresh: true);

        await _loadInvoicePayments();
      }

      if (mounted) {
        _showSafeSnackBar(
          'Payment status refreshed',
          backgroundColor: Colors.green,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSafeSnackBar(
          'Failed to refresh payment status: $e',
          backgroundColor: Colors.red,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingPaymentStatus = false;
        });
      }
    }
  }

  void _showReconciliationGuidance() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Text(
                'Reconciliation Required',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This invoice has payments that are posted but need to be reconciled in Odoo to complete the payment process.',
                style: TextStyle(
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.orange.shade700,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Next Steps:',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. Access your Odoo backend\n'
                      '2. Go to Accounting > Reconciliation\n'
                      '3. Match the payments with this invoice\n'
                      '4. Complete the reconciliation process',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Got it',
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPaymentHistorySection(
    InvoiceDetailsProvider provider,
    bool isDark,
  ) {
    final invoice = provider.invoice;
    if (invoice == null) return const SizedBox.shrink();

    if (_invoicePayments.isEmpty &&
        provider.paymentState == 'not_paid' &&
        provider.invoiceState != 'paid') {
      return const SizedBox.shrink();
    }

    return _buildSectionCard(
      title: 'Payment Status & History',
      icon: HugeIcons.strokeRoundedPayment02,
      iconColor: isDark ? Colors.white70 : Colors.grey[800],
      children: [
        _buildPaymentSummaryCard(provider, isDark),

        if (invoice.requiresReconciliation) ...[
          const SizedBox(height: 16),
          ReconciliationStatusBar(
            payments: invoice.payments,
            invoice: invoice,
            showProgress: true,
            onViewDetails: () => _showReconciliationGuidance(),
          ),
        ],

        if (_invoicePayments.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildPaymentHistoryList(_invoicePayments, isDark),
        ],
      ],
    );
  }

  Widget _buildPaymentSummaryCard(
    InvoiceDetailsProvider provider,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        children: [
          _buildPaymentSummaryRow(
            'Total Amount',
            provider.invoiceAmount,
            provider.invoice?.currencyId,
            isDark,
            isTotal: true,
          ),
          const SizedBox(height: 8),
          _buildPaymentSummaryRow(
            'Amount Paid',
            provider.invoiceAmount - provider.amountResidual,
            provider.invoice?.currencyId,
            isDark,
            isPaid: true,
          ),
          const SizedBox(height: 8),
          _buildPaymentSummaryRow(
            'Amount Due',
            provider.amountResidual,
            provider.invoice?.currencyId,
            isDark,
            isDue: provider.amountResidual > 0,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSummaryRow(
    String label,
    double amount,
    List<dynamic>? currencyId,
    bool isDark, {
    bool isTotal = false,
    bool isPaid = false,
    bool isDue = false,
  }) {
    Color textColor;
    if (isPaid) {
      textColor = Colors.green;
    } else if (isDue) {
      textColor = Colors.red;
    } else if (isTotal) {
      textColor = isDark ? Colors.white : Colors.black87;
    } else {
      textColor = isDark ? Colors.grey[300]! : Colors.grey[700]!;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            fontWeight: isTotal ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          context.read<CurrencyProvider>().formatAmount(
            amount,
            currency: currencyId != null && currencyId.length > 1
                ? currencyId[1].toString()
                : null,
          ),
          style: TextStyle(
            fontSize: 14,
            color: textColor,
            fontWeight: isTotal || isPaid || isDue
                ? FontWeight.w600
                : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentHistoryList(List<Payment> payments, bool isDark) {
    if (payments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[850] : Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'No payment history available',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment History',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        ...payments.map((payment) => _buildPaymentHistoryItem(payment, isDark)),
      ],
    );
  }

  Widget _buildPaymentHistoryItem(Payment payment, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getPaymentStatusColor(payment).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getPaymentStatusIcon(payment),
              color: _getPaymentStatusColor(payment),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      payment.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      '\$${payment.amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _getPaymentStatusColor(payment),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      payment.statusDisplayText,
                      style: TextStyle(
                        fontSize: 12,
                        color: _getPaymentStatusColor(payment),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (payment.paymentDate != null)
                      Text(
                        DateFormat('MMM dd, yyyy').format(payment.paymentDate!),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getPaymentStatusColor(Payment payment) {
    if (payment.isFullyReconciled) {
      return Colors.green;
    } else if (payment.isInPayment) {
      return Colors.blue;
    } else if (payment.requiresReconciliation) {
      return Colors.orange;
    } else {
      return Colors.grey;
    }
  }

  IconData _getPaymentStatusIcon(Payment payment) {
    if (payment.isFullyReconciled) {
      return Icons.check_circle;
    } else if (payment.isInPayment) {
      return Icons.schedule;
    } else if (payment.requiresReconciliation) {
      return Icons.sync_problem;
    } else {
      return Icons.payment;
    }
  }

  Widget _buildShimmer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shimmerBase = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final shimmerHighlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Shimmer.fromColors(
        baseColor: shimmerBase,
        highlightColor: shimmerHighlight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 32, width: 200, color: shimmerBase),
            const SizedBox(height: 16),
            Container(height: 20, width: 120, color: shimmerBase),
            const SizedBox(height: 8),
            Container(height: 20, width: 180, color: shimmerBase),
            const SizedBox(height: 8),
            Container(height: 20, width: 100, color: shimmerBase),
            const SizedBox(height: 8),
            Container(height: 20, width: 140, color: shimmerBase),
            const SizedBox(height: 24),
            for (int i = 0; i < 3; i++) ...[
              Container(height: 24, width: 180, color: shimmerBase),
              const SizedBox(height: 12),
              Container(height: 18, width: double.infinity, color: shimmerBase),
              const SizedBox(height: 8),
              Container(height: 18, width: 200, color: shimmerBase),
              const SizedBox(height: 24),
            ],
          ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.18)
                : Colors.black.withOpacity(0.05),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.only(
              left: 12,
              right: 12,
              top: 12,
              bottom: 8,
            ),
            decoration: BoxDecoration(),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    Color? valueColor,
    bool highlight = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.white70 : Color(0xff7F7F7F),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
                color:
                    valueColor ??
                    (highlight
                        ? (isDark ? Colors.white : Colors.grey[900])
                        : (isDark ? Colors.grey[200] : Colors.grey[800])),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleStatusBadge(Invoice invoice, bool isDark) {
    final statusText = _getInvoiceStatusLabel(invoice);
    final statusColor = _getInvoiceStatusColor(invoice);
    final textColor = isDark ? Colors.white : statusColor;
    final backgroundColor = isDark
        ? statusColor.withOpacity(0.15)
        : statusColor.withOpacity(0.10);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        statusText,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  bool _canEditInvoice(Invoice invoice) {
    return invoice.status == 'draft';
  }

  String _getInvoiceStatusLabel(Invoice invoice) {
    switch (invoice.status.toLowerCase()) {
      case 'draft':
        return 'Draft';
      case 'cancel':
        return 'Cancelled';
      case 'sent':
        return 'Sent';
      case 'posted':
        switch (invoice.paymentState.toLowerCase()) {
          case 'paid':
            return 'Paid';
          case 'partial':
            return 'Partially Paid';
          case 'reversed':
            return 'Reversed';
          case 'in_payment':
            return 'In Payment';
          case 'blocked':
            return 'Blocked';
          case 'invoicing_legacy':
            return 'Invoicing App Legacy';
          default:
            if (invoice.isMoveSent == true) {
              return 'Sent';
            }

            return 'Posted';
        }
      default:
        return invoice.status.isNotEmpty ? invoice.status : 'Unknown';
    }
  }

  Color _getInvoiceStatusColor(Invoice invoice) {
    switch (invoice.status.toLowerCase()) {
      case 'draft':
        return Colors.grey;
      case 'cancel':
        return Colors.red;
      case 'sent':
        return Colors.grey;
      case 'posted':
        switch (invoice.paymentState.toLowerCase()) {
          case 'paid':
            return Colors.green;
          case 'partial':
            return Colors.orange;
          case 'reversed':
            return Colors.purple;
          case 'in_payment':
            return Colors.green;
          case 'blocked':
            return Colors.grey;
          case 'invoicing_legacy':
            return Colors.amber;
          default:
            return Colors.grey;
        }
      default:
        return Colors.grey;
    }
  }

  Widget _buildStatusRow(String label, String paymentState, String state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = Provider.of<InvoiceDetailsProvider>(
      context,
      listen: false,
    );

    final invoice = provider.invoice;
    if (invoice == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildSimpleStatusBadge(invoice, isDark),
                    if (_isRefreshingPaymentStatus) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: isDark ? Colors.blue[200] : Colors.blue,
                        ),
                      ),
                    ],
                  ],
                ),
                if (invoice.requiresReconciliation) ...[
                  const SizedBox(height: 8),
                  ReconciliationIndicator(
                    invoice: invoice,
                    showDetails: false,
                    compact: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
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

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
    bool isDestructive = false,
    bool isPrimary = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isPrimary) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton.icon(
          icon: Icon(
            icon,
            color: onPressed == null
                ? (isDark ? Colors.grey[500] : Colors.grey[400])
                : (isDark ? Colors.white : Colors.black87),
            size: 20,
          ),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: onPressed == null
                  ? (isDark ? Colors.grey[500] : Colors.grey[400])
                  : (isDark ? Colors.white : Colors.black87),
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: isDark ? Colors.white : Colors.black87,
            side: BorderSide(
              color: onPressed == null
                  ? (isDark ? Colors.grey[600]! : Color(0xff000000))
                  : (isDark ? Colors.grey[600]! : Color(0xff000000)),
              width: 1,
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            minimumSize: const Size(double.infinity, 52),
            backgroundColor: isDark ? Colors.transparent : Colors.white,
          ),
          onPressed: onPressed,
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ElevatedButton.icon(
          icon: Icon(icon, color: Colors.white, size: 20),
          label: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: onPressed == null ? Colors.grey[400] : color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
            minimumSize: const Size(double.infinity, 52),
          ),
          onPressed: onPressed,
        ),
      );
    }
  }

  Widget _buildPrimaryActionButtons(InvoiceDetailsProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: HugeIcons.strokeRoundedFileDownload,
                label: 'Print Invoice',
                color: Color(0xFF1E88E5),
                isPrimary: true,

                onPressed: () async {
                  final isDark =
                      Theme.of(context).brightness == Brightness.dark;

                  bool dialogDismissed = false;

                  showDialog(
                    context: context,
                    barrierDismissible: true,
                    builder: (dialogContext) {
                      return Dialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        backgroundColor: isDark
                            ? const Color(0xFF212121)
                            : Colors.white,
                        elevation: 8,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 28,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Align(
                                alignment: Alignment.topRight,
                                child: IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  iconSize: 20,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                              ),
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.12)
                                      : AppTheme.primaryColor.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: LoadingAnimationWidget.fourRotatingDots(
                                  color: isDark
                                      ? Colors.white
                                      : AppTheme.primaryColor,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Generating PDF',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.grey[900],
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Please wait while we prepare your document',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: isDark
                                          ? Colors.grey[400]
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

                  void dismissDialog() {
                    if (!dialogDismissed && mounted) {
                      try {
                        final navigator = Navigator.of(
                          context,
                          rootNavigator: true,
                        );
                        if (navigator.canPop()) {
                          navigator.pop();
                          dialogDismissed = true;
                        }
                      } catch (e) {}
                    }
                  }

                  try {
                    await PDFGenerator.generateInvoicePdf(
                      context,
                      provider.invoice!,
                      onBeforeOpen: dismissDialog,
                    );
                  } catch (e) {
                    dismissDialog();
                    _showSafeSnackBar(
                      'PDF generation failed: ${e.toString()}',
                      backgroundColor: Colors.red,
                    );
                  }
                },
              ),
            ),
            SizedBox(width: 8),
            if (provider.invoiceState == 'draft')
              Expanded(
                child: _buildActionButton(
                  icon: HugeIcons.strokeRoundedInvoice03,
                  label: 'Confirm Invoice',
                  color: Color(0xff000000),
                  isPrimary: false,

                  onPressed: !_canWriteAccountMove
                      ? () {
                          CustomSnackbar.showError(
                            context,
                            'Permission Denied: You do not have permission to post invoices (account.move write). Please contact your administrator.',
                          );
                        }
                      : () async {
                          final isDark =
                              Theme.of(context).brightness == Brightness.dark;

                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) {
                              return Dialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                backgroundColor: isDark
                                    ? const Color(0xFF212121)
                                    : Colors.white,
                                elevation: 8,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 28,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 56,
                                        height: 56,
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white.withOpacity(0.12)
                                              : AppTheme.primaryColor
                                                    .withOpacity(0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child:
                                            LoadingAnimationWidget.fourRotatingDots(
                                              color: isDark
                                                  ? Colors.white
                                                  : AppTheme.primaryColor,
                                              size: 32,
                                            ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Confirming Invoice',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.grey[900],
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Please wait while we validate your invoice',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: isDark
                                                  ? Colors.grey[400]
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

                          final success = await provider.postInvoice(
                            context,
                            widget.invoiceId,
                          );
                          if (context.mounted) {
                            Navigator.of(context).pop();
                            if (success) {
                              setState(() {
                                _hasChanges = true;
                              });
                              CustomSnackbar.showSuccess(
                                context,
                                'Invoice validated successfully',
                              );
                              widget.onInvoiceUpdated?.call();
                            } else {
                              CustomSnackbar.showError(
                                context,
                                provider.errorMessage,
                              );
                            }
                          }
                        },
                ),
              ),
            if (provider.invoiceState != 'draft' &&
                provider.invoiceState != 'cancel')
              Expanded(
                child: _buildActionButton(
                  icon: HugeIcons.strokeRoundedPayment02,
                  label: 'Record Payment',
                  color: const Color(0xff000000),

                  isPrimary: false,

                  onPressed:
                      (provider.isFullyPaid || !_canCreatePaymentRegister)
                      ? () {
                          if (!_canCreatePaymentRegister) {
                            CustomSnackbar.showError(
                              context,
                              'Permission Denied: You do not have permission to register payments (account.payment.register). Please contact your administrator.',
                            );
                          }
                        }
                      : () async {
                          try {
                            final invoice = provider.invoice;
                            if (invoice == null) return;

                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EnhancedPaymentScreen(
                                  invoice: invoice,
                                  existingPayments: _invoicePayments,
                                ),
                              ),
                            );

                            if (result != null) {
                              if (result is Map<String, dynamic>) {
                                final success = result['success'] == true;
                                final forceRefresh =
                                    result['forceRefresh'] == true;

                                if (success) {
                                  _showSafeSnackBar(
                                    'Payment recorded successfully!',
                                    backgroundColor: Colors.green,
                                  );

                                  if (forceRefresh) {
                                    final invoiceId = int.tryParse(
                                      widget.invoiceId,
                                    );
                                    if (invoiceId != null) {
                                      PaymentStatusSynchronizer.clearCache(
                                        invoiceId,
                                      );
                                      OdooSessionManager.clearClientCache();
                                      PaymentService.clearBehaviorCache();
                                    }
                                  }

                                  setState(() {
                                    _hasChanges = true;
                                    _lastManualRefreshTime = DateTime.now();
                                  });

                                  await _loadInvoiceData(forceRefresh: true);

                                  await _loadInvoicePayments();
                                }
                              } else if (result is Invoice) {
                                _showSafeSnackBar(
                                  'Payment recorded successfully!',
                                  backgroundColor: Colors.green,
                                );

                                final updatedData = {
                                  'id': result.id,
                                  'name': result.name,
                                  'payment_state': result.paymentState,
                                  'state': result.status,
                                  'amount_residual': result.amountResidual,
                                  'amount_total': result.total,
                                  'amount_paid': result.amountPaid,
                                };
                                provider.updateInvoiceData(updatedData);

                                setState(() {
                                  _hasChanges = true;
                                  _lastManualRefreshTime = DateTime.now();
                                });

                                await _loadInvoiceData(forceRefresh: true);

                                await _loadInvoicePayments();
                              } else if (result == true) {
                                _showSafeSnackBar(
                                  'Payment recorded successfully!',
                                  backgroundColor: Colors.green,
                                );

                                if (mounted) {
                                  setState(() {
                                    _hasChanges = true;
                                    _lastManualRefreshTime = DateTime.now();
                                  });

                                  final invoiceId = int.tryParse(
                                    widget.invoiceId,
                                  );
                                  if (invoiceId != null) {
                                    PaymentStatusSynchronizer.clearCache(
                                      invoiceId,
                                    );
                                  }

                                  await _loadInvoiceData(forceRefresh: true);

                                  await _loadInvoicePayments();
                                }
                              }

                              widget.onInvoiceUpdated?.call();
                            }
                          } catch (e) {
                            _showSafeSnackBar(
                              'Error recording payment: $e',
                              backgroundColor: Colors.red,
                            );
                          }
                        },
                ),
              ),
          ],
        ),

        if (provider.paymentState == 'in_payment')
          _buildActionButton(
            icon: HugeIcons.strokeRoundedRefresh,
            label: 'Reconcile in Odoo',
            color: const Color(0xFFFF9800),

            isPrimary: false,

            onPressed: () {
              _showReconciliationGuidance();
            },
          ),
      ],
    );
  }

  Widget _buildSecondaryActionButtons(InvoiceDetailsProvider provider) {
    if (provider.invoiceState != 'posted' &&
        provider.invoiceState != 'draft' &&
        provider.invoiceState != 'cancel') {
      return Container();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: Color(0xff000000).withOpacity(.5))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'More Actions',
                style: TextStyle(
                  color: Color(0xff000000).withOpacity(.5),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(child: Divider(color: Color(0xff000000).withOpacity(.5))),
          ],
        ),
        const SizedBox(height: 16),
        if (provider.invoiceState == 'posted')
          _buildActionButton(
            icon: Icons.restore,
            label: 'Reset to Draft',
            color: AppTheme.primaryColor,
            onPressed: () async {
              final isDark = Theme.of(context).brightness == Brightness.dark;

              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) {
                  return Dialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    backgroundColor: isDark
                        ? const Color(0xFF212121)
                        : Colors.white,
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 28,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.12)
                                  : AppTheme.primaryColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: LoadingAnimationWidget.fourRotatingDots(
                              color: isDark
                                  ? Colors.white
                                  : AppTheme.primaryColor,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Resetting Invoice',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.grey[900],
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Please wait while we reset your invoice to draft',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: isDark
                                      ? Colors.grey[400]
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

              final success = await provider.resetToDraft(
                context,
                widget.invoiceId,
              );
              if (context.mounted) {
                Navigator.of(context).pop();
                if (success) {
                  setState(() {
                    _hasChanges = true;
                  });
                  CustomSnackbar.showSuccess(
                    context,
                    'Invoice reset to draft successfully',
                  );
                } else {
                  CustomSnackbar.showError(context, provider.errorMessage);
                }
              }
            },
          ),
        if (provider.invoiceState == 'draft')
          _buildActionButton(
            icon: HugeIcons.strokeRoundedCancelCircleHalfDot,
            label: 'Cancel Invoice',
            color: Colors.red[700]!,
            isPrimary: true,
            onPressed: () async {
              final isDark = Theme.of(context).brightness == Brightness.dark;

              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) {
                  return Dialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    backgroundColor: isDark
                        ? const Color(0xFF212121)
                        : Colors.white,
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 28,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.12)
                                  : AppTheme.primaryColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: LoadingAnimationWidget.fourRotatingDots(
                              color: isDark
                                  ? Colors.white
                                  : AppTheme.primaryColor,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Cancelling Invoice',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.grey[900],
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Please wait while we cancel your invoice',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: isDark
                                      ? Colors.grey[400]
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

              final success = await provider.cancelInvoice(
                context,
                widget.invoiceId,
              );
              if (context.mounted) {
                Navigator.of(context).pop();
                if (success) {
                  setState(() {
                    _hasChanges = true;
                  });
                  CustomSnackbar.showSuccess(
                    context,
                    'Invoice cancelled successfully',
                  );
                } else {
                  CustomSnackbar.showError(context, provider.errorMessage);
                }
              }
            },
          ),
        if (provider.invoiceState == 'draft' ||
            provider.invoiceState == 'cancel')
          _buildActionButton(
            icon: HugeIcons.strokeRoundedDelete02,
            label: 'Delete Invoice',
            color: AppTheme.primaryColor,
            isDestructive: true,
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete Invoice'),
                  content: const Text(
                    'Are you sure you want to delete this invoice? This action cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                final isDark = Theme.of(context).brightness == Brightness.dark;

                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) {
                    return Dialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      backgroundColor: isDark
                          ? const Color(0xFF212121)
                          : Colors.white,
                      elevation: 8,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 28,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withOpacity(0.12)
                                    : Colors.red[900]!.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: LoadingAnimationWidget.fourRotatingDots(
                                color: isDark ? Colors.white : Colors.red[900]!,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Deleting Invoice',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.grey[900],
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Please wait while we delete your invoice',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: isDark
                                        ? Colors.grey[400]
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

                final success = await provider.deleteInvoice(
                  context,
                  widget.invoiceId,
                );
                if (context.mounted) {
                  Navigator.of(context).pop();
                  if (success) {
                    setState(() {
                      _hasChanges = true;
                    });
                    CustomSnackbar.showSuccess(
                      context,
                      'Invoice deleted successfully',
                    );
                    Navigator.of(context).pop(true);
                  } else {
                    CustomSnackbar.showError(context, provider.errorMessage);
                  }
                }
              }
            },
          ),
      ],
    );
  }

  Widget _buildHeaderDetails(InvoiceDetailsProvider provider) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    List<Widget> rows = [];

    rows.add(
      _buildInfoRow('Invoice ', provider.invoiceNumber, highlight: true),
    );

    final origin =
        provider.invoiceOrigin.isNotEmpty && provider.invoiceOrigin != 'false'
        ? provider.invoiceOrigin
        : '-';
    if (origin != '-') {
      rows.add(_buildInfoRow('Origin', origin));
    }

    final reference =
        provider.customerReference.isNotEmpty &&
            provider.customerReference != 'false'
        ? provider.customerReference
        : '-';
    if (reference != '-') {
      rows.add(_buildInfoRow('Reference', reference));
    }

    rows.add(
      _buildStatusRow('Status', provider.paymentState, provider.invoiceState),
    );

    final paymentTerms =
        provider.paymentTerms.isNotEmpty && provider.paymentTerms != 'false'
        ? provider.paymentTerms
        : '-';
    if (paymentTerms != '-') {
      rows.add(_buildInfoRow('Payment Term', paymentTerms));
    }

    final salesperson =
        provider.salesperson.isNotEmpty &&
            provider.salesperson != 'Unassigned' &&
            provider.salesperson != 'false'
        ? provider.salesperson
        : '-';
    if (salesperson != '-') {
      rows.add(_buildInfoRow('Salesperson', salesperson));
    }

    if (provider.invoiceDate != null) {
      rows.add(
        _buildInfoRow('Invoice Date', dateFormat.format(provider.invoiceDate!)),
      );
    }

    if (provider.dueDate != null) {
      rows.add(
        _buildInfoRow(
          'Due Date',
          dateFormat.format(provider.dueDate!),
          valueColor:
              provider.dueDate!.isBefore(DateTime.now()) &&
                  !provider.isFullyPaid
              ? Colors.red
              : null,
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: rows,
    );
  }

  Widget _buildCustomerDetails(InvoiceDetailsProvider provider) {
    List<Widget> rows = [];
    rows.add(_buildInfoRow('Customer', provider.customerName));

    if (provider.invoice?.customerId != null) {
      final customerId = provider.invoice!.customerId.toString();
      rows.add(_buildInfoRow('Customer ID', customerId));
    }

    final email =
        provider.invoice?.customerEmail != null &&
            provider.invoice!.customerEmail != 'false'
        ? provider.invoice!.customerEmail
        : 'N/A';
    rows.add(_buildInfoRow('Email', email ?? 'N/A'));

    final phone =
        provider.invoice?.customerPhone != null &&
            provider.invoice!.customerPhone != 'false'
        ? provider.invoice!.customerPhone
        : 'N/A';
    rows.add(_buildInfoRow('Phone', phone ?? 'N/A'));

    final address = provider.invoice?.customerAddress ?? 'N/A';
    rows.add(_buildInfoRow('Address', address));

    final currencyId = provider.invoiceData['currency_id'];
    if (currencyId is List && currencyId.length > 1) {
      final currencyCode = currencyId[1].toString();
      rows.add(_buildInfoRow('Currency', currencyCode));
    } else if (provider.currency.isNotEmpty) {
      rows.add(_buildInfoRow('Currency', provider.currency));
    }

    return Column(children: rows);
  }

  Widget _buildAmountDetails(InvoiceDetailsProvider provider) {
    return _buildInvoiceSpecificAmounts(provider);
  }

  Widget _buildAmountSummary(InvoiceDetailsProvider provider, bool isDark) {
    final invoiceData = provider.invoiceData;

    final discountAmount =
        (invoiceData['amount_discount'] as num?)?.toDouble() ?? 0.0;
    final shippingAmount =
        (invoiceData['amount_delivery'] as num?)?.toDouble() ?? 0.0;

    double deliveryFromLines = 0.0;
    if (shippingAmount == 0.0) {
      final invoiceLines = provider.invoiceLines;
      for (final line in invoiceLines) {
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

    final currencyId = provider.invoiceData['currency_id'];
    final String? currencyCode = (currencyId is List && currencyId.length > 1)
        ? currencyId[1].toString()
        : null;

    final subtotal = provider.amountUntaxed;
    final tax = provider.amountTax;
    final total = provider.invoiceAmount;

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
            const SizedBox(height: 8),
            Text(
              currencyProvider.formatAmount(total, currency: currencyCode),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 12),
            _buildAmountRow('Subtotal', subtotal, currencyCode, isDark),
            _buildAmountRow('Tax', tax, currencyCode, isDark),
            if (discountAmount > 0)
              _buildAmountRow(
                'Discount',
                -discountAmount,
                currencyCode,
                isDark,
                isDiscount: true,
              ),
            if (totalShipping > 0)
              _buildAmountRow('Shipping', totalShipping, currencyCode, isDark),
            Divider(color: isDark ? Colors.grey[600] : Colors.grey[300]),
            _buildAmountRow(
              'Total',
              total,
              currencyCode,
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
    String? currencyCode,
    bool isDark, {
    bool isTotal = false,
    bool isDiscount = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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

  Widget _buildInvoiceSpecificAmounts(InvoiceDetailsProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer<CurrencyProvider>(
      builder: (context, currencyProvider, _) {
        final currencyId = provider.invoiceData['currency_id'];
        final String? currencyCode =
            (currencyId is List && currencyId.length > 1)
            ? currencyId[1].toString()
            : null;

        List<Widget> rows = [];

        rows.add(
          _buildInfoRow(
            'Amount Paid',
            currencyProvider.formatAmount(
              provider.invoiceAmount - provider.amountResidual,
              currency: currencyCode,
            ),
          ),
        );

        rows.add(
          _buildInfoRow(
            'Amount Due',
            currencyProvider.formatAmount(
              provider.amountResidual,
              currency: currencyCode,
            ),
            valueColor: provider.amountResidual > 0 ? Colors.red : Colors.green,
          ),
        );

        rows.add(
          _buildInfoRow(
            'Overdue',
            provider.dueDate != null &&
                    provider.dueDate!.isBefore(DateTime.now()) &&
                    !provider.isFullyPaid
                ? 'Yes'
                : 'No',
            valueColor: isDark
                ? Colors.white
                : (provider.dueDate != null &&
                          provider.dueDate!.isBefore(DateTime.now()) &&
                          !provider.isFullyPaid
                      ? Colors.red
                      : Colors.green),
          ),
        );

        rows.add(
          _buildInfoRow(
            'Paid',
            provider.isFullyPaid ? 'Yes' : 'No',
            valueColor: isDark
                ? Colors.white
                : (provider.isFullyPaid ? Colors.green : Colors.orange),
          ),
        );

        return Column(children: rows);
      },
    );
  }

  Widget _buildTaxDetails(InvoiceDetailsProvider provider) {
    if (provider.invoiceLines.isEmpty) {
      return const Text('No tax details.');
    }

    return Consumer<CurrencyProvider>(
      builder: (context, currencyProvider, _) {
        final currencyId = provider.invoiceData['currency_id'];
        final String? currencyCode =
            (currencyId is List && currencyId.length > 1)
            ? currencyId[1].toString()
            : null;

        return Column(
          children: provider.invoiceLines
              .map((line) {
                final taxName =
                    line['tax_ids'] is List &&
                        line['tax_ids'].isNotEmpty &&
                        line['tax_ids'][0] is List &&
                        line['tax_ids'][0].length > 1
                    ? line['tax_ids'][0][1]?.toString() ?? 'None'
                    : 'None';
                final total = line['price_total'] as double? ?? 0.0;
                final subtotal = line['price_subtotal'] as double? ?? 0.0;
                final taxAmount = total - subtotal;
                List<Widget> taxRows = [];
                if (taxName != 'None') {
                  taxRows.add(_buildInfoRow('Tax Name', taxName));
                  taxRows.add(
                    _buildInfoRow(
                      'Tax Amount',
                      currencyProvider.formatAmount(
                        taxAmount,
                        currency: currencyCode,
                      ),
                      highlight: true,
                    ),
                  );
                }
                return taxRows.isNotEmpty
                    ? Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: taxRows,
                          ),
                        ),
                      )
                    : Container();
              })
              .where((widget) => widget is! Container)
              .toList(),
        );
      },
    );
  }

  Widget _buildInvoiceLines(InvoiceDetailsProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (provider.invoiceLines.isEmpty) {
      return Text(
        'No invoice lines.',
        style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
      );
    }

    return Consumer<CurrencyProvider>(
      builder: (context, currencyProvider, _) {
        final currencyId = provider.invoiceData['currency_id'];
        final String? currencyCode =
            (currencyId is List && currencyId.length > 1)
            ? currencyId[1].toString()
            : null;

        return Column(
          children: provider.invoiceLines.map((line) {
            return _buildInvoiceLineCard(
              line,
              isDark,
              currencyProvider,
              currencyCode,
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildInvoiceLineCard(
    Map<String, dynamic> line,
    bool isDark,
    CurrencyProvider currencyProvider,
    String? currencyCode,
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
    final quantity = (line['quantity'] as num?)?.toDouble() ?? 0.0;
    final unitPrice = (line['price_unit'] as num?)?.toDouble() ?? 0.0;
    final subtotal = (line['price_subtotal'] as num?)?.toDouble() ?? 0.0;

    String description = line['name']?.toString() ?? '';
    if (description.startsWith(product)) {
      description = description.substring(product.length).trim();
    }
    final sku = line['default_code']?.toString();
    final barcode = line['barcode']?.toString();
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
                    Text(
                      currencyProvider.formatAmount(
                        unitPrice,
                        currency: currencyCode,
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
                    Text(
                      currencyProvider.formatAmount(
                        subtotal,
                        currency: currencyCode,
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(InvoiceDetailsProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                provider.errorMessage,
                style: TextStyle(color: Colors.red[700], fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  provider.fetchInvoiceDetails(context, widget.invoiceId);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA12424),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? Colors.grey[900] : Colors.grey[50];

    if (_isLoadingInitialData) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: isDarkMode ? Colors.grey[900] : Colors.grey[50],
          foregroundColor: isDarkMode
              ? Colors.white
              : Theme.of(context).primaryColor,
          elevation: 0,
          title: Text(
            'Invoice Details',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          leading: IconButton(
            icon: Icon(
              HugeIcons.strokeRoundedArrowLeft01,
              color: isDark ? Colors.white : Colors.black,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: ListShimmer.buildInvoiceDetailsShimmer(context),
      );
    }

    return Consumer<InvoiceDetailsProvider>(
      builder: (context, provider, child) {
        try {
          if (provider.isLoading || provider.invoiceNumber.isEmpty) {
            if (_fadeController.value != 0.0) {
              _fadeController.value = 0.0;
            }
          } else if (provider.errorMessage.isEmpty) {
            if (_fadeController.status != AnimationStatus.forward &&
                _fadeController.value != 1.0) {
              _fadeController.forward();
            }
          }
        } catch (_) {}
        return Stack(
          children: [
            Scaffold(
              backgroundColor: backgroundColor,
              appBar: AppBar(
                backgroundColor: isDarkMode
                    ? Colors.grey[900]
                    : Colors.grey[50],
                foregroundColor: isDarkMode
                    ? Colors.white
                    : Theme.of(context).primaryColor,
                elevation: 0,
                title: Text(
                  provider.isLoading ||
                          provider.invoiceNumber.isEmpty ||
                          provider.invoiceNumber == 'Draft'
                      ? 'Invoice Details'
                      : provider.invoiceNumber,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                leading: IconButton(
                  icon: Icon(
                    HugeIcons.strokeRoundedArrowLeft01,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  onPressed: () => Navigator.of(context).pop(_hasChanges),
                ),
                actions: [
                  _buildRelatedSaleOrdersAppBarAction(provider, isDark),

                  if (provider.invoice != null &&
                      _canEditInvoice(provider.invoice!))
                    Container(
                      margin: const EdgeInsets.only(right: 0),
                      child: IconButton(
                        icon: Icon(
                          HugeIcons.strokeRoundedPencilEdit02,

                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[400]
                              : Colors.grey[600],
                        ),
                        tooltip: 'Edit Invoice',
                        onPressed:
                            (provider.isLoading ||
                                provider.invoiceNumber.isEmpty ||
                                provider.errorMessage.isNotEmpty)
                            ? null
                            : () async {
                                Map<String, dynamic>? completeInvoice;
                                try {
                                  final client =
                                      await OdooSessionManager.getClient();
                                  if (client != null) {
                                    final invoiceData = await client.callKw({
                                      'model': 'account.move',
                                      'method': 'read',
                                      'args': [
                                        [int.parse(widget.invoiceId)],
                                      ],
                                      'kwargs': {
                                        'fields': [
                                          'id',
                                          'name',
                                          'partner_id',
                                          'invoice_date',
                                          'invoice_date_due',
                                          'amount_total',
                                          'amount_untaxed',
                                          'amount_tax',
                                          'state',
                                          'narration',
                                          'currency_id',
                                          'invoice_line_ids',
                                        ],
                                      },
                                    });

                                    if (invoiceData is List &&
                                        invoiceData.isNotEmpty) {
                                      completeInvoice =
                                          Map<String, dynamic>.from(
                                            invoiceData[0],
                                          );
                                    }
                                  }
                                } catch (e) {
                                  completeInvoice = provider.invoice?.toJson();
                                }

                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CreateInvoiceScreen(
                                      invoiceToEdit:
                                          completeInvoice ??
                                          provider.invoice?.toJson(),
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
                                                Text('Updating invoice...'),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );

                                  try {
                                    await provider.fetchInvoiceDetails(
                                      context,
                                      widget.invoiceId,
                                    );

                                    if (mounted &&
                                        Navigator.of(context).canPop()) {
                                      Navigator.of(context).pop();

                                      await Future.delayed(
                                        Duration(milliseconds: 300),
                                      );

                                      if (mounted) {
                                        CustomSnackbar.showSuccess(
                                          context,
                                          'Invoice updated successfully',
                                        );

                                        widget.onInvoiceUpdated?.call();
                                      }
                                    }
                                  } catch (e) {
                                    if (mounted &&
                                        Navigator.of(context).canPop()) {
                                      Navigator.of(context).pop();
                                    }

                                    if (mounted) {
                                      CustomSnackbar.showError(
                                        context,
                                        'Failed to refresh invoice',
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
                    tooltip: 'More options',
                    enabled:
                        !provider.isLoading &&
                        provider.invoiceNumber.isNotEmpty &&
                        provider.errorMessage.isEmpty,
                    itemBuilder: (context) {
                      final phone =
                          provider.invoice?.customerPhone != null &&
                              provider.invoice!.customerPhone != 'false'
                          ? provider.invoice!.customerPhone
                          : 'Not available';

                      final hasPhoneNumber = phone != null && phone.isNotEmpty;

                      final isDraft =
                          provider.invoiceState.toLowerCase() == 'draft';
                      final isCancelled =
                          provider.invoiceState.toLowerCase() == 'cancel';
                      final isPosted =
                          provider.invoiceState.toLowerCase() == 'posted';
                      final canConfirm = isDraft;
                      final canCancel = [
                        'draft',
                        'posted',
                      ].contains(provider.invoiceState.toLowerCase());
                      final canResetToDraft = isCancelled || isPosted;
                      final isPaid =
                          provider.paymentState.toLowerCase() == 'paid';
                      final canRecordPayment =
                          !isDraft && !isCancelled && !isPaid;

                      return [
                        if (canConfirm)
                          PopupMenuItem<String>(
                            value: 'confirm_invoice',
                            child: Row(
                              children: [
                                Icon(
                                  HugeIcons.strokeRoundedCheckmarkCircle02,
                                  color: isDark
                                      ? Colors.grey[300]
                                      : Colors.grey[800],
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Confirm Invoice',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (canCancel)
                          PopupMenuItem<String>(
                            value: 'cancel_invoice',
                            child: Row(
                              children: [
                                Icon(
                                  HugeIcons.strokeRoundedCancel01,
                                  color: isDark
                                      ? Colors.grey[300]
                                      : Colors.grey[800],
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Cancel Invoice',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (canResetToDraft)
                          PopupMenuItem<String>(
                            value: 'reset_to_draft',
                            child: Row(
                              children: [
                                Icon(
                                  HugeIcons.strokeRoundedRefresh,
                                  color: isDark
                                      ? Colors.grey[300]
                                      : Colors.grey[800],
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Reset to Draft',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        PopupMenuItem<String>(
                          value: 'delete_invoice',
                          child: Row(
                            children: [
                              Icon(
                                HugeIcons.strokeRoundedDelete04,
                                color: isDark
                                    ? Colors.red[300]
                                    : Colors.red[600],
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Delete Invoice',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.red[200]
                                      : Colors.red[600],
                                  fontWeight: FontWeight.w500,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (canRecordPayment)
                          PopupMenuItem<String>(
                            value: 'record_payment',
                            child: Row(
                              children: [
                                Icon(
                                  HugeIcons.strokeRoundedPayment02,
                                  color: isDark
                                      ? Colors.grey[300]
                                      : Colors.grey[800],
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Record Payment',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        PopupMenuItem<String>(
                          value: 'print_invoice',
                          child: Row(
                            children: [
                              Icon(
                                HugeIcons.strokeRoundedFileDownload,
                                color: isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[800],
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Print Invoice',
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
                          value: 'send_invoice',
                          child: Row(
                            children: [
                              Icon(
                                HugeIcons.strokeRoundedShare08,
                                color: isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[800],
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Send Email',
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
                          enabled: hasPhoneNumber,
                          child: Row(
                            children: [
                              Icon(
                                HugeIcons.strokeRoundedWhatsapp,
                                color: hasPhoneNumber
                                    ? (isDark
                                          ? Colors.grey[300]
                                          : Colors.grey[800])
                                    : (isDark
                                          ? Colors.grey[600]
                                          : Colors.grey[400]),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Share via WhatsApp',
                                style: TextStyle(
                                  color: hasPhoneNumber
                                      ? (isDark ? Colors.white : Colors.black87)
                                      : (isDark
                                            ? Colors.grey[600]
                                            : Colors.grey[400]),
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
                      if (!provider.isLoading &&
                          provider.invoiceNumber.isNotEmpty &&
                          provider.errorMessage.isEmpty) {
                        final phone =
                            provider.invoice?.customerPhone != null &&
                                provider.invoice!.customerPhone != 'false'
                            ? provider.invoice!.customerPhone
                            : 'Contact Unavailable';

                        if (value == 'send_whatsapp' &&
                            (phone == null || phone.isEmpty)) {
                          if (context.mounted) {
                            CustomSnackbar.showError(
                              context,
                              'Cannot send via WhatsApp - no phone number available for customer',
                            );
                          }
                          return;
                        }

                        final isDark =
                            Theme.of(context).brightness == Brightness.dark;
                        final dialogContext = context;

                        if (value == 'confirm_invoice' ||
                            value == 'cancel_invoice' ||
                            value == 'reset_to_draft' ||
                            value == 'delete_invoice' ||
                            value == 'record_payment') {
                          try {
                            if (value == 'confirm_invoice') {
                              final ok = await provider.postInvoice(
                                context,
                                widget.invoiceId,
                              );
                              if (mounted) {
                                if (ok) {
                                  _showSafeSnackBar(
                                    'Invoice confirmed',
                                    backgroundColor: Colors.green,
                                  );
                                } else {
                                  _showSafeSnackBar(
                                    provider.errorMessage.isNotEmpty
                                        ? provider.errorMessage
                                        : 'Failed to confirm invoice',
                                    backgroundColor: Colors.red,
                                  );
                                }
                              }
                              return;
                            }

                            if (value == 'cancel_invoice') {
                              if (!_canWriteAccountMove) {
                                if (mounted) {
                                  CustomSnackbar.showError(
                                    context,
                                    'Permission Denied: You do not have permission to cancel invoices (account.move write). Please contact your administrator.',
                                  );
                                }
                                return;
                              }
                              final ok = await provider.cancelInvoice(
                                context,
                                widget.invoiceId,
                              );
                              if (mounted) {
                                if (ok) {
                                  _showSafeSnackBar(
                                    'Invoice cancelled',
                                    backgroundColor: Colors.green,
                                  );
                                } else {
                                  _showSafeSnackBar(
                                    provider.errorMessage.isNotEmpty
                                        ? provider.errorMessage
                                        : 'Failed to cancel invoice',
                                    backgroundColor: Colors.red,
                                  );
                                }
                              }
                              return;
                            }

                            if (value == 'reset_to_draft') {
                              if (!_canWriteAccountMove) {
                                if (mounted) {
                                  CustomSnackbar.showError(
                                    context,
                                    'Permission Denied: You do not have permission to reset invoices to draft (account.move write). Please contact your administrator.',
                                  );
                                }
                                return;
                              }
                              final ok = await provider.resetToDraft(
                                context,
                                widget.invoiceId,
                              );
                              if (mounted) {
                                if (ok) {
                                  _showSafeSnackBar(
                                    'Invoice reset to draft',
                                    backgroundColor: Colors.green,
                                  );
                                } else {
                                  _showSafeSnackBar(
                                    provider.errorMessage.isNotEmpty
                                        ? provider.errorMessage
                                        : 'Failed to reset invoice to draft',
                                    backgroundColor: Colors.red,
                                  );
                                }
                              }
                              return;
                            }

                            if (value == 'delete_invoice') {
                              if (!_canUnlinkAccountMove) {
                                if (mounted) {
                                  CustomSnackbar.showError(
                                    context,
                                    'Permission Denied: You do not have permission to delete invoices (account.move unlink). Please contact your administrator.',
                                  );
                                }
                                return;
                              }
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) {
                                  final isDarkDlg =
                                      Theme.of(ctx).brightness ==
                                      Brightness.dark;
                                  return AlertDialog(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    elevation: isDarkDlg ? 0 : 8,
                                    backgroundColor: isDarkDlg
                                        ? Colors.grey[900]
                                        : Colors.white,
                                    title: Text(
                                      'Delete Invoice',
                                      style: Theme.of(ctx).textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: isDarkDlg
                                                ? Colors.white
                                                : Theme.of(
                                                    ctx,
                                                  ).colorScheme.onSurface,
                                          ),
                                    ),
                                    content: Text(
                                      'Are you sure you want to delete this invoice? This action cannot be undone.',
                                      style: Theme.of(ctx).textTheme.bodyMedium
                                          ?.copyWith(
                                            color: isDarkDlg
                                                ? Colors.grey[300]
                                                : Theme.of(ctx)
                                                      .colorScheme
                                                      .onSurfaceVariant,
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
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(false),
                                              style: TextButton.styleFrom(
                                                foregroundColor: isDarkDlg
                                                    ? Colors.grey[400]
                                                    : Theme.of(ctx)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                              ),
                                              child: const Text(
                                                'Cancel',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(true),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.red[600],
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 20,
                                                      vertical: 12,
                                                    ),
                                                elevation: isDarkDlg ? 0 : 3,
                                              ),
                                              child: const Text(
                                                'Delete',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              );

                              if (confirmed == true) {
                                final ok = await provider.deleteInvoice(
                                  context,
                                  widget.invoiceId,
                                );
                                if (mounted) {
                                  if (ok) {
                                    _showSafeSnackBar(
                                      'Invoice deleted',
                                      backgroundColor: Colors.green,
                                    );
                                    Navigator.of(context).pop(true);
                                  } else {
                                    _showSafeSnackBar(
                                      provider.errorMessage.isNotEmpty
                                          ? provider.errorMessage
                                          : 'Failed to delete invoice',
                                      backgroundColor: Colors.red,
                                    );
                                  }
                                }
                              }
                              return;
                            }

                            if (value == 'record_payment') {
                              final invoice = Invoice(
                                id: int.tryParse(widget.invoiceId),
                                name: provider.invoiceNumber,
                                customerName: provider.customerName,
                                lines: const [],
                                taxLines: const [],
                                subtotal: provider.amountUntaxed,
                                taxAmount: provider.amountTax,
                                total: provider.invoiceAmount,
                                amountPaid:
                                    provider.invoiceAmount -
                                    provider.amountResidual,
                                amountResidual: provider.amountResidual,
                                status: provider.invoiceState,
                                paymentState: provider.paymentState,
                                invoiceDate: provider.invoiceDate,
                                dueDate: provider.dueDate,
                                currencyId: provider.invoice?.currencyId,
                                payments: _invoicePayments,
                              );

                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EnhancedPaymentScreen(
                                    invoice: invoice,
                                    existingPayments: _invoicePayments,
                                  ),
                                ),
                              );

                              if (mounted &&
                                  result is Map &&
                                  (result['success'] == true ||
                                      result['forceRefresh'] == true)) {
                                _lastManualRefreshTime = DateTime.now();
                                await _refreshPaymentStatus();
                              }
                              return;
                            }
                          } catch (e) {
                            if (mounted) {
                              _showSafeSnackBar(
                                'Operation failed: ${e.toString()}',
                                backgroundColor: Colors.red,
                              );
                            }
                          }
                          return;
                        }

                        showDialog(
                          context: context,
                          barrierDismissible: true,
                          builder: (dialogContext) {
                            return Dialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              backgroundColor: isDark
                                  ? Colors.grey[900]
                                  : Colors.white,
                              elevation: 8,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 28,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Align(
                                      alignment: Alignment.topRight,
                                      child: IconButton(
                                        icon: const Icon(Icons.close),
                                        onPressed: () =>
                                            Navigator.of(dialogContext).pop(),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        iconSize: 20,
                                        color: isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[600],
                                      ),
                                    ),
                                    Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white.withOpacity(0.12)
                                            : const Color(
                                                0xFF1E88E5,
                                              ).withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child:
                                          LoadingAnimationWidget.fourRotatingDots(
                                            color: isDark
                                                ? Colors.white
                                                : const Color(0xFF1E88E5),
                                            size: 32,
                                          ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      value == 'send_invoice'
                                          ? 'Sending Invoice'
                                          : value == 'send_whatsapp'
                                          ? 'Sending via WhatsApp'
                                          : 'Generating PDF',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.grey[900],
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      value == 'send_invoice'
                                          ? 'Please wait while we send your invoice'
                                          : value == 'send_whatsapp'
                                          ? 'Please wait while we send your invoice via WhatsApp'
                                          : 'Please wait while we prepare your document',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: isDark
                                                ? Colors.grey[400]
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

                        try {
                          final invoiceData = provider.invoice;

                          int? invoiceId;
                          if (invoiceData?.id is int) {
                            invoiceId = invoiceData?.id as int;
                          } else if (invoiceData?.id is String) {
                            invoiceId = int.tryParse(invoiceData?.id as String);
                          }

                          if (invoiceId == null) {
                            throw Exception(
                              'Invalid invoice ID format: ${invoiceData?.id}',
                            );
                          }

                          if (value == 'send_invoice') {
                            try {
                              await InvoiceService.instance.sendInvoice(
                                dialogContext,
                                invoiceId,
                                closeLoadingDialog: () {
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                },
                              );
                            } catch (e) {
                              if (mounted) {
                                _showErrorDialog(
                                  'Send Email Failed',
                                  e.toString(),
                                );
                              }
                            }
                          } else if (value == 'send_whatsapp') {
                            await PDFGenerator.sendInvoiceViaWhatsApp(
                              dialogContext,
                              provider.invoice!,
                            );

                            try {
                              if (mounted && Navigator.of(context).canPop()) {
                                Navigator.of(
                                  context,
                                  rootNavigator: true,
                                ).pop();
                              }
                            } catch (e) {}
                          } else {
                            try {
                              await PDFGenerator.generateInvoicePdf(
                                dialogContext,
                                provider.invoice!,
                              );
                            } catch (e) {
                              if (mounted) {
                                CustomSnackbar.showError(
                                  context,
                                  'PDF generation failed: ${e.toString()}',
                                );
                              }
                            } finally {
                              try {
                                if (mounted &&
                                    Navigator.of(
                                      context,
                                      rootNavigator: true,
                                    ).canPop()) {
                                  Navigator.of(
                                    context,
                                    rootNavigator: true,
                                  ).pop();
                                }
                              } catch (e) {}
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            CustomSnackbar.showError(
                              context,
                              'Operation failed: ${e.toString()}',
                            );
                          }
                        }
                      }
                    },
                  ),
                ],
              ),
              body: provider.isLoading || provider.invoiceNumber.isEmpty
                  ? ListShimmer.buildInvoiceDetailsShimmer(context)
                  : provider.errorMessage.isNotEmpty
                  ? _buildErrorState(provider)
                  : Column(
                      children: [
                        Expanded(
                          child: RefreshIndicator(
                            color: primaryColor,
                            onRefresh: () =>
                                _loadInvoiceData(forceRefresh: true),
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(20.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildTopSection(
                                      provider,
                                      provider.customerName.isNotEmpty
                                          ? provider.customerName
                                          : 'Unknown Customer',
                                      _extractCustomerAddress(
                                        provider.invoiceData,
                                      ),
                                      _extractCustomerPhone(
                                        provider.invoiceData,
                                      ),
                                      _extractCustomerEmail(
                                        provider.invoiceData,
                                      ),
                                      isDark,
                                      primaryColor,
                                    ),
                                    const SizedBox(height: 12),

                                    _buildTabsSection(provider, isDark),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        _buildStaticTotalSection(provider, isDark),
                      ],
                    ),
            ),

            if (provider.isProcessing)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF212121) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LoadingAnimationWidget.fourRotatingDots(
                          color: primaryColor,
                          size: 40,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Processing...',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.grey[900],
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildRelatedSaleOrdersSection(
    InvoiceDetailsProvider provider,
    bool isDark,
  ) {
    final relatedSaleOrders = _getMockRelatedSaleOrders(provider);

    if (relatedSaleOrders.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildSectionCard(
      title: 'Related Sale Orders',
      icon: HugeIcons.strokeRoundedShoppingCart01,
      iconColor: isDark ? Colors.white70 : Colors.blue[600],
      children: [
        ...relatedSaleOrders.map(
          (order) => _buildRelatedDocumentCard(
            title: order['name'] ?? 'Unknown',
            subtitle: 'Status: ${order['state'] ?? 'Unknown'}',
            amount: order['amount_total']?.toString() ?? '0.00',
            date: order['date_order'] ?? '',
            onTap: () => _navigateToSaleOrder(order),
            isDark: isDark,
            icon: HugeIcons.strokeRoundedShoppingCart02,
          ),
        ),
      ],
    );
  }

  Widget _buildRelatedDocumentCard({
    required String title,
    required String subtitle,
    required String amount,
    required String date,
    required VoidCallback onTap,
    required bool isDark,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white
                                  : AppTheme.primaryColor,
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 0,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isDark
                                    ? Colors.green[300]!
                                    : Colors.green[600]!,
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.transparent,
                            ),
                            child: Text(
                              double.tryParse(amount)?.toStringAsFixed(2) ??
                                  amount,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.green[300]
                                    : Colors.green[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? Colors.grey[400]
                              : Color(0xff000000).withOpacity(.4),
                        ),
                      ),

                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Date: $date',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Color(0xff000000).withOpacity(.4),
                            ),
                          ),
                          Icon(
                            HugeIcons.strokeRoundedArrowRight01,
                            size: 16,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getMockRelatedSaleOrders(
    InvoiceDetailsProvider provider,
  ) {
    final origin = provider.invoiceOrigin;
    if (origin.isNotEmpty && origin != 'false') {
      return [{}];
    }
    return [];
  }

  void _navigateToSaleOrder(Map<String, dynamic> saleOrder) {
    NavigationHelper.navigateToSaleOrder(
      context,
      saleOrder,
      replaceCurrentPage: true,
    );
  }

  bool _invoiceDataIsValid(Map? invoiceData) {
    if (invoiceData == null || invoiceData.isEmpty) return false;
    return invoiceData.containsKey('id') && invoiceData.containsKey('state');
  }

  Widget _buildInvoiceLinesTable(InvoiceDetailsProvider provider, bool isDark) {
    if (provider.invoiceLines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'No invoice lines found.',
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
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(right: 0, bottom: 0),

              child: Theme(
                data: Theme.of(context).copyWith(
                  scrollbarTheme: ScrollbarThemeData(
                    thumbVisibility: WidgetStateProperty.all(true),
                    trackVisibility: WidgetStateProperty.all(true),
                    thickness: WidgetStateProperty.all(3),
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
                    crossAxisMargin: 2,
                    mainAxisMargin: 4,
                  ),
                ),
                child: Scrollbar(
                  controller: verticalController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  interactive: true,
                  thickness: 6,
                  radius: const Radius.circular(5),
                  child: Scrollbar(
                    controller: horizontalController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    interactive: true,
                    thickness: 6,
                    radius: const Radius.circular(5),
                    notificationPredicate: (ScrollNotification notification) {
                      return notification.depth == 1;
                    },
                    child: SingleChildScrollView(
                      controller: verticalController,
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        controller: horizontalController,
                        scrollDirection: Axis.horizontal,
                        child: Container(
                          margin: const EdgeInsets.all(0),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF2D2D2D)
                                : Colors.white,
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
                                color: isDark
                                    ? Colors.grey[700]!
                                    : Colors.grey[300]!,
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Table(
                              border: TableBorder(
                                horizontalInside: BorderSide(
                                  color: isDark
                                      ? Colors.grey[700]!
                                      : Colors.grey[300]!,
                                  width: 1,
                                ),
                              ),
                              columnWidths: const {
                                0: FixedColumnWidth(200),
                                1: FixedColumnWidth(140),
                                2: FixedColumnWidth(80),
                                3: FixedColumnWidth(130),
                                4: FixedColumnWidth(130),
                                5: FixedColumnWidth(120),
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
                                          'UoM',
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
                                          'Price',
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
                                          'Discount %',
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
                                          'Total',
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

                                ...provider.invoiceLines.asMap().entries.map((
                                  entry,
                                ) {
                                  final index = entry.key;
                                  final line = entry.value;

                                  final productId = line['product_id'];
                                  final productName =
                                      productId is List && productId.length > 1
                                      ? productId[1].toString()
                                      : line['name']?.toString() ??
                                            'Unknown Product';

                                  final quantity = (line['quantity'] ?? 0.0)
                                      .toDouble();
                                  final priceUnit = (line['price_unit'] ?? 0.0)
                                      .toDouble();
                                  final discount = (line['discount'] ?? 0.0)
                                      .toDouble();
                                  final priceSubtotal =
                                      (line['price_subtotal'] ?? 0.0)
                                          .toDouble();

                                  final uomId = line['product_uom_id'];
                                  final uomName =
                                      (uomId is List && uomId.length > 1)
                                      ? uomId[1].toString()
                                      : '';

                                  String taxInfo = 'No Tax';

                                  if (line['tax_details'] is List &&
                                      (line['tax_details'] as List)
                                          .isNotEmpty) {
                                    final taxDetails =
                                        line['tax_details'] as List;
                                    final Set<String> uniqueTaxNames =
                                        <String>{};

                                    for (var tax in taxDetails) {
                                      if (tax is Map<String, dynamic>) {
                                        final name =
                                            tax['name']?.toString() ?? '';

                                        if (name.isNotEmpty) {
                                          uniqueTaxNames.add(name);
                                        }
                                      }
                                    }

                                    if (uniqueTaxNames.isNotEmpty) {
                                      taxInfo = uniqueTaxNames.join(', ');
                                    }
                                  } else if (line['tax_ids'] is List &&
                                      (line['tax_ids'] as List).isNotEmpty) {
                                    final taxIds = line['tax_ids'] as List;
                                    final Set<String> uniqueTaxNames =
                                        <String>{};

                                    for (var taxId in taxIds) {
                                      if (taxId is List && taxId.length > 1) {
                                        uniqueTaxNames.add(taxId[1].toString());
                                      }
                                    }

                                    if (uniqueTaxNames.isNotEmpty) {
                                      taxInfo = uniqueTaxNames.join(', ');
                                    } else {
                                      taxInfo = 'Tax Applied';
                                    }
                                  }

                                  return TableRow(
                                    children: [
                                      TableCell(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
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
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryColor,
                                                borderRadius:
                                                    BorderRadius.circular(12),
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
                                          child: Text(
                                            uomName.isNotEmpty ? uomName : '-',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              color: isDark
                                                  ? Colors.grey[300]
                                                  : Colors.grey[700],
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),

                                      TableCell(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          child: Consumer<CurrencyProvider>(
                                            builder:
                                                (context, currencyProvider, _) {
                                                  final currencyId = provider
                                                      .invoiceData['currency_id'];
                                                  final currencyCode =
                                                      (currencyId is List &&
                                                          currencyId.length > 1)
                                                      ? currencyId[1].toString()
                                                      : null;

                                                  return Text(
                                                    currencyProvider
                                                        .formatAmount(
                                                          priceUnit,
                                                          currency:
                                                              currencyCode,
                                                        ),
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: isDark
                                                          ? Colors.grey[300]
                                                          : Colors.grey[700],
                                                    ),
                                                  );
                                                },
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
                                            discount > 0
                                                ? '${discount.toStringAsFixed(1)}%'
                                                : '-',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              color: discount > 0
                                                  ? (isDark
                                                        ? Colors.green[300]
                                                        : Colors.green[600])
                                                  : (isDark
                                                        ? Colors.grey[300]
                                                        : Colors.grey[700]),
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
                                            taxInfo,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              color: isDark
                                                  ? Colors.grey[300]
                                                  : Colors.grey[700],
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),

                                      TableCell(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          child: Consumer<CurrencyProvider>(
                                            builder:
                                                (context, currencyProvider, _) {
                                                  final currencyId = provider
                                                      .invoiceData['currency_id'];
                                                  final currencyCode =
                                                      (currencyId is List &&
                                                          currencyId.length > 1)
                                                      ? currencyId[1].toString()
                                                      : null;

                                                  return Text(
                                                    currencyProvider
                                                        .formatAmount(
                                                          priceSubtotal,
                                                          currency:
                                                              currencyCode,
                                                        ),
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: isDark
                                                          ? Colors.white
                                                          : Colors.grey[800],
                                                    ),
                                                  );
                                                },
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
              ),
            ),
          ),
        ],
      ),
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

  Widget _buildTabsSection(InvoiceDetailsProvider provider, bool isDark) {
    return Container(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(
              top: 0,
              bottom: 16,
              left: 16,
              right: 16,
            ),
            child: Container(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTabItem(
                      'Invoice Lines ${provider.invoiceLines.length}',
                      0,
                      isDark,
                      enabled: true,
                    ),
                    const SizedBox(width: 8),
                    _buildTabItem('Other Info', 1, isDark, enabled: true),
                  ],
                ),
              ),
            ),
          ),

          Container(
            margin: EdgeInsets.symmetric(horizontal: 0),
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
            height: _calculateTableHeight(provider.invoiceLines.length),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildInvoiceLinesTable(provider, isDark),

                  _buildOtherInfoContent(isDark),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(
    String text,
    int index,
    bool isDark, {
    bool enabled = true,
  }) {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, child) {
        final isCurrentlySelected = _tabController.index == index;
        return GestureDetector(
          onTap: enabled
              ? () {
                  _tabController.animateTo(index);
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: isCurrentlySelected
                  ? Colors.black
                  : (enabled
                        ? Colors.white
                        : (isDark ? Colors.grey[850] : Colors.grey[100])),
              border: Border.all(
                color: isCurrentlySelected
                    ? Colors.black
                    : (enabled
                          ? (isDark ? Colors.grey[600]! : Colors.grey[300]!)
                          : (isDark ? Colors.grey[700]! : Colors.grey[300]!)),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: isCurrentlySelected
                    ? Colors.white
                    : (enabled
                          ? (isDark ? Colors.grey[400] : Colors.grey[700])
                          : (isDark ? Colors.grey[600] : Colors.grey[500])),
                fontSize: 15,
                fontWeight: isCurrentlySelected
                    ? FontWeight.bold
                    : FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
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
        if (mounted) {
          setState(() {
            _isLoadingAdditionalInfo = false;
          });
        }
        return;
      }

      final List<String> fieldsToFetch = [
        'ref',
        'invoice_user_id',
        'team_id',
        'partner_bank_id',
        'payment_reference',
        'delivery_date',
        'invoice_incoterm_id',
        'incoterm_location',
        'fiscal_position_id',
        'secured',
        'preferred_payment_method_line_id',
        'auto_post',
        'checked',
        'campaign_id',
        'medium_id',
        'source_id',
      ];

      if (invalidFields != null && invalidFields.isNotEmpty) {
        fieldsToFetch.removeWhere((field) => invalidFields.contains(field));
      }

      final result = await client.callKw({
        'model': 'account.move',
        'method': 'read',
        'args': [
          [int.parse(widget.invoiceId)],
        ],
        'kwargs': {'fields': fieldsToFetch},
      });

      if (result != null && result.isNotEmpty) {
        if (mounted) {
          setState(() {
            _additionalInfo = Map<String, dynamic>.from(result[0]);
            _isLoadingAdditionalInfo = false;
          });
        }
      }
    } catch (e) {
      if (e.toString().contains('Invalid field') &&
          e.toString().contains('account.move')) {
        final fieldMatch = RegExp(
          r"Invalid field '([^']+)'",
        ).firstMatch(e.toString());
        if (fieldMatch != null) {
          final invalidField = fieldMatch.group(1);

          final List<String> allInvalidFields = List.from(invalidFields ?? []);
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

      if (mounted) {
        setState(() {
          _isLoadingAdditionalInfo = false;
        });
      }
    }
  }

  String _formatDateInvoice(dynamic dateString) {
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

  String _safeStringInvoice(dynamic value) {
    if (value == null || value == false) return '';
    if (value is bool) return '';
    if (value is List && value.length > 1) {
      return value[1].toString();
    }
    return value.toString();
  }

  String _formatBooleanInvoice(dynamic value) {
    if (value == null || value == false) return 'No';
    if (value == true) return 'Yes';
    return value.toString();
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

    final data = _additionalInfo;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoSection('INVOICE', isDark, [
            ('Customer Reference', _safeStringInvoice(data['ref'])),
            ('Salesperson', _safeStringInvoice(data['invoice_user_id'])),
            ('Sales Team', _safeStringInvoice(data['team_id'])),
            ('Recipient Bank', _safeStringInvoice(data['partner_bank_id'])),
            (
              'Payment Reference',
              _safeStringInvoice(data['payment_reference']),
            ),
            ('Delivery Date', _formatDateInvoice(data['delivery_date'])),
          ]),
          const SizedBox(height: 20),

          _buildInfoSection('ACCOUNTING', isDark, [
            ('Incoterm', _safeStringInvoice(data['invoice_incoterm_id'])),
            (
              'Incoterm Location',
              _safeStringInvoice(data['incoterm_location']),
            ),
            ('Fiscal Position', _safeStringInvoice(data['fiscal_position_id'])),
            ('Secured', _formatBooleanInvoice(data['secured'])),
            (
              'Payment Method',
              _safeStringInvoice(data['preferred_payment_method_line_id']),
            ),
            ('Auto-post', _formatBooleanInvoice(data['auto_post'])),
            ('Checked', _formatBooleanInvoice(data['checked'])),
          ]),
          const SizedBox(height: 20),

          _buildInfoSection('MARKETING', isDark, [
            ('Campaign', _safeStringInvoice(data['campaign_id'])),
            ('Medium', _safeStringInvoice(data['medium_id'])),
            ('Source', _safeStringInvoice(data['source_id'])),
          ]),
        ],
      ),
    );
  }

  Widget _buildInfoSection(
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
                _buildOtherInfoRow(
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

  Widget _buildOtherInfoRow(
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
          _showFieldInfo(label, value);
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

  void _showFieldInfo(String label, String value) {
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
      ..strokeWidth = 2;

    double startY = 0;
    while (startY < size.height) {
      canvas.drawLine(Offset(0, startY), Offset(0, startY + dashHeight), paint);
      startY += dashHeight + dashSpace;
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

String _safeString(dynamic value) {
  if (value == null || value == false) return '';
  if (value is List && value.isNotEmpty) {
    return value[1]?.toString() ?? '';
  }
  return value.toString();
}

String _getInvoiceNumber(Map<String, dynamic> invoiceData) {
  final name = invoiceData['name'];
  if (name == null || name == false || name.toString().trim().isEmpty) {
    return 'Draft';
  }
  return name.toString();
}

String _getPaymentTerms(Map<String, dynamic> invoice) {
  final paymentTermId = invoice['invoice_payment_term_id'];
  if (paymentTermId != null &&
      paymentTermId is List &&
      paymentTermId.length > 1) {
    return paymentTermId[1].toString();
  }
  return '30 Days';
}

String _formatDate(String? dateString) {
  if (dateString == null ||
      dateString.isEmpty ||
      dateString == 'null' ||
      dateString == 'false' ||
      dateString == 'true') {
    return 'Not specified';
  }
  try {
    final date = DateTime.parse(dateString);
    return DateFormat('MMM dd, yyyy').format(date);
  } catch (e) {
    return 'Not specified';
  }
}

String _getInvoiceState(String? state) {
  switch (state) {
    case 'draft':
      return 'Draft';
    case 'posted':
      return 'Posted';
    case 'paid':
      return 'Paid';
    case 'cancel':
      return 'Cancelled';
    default:
      return 'Unknown';
  }
}

Color _getStateColor(String? state) {
  switch (state) {
    case 'draft':
      return const Color(0xFF6C757D);
    case 'posted':
      return const Color(0xFF007BFF);
    case 'paid':
      return const Color(0xFF28A745);
    case 'cancel':
      return const Color(0xFFDC3545);
    default:
      return const Color(0xFF6C757D);
  }
}

Color _getPaymentStateColor(String? paymentState) {
  switch (paymentState) {
    case 'paid':
      return const Color(0xFF28A745);
    case 'in_payment':
      return const Color(0xFF007BFF);
    case 'partial':
      return const Color(0xFFFFC107);
    case 'reversed':
      return const Color(0xFF6F42C1);
    case 'blocked':
      return const Color(0xFFDC3545);
    default:
      return const Color(0xFF6C757D);
  }
}

String _getPaymentStateLabel(String? paymentState) {
  switch (paymentState) {
    case 'paid':
      return 'PAID';
    case 'in_payment':
      return 'IN PAYMENT';
    case 'partial':
      return 'PARTIALLY PAID';
    case 'reversed':
      return 'REVERSED';
    case 'blocked':
      return 'BLOCKED';
    default:
      return 'UNKNOWN';
  }
}

Contact? _customerDetails;
bool _isLoadingCustomerDetails = false;

Future<void> _fetchCustomerDetails(Invoice invoice) async {
  if (_isLoadingCustomerDetails) return;

  final partnerId = invoice.customerId;
  if (partnerId == null) return;

  final customerIdToFetch = partnerId;

  _isLoadingCustomerDetails = true;

  try {
    final sessionService = SessionService();
    final client = await sessionService.client;

    if (client == null) return;

    List<String> fieldsToFetch = [
      'id',
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
      'is_company',
      'parent_id',
      'vat',
    ];

    var result;

    try {
      result = await client
          .callKw({
            'model': 'res.partner',
            'method': 'search_read',
            'args': [
              [
                ['id', '=', customerIdToFetch],
              ],
              fieldsToFetch,
            ],
            'kwargs': {},
          })
          .timeout(const Duration(seconds: 10));
    } catch (fieldError) {
      if (fieldError.toString().contains('mobile')) {
        fieldsToFetch.remove('mobile');

        result = await client
            .callKw({
              'model': 'res.partner',
              'method': 'search_read',
              'args': [
                [
                  ['id', '=', customerIdToFetch],
                ],
                fieldsToFetch,
              ],
              'kwargs': {},
            })
            .timeout(const Duration(seconds: 10));
      } else {
        rethrow;
      }
    }

    if (result.isNotEmpty) {
      final customerData = result[0];
      _customerDetails = Contact.fromJson(customerData);
    }
  } finally {
    _isLoadingCustomerDetails = false;
  }
}

String? _extractCustomerAddress(Map<String, dynamic> invoiceData) {
  final c = _customerDetails;
  if (c == null) return null;

  bool isReal(String? v) =>
      v != null && v.trim().isNotEmpty && v.trim().toLowerCase() != 'false';

  final addressParts = [
    c.street,
    c.street2,
    c.city,
    c.state,
    c.zip,
  ].where((part) => isReal(part)).toList();

  return addressParts.isNotEmpty ? addressParts.join(', ') : null;
}

String? _extractCustomerPhone(Map<String, dynamic> invoiceData) {
  final c = _customerDetails;
  if (c == null) return null;

  bool isReal(String? v) =>
      v != null && v.trim().isNotEmpty && v.trim().toLowerCase() != 'false';

  return isReal(c.phone) ? c.phone : (isReal(c.mobile) ? c.mobile : null);
}

String? _extractCustomerEmail(Map<String, dynamic> invoiceData) {
  final c = _customerDetails;
  if (c == null) return null;

  bool isReal(String? v) =>
      v != null && v.trim().isNotEmpty && v.trim().toLowerCase() != 'false';

  return isReal(c.email) ? c.email : null;
}

String? _extractCustomerVat(Map<String, dynamic> invoiceData) {
  final c = _customerDetails;
  if (c == null) return null;

  bool isReal(String? v) =>
      v != null && v.trim().isNotEmpty && v.trim().toLowerCase() != 'false';

  return isReal(c.vat) ? c.vat : null;
}

Widget _buildTopSection(
  InvoiceDetailsProvider provider,
  String displayName,
  String? address,
  String? phone,
  String? email,
  bool isDark,
  Color primaryColor,
) {
  final invoiceData = provider.invoiceData;
  final state = invoiceData['state']?.toString();
  final paymentState = invoiceData['payment_state']?.toString();

  return Stack(
    children: [
      Container(
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
                  _getInvoiceNumber(invoiceData),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getStateColor(state).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _getInvoiceState(state),
                    style: TextStyle(
                      color: _getStateColor(state),
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

            if (_extractCustomerVat(invoiceData) != null) ...[
              const SizedBox(height: 4),
              Text(
                '${_customerDetails?.country ?? 'Country'} – ${_extractCustomerVat(invoiceData)}',
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
                  'Payment Terms : ${_getPaymentTerms(invoiceData)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[300] : Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(invoiceData['invoice_date']?.toString()),
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
      ),

      if (paymentState != null &&
          paymentState != 'not_paid' &&
          paymentState != 'invoicing_legacy')
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _getPaymentStateColor(paymentState),
              borderRadius: const BorderRadius.only(
                bottomRight: Radius.circular(16),
                topLeft: Radius.circular(16),
              ),
            ),
            child: Text(
              _getPaymentStateLabel(paymentState),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
    ],
  );
}

Widget _buildStaticTotalSection(InvoiceDetailsProvider provider, bool isDark) {
  final currencyId = provider.invoice?.currencyId;
  final String? currencyCode = (currencyId is List && currencyId.length > 1)
      ? currencyId[1].toString()
      : null;

  final untaxedAmount = provider.amountUntaxed;
  final taxAmount = provider.amountTax;
  final totalAmount = provider.invoiceAmount;

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
