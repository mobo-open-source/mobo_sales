import 'dart:async';
import 'package:flutter/material.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:mobo_sales/widgets/order_like_list_tile.dart';
import 'package:shimmer/shimmer.dart';
import '../../models/delivery.dart';
import '../../utils/date_picker_utils.dart';
import '../../services/odoo_session_manager.dart';
import '../../widgets/connection_status_widget.dart';
import '../../widgets/empty_state_widget.dart';
import 'delivery_details_screen.dart';

class DeliveryListScreen extends StatefulWidget {
  final String? saleOrderName;

  const DeliveryListScreen({super.key, this.saleOrderName});

  @override
  State<DeliveryListScreen> createState() => _DeliveryListScreenState();
}

class _DeliveryListScreenState extends State<DeliveryListScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Delivery>? _deliveries;
  bool _isLoading = true;
  bool _isServerUnreachable = false;
  String? _accessErrorMessage;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  final Set<String> _activeFilters = {};
  DateTime? _startDate;
  DateTime? _endDate;

  String? _selectedGroupBy;
  bool _isGrouped = false;
  Map<String, List<Delivery>> _groupedDeliveries = {};
  final Map<String, bool> _expandedGroups = {};
  bool _allGroupsExpanded = false;

  static const Map<String, String> _deliveryStatusFilters = {
    'draft': 'Draft',
    'waiting': 'Waiting',
    'confirmed': 'Confirmed',
    'assigned': 'Ready',
    'done': 'Done',
    'cancel': 'Cancelled',
  };

  static const Map<String, String> _groupByOptions = {
    'state': 'Status',
    'partner_id': 'Customer',
    'scheduled_date': 'Scheduled Date',
  };

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchDeliveries();
    });
  }

  void _onSearchChanged() {
    final newText = _searchController.text.trim();
    if (newText == _searchQuery) return;

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _searchQuery = newText;
      });
      _fetchDeliveries();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchDeliveries() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _accessErrorMessage = null;
      _isServerUnreachable = false;
    });

    try {
      List<dynamic> domain = [
        ['picking_type_code', '=', 'outgoing'],
      ];

      if (widget.saleOrderName != null) {
        domain.add(['origin', 'ilike', widget.saleOrderName]);
      }

      if (_searchQuery.isNotEmpty) {
        domain.add('|');
        domain.add(['name', 'ilike', _searchQuery]);
        domain.add(['partner_id.name', 'ilike', _searchQuery]);
      }

      if (_activeFilters.isNotEmpty) {
        if (_activeFilters.length == 1) {
          domain.add(['state', '=', _activeFilters.first]);
        } else {
          domain.add(['state', 'in', _activeFilters.toList()]);
        }
      }

      if (_startDate != null) {
        domain.add(['scheduled_date', '>=', _startDate!.toIso8601String()]);
      }
      if (_endDate != null) {
        domain.add(['scheduled_date', '<=', _endDate!.toIso8601String()]);
      }

      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final result = await client.callKw({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'domain': domain,
          'fields': [
            'name',
            'state',
            'partner_id',
            'scheduled_date',
            'date_deadline',
            'origin',
            'picking_type_code',
            'location_id',
            'location_dest_id',
            'picking_type_id',
          ],
          'order': 'scheduled_date desc, id desc',
          'limit': 100,
        },
      });

      if (!mounted) return;

      if (result is List) {
        setState(() {
          _deliveries = result
              .map((json) => Delivery.fromJson(json as Map<String, dynamic>))
              .toList();
          _isLoading = false;
        });
      } else {
        throw Exception('Unexpected response format');
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _deliveries = null;
        _isLoading = false;
        _accessErrorMessage = e.toString();
        _isServerUnreachable = _isServerUnreachableError(e);
      });
    }
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

              return Container(
                height: MediaQuery.of(context).size.height * 0.8,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF232323) : Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
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
                          _buildFilterTab(isDark, setDialogState, theme),
                          _buildGroupByTab(isDark, setDialogState, theme),
                        ],
                      ),
                    ),

                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: isDark
                                ? Colors.grey[800]!
                                : Colors.grey[200]!,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setDialogState(() {
                                  _activeFilters.clear();
                                  _startDate = null;
                                  _endDate = null;
                                  _selectedGroupBy = null;
                                  _isGrouped = false;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Clear All'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                setState(() {
                                  if (_selectedGroupBy != null) {
                                    _isGrouped = true;
                                    _groupDeliveries();
                                  } else {
                                    _isGrouped = false;
                                  }
                                });
                                _fetchDeliveries();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.primaryColor,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
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
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildFilterTab(
    bool isDark,
    StateSetter setDialogState,
    ThemeData theme,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_activeFilters.isNotEmpty ||
              _startDate != null ||
              _endDate != null) ...[
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
              children: [
                if (_activeFilters.isNotEmpty)
                  Chip(
                    label: Text(
                      'Status (${_activeFilters.length})',
                      style: const TextStyle(fontSize: 13),
                    ),
                    backgroundColor: isDark
                        ? Colors.white.withOpacity(.08)
                        : theme.primaryColor.withOpacity(0.08),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setDialogState(() {
                        _activeFilters.clear();
                      });
                    },
                  ),
                if (_startDate != null || _endDate != null)
                  Chip(
                    label: const Text(
                      'Date Range',
                      style: TextStyle(fontSize: 13),
                    ),
                    backgroundColor: isDark
                        ? Colors.white.withOpacity(.08)
                        : theme.primaryColor.withOpacity(0.08),
                    deleteIcon: const Icon(Icons.close, size: 16),
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
            style: theme.textTheme.labelMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _deliveryStatusFilters.entries.map((entry) {
              final isSelected = _activeFilters.contains(entry.key);
              return ChoiceChip(
                label: Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? Colors.white : Colors.black87),
                  ),
                ),
                selected: isSelected,
                selectedColor: theme.primaryColor,
                backgroundColor: isDark
                    ? Colors.white.withOpacity(.08)
                    : theme.primaryColor.withOpacity(0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                  ),
                ),
                onSelected: (val) {
                  setDialogState(() {
                    if (val) {
                      _activeFilters.add(entry.key);
                    } else {
                      _activeFilters.remove(entry.key);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          Text(
            'Date Range',
            style: theme.textTheme.labelMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          InkWell(
            onTap: () async {
              final date = await DatePickerUtils.showStandardDatePicker(
                context: context,
                initialDate: _startDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) {
                setDialogState(() {
                  _startDate = date;
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _startDate != null
                          ? 'From: ${DateFormat('MMM dd, yyyy').format(_startDate!)}'
                          : 'Select start date',
                      style: TextStyle(
                        color: _startDate != null
                            ? (isDark ? Colors.white : Colors.grey[800])
                            : (isDark ? Colors.grey[400] : Colors.grey[600]),
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
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          InkWell(
            onTap: () async {
              final date = await DatePickerUtils.showStandardDatePicker(
                context: context,
                initialDate: _endDate ?? DateTime.now(),
                firstDate: _startDate ?? DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) {
                setDialogState(() {
                  _endDate = date;
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _endDate != null
                          ? 'To: ${DateFormat('MMM dd, yyyy').format(_endDate!)}'
                          : 'Select end date',
                      style: TextStyle(
                        color: _endDate != null
                            ? (isDark ? Colors.white : Colors.grey[800])
                            : (isDark ? Colors.grey[400] : Colors.grey[600]),
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
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupByTab(
    bool isDark,
    StateSetter setDialogState,
    ThemeData theme,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Group deliveries by',
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
          ..._groupByOptions.entries.map((entry) {
            String description = '';
            switch (entry.key) {
              case 'state':
                description =
                    'Group by delivery status (Draft, Ready, Done, etc.)';
                break;
              case 'partner_id':
                description = 'Group by customer name';
                break;
              case 'scheduled_date':
                description = 'Group by scheduled month';
                break;
            }
            return Column(
              children: [
                RadioListTile<String>(
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
                ),
                if (entry.key != _groupByOptions.keys.last) const Divider(),
              ],
            );
          }),
        ],
      ),
    );
  }

  void _groupDeliveries() {
    if (_deliveries == null || _selectedGroupBy == null) {
      _groupedDeliveries = {};
      return;
    }

    _groupedDeliveries = {};
    for (final delivery in _deliveries!) {
      String groupKey;
      switch (_selectedGroupBy) {
        case 'state':
          groupKey = delivery.getStateLabel();
          break;
        case 'partner_id':
          groupKey = delivery.partnerName ?? 'No Customer';
          break;
        case 'scheduled_date':
          if (delivery.scheduledDate != null) {
            final date = DateTime.parse(delivery.scheduledDate!);
            groupKey = DateFormat('MMM yyyy').format(date);
          } else {
            groupKey = 'No Date';
          }
          break;
        default:
          groupKey = 'Other';
      }

      if (!_groupedDeliveries.containsKey(groupKey)) {
        _groupedDeliveries[groupKey] = [];
        _expandedGroups[groupKey] = true;
      }
      _groupedDeliveries[groupKey]!.add(delivery);
    }
  }

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
        errorString.contains('unexpected response');
  }

  Color _getStateColor(String state) {
    switch (state) {
      case 'done':
        return Colors.green;
      case 'assigned':
        return Colors.blue;
      case 'confirmed':
        return Colors.orange;
      case 'cancel':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.grey[900] : Colors.grey[50];

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          widget.saleOrderName != null
              ? 'Deliveries - ${widget.saleOrderName}'
              : 'Deliveries',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: isDark ? Colors.white : Theme.of(context).primaryColor,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(HugeIcons.strokeRoundedArrowLeft01),
        ),
        backgroundColor: backgroundColor,
        foregroundColor: isDark ? Colors.white : Theme.of(context).primaryColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchBar(isDark),
          Expanded(
            child: _isLoading
                ? _buildLoadingShimmer(isDark)
                : _isServerUnreachable ||
                      (_accessErrorMessage != null &&
                          _isServerUnreachableError(_accessErrorMessage!))
                ? ConnectionStatusWidget(
                    serverUnreachable: true,
                    serverErrorMessage: _accessErrorMessage,
                    onRetry: _fetchDeliveries,
                  )
                : _accessErrorMessage != null
                ? _buildErrorState(isDark)
                : _deliveries == null || _deliveries!.isEmpty
                ? _buildEmptyState(isDark)
                : _buildDeliveryList(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16, top: 16),
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withOpacity(0.05),
              offset: const Offset(0, 6),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          enabled: !_isLoading,
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xff1E1E1E),
            fontWeight: FontWeight.w400,
            fontSize: 15,
            height: 1.0,
          ),
          decoration: InputDecoration(
            hintText: 'Search deliveries...',
            hintStyle: TextStyle(
              color: isDark ? Colors.white : const Color(0xff1E1E1E),
              fontWeight: FontWeight.w400,
              fontSize: 15,
              height: 1.0,
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
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
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
                  )
                : null,
            filled: true,
            fillColor: isDark ? Colors.grey[850] : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).primaryColor),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingShimmer(bool isDark) {
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey[700]! : Colors.grey[300]!,
      highlightColor: isDark ? Colors.grey[600]! : Colors.grey[100]!,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 5,
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(width: 100, height: 14, color: Colors.white),
                      Container(
                        width: 60,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(width: 150, height: 12, color: Colors.white),
                  const SizedBox(height: 8),
                  Container(width: 120, height: 12, color: Colors.white),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: isDark ? Colors.white : Theme.of(context).primaryColor,
          ),
          const SizedBox(height: 16),
          Text(
            'Loading deliveries...',
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              'Error Loading Deliveries',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _accessErrorMessage ?? 'Unknown error',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchDeliveries,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return EmptyStateWidget(
      icon: HugeIcons.strokeRoundedPackageDelivered,
      title: 'No Deliveries Found',
      message: widget.saleOrderName != null
          ? 'No deliveries found for this sale order.'
          : 'No deliveries available.',
    );
  }

  Widget _buildDeliveryList(bool isDark) {
    if (_isGrouped &&
        _selectedGroupBy != null &&
        _groupedDeliveries.isNotEmpty) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_groupedDeliveries.length} groups',
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _allGroupsExpanded = !_allGroupsExpanded;
                      for (final key in _groupedDeliveries.keys) {
                        _expandedGroups[key] = _allGroupsExpanded;
                      }
                    });
                  },
                  icon: Icon(
                    _allGroupsExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                  label: Text(
                    _allGroupsExpanded ? 'Collapse All' : 'Expand All',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchDeliveries,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _groupedDeliveries.length,
                itemBuilder: (context, index) {
                  final groupKey = _groupedDeliveries.keys.elementAt(index);
                  final deliveries = _groupedDeliveries[groupKey]!;
                  final isExpanded = _expandedGroups[groupKey] ?? true;
                  return _buildGroupExpansionTile(
                    groupKey,
                    deliveries,
                    isExpanded,
                    isDark,
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchDeliveries,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _deliveries!.length,
        itemBuilder: (context, index) {
          final delivery = _deliveries![index];
          return _buildDeliveryCard(delivery, isDark);
        },
      ),
    );
  }

  Widget _buildGroupExpansionTile(
    String groupKey,
    List<Delivery> deliveries,
    bool isExpanded,
    bool isDark,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 6),
              color: Colors.black.withOpacity(0.05),
            ),
        ],
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _expandedGroups[groupKey] = !isExpanded;

                _allGroupsExpanded = _expandedGroups.values.every(
                  (expanded) => expanded,
                );
              });
            },
            borderRadius: BorderRadius.circular(12),
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
                          '${deliveries.length} deliver${deliveries.length != 1 ? 'ies' : 'y'}',
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
            ...deliveries.map(
              (delivery) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: _buildDeliveryCard(delivery, isDark),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeliveryCard(Delivery delivery, bool isDark) {
    final stateColor = _getStateColor(delivery.state);

    String mainDate = delivery.scheduledDate != null
        ? DateFormat(
            'MMM dd, yyyy',
          ).format(DateTime.parse(delivery.scheduledDate!))
        : '';

    String infoLine = mainDate.isNotEmpty
        ? 'Scheduled: $mainDate'
        : 'No scheduled date';

    String? extraInfoLine;
    if (delivery.origin != null) {
      extraInfoLine = 'Source: ${delivery.origin}';
    } else if (delivery.dateDeadline != null) {
      extraInfoLine =
          'Deadline: ${DateFormat('MMM dd, yyyy').format(DateTime.parse(delivery.dateDeadline!))}';
    }

    return OrderLikeListTile(
      id: delivery.name,
      customer: delivery.partnerName ?? 'No Customer',
      infoLine: infoLine,
      extraInfoLine: extraInfoLine,
      amount: null,

      currencyId: null,
      status: delivery.getStateLabel(),
      statusColor: stateColor,
      isDark: isDark,
      onTap: () {
        Navigator.push(
          context,

          MaterialPageRoute(
            builder: (context) =>
                DeliveryDetailsScreen(deliveryId: delivery.id),
          ),
        );
      },
      mainIcon: HugeIcons.strokeRoundedCalendar03,
      extraIcon: HugeIcons.strokeRoundedFileAttachment,
      amountLabel: null,
    );
  }
}
