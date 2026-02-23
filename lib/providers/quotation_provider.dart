import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../providers/currency_provider.dart';
import '../services/quotation_service.dart';
import '../models/attachment.dart';
import '../services/odoo_session_manager.dart';
import '../services/permission_service.dart';
import '../services/connectivity_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import '../models/quote.dart';
import '../services/field_validation_service.dart';

class QuotationProvider with ChangeNotifier {
  final QuotationService _quotationService;
  final ConnectivityService _connectivityService;

  QuotationProvider({
    QuotationService? quotationService,
    ConnectivityService? connectivityService,
  }) : _quotationService = quotationService ?? QuotationService(),
       _connectivityService = connectivityService ?? ConnectivityService() {
    _setupConnectivityListener();
    _searchController.addListener(() {
      final newText = _searchController.text.trim();
      if (newText == _searchQuery) return;

      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        _searchQuery = newText;
        _currentPage = 0;
        _hasMoreData = true;
        _cachedQuotations.clear();
        _cachedTotalCount = 0;
        _lastFetchTime = null;
        loadQuotations(isLoadMore: false);
      });
    });
  }

  List<Quote> _allQuotations = [];
  List<Quote> _filteredQuotations = [];
  List<Map<String, dynamic>> _orderLines = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isLoadingOrderLines = false;
  bool _hasMoreData = true;
  bool _isOffline = false;
  bool _hasInitiallyLoaded = false;
  VoidCallback? _connectivityListener;
  Timer? _retryTimer;
  Timer? _debounce;
  String? _errorMessage;
  String? _accessErrorMessage;
  List<String> _availableFields = ['invoice_status', 'delivery_status'];
  bool _isFieldsFetched = false;

  Set<String> _activeFilters = {};

  final Map<int, Map<String, dynamic>> _taxCache = {};

  Set<String> get activeFilters => _activeFilters;

  int? _customerFilterId;

  String? _invoiceNameFilter;

  void setCustomerFilter(int? partnerId) {
    _customerFilterId = partnerId;

    _cachedQuotations.clear();
    _cachedTotalCount = 0;
    _lastFetchTime = null;
  }

  Future<void> _loadTaxesForOrderLines() async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return;

      final Set<int> needed = {};
      for (final line in _orderLines) {
        final dynamic taxField = line['tax_id'];
        if (taxField is List) {
          for (final t in taxField) {
            if (t is int && !_taxCache.containsKey(t)) {
              needed.add(t);
            } else if (t is List &&
                t.isNotEmpty &&
                t[0] is int &&
                !_taxCache.containsKey(t[0])) {
              needed.add(t[0] as int);
            }
          }
        } else if (taxField is int && !_taxCache.containsKey(taxField)) {
          needed.add(taxField);
        }

        final dynamic taxIdsField = line['tax_ids'];
        if (taxIdsField is List) {
          for (final t in taxIdsField) {
            if (t is int && !_taxCache.containsKey(t)) {
              needed.add(t);
            } else if (t is List &&
                t.isNotEmpty &&
                t[0] is int &&
                !_taxCache.containsKey(t[0])) {
              needed.add(t[0] as int);
            }
          }
        }
      }

      if (needed.isEmpty) return;

      final taxes = await OdooSessionManager.safeCallKw({
        'model': 'account.tax',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', needed.toList()],
          ],
        ],
        'kwargs': {
          'fields': ['id', 'name', 'amount', 'amount_type'],
          'limit': 500,
        },
      });

      if (taxes is List) {
        for (final t in taxes) {
          final map = Map<String, dynamic>.from(t as Map);
          final id = map['id'] as int?;
          if (id != null) {
            _taxCache[id] = map;
          }
        }
      }
    } catch (e) {}
  }

  String buildTaxPercentLabel(dynamic taxIdField) {
    if (taxIdField == null) return '-';
    final List<String> parts = [];

    if (taxIdField is List) {
      for (final t in taxIdField) {
        if (t is int) {
          final tax = _taxCache[t];
          if (tax != null) {
            final String type = (tax['amount_type'] ?? '').toString();
            final num amt = (tax['amount'] as num?) ?? 0;
            if (type == 'percent') {
              parts.add('${amt.toStringAsFixed(0)}%');
            } else {
              parts.add((tax['name'] ?? 'Tax').toString());
            }
          }
        } else if (t is List && t.isNotEmpty && t[0] is int) {
          final taxId = t[0] as int;
          final tax = _taxCache[taxId];
          if (tax != null) {
            final String type = (tax['amount_type'] ?? '').toString();
            final num amt = (tax['amount'] as num?) ?? 0;
            if (type == 'percent') {
              parts.add('${amt.toStringAsFixed(0)}%');
            } else {
              parts.add((tax['name'] ?? 'Tax').toString());
            }
          }
        }
      }
    } else if (taxIdField is int) {
      final tax = _taxCache[taxIdField];
      if (tax != null) {
        final String type = (tax['amount_type'] ?? '').toString();
        final num amt = (tax['amount'] as num?) ?? 0;
        if (type == 'percent') {
          parts.add('${amt.toStringAsFixed(0)}%');
        } else {
          parts.add((tax['name'] ?? 'Tax').toString());
        }
      }
    }

    if (parts.isEmpty) return '-';
    return parts.join(' + ');
  }

  void setInvoiceNameFilter(String? invoiceName) {
    _invoiceNameFilter = invoiceName;

    _cachedQuotations.clear();
    _cachedTotalCount = 0;
    _lastFetchTime = null;
  }

  Future<int> loadMore() async {
    return _loadMoreData();
  }

  Future<Map<String, String>> fetchGroupByOptions() async {
    try {
      if (!_isFieldsFetched || _availableFields.isEmpty) {
        _availableFields = await _fetchAvailableFields();
        _isFieldsFetched = true;
      }

      final baseline = <String>[
        'user_id',
        'partner_id',
        'date_order:year',
        'date_order:quarter',
        'date_order:month',
        'date_order:week',
        'date_order:day',
      ];

      final map = <String, String>{
        'user_id': 'Salesperson',
        'partner_id': 'Customer',
        'date_order:year': 'Order Date: Year',
        'date_order:quarter': 'Order Date: Quarter',
        'date_order:month': 'Order Date: Month',
        'date_order:week': 'Order Date: Week',
        'date_order:day': 'Order Date: Day',
      };

      _groupByOptions = map;
      notifyListeners();
      return _groupByOptions;
    } catch (e) {
      return _groupByOptions;
    }
  }

  Map<String, List<Map<String, dynamic>>> groupQuotations(
    List<Map<String, dynamic>> quotations,
    String groupByField,
  ) {
    try {
      if (quotations.isEmpty) {
        return {};
      }

      final groups = <String, List<Map<String, dynamic>>>{};

      for (final quotation in quotations) {
        try {
          final groupKey = _getGroupKey(quotation, groupByField);
          if (groupKey.isNotEmpty) {
            groups.putIfAbsent(groupKey, () => []).add(quotation);
          } else {
            groups.putIfAbsent('Unknown', () => []).add(quotation);
          }
        } catch (e) {
          groups.putIfAbsent('Unknown', () => []).add(quotation);
        }
      }

      if (groups.isEmpty) {
        return {};
      }

      try {
        final sortedGroups = Map.fromEntries(
          groups.entries.toList()..sort((a, b) {
            final keyA = a.key;
            final keyB = b.key;

            if (keyA.toLowerCase().contains('unknown') &&
                !keyB.toLowerCase().contains('unknown')) {
              return 1;
            }
            if (!keyA.toLowerCase().contains('unknown') &&
                keyB.toLowerCase().contains('unknown')) {
              return -1;
            }

            return keyA.compareTo(keyB);
          }),
        );

        return sortedGroups;
      } catch (e) {
        return groups;
      }
    } catch (e) {
      return {};
    }
  }

  String _getGroupKey(Map<String, dynamic> quotation, String groupByField) {
    try {
      if (groupByField.startsWith('date_order:')) {
        final parts = groupByField.split(':');
        final field = parts[0];
        final granularity = parts.length > 1 ? parts[1] : 'month';
        final value = quotation[field];

        if (value != null &&
            value.toString().isNotEmpty &&
            value.toString().toLowerCase() != 'false') {
          try {
            final date = DateTime.parse(value.toString());
            return _formatDateByGranularity(date, granularity);
          } catch (e) {
            return 'Invalid Date';
          }
        }
        return 'No Date';
      }

      final value = quotation[groupByField];

      switch (groupByField) {
        case 'state':
          final state = value?.toString();
          if (state == null ||
              state.isEmpty ||
              state.toLowerCase() == 'false') {
            return 'Unknown Status';
          }
          return _getStateLabel(state);
        case 'partner_id':
          if (value is List && value.length >= 2) {
            final name = value[1].toString().trim();
            if (name.isEmpty || name.toLowerCase() == 'false') {
              return 'Unknown Customer';
            }
            return name;
          }
          return 'Unknown Customer';
        case 'user_id':
          if (value is List && value.length >= 2) {
            final name = value[1].toString().trim();
            if (name.isEmpty || name.toLowerCase() == 'false') {
              return 'Unassigned';
            }
            return name;
          }
          return 'Unassigned';
        case 'currency_id':
          if (value is List && value.length >= 2) {
            final name = value[1].toString().trim();
            if (name.isEmpty || name.toLowerCase() == 'false') {
              return 'Unknown Currency';
            }
            return name;
          }
          return 'Unknown Currency';
        case 'date_order':
        case 'validity_date':
          if (value != null &&
              value.toString().isNotEmpty &&
              value.toString().toLowerCase() != 'false') {
            try {
              final date = DateTime.parse(value.toString());
              final monthNames = [
                'January',
                'February',
                'March',
                'April',
                'May',
                'June',
                'July',
                'August',
                'September',
                'October',
                'November',
                'December',
              ];
              return '${monthNames[date.month - 1]} ${date.year}';
            } catch (e) {
              return 'Invalid Date';
            }
          }
          return 'No Date';
        case 'amount_total':
          final amount = double.tryParse(value?.toString() ?? '0') ?? 0;

          String? currencyCode;
          if (quotation['currency_id'] is List &&
              quotation['currency_id'].length >= 2) {
            final currencyName = quotation['currency_id'][1].toString();

            currencyCode = currencyName.split(' ').first;
          }
          return _getAmountRange(amount, currencyCode: currencyCode);
        default:
          final stringValue = value?.toString().trim();
          if (stringValue == null ||
              stringValue.isEmpty ||
              stringValue.toLowerCase() == 'false') {
            return 'Unknown';
          }
          return stringValue;
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  String _formatDateByGranularity(DateTime date, String granularity) {
    switch (granularity) {
      case 'year':
        return '${date.year}';
      case 'quarter':
        final quarter = ((date.month - 1) ~/ 3) + 1;
        return 'Q$quarter ${date.year}';
      case 'month':
        final monthNames = [
          'January',
          'February',
          'March',
          'April',
          'May',
          'June',
          'July',
          'August',
          'September',
          'October',
          'November',
          'December',
        ];
        return '${monthNames[date.month - 1]} ${date.year}';
      case 'week':
        final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays;
        final weekNumber = ((dayOfYear - date.weekday + 10) / 7).floor();
        return 'Week $weekNumber, ${date.year}';
      case 'day':
        return DateFormat('MMM dd, yyyy').format(date);
      default:
        return DateFormat('MMM dd, yyyy').format(date);
    }
  }

  String _getStateLabel(String state) {
    switch (state) {
      case 'draft':
        return 'Draft';
      case 'sent':
        return 'Quotation Sent';
      case 'sale':
        return 'Sales Order';
      case 'done':
        return 'Locked';
      case 'cancel':
        return 'Cancelled';
      default:
        return state.toUpperCase();
    }
  }

  Future<void> _fetchGroupSummary() async {
    if (!_isGrouped || _selectedGroupBy == null) return;

    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return;

      List<dynamic> domain = _buildDomain();

      String groupByField = _selectedGroupBy!;
      String? granularity;

      if (groupByField.contains(':')) {
        final parts = groupByField.split(':');
        groupByField = parts[0];
        granularity = parts[1];
      }

      final result = await OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'read_group',
        'args': [domain],
        'kwargs': {
          'fields': ['id'],
          'groupby': [
            granularity != null ? '$groupByField:$granularity' : groupByField,
          ],
          'lazy': false,
        },
      });

      if (result is List) {
        _groupSummary.clear();
        _groupedQuotations.clear();

        int totalGroupedCount = 0;
        for (final group in result) {
          if (group is Map) {
            final groupKey = _getGroupKeyFromReadGroup(
              group.cast<String, dynamic>(),
              _selectedGroupBy!,
            );
            final count = group['__count'] ?? 0;
            _groupSummary[groupKey] = count;
            totalGroupedCount += count as int;

            _groupedQuotations[groupKey] = [];
          }
        }

        if (_totalQuotations > totalGroupedCount) {
          final missingCount = _totalQuotations - totalGroupedCount;
          String undefinedLabel;

          if (groupByField.contains('date')) {
            undefinedLabel = 'No Date';
          } else if (groupByField == 'user_id') {
            undefinedLabel = 'Unassigned';
          } else if (groupByField == 'partner_id') {
            undefinedLabel = 'Unknown Customer';
          } else {
            undefinedLabel = 'Undefined';
          }

          _groupSummary[undefinedLabel] = missingCount;
          _groupedQuotations[undefinedLabel] = [];
        }

        notifyListeners();
      }
    } catch (e) {}
  }

  String _getGroupKeyFromReadGroup(
    Map<String, dynamic> group,
    String groupByField,
  ) {
    try {
      if (groupByField.contains(':')) {
        final parts = groupByField.split(':');
        final baseField = parts[0];
        final granularity = parts[1];

        var value = group[groupByField];

        value ??= group[baseField];

        if (value == null || value == false) {
          return 'No Date';
        }

        if (value is String) {
          try {
            switch (granularity) {
              case 'year':
                final year = int.tryParse(value);
                if (year != null) {
                  return year.toString();
                }
                break;
              case 'quarter':
                return value;
              case 'month':
                if (value.contains('-')) {
                  final date = DateTime.parse(value);
                  return _formatDateByGranularity(date, granularity);
                }
                return value;
              case 'week':
                if (value.contains('-')) {
                  final date = DateTime.parse(value);
                  return _formatDateByGranularity(date, granularity);
                }
                return value;
              case 'day':
                final date = DateTime.parse(value);
                return _formatDateByGranularity(date, granularity);
            }

            final date = DateTime.parse(value);
            return _formatDateByGranularity(date, granularity);
          } catch (e) {
            return value;
          }
        }

        return value.toString();
      }

      final value = group[groupByField];
      return _getGroupKey({groupByField: value}, groupByField);
    } catch (e) {
      return 'Unknown';
    }
  }

  List<dynamic> _buildGroupDomain(String groupKey, String groupByField) {
    try {
      if (groupByField.startsWith('date_order:')) {
        final parts = groupByField.split(':');
        final field = parts[0];
        final granularity = parts.length > 1 ? parts[1] : 'month';

        if (groupKey == 'No Date' || groupKey == 'Invalid Date') {
          return [
            [field, '=', false],
          ];
        }

        return _buildDateDomainByGranularity(field, groupKey, granularity);
      }

      switch (groupByField) {
        case 'state':
          final stateMap = {
            'Draft': 'draft',
            'Quotation Sent': 'sent',
            'Sales Order': 'sale',
            'Locked': 'done',
            'Cancelled': 'cancel',
          };
          final stateValue = stateMap[groupKey] ?? groupKey.toLowerCase();
          return [
            ['state', '=', stateValue],
          ];
        case 'partner_id':
          if (groupKey == 'Unknown Customer') {
            return [
              ['partner_id', '=', false],
            ];
          }

          return [
            ['partner_id.name', 'ilike', groupKey],
          ];
        case 'user_id':
          if (groupKey == 'Unassigned') {
            return [
              ['user_id', '=', false],
            ];
          }
          return [
            ['user_id.name', 'ilike', groupKey],
          ];
        case 'currency_id':
          if (groupKey == 'Unknown Currency') {
            return [
              ['currency_id', '=', false],
            ];
          }
          return [
            ['currency_id.name', 'ilike', groupKey],
          ];
        case 'date_order':
        case 'validity_date':
          if (groupKey == 'No Date' || groupKey == 'Invalid Date') {
            return [
              [groupByField, '=', false],
            ];
          }

          try {
            final parts = groupKey.split(' ');
            if (parts.length == 2) {
              final monthNames = [
                'January',
                'February',
                'March',
                'April',
                'May',
                'June',
                'July',
                'August',
                'September',
                'October',
                'November',
                'December',
              ];
              final monthIndex = monthNames.indexOf(parts[0]) + 1;
              final year = int.parse(parts[1]);
              if (monthIndex > 0) {
                final startDate = DateTime(year, monthIndex, 1);
                final endDate = DateTime(year, monthIndex + 1, 0, 23, 59, 59);
                return [
                  [groupByField, '>=', startDate.toIso8601String()],
                  [groupByField, '<=', endDate.toIso8601String()],
                ];
              }
            }
          } catch (e) {}
          return [];
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

  List<dynamic> _buildDateDomainByGranularity(
    String field,
    String groupKey,
    String granularity,
  ) {
    try {
      switch (granularity) {
        case 'year':
          final year = int.parse(groupKey);
          final startDate = DateTime(year, 1, 1);
          final endDate = DateTime(year, 12, 31, 23, 59, 59);
          return [
            [field, '>=', startDate.toIso8601String()],
            [field, '<=', endDate.toIso8601String()],
          ];
        case 'quarter':
          final parts = groupKey.split(' ');
          if (parts.length == 2) {
            final quarter = int.parse(parts[0].replaceFirst('Q', ''));
            final year = int.parse(parts[1]);
            final startMonth = (quarter - 1) * 3 + 1;
            final endMonth = startMonth + 2;
            final startDate = DateTime(year, startMonth, 1);
            final endDate = DateTime(year, endMonth + 1, 0, 23, 59, 59);
            return [
              [field, '>=', startDate.toIso8601String()],
              [field, '<=', endDate.toIso8601String()],
            ];
          }
          break;
        case 'month':
          final parts = groupKey.split(' ');
          if (parts.length == 2) {
            final monthNames = [
              'January',
              'February',
              'March',
              'April',
              'May',
              'June',
              'July',
              'August',
              'September',
              'October',
              'November',
              'December',
            ];
            final monthIndex = monthNames.indexOf(parts[0]) + 1;
            final year = int.parse(parts[1]);
            if (monthIndex > 0) {
              final startDate = DateTime(year, monthIndex, 1);
              final endDate = DateTime(year, monthIndex + 1, 0, 23, 59, 59);
              return [
                [field, '>=', startDate.toIso8601String()],
                [field, '<=', endDate.toIso8601String()],
              ];
            }
          }
          break;
        case 'week':
          final parts = groupKey.replaceAll(',', '').split(' ');
          if (parts.length == 3) {
            final weekNumber = int.parse(parts[1]);
            final year = int.parse(parts[2]);

            final firstDayOfYear = DateTime(year, 1, 1);
            final daysToAdd = (weekNumber - 1) * 7 - firstDayOfYear.weekday + 1;
            final startDate = firstDayOfYear.add(Duration(days: daysToAdd));
            final endDate = startDate.add(
              const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
            );
            return [
              [field, '>=', startDate.toIso8601String()],
              [field, '<=', endDate.toIso8601String()],
            ];
          }
          break;
        case 'day':
          try {
            final date = DateFormat('MMM dd, yyyy').parse(groupKey);
            final startDate = DateTime(date.year, date.month, date.day);
            final endDate = DateTime(
              date.year,
              date.month,
              date.day,
              23,
              59,
              59,
            );
            return [
              [field, '>=', startDate.toIso8601String()],
              [field, '<=', endDate.toIso8601String()],
            ];
          } catch (e) {}
          break;
      }
    } catch (e) {}
    return [];
  }

  Future<void> loadGroupQuotations(String groupKey) async {
    if (!_isGrouped || _selectedGroupBy == null) return;

    if (_loadedGroups.containsKey(groupKey)) return;

    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return;

      List<dynamic> domain = _buildDomain();

      final groupDomain = _buildGroupDomain(groupKey, _selectedGroupBy!);

      domain.addAll(groupDomain);

      final result = await OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [domain],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'partner_id',
            'date_order',
            'validity_date',
            'state',
            'amount_total',
            'currency_id',
            'user_id',
            'amount_untaxed',
          ],
          'order': 'date_order desc, id desc',
        },
      });

      if (result is List) {
        final quotations = result
            .map((data) => Quote.fromJson(Map<String, dynamic>.from(data)))
            .toList();
        _loadedGroups[groupKey] = quotations;

        notifyListeners();
      }
    } catch (e) {}
  }

  String _getAmountRange(double amount, {String? currencyCode}) {
    final symbol = currencyCode != null ? _getCurrencySymbol(currencyCode) : '';

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
    return CurrencyProvider().getCurrencySymbol(currencyCode);
  }

  DateTime? _startDate;
  DateTime? _endDate;

  DateTime? get startDate => _startDate;

  DateTime? get endDate => _endDate;

  void setDateRange(DateTime? start, DateTime? end) {
    _startDate = start;
    _endDate = end;

    _cachedQuotations.clear();
    _cachedTotalCount = 0;
    _lastFetchTime = null;
  }

  bool _isServerUnreachable = false;

  bool get isServerUnreachable => _isServerUnreachable;

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

  int? get customerFilterId => _customerFilterId;

  String? get errorMessage => _errorMessage;

  String? get accessErrorMessage => _accessErrorMessage;

  List<Map<String, dynamic>> get orderLines => _orderLines;

  bool get isLoadingOrderLines => _isLoadingOrderLines;

  static const int _pageSize = 40;
  int _currentPage = 0;
  int _totalQuotations = 0;
  final ScrollController _scrollController = ScrollController();

  int get pageSize => _pageSize;

  int get currentPage => _currentPage;

  int get currentStartIndex => (_currentPage * _pageSize) + 1;

  int get currentEndIndex => _allQuotations.length;

  int get totalPages =>
      _totalQuotations > 0 ? ((_totalQuotations - 1) ~/ _pageSize) + 1 : 0;

  bool get canGoToPreviousPage => _currentPage > 0;

  bool get canGoToNextPage => _hasMoreData;

  String getPaginationText() {
    if (_totalQuotations == 0 && _allQuotations.isEmpty) return "0 items";
    if (_totalQuotations == 0) return "${_allQuotations.length} items";

    final pageStart = (_currentPage * _pageSize) + 1;

    final expectedPageEnd = (_currentPage + 1) * _pageSize;
    final pageEnd = expectedPageEnd > _totalQuotations
        ? _totalQuotations
        : expectedPageEnd;
    return "$pageStart-$pageEnd/$_totalQuotations";
  }

  Future<void> goToPage(int page) async {
    if (page < 0 || page == _currentPage) return;

    _currentPage = page;
    await _fetchSpecificPage();
  }

  Future<void> goToNextPage() async {
    if (!canGoToNextPage) return;
    _currentPage++;
    await _fetchSpecificPage();
  }

  Future<void> goToPreviousPage() async {
    if (!canGoToPreviousPage) return;
    _currentPage--;
    await _fetchSpecificPage();
  }

  List<dynamic> _buildDomain() {
    List<dynamic> domain = [
      [
        'state',
        'in',
        ['draft', 'sent', 'sale', 'done', 'cancel'],
      ],
    ];

    if (_activeFilters.isNotEmpty) {
      for (final filter in _activeFilters) {
        switch (filter) {
          case 'quotation':
            domain.add([
              'state',
              'in',
              ['draft', 'sent'],
            ]);
            break;
          case 'sale':
            domain.add(['state', '=', 'sale']);
            break;
          case 'user_quotations':
            break;
          case 'invoiced':
            domain.add(['invoice_status', '=', 'invoiced']);
            break;
          case 'to_invoice':
            domain.add(['invoice_status', '=', 'to invoice']);
            break;
          case 'delivered':
            domain.add(['delivery_status', '=', 'delivered']);
            break;
          case 'to_deliver':
            domain.add(['delivery_status', '=', 'to deliver']);
            break;
          case 'expired':
            final now = DateTime.now();
            final todayStr =
                '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
            domain.addAll([
              [
                'state',
                'in',
                ['draft', 'sent'],
              ],
              ['validity_date', '<', todayStr],
            ]);
            break;
        }
      }
    }

    if (_customerFilterId != null) {
      domain.add(['partner_id', '=', _customerFilterId]);
    }

    if (_invoiceNameFilter != null && _invoiceNameFilter!.isNotEmpty) {
      domain.add(['name', 'ilike', _invoiceNameFilter!.trim()]);
    }

    if (_startDate != null || _endDate != null) {
      if (_startDate != null && _endDate != null) {
        final startStr =
            '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')} 00:00:00';
        final endStr =
            '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')} 23:59:59';
        domain.add(['create_date', '>=', startStr]);
        domain.add(['create_date', '<=', endStr]);
      } else if (_startDate != null) {
        final startStr =
            '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')} 00:00:00';
        domain.add(['create_date', '>=', startStr]);
      } else if (_endDate != null) {
        final endStr =
            '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')} 23:59:59';
        domain.add(['create_date', '<=', endStr]);
      }
    }

    if (_searchQuery.isNotEmpty) {
      domain.add('|');
      domain.add(['name', 'ilike', _searchQuery]);
      domain.add(['partner_id.name', 'ilike', _searchQuery]);
    }

    return domain;
  }

  Future<void> _fetchSpecificPage() async {
    if (_isLoadingMore) {
      return;
    }

    _isLoadingMore = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _checkConnectivity();
      if (_isOffline) {
        _errorMessage = 'No internet connection. Please check your connection.';
        _isLoadingMore = false;
        notifyListeners();
        return;
      }

      final session = await OdooSessionManager.getClient();
      if (session == null) {
        _errorMessage = 'No active session. Please log in again.';
        _isLoadingMore = false;
        notifyListeners();
        return;
      }

      List<dynamic> domain = _buildDomain();

      final countFuture = OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'search_count',
        'args': [domain],
        'kwargs': {},
      });

      final List<String> fieldsToFetch = [
        'id',
        'name',
        'partner_id',
        'date_order',
        'state',
        'amount_total',
        'currency_id',
        'user_id',
        'validity_date',
        'create_date',
        'write_date',
        'amount_untaxed',
        'amount_tax',
        'order_line',
      ];

      if (_availableFields.contains('invoice_status')) {
        fieldsToFetch.add('invoice_status');
      }
      if (_availableFields.contains('delivery_status')) {
        fieldsToFetch.add('delivery_status');
      }

      final listFuture =
          FieldValidationService.executeWithFieldValidation<
            List<Map<String, dynamic>>
          >(
            model: 'sale.order',
            initialFields: fieldsToFetch,
            apiCall: (currentFields) async {
              final res = await OdooSessionManager.safeCallKw({
                'model': 'sale.order',
                'method': 'search_read',
                'args': [domain],
                'kwargs': {
                  'fields': currentFields,
                  'order': 'date_order desc, id desc',
                  'limit': _pageSize,
                  'offset': _currentPage * _pageSize,
                },
              });
              if (res is List) {
                return res.cast<Map<String, dynamic>>();
              }
              return [];
            },
          );

      final results = await Future.wait<dynamic>([countFuture, listFuture]);

      final totalCount = results[0] as int;
      final result = results[1];

      _totalQuotations = totalCount;
      if (result is List) {
        final fetchedQuotations = result
            .map((data) {
              if (data is Map) {
                try {
                  return Quote.fromJson(Map<String, dynamic>.from(data));
                } catch (e) {
                  return null;
                }
              } else if (data is int) {
                return null;
              }
              return null;
            })
            .whereType<Quote>()
            .toList();

        if (_currentPage == 0) {
          _allQuotations = fetchedQuotations;
        } else {
          _allQuotations.addAll(fetchedQuotations);
        }
        _filteredQuotations = List.from(_allQuotations);
        _hasMoreData = _allQuotations.length < _totalQuotations;

        if (_isGrouped && _selectedGroupBy != null) {
          if (_groupSummary.isEmpty) {
            _fetchGroupSummary();
          }
        }
      }

      _hasInitiallyLoaded = true;
      _isLoading = false;
      _isLoadingMore = false;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      if (e.toString().contains('odoo.exceptions.AccessError') ||
          e.toString().contains('You are not allowed to access')) {
        _accessErrorMessage =
            'You do not have permission to view quotations. Please contact your administrator.';
        _allQuotations.clear();
        _filteredQuotations.clear();
      } else {
        _errorMessage = e.toString();
      }
      _isLoading = false;
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  static List<Quote> _cachedQuotations = [];
  static int _cachedTotalCount = 0;
  static DateTime? _lastFetchTime;

  List<Quote> get allQuotations => _allQuotations;

  List<Quote> get filteredQuotations => _filteredQuotations;

  bool get isLoading => _isLoading;

  bool get isLoadingMore => _isLoadingMore;

  bool get hasMoreData => _hasMoreData;

  bool get isOffline => _isOffline;

  bool get hasInitiallyLoaded => _hasInitiallyLoaded;

  int get totalQuotations => _totalQuotations;

  ScrollController get scrollController => _scrollController;

  TextEditingController get searchController => _searchController;
  List<Attachment> _attachments = [];
  bool _isLoadingAttachments = false;

  List<Attachment> get attachments => _attachments;

  bool get isLoadingAttachments => _isLoadingAttachments;

  Map<String, String> _groupByOptions = {};

  Map<String, String> get groupByOptions => _groupByOptions;

  String? _selectedGroupBy;
  bool _isGrouped = false;
  final Map<String, List<Quote>> _groupedQuotations = {};

  String? get selectedGroupBy => _selectedGroupBy;

  final Map<String, int> _groupSummary = {};

  Map<String, int> get groupSummary => _groupSummary;

  final Map<String, List<Quote>> _loadedGroups = {};

  Map<String, List<Quote>> get loadedGroups => _loadedGroups;

  Map<String, List<Quote>> get groupedQuotations => _groupedQuotations;

  bool get isGrouped => _isGrouped;

  void setGroupBy(String? groupBy) {
    _selectedGroupBy = groupBy;
    _isGrouped = groupBy != null;

    _groupSummary.clear();
    _loadedGroups.clear();
    _groupedQuotations.clear();
    _lastFetchTime = null;

    if (_isGrouped) {
      _fetchGroupSummary();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    if (_connectivityListener != null) {
      _connectivityService.removeListener(_connectivityListener!);
    }
    _retryTimer?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> loadAttachments(int orderId) async {
    try {
      _isLoadingAttachments = true;
      _attachments.clear();
      notifyListeners();

      final result = await OdooSessionManager.safeCallKw({
        'model': 'ir.attachment',
        'method': 'search_read',
        'args': [
          [
            ['res_model', '=', 'sale.order'],
            ['res_id', '=', orderId],
          ],
        ],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'type',
            'url',
            'mimetype',
            'create_date',
            'description',
          ],
          'order': 'create_date desc',
        },
      });

      if (result is List) {
        for (int i = 0; i < result.length; i++) {}

        _attachments = result.map((json) => Attachment.fromJson(json)).toList();
      }

      _isLoadingAttachments = false;
      notifyListeners();
    } catch (e) {
      _isLoadingAttachments = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> uploadAttachment(
    int orderId,
    Uint8List fileBytes,
    String fileName,
    String mimetype, {
    String? description,
  }) async {
    try {
      _isLoadingAttachments = true;
      notifyListeners();

      final base64File = base64Encode(fileBytes as List<int>);

      await OdooSessionManager.safeCallKw({
        'model': 'ir.attachment',
        'method': 'create',
        'args': [
          {
            'name': fileName,
            'type': 'binary',
            'datas': base64File,
            'res_model': 'sale.order',
            'res_id': orderId,
            'mimetype': mimetype,
            if (description != null) 'description': description,
          },
        ],
        'kwargs': {},
      });

      await loadAttachments(orderId);
    } catch (e) {
      _isLoadingAttachments = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteAttachment(int attachmentId) async {
    try {
      _isLoadingAttachments = true;
      notifyListeners();

      await OdooSessionManager.safeCallKw({
        'model': 'ir.attachment',
        'method': 'unlink',
        'args': [
          [attachmentId],
        ],
        'kwargs': {},
      });

      _attachments.removeWhere((a) => a.id == attachmentId);
      _isLoadingAttachments = false;
      notifyListeners();
    } catch (e) {
      _isLoadingAttachments = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<int> _loadMoreData() async {
    await goToNextPage();
    return 0;
  }

  Future<void> loadMoreQuotations() async {
    await goToNextPage();
  }

  Future<void> refreshQuotations() async {
    _cachedQuotations.clear();
    _cachedTotalCount = 0;
    _lastFetchTime = null;
    _currentPage = 0;
    await loadQuotations();
  }

  void _setupConnectivityListener() {
    _connectivityListener = () {
      _isOffline = !_connectivityService.isConnected;

      if (!_isOffline && _allQuotations.isEmpty && !_isLoading) {
        _retryTimer?.cancel();
        _isLoading = true;
        _errorMessage = null;
        _accessErrorMessage = null;
        notifyListeners();
        _loadQuotations();
      } else if (_isOffline) {
        _startRetryTimer();
      }
      notifyListeners();
    };

    _connectivityService.addListener(_connectivityListener!);
  }

  void _startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_allQuotations.isEmpty && !_isLoading) {
        _loadQuotations();
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    _isOffline = connectivityResult.contains(ConnectivityResult.none);
  }

  Future<void> loadQuotations({
    bool isLoadMore = false,
    Set<String>? filters,
    String? groupBy,
    bool clearGroupBy = false,
  }) async {
    if (filters != null) {
      _activeFilters = filters;

      if (_activeFilters.isEmpty) {
        _cachedQuotations.clear();
        _cachedTotalCount = 0;
        _lastFetchTime = null;
      }
    }

    if (groupBy != null) {
      setGroupBy(groupBy);
    } else if (clearGroupBy) {
      _selectedGroupBy = null;
      _isGrouped = false;
      _groupedQuotations.clear();
    }

    const cacheDuration = Duration(minutes: 5);
    final hasFreshCache =
        !isLoadMore &&
        _cachedQuotations.isNotEmpty &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < cacheDuration &&
        _activeFilters.isEmpty &&
        _searchQuery.isEmpty &&
        _customerFilterId == null &&
        _invoiceNameFilter == null &&
        _startDate == null &&
        _endDate == null &&
        _selectedGroupBy == null;

    if (hasFreshCache) {
      _allQuotations = List.from(_cachedQuotations);
      _filteredQuotations = List.from(_allQuotations);
      _totalQuotations = _cachedTotalCount;
      _hasMoreData = (_currentPage + 1) * _pageSize < _cachedTotalCount;
      _isLoading = false;
      _hasInitiallyLoaded = true;
      _errorMessage = null;
      if (_allQuotations.isNotEmpty && _accessErrorMessage != null) {
        _accessErrorMessage = null;
      }

      notifyListeners();
      return;
    }

    if (!isLoadMore) {
      _isLoading = true;
      _allQuotations.clear();
      _filteredQuotations.clear();
      _currentPage = 0;
      _hasMoreData = true;
      _errorMessage = null;

      notifyListeners();
    }

    await _fetchSpecificPage();

    if (_allQuotations.isNotEmpty && _accessErrorMessage != null) {
      _accessErrorMessage = null;
      notifyListeners();
    }
  }

  Future<List<String>> _fetchAvailableFields() async {
    try {
      final result = await OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'fields_get',
        'args': [],
        'kwargs': {
          'attributes': ['name'],
        },
      });

      final fields = result.keys.toList().cast<String>();
      return fields;
    } catch (e) {
      return [];
    }
  }

  Future<List<Quote>> _loadQuotations({bool isLoadMore = false}) async {
    try {
      await _checkConnectivity();
      if (_isOffline) {
        _isLoading = false;
        _errorMessage = 'No internet connection. Please check your connection.';
        _accessErrorMessage = null;
        notifyListeners();

        return [];
      }

      final session = await OdooSessionManager.getCurrentSession();
      if (session == null) {
        _isLoading = false;
        _errorMessage = 'No active session. Please log in again.';
        _accessErrorMessage = null;
        notifyListeners();
        return [];
      }

      if (!_isFieldsFetched) {
        _availableFields = await _fetchAvailableFields();
        _isFieldsFetched = true;
      }

      const cacheDuration = Duration(minutes: 5);
      final shouldUseCache =
          !isLoadMore &&
          _cachedQuotations.isNotEmpty &&
          _lastFetchTime != null &&
          DateTime.now().difference(_lastFetchTime!) < cacheDuration &&
          _activeFilters.isEmpty &&
          _searchQuery.isEmpty &&
          _customerFilterId == null &&
          _invoiceNameFilter == null &&
          _selectedGroupBy == null;

      if (shouldUseCache) {
        _allQuotations = List.from(_cachedQuotations);
        _filteredQuotations = List.from(_allQuotations);
        _isLoading = false;
        _errorMessage = null;
        if (_allQuotations.isNotEmpty && _accessErrorMessage != null) {
          _accessErrorMessage = null;
        }
        notifyListeners();
        return _allQuotations;
      }

      final quotations = await fetchQuotations(isLoadMore: isLoadMore);

      if (!isLoadMore) {
        _allQuotations = quotations;
        _cachedQuotations = List.from(quotations);
        _cachedTotalCount = _totalQuotations;
      } else {
        _allQuotations.addAll(quotations);
        _cachedQuotations = List.from(_allQuotations);
        _cachedTotalCount = _totalQuotations;
      }

      if (_isGrouped) {
        if (_groupSummary.isEmpty) {
          _fetchGroupSummary();
        }
      } else {
        _groupedQuotations.clear();
      }

      if (_allQuotations.isNotEmpty) {}

      _errorMessage = null;
      _accessErrorMessage = null;

      notifyListeners();
      return _allQuotations;
    } on OdooException catch (e) {
      if (e.message.contains('odoo.exceptions.AccessError') ||
          e.toString().contains('odoo.exceptions.AccessError')) {
        _accessErrorMessage =
            'You do not have permission to view quotations. Please contact your administrator.';
        _allQuotations.clear();
        _filteredQuotations.clear();
        _isLoading = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });

        return [];
      }
      _errorMessage = "Failed to fetch quotations. Please try again.";
      _isLoading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });

      return [];
    } catch (e) {
      if (e.toString().contains('odoo.exceptions.AccessError')) {
        _accessErrorMessage =
            'You do not have permission to view quotations. Please contact your administrator.';
        _allQuotations.clear();
        _filteredQuotations.clear();
        _isLoading = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });

        return [];
      }
      _errorMessage = "Failed to fetch quotations. Please try again.";
      _isLoading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });

      return [];
    }
  }

  Future<List<Quote>> fetchQuotations({bool isLoadMore = false}) async {
    try {
      final session = await OdooSessionManager.getCurrentSession();
      if (session == null) {
        _errorMessage = 'No active Odoo session.';
        _accessErrorMessage = null;
        return [];
      }

      List<dynamic> domain = [
        [
          'state',
          'in',
          ['draft', 'sent', 'sale', 'done', 'cancel'],
        ],
      ];

      if (_activeFilters.isNotEmpty) {
        for (final filter in _activeFilters) {
          switch (filter) {
            case 'quotation':
              domain.add([
                'state',
                'in',
                ['draft', 'sent'],
              ]);
              break;
            case 'sale':
              domain.add(['state', '=', 'sale']);
              break;
            case 'user_quotations':
              final session = await OdooSessionManager.getCurrentSession();
              if (session != null) {
                domain.add(['user_id', '=', session.userId]);
              }
              break;
            case 'invoiced':
              domain.add(['invoice_status', '=', 'invoiced']);
              break;
            case 'to_invoice':
              domain.add(['invoice_status', '=', 'to invoice']);
              break;
            case 'delivered':
              domain.add(['delivery_status', '=', 'delivered']);
              break;
            case 'to_deliver':
              domain.add(['delivery_status', '=', 'to deliver']);
              break;
            case 'expired':
              final now = DateTime.now();
              final todayStr =
                  '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
              domain.addAll([
                [
                  'state',
                  'in',
                  ['draft', 'sent'],
                ],
                ['validity_date', '<', todayStr],
              ]);
              break;
          }
        }
      } else {}

      if (_customerFilterId != null) {
        domain.add(['partner_id', '=', _customerFilterId]);
      } else {}

      if (_invoiceNameFilter != null && _invoiceNameFilter!.isNotEmpty) {
        domain.add(['name', 'ilike', _invoiceNameFilter!.trim()]);
      }

      if (_startDate != null || _endDate != null) {
        if (_startDate != null && _endDate != null) {
          final startStr =
              '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')} 00:00:00';
          final endStr =
              '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')} 23:59:59';
          domain.add(['create_date', '>=', startStr]);
          domain.add(['create_date', '<=', endStr]);
        } else if (_startDate != null) {
          final startStr =
              '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')} 00:00:00';
          domain.add(['create_date', '>=', startStr]);
        } else if (_endDate != null) {
          final endStr =
              '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')} 23:59:59';
          domain.add(['create_date', '<=', endStr]);
        }
      } else {}

      if (_searchQuery.isNotEmpty) {
        domain.add('|');
        domain.add(['name', 'ilike', _searchQuery]);
        domain.add(['partner_id.name', 'ilike', _searchQuery]);
      }

      List<String> fields = [
        'id',
        'name',
        'partner_id',
        'user_id',
        'date_order',
        'amount_total',
        'amount_untaxed',
        'amount_tax',
        'state',
        'currency_id',
        'currency_rate',
        'note',
        'validity_date',
        'create_date',
        'write_date',
        'order_line',
      ];

      if (_availableFields.contains('delivery_status')) {
        fields.add('delivery_status');
      }
      if (_availableFields.contains('invoice_status')) {
        fields.add('invoice_status');
      }

      final countFuture = OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'search_count',
        'args': [domain],
        'kwargs': {},
      });

      final listFuture = OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [domain],
        'kwargs': {
          'fields': fields,
          'limit': _pageSize,
          'offset': _currentPage * _pageSize,
          'order': 'date_order desc',
        },
      });

      final results = await Future.wait([countFuture, listFuture]);

      final totalCount = results[0] as int;
      final result = results[1];

      if (result is! List) {
        _errorMessage = 'Unexpected response format from server.';
        _accessErrorMessage = null;
        throw Exception('Unexpected response format from server');
      }

      final quotations = List<Map<String, dynamic>>.from(result);

      final uniqueQuotations = <Quote>[];
      final seenIds = isLoadMore
          ? _allQuotations.map((q) => q.id as int).toSet()
          : <int>{};
      int duplicateCount = 0;

      if (isLoadMore) {}

      for (var quotation in quotations) {
        final quotationId = quotation['id'] as int;
        if (!seenIds.contains(quotationId)) {
          seenIds.add(quotationId);
          uniqueQuotations.add(Quote.fromJson(quotation));
        } else {
          duplicateCount++;
        }
      }

      if (duplicateCount > 0) {}

      _totalQuotations = totalCount;
      final totalAfterAdding = _allQuotations.length + uniqueQuotations.length;
      _hasMoreData = totalAfterAdding < totalCount;

      if (uniqueQuotations.isNotEmpty) {}

      _errorMessage = null;
      _accessErrorMessage = null;
      return uniqueQuotations;
    } on OdooException catch (e) {
      if (e.message.contains('odoo.exceptions.AccessError') ||
          e.toString().contains('odoo.exceptions.AccessError')) {
        _accessErrorMessage =
            'You do not have permission to view quotations. Please contact your administrator.';
        _allQuotations.clear();
        _filteredQuotations.clear();
        _isLoading = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });

        return [];
      }
      _errorMessage = "Failed to fetch quotations. Please try again.";
      _accessErrorMessage = null;
      return [];
    } catch (e) {
      if (_isServerUnreachableError(e)) {
        _isServerUnreachable = true;
        _errorMessage =
            "Server/Database unreachable. Please check your server or try again.";
        _accessErrorMessage = null;
        _allQuotations.clear();
        _filteredQuotations.clear();
        _isLoading = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });

        return [];
      }

      if (e.toString().contains('odoo.exceptions.AccessError')) {
        _accessErrorMessage =
            'You do not have permission to view quotations. Please contact your administrator.';
        _allQuotations.clear();
        _filteredQuotations.clear();
        _isLoading = false;
        _isServerUnreachable = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });

        return [];
      }
      _errorMessage = "Failed to fetch quotations. Please try again.";
      _accessErrorMessage = null;
      _isServerUnreachable = false;
      return [];
    }
  }

  Future<void> loadOrderLines(int quotationId) async {
    try {
      _isLoadingOrderLines = true;
      _orderLines.clear();
      notifyListeners();

      final session = await OdooSessionManager.getCurrentSession();
      if (session == null) {
        _errorMessage = 'No active Odoo session.';
        _isLoadingOrderLines = false;
        notifyListeners();
        return;
      }

      final baseFields = [
        'product_id',
        'product_uom_qty',
        'qty_delivered',
        'qty_invoiced',
        'price_unit',
        'price_subtotal',
        'price_tax',
        'name',
      ];

      dynamic result;
      String taxField = '';

      try {
        result = await OdooSessionManager.safeCallKw({
          'model': 'sale.order.line',
          'method': 'search_read',
          'args': [
            [
              ['order_id', '=', quotationId],
            ],
          ],
          'kwargs': {
            'fields': [...baseFields, 'tax_ids'],
          },
        });
        taxField = 'tax_ids';
      } catch (e) {
        try {
          result = await OdooSessionManager.safeCallKw({
            'model': 'sale.order.line',
            'method': 'search_read',
            'args': [
              [
                ['order_id', '=', quotationId],
              ],
            ],
            'kwargs': {
              'fields': [...baseFields, 'tax_id'],
            },
          });
          taxField = 'tax_id';
        } catch (e2) {
          result = await OdooSessionManager.safeCallKw({
            'model': 'sale.order.line',
            'method': 'search_read',
            'args': [
              [
                ['order_id', '=', quotationId],
              ],
            ],
            'kwargs': {'fields': baseFields},
          });
          taxField = '';
        }
      }

      if (result is List) {
        _orderLines = List<Map<String, dynamic>>.from(result);

        if (taxField == 'tax_ids') {
          for (final line in _orderLines) {
            if (line['tax_ids'] != null) {
              line['tax_id'] = line['tax_ids'];
            }
          }
        }

        if (taxField.isNotEmpty) {
          await _loadTaxesForOrderLines();
        }
      } else {
        _errorMessage = 'Unexpected response format for order lines';
      }

      _isLoadingOrderLines = false;
      notifyListeners();
    } catch (e) {
      if (e.toString().contains('Server returned HTML instead of JSON')) {
        _errorMessage =
            'Server connection issue. Please check your internet connection and try again.';
      } else if (e.toString().contains('SocketException') ||
          e.toString().contains('TimeoutException')) {
        _errorMessage =
            'Network connection failed. Please check your internet connection.';
      } else {
        _errorMessage = 'Failed to load order lines. Please try again.';
      }

      _isLoadingOrderLines = false;
      notifyListeners();
    }
  }

  void filterQuotations(String tab) {
    if (_allQuotations.isEmpty) {
      _filteredQuotations = [];
      notifyListeners();
      return;
    }

    _filteredQuotations = _allQuotations.where((quotation) {
      final state = _safeString(quotation.status).toLowerCase();
      final deliveryStatus = _availableFields.contains('delivery_status')
          ? _safeString(quotation.extraData?['delivery_status']).toLowerCase()
          : '';
      final invoiceStatus = _availableFields.contains('invoice_status')
          ? _safeString(quotation.extraData?['invoice_status']).toLowerCase()
          : '';

      if (tab == "Active") {
        if (!_availableFields.contains('delivery_status') &&
            !_availableFields.contains('invoice_status')) {
          return state == 'draft' || state == 'sent';
        }
        return state == 'draft' ||
            state == 'sent' ||
            deliveryStatus == 'to deliver' ||
            deliveryStatus == 'pending' ||
            deliveryStatus == 'partially' ||
            invoiceStatus == 'to invoice' ||
            invoiceStatus == 'upselling';
      } else if (tab == "Completed") {
        if (!_availableFields.contains('delivery_status') &&
            !_availableFields.contains('invoice_status')) {
          return state == 'sale' || state == 'done';
        }
        return deliveryStatus == 'full' && invoiceStatus == 'invoiced';
      } else {
        return state == 'cancel';
      }
    }).toList();

    notifyListeners();
  }

  String _safeString(dynamic value) {
    if (value is String) return value;
    if (value is bool) return value ? 'true' : 'none';
    return '';
  }

  String formatState(String state) {
    switch (state.toLowerCase()) {
      case 'sale':
        return 'Sale';
      case 'done':
        return 'Done';
      case 'cancel':
        return 'Cancelled';
      case 'draft':
        return 'Draft';
      case 'sent':
        return 'Sent';
      case 'none':
        return 'None';
      default:
        return state.capitalize();
    }
  }

  Color getStatusColor(String state) {
    switch (state.toLowerCase()) {
      case 'sale':
        return Colors.green;
      case 'done':
        return Colors.blue;
      case 'cancel':
        return Colors.red;
      case 'draft':
        return Colors.grey;
      case 'sent':
        return Colors.orange;
      case 'none':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  Color getDeliveryStatusColor(String status) {
    if (!_availableFields.contains('delivery_status')) {
      return Colors.grey;
    }
    switch (status.toLowerCase()) {
      case 'full':
        return Colors.green;
      case 'partially':
        return Colors.orange;
      case 'to deliver':
      case 'pending':
        return Colors.orange;
      case 'nothing':
      case 'none':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Color getInvoiceStatusColor(String status) {
    if (!_availableFields.contains('invoice_status')) {
      return Colors.grey;
    }
    switch (status.toLowerCase()) {
      case 'invoiced':
        return Colors.green;
      case 'to invoice':
        return Colors.blue;
      case 'upselling':
        return Colors.orange;
      case 'no':
      case 'none':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String formatStatus(String status) {
    if (!_availableFields.contains('delivery_status') &&
        !_availableFields.contains('invoice_status')) {
      return 'N/A';
    }
    switch (status.toLowerCase()) {
      case 'full':
        return 'Delivered';
      case 'partially':
        return 'Partially Delivered';
      case 'to deliver':
      case 'pending':
        return 'Pending';
      case 'nothing':
      case 'none':
        return 'Nothing to Deliver';
      case 'invoiced':
        return 'Invoiced';
      case 'to invoice':
        return 'To Invoice';
      case 'upselling':
        return 'Upselling';
      case 'no':
        return 'Nothing to Invoice';
      default:
        return status.capitalize();
    }
  }

  String formatAmount(double amount, {List<dynamic>? currencyId}) {
    String symbol = '';
    if (currencyId != null && currencyId.length > 1) {
      symbol = currencyId[1]?.toString() ?? '';
    }

    final format = NumberFormat.currency(
      locale: 'en_US',
      symbol: symbol,
      customPattern: '#,##0.00 \u00A4',
      decimalDigits: 2,
    );
    return format.format(amount);
  }

  static const Map<String, String> _currencyToLocale = {
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
  };

  Future<void> convertQuotationToOrder(int quotationId) async {
    try {
      final readRes = await OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'read',
        'args': [
          [quotationId],
        ],
        'kwargs': {
          'fields': ['state'],
        },
      });

      final currentState = (readRes is List && readRes.isNotEmpty)
          ? (readRes.first['state']?.toString() ?? '')
          : '';

      if (currentState == 'sale' || currentState == 'done') {
        await _updateQuotationStatus(quotationId, currentState);

        return;
      }

      if (currentState == 'cancel') {
        throw Exception('Cannot confirm a cancelled quotation.');
      }

      if (currentState == 'draft' || currentState == 'sent') {
        await OdooSessionManager.safeCallKw({
          'model': 'sale.order',
          'method': 'action_confirm',
          'args': [
            [quotationId],
          ],
          'kwargs': {},
        });

        final verify = await OdooSessionManager.safeCallKw({
          'model': 'sale.order',
          'method': 'read',
          'args': [
            [quotationId],
          ],
          'kwargs': {
            'fields': ['state'],
          },
        });

        final newState = (verify is List && verify.isNotEmpty)
            ? (verify.first['state']?.toString() ?? '')
            : '';
        await _updateQuotationStatus(
          quotationId,
          newState.isEmpty ? 'sale' : newState,
        );

        return;
      }

      throw Exception(
        'Order is in state "$currentState" and cannot be confirmed.',
      );
    } catch (e) {
      final msg = e.toString();
      if (msg.contains(
        'Some orders are not in a state requiring confirmation',
      )) {
        try {
          final verify = await OdooSessionManager.safeCallKw({
            'model': 'sale.order',
            'method': 'read',
            'args': [
              [quotationId],
            ],
            'kwargs': {
              'fields': ['state'],
            },
          });
          final state = (verify is List && verify.isNotEmpty)
              ? (verify.first['state']?.toString() ?? '')
              : '';
          if (state == 'sale' || state == 'done') {
            await _updateQuotationStatus(quotationId, state);

            return;
          }
        } catch (_) {}
      }
      throw Exception('Failed to convert quotation to order: $e');
    }
  }

  Future<void> _updateQuotationStatus(int quotationId, String newState) async {
    try {
      List<String> fields = [
        'name',
        'partner_id',
        'date_order',
        'amount_total',
        'state',
        'currency_id',
        'note',
      ];
      if (_availableFields.contains('delivery_status')) {
        fields.add('delivery_status');
      }
      if (_availableFields.contains('invoice_status')) {
        fields.add('invoice_status');
      }

      final result = await OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'read',
        'args': [
          [quotationId],
        ],
        'kwargs': {'fields': fields},
      });

      if (result.isNotEmpty) {
        final updatedQuotation = result[0] as Map<String, dynamic>;

        final allIndex = _allQuotations.indexWhere((q) => q.id == quotationId);
        if (allIndex != -1) {
          _allQuotations[allIndex] = Quote.fromJson(updatedQuotation);
        }
        final filteredIndex = _filteredQuotations.indexWhere(
          (q) => q.id == quotationId,
        );
        if (filteredIndex != -1) {
          _filteredQuotations[filteredIndex] = Quote.fromJson(updatedQuotation);
        }
        final cacheIndex = _cachedQuotations.indexWhere(
          (q) => q.id == quotationId,
        );
        if (cacheIndex != -1) {
          _cachedQuotations[cacheIndex] = Quote.fromJson(updatedQuotation);
        }

        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteQuotation(int orderId) async {
    try {
      await _quotationService.deleteQuotationInstance(orderId);

      _allQuotations.removeWhere((q) => q.id == orderId);
      _filteredQuotations.removeWhere((q) => q.id == orderId);
      _cachedQuotations.removeWhere((q) => q.id == orderId);
      _totalQuotations = (_totalQuotations - 1).clamp(0, 1 << 31);

      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> cancelQuotation(int quotationId) async {
    try {
      final readResult = await OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'read',
        'args': [
          [quotationId],
        ],
        'kwargs': {
          'fields': ['state', 'name'],
        },
      });

      if (readResult is! List || readResult.isEmpty) {
        throw Exception('Quotation not found');
      }

      final quotation = readResult.first;
      final currentState = quotation['state']?.toString() ?? '';
      final quotationName = quotation['name']?.toString() ?? '#$quotationId';

      if (currentState == 'cancel') {
        throw Exception('Quotation $quotationName is already cancelled');
      }

      if (currentState == 'sale' || currentState == 'done') {
        throw Exception(
          'Cannot cancel $quotationName. This is already a confirmed sale order and cannot be cancelled.',
        );
      }

      if (currentState != 'draft' && currentState != 'sent') {
        throw Exception(
          'Cannot cancel quotation $quotationName. Only draft and sent quotations can be cancelled (current state: $currentState).',
        );
      }

      final canWrite = await PermissionService.instance.canWrite('sale.order');
      if (!canWrite) {
        throw Exception(
          'You do not have permission to cancel quotations (sale.order write).',
        );
      }

      await OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'action_cancel',
        'args': [
          [quotationId],
        ],
        'kwargs': {},
      });

      await _updateQuotationStatus(quotationId, 'cancel');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> clearCache() async {
    _cachedQuotations.clear();
    _cachedTotalCount = 0;
    _lastFetchTime = null;
    _allQuotations.clear();
    _filteredQuotations.clear();
    _currentPage = 0;
    _hasMoreData = true;
    _errorMessage = null;
    _accessErrorMessage = null;
    _activeFilters = {};
    _customerFilterId = null;
    _startDate = null;
    _endDate = null;
    notifyListeners();
  }

  Future<void> updateQuotationStatus(int quotationId, String newState) async {
    await _updateQuotationStatus(quotationId, newState);
  }

  Future<void> updateQuotationNotes(int quotationId, String notes) async {
    try {
      await OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'write',
        'args': [
          [quotationId],
          {'note': notes},
        ],
        'kwargs': {},
      });

      final index = _allQuotations.indexWhere((q) => q.id == quotationId);
      if (index != -1) {
        _allQuotations[index] = _allQuotations[index].copyWith(notes: notes);
        notifyListeners();
      }
    } catch (e) {
      throw Exception('Failed to update notes: $e');
    }
  }

  void clearServerUnreachableState() {
    _isServerUnreachable = false;
    notifyListeners();
  }

  Future<void> clearData() async {
    _allQuotations = [];
    _filteredQuotations = [];
    _orderLines = [];
    _cachedQuotations = [];
    _lastFetchTime = null;
    _isLoading = false;
    _errorMessage = null;
    _accessErrorMessage = null;
    _isServerUnreachable = false;
    _availableFields = [];
    _isFieldsFetched = false;
    _activeFilters.clear();
    _customerFilterId = null;
    _invoiceNameFilter = null;
    _startDate = null;
    _endDate = null;
    _currentPage = 0;
    _totalQuotations = 0;
    _cachedQuotations = [];
    _hasInitiallyLoaded = false;

    if (_connectivityListener != null) {
      _connectivityService.removeListener(_connectivityListener!);
      _connectivityListener = null;
    }
    _retryTimer?.cancel();
    _debounce?.cancel();

    notifyListeners();
  }
}

extension StringExtension on String {
  String capitalize() {
    return isNotEmpty ? '${this[0].toUpperCase()}${substring(1)}' : this;
  }
}
