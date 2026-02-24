import '../models/product.dart';
import '../services/odoo_session_manager.dart';
import '../services/field_validation_service.dart';
import '../services/permission_service.dart';

class ProductService {
  static final ProductService instance = ProductService._internal();

  ProductService._internal();

  List<Map<String, String>>? _cachedCategories;
  DateTime? _categoriesFetchedAt;
  List<Map<String, String>>? _cachedTaxes;
  DateTime? _taxesFetchedAt;
  List<Map<String, String>>? _cachedUOMs;
  DateTime? _uomsFetchedAt;
  List<Map<String, String>>? _cachedCurrencies;
  DateTime? _currenciesFetchedAt;

  final Duration _cacheTTL = const Duration(minutes: 10);

  bool _isFresh(DateTime? t) =>
      t != null && DateTime.now().difference(t) < _cacheTTL;

  void clearDropdownCaches() {
    _cachedCategories = null;
    _categoriesFetchedAt = null;
    _cachedTaxes = null;
    _taxesFetchedAt = null;
    _cachedUOMs = null;
    _uomsFetchedAt = null;
    _cachedCurrencies = null;
    _currenciesFetchedAt = null;
  }

  Future<bool> canCreateProduct() async {
    try {
      final result = await OdooSessionManager.safeCallKw({
        'model': 'product.template',
        'method': 'check_access_rights',
        'args': ['create'],
        'kwargs': {'raise_exception': false},
      });

      if (result is bool) return result;
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<Product?> createProduct(Map<String, dynamic> data) async {
    try {
      final canCreate = await PermissionService.instance.canCreate(
        'product.template',
      );
      if (!canCreate) {
        throw Exception('You do not have permission to create products.');
      }
      final cleanedData = _cleanProductData(data);
      final result = await OdooSessionManager.safeCallKw({
        'model': 'product.template',
        'method': 'create',
        'args': [cleanedData],
        'kwargs': {},
      });

      if (result != null && result is int) {
        return await fetchProductDetails(result.toString());
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> updateProduct(
    String productId,
    Map<String, dynamic> data,
  ) async {
    try {
      final canWrite = await PermissionService.instance.canWrite(
        'product.template',
      );
      if (!canWrite) {
        throw Exception('You do not have permission to modify products.');
      }
      final session = await OdooSessionManager.getCurrentSession();
      if (session == null) throw Exception('No active Odoo session');

      late int templateId;

      if (data.containsKey('id')) {
        templateId = int.parse(productId);
      } else {
        final productResult = await OdooSessionManager.safeCallKw({
          'model': 'product.product',
          'method': 'read',
          'args': [
            [int.parse(productId)],
          ],
          'kwargs': {
            'fields': ['product_tmpl_id'],
          },
        });

        if (productResult is! List || productResult.isEmpty) {
          throw Exception('Product not found');
        }
        templateId = productResult.first['product_tmpl_id'][0];
      }

      final cleanedData = _cleanProductData(data);

      final result = await OdooSessionManager.safeCallKw({
        'model': 'product.template',
        'method': 'write',
        'args': [
          [templateId],
          cleanedData,
        ],
        'kwargs': {},
      });

      return result == true;
    } catch (e) {
      rethrow;
    }
  }

  Map<String, dynamic> _cleanProductData(Map<String, dynamic> data) {
    final cleanedData = Map<String, dynamic>.from(data);

    final potentiallyMissingFields = [
      'lead_time',
      'property_stock_inventory',
      'property_stock_production',
      'procurement_route',
      'cost_method',
      'property_account_income',
      'property_account_expense',
      'seller_ids',
      'dimensions',
      'qty_available',
      'taxes_id',
      'currency_id',
      'uom_id',
    ];

    cleanedData.removeWhere((key, value) {
      if (value == null) return true;
      if (potentiallyMissingFields.contains(key)) return true;
      if (value is String && value.trim().isEmpty) {
        if (!['default_code', 'barcode', 'description_sale'].contains(key)) {
          return true;
        }
      }
      return false;
    });

    return cleanedData;
  }

  Future<Product?> fetchProductDetails(String productId) async {
    try {
      final session = await OdooSessionManager.getCurrentSession();
      if (session == null) throw Exception('No active Odoo session');

      return await FieldValidationService.executeWithFieldValidation<Product?>(
        model: 'product.template',
        apiCall: (fields) async {
          final result = await OdooSessionManager.safeCallKw({
            'model': 'product.template',
            'method': 'read',
            'args': [
              [int.parse(productId)],
            ],
            'kwargs': {'fields': fields},
          });

          if (result is List && result.isNotEmpty) {
            return Product.fromJson(result.first);
          }
          return null;
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<Product?> fetchProductTemplateByProductId(String productId) async {
    try {
      final productResult = await OdooSessionManager.safeCallKw({
        'model': 'product.product',
        'method': 'read',
        'args': [
          [int.parse(productId)],
        ],
        'kwargs': {
          'fields': ['product_tmpl_id'],
        },
      });

      if (productResult is List && productResult.isNotEmpty) {
        final templateId = productResult.first['product_tmpl_id'][0];

        return await FieldValidationService.executeWithFieldValidation<
          Product?
        >(
          model: 'product.template',
          apiCall: (fields) async {
            final templateResult = await OdooSessionManager.safeCallKw({
              'model': 'product.template',
              'method': 'read',
              'args': [
                [templateId],
              ],
              'kwargs': {'fields': fields},
            });

            if (templateResult is List && templateResult.isNotEmpty) {
              return Product.fromJson(templateResult.first);
            }
            return null;
          },
        );
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, String>>> fetchCategoryOptions({
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh &&
          _cachedCategories != null &&
          _isFresh(_categoriesFetchedAt)) {
        return _cachedCategories!;
      }
      final result = await OdooSessionManager.safeCallKw({
        'model': 'product.category',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'fields': ['id', 'name'],
          'order': 'name ASC',
        },
      }).timeout(const Duration(seconds: 12));

      if (result is List) {
        _cachedCategories = result
            .map(
              (item) => {
                'value': item['id'].toString(),
                'label': item['name'] as String,
              },
            )
            .toList();
        _categoriesFetchedAt = DateTime.now();
        return _cachedCategories!;
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, String>>> fetchTaxOptions({
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh && _cachedTaxes != null && _isFresh(_taxesFetchedAt)) {
        return _cachedTaxes!;
      }
      try {
        final result = await OdooSessionManager.safeCallKw({
          'model': 'account.tax',
          'method': 'search_read',
          'args': [
            [
              ['type_tax_use', '=', 'sale'],
              ['active', '=', true],
            ],
          ],
          'kwargs': {
            'fields': ['id', 'name', 'amount', 'amount_type'],
            'order': 'name ASC',
          },
        }).timeout(const Duration(seconds: 12));

        if (result is List) {
          _cachedTaxes = result
              .map(
                (item) => {
                  'value': item['id'].toString(),
                  'label':
                      '${item['name']} (${item['amount']}${item['amount_type'] == 'percent' ? '%' : ''})',
                },
              )
              .toList();
          _taxesFetchedAt = DateTime.now();
          return _cachedTaxes!;
        }
      } catch (fieldError) {
        if (fieldError.toString().contains('Invalid field')) {
          final result = await OdooSessionManager.safeCallKw({
            'model': 'account.tax',
            'method': 'search_read',
            'args': [
              [
                ['type_tax_use', '=', 'sale'],
                ['active', '=', true],
              ],
            ],
            'kwargs': {
              'fields': ['id', 'name'],
              'order': 'name ASC',
            },
          }).timeout(const Duration(seconds: 12));

          if (result is List) {
            _cachedTaxes = result
                .map(
                  (item) => {
                    'value': item['id'].toString(),
                    'label': item['name'] as String,
                  },
                )
                .toList();
            _taxesFetchedAt = DateTime.now();
            return _cachedTaxes!;
          }
        } else {
          rethrow;
        }
      }

      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, String>>> fetchUOMOptions({
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh && _cachedUOMs != null && _isFresh(_uomsFetchedAt)) {
        return _cachedUOMs!;
      }
      try {
        final result = await OdooSessionManager.safeCallKw({
          'model': 'uom.uom',
          'method': 'search_read',
          'args': [
            [
              ['active', '=', true],
            ],
          ],
          'kwargs': {
            'fields': ['id', 'name', 'category_id'],
            'order': 'name ASC',
          },
        }).timeout(const Duration(seconds: 12));

        if (result is List) {
          _cachedUOMs = result
              .map(
                (item) => {
                  'value': item['id'].toString(),
                  'label': item['name'] as String,
                },
              )
              .toList();
          _uomsFetchedAt = DateTime.now();
          return _cachedUOMs!;
        }
      } catch (categoryFieldError) {
        if (categoryFieldError.toString().contains('Invalid field') &&
            categoryFieldError.toString().contains('category_id')) {
          final result = await OdooSessionManager.safeCallKw({
            'model': 'uom.uom',
            'method': 'search_read',
            'args': [
              [
                ['active', '=', true],
              ],
            ],
            'kwargs': {
              'fields': ['id', 'name'],
              'order': 'name ASC',
            },
          }).timeout(const Duration(seconds: 12));

          if (result is List) {
            _cachedUOMs = result
                .map(
                  (item) => {
                    'value': item['id'].toString(),
                    'label': item['name'] as String,
                  },
                )
                .toList();
            _uomsFetchedAt = DateTime.now();
            return _cachedUOMs!;
          }
        } else {
          rethrow;
        }
      }

      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, String>>> fetchCurrencyOptions({
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh &&
          _cachedCurrencies != null &&
          _isFresh(_currenciesFetchedAt)) {
        return _cachedCurrencies!;
      }

      final result = await OdooSessionManager.safeCallKw({
        'model': 'res.currency',
        'method': 'search_read',
        'args': [
          [
            ['active', '=', true],
          ],
        ],
        'kwargs': {
          'fields': ['id', 'name', 'symbol'],
          'order': 'name ASC',
        },
      }).timeout(const Duration(seconds: 12));

      if (result is List) {
        _cachedCurrencies = result
            .map(
              (item) => {
                'value': item['id'].toString(),
                'label': '${item['name']} (${item['symbol']})',
              },
            )
            .toList();
        _currenciesFetchedAt = DateTime.now();
        return _cachedCurrencies!;
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchProducts({
    required List<dynamic> domain,
    required List<String> fields,
    int limit = 40,
    int offset = 0,
    String order = 'name asc',
  }) async {
    try {
      final result = await OdooSessionManager.safeCallKw({
        'model': 'product.template',
        'method': 'search_read',
        'args': [domain],
        'kwargs': {
          'fields': fields,
          'order': order,
          'limit': limit,
          'offset': offset,
        },
      });

      if (result is List) {
        return result.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<int> getProductCount(List<dynamic> domain) async {
    try {
      final result = await OdooSessionManager.safeCallKw({
        'model': 'product.template',
        'method': 'search_count',
        'args': [domain],
        'kwargs': {},
      });

      if (result is int) return result;
      return 0;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchGroupSummary({
    required List<dynamic> domain,
    required String groupBy,
  }) async {
    try {
      final result = await OdooSessionManager.safeCallKw({
        'model': 'product.template',
        'method': 'read_group',
        'args': [domain],
        'kwargs': {
          'fields': [groupBy],
          'groupby': [groupBy],
          'lazy': false,
        },
      });

      if (result is List) {
        return result.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchProductData(
    int productId, {
    List<String>? fields,
  }) async {
    try {
      final result = await OdooSessionManager.safeCallKw({
        'model': 'product.product',
        'method': 'read',
        'args': [
          [productId],
        ],
        'kwargs': {if (fields != null) 'fields': fields},
      });

      return result.isNotEmpty ? result[0] : {};
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchFields(String model) async {
    try {
      final result = await OdooSessionManager.safeCallKw({
        'model': model,
        'method': 'fields_get',
        'args': [],
        'kwargs': {
          'attributes': ['name'],
        },
      });

      if (result is Map) {
        return result.cast<String, dynamic>();
      }
      return {};
    } catch (e) {
      return {};
    }
  }
}
