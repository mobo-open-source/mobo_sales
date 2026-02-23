import 'odoo_session_manager.dart';
import 'field_validation_service.dart';

/// Provides stock-related data from Odoo's inventory module.
class StockService {
  static StockService? _instance;
  static StockService get instance => _instance ??= StockService._();

  StockService._();

  /// Returns the company ID for the current Odoo user.
  Future<int?> getCompanyId() async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return null;

      final userId = client.sessionId?.userId;
      if (userId == null) return null;

      final userResult = await client.callKw({
        'model': 'res.users',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', userId],
          ],
          ['company_id'],
        ],
        'kwargs': {},
      });

      if (userResult != null && userResult.isNotEmpty) {
        final companyId = userResult[0]['company_id'];
        if (companyId is List && companyId.isNotEmpty) {
          return companyId[0] as int;
        } else if (companyId is int) {
          return companyId;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Fetches a paginated list of product templates matching [domain].
  Future<List<Map<String, dynamic>>> fetchStockTemplates({
    required List<dynamic> domain,
    required int limit,
    required int offset,
    int? companyId,
  }) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');

      final result = await client.callKw({
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
        'kwargs': {'offset': offset, 'limit': limit},
        'context': companyId != null ? {'company_id': companyId} : {},
      });

      if (result is List) {
        return result.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  /// Returns the total count of products matching [domain].
  Future<int> getStockCount({
    required List<dynamic> domain,
    int? companyId,
  }) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');

      final result = await client.callKw({
        'model': 'product.template',
        'method': 'search_count',
        'args': [domain],
        'kwargs': {},
        'context': companyId != null ? {'company_id': companyId} : {},
      });

      if (result is int) return result;
      return 0;
    } catch (e) {
      rethrow;
    }
  }

  /// Fetches all stock locations for the given [companyId].
  Future<List<Map<String, dynamic>>> fetchLocations({int? companyId}) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');

      final result = await client.callKw({
        'model': 'stock.location',
        'method': 'search_read',
        'args': [[]],
        'kwargs': {
          'fields': ['id', 'complete_name', 'usage'],
        },
        'context': companyId != null ? {'company_id': companyId} : {},
      });

      if (result is List) {
        return result.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  /// Returns stock quant records for the given [productId].
  Future<List<Map<String, dynamic>>> fetchStockQuants(
    int productId, {
    int? companyId,
  }) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');

      final result = await client.callKw({
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
        'context': companyId != null ? {'company_id': companyId} : {},
      });

      if (result is List) {
        return result.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  /// Fetches on-hand and forecasted quantity info for [productId].
  Future<Map<String, dynamic>?> fetchProductStockInfo(
    int productId, {
    int? companyId,
  }) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');

      final result =
          await FieldValidationService.executeWithFieldValidation<
            List<dynamic>
          >(
            model: 'product.product',
            initialFields: ['qty_available', 'virtual_available'],
            apiCall: (fields) async {
              return await client.callKw({
                'model': 'product.product',
                'method': 'read',
                'args': [
                  [productId],
                ],
                'kwargs': {'fields': fields},
                'context': companyId != null ? {'company_id': companyId} : {},
              });
            },
          );

      if (result.isNotEmpty) {
        return result[0] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  /// Fetches stock moves for [productId] matching [domain].
  Future<List<Map<String, dynamic>>> fetchStockMoves({
    required int productId,
    required List<dynamic> domain,
    int? companyId,
  }) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');

      final result = await client.callKw({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [domain],
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
        'context': companyId != null ? {'company_id': companyId} : {},
      });

      if (result is List) {
        return result.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  /// Fetches stock move lines for the given [lineIds].
  Future<List<Map<String, dynamic>>> fetchStockMoveLines(
    List<int> lineIds, {
    int? companyId,
  }) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');

      final result = await client.callKw({
        'model': 'stock.move.line',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', lineIds],
          ],
          ['id', 'move_id', 'quantity'],
        ],
        'kwargs': {},
        'context': companyId != null ? {'company_id': companyId} : {},
      });

      if (result is List) {
        return result.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }
}
