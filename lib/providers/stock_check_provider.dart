import 'dart:async';
import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../services/session_service.dart';
import '../services/stock_service.dart';

/// Manages stock product listing, pagination, search, and inventory detail fetching.
class StockCheckProvider with ChangeNotifier {
  final ConnectivityService _connectivityService;
  final SessionService _sessionService;
  final StockService _stockService;

  StockCheckProvider({
    ConnectivityService? connectivityService,
    SessionService? sessionService,
    StockService? stockService,
  }) : _connectivityService =
           connectivityService ?? ConnectivityService.instance,
       _sessionService = sessionService ?? SessionService.instance,
       _stockService = stockService ?? StockService.instance;

  List<Map<String, dynamic>> _stockList = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  String _searchQuery = '';
  int _currentPage = 0;
  static const int _pageSize = 20;
  DateTime? _lastFetchTime;
  List<Map<String, dynamic>>? _cache;
  int? _companyId;
  int _totalProducts = 0;
  Timer? _debounceTimer;
  static const Duration _cacheDuration = Duration(seconds: 30);
  bool _isServerUnreachable = false;
  String? _error;

  List<Map<String, dynamic>> get stockList => _stockList;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMoreData => _hasMoreData;
  String get searchQuery => _searchQuery;
  int get currentPage => _currentPage;
  int? get companyId => _companyId;
  int get totalProducts => _totalProducts;
  bool get isServerUnreachable => _isServerUnreachable;
  String? get error => _error;

  bool _isServerUnreachableError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('socketexception') ||
        errorString.contains('connection refused') ||
        errorString.contains('connection timeout') ||
        errorString.contains('host unreachable') ||
        errorString.contains('no route to host') ||
        errorString.contains('network is unreachable') ||
        errorString.contains('failed to connect') ||
        errorString.contains('connection failed');
  }

  /// Loads the first page of stock products, optionally bypassing the cache.
  Future<void> fetchInitialStock({bool forceRefresh = false}) async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    _isServerUnreachable = false;
    notifyListeners();

    if (!_connectivityService.isConnected) {
      _error = "No internet connection available.";
      _isLoading = false;
      notifyListeners();
      return;
    }
    if (!_sessionService.hasValidSession) {
      _error = "No active Odoo session.";
      _isLoading = false;
      notifyListeners();
      return;
    }

    if (!forceRefresh &&
        _cache != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheDuration &&
        _searchQuery.isEmpty) {
      _stockList = List<Map<String, dynamic>>.from(_cache!);
      _isLoading = false;
      notifyListeners();
      return;
    }

    _currentPage = 0;
    _hasMoreData = true;
    _stockList = [];
    notifyListeners();
    try {
      _companyId ??= await _stockService.getCompanyId();

      List<dynamic> domain = [
        ['active', '=', true],
        [
          'type',
          'in',
          ['product', 'consu'],
        ],
      ];
      if (_searchQuery.isNotEmpty) {
        domain = [
          '&',
          '&',
          ['active', '=', true],
          [
            'type',
            'in',
            ['product', 'consu'],
          ],
          '|',
          '|',
          '|',
          ['name', 'ilike', _searchQuery],
          ['default_code', 'ilike', _searchQuery],
          ['categ_id.name', 'ilike', _searchQuery],
          ['barcode', 'ilike', _searchQuery],
        ];
      }

      final templateResult = await _stockService.fetchStockTemplates(
        domain: domain,
        limit: _pageSize,
        offset: 0,
        companyId: _companyId,
      );

      _totalProducts = await _stockService.getStockCount(
        domain: domain,
        companyId: _companyId,
      );

      if (templateResult.isNotEmpty) {
        _stockList = templateResult;
        _hasMoreData = _stockList.length < _totalProducts;

        if (_searchQuery.isEmpty) {
          _cache = List<Map<String, dynamic>>.from(_stockList);
          _lastFetchTime = DateTime.now();
        }
      } else {
        _stockList = [];
        _hasMoreData = false;
      }
    } catch (e) {
      if (_isServerUnreachableError(e)) {
        _isServerUnreachable = true;
        _error =
            "Server/Database unreachable. Please check your server or try again.";
      } else {
        _error = e.toString();
        _isServerUnreachable = false;
      }
      _stockList = [];
      _hasMoreData = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Appends the next page of stock results to [stockList].
  Future<void> fetchNextPage() async {
    if (_isLoading || !_hasMoreData || _isLoadingMore) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      List<dynamic> domain = [
        ['active', '=', true],
        [
          'type',
          'in',
          ['product', 'consu'],
        ],
      ];
      if (_searchQuery.isNotEmpty) {
        domain = [
          '&',
          '&',
          ['active', '=', true],
          [
            'type',
            'in',
            ['product', 'consu'],
          ],
          '|',
          '|',
          '|',
          ['name', 'ilike', _searchQuery],
          ['default_code', 'ilike', _searchQuery],
          ['categ_id.name', 'ilike', _searchQuery],
          ['barcode', 'ilike', _searchQuery],
        ];
      }
      final offset = (_currentPage + 1) * _pageSize;

      final templateResult = await _stockService.fetchStockTemplates(
        domain: domain,
        limit: _pageSize,
        offset: offset,
        companyId: _companyId,
      );

      if (templateResult.isNotEmpty) {
        _stockList.addAll(templateResult);
        _currentPage++;
        _hasMoreData = _stockList.length < _totalProducts;
      } else {
        _hasMoreData = false;
      }
    } catch (e) {
      if (_isServerUnreachableError(e)) {
        _isServerUnreachable = true;
        _error =
            "Server/Database unreachable. Please check your server or try again.";
      } else {
        _error = e.toString();
        _isServerUnreachable = false;
      }
      _hasMoreData = false;
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Updates the search query and triggers a debounced refresh.
  void updateSearchQuery(String query) {
    _searchQuery = query;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      fetchInitialStock(forceRefresh: true);
    });
  }

  /// Clears the cache and reloads the first page of stock.
  void refresh() {
    _cache = null;
    _lastFetchTime = null;
    fetchInitialStock(forceRefresh: true);
  }

  /// Fetches full inventory details (quants, moves, locations) for [productId].
  Future<Map<String, dynamic>> fetchInventoryDetails(int productId) async {
    try {
      final locationResult = await _stockService.fetchLocations(
        companyId: _companyId,
      );

      final locationUsageMap = <String, String>{};
      final internalLocations = <String>[];
      for (var loc in locationResult) {
        final locationName = loc['complete_name'] as String;
        final usage = loc['usage'] as String;
        locationUsageMap[locationName] = usage;
        if (usage == 'internal') {
          internalLocations.add(locationName);
        }
      }

      final stockQuantResult = await _stockService.fetchStockQuants(
        productId,
        companyId: _companyId,
      );

      List<Map<String, dynamic>> stockDetails = [];
      double quantTotalInStock = 0.0;
      double totalAvailable = 0.0;
      double totalReserved = 0.0;
      for (var quant in stockQuantResult) {
        final locationName =
            quant['location_id'] is List && quant['location_id'].length > 1
            ? quant['location_id'][1]
            : 'Unknown';
        final locationId =
            quant['location_id'] is List && quant['location_id'].length > 0
            ? quant['location_id'][0]
            : 'Unknown';
        final quantity = (quant['quantity'] as num?)?.toDouble() ?? 0.0;
        final reserved =
            (quant['reserved_quantity'] as num?)?.toDouble() ?? 0.0;
        final available = quantity - reserved;
        String usage = locationUsageMap[locationName] ?? 'unknown';
        bool shouldCountInTotals = false;

        if (usage == 'internal') {
          shouldCountInTotals = true;
        }
        if (shouldCountInTotals) {
          quantTotalInStock += quantity;
          totalAvailable += available;
          totalReserved += reserved;
        }
        stockDetails.add({
          'warehouse': locationName,
          'quantity': quantity,
          'reserved_quantity': reserved,
          'available': available,
          'is_external': !shouldCountInTotals,
          'location_type': usage,
          'is_counted_in_totals': shouldCountInTotals,
        });
      }

      final productStockInfo = await _stockService.fetchProductStockInfo(
        productId,
        companyId: _companyId,
      );

      final expectedStock = productStockInfo != null
          ? (productStockInfo['qty_available'] as num?)?.toDouble() ?? 0.0
          : 0.0;
      final expectedVirtual = productStockInfo != null
          ? (productStockInfo['virtual_available'] as num?)?.toDouble() ?? 0.0
          : 0.0;
      final totalInStock = expectedStock;
      final forecastedStock = expectedVirtual;

      final incomingMoveResult = await _stockService.fetchStockMoves(
        productId: productId,
        domain: [
          ['product_id', '=', productId],
          [
            'state',
            'in',
            ['confirmed', 'waiting', 'assigned', 'partially_available'],
          ],
          ['location_dest_id.usage', '=', 'internal'],
          ['location_id.usage', '!=', 'internal'],
        ],
        companyId: _companyId,
      );

      final outgoingMoveResult = await _stockService.fetchStockMoves(
        productId: productId,
        domain: [
          ['product_id', '=', productId],
          [
            'state',
            'in',
            ['confirmed', 'waiting', 'assigned', 'partially_available'],
          ],
          ['location_id.usage', '=', 'internal'],
          [
            'location_dest_id.usage',
            'in',
            ['customer', 'production', 'inventory'],
          ],
        ],
        companyId: _companyId,
      );

      final allMoveLineIds = <int>[];
      for (var move in [...incomingMoveResult, ...outgoingMoveResult]) {
        if (move['move_line_ids'] is List) {
          allMoveLineIds.addAll(
            (move['move_line_ids'] as List).whereType<int>(),
          );
        }
      }

      Map<int, double> moveLineQtyDone = {};
      if (allMoveLineIds.isNotEmpty) {
        final moveLineResult = await _stockService.fetchStockMoveLines(
          allMoveLineIds,
          companyId: _companyId,
        );

        for (var line in moveLineResult) {
          final moveId = (line['move_id'] is List && line['move_id'].isNotEmpty)
              ? line['move_id'][0] as int
              : null;
          final qtyDone = (line['quantity'] as num?)?.toDouble() ?? 0.0;
          if (moveId != null) {
            moveLineQtyDone[moveId] =
                (moveLineQtyDone[moveId] ?? 0.0) + qtyDone;
          }
        }
      }

      List<Map<String, dynamic>> incomingStock = [];
      double totalIncoming = 0.0;
      for (var move in incomingMoveResult) {
        final moveId = move['id'] as int;
        final quantityToReceive =
            (move['product_uom_qty'] as num?)?.toDouble() ?? 0.0;
        final qtyDone = moveLineQtyDone[moveId] ?? 0.0;
        final remainingToReceive = quantityToReceive - qtyDone;
        if (remainingToReceive > 0) {
          totalIncoming += remainingToReceive;
        }
        incomingStock.add({
          'quantity': remainingToReceive,
          'expected_date': move['date'] ?? 'N/A',
          'from_location':
              move['location_id'] is List && move['location_id'].length > 1
              ? move['location_id'][1]
              : 'Unknown',
          'to_location':
              move['location_dest_id'] is List &&
                  move['location_dest_id'].length > 1
              ? move['location_dest_id'][1]
              : 'Unknown',
          'state': move['state'] ?? 'N/A',
        });
      }

      List<Map<String, dynamic>> outgoingStock = [];
      double totalOutgoing = 0.0;
      for (var move in outgoingMoveResult) {
        final moveId = move['id'] as int;
        final quantityToDeliver =
            (move['product_uom_qty'] as num?)?.toDouble() ?? 0.0;
        final qtyDone = moveLineQtyDone[moveId] ?? 0.0;
        final remainingToDeliver = quantityToDeliver - qtyDone;
        if (remainingToDeliver > 0) {
          totalOutgoing += remainingToDeliver;
        }
        outgoingStock.add({
          'quantity': remainingToDeliver,
          'date_expected': move['date'] ?? 'N/A',
          'from_location':
              move['location_id'] is List && move['location_id'].length > 1
              ? move['location_id'][1]
              : 'Unknown',
          'to_location':
              move['location_dest_id'] is List &&
                  move['location_dest_id'].length > 1
              ? move['location_dest_id'][1]
              : 'Unknown',
          'state': move['state'] ?? 'N/A',
        });
      }
      return {
        'stock_details': stockDetails,
        'incoming_stock': incomingStock,
        'outgoing_stock': outgoingStock,
        'totalInStock': totalInStock,
        'quantTotalInStock': quantTotalInStock,
        'totalAvailable': totalAvailable,
        'totalReserved': totalReserved,
        'totalIncoming': totalIncoming,
        'totalOutgoing': totalOutgoing,
        'forecastedStock': forecastedStock,
        'expectedStock': expectedStock,
        'expectedVirtual': expectedVirtual,
      };
    } catch (e) {
      return {
        'stock_details': [],
        'incoming_stock': [],
        'outgoing_stock': [],
        'totalInStock': 0.0,
        'quantTotalInStock': 0.0,
        'totalAvailable': 0.0,
        'totalReserved': 0.0,
        'totalIncoming': 0.0,
        'totalOutgoing': 0.0,
        'forecastedStock': 0.0,
        'expectedStock': 0.0,
        'expectedVirtual': 0.0,
      };
    }
  }

  /// Resets all provider state to defaults.
  Future<void> clearData() async {
    _stockList = [];
    _isLoading = false;
    _isLoadingMore = false;
    _hasMoreData = true;
    _searchQuery = '';
    _currentPage = 0;
    _lastFetchTime = null;
    _cache = null;
    _companyId = null;
    _totalProducts = 0;
    _isServerUnreachable = false;
    _error = null;

    _debounceTimer?.cancel();

    notifyListeners();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
