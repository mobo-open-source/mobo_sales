import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:hugeicons/hugeicons.dart';

import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:shimmer/shimmer.dart';
import 'package:provider/provider.dart';
import '../../services/odoo_session_manager.dart';
import '../../services/connectivity_service.dart';
import '../../services/session_service.dart';
import '../../services/field_validation_service.dart';
import '../../utils/app_theme.dart';
import '../../widgets/barcode_scanner_screen.dart';
import '../../widgets/connection_status_widget.dart';
import '../../widgets/custom_snackbar.dart';
import '../../widgets/list_shimmer.dart';
import '../../widgets/product_list_tile.dart';
import 'package:flutter/services.dart';

class StockCheckPage extends StatefulWidget {
  const StockCheckPage({super.key});

  @override
  _StockCheckPageState createState() => _StockCheckPageState();
}

class _StockCheckPageState extends State<StockCheckPage> {
  bool _isLoading = false;
  bool _isScanning = false;
  bool _isActionLoading = false;
  List<Map<String, dynamic>> _productTemplates = [];
  List<Map<String, dynamic>> _filteredProductTemplates = [];
  final TextEditingController _searchController = TextEditingController();
  OdooSession? _sessionId;

  final ScrollController _scrollController = ScrollController();
  int _currentPage = 0;
  static const int _pageSize = 20;
  bool _hasMoreData = true;
  bool _isLoadingMore = false;
  int _totalProducts = 0;
  int? _companyId;
  bool _hasSearched = false;

  String? _clickedTileId;
  bool _isServerUnreachable = false;

  Timer? _debounceTimer;
  String _currentSearchQuery = '';
  String _lastSearchValue = '';
  bool _isSearching = false;

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

  Widget _buildTag({
    required String text,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildProductImage(
    String? imageUrl,
    Uint8List? imageBytes,
    String name,
  ) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: imageUrl != null && imageUrl.isNotEmpty
            ? (imageUrl.startsWith('http')
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      httpHeaders: _sessionId != null
                          ? {"Cookie": "session_id=$_sessionId"}
                          : null,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      progressIndicatorBuilder:
                          (context, url, downloadProgress) => SizedBox(
                            width: 60,
                            height: 60,
                            child: Center(
                              child: CircularProgressIndicator(
                                value: downloadProgress.progress,
                                strokeWidth: 2,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ),
                      errorWidget: (context, url, error) => const Icon(
                        HugeIcons.strokeRoundedImage03,
                        color: Colors.grey,
                        size: 24,
                      ),
                    )
                  : Image.memory(
                      imageBytes!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        HugeIcons.strokeRoundedImage03,
                        color: Colors.grey,
                        size: 24,
                      ),
                    ))
            : const Icon(
                HugeIcons.strokeRoundedImage03,
                color: Colors.grey,
                size: 30,
              ),
      ),
    );
  }

  Widget _buildProductCard(
    Map<String, dynamic> template,
    Color cardColor,
    Color borderColor,
    Color textColor,
    Color subtitleColor,
    bool isDark,
  ) {
    final imageUrl = template['image_url'] as String?;
    Uint8List? imageBytes;
    if (imageUrl != null &&
        imageUrl.isNotEmpty &&
        !imageUrl.startsWith('http')) {
      try {
        final base64String = imageUrl.contains(',')
            ? imageUrl.split(',')[1]
            : imageUrl;
        imageBytes = base64Decode(base64String);
      } catch (e) {}
    }

    return ProductListTile(
      id: template['id'].toString(),
      name: template['name'] as String,
      defaultCode: (template['default_code']?.toString() == 'false')
          ? null
          : template['default_code']?.toString(),
      listPrice: (template['price'] as num?)?.toDouble() ?? 0.0,
      currencyId: null,
      category: template['category']?.toString(),
      qtyAvailable: ((template['qty_available'] as num?)?.toDouble() ?? 0.0)
          .toDouble(),
      imageUrl: imageUrl,
      imageBytes: imageBytes,
      variantCount: (template['variants'] as List).length,
      isDark: isDark,
      onTap: null,
    );
  }

  @override
  void initState() {
    super.initState();
    _isLoading = true;

    _searchController.addListener(() {
      final currentValue = _searchController.text;
      if (currentValue == _lastSearchValue) return;
      _lastSearchValue = currentValue;

      if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _performSearch(currentValue.trim());
      });
    });

    _scrollController.addListener(_scrollListener);
    _initializeAndLoadStock();
  }

  Future<void> _initializeAndLoadStock() async {
    final connectivityService = context.read<ConnectivityService>();
    final sessionService = context.read<SessionService>();

    while (!connectivityService.isInitialized ||
        !sessionService.isInitialized) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (connectivityService.isConnected && sessionService.hasValidSession) {
      _loadStockData();
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMoreData && !_isLoading) {
        _loadMoreData();
      }
    }
  }

  Future<void> _loadMoreData() async {
    if (_isLoading || !_hasMoreData || _isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
    });
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }
      final offset = (_currentPage + 1) * _pageSize;

      List<dynamic> domain = [
        ['active', '=', true],
        [
          'type',
          'in',
          ['product', 'consu'],
        ],
      ];
      final templateResult = await client.callKw({
        'model': 'product.template',
        'method': 'search_read',
        'args': [
          domain,
          [
            'id',
            'name',
            'default_code',
            'categ_id',
            'list_price',
            'image_1920',
            'type',
          ],
        ],
        'kwargs': {'offset': offset, 'limit': _pageSize},
        'context': _companyId != null ? {'company_id': _companyId} : {},
      });
      if (templateResult.isEmpty) {
        setState(() {
          _hasMoreData = false;
          _isLoadingMore = false;
        });
        return;
      }
      List<Map<String, dynamic>> newTemplates = [];
      for (var template in templateResult) {
        String? imageUrl;
        final imageData = template['image_1920'];
        if (imageData != false && imageData is String && imageData.isNotEmpty) {
          try {
            final base64String = imageData.replaceAll(RegExp(r'\s+'), '');
            base64Decode(base64String);
            imageUrl = base64String.contains(',')
                ? base64String
                : 'data:image/png;base64,$base64String';
          } catch (e) {
            imageUrl = 'https://dummyimage.com/150x150/000/fff';
          }
        }
        final variants = await _fetchVariantsSafe(
          client,
          template['id'],
          _companyId,
        );

        double qtyAvailable = 0.0;
        double virtualAvailable = 0.0;
        List<Map<String, dynamic>> variantList = [];
        for (var variant in variants) {
          final variantQtyAvailable =
              (variant['qty_available'] as num?)?.toDouble() ?? 0.0;
          final variantVirtualAvailable =
              (variant['virtual_available'] as num?)?.toDouble() ?? 0.0;
          qtyAvailable += variantQtyAvailable;
          virtualAvailable += variantVirtualAvailable;
          String? variantImageUrl = imageUrl;
          final vImageData = variant['image_1920'];
          if (vImageData != false &&
              vImageData is String &&
              vImageData.isNotEmpty) {
            try {
              final base64String = vImageData.replaceAll(RegExp(r'\s+'), '');
              base64Decode(base64String);
              variantImageUrl = base64String.contains(',')
                  ? base64String
                  : 'data:image/png;base64,$base64String';
            } catch (e) {
              variantImageUrl = imageUrl;
            }
          }
          variantList.add({
            'id': variant['id'],
            'name': variant['name'] ?? 'N/A',
            'default_code': variant['default_code'] ?? 'N/A',
            'barcode': variant['barcode'] ?? 'N/A',
            'qty_available': variantQtyAvailable,
            'virtual_available': variantVirtualAvailable,
            'image_url': variantImageUrl,
            'price': (variant['list_price'] as num?)?.toDouble() ?? 0.0,
            'attribute_value_ids':
                variant['product_template_attribute_value_ids'] ?? [],
            'selected_attributes': <String, String>{},
            'type': variant['type'] ?? 'product',
          });
        }
        newTemplates.add({
          'id': template['id'],
          'name': template['name'] ?? 'N/A',
          'default_code': template['default_code'] ?? 'N/A',
          'barcode': '',
          'qty_available': qtyAvailable,
          'virtual_available': virtualAvailable,
          'image_url': imageUrl,
          'price': (template['list_price'] as num?)?.toDouble() ?? 0.0,
          'category': template['categ_id'] is List
              ? template['categ_id'][1] ?? 'N/A'
              : 'N/A',
          'variants': variantList,
          'variant_count': variantList.length,
          'attributes': <Map<String, String>>[],
          'type': template['type'] ?? 'product',
        });
      }
      newTemplates.sort(
        (a, b) => a['name'].toString().toLowerCase().compareTo(
          b['name'].toString().toLowerCase(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _productTemplates.addAll(newTemplates);
        _filteredProductTemplates = _productTemplates;
        _currentPage++;
        _hasMoreData = _productTemplates.length < _totalProducts;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (_isServerUnreachableError(e)) {
        if (mounted) {
          setState(() {
            _isServerUnreachable = true;
            _isLoadingMore = false;
          });
        }
        return;
      } else {
        if (mounted) {
          setState(() {
            _isServerUnreachable = false;
            _isLoadingMore = false;
          });

          CustomSnackbar.showError(
            context,
            'Error loading more products: ${e.toString()}',
          );
        }
      }
    }
  }

  Future<void> _loadStockData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasSearched = false;
      _currentPage = 0;
      _hasMoreData = true;
      _productTemplates = [];
      _filteredProductTemplates = [];
      _searchController.clear();
    });

    try {
      final client = await OdooSessionManager.getClient();
      if (!mounted) return;
      if (client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }
      _sessionId = client.sessionId;

      List<dynamic> domain = [
        ['active', '=', true],
        [
          'type',
          'in',
          ['product', 'consu'],
        ],
      ];

      final templateResult = await client.callKw({
        'model': 'product.template',
        'method': 'search_read',
        'args': [
          domain,
          [
            'id',
            'name',
            'default_code',
            'categ_id',
            'list_price',
            'image_1920',
            'type',
          ],
        ],
        'kwargs': {'offset': 0, 'limit': _pageSize},
        'context': _companyId != null ? {'company_id': _companyId} : {},
      });

      final countResult = await client.callKw({
        'model': 'product.template',
        'method': 'search_count',
        'args': [domain],
        'kwargs': {},
        'context': _companyId != null ? {'company_id': _companyId} : {},
      });
      _totalProducts = countResult as int;

      if (templateResult.isNotEmpty) {
        List<Map<String, dynamic>> newTemplates = [];
        for (var template in templateResult) {
          String? imageUrl;
          final imageData = template['image_1920'];
          if (imageData != false &&
              imageData is String &&
              imageData.isNotEmpty) {
            try {
              final base64String = imageData.replaceAll(RegExp(r'\s+'), '');
              base64Decode(base64String);
              imageUrl = base64String.contains(',')
                  ? base64String
                  : 'data:image/png;base64,$base64String';
            } catch (e) {
              imageUrl = 'https://dummyimage.com/150x150/000/fff';
            }
          }

          final variants = await _fetchVariantsSafe(
            client,
            template['id'],
            _companyId,
          );

          double qtyAvailable = 0.0;
          double virtualAvailable = 0.0;
          List<Map<String, dynamic>> variantList = [];
          for (var variant in variants) {
            final variantQtyAvailable =
                (variant['qty_available'] as num?)?.toDouble() ?? 0.0;
            final variantVirtualAvailable =
                (variant['virtual_available'] as num?)?.toDouble() ?? 0.0;
            qtyAvailable += variantQtyAvailable;
            virtualAvailable += variantVirtualAvailable;
            String? variantImageUrl = imageUrl;
            final vImageData = variant['image_1920'];
            if (vImageData != false &&
                vImageData is String &&
                vImageData.isNotEmpty) {
              try {
                final base64String = vImageData.replaceAll(RegExp(r'\s+'), '');
                base64Decode(base64String);
                variantImageUrl = base64String.contains(',')
                    ? base64String
                    : 'data:image/png;base64,$base64String';
              } catch (e) {
                variantImageUrl = imageUrl;
              }
            }
            variantList.add({
              'id': variant['id'],
              'name': variant['name'] ?? 'N/A',
              'default_code': variant['default_code'] ?? 'N/A',
              'barcode': variant['barcode'] ?? 'N/A',
              'qty_available': variantQtyAvailable,
              'virtual_available': variantVirtualAvailable,
              'image_url': variantImageUrl,
              'price': (variant['list_price'] as num?)?.toDouble() ?? 0.0,
              'attribute_value_ids':
                  variant['product_template_attribute_value_ids'] ?? [],
              'selected_attributes': <String, String>{},
              'type': variant['type'] ?? 'product',
            });
          }

          newTemplates.add({
            'id': template['id'],
            'name': template['name'] ?? 'N/A',
            'default_code': template['default_code'] ?? 'N/A',
            'barcode': '',
            'qty_available': qtyAvailable,
            'virtual_available': virtualAvailable,
            'image_url': imageUrl,
            'price': (template['list_price'] as num?)?.toDouble() ?? 0.0,
            'category': template['categ_id'] is List
                ? template['categ_id'][1] ?? 'N/A'
                : 'N/A',
            'variants': variantList,
            'variant_count': variantList.length,
            'attributes': <Map<String, String>>[],
            'type': template['type'] ?? 'product',
          });
        }
        newTemplates.sort(
          (a, b) => a['name'].toString().toLowerCase().compareTo(
            b['name'].toString().toLowerCase(),
          ),
        );
        if (!mounted) return;
        setState(() {
          _productTemplates = newTemplates;
          _filteredProductTemplates = newTemplates;
          _hasMoreData = _productTemplates.length < _totalProducts;
          _isLoading = false;
        });
      } else {
        setState(() {
          _productTemplates = [];
          _filteredProductTemplates = [];
          _hasMoreData = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (_isServerUnreachableError(e)) {
        if (mounted) {
          setState(() {
            _isServerUnreachable = true;
            _productTemplates = [];
            _filteredProductTemplates = [];
            _hasMoreData = false;
            _isLoading = false;
          });
        }
        return;
      } else {
        if (mounted) {
          setState(() {
            _isServerUnreachable = false;
            _productTemplates = [];
            _filteredProductTemplates = [];
            _hasMoreData = false;
            _isLoading = false;
          });

          CustomSnackbar.showError(
            context,
            'Error loading stock data: ${e.toString()}',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasSearched = true;
        });
      }
    }
  }

  Future<List<dynamic>> _fetchVariantsSafe(
    dynamic client,
    int templateId,
    int? companyId,
  ) async {
    return await FieldValidationService.executeWithFieldValidation<
      List<dynamic>
    >(
      model: 'product.product',
      initialFields: [
        'id',
        'name',
        'default_code',
        'barcode',
        'qty_available',
        'virtual_available',
        'image_1920',
        'list_price',
        'product_template_attribute_value_ids',
        'type',
      ],
      apiCall: (fields) async {
        return await client.callKw({
          'model': 'product.product',
          'method': 'search_read',
          'args': [
            [
              ['product_tmpl_id', '=', templateId],
            ],
            fields,
          ],
          'kwargs': {},
          'context': companyId != null ? {'company_id': companyId} : {},
        });
      },
    );
  }

  Future<void> _scanBarcode() async {
    setState(() => _isScanning = true);
    try {
      final String? barcode = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => BarcodeScannerScreen()),
      );

      if (barcode != null && barcode.isNotEmpty) {
        setState(() {
          _searchController.text = barcode;
        });

        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted && _filteredProductTemplates.isEmpty && !_isSearching) {
          CustomSnackbar.showWarning(
            context,
            'No product found with barcode: $barcode',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(context, 'Error scanning barcode: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<Map<String, dynamic>> _fetchInventory(int productId) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('Failed to get Odoo client');
      }

      final locationResult = await client.callKw({
        'model': 'stock.location',
        'method': 'search_read',
        'args': [[]],
        'kwargs': {
          'fields': ['id', 'complete_name', 'usage'],
        },
        'context': _companyId != null ? {'company_id': _companyId} : {},
      });

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

      final stockQuantResult = await client.callKw({
        'model': 'stock.quant',
        'method': 'search_read',
        'args': [
          [
            ['product_id', '=', productId],
          ],
        ],
        'kwargs': {
          'fields': ['location_id', 'quantity', 'reserved_quantity'],
        },
        'context': _companyId != null ? {'company_id': _companyId} : {},
      });

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

        if (usage == 'unknown') {
          try {
            final specificLocationResult = await client.callKw({
              'model': 'stock.location',
              'method': 'search_read',
              'args': [
                [
                  ['id', '=', locationId],
                ],
              ],
              'kwargs': {
                'fields': ['usage', 'complete_name', 'location_id'],
              },
              'context': _companyId != null ? {'company_id': _companyId} : {},
            });

            if (specificLocationResult.isNotEmpty) {
              usage =
                  specificLocationResult[0]['usage'] as String? ?? 'unknown';
              locationUsageMap[locationName] = usage;

              if (usage == 'unknown') {
                final parentLocationId =
                    specificLocationResult[0]['location_id'];
                if (parentLocationId is List && parentLocationId.isNotEmpty) {
                  final parentName = parentLocationId[1] as String;

                  if (internalLocations.contains(parentName)) {
                    usage = 'internal';
                    shouldCountInTotals = true;
                  }
                }
              }
            }
          } catch (e) {}
        }

        final isInternal = usage == 'internal';

        shouldCountInTotals = isInternal;

        if (usage == 'unknown') {
          final locationNameLower = locationName.toLowerCase();

          if (locationNameLower.contains('stock')) {
            shouldCountInTotals = true;
          } else if (locationNameLower.contains('warehouse') ||
              locationNameLower.contains('wh/')) {
            shouldCountInTotals = true;
          } else if (locationNameLower.contains('customer') ||
              locationNameLower.contains('supplier') ||
              locationNameLower.contains('vendor')) {
          } else {}
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

        if (!shouldCountInTotals) {
          final countStatus = shouldCountInTotals ? 'counted' : 'not counted';
        }
      }

      final productResult = await client.callKw({
        'model': 'product.product',
        'method': 'read',
        'args': [
          [productId],
        ],
        'kwargs': {
          'fields': ['qty_available', 'virtual_available'],
        },
        'context': _companyId != null ? {'company_id': _companyId} : {},
      });

      final expectedStock = productResult.isNotEmpty
          ? (productResult[0]['qty_available'] as num?)?.toDouble() ?? 0.0
          : 0.0;
      final expectedVirtual = productResult.isNotEmpty
          ? (productResult[0]['virtual_available'] as num?)?.toDouble() ?? 0.0
          : 0.0;

      final totalInStock = expectedStock;
      final forecastedStock = expectedVirtual;

      final stockDifference = expectedStock - quantTotalInStock;
      if (stockDifference != 0) {
        if (stockDifference.abs() > 0.1) {
          for (var stock in stockDetails) {
            if (stock['is_counted_in_totals'] == false &&
                stock['location_type'] == 'unknown') {
              final stockQuantity =
                  (stock['quantity'] as num?)?.toDouble() ?? 0.0;
            }
          }
        }
      } else {}

      final incomingMoveResult = await client.callKw({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [
          [
            ['product_id', '=', productId],
            [
              'state',
              'in',
              ['confirmed', 'waiting', 'assigned', 'partially_available'],
            ],
            ['location_dest_id.usage', '=', 'internal'],
            ['location_id.usage', '!=', 'internal'],
          ],
        ],
        'kwargs': {
          'fields': [
            'id',
            'product_uom_qty',
            'move_line_ids',
            'quantity',
            'date',
            'location_id',
            'location_dest_id',
            'state',
          ],
        },
        'context': _companyId != null ? {'company_id': _companyId} : {},
      });

      final outgoingMoveResult = await client.callKw({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [
          [
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
        ],
        'kwargs': {
          'fields': [
            'id',
            'product_uom_qty',
            'move_line_ids',
            'quantity',
            'date',
            'location_id',
            'location_dest_id',
            'state',
          ],
        },
        'context': _companyId != null ? {'company_id': _companyId} : {},
      });

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
        final moveLineResult = await client.callKw({
          'model': 'stock.move.line',
          'method': 'search_read',
          'args': [
            [
              ['id', 'in', allMoveLineIds],
            ],
            ['id', 'move_id', 'quantity'],
          ],
          'kwargs': {},
          'context': _companyId != null ? {'company_id': _companyId} : {},
        });
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

  Future<void> _performSearch(String searchQuery) async {
    if (!mounted) return;

    _currentSearchQuery = searchQuery.toLowerCase();

    if (searchQuery.isEmpty) {
      setState(() {
        _filteredProductTemplates = List.from(_productTemplates);
        _isSearching = false;
      });
      return;
    }

    final clientSideResults = _performClientSideSearch(
      searchQuery,
      _productTemplates,
    );

    if (clientSideResults.isNotEmpty) {
      setState(() {
        _filteredProductTemplates = clientSideResults;
        _isSearching = false;
      });
    } else if (searchQuery.length >= 2) {
      await _performServerSearch(searchQuery);
    } else {
      setState(() {
        _filteredProductTemplates = [];
        _isSearching = false;
      });
    }
  }

  List<Map<String, dynamic>> _performClientSideSearch(
    String query,
    List<Map<String, dynamic>> products,
  ) {
    if (query.isEmpty || query.length < 2) {
      return products;
    }

    final lowerQuery = query.toLowerCase();
    return products.where((product) {
      final name = (product['name'] ?? '').toString().toLowerCase();
      final defaultCode = (product['default_code'] ?? '')
          .toString()
          .toLowerCase();
      final category = (product['category'] ?? '').toString().toLowerCase();

      final variants = product['variants'] as List<Map<String, dynamic>>? ?? [];
      final hasVariantMatch = variants.any((variant) {
        final variantName = (variant['name'] ?? '').toString().toLowerCase();
        final variantCode = (variant['default_code'] ?? '')
            .toString()
            .toLowerCase();
        final barcode = (variant['barcode'] ?? '').toString().toLowerCase();

        return variantName.contains(lowerQuery) ||
            variantCode.contains(lowerQuery) ||
            barcode.contains(lowerQuery);
      });

      return name.contains(lowerQuery) ||
          defaultCode.contains(lowerQuery) ||
          category.contains(lowerQuery) ||
          hasVariantMatch;
    }).toList();
  }

  Future<void> _performServerSearch(String searchQuery) async {
    if (!mounted) return;

    setState(() {
      _isSearching = true;
    });

    try {
      final client = await OdooSessionManager.getClient();
      if (!mounted || client == null) {
        throw Exception('No active Odoo session found. Please log in again.');
      }

      List<dynamic> domain = [
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
        ['name', 'ilike', searchQuery],
        ['default_code', 'ilike', searchQuery],
        ['categ_id.name', 'ilike', searchQuery],
        ['barcode', 'ilike', searchQuery],
      ];
      final templateResult = await client.callKw({
        'model': 'product.template',
        'method': 'search_read',
        'args': [
          domain,
          [
            'id',
            'name',
            'default_code',
            'categ_id',
            'list_price',
            'image_1920',
            'type',
          ],
        ],
        'kwargs': {'offset': 0, 'limit': _pageSize},
        'context': _companyId != null ? {'company_id': _companyId} : {},
      });

      final countResult = await client.callKw({
        'model': 'product.template',
        'method': 'search_count',
        'args': [domain],
        'kwargs': {},
        'context': _companyId != null ? {'company_id': _companyId} : {},
      });

      _totalProducts = countResult as int;

      if (templateResult.isNotEmpty) {
        List<Map<String, dynamic>> newTemplates = [];
        for (var template in templateResult) {
          String? imageUrl;
          final imageData = template['image_1920'];
          if (imageData != false &&
              imageData is String &&
              imageData.isNotEmpty) {
            try {
              final base64String = imageData.replaceAll(RegExp(r'\s+'), '');
              base64Decode(base64String);
              imageUrl = base64String.contains(',')
                  ? base64String
                  : 'data:image/png;base64,$base64String';
            } catch (e) {
              imageUrl = 'https://dummyimage.com/150x150/000/fff';
            }
          }
          final variants = await client.callKw({
            'model': 'product.product',
            'method': 'search_read',
            'args': [
              [
                ['product_tmpl_id', '=', template['id']],
              ],
              [
                'id',
                'name',
                'default_code',
                'barcode',
                'qty_available',
                'virtual_available',
                'image_1920',
                'list_price',
                'product_template_attribute_value_ids',
                'type',
              ],
            ],
            'kwargs': {},
            'context': _companyId != null ? {'company_id': _companyId} : {},
          });
          double qtyAvailable = 0.0;
          double virtualAvailable = 0.0;
          List<Map<String, dynamic>> variantList = [];
          for (var variant in variants) {
            final variantQtyAvailable =
                (variant['qty_available'] as num?)?.toDouble() ?? 0.0;
            final variantVirtualAvailable =
                (variant['virtual_available'] as num?)?.toDouble() ?? 0.0;
            qtyAvailable += variantQtyAvailable;
            virtualAvailable += variantVirtualAvailable;
            String? variantImageUrl = imageUrl;
            final vImageData = variant['image_1920'];
            if (vImageData != false &&
                vImageData is String &&
                vImageData.isNotEmpty) {
              try {
                final base64String = vImageData.replaceAll(RegExp(r'\s+'), '');
                base64Decode(base64String);
                variantImageUrl = base64String.contains(',')
                    ? base64String
                    : 'data:image/png;base64,$base64String';
              } catch (e) {
                variantImageUrl = imageUrl;
              }
            }
            variantList.add({
              'id': variant['id'],
              'name': variant['name'] ?? 'N/A',
              'default_code': variant['default_code'] ?? 'N/A',
              'barcode': variant['barcode'] ?? 'N/A',
              'qty_available': variantQtyAvailable,
              'virtual_available': variantVirtualAvailable,
              'image_url': variantImageUrl,
              'price': (variant['list_price'] as num?)?.toDouble() ?? 0.0,
              'attribute_value_ids':
                  variant['product_template_attribute_value_ids'] ?? [],
              'selected_attributes': <String, String>{},
              'type': variant['type'] ?? 'product',
            });
          }
          newTemplates.add({
            'id': template['id'],
            'name': template['name'] ?? 'N/A',
            'default_code': template['default_code'] ?? 'N/A',
            'barcode': '',
            'qty_available': qtyAvailable,
            'virtual_available': virtualAvailable,
            'image_url': imageUrl,
            'price': (template['list_price'] as num?)?.toDouble() ?? 0.0,
            'category': template['categ_id'] is List
                ? template['categ_id'][1] ?? 'N/A'
                : 'N/A',
            'variants': variantList,
            'variant_count': variantList.length,
            'attributes': <Map<String, String>>[],
            'type': template['type'] ?? 'product',
          });
        }
        newTemplates.sort(
          (a, b) => a['name'].toString().toLowerCase().compareTo(
            b['name'].toString().toLowerCase(),
          ),
        );
        if (!mounted) return;
        setState(() {
          _filteredProductTemplates = newTemplates;
          _currentPage = 1;
          _hasMoreData = newTemplates.length < _totalProducts;
          _isSearching = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _filteredProductTemplates = [];
          _hasMoreData = false;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (_isServerUnreachableError(e)) {
        if (mounted) {
          setState(() {
            _isServerUnreachable = true;
            _filteredProductTemplates = [];
            _hasMoreData = false;
            _isSearching = false;
          });
        }
        return;
      } else {
        if (mounted) {
          setState(() {
            _isServerUnreachable = false;
            _filteredProductTemplates = [];
            _hasMoreData = false;
            _isSearching = false;
          });

          CustomSnackbar.showError(
            context,
            'Error searching products: ${e.toString()}',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasSearched = true;
        });
      }
    }
  }

  static final Map<String, List<Map<String, String>>> _attributeCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheDuration = Duration(minutes: 30);

  static void clearCache() {
    _attributeCache.clear();
    _cacheTimestamps.clear();
  }

  Future<List<Map<String, String>>> _fetchVariantAttributes(
    OdooClient odooClient,
    List<int> attributeValueIds,
  ) async {
    if (attributeValueIds.isEmpty) return [];

    try {
      final cacheKey = attributeValueIds.join(',');
      final now = DateTime.now();
      if (_attributeCache.containsKey(cacheKey) &&
          _cacheTimestamps.containsKey(cacheKey) &&
          now.difference(_cacheTimestamps[cacheKey]!) < _cacheDuration) {
        return _attributeCache[cacheKey]!;
      }

      final attributeValueResult = await odooClient.callKw({
        'model': 'product.template.attribute.value',
        'method': 'read',
        'args': [attributeValueIds],
        'kwargs': {
          'fields': ['product_attribute_value_id', 'attribute_id'],
        },
      });

      if (attributeValueResult.isEmpty) return [];

      final valueIds = <int>[];
      final attributeIds = <int>[];
      final valueToAttributeMap = <int, int>{};

      for (var attrValue in attributeValueResult) {
        final valueId = attrValue['product_attribute_value_id'] is List
            ? attrValue['product_attribute_value_id'][0] as int
            : attrValue['product_attribute_value_id'] as int;
        final attributeId = attrValue['attribute_id'] is List
            ? attrValue['attribute_id'][0] as int
            : attrValue['attribute_id'] as int;
        valueIds.add(valueId);
        attributeIds.add(attributeId);
        valueToAttributeMap[valueId] = attributeId;
      }

      final valueData = await odooClient.callKw({
        'model': 'product.attribute.value',
        'method': 'read',
        'args': [valueIds],
        'kwargs': {
          'fields': ['name'],
        },
      });

      final attributeData = await odooClient.callKw({
        'model': 'product.attribute',
        'method': 'read',
        'args': [attributeIds.toSet().toList()],
        'kwargs': {
          'fields': ['name'],
        },
      });

      final valueMap = <int, String>{};
      for (var value in valueData) {
        valueMap[value['id'] as int] = value['name'] as String;
      }

      final attributeMap = <int, String>{};
      for (var attr in attributeData) {
        attributeMap[attr['id'] as int] = attr['name'] as String;
      }

      final attributes = <Map<String, String>>[];
      for (var attrValue in attributeValueResult) {
        final valueId = attrValue['product_attribute_value_id'] is List
            ? attrValue['product_attribute_value_id'][0] as int
            : attrValue['product_attribute_value_id'] as int;
        final attributeId = attrValue['attribute_id'] is List
            ? attrValue['attribute_id'][0] as int
            : attrValue['attribute_id'] as int;

        final valueName = valueMap[valueId];
        final attributeName = attributeMap[attributeId];

        if (valueName != null && attributeName != null) {
          attributes.add({
            'attribute_name': attributeName,
            'value_name': valueName,
          });
        }
      }

      _attributeCache[cacheKey] = attributes;
      _cacheTimestamps[cacheKey] = now;

      return attributes;
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, String>>> _fetchVariantAttributesForBottomSheet(
    Map<String, dynamic> variant,
  ) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return [];

      final attributeValueIds =
          (variant['attribute_value_ids'] as List?)
              ?.map((dynamic id) => id as int)
              .toList() ??
          [];

      if (attributeValueIds.isEmpty) return [];

      return await _fetchVariantAttributes(client, attributeValueIds);
    } catch (e) {
      return [];
    }
  }

  Future<void> _showVariantsDialog(
    BuildContext context,
    Map<String, dynamic> template,
  ) async {
    final variants = (template['variants'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .toList();
    if (variants.isEmpty) return;

    final deviceSize = MediaQuery.of(context).size;
    final dialogHeight = deviceSize.height * 0.75;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final maxListHeight = MediaQuery.of(dialogContext).size.height * 0.6;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 8,
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: dialogHeight,
              minHeight: 300,
              maxWidth: MediaQuery.of(context).size.width - 32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Stock Variants',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              template["name"] ?? 'Unknown Product',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: maxListHeight,
                      minHeight: 200,
                    ),
                    child:
                        FutureBuilder<
                          List<
                            Map<Map<String, dynamic>, List<Map<String, String>>>
                          >
                        >(
                          future: Future.wait(
                            variants.map((variant) async {
                              final client =
                                  await OdooSessionManager.getClient();
                              if (client == null) return {variant: []};
                              final attributeValueIds =
                                  (variant['attribute_value_ids'] as List?)
                                      ?.map((dynamic id) => id as int)
                                      .toList() ??
                                  [];
                              final attributes = await _fetchVariantAttributes(
                                client,
                                attributeValueIds,
                              );
                              return {variant: attributes};
                            }),
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const VariantsDialogShimmer();
                            }
                            if (snapshot.hasError) {
                              return const Center(
                                child: Text('Error loading variants'),
                              );
                            }
                            final variantAttributes = snapshot.data ?? [];
                            final uniqueVariants =
                                <
                                  String,
                                  Map<
                                    Map<String, dynamic>,
                                    List<Map<String, String>>
                                  >
                                >{};
                            for (var entry in variantAttributes) {
                              final variant = entry.keys.first;
                              final attrs = entry.values.first;
                              final key =
                                  '${variant['default_code'] ?? variant['id']}_${attrs.map((a) => '${a['attribute_name']}:${a['value_name']}').join('|')}';
                              uniqueVariants[key] = entry;
                            }

                            return ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              shrinkWrap: true,
                              itemCount: uniqueVariants.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                thickness: 0.5,
                                indent: 16,
                                endIndent: 16,
                                color: isDark
                                    ? Colors.grey[700]
                                    : Colors.grey[300],
                              ),
                              itemBuilder: (context, index) {
                                final entry = uniqueVariants.values.elementAt(
                                  index,
                                );
                                final variant = entry.keys.first;
                                final attributes = entry.values.first;
                                return _buildVariantListItem(
                                  variant: variant,
                                  dialogContext: dialogContext,
                                  template: template,
                                  attributes: attributes,
                                  selectedAttributes: {},
                                  isDark: isDark,
                                );
                              },
                            );
                          },
                        ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVariantListItem({
    required Map<String, dynamic> variant,
    required BuildContext dialogContext,
    required Map<String, dynamic> template,
    required List<Map<String, String>> attributes,
    required Map<String, String>? selectedAttributes,
    bool isDark = false,
  }) {
    final imageUrl = variant['image_url'] ?? template['image_url'] as String?;
    Uint8List? imageBytes;
    if (imageUrl != null &&
        imageUrl.isNotEmpty &&
        !imageUrl.startsWith('http')) {
      try {
        final base64String = imageUrl.contains(',')
            ? imageUrl.split(',')[1]
            : imageUrl;
        if (RegExp(r'^[a-zA-Z0-9+/]*={0,2}$').hasMatch(base64String)) {
          imageBytes = base64Decode(base64String);
        }
      } catch (e) {}
    }

    return ProductListTile(
      id: variant['id'].toString(),
      name: variant['name'].split(' [').first,
      defaultCode:
          (variant['default_code'] is bool || variant['default_code'] == null)
          ? null
          : variant['default_code'].toString(),
      listPrice: (variant['price'] ?? 0).toDouble(),
      currencyId: null,
      category: template['category']?.toString(),
      qtyAvailable: ((variant['qty_available'] as num?)?.toDouble() ?? 0.0)
          .toDouble(),
      imageUrl: variant['image_url'] ?? template['image_url'] as String?,
      imageBytes: imageBytes,
      variantCount: 1,
      isDark: isDark,
      attributes: attributes.isNotEmpty ? attributes : null,
      actionButtons: null,
      onTap: () async {
        Navigator.of(dialogContext).pop();
        await _showInventoryDetailsBottomSheet(context, variant);
      },
      popupMenu: attributes.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Tooltip(
                message: attributes
                    .map(
                      (attr) =>
                          '${attr['attribute_name']}: ${attr['value_name']}',
                    )
                    .join('\n'),
                child: Icon(
                  HugeIcons.strokeRoundedTags,
                  size: 18,
                  color: isDark ? Colors.grey[300] : Colors.deepPurple,
                ),
              ),
            )
          : null,
    );
  }

  List<String> nameParts(String name) {
    final parts = name.split(' [');
    if (parts.length > 1) {
      return [parts[0], parts[1].replaceAll(']', '')];
    }
    return [name, ''];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.grey[850] : Colors.white;
    final borderColor = isDark ? Colors.grey[800]! : Colors.grey[200]!;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[300] : Colors.grey[700];
    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Stock Check',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        foregroundColor: isDark ? Colors.white : Theme.of(context).primaryColor,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
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
                            hintText: 'Search by name, code or barcode',
                            hintStyle: TextStyle(
                              color: isDark ? Colors.white : Color(0xff1E1E1E),
                              fontWeight: FontWeight.w400,
                              fontStyle: FontStyle.normal,
                              fontSize: 15,
                              height: 1.0,
                              letterSpacing: 0.0,
                            ),
                            prefixIcon: Icon(
                              HugeIcons.strokeRoundedSearchList02,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Color(0xff9EA2AE),
                              size: 18,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      Icons.clear,
                                      color: isDark
                                          ? Colors.grey[400]
                                          : Colors.grey,
                                    ),
                                    onPressed: () {
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
                              borderSide: BorderSide(
                                color: AppTheme.primaryColor,
                                width: 1,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            isDense: true,

                            alignLabelWithHint: true,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[850] : Colors.white,
                        shape: BoxShape.circle,

                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF000000).withOpacity(0.05),
                            offset: Offset(0, 6),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: _isScanning
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.primaryColor,
                                ),
                              )
                            : Icon(
                                HugeIcons.strokeRoundedCameraAi,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                        onPressed: _isScanning ? null : _scanBarcode,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Consumer2<ConnectivityService, SessionService>(
                  builder: (context, connectivityService, sessionService, child) {
                    if (!connectivityService.isConnected) {
                      return ConnectionStatusWidget(
                        onRetry: () {
                          if (connectivityService.isConnected) {
                            _initializeAndLoadStock();
                          }
                        },
                        customMessage:
                            'No internet connection. Please check your network and try again.',
                      );
                    }

                    if (!sessionService.hasValidSession) {
                      return ConnectionStatusWidget(
                        serverUnreachable: true,
                        onRetry: () {
                          if (sessionService.hasValidSession) {
                            _initializeAndLoadStock();
                          }
                        },
                        customMessage:
                            'Your session has expired. Please log in again to continue.',
                      );
                    }

                    if (_isServerUnreachable) {
                      return ConnectionStatusWidget(
                        serverUnreachable: true,
                        serverErrorMessage:
                            'Cannot connect to Odoo server. Please check your server configuration or try again later.',
                        onRetry: () {
                          setState(() {
                            _isServerUnreachable = false;
                          });
                          _initializeAndLoadStock();
                        },
                      );
                    }

                    if (_isLoading &&
                        connectivityService.isConnected &&
                        sessionService.hasValidSession) {
                      return ListShimmer.buildListShimmer(
                        context,
                        itemCount: 8,
                        type: ShimmerType.product,
                      );
                    }

                    if (_filteredProductTemplates.isEmpty && _hasSearched) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 64,
                              color: isDark
                                  ? Colors.grey[700]
                                  : Colors.grey[400],
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No products found',
                              style: TextStyle(
                                fontSize: 18,
                                color: subtitleColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: () async {
                        setState(() => _isLoading = true);
                        await _loadStockData();
                      },
                      child: ListView.builder(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: _filteredProductTemplates.length + 1,
                        itemBuilder: (context, index) {
                          if (index == _filteredProductTemplates.length) {
                            if (_isLoadingMore) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            } else if (!_hasMoreData) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    'All products are loaded',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: subtitleColor,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          }
                          final template = _filteredProductTemplates[index];

                          final variants = template['variants'] as List;

                          for (var v in variants) {}
                          return GestureDetector(
                            onTap: () async {
                              setState(() => _isActionLoading = true);
                              if ((template['variants'] as List).length > 1) {
                                await _showVariantsDialog(context, template);
                              } else {
                                final variant = template['variants'][0];
                                await _showInventoryDetailsBottomSheet(
                                  context,
                                  variant,
                                );
                              }
                              setState(() => _isActionLoading = false);
                            },
                            child: _buildProductCard(
                              template,
                              cardColor!,
                              borderColor,
                              textColor,
                              subtitleColor!,
                              isDark,
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showInventoryDetailsBottomSheet(
    BuildContext context,
    Map<String, dynamic> variant,
  ) async {
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    final handleColor = isDark
        ? colorScheme.onSurface.withOpacity(0.2)
        : Colors.grey[300];
    final subtitleTextColor = isDark
        ? colorScheme.onSurface.withOpacity(0.7)
        : Colors.grey[600];
    final iconBgColor = isDark
        ? colorScheme.primaryContainer
        : AppTheme.primaryColor.withOpacity(0.1);
    final iconColor = isDark
        ? colorScheme.onPrimaryContainer
        : AppTheme.primaryColor;
    final closeIconBg = isDark
        ? colorScheme.surfaceContainerHighest.withOpacity(0.3)
        : Colors.grey[100];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[900] : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: handleColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.grey[800]
                                  : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              HugeIcons.strokeRoundedPackage,
                              color: isDark ? Colors.white : Colors.black,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Inventory Details',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                FutureBuilder<List<Map<String, String>>>(
                                  future: _fetchVariantAttributesForBottomSheet(
                                    variant,
                                  ),
                                  builder: (context, snapshot) {
                                    final hasSku =
                                        variant["default_code"] != null &&
                                        variant["default_code"] is String &&
                                        variant["default_code"]
                                            .toString()
                                            .trim()
                                            .isNotEmpty &&
                                        variant["default_code"] != 'false';

                                    final attributes = snapshot.data ?? [];
                                    final hasAttributes = attributes.isNotEmpty;

                                    String displayText =
                                        variant["name"] ?? 'Unknown Variant';

                                    if (hasSku && hasAttributes) {
                                      displayText +=
                                          ' (SKU: ${variant["default_code"]})';
                                      displayText +=
                                          ' • ${attributes.map((attr) => '${attr['attribute_name']}: ${attr['value_name']}').join(', ')}';
                                    } else if (hasSku) {
                                      displayText +=
                                          ' (SKU: ${variant["default_code"]})';
                                    } else if (hasAttributes) {
                                      displayText +=
                                          ' • ${attributes.map((attr) => '${attr['attribute_name']}: ${attr['value_name']}').join(', ')}';
                                    }

                                    return Text(
                                      displayText,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          Material(
                            color: isDark
                                ? Colors.white.withOpacity(.1)
                                : Colors.grey.withOpacity(.1),
                            borderRadius: BorderRadius.circular(8),
                            child: IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: Icon(
                                HugeIcons.strokeRoundedCancelCircleHalfDot,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                              tooltip: 'Close',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: isDark
                    ? Colors.white.withOpacity(.5)
                    : Colors.black.withOpacity(.5),
              ),
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: _fetchInventory(variant['id']),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return _buildLoadingState(isDark: isDark);
                    }
                    if (snapshot.hasError) {
                      return _buildErrorState(
                        snapshot.error.toString(),
                        isDark: isDark,
                      );
                    }

                    return SingleChildScrollView(
                      controller: scrollController,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: _buildInventoryContent(
                          variant: variant,
                          inventoryDetails: snapshot.data!,
                          isDark: isDark,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState({bool isDark = false}) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Shimmer.fromColors(
            baseColor: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            highlightColor: isDark ? Colors.grey[600]! : Colors.grey[200]!,
            child: Column(
              children: [
                _buildShimmerCard(height: 120, isDark: isDark),
                const SizedBox(height: 16),
                _buildShimmerCard(height: 80, isDark: isDark),
                const SizedBox(height: 16),
                _buildShimmerCard(height: 100, isDark: isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerCard({required double height, bool isDark = false}) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _buildErrorState(String error, {bool isDark = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.error_outline,
                size: 48,
                color: isDark ? Colors.red[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Unable to load inventory',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.red[400] : Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(
                color: isDark ? Colors.red[400] : Colors.grey[600],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryContent({
    required Map<String, dynamic> variant,
    required Map<String, dynamic> inventoryDetails,
    bool isDark = false,
  }) {
    final stockDetails =
        inventoryDetails['stock_details'] as List<Map<String, dynamic>>;
    final incomingStock =
        inventoryDetails['incoming_stock'] as List<Map<String, dynamic>>;
    final outgoingStock =
        inventoryDetails['outgoing_stock'] as List<Map<String, dynamic>>;

    final totalInStock = inventoryDetails['totalInStock'] as double;
    final totalReserved = inventoryDetails['totalReserved'] as double;
    final totalIncoming = inventoryDetails['totalIncoming'] as double;
    final totalOutgoing = inventoryDetails['totalOutgoing'] as double;
    final forecastedStock = inventoryDetails['forecastedStock'] as double;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStockOverview(
          context: context,
          totalInStock: totalInStock,
          totalReserved: totalReserved,
          forecastedStock: forecastedStock,
          totalIncoming: totalIncoming,
          totalOutgoing: totalOutgoing,
        ),
        const SizedBox(height: 16),
        _buildStockCalculationExplanation(context, stockDetails),
        const SizedBox(height: 24),
        if (stockDetails.isNotEmpty) ...[
          _buildSectionHeader(
            context,
            "Stock Locations",
            HugeIcons.strokeRoundedWarehouse,
          ),
          const SizedBox(height: 12),
          _buildStockLocationsCard(context, stockDetails),
          const SizedBox(height: 24),
        ],
        if (incomingStock.isNotEmpty) ...[
          _buildSectionHeader(
            context,
            "Incoming Shipments",
            HugeIcons.strokeRoundedShippingLoading,
          ),
          const SizedBox(height: 12),
          _buildShipmentsCard(context, incomingStock, isIncoming: true),
          const SizedBox(height: 24),
        ],
        if (outgoingStock.isNotEmpty) ...[
          _buildSectionHeader(
            context,
            'Outgoing Shipments',
            HugeIcons.strokeRoundedShippingCenter,
          ),
          const SizedBox(height: 12),
          _buildShipmentsCard(context, outgoingStock, isIncoming: false),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildStockOverview({
    required BuildContext context,
    required double totalInStock,
    required double totalReserved,
    required double forecastedStock,
    required double totalIncoming,
    required double totalOutgoing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                HugeIcons.strokeRoundedAnalyticsUp,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Stock Overview',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[200] : Colors.grey[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  context: context,
                  label: 'On Hand',
                  value: totalInStock.toStringAsFixed(1),
                  color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
                  icon: HugeIcons.strokeRoundedPackaging,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  context: context,
                  label: 'Reserved',
                  value: totalReserved.toStringAsFixed(1),
                  color: isDark ? Colors.grey[500]! : Colors.grey[700]!,
                  icon: HugeIcons.strokeRoundedCircleLockCheck02,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  context: context,
                  label: 'Forecasted',
                  value: forecastedStock.toStringAsFixed(1),
                  color: isDark ? Colors.grey[300]! : Colors.grey[800]!,
                  icon: HugeIcons.strokeRoundedPackageProcess,
                  isDark: isDark,
                ),
              ),
            ],
          ),
          if (totalIncoming > 0 || totalOutgoing > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (totalIncoming > 0) ...[
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[800] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? Colors.grey[600]! : Colors.grey[400]!,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            HugeIcons.strokeRoundedCircleArrowDownLeft,
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${totalIncoming.toStringAsFixed(1)} incoming',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.grey[300]
                                  : Colors.grey[700],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (totalOutgoing > 0) const SizedBox(width: 8),
                ],
                if (totalOutgoing > 0) ...[
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[800] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? Colors.grey[600]! : Colors.grey[500]!,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            HugeIcons.strokeRoundedCircleArrowUpRight,
                            color: isDark ? Colors.grey[400] : Colors.grey[800],
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${totalOutgoing.toStringAsFixed(1)} outgoing',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[800],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required BuildContext context,
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            size: 20,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.grey[200] : Colors.grey[800],
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, color: isDark ? Colors.white : Colors.grey[700], size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.grey[800],
          ),
        ),
      ],
    );
  }

  Widget _buildStockLocationsCard(
    BuildContext context,
    List<Map<String, dynamic>> stockDetails,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900]! : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        children: stockDetails.asMap().entries.map((entry) {
          final index = entry.key;
          final stock = entry.value;
          final isLast = index == stockDetails.length - 1;
          final isExternal = stock['is_external'] == true;
          final locationType = stock['location_type'] ?? 'unknown';
          final isCounted = stock['is_counted_in_totals'] == true;

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? (isExternal ? Colors.grey[850] : Colors.grey[900]!)
                  : (isExternal ? Colors.orange[25] : null),
              border: isLast
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: isDark
                            ? Colors.grey[800]!
                            : (isExternal
                                  ? Colors.orange[100]!
                                  : Colors.grey[100]!),
                      ),
                    ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? (isExternal ? Colors.grey[800] : Colors.grey[900]!)
                        : (isExternal ? Colors.orange[100] : Colors.grey[100]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isExternal
                        ? HugeIcons.strokeRoundedLocation01
                        : HugeIcons.strokeRoundedBuilding01,
                    color: isDark
                        ? Colors.white
                        : (isExternal ? Colors.orange[700] : Colors.grey[600]),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stock['warehouse'] ?? 'Unknown Location',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isDark
                              ? Colors.white
                              : (isExternal
                                    ? Colors.orange[800]
                                    : Colors.grey[800]),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            'Reserved: ${(stock['reserved_quantity'] as num?)?.toStringAsFixed(1) ?? '0'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.grey[900]!
                                  : (isExternal
                                        ? Colors.orange[100]
                                        : Colors.green[100]),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isExternal ? locationType : 'internal',
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark
                                    ? Colors.white
                                    : (isExternal
                                          ? Colors.orange[700]
                                          : Colors.green[700]),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? (isCounted
                                        ? Colors.grey[900]!
                                        : Colors.grey[800]!)
                                  : (isCounted
                                        ? Colors.green[100]
                                        : Colors.orange[100]),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              isCounted ? 'counted' : 'not counted',
                              style: TextStyle(
                                fontSize: 9,
                                color: isDark
                                    ? Colors.white
                                    : (isCounted
                                          ? Colors.green[700]
                                          : Colors.orange[700]),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      (stock['available'] as num?)?.toStringAsFixed(1) ?? '0',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? Colors.white
                            : (((stock['available'] as num?)?.toDouble() ?? 0) >
                                      0
                                  ? Colors.green[700]
                                  : Colors.red[700]),
                      ),
                    ),
                    Text(
                      'of ${(stock['quantity'] as num?)?.toStringAsFixed(1) ?? '0'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildShipmentsCard(
    BuildContext context,
    List<Map<String, dynamic>> shipments, {
    required bool isIncoming,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isIncoming ? Colors.blue : Colors.red;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900]! : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        children: shipments.asMap().entries.map((entry) {
          final index = entry.key;
          final shipment = entry.value;
          final isLast = index == shipments.length - 1;

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.grey[800]! : Colors.grey[100]!,
                      ),
                    ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[900]! : color[50],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${(shipment['quantity'] as num?)?.toStringAsFixed(1) ?? '0'} items',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : color[800],
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatDate(
                        shipment[isIncoming
                            ? 'expected_date'
                            : 'date_expected'],
                      ),
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildLocationChip(
                        label: 'From',
                        location: shipment['from_location'] ?? 'Unknown',
                        icon: Icons.arrow_circle_right_outlined,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildLocationChip(
                        label: 'To',
                        location: shipment['to_location'] ?? 'Unknown',
                        icon: HugeIcons.strokeRoundedLocation05,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLocationChip({
    required String label,
    required String location,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900]! : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: isDark ? Colors.white : Colors.grey[600]),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.grey[400] : Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  location,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? date) {
    if (date == null || date == 'N/A') return 'Not specified';
    try {
      final parsedDate = DateTime.parse(date);
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return "${parsedDate.day} ${months[parsedDate.month - 1]} ${parsedDate.year}";
    } catch (e) {
      return date ?? 'Invalid date';
    }
  }

  Widget _buildStockCalculationExplanation(
    BuildContext context,
    List<Map<String, dynamic>> stockDetails,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final internalLocations = stockDetails
        .where((s) => s['is_counted_in_totals'] == true)
        .toList();
    final externalLocations = stockDetails
        .where((s) => s['is_counted_in_totals'] == false)
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[600]! : Colors.grey[400]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                HugeIcons.strokeRoundedInformationCircle,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Stock Calculation Info',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[200] : Colors.grey[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Stock totals include only internal warehouse locations. External locations (customer, supplier, etc.) are shown for reference but not counted in totals.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              height: 1.4,
            ),
          ),
          if (internalLocations.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Internal locations (${internalLocations.length}): ${internalLocations.map((s) => s['warehouse']).join(', ')}',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (externalLocations.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'External locations (${externalLocations.length}): ${externalLocations.map((s) => '${s['warehouse']} (${s['location_type']})').join(', ')}',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class VariantsDialogShimmer extends StatelessWidget {
  const VariantsDialogShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
      shrinkWrap: true,
      itemCount: 4,

      itemBuilder: (context, index) =>
          _buildVariantListItemShimmer(isDark: isDark),
    );
  }

  Widget _buildVariantListItemShimmer({required bool isDark}) {
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[600]! : Colors.grey[100]!;

    return Card(
      color: isDark ? Colors.grey[900] : Colors.white,
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Shimmer.fromColors(
              baseColor: baseColor,
              highlightColor: highlightColor,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!, width: 1),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Shimmer.fromColors(
                    baseColor: baseColor,
                    highlightColor: highlightColor,
                    child: Container(
                      width: double.infinity,
                      height: 15,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Shimmer.fromColors(
                    baseColor: baseColor,
                    highlightColor: highlightColor,
                    child: Container(
                      width: 150,
                      height: 12,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Shimmer.fromColors(
                        baseColor: baseColor,
                        highlightColor: highlightColor,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey[900]!
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          width: 80,
                          height: 16,
                        ),
                      ),
                      Shimmer.fromColors(
                        baseColor: baseColor,
                        highlightColor: highlightColor,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey[900]!
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          width: 100,
                          height: 16,
                        ),
                      ),
                      Shimmer.fromColors(
                        baseColor: baseColor,
                        highlightColor: highlightColor,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey[900]!
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          width: 80,
                          height: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
