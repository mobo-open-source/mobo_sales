import 'odoo_session_manager.dart';

/// Provides currency data for the currently active Odoo company.
class CurrencyService {
  static final CurrencyService instance = CurrencyService._internal();

  CurrencyService._internal();

  /// Fetches the currency configured for the current user's company.
  Future<Map<String, dynamic>?> fetchCompanyCurrency() async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No active client session');
      }

      final session = await OdooSessionManager.getCurrentSession();
      if (session == null) {
        throw Exception('No active session');
      }

      final userResult = await client.callKw({
        'model': 'res.users',
        'method': 'search_read',
        'args': [
          [
            ['login', '=', session.userLogin],
          ],
          ['company_id'],
        ],
        'kwargs': {},
      });

      if (userResult == null || userResult.isEmpty) {
        throw Exception('User data not found');
      }

      final companyId = userResult[0]['company_id'][0];

      final companyResult = await client.callKw({
        'model': 'res.company',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', companyId],
          ],
          ['currency_id'],
        ],
        'kwargs': {},
      });

      if (companyResult == null || companyResult.isEmpty) {
        throw Exception('Company data not found');
      }

      final currencyId = companyResult[0]['currency_id'];
      if (currencyId is List && currencyId.length > 1) {
        return {'id': currencyId[0], 'name': currencyId[1].toString()};
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }
}
