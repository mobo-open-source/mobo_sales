import 'package:flutter/foundation.dart' show visibleForTesting;
import '../models/product.dart';
import 'data_change_bus.dart';
import '../services/odoo_compat.dart';
import '../services/odoo_session_manager.dart';
import '../services/field_validation_service.dart';
import '../services/permission_service.dart';

class ProductService {
  static final ProductService instance = ProductService._internal();

  ProductService._internal() : _bus = DataChangeBus.instance;

  /// A service that announces on [bus] instead of the app's; for tests.
  @visibleForTesting
  ProductService.forTesting({required DataChangeBus bus}) : _bus = bus;

  final DataChangeBus _bus;

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

  /// Whether the current user may create products.
  ///
  /// `check_access_rights` no longer exists in Odoo 20, so the question goes
  /// through [OdooCompat.hasAccess], which asks the way each version expects.
  /// Any failure to ask counts as "no", as it always has here. [callKw] and
  /// [generation] stand in for the live session in tests.
  Future<bool> canCreateProduct({OdooCallKw? callKw, int? generation}) async {
    try {
      return await OdooCompat.hasAccess(
        model: 'product.template',
        operation: 'create',
        callKw: callKw,
        generation: generation,
      );
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
        // On the server: every list of products reads it again.
        _bus.productChanged(result, kind: DataChangeKind.created);
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

      if (result == true) {
        // The server has the edit: the lists, the product's page and the
        // pickers that hold a copy of it read it again.
        _bus.productChanged(templateId);
      }
      return result == true;
    } catch (e) {
      rethrow;
    }
  }

  /// Archives the product with template id [templateId], and its variants, and
  /// announces it. Not a deletion in Odoo, but gone from every list.
  Future<void> archiveProduct(int templateId) async {
    final canWrite = await PermissionService.instance.canWrite(
      'product.template',
    );
    if (!canWrite) {
      throw Exception('You do not have permission to modify products.');
    }
    final result = await OdooSessionManager.safeCallKw({
      'model': 'product.template',
      'method': 'write',
      'args': [
        [templateId],
        {'active': false},
      ],
      'kwargs': {},
    });
    if (result != true) {
      throw Exception('Failed to archive the product');
    }
    _bus.productChanged(templateId, kind: DataChangeKind.deleted);
  }

  /// Drops what must not be sent on a create or write: nulls, blank strings
  /// (except the three text fields that may be cleared) and the fields below.
  ///
  /// Checked against the Odoo 17, 18, 19 and 20 sources:
  /// * `currency_id` is a computed, non-stored field on `product.template` in
  ///   every release, so it cannot be written; dropping it is correct.
  /// * `taxes_id` (many2many) and `uom_id` (many2one, required) exist and are
  ///   writable in every release, up to and including 20. Dropping them means
  ///   the tax and unit chosen on the product form are never saved, on any
  ///   version. That is not an Odoo 20 regression and it is left as it was:
  ///   sending them as-is would also make an edit of a product with several
  ///   taxes replace them all with the single tax the form can show.
  /// * `lead_time`, `procurement_route`, `dimensions`, `property_account_income`
  ///   and `property_account_expense` are not fields of any release (the
  ///   accounts are `property_account_income_id` / `..._expense_id`); the form
  ///   never sends them. `qty_available` and `cost_method` are computed.
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
      // Odoo 19 removed `uom.uom.category_id`, which fails the whole read.
      final generation = await OdooSessionManager.serverGeneration();
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
            'fields': uomOptionFields(generation),
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

  /// One row per [groupBy] value with its `__count`, in the shape the old
  /// `read_group` returned (`[id, name]` for a many2one, the raw value for a
  /// selection). Odoo 19 and 20 changed `read_group`, so the call goes through
  /// [OdooCompat.readGroup]. [callKw] and [generation] stand in for the live
  /// session in tests.
  Future<List<Map<String, dynamic>>> fetchGroupSummary({
    required List<dynamic> domain,
    required String groupBy,
    OdooCallKw? callKw,
    int? generation,
  }) async {
    try {
      return await OdooCompat.readGroup(
        model: 'product.template',
        domain: domain,
        fields: [groupBy],
        groupby: [groupBy],
        callKw: callKw,
        generation: generation,
      );
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
