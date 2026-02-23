import 'dart:async';

import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/odoo_session_manager.dart';
import '../services/connectivity_service.dart';
import '../services/session_service.dart';
import '../services/field_validation_service.dart';
import '../services/product_service.dart';

/// Manages the product list with pagination, filtering, grouping, category selection, and search.
class ProductProvider with ChangeNotifier {
  final ConnectivityService _connectivityService;
  final SessionService _sessionService;
  final ProductService _productService;

  ProductProvider({
    ConnectivityService? connectivityService,
    SessionService? sessionService,
    ProductService? productService,
  }) : _connectivityService =
           connectivityService ?? ConnectivityService.instance,
       _sessionService = sessionService ?? SessionService.instance,
       _productService = productService ?? ProductService.instance;

  List<Product> _products = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isSearching = false;

  static const int _pageSize = 40;
  int _currentPage = 0;
  bool _hasMoreData = true;
  String _currentSearchQuery = '';
  String _currentCategory = 'All Products';
  Map<String, dynamic>? _currentFilters;
  int _totalProducts = 0;
  String? _error;
  DateTime? _lastFetchTime;
  bool _isServerUnreachable = false;
  bool _hasInitiallyLoaded = false;
  static const cacheDuration = Duration(minutes: 10);

  String? _accessErrorMessage;
  String? get accessErrorMessage => _accessErrorMessage;

  List<String> _categories = ['All Products'];
  List<String> get categories => _categories;

  Map<String, String> _groupByOptions = {};
  String? _selectedGroupBy;
  bool _isGrouped = false;
  List<String> _availableFields = ['qty_available'];
  bool _isFieldsFetched = false;

  final Set<String> _activeFilters = {};
  bool _showActiveOnly = true;
  bool _showInStockOnly = false;

  bool _showServicesOnly = false;
  bool _showConsumablesOnly = false;
  bool _showStorableOnly = false;
  bool _showAvailableOnly = false;

  double? _priceMin;
  double? _priceMax;
  String? _selectedBrand;
  DateTime? _startDate;
  DateTime? _endDate;

  List<Product> get products => _products;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isSearching => _isSearching;
  bool get hasMoreData => _hasMoreData;
  int get totalProducts => _totalProducts;
  String? get error => _error;
  DateTime? get lastFetchTime => _lastFetchTime;
  bool get isServerUnreachable => _isServerUnreachable;
  bool get hasInitiallyLoaded => _hasInitiallyLoaded;
  String get currentCategory => _currentCategory;

  Set<String> get activeFilters => _activeFilters;
  bool get showActiveOnly => _showActiveOnly;
  bool get showInStockOnly => _showInStockOnly;

  bool get showServicesOnly => _showServicesOnly;
  bool get showConsumablesOnly => _showConsumablesOnly;
  bool get showStorableOnly => _showStorableOnly;
  bool get showAvailableOnly => _showAvailableOnly;

  double? get priceMin => _priceMin;
  double? get priceMax => _priceMax;
  String? get selectedBrand => _selectedBrand;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;

  Map<String, String> get groupByOptions => _groupByOptions;
  String? get selectedGroupBy => _selectedGroupBy;
  bool get isGrouped => _isGrouped;

  final Map<String, int> _groupSummary = {};
  Map<String, int> get groupSummary => _groupSummary;

  final Map<String, List<Product>> _loadedGroups = {};
  Map<String, List<Product>> get loadedGroups => _loadedGroups;

  int get pageSize => _pageSize;
  int get currentPage => _currentPage;
  int get startRecord =>
      _totalProducts == 0 ? 0 : (_currentPage * _pageSize) + 1;

  int get endRecord => ((_currentPage * _pageSize) + _pageSize) > _totalProducts
      ? _totalProducts
      : ((_currentPage * _pageSize) + _pageSize);

  int get totalPages =>
      _totalProducts > 0 ? ((_totalProducts - 1) ~/ _pageSize) + 1 : 0;
  bool get canGoToPreviousPage => _currentPage > 0;
  bool get canGoToNextPage => _hasMoreData;

  /// Returns a pagination string like '1-40/200' for the current page.
  String getPaginationText() {
    if (_isGrouped) {
      return "$_totalProducts/$_totalProducts";
    }
    if (_totalProducts == 0 && _products.isEmpty) return "0-0/0";

    return "$startRecord-$endRecord/$_totalProducts";
  }

  /// Jumps to [page] and fetches its products.
  Future<void> goToPage(int page) async {
    if (page < 0 || page == _currentPage) return;

    _currentPage = page;
    await _fetchSpecificPage();
  }

  /// Advances to the next page of products.
  Future<void> goToNextPage() async {
    if (!canGoToNextPage) return;
    _currentPage++;
    await _fetchSpecificPage();
  }

  /// Returns to the previous page of products.
  Future<void> goToPreviousPage() async {
    if (!canGoToPreviousPage) return;
    _currentPage--;
    await _fetchSpecificPage();
  }

  Future<void> _fetchSpecificPage() async {
    if (_isLoading || _isLoadingMore) return;

    if (!_connectivityService.isConnected || !_sessionService.hasValidSession) {
      _error = "No connection or session available.";
      notifyListeners();
      return;
    }

    _isLoadingMore = true;
    _error = null;
    notifyListeners();

    try {
      List<dynamic> domain = _buildDomain(
        _currentSearchQuery,
        _currentCategory,
        _currentFilters,
      );

      final List<String> fieldsToFetch = [
        'id',
        'name',
        'list_price',
        'default_code',
        'categ_id',
        'barcode',
        'image_128',
        'currency_id',
        'active',
        'product_variant_count',
        'product_variant_ids',
      ];
      if (_availableFields.contains('qty_available')) {
        fieldsToFetch.add('qty_available');
      }

      try {
        final result =
            await FieldValidationService.executeWithFieldValidation<
              List<Map<String, dynamic>>
            >(
              model: 'product.template',
              initialFields: fieldsToFetch,
              apiCall: (currentFields) async {
                return await _productService.fetchProducts(
                  domain: domain,
                  fields: currentFields,
                  limit: _pageSize,
                  offset: _currentPage * _pageSize,
                );
              },
            );
        _processResult(result);
      } catch (e) {
        rethrow;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  void _processResult(List<dynamic> result) {
    final fetchedProducts = result
        .map((productData) {
          if (productData is Map) {
            try {
              return Product.fromJson(Map<String, dynamic>.from(productData));
            } catch (e) {
              return null;
            }
          }
          return null;
        })
        .whereType<Product>()
        .toList();

    _products = fetchedProducts;

    if (_totalProducts > 0) {
      _hasMoreData = (_currentPage + 1) * _pageSize < _totalProducts;
    } else {
      _hasMoreData = fetchedProducts.length == _pageSize;
    }
  }

  List<dynamic> _buildDomain(
    String searchQuery,
    String category,
    Map<String, dynamic>? filters,
  ) {
    final List<dynamic> domain = [];

    domain.add(['sale_ok', '=', true]);

    if (category != 'All Products' && category.isNotEmpty) {
      domain.add(['categ_id.name', '=', category]);
    }

    if (filters != null) {
      if (filters['showActiveOnly'] == true) {
        domain.add(['active', '=', true]);
      }
      if (filters['showInStockOnly'] == true) {
        domain.add(['qty_available', '>', 0]);
      }

      if (filters['showServicesOnly'] == true) {
        domain.add(['type', '=', 'service']);
      }
      if (filters['showConsumablesOnly'] == true) {
        domain.add(['type', '=', 'consu']);
      }
      if (filters['showStorableOnly'] == true) {
        domain.add(['type', '=', 'product']);
      }
      if (filters['showAvailableOnly'] == true) {
        domain.add(['qty_available', '>', 0]);
      }

      if (filters['priceMin'] != null && filters['priceMax'] != null) {
        domain.add(['list_price', '>=', filters['priceMin']]);
        domain.add(['list_price', '<=', filters['priceMax']]);
      }

      if (filters['startDate'] != null || filters['endDate'] != null) {
        if (filters['startDate'] != null && filters['endDate'] != null) {
          final start = filters['startDate'] as DateTime;
          final end = filters['endDate'] as DateTime;
          final startStr =
              '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')} 00:00:00';
          final endStr =
              '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')} 23:59:59';
          domain.add(['create_date', '>=', startStr]);
          domain.add(['create_date', '<=', endStr]);
        } else if (filters['startDate'] != null) {
          final start = filters['startDate'] as DateTime;
          final startStr =
              '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')} 00:00:00';
          domain.add(['create_date', '>=', startStr]);
        } else if (filters['endDate'] != null) {
          final end = filters['endDate'] as DateTime;
          final endStr =
              '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')} 23:59:59';
          domain.add(['create_date', '<=', endStr]);
        }
      }
    }

    final q = searchQuery.trim();
    if (q.isNotEmpty) {
      domain.add('|');
      domain.add(['name', 'ilike', q]);
      domain.add('|');
      domain.add(['default_code', 'ilike', q]);
      domain.add(['barcode', 'ilike', q]);
    }

    return domain;
  }

  /// Fetches products from Odoo, using cache unless [forceRefresh] is set.
  Future<void> fetchProducts({
    bool forceRefresh = false,
    String? searchQuery,
    String? category,
    Map<String, dynamic>? filters,
  }) async {
    if (_isLoading || _isSearching) return;

    if (!forceRefresh &&
        _products.isNotEmpty &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < cacheDuration &&
        searchQuery == null &&
        category == null) {
      return;
    }

    if (!_connectivityService.isConnected) {
      _error = "No internet connection available.";
      _isLoading = false;
      _isSearching = false;
      _isServerUnreachable = false;
      _accessErrorMessage = null;
      notifyListeners();
      return;
    }

    if (!_sessionService.hasValidSession) {
      _error = "No active Odoo session.";
      _isLoading = false;
      _isSearching = false;
      _isServerUnreachable = false;
      _accessErrorMessage = null;
      notifyListeners();
      return;
    }

    _currentSearchQuery = (searchQuery ?? '').trim();
    _currentCategory = category ?? 'All Products';
    _currentFilters = filters;
    _currentPage = 0;
    _hasMoreData = true;
    _products = [];

    if (_currentSearchQuery.isNotEmpty) {
      _isSearching = true;
    } else {
      _isLoading = true;
    }
    _error = null;
    _isServerUnreachable = false;
    _accessErrorMessage = null;
    notifyListeners();

    try {
      final List<dynamic> domain = _buildDomain(
        _currentSearchQuery,
        _currentCategory,
        _currentFilters,
      );

      final countFuture = _productService
          .getProductCount(domain)
          .timeout(const Duration(seconds: 10), onTimeout: () => 0);

      final List<String> fieldsToFetch = [
        'id',
        'name',
        'list_price',
        'default_code',
        'categ_id',
        'barcode',
        'image_128',
        'currency_id',
        'active',
        'product_variant_count',
        'product_variant_ids',
      ];

      if (_availableFields.contains('qty_available')) {
        fieldsToFetch.add('qty_available');
      }

      final listFuture =
          FieldValidationService.executeWithFieldValidation<
                List<Map<String, dynamic>>
              >(
                model: 'product.template',
                initialFields: fieldsToFetch,
                apiCall: (currentFields) async {
                  return await _productService.fetchProducts(
                    domain: domain,
                    fields: currentFields,
                    limit: _pageSize,
                    offset: _currentPage * _pageSize,
                  );
                },
              )
              .timeout(
                const Duration(seconds: 15),
                onTimeout: () =>
                    throw TimeoutException('Product fetch timed out'),
              );

      final results = await Future.wait([countFuture, listFuture]);
      _totalProducts = results[0] as int;
      _processResult(results[1] as List<dynamic>);
      _lastFetchTime = DateTime.now();
    } on TimeoutException {
      _error = "Request timed out. Please check your connection and try again.";
      _isServerUnreachable = false;
      _accessErrorMessage = null;
    } catch (e) {
      if (_isServerUnreachableError(e)) {
        _isServerUnreachable = true;
        _error =
            "Server/Database unreachable. Please check your server or try again.";
        _accessErrorMessage = null;
      } else if (e.toString().contains('AccessError') ||
          e.toString().contains('not allowed to access')) {
        _accessErrorMessage =
            "You do not have permission to view products. Please contact your administrator to request access.";
        _error = null;
        _isServerUnreachable = false;
      } else if (e.toString().contains('SocketException') ||
          e.toString().contains('NetworkException')) {
        _error = "Network error. Please check your internet connection.";
        _isServerUnreachable = false;
        _accessErrorMessage = null;
      } else {
        _error = e.toString();
        _isServerUnreachable = false;
        _accessErrorMessage = null;
      }
    } finally {
      _isLoading = false;
      _isSearching = false;
      notifyListeners();
    }
  }

  /// Loads available product categories from Odoo.
  Future<void> fetchCategories() async {
    try {
      final result = await _productService.fetchCategoryOptions();

      final Set<String> uniqueCategories = {'All Products'};
      for (var category in result) {
        String categoryName = category['label'] ?? '';
        if (categoryName.isNotEmpty) {
          uniqueCategories.add(categoryName);
        }
      }

      _categories = uniqueCategories.toList()..sort();
      notifyListeners();
    } catch (e) {
      _categories = ['All Products'];
    }
  }

  /// Force-refreshes the product list with optional search, category, and filter overrides.
  Future<void> refreshProducts({
    String? searchQuery,
    String? category,
    Map<String, dynamic>? filters,
  }) async {
    await fetchProducts(
      forceRefresh: true,
      searchQuery: searchQuery,
      category: category,
      filters: filters,
    );
  }

  /// Loads the next page of products (alias for [goToNextPage]).
  Future<void> loadMoreProducts() async {
    await goToNextPage();
  }

  /// Applies one or more filter values to the current state without fetching.
  void setFilterState({
    bool? showActiveOnly,
    bool? showInStockOnly,

    bool? showServicesOnly,
    bool? showConsumablesOnly,
    bool? showStorableOnly,
    bool? showAvailableOnly,

    double? priceMin,
    double? priceMax,
    String? selectedBrand,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    if (showActiveOnly != null) _showActiveOnly = showActiveOnly;
    if (showInStockOnly != null) _showInStockOnly = showInStockOnly;

    if (showServicesOnly != null) _showServicesOnly = showServicesOnly;
    if (showConsumablesOnly != null) _showConsumablesOnly = showConsumablesOnly;
    if (showStorableOnly != null) _showStorableOnly = showStorableOnly;
    if (showAvailableOnly != null) _showAvailableOnly = showAvailableOnly;

    if (priceMin != null) _priceMin = priceMin;
    if (priceMax != null) _priceMax = priceMax;
    if (selectedBrand != null) _selectedBrand = selectedBrand;
    if (startDate != null) _startDate = startDate;
    if (endDate != null) _endDate = endDate;
    notifyListeners();
  }

  /// Resets all active filters to their defaults.
  void clearFilters() {
    _activeFilters.clear();
    _showActiveOnly = true;
    _showInStockOnly = false;

    _showServicesOnly = false;
    _showConsumablesOnly = false;
    _showStorableOnly = false;
    _showAvailableOnly = false;

    _priceMin = null;
    _priceMax = null;
    _selectedBrand = null;
    _startDate = null;
    _endDate = null;
    notifyListeners();
  }

  /// Clears the server-unreachable error flag.
  void clearServerUnreachableState() {
    _isServerUnreachable = false;
    notifyListeners();
  }

  /// Sets the group-by field and triggers a group summary fetch.
  void setGroupBy(String? groupBy) {
    _selectedGroupBy = groupBy;
    _isGrouped = groupBy != null;
    _groupSummary.clear();
    _loadedGroups.clear();
    _products.clear();
    _lastFetchTime = null;

    if (_isGrouped) {
      _fetchGroupSummary();
    }
    notifyListeners();
  }

  Future<void> _fetchGroupSummary() async {
    if (!_isGrouped || _selectedGroupBy == null) return;

    try {
      List<dynamic> domain = _buildDomain(
        _currentSearchQuery,
        _currentCategory,
        _currentFilters,
      );

      final response = await _productService.fetchGroupSummary(
        domain: domain,
        groupBy: _selectedGroupBy!,
      );

      _groupSummary.clear();

      int totalGroupedCount = 0;
      for (final group in response) {
        final groupKey = _getGroupKeyFromReadGroup(group, _selectedGroupBy!);
        final count = group['__count'] ?? 0;
        _groupSummary[groupKey] = count;
        totalGroupedCount += count as int;
      }

      if (_totalProducts > totalGroupedCount) {
        final missingCount = _totalProducts - totalGroupedCount;
        String undefinedLabel;

        if (_selectedGroupBy == 'categ_id') {
          undefinedLabel = 'Uncategorized';
        } else if (_selectedGroupBy == 'type') {
          undefinedLabel = 'Unknown Type';
        } else {
          undefinedLabel = 'Undefined';
        }

        _groupSummary[undefinedLabel] = missingCount;
      }

      notifyListeners();
    } catch (e) {}
  }

  /// Loads all products belonging to the group identified by [groupKey].
  Future<void> loadGroupProducts(String groupKey) async {
    if (!_isGrouped || _selectedGroupBy == null) return;

    if (_loadedGroups.containsKey(groupKey)) return;

    try {
      List<dynamic> domain = _buildDomain(
        _currentSearchQuery,
        _currentCategory,
        _currentFilters,
      );

      final groupDomain = _buildGroupDomain(groupKey, _selectedGroupBy!);
      domain.addAll(groupDomain);

      final result = await _productService.fetchProducts(
        domain: domain,
        fields: [
          'id',
          'name',
          'list_price',
          'qty_available',
          'default_code',
          'barcode',
          'categ_id',
          'image_128',
          'currency_id',
          'active',
          'sale_ok',
          'purchase_ok',
          'create_date',
          'write_date',
          'uom_id',
          'taxes_id',
          'product_variant_count',
          'product_variant_ids',
        ],
        limit: 1000,
      );

      final products = result
          .map((data) {
            try {
              return Product.fromJson(data);
            } catch (e) {
              return null;
            }
          })
          .where((p) => p != null)
          .cast<Product>()
          .toList();

      _loadedGroups[groupKey] = products;
      notifyListeners();
    } catch (e) {}
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

  Future<List<String>> _fetchAvailableFields() async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return [];

      final fieldsResponse = await OdooSessionManager.safeCallKw({
        'model': 'product.template',
        'method': 'fields_get',
        'args': [],
        'kwargs': {},
      });

      if (fieldsResponse is Map) {
        return fieldsResponse.keys.cast<String>().toList();
      }
    } catch (e) {}
    return [];
  }

  String _labelForField(String field) {
    switch (field) {
      case 'categ_id':
        return 'Product Category';
      case 'type':
        return 'Product Type';
      case 'pos_categ_id':
        return 'POS Product Category';
      default:
        return field
            .replaceAll('_', ' ')
            .split(' ')
            .map(
              (word) =>
                  word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1),
            )
            .join(' ');
    }
  }

  /// Returns the available group-by field options as a label map.
  Future<Map<String, String>> fetchGroupByOptions() async {
    try {
      if (!_isFieldsFetched || _availableFields.isEmpty) {
        _availableFields = await _fetchAvailableFields();
        _isFieldsFetched = true;
      }

      final baseline = <String>['categ_id', 'type', 'pos_categ_id'];

      final validFields = baseline
          .where(
            (f) => _availableFields.isEmpty || _availableFields.contains(f),
          )
          .toList();

      final map = <String, String>{
        for (final f in validFields) f: _labelForField(f),
      };

      _groupByOptions = map;
      notifyListeners();
      return _groupByOptions;
    } catch (e) {
      return _groupByOptions;
    }
  }

  String _getGroupKeyFromReadGroup(Map group, String groupByField) {
    final groupValue = group[groupByField];
    if (groupValue == null || groupValue == false) {
      return 'Unknown';
    }

    if (groupValue is List && groupValue.isNotEmpty) {
      return groupValue[1]?.toString() ?? 'Unknown';
    }

    return groupValue.toString();
  }

  List<dynamic> _buildGroupDomain(String groupKey, String groupByField) {
    if (groupKey == 'Unknown' || groupKey == 'No Category') {
      return [
        [groupByField, '=', false],
      ];
    }

    if (groupByField == 'categ_id') {
      return [
        ['categ_id.name', '=', groupKey],
      ];
    }

    if (groupByField == 'type') {
      String odooValue;
      switch (groupKey) {
        case 'Consumable':
          odooValue = 'consu';
          break;
        case 'Service':
          odooValue = 'service';
          break;
        case 'Storable Product':
          odooValue = 'product';
          break;
        default:
          odooValue = groupKey.toLowerCase();
      }
      return [
        [groupByField, '=', odooValue],
      ];
    }

    if (groupByField == 'active' ||
        groupByField == 'sale_ok' ||
        groupByField == 'purchase_ok') {
      return [
        [groupByField, '=', groupKey == 'Active' || groupKey == 'Yes'],
      ];
    }

    if (groupByField == 'create_date' || groupByField == 'write_date') {
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
        final year = int.tryParse(parts[1]);
        if (monthIndex > 0 && year != null) {
          final startDate = DateTime(year, monthIndex, 1);
          final endDate = DateTime(
            year,
            monthIndex + 1,
            1,
          ).subtract(Duration(days: 1));
          return [
            [
              groupByField,
              '>=',
              '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')} 00:00:00',
            ],
            [
              groupByField,
              '<=',
              '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')} 23:59:59',
            ],
          ];
        }
      }
    }

    return [
      [groupByField, '=', groupKey],
    ];
  }

  Map<String, List<Product>> groupProducts(List<Product> products) {
    if (!_isGrouped || _selectedGroupBy == null || _selectedGroupBy!.isEmpty) {
      return {};
    }

    if (products.isEmpty) {
      return {};
    }

    final groups = <String, List<Product>>{};

    for (final product in products) {
      try {
        final groupKey = _getGroupKey(product, _selectedGroupBy!);
        groups.putIfAbsent(groupKey, () => []).add(product);
      } catch (e) {
        groups.putIfAbsent('Unknown', () => []).add(product);
      }
    }

    final sortedGroups = Map.fromEntries(
      groups.entries.toList()..sort((a, b) {
        if (a.key.toLowerCase().contains('unknown') &&
            !b.key.toLowerCase().contains('unknown')) {
          return 1;
        }
        if (!a.key.toLowerCase().contains('unknown') &&
            b.key.toLowerCase().contains('unknown')) {
          return -1;
        }
        return a.key.compareTo(b.key);
      }),
    );

    return sortedGroups;
  }

  String _getGroupKey(Product product, String groupByField) {
    try {
      switch (groupByField) {
        case 'categ_id':
          return product.categoryValue;
        case 'active':
          return product.active == true ? 'Active' : 'Inactive';
        case 'sale_ok':
          return product.saleOk == true ? 'For Sale' : 'Not for Sale';
        case 'purchase_ok':
          return product.purchaseOk == true
              ? 'Can Purchase'
              : 'Cannot Purchase';
        case 'create_date':
          if (product.creationDate != null) {
            final date = product.creationDate!;
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
          }
          return 'Unknown Date';
        default:
          return 'Other';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  void updateProduct(Product updatedProduct) {
    final index = _products.indexWhere((p) => p.id == updatedProduct.id);
    if (index != -1) {
      _products[index] = updatedProduct;
      notifyListeners();
    }
  }

  Future<void> clearData() async {
    _products = [];
    _isLoading = false;
    _isLoadingMore = false;
    _isSearching = false;
    _currentPage = 0;
    _hasMoreData = true;
    _currentSearchQuery = '';
    _currentCategory = 'All Products';
    _totalProducts = 0;
    _error = null;
    _lastFetchTime = null;
    _isServerUnreachable = false;
    _hasInitiallyLoaded = false;
    _accessErrorMessage = null;
    _categories = ['All Products'];
    _groupByOptions.clear();
    _selectedGroupBy = null;
    _isGrouped = false;
    _groupSummary.clear();
    _isFieldsFetched = false;
    _loadedGroups.clear();
    clearFilters();
    notifyListeners();
  }
}
