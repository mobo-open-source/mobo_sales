import 'dart:async';
import 'package:flutter/material.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import 'package:mobo_sales/widgets/order_like_list_tile.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/screens/quotations/quotation_details_screen.dart';
import 'package:mobo_sales/screens/quotations/create_quote_screen.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:mobo_sales/utils/date_picker_utils.dart';

import '../../providers/quotation_provider.dart';
import '../../services/connectivity_service.dart';
import '../../services/session_service.dart';
import '../../widgets/connection_status_widget.dart';
import '../../widgets/custom_snackbar.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/list_shimmer.dart';
import '../../models/quote.dart';

class QuotationListScreen extends StatefulWidget {
  final int? customerId;
  final Set<String>? initialFilters;

  final bool showForcedAppBar;
  final String? forcedAppBarTitle;

  final bool expiringSoonOnly;

  final String? invoiceName;

  const QuotationListScreen({
    super.key,
    this.customerId,
    this.initialFilters,
    this.showForcedAppBar = false,
    this.forcedAppBarTitle,
    this.expiringSoonOnly = false,
    this.invoiceName,
  });

  @override
  State<QuotationListScreen> createState() => _QuotationListScreenState();
}

class _QuotationListScreenState extends State<QuotationListScreen>
    with AutomaticKeepAliveClientMixin {
  final double _standardPadding = 16.0;
  final double _smallPadding = 8.0;
  final double _tinyPadding = 4.0;
  final double _cardBorderRadius = 12.0;
  bool _isActivePage = true;
  bool _hasLoaded = false;

  bool _isInitialLoad = true;

  QuotationProvider? _quotationProvider;
  bool _showScrollToTop = false;
  VoidCallback? _quotesScrollListener;

  final Map<String, bool> _expandedGroups = {};
  bool _allGroupsExpanded = false;

  Set<String> _activeFilters = {};
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedGroupBy;

  static const Map<String, String> kQuotationFilters = {
    'quotation': 'Quotations',
    'sale': 'Sale Orders',
    'user_quotations': 'My Quotations',
    'invoiced': 'Invoiced',
    'to_invoice': 'To Invoice',
    'delivered': 'Delivered',
    'to_deliver': 'To Deliver',
    'expired': 'Expired Quotes',
  };

  bool _isFilterDisabled(String filter, Set<String> selected) {
    if (selected.contains('quotation')) {
      return filter != 'quotation';
    }
    if (selected.contains('sale')) {
      return filter == 'quotation';
    }
    if (selected.contains('invoiced') || selected.contains('to_invoice')) {
      return filter == 'quotation';
    }
    if (selected.contains('delivered') || selected.contains('to_deliver')) {
      return filter == 'quotation';
    }
    return false;
  }

  Future<void> _clearSearchAndReload({bool resetFilters = false}) async {
    if (mounted) FocusScope.of(context).unfocus();

    final provider = Provider.of<QuotationProvider>(context, listen: false);

    provider.searchController.clear();

    if (resetFilters) {
      setState(() {
        _activeFilters.clear();
        _startDate = null;
        _endDate = null;
        _selectedGroupBy = null;
      });

      provider.setDateRange(null, null);
      await provider.loadQuotations(filters: const {}, clearGroupBy: true);
    } else {
      await provider.loadQuotations(
        filters: _activeFilters,
        groupBy: _selectedGroupBy,
      );
    }

    if (mounted) setState(() {});
  }

  void showQuotationFilterAndGroupByBottomSheet() async {
    try {
      final provider = Provider.of<QuotationProvider>(context, listen: false);

      _activeFilters = Set.from(provider.activeFilters);
      _startDate = provider.startDate;
      _endDate = provider.endDate;

      await provider.fetchGroupByOptions();

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: true,
        enableDrag: true,
        builder: (context) => DefaultTabController(
          length: 2,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              final theme = Theme.of(context);
              final isDark = theme.brightness == Brightness.dark;

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
                    children: [
                      Container(
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
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
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
                            _buildFilterTab(
                              context,
                              setDialogState,
                              isDark,
                              theme,
                              provider,
                            ),
                            _buildGroupByTab(
                              context,
                              setDialogState,
                              isDark,
                              theme,
                              provider,
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
                                  });

                                  Navigator.of(context).pop();

                                  final provider =
                                      Provider.of<QuotationProvider>(
                                        context,
                                        listen: false,
                                      );
                                  provider.setDateRange(null, null);
                                  await provider.loadQuotations(
                                    filters: const {},
                                    clearGroupBy: true,
                                  );
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

                                    provider.setDateRange(_startDate, _endDate);
                                    await provider.loadQuotations(
                                      filters: _activeFilters,
                                      groupBy: _selectedGroupBy,
                                    );

                                    int filterCount = 0;
                                    if (_activeFilters.contains('quotation')) {
                                      filterCount++;
                                    }
                                    if (_activeFilters.contains('sale')) {
                                      filterCount++;
                                    }
                                    if (_activeFilters.contains('invoiced')) {
                                      filterCount++;
                                    }
                                    if (_activeFilters.contains('to_invoice')) {
                                      filterCount++;
                                    }
                                    if (_activeFilters.contains('delivered')) {
                                      filterCount++;
                                    }
                                    if (_activeFilters.contains('to_deliver')) {
                                      filterCount++;
                                    }
                                    if (_activeFilters.contains('expired')) {
                                      filterCount++;
                                    }
                                    if (_activeFilters.contains(
                                      'user_quotations',
                                    )) {
                                      filterCount++;
                                    }
                                    if (_startDate != null) filterCount++;
                                    if (_endDate != null) filterCount++;
                                    if (provider
                                        .searchController
                                        .text
                                        .isNotEmpty) {
                                      filterCount++;
                                    }

                                    if (mounted) {
                                      CustomSnackbar.showInfo(
                                        context,
                                        filterCount == 0
                                            ? 'All filters cleared'
                                            : 'Applied $filterCount filter${filterCount > 1 ? 's' : ''}',
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
        ),
      );
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Failed to open filter dialog: ${e.toString()}',
        );
      }
    }
  }

  Widget _buildFilterTab(
    BuildContext context,
    StateSetter setDialogState,
    bool isDark,
    ThemeData theme,
    QuotationProvider provider,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_activeFilters.isNotEmpty) ...[
            Text(
              'Active Filters',
              style: theme.textTheme.labelMedium?.copyWith(
                color: isDark ? Colors.white : theme.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _activeFilters.map((filter) {
                final filterName = kQuotationFilters[filter] ?? filter;
                return Chip(
                  label: Text(filterName, style: const TextStyle(fontSize: 13)),
                  backgroundColor: isDark
                      ? Colors.white.withOpacity(.08)
                      : theme.primaryColor.withOpacity(0.08),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setDialogState(() {
                      _activeFilters.remove(filter);
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],

          Text(
            'Status',
            style: theme.textTheme.labelMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kQuotationFilters.entries.map((entry) {
              final selected = _activeFilters.contains(entry.key);
              final disabled = _isFilterDisabled(entry.key, _activeFilters);
              return ChoiceChip(
                label: Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: disabled
                        ? (isDark ? Colors.grey[700] : Colors.grey[400])
                        : (selected
                              ? Colors.white
                              : (isDark ? Colors.white : Colors.black87)),
                  ),
                ),
                selected: selected,
                selectedColor: theme.primaryColor,
                disabledColor: isDark ? Colors.grey[800] : Colors.grey[200],
                backgroundColor: isDark
                    ? Colors.white.withOpacity(.08)
                    : theme.primaryColor.withOpacity(0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                  ),
                ),
                onSelected: disabled
                    ? null
                    : (isSelected) {
                        setDialogState(() {
                          if (isSelected) {
                            _activeFilters.add(entry.key);
                          } else {
                            _activeFilters.remove(entry.key);
                          }
                        });
                      },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          Text(
            'Date Range (Creation Date)',
            style: theme.textTheme.labelMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start Date',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.grey[300] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        try {
                          final picked =
                              await DatePickerUtils.showStandardDatePicker(
                                context: context,
                                initialDate: _startDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 365),
                                ),
                              );
                          if (picked != null) {
                            setDialogState(() {
                              _startDate = picked;
                            });
                          }
                        } catch (e) {
                          if (mounted) {
                            CustomSnackbar.showError(
                              context,
                              'Failed to open date picker: ${e.toString()}',
                            );
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark
                                ? Colors.grey[600]!
                                : Colors.grey[400]!,
                          ),
                          borderRadius: BorderRadius.circular(8),
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
                                    ? DateFormat(
                                        'MMM dd, yyyy',
                                      ).format(_startDate!)
                                    : 'Select start date',
                                style: TextStyle(
                                  color: _startDate != null
                                      ? (isDark ? Colors.white : Colors.black87)
                                      : (isDark
                                            ? Colors.grey[500]
                                            : Colors.grey[500]),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'End Date',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.grey[300] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        try {
                          final picked =
                              await DatePickerUtils.showStandardDatePicker(
                                context: context,
                                initialDate: _endDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 365),
                                ),
                              );
                          if (picked != null) {
                            setDialogState(() {
                              _endDate = picked;
                            });
                          }
                        } catch (e) {
                          if (mounted) {
                            CustomSnackbar.showError(
                              context,
                              'Failed to open date picker: ${e.toString()}',
                            );
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark
                                ? Colors.grey[600]!
                                : Colors.grey[400]!,
                          ),
                          borderRadius: BorderRadius.circular(8),
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
                                    ? DateFormat(
                                        'MMM dd, yyyy',
                                      ).format(_endDate!)
                                    : 'Select end date',
                                style: TextStyle(
                                  color: _endDate != null
                                      ? (isDark ? Colors.white : Colors.black87)
                                      : (isDark
                                            ? Colors.grey[500]
                                            : Colors.grey[500]),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_startDate != null || _endDate != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  setDialogState(() {
                    _startDate = null;
                    _endDate = null;
                  });
                },
                icon: Icon(Icons.clear, size: 16, color: Colors.grey[600]),
                label: Text(
                  'Clear date range',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildGroupByTab(
    BuildContext context,
    StateSetter setDialogState,
    bool isDark,
    ThemeData theme,
    QuotationProvider provider,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Group quotations by',
            style: theme.textTheme.labelMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          RadioListTile<String?>(
            title: Text(
              'None',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              'Display as a simple list',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
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

          if (provider.groupByOptions.isEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'No group by options available',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Retry',
                  icon: Icon(
                    Icons.refresh,
                    color: isDark ? Colors.white : Colors.black54,
                  ),
                  onPressed: () async {
                    try {
                      await provider.fetchGroupByOptions();
                      setDialogState(() {});
                    } catch (_) {}
                  },
                ),
              ],
            ),
          ] else ...[
            ...provider.groupByOptions.entries.map((entry) {
              String description = '';
              switch (entry.key) {
                case 'user_id':
                  description = 'Group by assigned salesperson';
                  break;
                case 'partner_id':
                  description = 'Group by customer name';
                  break;
                case 'date_order:year':
                  description = 'Group quotations by year';
                  break;
                case 'date_order:quarter':
                  description = 'Group quotations by quarter (Q1, Q2, Q3, Q4)';
                  break;
                case 'date_order:month':
                  description = 'Group quotations by month';
                  break;
                case 'date_order:week':
                  description = 'Group quotations by week number';
                  break;
                case 'date_order:day':
                  description = 'Group quotations by specific day';
                  break;
                default:
                  description = 'Group by ${entry.value.toLowerCase()}';
              }

              return RadioListTile<String>(
                title: Text(
                  entry.value,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  description,
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
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
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = Provider.of<QuotationProvider>(context, listen: false);

      final isContextual =
          widget.customerId != null ||
          (widget.invoiceName != null && widget.invoiceName!.isNotEmpty);

      if (!isContextual) {
        provider.setCustomerFilter(null);
        provider.setInvoiceNameFilter(null);
      }

      if (isContextual ||
          (provider.allQuotations.isEmpty && !provider.isLoading)) {
        _loadQuotations();
      } else {
        setState(() {
          _isInitialLoad = false;
        });
      }

      _quotesScrollListener = () {
        final ctrl = provider.scrollController;
        final shouldShow = ctrl.hasClients && ctrl.offset > 300;
        if (shouldShow != _showScrollToTop) {
          if (mounted) {
            setState(() {
              _showScrollToTop = shouldShow;
            });
          }
        }
      };
      provider.scrollController.addListener(_quotesScrollListener!);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    try {
      _quotationProvider ??= Provider.of<QuotationProvider>(
        context,
        listen: false,
      );
    } catch (e) {
      return;
    }

    if (!_hasLoaded && _isActivePage && mounted && _quotationProvider != null) {
      final provider = _quotationProvider!;

      if (provider.accessErrorMessage == null &&
          ((widget.customerId != null) ||
              (widget.invoiceName != null && widget.invoiceName!.isNotEmpty) ||
              (provider.allQuotations.isEmpty && !provider.isLoading))) {
        _hasLoaded = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadQuotations();
        });
      }
    }
  }

  void _navigateToQuotationDetail(BuildContext context, Quote quotation) {
    _isActivePage = false;

    Navigator.push(
      context,

      MaterialPageRoute(
        builder: (context) => QuotationDetailScreen(quotation: quotation),
      ),
    ).then((_) {
      _isActivePage = true;
    });
  }

  Future<void> _loadQuotations() async {
    if (!mounted) return;

    _quotationProvider ??= Provider.of<QuotationProvider>(
      context,
      listen: false,
    );
    final provider = _quotationProvider!;

    if (provider.accessErrorMessage != null) {
      if (mounted) {
        setState(() {
          _isInitialLoad = false;
        });
      }
      return;
    }

    provider.setCustomerFilter(widget.customerId);

    if (widget.invoiceName != null && widget.invoiceName!.isNotEmpty) {
      provider.setInvoiceNameFilter(widget.invoiceName!.trim());
    } else {
      provider.setInvoiceNameFilter(null);
    }

    final Set<String> filtersToUse =
        widget.initialFilters ??
        (widget.customerId != null ? <String>{} : provider.activeFilters);

    await provider.loadQuotations(filters: filtersToUse);

    if (mounted) {
      setState(() {
        _isInitialLoad = false;
        _hasLoaded = true;
      });
    }

    if (provider.allQuotations.isNotEmpty) {
      for (int i = 0; i < provider.allQuotations.length && i < 3; i++) {
        final quotation = provider.allQuotations[i];
      }
    } else {}
  }

  Widget _buildContentArea(QuotationProvider provider, bool isDarkMode) {
    if (provider.accessErrorMessage != null) {
      return _buildAccessErrorWidget(provider, isDarkMode);
    }

    if (provider.allQuotations.isNotEmpty) {
      return _buildQuotationsList();
    }

    if (_isInitialLoad ||
        (provider.isLoading && provider.allQuotations.isEmpty)) {
      return _buildQuotationsListShimmer();
    }

    return _buildQuotationsList();
  }

  Widget _buildAccessErrorWidget(QuotationProvider provider, bool isDarkMode) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? Colors.white.withOpacity(0.06)
                    : Theme.of(context).colorScheme.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDarkMode
                      ? Colors.white.withOpacity(0.18)
                      : Theme.of(context).colorScheme.error.withOpacity(0.18),
                  width: 1.2,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: isDarkMode
                        ? Colors.white.withOpacity(0.85)
                        : Theme.of(context).colorScheme.error.withOpacity(0.85),
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Access Error',
                    style: TextStyle(
                      color: isDarkMode
                          ? Colors.white
                          : Theme.of(context).colorScheme.error,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    provider.accessErrorMessage!,
                    style: TextStyle(
                      color: isDarkMode
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
                        backgroundColor: isDarkMode
                            ? Colors.white.withOpacity(0.1)
                            : Theme.of(context).colorScheme.primary,
                        foregroundColor: isDarkMode
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
                        provider.loadQuotations(isLoadMore: false);
                      },
                      icon: Icon(Icons.refresh, size: 20),
                      label: Text(
                        'Retry',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
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

  Widget _buildQuotationsList() {
    return Consumer<QuotationProvider>(
      builder: (context, provider, child) {
        List quotations = provider.allQuotations;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final activeFilters = provider.activeFilters;
        final hasDateFilter =
            provider.startDate != null || provider.endDate != null;

        if (widget.initialFilters?.contains('expired') == true) {
          DateTime? parseDateOnly(dynamic v) {
            if (v == null) return null;
            final s = v.toString();
            if (s.isEmpty) return null;
            try {
              final datePart = s.length >= 10 ? s.substring(0, 10) : s;
              return DateTime.parse(datePart);
            } catch (_) {
              return null;
            }
          }

          final today = DateTime.now();
          final todayDateOnly = DateTime(today.year, today.month, today.day);
          quotations = quotations.where((q) {
            final state = (q['state'] ?? '').toString();
            if (state != 'draft' && state != 'sent') return false;
            final d = parseDateOnly(q['validity_date']);
            if (d == null) return false;
            return d.isBefore(todayDateOnly);
          }).toList();
        }

        if (widget.expiringSoonOnly) {
          DateTime? parseDateOnly(dynamic v) {
            if (v == null) return null;
            final s = v.toString();
            if (s.isEmpty) return null;
            try {
              final datePart = s.length >= 10 ? s.substring(0, 10) : s;
              return DateTime.parse(datePart);
            } catch (_) {
              return null;
            }
          }

          final now = DateTime.now();
          final from = DateTime(
            now.year,
            now.month,
            now.day,
          ).add(const Duration(days: 3));
          final to = DateTime(
            now.year,
            now.month,
            now.day,
          ).add(const Duration(days: 7));
          quotations = quotations.where((q) {
            final state = (q['state'] ?? '').toString();
            if (state != 'draft' && state != 'sent') return false;
            final d = parseDateOnly(q['validity_date']);
            if (d == null) return false;
            return !d.isBefore(from) && !d.isAfter(to);
          }).toList();
        }
        if (quotations.isEmpty) {
          if (provider.isLoading) {
            return _buildQuotationsListShimmer();
          }

          final hasActiveFilters =
              activeFilters.isNotEmpty ||
              provider.searchController.text.isNotEmpty ||
              hasDateFilter;

          final is404WithNoData =
              provider.errorMessage != null &&
              provider.errorMessage!.toLowerCase().contains('404') &&
              provider.allQuotations.isEmpty;

          if (!is404WithNoData &&
              (provider.isServerUnreachable ||
                  (provider.errorMessage != null &&
                      _isServerUnreachableError(provider.errorMessage!)))) {
            return ConnectionStatusWidget(
              serverUnreachable: true,
              serverErrorMessage: provider.errorMessage,
              onRetry: () => provider.refreshQuotations(),
            );
          }

          if (!is404WithNoData && provider.errorMessage != null) {
            return RefreshIndicator(
              onRefresh: () => provider.refreshQuotations(),
              child: CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyStateWidget(
                      icon: HugeIcons.strokeRoundedFileScript,
                      title: 'Error Loading Data',
                      message: provider.errorMessage!,
                      showRetry: true,
                      onRetry: () => provider.refreshQuotations(),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.refreshQuotations(),
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyStateWidget.quotations(
                    hasSearchQuery: provider.searchController.text.isNotEmpty,
                    hasFilters: hasActiveFilters,
                    onClearFilters: hasActiveFilters
                        ? () {
                            provider.searchController.clear();
                            provider.loadQuotations(filters: {});
                          }
                        : null,
                    onRetry: () {
                      provider.refreshQuotations();
                    },
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _handleRefresh,
          child: provider.isGrouped
              ? _buildGroupedQuotationsList(provider, isDark, activeFilters)
              : provider.isLoadingMore
              ? _buildQuotationsListShimmer()
              : ListView.builder(
                  controller: provider.scrollController,
                  itemCount: quotations.length,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemBuilder: (context, index) {
                    return _buildEnhancedQuotationCard(
                      quotations[index],
                      isDark,
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _buildGroupedQuotationsList(
    QuotationProvider provider,
    bool isDark,
    Set<String> activeFilters,
  ) {
    try {
      if (provider.groupSummary.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.group_work_outlined,
                  size: 64,
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading groups...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please wait while we organize your quotations',
                  style: TextStyle(
                    color: isDark ? Colors.grey[500] : Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }

      for (final groupKey in provider.groupSummary.keys) {
        if (!_expandedGroups.containsKey(groupKey)) {
          _expandedGroups[groupKey] = false;
        }
      }

      _expandedGroups.removeWhere(
        (key, value) => !provider.groupSummary.containsKey(key),
      );

      return Expanded(
        child: ListView.builder(
          controller: provider.scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: provider.groupSummary.keys.length,
          itemBuilder: (context, index) {
            try {
              final groupKey = provider.groupSummary.keys.elementAt(index);
              final count = provider.groupSummary[groupKey]!;
              final isExpanded = _expandedGroups[groupKey] ?? false;
              final loadedQuotations = provider.loadedGroups[groupKey] ?? [];

              return _buildOdooStyleGroupTile(
                groupKey,
                count,
                isExpanded,
                loadedQuotations,
                provider,
                isDark,
              );
            } catch (e) {
              return const SizedBox.shrink();
            }
          },
        ),
      );
    } catch (e) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: isDark ? Colors.red[400] : Colors.red[600],
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading groups',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.red[400] : Colors.red[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please try refreshing the page',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildOdooStyleGroupTile(
    String groupKey,
    int count,
    bool isExpanded,
    List<Quote> loadedQuotations,
    QuotationProvider provider,
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

                if (!isExpanded && loadedQuotations.isEmpty) {
                  await provider.loadGroupQuotations(groupKey);
                }
              } catch (e) {}
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          groupKey.isNotEmpty ? groupKey : 'Unknown Group',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$count quotation${count != 1 ? 's' : ''}',
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
          if (isExpanded)
            loadedQuotations.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(24),
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
                  )
                : Column(
                    children: loadedQuotations.map((quotation) {
                      try {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: _buildEnhancedQuotationCard(quotation, isDark),
                        );
                      } catch (e) {
                        return const SizedBox.shrink();
                      }
                    }).toList(),
                  ),
        ],
      ),
    );
  }

  Widget _buildEnhancedQuotationCard(Quote quotation, bool isDark) {
    final quotationId = quotation.name;
    final customer = quotation.customerName ?? 'Unknown';
    final dateOrder = quotation.dateOrder?.toIso8601String();
    final validityDate = quotation.validityDate?.toIso8601String();
    final totalAmount = quotation.total;
    final state = quotation.status;
    final currencyId =
        (quotation.extraData != null &&
            quotation.extraData!['currency_id'] is List)
        ? quotation.extraData!['currency_id'] as List<dynamic>?
        : null;

    Color getStatusColor(String s) {
      switch (s) {
        case 'sale':
          return Colors.green;
        case 'draft':
          return Colors.orange;
        case 'sent':
          return Colors.blue;
        case 'cancel':
          return Colors.red;
        case 'expired':
          return Colors.grey;
        default:
          return Theme.of(context).primaryColor;
      }
    }

    String getStatusLabel(String s) {
      switch (s) {
        case 'sale':
          return 'Sale Order';
        case 'draft':
          return 'Quotation';
        case 'sent':
          return 'Sent';
        case 'cancel':
          return 'Cancelled';
        case 'expired':
          return 'Expired';
        default:
          return s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : 'Unknown';
      }
    }

    Widget? popup;

    if (state == 'draft' || state == 'sent' || state == 'cancel') {
      popup = PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        splashRadius: 14,
        color: isDark ? Colors.grey[900] : Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onSelected: (value) async {
          if (value == 'convert') {
            final confirmed = await _showConvertToSaleOrderDialog(
              context,
              quotation,
            );
            if (confirmed == true) {
              _convertToOrder(context, quotation);
            }
          } else if (value == 'cancel') {
            _confirmCancelQuotation(context, quotation);
          } else if (value == 'delete') {
            _confirmDeleteQuotation(context, quotation);
          } else if (value == 'print') {
            CustomSnackbar.showInfo(context, 'Printing quotation...');
          }
        },
        itemBuilder: (context) {
          List<PopupMenuEntry<String>> items = [];

          if (state == 'draft' || state == 'sent') {
            items.add(
              PopupMenuItem<String>(
                value: 'convert',
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
            );
          }
          if (state != 'sale' && state != 'cancel') {
            items.add(
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
            );
          }

          if (state == 'draft' || state == 'cancel') {
            items.add(
              PopupMenuItem<String>(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      HugeIcons.strokeRoundedDelete02,
                      color: Colors.red[400],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Delete',
                      style: TextStyle(
                        color: Colors.red[400],
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return items;
        },

        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: Icon(
              Icons.more_vert,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              size: 20,
            ),
          ),
        ),
      );
    }

    String infoLine = _formatDateSafe(dateOrder);
    String? extraInfoLine =
        validityDate != null && validityDate.isNotEmpty && validityDate != 'N/A'
        ? 'Valid until ${_formatDateSafe(validityDate, format: 'MMM dd', fallback: '')}'
        : null;

    return OrderLikeListTile(
      id: quotationId,
      customer: customer,
      infoLine: infoLine,
      extraInfoLine: extraInfoLine,
      amount: totalAmount,
      currencyId: currencyId,
      status: getStatusLabel(state),
      statusColor: getStatusColor(state),
      isDark: isDark,
      onTap: () => _navigateToQuotationDetail(context, quotation),
      popupMenu: popup,
      mainIcon: HugeIcons.strokeRoundedCalendar03,
      extraIcon: HugeIcons.strokeRoundedCalendar01,
      amountLabel: 'Total Amount',
    );
  }

  Widget _buildEmptyState(bool isDark, Set<String> activeFilters) {
    final isFilteredByInvoice =
        widget.invoiceName != null && widget.invoiceName!.isNotEmpty;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        Colors.blue[900]!.withOpacity(0.3),
                        Colors.blue[800]!.withOpacity(0.1),
                      ]
                    : [Colors.blue[50]!, Colors.blue[100]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(
              HugeIcons.strokeRoundedNote02,
              size: 64,
              color: isDark ? Colors.blue[300] : Colors.blue[600],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            isFilteredByInvoice
                ? 'No Related Sale Orders'
                : activeFilters.isEmpty
                ? 'No Quotations Found'
                : 'No Matching Quotations',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.grey[800],
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isFilteredByInvoice
                ? 'Invoice ${widget.invoiceName} doesn\'t have any associated sale orders'
                : activeFilters.isEmpty
                ? 'Create your first quotation to get started'
                : 'Try adjusting your filters to see more results',
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          if (activeFilters.isNotEmpty) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Provider.of<QuotationProvider>(
                  context,
                  listen: false,
                ).loadQuotations(filters: {});
              },
              icon: Icon(Icons.clear_all, color: Colors.white),
              label: Text('Clear Filters'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingMoreIndicator() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.all(_standardPadding),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: Consumer<QuotationProvider>(
            builder: (context, provider, child) {
              return provider.isLoadingMore
                  ? CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDark ? Colors.white : Theme.of(context).primaryColor,
                      ),
                      strokeWidth: 2,
                    )
                  : SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAllQuotationsFetched(int count, Set<String> filters) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final textColor = isDark
        ? (Colors.grey[400] ?? const Color(0xFFBDBDBD))
        : (Colors.grey[600] ?? const Color(0xFF757575));

    String label;
    if (filters.isEmpty) {
      label = 'All quotations';
    } else {
      label = filters.map((f) => kQuotationFilters[f] ?? f).join(', ');
    }

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
          '$label loaded ($count total)',
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

  Widget _buildQuotationsListShimmer() {
    return ListShimmer.buildListShimmer(
      context,
      itemCount: 8,
      type: ShimmerType.standard,
    );
  }

  Future<bool?> _showConvertToSaleOrderDialog(
    BuildContext context,
    Quote quotation,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final quotationName = quotation.name;

    return await showDialog<bool>(
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
  }

  Future<void> _convertToOrder(BuildContext context, Quote quotation) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withOpacity(0.3)
                        : Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
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
        );
      },
    );

    try {
      final provider = _quotationProvider!;
      await provider
          .convertQuotationToOrder(quotation.id!)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException(
              'The server took too long to respond. Please try again.',
            ),
          );

      if (context.mounted) {
        Navigator.of(context).pop();

        Future.delayed(const Duration(milliseconds: 100), () {
          if (context.mounted) {
            CustomSnackbar.showSuccess(
              context,
              'Quotation converted to sale order successfully',
            );
          }
        });
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
      }
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
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[900]
              : Colors.white,
          title: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red[400], size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Conversion Failed',
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
                  msg,
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
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _convertToOrder(context, quotation);
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
  }

  String _safeString(dynamic value) {
    if (value is String) return value;
    if (value is bool) return value ? 'true' : 'N/A';
    if (value == null) return 'N/A';
    return value.toString();
  }

  String getCustomerName(dynamic partnerId) {
    if (partnerId is List && partnerId.length > 1) {
      return _safeString(partnerId[1]);
    }
    return 'Unknown';
  }

  String _formatDateSafe(
    String? dateString, {
    String format = 'MMM dd, yyyy',
    String fallback = 'Not specified',
  }) {
    if (dateString == null || dateString.isEmpty || dateString == 'N/A') {
      return fallback;
    }
    try {
      final date = DateTime.parse(dateString);
      return DateFormat(format).format(date);
    } catch (e) {
      return fallback;
    }
  }

  Future<void> _handleRefresh() async {
    final provider = _quotationProvider!;

    setState(() {
      _isInitialLoad = true;
    });

    provider.clearCache();
    await provider.loadQuotations(filters: provider.activeFilters);

    if (mounted) {
      setState(() {
        _isInitialLoad = false;
      });
    }
  }

  void _confirmDeleteQuotation(BuildContext context, Quote quotation) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final quotationName = quotation.name;
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
        final provider = Provider.of<QuotationProvider>(context, listen: false);
        await provider.deleteQuotation(quotation.id!);
        if (context.mounted) {
          Navigator.of(context).pop();

          Future.delayed(const Duration(milliseconds: 100), () {
            if (context.mounted) {
              CustomSnackbar.showSuccess(
                context,
                'Quotation deleted successfully',
              );
            }
          });
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.of(context).pop();
          CustomSnackbar.showError(context, 'Failed to delete quotation: $e');
        }
      }
    }
  }

  void _confirmCancelQuotation(BuildContext context, Quote quotation) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final quotationName = quotation.name;

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
                    'Cancelling Quotation',
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
        final provider = Provider.of<QuotationProvider>(context, listen: false);
        await provider.cancelQuotation(quotation.id!);
        if (context.mounted) {
          Navigator.of(context).pop();

          Future.delayed(const Duration(milliseconds: 100), () {
            if (context.mounted) {
              CustomSnackbar.showSuccess(
                context,
                'Quotation cancelled successfully',
              );
            }
          });
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.of(context).pop();
          CustomSnackbar.showError(context, 'Failed to cancel quotation: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? Colors.grey[900] : Colors.grey[50];
    final primaryColor = Theme.of(context).primaryColor;
    final bool isFilteredByCustomer = widget.customerId != null;
    final bool isFilteredByInvoice = widget.invoiceName != null;

    final bool shouldShowAppBar =
        widget.showForcedAppBar || isFilteredByCustomer || isFilteredByInvoice;

    return Consumer<QuotationProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          backgroundColor: backgroundColor,
          appBar: shouldShowAppBar
              ? AppBar(
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.forcedAppBarTitle ??
                            (isFilteredByCustomer
                                ? 'Customer Quotations'
                                : isFilteredByInvoice
                                ? 'Related Sale Orders'
                                : 'Quotations'),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                          letterSpacing: 0.5,
                          color: isDarkMode ? Colors.white : primaryColor,
                        ),
                      ),
                      if (isFilteredByInvoice)
                        Text(
                          'Invoice: ${widget.invoiceName}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: isDarkMode
                                ? Colors.white.withOpacity(0.7)
                                : primaryColor.withOpacity(0.7),
                          ),
                        ),
                    ],
                  ),
                  leading: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(HugeIcons.strokeRoundedArrowLeft01),
                  ),
                  backgroundColor: backgroundColor,
                  foregroundColor: isDarkMode ? Colors.white : primaryColor,
                  elevation: 0,
                )
              : null,
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  top: 0.0,
                  left: 16.0,
                  right: 16.0,
                  bottom: 16.0,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
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
                              controller: provider.searchController,
                              enabled: !provider.isLoading,
                              style: TextStyle(
                                color: isDarkMode
                                    ? Colors.white
                                    : Color(0xff1E1E1E),
                                fontWeight: FontWeight.w400,
                                fontStyle: FontStyle.normal,
                                fontSize: 15,
                                height: 1.0,
                                letterSpacing: 0.0,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Search by quotation ID or customer...',
                                hintStyle: TextStyle(
                                  color: isDarkMode
                                      ? Colors.white
                                      : Color(0xff1E1E1E),
                                  fontWeight: FontWeight.w400,
                                  fontStyle: FontStyle.normal,
                                  fontSize: 15,
                                  height: 1.0,
                                  letterSpacing: 0.0,
                                ),
                                prefixIcon: IconButton(
                                  onPressed: provider.isLoading
                                      ? null
                                      : () =>
                                            showQuotationFilterAndGroupByBottomSheet(),
                                  icon: Icon(
                                    HugeIcons.strokeRoundedFilterHorizontal,
                                    color: isDarkMode
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                    size: 18,
                                  ),
                                  tooltip: 'Filter & Group By',
                                  splashRadius: 20,
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                ),
                                suffixIcon:
                                    provider.searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(
                                          Icons.clear,
                                          color: isDarkMode
                                              ? Colors.grey[400]
                                              : Colors.grey,
                                        ),
                                        onPressed: provider.isLoading
                                            ? null
                                            : () {
                                                _clearSearchAndReload();
                                              },
                                      )
                                    : null,
                                filled: true,
                                fillColor: isDarkMode
                                    ? Colors.grey[850]
                                    : Colors.white,
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
                      ],
                    ),
                  ],
                ),
              ),

              Builder(
                builder: (context) {
                  final provider = context.read<QuotationProvider>();

                  if (!_hasLoaded && provider.allQuotations.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final paginationText = provider.getPaginationText();
                  if (paginationText == "0 items") {
                    return const SizedBox.shrink();
                  }

                  final activeFilters = provider.activeFilters;
                  final hasDateFilter =
                      provider.startDate != null || provider.endDate != null;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Row(
                      children: [
                        _buildFilterIndicator(
                          provider,
                          isDarkMode,
                          activeFilters,
                          hasDateFilter,
                          provider.isGrouped,
                        ),
                        if (provider.isGrouped) ...[
                          const SizedBox(width: 8),
                          _buildGroupByPill(
                            isDarkMode,
                            _getGroupByDisplayName(provider.selectedGroupBy),
                          ),
                        ],
                        const Spacer(),
                        _buildTopPaginationBar(provider, isDarkMode),
                        if (!provider.isGrouped) ...[
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap:
                                    (provider.canGoToPreviousPage &&
                                        !provider.isLoading)
                                    ? () => provider.goToPreviousPage()
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8.0,
                                    horizontal: 4,
                                  ),
                                  child: Icon(
                                    HugeIcons.strokeRoundedArrowLeft01,
                                    size: 20,
                                    color:
                                        (provider.canGoToPreviousPage &&
                                            !provider.isLoading)
                                        ? (isDarkMode
                                              ? Colors.white
                                              : Colors.black87)
                                        : (isDarkMode
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
                                onTap:
                                    (provider.canGoToNextPage &&
                                        !provider.isLoading)
                                    ? () => provider.goToNextPage()
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8.0,
                                    horizontal: 4,
                                  ),
                                  child: Icon(
                                    HugeIcons.strokeRoundedArrowRight01,
                                    size: 20,
                                    color:
                                        (provider.canGoToNextPage &&
                                            !provider.isLoading)
                                        ? (isDarkMode
                                              ? Colors.white
                                              : Colors.black87)
                                        : (isDarkMode
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
                    if (!connectivityService.isConnected) {
                      return ConnectionStatusWidget(
                        onRetry: () {
                          if (connectivityService.isConnected &&
                              sessionService.hasValidSession) {
                            _loadQuotations();
                          }
                        },
                        customMessage:
                            'No internet connection. Please check your connection and try again.',
                      );
                    }

                    if (provider.isServerUnreachable) {
                      return ConnectionStatusWidget(
                        serverUnreachable: true,
                        serverErrorMessage:
                            'Unable to load quotations from server/database. Please check your server or try again.',
                        onRetry: () {
                          if (connectivityService.isConnected &&
                              sessionService.hasValidSession) {
                            provider.clearServerUnreachableState();
                            _loadQuotations();
                          }
                        },
                      );
                    }

                    if (provider.accessErrorMessage != null) {
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
                                  color: isDarkMode
                                      ? Colors.white.withOpacity(0.06)
                                      : Theme.of(
                                          context,
                                        ).colorScheme.error.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isDarkMode
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
                                      color: isDarkMode
                                          ? Colors.white.withOpacity(0.85)
                                          : Theme.of(context).colorScheme.error
                                                .withOpacity(0.85),
                                      size: 48,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Access Error',
                                      style: TextStyle(
                                        color: isDarkMode
                                            ? Colors.white
                                            : Theme.of(
                                                context,
                                              ).colorScheme.error,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      provider.accessErrorMessage!,
                                      style: TextStyle(
                                        color: isDarkMode
                                            ? Colors.white.withOpacity(0.8)
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .error
                                                  .withOpacity(0.8),
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
                                          backgroundColor: isDarkMode
                                              ? Colors.white.withOpacity(0.1)
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                          foregroundColor: isDarkMode
                                              ? Colors.white
                                              : Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          elevation: 0,
                                        ),
                                        onPressed: () {
                                          provider.loadQuotations(
                                            isLoadMore: false,
                                          );
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

                    return _buildContentArea(provider, isDarkMode);
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
                          heroTag: 'fab_scroll_top_quotations',
                          mini: true,
                          onPressed: () {
                            final ctrl = provider.scrollController;
                            if (ctrl.hasClients) {
                              ctrl.animateTo(
                                0,
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeOut,
                              );
                            }
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
                      heroTag: 'fab_create_quote',
                      onPressed: () async {
                        final isIOS =
                            Theme.of(context).platform == TargetPlatform.iOS;
                        final result = await Navigator.push(
                          context,

                          MaterialPageRoute(
                            builder: (context) => const CreateQuoteScreen(),
                          ),
                        );
                        if (result == true) {
                          await provider.refreshQuotations();
                        }
                      },
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Theme.of(context).primaryColor,
                      tooltip: 'Create Quotation',
                      child: Icon(
                        HugeIcons.strokeRoundedFileAdd,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.black
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  void _showFilterDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 400,
                  maxHeight: 600,
                ),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.grey[850]
                            : Theme.of(context).primaryColor.withOpacity(0.05),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            HugeIcons.strokeRoundedFilterHorizontal,
                            color: Theme.of(context).primaryColor,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Filter Quotations',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.grey[800],
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(
                              Icons.close,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),

                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Status',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Consumer<QuotationProvider>(
                              builder: (context, provider, child) {
                                Set<String> dialogFilters = Set.from(
                                  provider.activeFilters,
                                );

                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: kQuotationFilters.entries.map((
                                    entry,
                                  ) {
                                    final isSelected = dialogFilters.contains(
                                      entry.key,
                                    );
                                    return FilterChip(
                                      label: Text(entry.value),
                                      selected: isSelected,
                                      onSelected: (selected) {
                                        setDialogState(() {
                                          if (selected) {
                                            dialogFilters.add(entry.key);
                                          } else {
                                            dialogFilters.remove(entry.key);
                                          }
                                        });
                                      },
                                      backgroundColor: isDark
                                          ? Colors.grey[800]
                                          : Colors.grey[100],
                                      selectedColor: Theme.of(
                                        context,
                                      ).primaryColor.withOpacity(0.2),
                                      checkmarkColor: Theme.of(
                                        context,
                                      ).primaryColor,
                                      labelStyle: TextStyle(
                                        color: isSelected
                                            ? Theme.of(context).primaryColor
                                            : (isDark
                                                  ? Colors.grey[300]
                                                  : Colors.grey[700]),
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Date Range (Creation Date)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Consumer<QuotationProvider>(
                              builder: (context, provider, child) {
                                return Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Start Date',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: isDark
                                                  ? Colors.grey[300]
                                                  : Colors.grey[600],
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          InkWell(
                                            onTap: () async {
                                              final picked =
                                                  await showDatePicker(
                                                    context: context,
                                                    initialDate:
                                                        provider.startDate ??
                                                        DateTime.now(),
                                                    firstDate: DateTime(2000),
                                                    lastDate: DateTime.now()
                                                        .add(
                                                          const Duration(
                                                            days: 365,
                                                          ),
                                                        ),
                                                  );
                                              if (picked != null) {
                                                provider.setDateRange(
                                                  picked,
                                                  provider.endDate,
                                                );
                                              }
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 12,
                                                  ),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: isDark
                                                      ? Colors.grey[600]!
                                                      : Colors.grey[400]!,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
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
                                                      provider.startDate != null
                                                          ? DateFormat(
                                                              'MMM dd, yyyy',
                                                            ).format(
                                                              provider
                                                                  .startDate!,
                                                            )
                                                          : 'Select start date',
                                                      style: TextStyle(
                                                        color:
                                                            provider.startDate !=
                                                                null
                                                            ? (isDark
                                                                  ? Colors.white
                                                                  : Colors
                                                                        .black87)
                                                            : (isDark
                                                                  ? Colors
                                                                        .grey[500]
                                                                  : Colors
                                                                        .grey[500]),
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'End Date',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: isDark
                                                  ? Colors.grey[300]
                                                  : Colors.grey[600],
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          InkWell(
                                            onTap: () async {
                                              final picked =
                                                  await showDatePicker(
                                                    context: context,
                                                    initialDate:
                                                        provider.endDate ??
                                                        DateTime.now(),
                                                    firstDate: DateTime(2000),
                                                    lastDate: DateTime.now()
                                                        .add(
                                                          const Duration(
                                                            days: 365,
                                                          ),
                                                        ),
                                                  );
                                              if (picked != null) {
                                                provider.setDateRange(
                                                  provider.startDate,
                                                  picked,
                                                );
                                              }
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 12,
                                                  ),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: isDark
                                                      ? Colors.grey[600]!
                                                      : Colors.grey[400]!,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
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
                                                      provider.endDate != null
                                                          ? DateFormat(
                                                              'MMM dd, yyyy',
                                                            ).format(
                                                              provider.endDate!,
                                                            )
                                                          : 'Select end date',
                                                      style: TextStyle(
                                                        color:
                                                            provider.endDate !=
                                                                null
                                                            ? (isDark
                                                                  ? Colors.white
                                                                  : Colors
                                                                        .black87)
                                                            : (isDark
                                                                  ? Colors
                                                                        .grey[500]
                                                                  : Colors
                                                                        .grey[500]),
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Consumer<QuotationProvider>(
                              builder: (context, provider, child) {
                                if (provider.startDate != null ||
                                    provider.endDate != null) {
                                  return TextButton.icon(
                                    onPressed: () {
                                      provider.setDateRange(null, null);
                                    },
                                    icon: Icon(
                                      Icons.clear,
                                      size: 16,
                                      color: Colors.grey[600],
                                    ),
                                    label: Text(
                                      'Clear date range',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),

                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.grey[850]
                                    : Colors.grey[50],
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(16),
                                  bottomRight: Radius.circular(16),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Consumer<QuotationProvider>(
                                      builder: (context, provider, child) {
                                        return OutlinedButton(
                                          onPressed: () {
                                            provider.loadQuotations(
                                              filters: {},
                                            );
                                            Navigator.of(context).pop();
                                          },
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                            side: BorderSide(
                                              color: isDark
                                                  ? Colors.grey[600]!
                                                  : Colors.grey[400]!,
                                            ),
                                          ),
                                          child: Text(
                                            'Clear All',
                                            style: TextStyle(
                                              color: isDark
                                                  ? Colors.grey[300]
                                                  : Colors.grey[700],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        _loadQuotations();
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(
                                          context,
                                        ).primaryColor,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                      ),
                                      child: const Text(
                                        'Apply Filters',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
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
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPaginationControls(QuotationProvider provider, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4.0),
          child: InkWell(
            onTap: provider.canGoToPreviousPage && !provider.isLoadingMore
                ? () async {
                    try {
                      await provider.goToPreviousPage();
                    } catch (e) {
                      if (mounted) {
                        CustomSnackbar.showError(
                          context,
                          'Error loading previous page: $e',
                        );
                      }
                    }
                  }
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
              child: Icon(
                HugeIcons.strokeRoundedArrowLeft01,
                size: 20,
                color: provider.canGoToPreviousPage && !provider.isLoadingMore
                    ? (isDark ? Colors.white : Colors.black87)
                    : (isDark ? Colors.grey[600] : Colors.grey[400]),
              ),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4.0),
          child: InkWell(
            onTap: provider.canGoToNextPage && !provider.isLoadingMore
                ? () async {
                    try {
                      await provider.goToNextPage();
                    } catch (e) {
                      if (mounted) {
                        CustomSnackbar.showError(
                          context,
                          'Error loading next page: $e',
                        );
                      }
                    }
                  }
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
              child: Icon(
                HugeIcons.strokeRoundedArrowRight01,
                size: 20,
                color: provider.canGoToNextPage && !provider.isLoadingMore
                    ? (isDark ? Colors.white : Colors.black87)
                    : (isDark ? Colors.grey[600] : Colors.grey[400]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterIndicator(
    QuotationProvider provider,
    bool isDark,
    Set<String> activeFilters,
    bool hasDateFilter,
    bool hasGroupBy,
  ) {
    int count = 0;
    if (activeFilters.contains('quotation')) count++;
    if (activeFilters.contains('sale')) count++;
    if (activeFilters.contains('invoiced')) count++;
    if (activeFilters.contains('to_invoice')) count++;
    if (activeFilters.contains('delivered')) count++;
    if (activeFilters.contains('to_deliver')) count++;
    if (activeFilters.contains('expired')) count++;
    if (activeFilters.contains('user_quotations')) count++;
    if (_startDate != null) count++;
    if (_endDate != null) count++;
    if (provider.searchController.text.isNotEmpty) count++;

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
            color: isDark ? Colors.white70 : Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white70 : Colors.black,
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
              color: isDark ? Colors.black : Colors.white,
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

  String _getGroupByDisplayName(String? groupBy) {
    if (groupBy == null) return '';

    const groupByOptions = {
      'user_id': 'Salesperson',
      'partner_id': 'Customer',
      'state': 'Status',
      'company_id': 'Company',
      'date_order': 'Order Date',
    };

    return groupByOptions[groupBy] ?? groupBy;
  }

  Widget _buildTopPaginationBar(QuotationProvider provider, bool isDark) {
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
        provider.getPaginationText(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.grey[300] : Colors.grey[700],
        ),
      ),
    );
  }

  bool _hasActiveFilters(Set<String> activeFilters, bool hasDateFilter) {
    final provider = Provider.of<QuotationProvider>(context, listen: false);
    return activeFilters.isNotEmpty ||
        hasDateFilter ||
        provider.searchController.text.isNotEmpty;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    try {
      final provider =
          _quotationProvider ??
          (mounted
              ? Provider.of<QuotationProvider>(context, listen: false)
              : null);
      if (provider != null && _quotesScrollListener != null) {
        provider.scrollController.removeListener(_quotesScrollListener!);
      }
    } catch (_) {}

    if ((widget.customerId != null || widget.invoiceName != null) &&
        _quotationProvider != null) {
      _quotationProvider!.setCustomerFilter(null);
      _quotationProvider!.setInvoiceNameFilter(null);
      _quotationProvider!.clearCache();

      _quotationProvider!.loadQuotations(filters: {}, clearGroupBy: false);
    }

    try {
      final hadExpiredFilter =
          widget.initialFilters?.contains('expired') == true;
      if (hadExpiredFilter || widget.expiringSoonOnly) {
        final provider2 =
            _quotationProvider ??
            (mounted
                ? Provider.of<QuotationProvider>(context, listen: false)
                : null);
        if (provider2 != null) {
          provider2.setDateRange(null, null);

          provider2.loadQuotations(filters: {}, clearGroupBy: true);
        }
      }
    } catch (_) {}

    super.dispose();
  }

  bool _isServerUnreachableError(String error) {
    final errorString = error.toLowerCase();
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
}

class AccessErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const AccessErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? Colors.white.withOpacity(0.06)
        : Theme.of(context).colorScheme.error.withOpacity(0.08);
    final borderColor = isDark
        ? Colors.white.withOpacity(0.18)
        : Theme.of(context).colorScheme.error.withOpacity(0.18);
    final textColor = isDark
        ? Colors.white
        : Theme.of(context).colorScheme.error;
    final buttonColor = isDark
        ? Colors.white
        : Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, color: textColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: buttonColor,
              side: BorderSide(color: buttonColor.withOpacity(0.7)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
