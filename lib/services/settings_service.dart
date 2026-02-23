import 'odoo_session_manager.dart';

/// Provides user profile and company preference data from Odoo.
class SettingsService {
  static final SettingsService instance = SettingsService._internal();

  SettingsService._internal();

  /// Fetches the current user's profile from `res.users`.
  Future<Map<String, dynamic>?> fetchUserProfile() async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active client session');

      final session = await OdooSessionManager.getCurrentSession();
      if (session == null) throw Exception('No active session');

      final userResult = await client.callKw({
        'model': 'res.users',
        'method': 'search_read',
        'args': [
          [
            ['login', '=', session.userLogin],
          ],
          [
            'name',
            'email',
            'login',
            'lang',
            'tz',
            'company_id',
            'partner_id',
            'image_1920',
          ],
        ],
        'kwargs': {},
      });

      if (userResult != null && userResult.isNotEmpty) {
        return userResult[0];
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  /// Fetches company details for the given [companyId].
  Future<Map<String, dynamic>?> fetchCompanyInfo(int companyId) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active client session');

      final companyResult = await client.callKw({
        'model': 'res.company',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', companyId],
          ],
          [
            'name',
            'email',
            'phone',
            'website',
            'currency_id',
            'country_id',
            'state_id',
            'city',
            'street',
            'zip',
          ],
        ],
        'kwargs': {},
      });

      if (companyResult != null && companyResult.isNotEmpty) {
        return companyResult[0];
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  /// Returns all active languages configured in Odoo.
  Future<List<Map<String, dynamic>>> fetchAvailableLanguages() async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active client session');

      final result = await client.callKw({
        'model': 'res.lang',
        'method': 'search_read',
        'args': [
          [
            ['active', '=', true],
          ],
          ['code', 'name', 'iso_code', 'direction'],
        ],
        'kwargs': {'order': 'name'},
      });

      if (result != null) {
        return List<Map<String, dynamic>>.from(result);
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  /// Returns all active currencies available in Odoo.
  Future<List<Map<String, dynamic>>> fetchAvailableCurrencies() async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active client session');

      final result = await client.callKw({
        'model': 'res.currency',
        'method': 'search_read',
        'args': [
          [
            ['active', '=', true],
          ],
          ['name', 'full_name', 'symbol', 'position', 'rounding'],
        ],
        'kwargs': {'order': 'name'},
      });

      if (result != null) {
        return List<Map<String, dynamic>>.from(result);
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  /// Returns all timezone options available for `res.users.tz`.
  Future<List<Map<String, dynamic>>> fetchAvailableTimezones() async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active client session');

      final result = await client.callKw({
        'model': 'res.users',
        'method': 'fields_get',
        'args': [
          ['tz'],
        ],
        'kwargs': {
          'attributes': ['selection', 'string'],
        },
      });

      final tzField = (result != null)
          ? result['tz'] as Map<String, dynamic>?
          : null;
      final selection = tzField != null
          ? tzField['selection'] as List<dynamic>?
          : null;

      if (selection != null && selection.isNotEmpty) {
        return selection.map<Map<String, dynamic>>((item) {
          if (item is List && item.length >= 2) {
            return {'code': item[0].toString(), 'name': item[1].toString()};
          }
          return {'code': item.toString(), 'name': item.toString()};
        }).toList();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  /// Writes [updateData] fields to the `res.users` record for [userId].
  Future<void> updateUserPreferences(
    int userId,
    Map<String, dynamic> updateData,
  ) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active client session');

      await client.callKw({
        'model': 'res.users',
        'method': 'write',
        'args': [
          [userId],
          updateData,
        ],
        'kwargs': {},
      });
    } catch (e) {
      rethrow;
    }
  }
}
