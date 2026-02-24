import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/widgets/custom_snackbar.dart';
import 'package:mobo_sales/widgets/order_like_list_tile.dart';
import '../../utils/app_theme.dart';
import 'create_invoice_screen.dart';
import '../../providers/currency_provider.dart';
import 'invoice_details_screen.dart';
import '../../services/field_validation_service.dart';
import '../../services/odoo_session_manager.dart';
import '../../services/connectivity_service.dart';
import '../../services/session_service.dart';
import '../../utils/date_picker_utils.dart';
import '../../widgets/connection_status_widget.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/list_shimmer.dart';
import '../../models/invoice.dart';

class InvoiceListScreen extends StatefulWidget {
  final int? customerId;
  final bool overdueOnly;
  final bool unpaidOnly;
  final String? saleOrderName;
  const InvoiceListScreen({
    super.key,
    this.customerId,
    this.overdueOnly = false,
    this.unpaidOnly = false,
    this.saleOrderName,
  });

  static void clearInvoiceCache() {
    InvoiceListScreenState.clearStaticCache();
  }

  @override
  State<InvoiceListScreen> createState() => InvoiceListScreenState();
}

class InvoiceListScreenState extends State<InvoiceListScreen>
    with AutomaticKeepAliveClientMixin {
  List<Invoice>? _invoices;
  bool _isLoading = true;
  bool _isInitialized = false;
  bool _isServerUnreachable = false;
  String _searchQuery = '';
  static const double _smallPadding = 8.0;
  static const double _tinyPadding = 4.0;
  static const double _standardPadding = 16.0;
  static const double _cardBorderRadius = 12.0;
  static const int _pageSize = 40;
  int _currentPage = 0;
  bool _hasMoreData = true;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  int _totalInvoices = 0;

  int get pageSize => _pageSize;

  int get currentPage => _currentPage;

  int get currentStartIndex => (_currentPage * _pageSize) + 1;

  int get currentEndIndex => _invoices?.length ?? 0;

  int get totalPages =>
      _totalInvoices > 0 ? ((_totalInvoices - 1) ~/ _pageSize) + 1 : 0;

  bool get canGoToPreviousPage => _currentPage > 0;

  bool get canGoToNextPage => _hasMoreData;

  String getPaginationText() {
    if (_totalInvoices == 0 && (_invoices?.isEmpty ?? true)) return "0 items";
    if (_totalInvoices == 0) return "${_invoices?.length ?? 0} items";

    final pageStart = (_currentPage * _pageSize) + 1;

    final expectedPageEnd = (_currentPage + 1) * _pageSize;
    final pageEnd = expectedPageEnd > _totalInvoices
        ? _totalInvoices
        : expectedPageEnd;
    return "$pageStart-$pageEnd/$_totalInvoices";
  }

  Future<void> goToPage(int page) async {
    if (page < 0 || page == _currentPage) return;

    _currentPage = page;
    await _fetchInvoices();
  }

  Future<void> goToNextPage() async {
    if (!canGoToNextPage) return;
    _currentPage++;
    await _fetchInvoices();
  }

  Future<void> goToPreviousPage() async {
    if (!canGoToPreviousPage) return;
    _currentPage--;
    await _fetchInvoices();
  }

  final TextEditingController _searchController = TextEditingController();
  bool _isManualRefresh = false;
  bool _showScrollToTop = false;

  Set<String> _activeFilters = {};
  DateTime? _startDate;
  DateTime? _endDate;

  String? _selectedGroupBy;
  bool _isGrouped = false;

  Map<String, int> _groupSummary = {};

  Map<String, List<Invoice>> _loadedGroups = {};

  Map<String, int> _cachedGroupSummary = {};
  Map<String, List<Invoice>> _cachedLoadedGroups = {};
  String? _cachedGroupByField;

  final Map<String, bool> _expandedGroups = {};
  bool _allGroupsExpanded = false;

  static List<Invoice> _cachedInvoices = [];
  static int _cachedTotalCount = 0;
  static DateTime? _lastFetchTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  static void clearStaticCache() {
    _cachedInvoices.clear();
    _cachedTotalCount = 0;
    _lastFetchTime = null;
    _savedFilters.clear();
    _savedStartDate = null;
    _savedEndDate = null;
    _savedGroupBy = null;
    _savedSearchQuery = '';
  }

  static Set<String> _savedFilters = {};
  static DateTime? _savedStartDate;
  static DateTime? _savedEndDate;
  static String? _savedGroupBy;
  static String _savedSearchQuery = '';

  static const Map<String, String> _invoiceStatusFilters = {
    'draft': 'Draft',
    'posted': 'Posted',
    'paid': 'Paid',
    'partial': 'Partially Paid',
    'not_paid': 'Not Paid',
    'in_payment': 'In Payment',
    'reversed': 'Reversed',
    'blocked': 'Blocked',
    'cancelled': 'Cancelled',
  };

  @override
  bool get wantKeepAlive => true;

  String? _accessErrorMessage;

  bool _isServerUnreachableError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('socketexception') ||
        errorString.contains('connection refused') ||
        errorString.contains('connection timeout') ||
        errorString.contains('host unreachable') ||
        errorString.contains('no route to host') ||
        errorString.contains('network is unreachable') ||
        errorString.contains('failed to connect') ||
        errorString.contains('connection failed') ||
        errorString.contains('server returned html instead of json') ||
        errorString.contains('server may be down') ||
        errorString.contains('url incorrect') ||
        errorString.contains('odoo server error') ||
        errorString.contains('unexpected response') ||
        errorString.contains('404') ||
        errorString.contains('not found') ||
        errorString.contains('500') ||
        errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('504');
  }

  String _getErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('valueerror')) {
      return 'Invalid search or filter criteria';
    } else if (errorString.contains('odooexception')) {
      return 'Failed to connect to Odoo server';
    } else if (errorString.contains('socketexception')) {
      return 'Network connection error';
    } else if (errorString.contains('timeout')) {
      return 'Request timed out';
    } else if (errorString.contains('session')) {
      return 'Session expired or invalid';
    } else {
      return 'An unexpected error occurred';
    }
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

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_isInitialized) {
      final isContextual =
          widget.customerId != null || widget.overdueOnly || widget.unpaidOnly;
      if (!isContextual) {
        _activeFilters = Set.from(_savedFilters);
        _startDate = _savedStartDate;
        _endDate = _savedEndDate;
        _selectedGroupBy = _savedGroupBy;
        _isGrouped = _selectedGroupBy != null;
        _searchQuery = _savedSearchQuery;
        _searchController.text = _savedSearchQuery;

        if (_selectedGroupBy != null &&
            _selectedGroupBy == _cachedGroupByField &&
            _cachedGroupSummary.isNotEmpty) {
          _groupSummary = Map.from(_cachedGroupSummary);
          _loadedGroups = Map.from(_cachedLoadedGroups);
        }
      }
      _initializeAndFetch();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {});
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMoreData) {
      _loadMoreData();
    }

    final shouldShow = _scrollController.offset > 300;
    if (shouldShow != _showScrollToTop) {
      setState(() {
        _showScrollToTop = shouldShow;
      });
    }
  }

  void _onSearchChanged() {
    final newText = _searchController.text.trim();

    if (newText == _searchQuery) return;

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _searchQuery = newText;
        _currentPage = 0;
        _hasMoreData = true;
        _invoices = null;
      });

      final isContextual =
          widget.customerId != null || widget.overdueOnly || widget.unpaidOnly;
      if (!isContextual) {
        _savedSearchQuery = _searchQuery;
      }

      _fetchInvoices();
    });
  }

  Future<void> _loadMoreData() async {
    if (!_hasMoreData || _isLoadingMore) return;
    if (!mounted) return;
    setState(() {
      _isLoadingMore = true;
    });
    _currentPage++;
    await _fetchInvoices(isLoadMore: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();

    try {
      final isContextual =
          widget.customerId != null ||
          widget.overdueOnly ||
          widget.unpaidOnly ||
          widget.saleOrderName != null;
      if (isContextual) {
        _savedFilters.clear();
        _savedStartDate = null;
        _savedEndDate = null;
        _savedGroupBy = null;

        _cachedInvoices.clear();
        _cachedTotalCount = 0;
        _lastFetchTime = null;
      }
    } catch (_) {}
    super.dispose();
  }

  Future<void> _initializeAndFetch() async {
    final bool isDefaultView =
        _searchQuery.isEmpty &&
        widget.customerId == null &&
        !widget.overdueOnly &&
        !widget.unpaidOnly &&
        widget.saleOrderName == null;
    if (isDefaultView &&
        !_isManualRefresh &&
        _cachedInvoices.isNotEmpty &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
      setState(() {
        _invoices = List.from(_cachedInvoices);
        _totalInvoices = _cachedTotalCount;
        _isInitialized = true;
        _isLoading = false;
        _isLoadingMore = false;

        _hasMoreData = (_currentPage + 1) * _pageSize < _cachedTotalCount;
      });
      return;
    }

    if (_isInitialized && !_isManualRefresh) {
      return;
    }

    try {
      final connectivityService = context.read<ConnectivityService>();
      final sessionService = context.read<SessionService>();

      if (connectivityService.isConnected && sessionService.hasValidSession) {
        await _fetchInvoices();
      }
    } catch (e) {
      _showErrorSnackBar('Failed to initialize');
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isManualRefresh = false;
      });
    }
  }

  Future<void> _fetchInvoices({bool isLoadMore = false}) async {
    try {
      if (!isLoadMore) {
        if (!mounted) return;
        setState(() {
          _isLoading = true;
          _accessErrorMessage = null;
          _isServerUnreachable = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _isLoadingMore = true;
        });
      }

      List<dynamic> domain = [
        [
          'move_type',
          'in',
          ['out_invoice', 'out_refund'],
        ],
      ];

      if (widget.customerId != null) {
        domain.add(['partner_id', '=', widget.customerId]);
      }

      if (widget.saleOrderName != null && widget.saleOrderName!.isNotEmpty) {
        domain.add(['invoice_origin', 'ilike', widget.saleOrderName!.trim()]);
      }

      if (widget.overdueOnly) {
        final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        domain.addAll([
          ['state', '=', 'posted'],
          [
            'payment_state',
            'in',
            ['not_paid', 'partial'],
          ],
          ['invoice_date_due', '<', todayStr],
        ]);
      }

      if (widget.unpaidOnly) {
        domain.addAll([
          ['state', '=', 'posted'],
          [
            'payment_state',
            'in',
            ['not_paid', 'partial'],
          ],
        ]);
      }

      if (_activeFilters.isNotEmpty) {
        List<dynamic> statusConditions = [];

        for (String filter in _activeFilters) {
          switch (filter) {
            case 'draft':
              statusConditions.add(['state', '=', 'draft']);
              break;
            case 'posted':
              statusConditions.add('&');
              statusConditions.add(['state', '=', 'posted']);
              statusConditions.add(['payment_state', '=', 'not_paid']);
              break;
            case 'paid':
              statusConditions.add(['payment_state', '=', 'paid']);
              break;
            case 'partial':
              statusConditions.add(['payment_state', '=', 'partial']);
              break;
            case 'not_paid':
              statusConditions.add('&');
              statusConditions.add(['state', '=', 'posted']);
              statusConditions.add(['payment_state', '=', 'not_paid']);
              break;
            case 'in_payment':
              statusConditions.add(['payment_state', '=', 'in_payment']);
              break;
            case 'reversed':
              statusConditions.add(['payment_state', '=', 'reversed']);
              break;
            case 'blocked':
              statusConditions.add(['payment_state', '=', 'blocked']);
              break;
            case 'cancelled':
              statusConditions.add(['state', '=', 'cancel']);
              break;
          }
        }

        if (statusConditions.isNotEmpty) {
          if (statusConditions.length > 1) {
            List<dynamic> orConditions = [];
            for (int i = 0; i < statusConditions.length - 1; i++) {
              orConditions.add('|');
            }
            orConditions.addAll(statusConditions);
            domain.addAll(orConditions);
          } else {
            domain.addAll(statusConditions);
          }
        }
      }

      if (_startDate != null) {
        final startDateStr = DateFormat('yyyy-MM-dd').format(_startDate!);
        domain.add(['invoice_date', '>=', startDateStr]);
      }

      if (_endDate != null) {
        final endDateStr = DateFormat('yyyy-MM-dd').format(_endDate!);
        domain.add(['invoice_date', '<=', endDateStr]);
      }

      if (_searchQuery.isNotEmpty) {
        domain.add('|');
        domain.add(['name', 'ilike', _searchQuery]);
        domain.add(['partner_id.name', 'ilike', _searchQuery]);
      }

      final countFuture = OdooSessionManager.callKwWithCompany({
        'model': 'account.move',
        'method': 'search_count',
        'args': [domain],
        'kwargs': {},
      });

      final listFuture =
          FieldValidationService.executeWithFieldValidation<
            List<Map<String, dynamic>>
          >(
            model: 'account.move',
            initialFields: [
              'id',
              'name',
              'invoice_date',
              'invoice_date_due',
              'amount_total',
              'amount_residual',
              'state',
              'partner_id',
              'payment_state',
              'currency_id',
              'invoice_origin',
              'create_date',
              'is_move_sent',
              'invoice_user_id',
              'team_id',
              'company_id',
            ],
            apiCall: (currentFields) => OdooSessionManager.callKwWithCompany({
              'model': 'account.move',
              'method': 'search_read',
              'args': [domain],
              'kwargs': {
                'fields': currentFields,
                'order': 'invoice_date desc, name desc, id desc',
                'limit': _pageSize,
                'offset': _currentPage * _pageSize,
              },
            }).then((res) => (res as List).cast<Map<String, dynamic>>()),
          );

      final results = await Future.wait([countFuture, listFuture]);
      final totalCount = results[0] as int;
      final result = results[1];

      if (result is List) {
        final newInvoices = result
            .whereType<Map<String, dynamic>>()
            .map((json) => Invoice.fromJson(json))
            .toList();

        if (!mounted) return;
        setState(() {
          _totalInvoices = totalCount;
          if (!isLoadMore) {
            _invoices = newInvoices;
          } else {
            _invoices?.addAll(newInvoices);
          }

          _hasMoreData = (_currentPage + 1) * _pageSize < totalCount;
          _isLoading = false;
          _isLoadingMore = false;
          _isInitialized = true;
          _accessErrorMessage = null;

          if (_selectedGroupBy != null) {
            _isGrouped = true;

            _fetchGroupSummary();
          } else {
            _groupSummary.clear();
            _loadedGroups.clear();
            _cachedGroupSummary.clear();
            _cachedLoadedGroups.clear();
            _cachedGroupByField = null;
            _isGrouped = false;
          }
        });

        final bool isDefaultViewAfterFetch =
            _searchQuery.isEmpty &&
            widget.customerId == null &&
            !widget.overdueOnly &&
            !widget.unpaidOnly;
        if (isDefaultViewAfterFetch) {
          _cachedInvoices = List.from(_invoices ?? []);
          _cachedTotalCount = totalCount;
          _lastFetchTime = DateTime.now();
        }
      } else {
        throw Exception('Unexpected response format');
      }
    } catch (e) {
      if (e.toString().contains('AccessError')) {
        if (!mounted) return;
        setState(() {
          _accessErrorMessage = "You don't have permission to view invoices.";
          _isLoading = false;
          _isLoadingMore = false;
        });
        return;
      }

      if (!mounted) return;

      final isServerError = _isServerUnreachableError(e);
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _isInitialized = true;
        if (isServerError) {
          _isServerUnreachable = true;
        }
      });

      if (isServerError) {
      } else {
        if (mounted) {
          _showErrorSnackBar('Failed to load invoices: ${_getErrorMessage(e)}');
        }
      }
    }
  }

  Future<void> _handleRefresh() async {
    _cachedInvoices.clear();
    _lastFetchTime = null;

    setState(() {
      _isLoading = true;
      _isManualRefresh = true;
      _currentPage = 0;
      _hasMoreData = true;
      _invoices = null;
    });

    await _fetchInvoices();

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        try {
          Theme.of(context);
          CustomSnackbar.showSuccess(context, 'Invoices refreshed');
        } catch (e) {}
      });
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      try {
        CustomSnackbar.showError(context, message);
      } catch (e) {}
    });
  }

  void showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return DefaultTabController(
          length: 2,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              final theme = Theme.of(context);
              final isDark = theme.brightness == Brightness.dark;

              final Map<String, String> invoiceGroupByOptions = {
                'state': 'Status',
                'invoice_user_id': 'Salesperson',
                'partner_id': 'Partner',
                'team_id': 'Sales Team',
                'company_id': 'Company',
              };

              return Container(
                height: MediaQuery.of(context).size.height * 0.8,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF232323) : Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Filter & Group By',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: Icon(
                                Icons.close,
                                color: isDark ? Colors.white : Colors.black54,
                              ),
                              splashRadius: 20,
                            ),
                          ],
                        ),
                      ),

                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TabBar(
                          indicator: BoxDecoration(
                            color: theme.primaryColor,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: theme.primaryColor.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          indicatorPadding: const EdgeInsets.all(4),
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          labelColor: Colors.white,
                          unselectedLabelColor: isDark
                              ? Colors.grey[400]
                              : Colors.grey[600],
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                          tabs: const [
                            Tab(height: 48, text: 'Filter'),
                            Tab(height: 48, text: 'Group By'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      Expanded(
                        child: TabBarView(
                          children: [
                            SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_activeFilters.isNotEmpty ||
                                      _startDate != null ||
                                      _endDate != null) ...[
                                    Text(
                                      'Active Filters',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: isDark
                                                ? Colors.white
                                                : theme.primaryColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        if (_activeFilters.isNotEmpty)
                                          Chip(
                                            label: Text(
                                              'Status (${_activeFilters.length})',
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                            backgroundColor: isDark
                                                ? Colors.white.withOpacity(.08)
                                                : theme.primaryColor
                                                      .withOpacity(0.08),
                                            deleteIcon: const Icon(
                                              Icons.close,
                                              size: 16,
                                            ),
                                            onDeleted: () {
                                              setDialogState(() {
                                                _activeFilters.clear();
                                              });
                                            },
                                          ),
                                        if (_startDate != null ||
                                            _endDate != null)
                                          Chip(
                                            label: const Text(
                                              'Date Range',
                                              style: TextStyle(fontSize: 13),
                                            ),
                                            backgroundColor: isDark
                                                ? Colors.white.withOpacity(.08)
                                                : theme.primaryColor
                                                      .withOpacity(0.08),
                                            deleteIcon: const Icon(
                                              Icons.close,
                                              size: 16,
                                            ),
                                            onDeleted: () {
                                              setDialogState(() {
                                                _startDate = null;
                                                _endDate = null;
                                              });
                                            },
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  Text(
                                    'Status',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: isDark
                                              ? Colors.grey[400]
                                              : Colors.grey[600],
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: _invoiceStatusFilters.entries.map(
                                      (entry) {
                                        final isSelected = _activeFilters
                                            .contains(entry.key);
                                        return ChoiceChip(
                                          label: Text(
                                            entry.value,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: isSelected
                                                  ? Colors.white
                                                  : (isDark
                                                        ? Colors.white
                                                        : Colors.black87),
                                            ),
                                          ),
                                          selected: isSelected,
                                          selectedColor: theme.primaryColor,
                                          backgroundColor: isDark
                                              ? Colors.white.withOpacity(.08)
                                              : theme.primaryColor.withOpacity(
                                                  0.08,
                                                ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            side: BorderSide(
                                              color: isDark
                                                  ? Colors.grey[600]!
                                                  : Colors.grey[300]!,
                                            ),
                                          ),
                                          onSelected: (val) {
                                            setDialogState(() {
                                              if (val) {
                                                _activeFilters.add(entry.key);
                                              } else {
                                                _activeFilters.remove(
                                                  entry.key,
                                                );
                                              }
                                            });
                                          },
                                        );
                                      },
                                    ).toList(),
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    'Date Range',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: isDark
                                              ? Colors.grey[400]
                                              : Colors.grey[600],
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: 12),

                                  InkWell(
                                    onTap: () async {
                                      final date =
                                          await DatePickerUtils.showStandardDatePicker(
                                            context: context,
                                            initialDate:
                                                _startDate ?? DateTime.now(),
                                            firstDate: DateTime(2020),
                                            lastDate: DateTime.now().add(
                                              const Duration(days: 365),
                                            ),
                                          );
                                      if (date != null) {
                                        setDialogState(() {
                                          _startDate = date;
                                        });
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.grey[850]
                                            : Colors.grey[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isDark
                                              ? Colors.grey[700]!
                                              : Colors.grey[300]!,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_today,
                                            size: 16,
                                            color: isDark
                                                ? Colors.grey[400]
                                                : Colors.grey[600],
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _startDate != null
                                                  ? 'From: ${DateFormat('MMM dd, yyyy').format(_startDate!)}'
                                                  : 'Select start date',
                                              style: TextStyle(
                                                color: _startDate != null
                                                    ? (isDark
                                                          ? Colors.white
                                                          : Colors.grey[800])
                                                    : (isDark
                                                          ? Colors.grey[400]
                                                          : Colors.grey[600]),
                                              ),
                                            ),
                                          ),
                                          if (_startDate != null)
                                            IconButton(
                                              onPressed: () {
                                                setDialogState(() {
                                                  _startDate = null;
                                                });
                                              },
                                              icon: Icon(
                                                Icons.clear,
                                                size: 16,
                                                color: isDark
                                                    ? Colors.grey[400]
                                                    : Colors.grey[600],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  InkWell(
                                    onTap: () async {
                                      final date =
                                          await DatePickerUtils.showStandardDatePicker(
                                            context: context,
                                            initialDate:
                                                _endDate ?? DateTime.now(),
                                            firstDate:
                                                _startDate ?? DateTime(2020),
                                            lastDate: DateTime.now().add(
                                              const Duration(days: 365),
                                            ),
                                          );
                                      if (date != null) {
                                        setDialogState(() {
                                          _endDate = date;
                                        });
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.grey[850]
                                            : Colors.grey[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isDark
                                              ? Colors.grey[700]!
                                              : Colors.grey[300]!,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_today,
                                            size: 16,
                                            color: isDark
                                                ? Colors.grey[400]
                                                : Colors.grey[600],
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _endDate != null
                                                  ? 'To: ${DateFormat('MMM dd, yyyy').format(_endDate!)}'
                                                  : 'Select end date',
                                              style: TextStyle(
                                                color: _endDate != null
                                                    ? (isDark
                                                          ? Colors.white
                                                          : Colors.grey[800])
                                                    : (isDark
                                                          ? Colors.grey[400]
                                                          : Colors.grey[600]),
                                              ),
                                            ),
                                          ),
                                          if (_endDate != null)
                                            IconButton(
                                              onPressed: () {
                                                setDialogState(() {
                                                  _endDate = null;
                                                });
                                              },
                                              icon: Icon(
                                                Icons.clear,
                                                size: 16,
                                                color: isDark
                                                    ? Colors.grey[400]
                                                    : Colors.grey[600],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Group invoices by',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: isDark
                                              ? Colors.grey[400]
                                              : Colors.grey[600],
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                  RadioListTile<String?>(
                                    title: Text(
                                      'None',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Display as a simple list',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                    value: null,
                                    groupValue: _selectedGroupBy,
                                    onChanged: (value) {
                                      setDialogState(() {
                                        _selectedGroupBy = value;
                                      });
                                    },
                                    activeColor: theme.primaryColor,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  const Divider(),
                                  ...invoiceGroupByOptions.entries.map((entry) {
                                    String description = '';
                                    switch (entry.key) {
                                      case 'state':
                                        description =
                                            'Group by invoice status (Draft, Posted, etc.)';
                                        break;
                                      case 'invoice_user_id':
                                        description =
                                            'Group by assigned salesperson';
                                        break;
                                      case 'partner_id':
                                        description =
                                            'Group by partner/customer';
                                        break;
                                      case 'team_id':
                                        description = 'Group by sales team';
                                        break;
                                      case 'company_id':
                                        description = 'Group by company';
                                        break;
                                      default:
                                        description =
                                            'Group by ${entry.value.toLowerCase()}';
                                    }
                                    return RadioListTile<String>(
                                      title: Text(
                                        entry.value,
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      subtitle: Text(
                                        description,
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.grey[400]
                                              : Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                      value: entry.key,
                                      groupValue: _selectedGroupBy,
                                      onChanged: (value) {
                                        setDialogState(() {
                                          _selectedGroupBy = value;
                                        });
                                      },
                                      activeColor: theme.primaryColor,
                                      contentPadding: EdgeInsets.zero,
                                    );
                                  }),
                                  const SizedBox(height: 24),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[850] : Colors.grey[50],
                          border: Border(
                            top: BorderSide(
                              color: isDark
                                  ? Colors.grey[700]!
                                  : Colors.grey[200]!,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  setDialogState(() {
                                    _activeFilters.clear();
                                    _startDate = null;
                                    _endDate = null;
                                    _selectedGroupBy = null;
                                    _isGrouped = false;
                                    _groupSummary.clear();
                                    _loadedGroups.clear();
                                    _currentPage = 0;
                                    _hasMoreData = true;
                                    _invoices = null;
                                    _isManualRefresh = true;
                                  });

                                  Navigator.of(context).pop();
                                  setState(() {
                                    _isGrouped = false;
                                    _groupSummary.clear();
                                    _loadedGroups.clear();
                                    _currentPage = 0;
                                    _hasMoreData = true;
                                    _invoices = null;
                                    _isManualRefresh = true;
                                  });
                                  await _fetchInvoices();

                                  final isContextual =
                                      widget.customerId != null ||
                                      widget.overdueOnly ||
                                      widget.unpaidOnly;
                                  if (!isContextual) {
                                    _savedFilters.clear();
                                    _savedStartDate = null;
                                    _savedEndDate = null;
                                    _savedGroupBy = null;
                                    _savedSearchQuery = '';
                                  }
                                  if (mounted) {
                                    CustomSnackbar.showInfo(
                                      context,
                                      'All filters cleared',
                                    );
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: isDark
                                      ? Colors.white
                                      : Colors.black87,
                                  side: BorderSide(
                                    color: isDark
                                        ? Colors.grey[600]!
                                        : Colors.grey[300]!,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('Clear All'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: () async {
                                  try {
                                    Navigator.of(context).pop();

                                    setState(() {
                                      _isGrouped = _selectedGroupBy != null;
                                      _currentPage = 0;
                                      _hasMoreData = true;
                                      _invoices = null;
                                      _isManualRefresh = true;

                                      _groupSummary.clear();
                                      _loadedGroups.clear();
                                    });
                                    await _fetchInvoices();

                                    final hasDateFilter =
                                        _startDate != null || _endDate != null;
                                    final totalFilters =
                                        _activeFilters.length +
                                        (hasDateFilter ? 1 : 0) +
                                        (_selectedGroupBy != null ? 1 : 0);
                                    if (mounted) {
                                      final isContextual =
                                          widget.customerId != null ||
                                          widget.overdueOnly ||
                                          widget.unpaidOnly;
                                      if (!isContextual) {
                                        _savedFilters = Set.from(
                                          _activeFilters,
                                        );
                                        _savedStartDate = _startDate;
                                        _savedEndDate = _endDate;
                                        _savedGroupBy = _selectedGroupBy;
                                        _savedSearchQuery = _searchQuery;
                                      }
                                      CustomSnackbar.showInfo(
                                        context,
                                        totalFilters == 0
                                            ? 'All filters cleared'
                                            : 'Applied $totalFilters setting${totalFilters > 1 ? 's' : ''}',
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      CustomSnackbar.showError(
                                        context,
                                        'Failed to apply filters: ${e.toString()}',
                                      );
                                    }
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('Apply'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _applyFilters() {
    if (_startDate != null &&
        _endDate != null &&
        _startDate!.isAfter(_endDate!)) {
      _showErrorSnackBar('Start date cannot be after end date');
      return;
    }

    setState(() {
      _currentPage = 0;
      _hasMoreData = true;
      _invoices = null;
      _isManualRefresh = true;

      if (_selectedGroupBy != null) {
        _groupSummary.clear();
        _loadedGroups.clear();
        _isGrouped = true;
      }
    });

    _fetchInvoices();
  }

  Future<void> _fetchGroupSummary() async {
    if (!_isGrouped || _selectedGroupBy == null) return;

    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return;

      List<dynamic> domain = [
        [
          'move_type',
          'in',
          ['out_invoice', 'out_refund'],
        ],
      ];

      if (widget.customerId != null) {
        domain.add(['partner_id', '=', widget.customerId]);
      }

      if (widget.saleOrderName != null && widget.saleOrderName!.isNotEmpty) {
        domain.add(['invoice_origin', 'ilike', widget.saleOrderName!.trim()]);
      }

      if (widget.overdueOnly) {
        final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        domain.addAll([
          ['state', '=', 'posted'],
          [
            'payment_state',
            'in',
            ['not_paid', 'partial'],
          ],
          ['invoice_date_due', '<', todayStr],
        ]);
      }

      if (widget.unpaidOnly) {
        domain.addAll([
          ['state', '=', 'posted'],
          [
            'payment_state',
            'in',
            ['not_paid', 'partial'],
          ],
        ]);
      }

      if (_activeFilters.isNotEmpty) {
        List<dynamic> statusConditions = [];
        for (String filter in _activeFilters) {
          switch (filter) {
            case 'draft':
              statusConditions.add(['state', '=', 'draft']);
              break;
            case 'posted':
              statusConditions.add('&');
              statusConditions.add(['state', '=', 'posted']);
              statusConditions.add(['payment_state', '=', 'not_paid']);
              break;
            case 'paid':
              statusConditions.add(['payment_state', '=', 'paid']);
              break;
            case 'partial':
              statusConditions.add(['payment_state', '=', 'partial']);
              break;
            case 'not_paid':
              statusConditions.add('&');
              statusConditions.add(['state', '=', 'posted']);
              statusConditions.add(['payment_state', '=', 'not_paid']);
              break;
            case 'in_payment':
              statusConditions.add(['payment_state', '=', 'in_payment']);
              break;
            case 'reversed':
              statusConditions.add(['payment_state', '=', 'reversed']);
              break;
            case 'blocked':
              statusConditions.add(['payment_state', '=', 'blocked']);
              break;
            case 'cancelled':
              statusConditions.add(['state', '=', 'cancel']);
              break;
          }
        }

        if (statusConditions.isNotEmpty) {
          if (statusConditions.length > 1) {
            List<dynamic> orConditions = [];
            for (int i = 0; i < statusConditions.length - 1; i++) {
              orConditions.add('|');
            }
            orConditions.addAll(statusConditions);
            domain.addAll(orConditions);
          } else {
            domain.addAll(statusConditions);
          }
        }
      }

      if (_startDate != null) {
        final startDateStr = DateFormat('yyyy-MM-dd').format(_startDate!);
        domain.add(['invoice_date', '>=', startDateStr]);
      }

      if (_endDate != null) {
        final endDateStr = DateFormat('yyyy-MM-dd').format(_endDate!);
        domain.add(['invoice_date', '<=', endDateStr]);
      }

      if (_searchQuery.isNotEmpty) {
        domain.add('|');
        domain.add(['name', 'ilike', _searchQuery]);
        domain.add(['partner_id.name', 'ilike', _searchQuery]);
      }

      final result = await client.callKw({
        'model': 'account.move',
        'method': 'read_group',
        'args': [domain],
        'kwargs': {
          'fields': ['id'],
          'groupby': [_selectedGroupBy!],
          'lazy': false,
        },
      });

      if (result is List) {
        _groupSummary.clear();

        int totalGroupedCount = 0;
        for (final group in result) {
          if (group is Map) {
            final groupKey = _getGroupKeyFromReadGroup(
              group,
              _selectedGroupBy!,
            );
            final count = group['__count'] ?? 0;
            _groupSummary[groupKey] = count;
            totalGroupedCount += count as int;
          }
        }

        if (_totalInvoices > totalGroupedCount) {
          final missingCount = _totalInvoices - totalGroupedCount;
          String undefinedLabel;

          if (_selectedGroupBy == 'invoice_user_id') {
            undefinedLabel = 'Unassigned';
          } else if (_selectedGroupBy == 'partner_id') {
            undefinedLabel = 'Unknown Partner';
          } else if (_selectedGroupBy == 'team_id') {
            undefinedLabel = 'No Team';
          } else if (_selectedGroupBy == 'company_id') {
            undefinedLabel = 'Unknown Company';
          } else {
            undefinedLabel = 'Undefined';
          }

          _groupSummary[undefinedLabel] = missingCount;
        }

        _cachedGroupSummary = Map.from(_groupSummary);
        _cachedLoadedGroups = Map.from(_loadedGroups);
        _cachedGroupByField = _selectedGroupBy;

        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {}
  }

  String _getGroupKeyFromReadGroup(
    Map<dynamic, dynamic> group,
    String groupByField,
  ) {
    try {
      final value = group[groupByField];

      final Map<String, dynamic> tempData = {};

      if (groupByField == 'state') {
        tempData['state'] = value;
        tempData['payment_state'] = '';
      } else if (groupByField == 'partner_id') {
        tempData['partner_id'] = value;
      } else if (groupByField == 'payment_state') {
        tempData['payment_state'] = value;
      } else if (groupByField == 'currency_id') {
        tempData['currency_id'] = value;
      } else if (groupByField == 'invoice_date' ||
          groupByField == 'invoice_date_due') {
        tempData[groupByField] = value;
      }

      return _groupKeyForInvoiceData(tempData, groupByField);
    } catch (e) {
      return 'Unknown';
    }
  }

  List<dynamic> _buildGroupDomain(String groupKey, String groupByField) {
    try {
      switch (groupByField) {
        case 'state':
          final stateMap = {
            'Draft': 'draft',
            'Posted': 'posted',
            'Cancelled': 'cancel',
            'Sent': 'sent',
          };
          final stateValue = stateMap[groupKey] ?? groupKey.toLowerCase();
          return [
            ['state', '=', stateValue],
          ];
        case 'invoice_user_id':
          if (groupKey == 'Unassigned') {
            return [
              '|',
              ['invoice_user_id', '=', false],
              ['invoice_user_id', '=', null],
            ];
          }
          return [
            ['invoice_user_id.name', '=', groupKey],
          ];
        case 'partner_id':
          if (groupKey == 'Unknown Partner') {
            return [
              '|',
              ['partner_id', '=', false],
              ['partner_id', '=', null],
            ];
          }
          return [
            ['partner_id.name', '=', groupKey],
          ];
        case 'team_id':
          if (groupKey == 'No Team') {
            return [
              '|',
              ['team_id', '=', false],
              ['team_id', '=', null],
            ];
          }
          return [
            ['team_id.name', '=', groupKey],
          ];
        case 'company_id':
          if (groupKey == 'Unknown Company') {
            return [
              '|',
              ['company_id', '=', false],
              ['company_id', '=', null],
            ];
          }
          return [
            ['company_id.name', '=', groupKey],
          ];
        default:
          if (groupKey == 'Unknown') {
            return [
              [groupByField, '=', false],
            ];
          }
          return [
            [groupByField, '=', groupKey],
          ];
      }
    } catch (e) {
      return [];
    }
  }

  Future<void> loadGroupInvoices(String groupKey) async {
    if (!_isGrouped || _selectedGroupBy == null) return;

    if (_loadedGroups.containsKey(groupKey)) return;

    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return;

      List<dynamic> domain = [
        [
          'move_type',
          'in',
          ['out_invoice', 'out_refund'],
        ],
      ];

      if (widget.customerId != null) {
        domain.add(['partner_id', '=', widget.customerId]);
      }

      if (widget.saleOrderName != null && widget.saleOrderName!.isNotEmpty) {
        domain.add(['invoice_origin', 'ilike', widget.saleOrderName!.trim()]);
      }

      if (widget.overdueOnly) {
        final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        domain.addAll([
          ['state', '=', 'posted'],
          [
            'payment_state',
            'in',
            ['not_paid', 'partial'],
          ],
          ['invoice_date_due', '<', todayStr],
        ]);
      }

      if (widget.unpaidOnly) {
        domain.addAll([
          ['state', '=', 'posted'],
          [
            'payment_state',
            'in',
            ['not_paid', 'partial'],
          ],
        ]);
      }

      if (_activeFilters.isNotEmpty) {
        List<dynamic> statusConditions = [];
        for (String filter in _activeFilters) {
          switch (filter) {
            case 'draft':
              statusConditions.add(['state', '=', 'draft']);
              break;
            case 'posted':
              statusConditions.add('&');
              statusConditions.add(['state', '=', 'posted']);
              statusConditions.add(['payment_state', '=', 'not_paid']);
              break;
            case 'paid':
              statusConditions.add(['payment_state', '=', 'paid']);
              break;
            case 'partial':
              statusConditions.add(['payment_state', '=', 'partial']);
              break;
            case 'not_paid':
              statusConditions.add('&');
              statusConditions.add(['state', '=', 'posted']);
              statusConditions.add(['payment_state', '=', 'not_paid']);
              break;
            case 'in_payment':
              statusConditions.add(['payment_state', '=', 'in_payment']);
              break;
            case 'reversed':
              statusConditions.add(['payment_state', '=', 'reversed']);
              break;
            case 'blocked':
              statusConditions.add(['payment_state', '=', 'blocked']);
              break;
            case 'cancelled':
              statusConditions.add(['state', '=', 'cancel']);
              break;
          }
        }

        if (statusConditions.isNotEmpty) {
          if (statusConditions.length > 1) {
            List<dynamic> orConditions = [];
            for (int i = 0; i < statusConditions.length - 1; i++) {
              orConditions.add('|');
            }
            orConditions.addAll(statusConditions);
            domain.addAll(orConditions);
          } else {
            domain.addAll(statusConditions);
          }
        }
      }

      if (_startDate != null) {
        final startDateStr = DateFormat('yyyy-MM-dd').format(_startDate!);
        domain.add(['invoice_date', '>=', startDateStr]);
      }

      if (_endDate != null) {
        final endDateStr = DateFormat('yyyy-MM-dd').format(_endDate!);
        domain.add(['invoice_date', '<=', endDateStr]);
      }

      if (_searchQuery.isNotEmpty) {
        domain.add('|');
        domain.add(['name', 'ilike', _searchQuery]);
        domain.add(['partner_id.name', 'ilike', _searchQuery]);
      }

      final groupDomain = _buildGroupDomain(groupKey, _selectedGroupBy!);

      domain.addAll(groupDomain);

      final result = await client.callKw({
        'model': 'account.move',
        'method': 'search_read',
        'args': [domain],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'invoice_date',
            'invoice_date_due',
            'amount_total',
            'amount_residual',
            'state',
            'partner_id',
            'payment_state',
            'currency_id',
            'invoice_origin',
            'create_date',
            'is_move_sent',
            'invoice_user_id',
            'team_id',
            'company_id',
          ],
          'order': 'invoice_date desc, name desc, id desc',
        },
      });

      if (result is List) {
        final invoices = result
            .whereType<Map<String, dynamic>>()
            .map((json) => Invoice.fromJson(json))
            .toList();
        _loadedGroups[groupKey] = invoices;

        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {}
  }

  String _groupKeyForInvoiceData(
    Map<String, dynamic> data,
    String groupByField,
  ) {
    switch (groupByField) {
      case 'state':
        final state = data['state']?.toString().toLowerCase() ?? '';
        switch (state) {
          case 'draft':
            return 'Draft';
          case 'cancel':
            return 'Cancelled';
          case 'sent':
            return 'Sent';
          case 'posted':
            final paymentState =
                data['payment_state']?.toString().toLowerCase() ?? '';
            switch (paymentState) {
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
              default:
                return 'Posted';
            }
          default:
            return state.isNotEmpty ? state : 'Unknown';
        }
      case 'invoice_user_id':
        if (data['invoice_user_id'] is List &&
            data['invoice_user_id'].length >= 2) {
          return data['invoice_user_id'][1].toString();
        }
        return 'Unassigned';
      case 'partner_id':
        if (data['partner_id'] is List && data['partner_id'].length >= 2) {
          return data['partner_id'][1].toString();
        }
        return 'Unknown Partner';
      case 'team_id':
        if (data['team_id'] is List && data['team_id'].length >= 2) {
          return data['team_id'][1].toString();
        }
        return 'No Team';
      case 'company_id':
        if (data['company_id'] is List && data['company_id'].length >= 2) {
          return data['company_id'][1].toString();
        }
        return 'Unknown Company';
      default:
        return 'Unknown';
    }
  }

  String _getAmountRange(double amount, {String? currencyCode}) {
    final symbol = currencyCode == null
        ? ''
        : context.read<CurrencyProvider>().getCurrencySymbol(currencyCode);
    if (amount < 1000) {
      return 'Under ${symbol}1K';
    } else if (amount < 5000) {
      return '${symbol}1K - ${symbol}5K';
    } else if (amount < 10000) {
      return '${symbol}5K - ${symbol}10K';
    } else if (amount < 50000) {
      return '${symbol}10K - ${symbol}50K';
    } else if (amount < 100000) {
      return '${symbol}50K - ${symbol}100K';
    } else {
      return 'Over ${symbol}100K';
    }
  }

  String _getCurrencySymbol(String currencyCode) {
    return context.read<CurrencyProvider>().getCurrencySymbol(currencyCode);
  }

  String _buildFilterSummary() {
    List<String> parts = [];

    if (_activeFilters.isNotEmpty) {
      final statusNames = _activeFilters
          .map((filter) => _invoiceStatusFilters[filter] ?? filter)
          .toList();
      parts.add('Status: ${statusNames.join(', ')}');
    }

    if (_startDate != null || _endDate != null) {
      if (_startDate != null && _endDate != null) {
        parts.add(
          'Date: ${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd, yyyy').format(_endDate!)}',
        );
      } else if (_startDate != null) {
        parts.add('From: ${DateFormat('MMM dd, yyyy').format(_startDate!)}');
      } else if (_endDate != null) {
        parts.add('Until: ${DateFormat('MMM dd, yyyy').format(_endDate!)}');
      }
    }

    return parts.join(' • ');
  }

  void _navigateToInvoiceDetail(BuildContext context, Invoice invoice) {
    Navigator.push(
      context,

      MaterialPageRoute(
        builder: (context) =>
            InvoiceDetailsPage(invoiceId: invoice.id.toString()),
      ),
    ).then((result) {
      if (result == true) {
        _handleRefresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;
    final backgroundColor = isDark ? Colors.grey[900] : Colors.grey[50];
    final bool isFilteredByCustomer =
        widget.customerId != null ||
        widget.overdueOnly ||
        widget.unpaidOnly ||
        widget.saleOrderName != null;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: isFilteredByCustomer
          ? AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.overdueOnly
                        ? 'Overdue Invoices'
                        : widget.unpaidOnly
                        ? 'Unpaid Invoices'
                        : widget.saleOrderName != null
                        ? 'Related Invoices'
                        : 'Invoices',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  if (widget.saleOrderName != null)
                    Text(
                      'Sale Order: ${widget.saleOrderName}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: isDark
                            ? Colors.white.withOpacity(0.7)
                            : primaryColor.withOpacity(0.7),
                      ),
                    ),
                ],
              ),
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  HugeIcons.strokeRoundedArrowLeft01,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              backgroundColor: backgroundColor,
              foregroundColor: isDark ? Colors.white : primaryColor,
              elevation: 0,
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(
              bottom: _standardPadding,
              left: _standardPadding,
              right: _standardPadding,
            ),
            child: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF000000).withOpacity(0.05),
                    offset: Offset(0, 6),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                enabled: !_isLoading,
                style: TextStyle(
                  color: isDark ? Colors.white : Color(0xff1E1E1E),
                  fontWeight: FontWeight.w400,
                  fontStyle: FontStyle.normal,
                  fontSize: 15,
                  height: 1.0,
                  letterSpacing: 0.0,
                ),
                decoration: InputDecoration(
                  hintText: 'Search invoices...',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white : Color(0xff1E1E1E),
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.normal,
                    fontSize: 15,
                    height: 1.0,
                    letterSpacing: 0.0,
                  ),
                  prefixIcon: IconButton(
                    icon: Icon(
                      HugeIcons.strokeRoundedFilterHorizontal,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      size: 18,
                    ),
                    tooltip: 'Filter & Group By',
                    onPressed: () {
                      showFilterBottomSheet();
                    },
                  ),
                  suffixIcon: Container(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: Icon(
                              Icons.clear,
                              color: isDark ? Colors.grey[400] : Colors.grey,
                              size: 20,
                            ),
                            onPressed: _isLoading
                                ? null
                                : () {
                                    _searchController.clear();
                                  },
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                      ],
                    ),
                  ),
                  filled: true,
                  fillColor: isDark ? Colors.grey[850] : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  isDense: true,
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ),

          Builder(
            builder: (context) {
              if (!_isInitialized && _invoices == null) {
                return const SizedBox.shrink();
              }

              final paginationText = getPaginationText();
              if (paginationText == "0 items") {
                return const SizedBox.shrink();
              }

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    _buildFilterIndicator(isDark, _isGrouped),
                    if (_isGrouped) ...[
                      const SizedBox(width: 8),
                      _buildGroupByPill(
                        isDark,
                        _getGroupByDisplayName(_selectedGroupBy),
                      ),
                    ],
                    const Spacer(),
                    _buildTopPaginationBar(isDark),
                    if (!_isGrouped) ...[
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: (canGoToPreviousPage && !_isLoadingMore)
                                ? () => goToPreviousPage()
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                                horizontal: 4,
                              ),
                              child: Icon(
                                HugeIcons.strokeRoundedArrowLeft01,
                                size: 20,
                                color: (canGoToPreviousPage && !_isLoadingMore)
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : (isDark
                                          ? Colors.grey[600]
                                          : Colors.grey[400]),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: (canGoToNextPage && !_isLoadingMore)
                                ? () => goToNextPage()
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                                horizontal: 4,
                              ),
                              child: Icon(
                                HugeIcons.strokeRoundedArrowRight01,
                                size: 20,
                                color: (canGoToNextPage && !_isLoadingMore)
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : (isDark
                                          ? Colors.grey[600]
                                          : Colors.grey[400]),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),

          Expanded(
            child: Consumer2<ConnectivityService, SessionService>(
              builder: (context, connectivityService, sessionService, child) {
                final isErrorWithNoData =
                    _isServerUnreachable && (_invoices?.isEmpty ?? true);

                if (_isServerUnreachable && !isErrorWithNoData) {
                  return ConnectionStatusWidget(
                    serverUnreachable: true,
                    serverErrorMessage:
                        'Unable to load invoices from server/database. Please check your server or try again.',
                    onRetry: () {
                      setState(() {
                        _isServerUnreachable = false;
                      });
                      _fetchInvoices();
                    },
                  );
                }

                if (_accessErrorMessage != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 20,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.06)
                                  : Theme.of(
                                      context,
                                    ).colorScheme.error.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withOpacity(0.18)
                                    : Theme.of(
                                        context,
                                      ).colorScheme.error.withOpacity(0.18),
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: isDark
                                      ? Colors.white.withOpacity(0.85)
                                      : Theme.of(
                                          context,
                                        ).colorScheme.error.withOpacity(0.85),
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Access Error',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Theme.of(context).colorScheme.error,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _accessErrorMessage!,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white.withOpacity(0.8)
                                        : Theme.of(
                                            context,
                                          ).colorScheme.error.withOpacity(0.8),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isDark
                                          ? Colors.white.withOpacity(0.1)
                                          : Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                      foregroundColor: isDark
                                          ? Colors.white
                                          : Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _accessErrorMessage = null;
                                        _isLoading = true;
                                      });
                                      _fetchInvoices();
                                    },
                                    icon: Icon(Icons.refresh, size: 20),
                                    label: Text(
                                      'Retry',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
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

                if (!connectivityService.isConnected) {
                  return ConnectionStatusWidget(
                    onRetry: () {
                      if (connectivityService.isConnected &&
                          sessionService.hasValidSession) {
                        _handleRefresh();
                      }
                    },
                    customMessage:
                        'No internet connection. Please check your connection and try again.',
                  );
                }

                return _isLoading
                    ? _buildFullPageShimmer()
                    : _buildInvoiceList(
                        isDark ? Colors.grey[850]! : Colors.white,
                        Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.12),
                        Theme.of(context).colorScheme.onSurface,
                        isDark ? Colors.grey[300]! : Colors.grey[700]!,
                        isDark,
                      );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: isFilteredByCustomer
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_showScrollToTop)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: FloatingActionButton(
                      heroTag: 'fab_scroll_top_invoices',
                      mini: true,
                      onPressed: () {
                        _scrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                        );
                      },
                      tooltip: 'Scroll to top',
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.secondaryContainer,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onSecondaryContainer,
                      child: const Icon(Icons.arrow_upward_rounded),
                    ),
                  ),
                FloatingActionButton(
                  heroTag: 'fab_create_invoice',
                  onPressed: () async {
                    final isIOS =
                        Theme.of(context).platform == TargetPlatform.iOS;
                    final result = await Navigator.push(
                      context,

                      MaterialPageRoute(
                        builder: (context) => const CreateInvoiceScreen(),
                      ),
                    );
                    if (result == true) {
                      setState(() {
                        _isManualRefresh = true;
                        _currentPage = 0;
                        _hasMoreData = true;
                        _invoices = null;
                      });
                      await _fetchInvoices();
                    }
                  },
                  backgroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Theme.of(context).primaryColor,
                  tooltip: 'Create Invoice',
                  child: Icon(
                    HugeIcons.strokeRoundedNoteAdd,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black
                        : Colors.white,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInvoiceList(
    Color cardColor,
    Color borderColor,
    Color textColor,
    Color subtitleColor,
    bool isDarkMode,
  ) {
    if (!_isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            const SizedBox(height: _standardPadding),
            Text(
              'Failed to initialize. Please try again.',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: _standardPadding),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_cardBorderRadius),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: _standardPadding,
                  vertical: _smallPadding,
                ),
              ),
              onPressed: _initializeAndFetch,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_invoices == null || _invoices!.isEmpty) {
      final hasFilters =
          _activeFilters.isNotEmpty || _startDate != null || _endDate != null;

      return RefreshIndicator(
        onRefresh: _handleRefresh,
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStateWidget.invoices(
                hasSearchQuery: _searchController.text.isNotEmpty,
                hasFilters: hasFilters,
                onClearFilters: hasFilters
                    ? () {
                        setState(() {
                          _activeFilters.clear();
                          _startDate = null;
                          _endDate = null;
                          _searchController.clear();
                          _currentPage = 0;
                          _hasMoreData = true;
                        });
                        _fetchInvoices();
                      }
                    : null,
                onRetry: _handleRefresh,
              ),
            ),
          ],
        ),
      );
    }

    if (_isGrouped && _selectedGroupBy != null) {
      if (_groupSummary.isEmpty) {
        return ListShimmer.buildListShimmer(
          context,
          itemCount: 8,
          type: ShimmerType.standard,
        );
      }

      final isDark = Theme.of(context).brightness == Brightness.dark;

      for (final groupKey in _groupSummary.keys) {
        if (!_expandedGroups.containsKey(groupKey)) {
          _expandedGroups[groupKey] = false;
        }
      }

      _expandedGroups.removeWhere(
        (key, value) => !_groupSummary.containsKey(key),
      );

      return Expanded(
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _groupSummary.keys.length,
            itemBuilder: (context, index) {
              try {
                final groupKey = _groupSummary.keys.elementAt(index);
                final count = _groupSummary[groupKey]!;
                final isExpanded = _expandedGroups[groupKey] ?? false;
                final loadedInvoices = _loadedGroups[groupKey] ?? [];

                return _buildOdooStyleGroupTile(
                  groupKey,
                  count,
                  isExpanded,
                  loadedInvoices,
                  isDark,
                );
              } catch (e) {
                return const SizedBox.shrink();
              }
            },
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: _standardPadding),
        itemCount: _invoices!.length,
        itemBuilder: (context, index) {
          final invoice = _invoices![index];
          return _buildInvoiceTile(invoice, isDarkMode);
        },
      ),
    );
  }

  Widget _buildInvoiceTile(Invoice invoice, bool isDarkMode) {
    final isFullyPaid = invoice.amountResidual <= 0 || invoice.status == 'paid';

    int? daysOverdue;
    bool isOverdue = false;
    if (invoice.dueDate != null &&
        !isFullyPaid &&
        invoice.dueDate!.isBefore(DateTime.now())) {
      daysOverdue = DateTime.now().difference(invoice.dueDate!).inDays;
      isOverdue = true;
    }

    String mainDate = invoice.invoiceDate != null
        ? DateFormat('MMM dd, yyyy').format(invoice.invoiceDate!)
        : '';
    String? dueDate = invoice.dueDate != null
        ? DateFormat('MMM dd, yyyy').format(invoice.dueDate!)
        : null;
    String infoLine = mainDate;

    String? extraInfoLine;
    if (dueDate != null &&
        isOverdue &&
        daysOverdue != null &&
        daysOverdue > 0) {
      extraInfoLine =
          'Due: $dueDate  •  $daysOverdue day${daysOverdue == 1 ? '' : 's'} overdue';
    } else if (dueDate != null) {
      extraInfoLine = 'Due: $dueDate';
    }

    return OrderLikeListTile(
      id: invoice.name,
      customer: invoice.customerName,
      infoLine: infoLine,
      extraInfoLine: extraInfoLine,
      amount: invoice.total,
      currencyId: invoice.currencyId,
      status: _getInvoiceStatusLabel(invoice),
      statusColor: _getInvoiceStatusColor(invoice),
      isDark: isDarkMode,
      onTap: () => _navigateToInvoiceDetail(context, invoice),
      mainIcon: invoice.invoiceDate != null
          ? HugeIcons.strokeRoundedCalendar03
          : null,
      extraIcon: HugeIcons.strokeRoundedCalendar01,
      amountLabel: 'Total Amount',
    );
  }

  Widget _buildOdooStyleGroupTile(
    String groupKey,
    int count,
    bool isExpanded,
    List<Invoice> loadedInvoices,
    bool isDark,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 6),
              color: Colors.black.withOpacity(0.08),
            ),
        ],
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          InkWell(
            onTap: () async {
              try {
                setState(() {
                  _expandedGroups[groupKey] = !isExpanded;
                  _allGroupsExpanded = _expandedGroups.values.every(
                    (expanded) => expanded,
                  );
                });

                if (!isExpanded && !_loadedGroups.containsKey(groupKey)) {
                  await loadGroupInvoices(groupKey);
                }
              } catch (e) {}
            },
            borderRadius: BorderRadius.circular(_cardBorderRadius),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          groupKey,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$count invoice${count != 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),

          if (isExpanded) ...[
            if (loadedInvoices.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ),
              )
            else
              ...loadedInvoices.map(
                (invoice) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: _buildInvoiceTile(invoice, isDark),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildDateRow({
    required IconData icon,
    required String label,
    required String date,
    required Color color,
    required BuildContext context,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color.withOpacity(0.8),
                  fontWeight: FontWeight.w400,
                ),
              ),
              SizedBox(height: 2),
              Text(
                date,
                style: TextStyle(
                  fontSize: 14,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAmountRow({
    required String label,
    required double amount,
    required bool isTotal,
    required Color textColor,
    required BuildContext context,
    required List<dynamic>? currencyId,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 14 : 13,
            fontWeight: isTotal ? FontWeight.w600 : FontWeight.w500,
            color: textColor.withOpacity(isTotal ? 1.0 : 0.8),
          ),
        ),
        Consumer<CurrencyProvider>(
          builder: (context, currencyProvider, _) {
            final String? currencyCode =
                (currencyId != null && currencyId.length > 1)
                ? currencyId[1].toString()
                : null;

            final formattedAmount = currencyProvider.formatAmount(
              amount,
              currency: currencyCode,
            );

            return Text(
              formattedAmount,
              style: TextStyle(
                fontSize: isTotal ? 16 : 14,
                fontWeight: FontWeight.w700,
                color: textColor,
                letterSpacing: -0.2,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAllInvoicesFetched(int count) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final textColor = isDark
        ? (Colors.grey[400] ?? const Color(0xFFBDBDBD))
        : (Colors.grey[600] ?? const Color(0xFF757575));

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        left: _smallPadding * 0.5,
        right: _smallPadding * 0.5,
        bottom: _smallPadding * 2,
        top: _smallPadding,
      ),
      child: Center(
        child: Text(
          'All invoices loaded ($count total)',
          style: TextStyle(
            color: textColor,
            fontSize: 14,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildLoadingMoreIndicator() {
    return Container(
      padding: const EdgeInsets.all(_standardPadding),
      child: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).primaryColor,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadMoreButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: _isLoadingMore || !_hasMoreData ? null : _loadMoreData,
          icon: const Icon(Icons.expand_more, size: 18),
          label: const Text('Load more'),
          style: OutlinedButton.styleFrom(
            foregroundColor: isDark ? Colors.white : Colors.black87,
            side: BorderSide(
              color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFullPageShimmer() {
    return ListShimmer.buildListShimmer(
      context,
      itemCount: 8,
      type: ShimmerType.standard,
    );
  }

  Widget _buildFilterIndicator(bool isDarkMode, bool hasGroupBy) {
    final hasDateFilter = _startDate != null || _endDate != null;
    final count =
        _activeFilters.length +
        (hasDateFilter ? 1 : 0) +
        (_searchQuery.isNotEmpty ? 1 : 0);

    if (count == 0) {
      if (hasGroupBy) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'No filters applied',
          style: TextStyle(
            fontSize: 12,
            color: isDarkMode ? Colors.white70 : Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white70 : Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count active',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDarkMode ? Colors.black : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupByPill(bool isDark, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white70 : Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            HugeIcons.strokeRoundedLayer,
            size: 14,
            color: isDark ? Colors.black : Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.black : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopPaginationBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Text(
        getPaginationText(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.grey[300] : Colors.grey[700],
        ),
      ),
    );
  }

  bool _hasActiveFilters() {
    final hasDateFilter = _startDate != null || _endDate != null;
    return _activeFilters.isNotEmpty || hasDateFilter;
  }

  String _getGroupByDisplayName(String? groupBy) {
    if (groupBy == null) return '';

    const groupByOptions = {
      'status': 'Status',
      'partner_id': 'Customer',
      'invoice_date': 'Invoice Date',
      'due_date': 'Due Date',
      'amount_total': 'Amount',
    };

    return groupByOptions[groupBy] ?? groupBy;
  }
}
