import '../models/contact.dart';
import 'odoo_session_manager.dart';
import 'permission_service.dart';

class CustomerService {
  static CustomerService? _instance;
  static CustomerService get instance => _instance ??= CustomerService._();

  CustomerService._();

  List<Map<String, String>>? _cachedTitleOptions;
  List<Map<String, String>>? _cachedCompanyTypeOptions;
  List<Map<String, String>>? _cachedCustomerRankOptions;
  List<Map<String, String>>? _cachedCurrencyOptions;
  List<Map<String, String>>? _cachedLanguageOptions;
  List<Map<String, String>>? _cachedTimezoneOptions;
  List<Map<String, String>>? _cachedStateOptions;

  void clearDropdownCaches() {
    _cachedTitleOptions = null;
    _cachedCompanyTypeOptions = null;
    _cachedCustomerRankOptions = null;
    _cachedCurrencyOptions = null;
    _cachedLanguageOptions = null;
    _cachedTimezoneOptions = null;
    _cachedStateOptions = null;
  }

  Future<Contact?> fetchCustomerDetails(int customerId) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final result = await OdooSessionManager.safeCallKw({
        'model': 'res.partner',
        'method': 'read',
        'args': [customerId],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'phone',
            'email',
            'website',
            'function',
            'street',
            'street2',
            'city',
            'state_id',
            'zip',
            'country_id',
            'image_1920',
            'partner_latitude',
            'partner_longitude',
            'is_company',
            'company_name',
            'vat',
            'company_type',
            'industry_id',
            'customer_rank',
            'user_id',
            'property_payment_term_id',
            'credit_limit',
            'currency_id',
            'lang',
            'tz',
            'comment',
            'active',
            'type',
            'create_date',
            'write_date',
          ],
        },
      });

      if (result is List && result.isNotEmpty) {
        return Contact.fromJson(Map<String, dynamic>.from(result[0]));
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Contact>> fetchAllCustomers({String? searchQuery}) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      List<dynamic> domain = [
        ['active', '=', true],
      ];

      if (searchQuery != null && searchQuery.isNotEmpty) {
        domain.add('|');
        domain.add('|');
        domain.add(['name', 'ilike', searchQuery]);
        domain.add(['email', 'ilike', searchQuery]);
        domain.add(['phone', 'ilike', searchQuery]);
      }

      final result = await OdooSessionManager.safeCallKw({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [domain],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'phone',
            'email',
            'website',
            'function',
            'street',
            'street2',
            'city',
            'state_id',
            'zip',
            'country_id',
            'image_1920',
            'is_company',
            'company_name',
            'vat',
            'company_type',
            'industry_id',
            'customer_rank',
            'user_id',
            'property_payment_term_id',
            'credit_limit',
            'currency_id',
            'lang',
            'tz',
            'comment',
            'active',
            'type',
            'create_date',
            'write_date',
          ],
          'order': 'name asc',
        },
      });

      if (result is List) {
        return result
            .map((data) => Contact.fromJson(Map<String, dynamic>.from(data)))
            .toList();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<Contact?> createCustomer(Map<String, dynamic> customerData) async {
    try {
      final canCreate = await PermissionService.instance.canCreate(
        'res.partner',
      );
      if (!canCreate) {
        throw Exception('You do not have permission to create customers.');
      }
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final result = await OdooSessionManager.safeCallKw({
        'model': 'res.partner',
        'method': 'create',
        'args': [customerData],
        'kwargs': {},
      });

      if (result != null) {
        return await fetchCustomerDetails(result);
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> updateCustomer(
    int customerId,
    Map<String, dynamic> customerData,
  ) async {
    try {
      final canWrite = await PermissionService.instance.canWrite('res.partner');
      if (!canWrite) {
        throw Exception('You do not have permission to modify customers.');
      }
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final result = await OdooSessionManager.safeCallKw({
        'model': 'res.partner',
        'method': 'write',
        'args': [
          [customerId],
          customerData,
        ],
        'kwargs': {},
      });

      return result == true;
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> deleteCustomer(int customerId) async {
    try {
      final canWrite = await PermissionService.instance.canWrite('res.partner');
      if (!canWrite) {
        throw Exception('You do not have permission to archive customers.');
      }
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final result = await OdooSessionManager.safeCallKw({
        'model': 'res.partner',
        'method': 'write',
        'args': [
          [customerId],
          {'active': false},
        ],
        'kwargs': {},
      });

      return result == true;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchCustomerStats(int customerId) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final totalOrders = await OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'search_count',
        'args': [
          [
            ['partner_id', '=', customerId],
          ],
        ],
        'kwargs': {},
      });

      final ordersResult = await OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [
          [
            ['partner_id', '=', customerId],
            [
              'state',
              'in',
              ['sale', 'done'],
            ],
          ],
        ],
        'kwargs': {
          'fields': ['amount_total'],
        },
      });

      double totalAmount = 0.0;
      if (ordersResult is List) {
        for (final order in ordersResult) {
          totalAmount += (order['amount_total'] ?? 0.0);
        }
      }

      final recentOrders = await OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [
          [
            ['partner_id', '=', customerId],
          ],
        ],
        'kwargs': {
          'fields': ['name', 'date_order', 'amount_total', 'state'],
          'limit': 5,
          'order': 'date_order desc',
        },
      });

      return {
        'total_orders': totalOrders ?? 0,
        'total_amount': totalAmount,
        'recent_orders': recentOrders ?? [],
      };
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchCustomerActivities(
    int customerId,
  ) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      final activities = <Map<String, dynamic>>[];

      final ordersResult = await OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [
          [
            ['partner_id', '=', customerId],
          ],
        ],
        'kwargs': {
          'fields': ['name', 'date_order', 'amount_total', 'state'],
          'limit': 10,
          'order': 'date_order desc',
        },
      });

      if (ordersResult is List) {
        for (final order in ordersResult) {
          activities.add({
            'type': 'Order',
            'date': order['date_order'] ?? '',
            'amount': order['amount_total']?.toString() ?? '0.0',
            'reference': order['name'] ?? '',
            'status': order['state'] ?? '',
            'icon': 'shopping_cart',
            'color': 'blue',
          });
        }
      }

      final invoicesResult = await OdooSessionManager.safeCallKw({
        'model': 'account.move',
        'method': 'search_read',
        'args': [
          [
            ['partner_id', '=', customerId],
            ['move_type', '=', 'out_invoice'],
          ],
        ],
        'kwargs': {
          'fields': ['name', 'invoice_date', 'amount_total', 'state'],
          'limit': 10,
          'order': 'invoice_date desc',
        },
      });

      if (invoicesResult is List) {
        for (final invoice in invoicesResult) {
          activities.add({
            'type': 'Invoice',
            'date': invoice['invoice_date'] ?? '',
            'amount': invoice['amount_total']?.toString() ?? '0.0',
            'reference': invoice['name'] ?? '',
            'status': invoice['state'] ?? '',
            'icon': 'receipt',
            'color': 'orange',
          });
        }
      }

      activities.sort((a, b) => (b['date'] ?? '').compareTo(a['date'] ?? ''));

      return activities.take(10).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Contact>> searchCustomers({
    String? name,
    String? email,
    String? phone,
    String? company,
    bool? isCompany,
  }) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      List<dynamic> domain = [
        ['active', '=', true],
      ];

      if (name != null && name.isNotEmpty) {
        domain.add(['name', 'ilike', name]);
      }

      if (email != null && email.isNotEmpty) {
        domain.add(['email', 'ilike', email]);
      }

      if (phone != null && phone.isNotEmpty) {
        domain.add('|');
        domain.add(['phone', 'ilike', phone]);
      }

      if (company != null && company.isNotEmpty) {
        domain.add(['company_name', 'ilike', company]);
      }

      if (isCompany != null) {
        domain.add(['is_company', '=', isCompany]);
      }

      final result = await OdooSessionManager.safeCallKw({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [domain],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'phone',
            'email',
            'website',
            'function',
            'street',
            'street2',
            'city',
            'state_id',
            'zip',
            'country_id',
            'image_1920',
            'is_company',
            'company_name',
            'vat',
            'company_type',
            'industry_id',
            'customer_rank',
            'user_id',
            'property_payment_term_id',
            'credit_limit',
            'currency_id',
            'lang',
            'tz',
            'comment',
            'active',
            'type',
            'create_date',
            'write_date',
          ],
          'order': 'name asc',
        },
      });

      if (result is List) {
        return result
            .map((data) => Contact.fromJson(Map<String, dynamic>.from(data)))
            .toList();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, String>>> fetchTitleOptions({
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh && _cachedTitleOptions != null) {
        return _cachedTitleOptions!;
      }
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');
      final result = await OdooSessionManager.safeCallKw({
        'model': 'res.partner.title',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'fields': ['id', 'name'],
        },
      });
      if (result is List) {
        final data = result
            .map(
              (e) => {
                'value': e['id']?.toString() ?? '',
                'label': e['name']?.toString() ?? '',
              },
            )
            .where((m) => m['value']!.isNotEmpty && m['label']!.isNotEmpty)
            .toList();
        _cachedTitleOptions = data;
        return data;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, String>>> fetchCompanyTypeOptions({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedCompanyTypeOptions != null) {
      return _cachedCompanyTypeOptions!;
    }
    final client = await OdooSessionManager.getClient();
    if (client == null) throw Exception('No active Odoo session');
    final result = await OdooSessionManager.safeCallKw({
      'model': 'res.partner',
      'method': 'fields_get',
      'args': [],
      'kwargs': {},
    });
    if (result is Map &&
        result['company_type'] != null &&
        result['company_type']['selection'] is List) {
      final data = (result['company_type']['selection'] as List)
          .map(
            (e) => {
              'value': e[0]?.toString() ?? '',
              'label': e[1]?.toString() ?? '',
            },
          )
          .where((m) => m['value']!.isNotEmpty && m['label']!.isNotEmpty)
          .toList();
      _cachedCompanyTypeOptions = data;
      return data;
    }
    return [];
  }

  Future<List<Map<String, String>>> fetchCustomerRankOptions({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedCustomerRankOptions != null) {
      return _cachedCustomerRankOptions!;
    }
    final client = await OdooSessionManager.getClient();
    if (client == null) throw Exception('No active Odoo session');
    final result = await OdooSessionManager.safeCallKw({
      'model': 'res.partner',
      'method': 'fields_get',
      'args': [],
      'kwargs': {},
    });
    if (result is Map &&
        result['customer_rank'] != null &&
        result['customer_rank']['selection'] is List) {
      final data = (result['customer_rank']['selection'] as List)
          .map(
            (e) => {
              'value': e[0]?.toString() ?? '',
              'label': e[1]?.toString() ?? '',
            },
          )
          .where((m) => m['value']!.isNotEmpty && m['label']!.isNotEmpty)
          .toList();
      _cachedCustomerRankOptions = data;
      return data;
    }
    return [];
  }

  Future<List<Map<String, String>>> fetchCurrencyOptions({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedCurrencyOptions != null) {
      return _cachedCurrencyOptions!;
    }
    final client = await OdooSessionManager.getClient();
    if (client == null) throw Exception('No active Odoo session');
    final result = await OdooSessionManager.safeCallKw({
      'model': 'res.currency',
      'method': 'search_read',
      'args': [],
      'kwargs': {
        'fields': ['id', 'name'],
      },
    });
    if (result is List) {
      final data = result
          .map(
            (e) => {
              'value': e['id']?.toString() ?? '',
              'label': e['name']?.toString() ?? '',
            },
          )
          .where((m) => m['value']!.isNotEmpty && m['label']!.isNotEmpty)
          .toList();
      _cachedCurrencyOptions = data;
      return data;
    }
    return [];
  }

  Future<List<Map<String, String>>> fetchLanguageOptions({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedLanguageOptions != null) {
      return _cachedLanguageOptions!;
    }
    final client = await OdooSessionManager.getClient();
    if (client == null) throw Exception('No active Odoo session');
    final result = await OdooSessionManager.safeCallKw({
      'model': 'res.lang',
      'method': 'search_read',
      'args': [],
      'kwargs': {
        'fields': ['code', 'name'],
      },
    });
    if (result is List) {
      final data = result
          .map(
            (e) => {
              'value': e['code']?.toString() ?? '',
              'label': e['name']?.toString() ?? '',
            },
          )
          .where((m) => m['value']!.isNotEmpty && m['label']!.isNotEmpty)
          .toList();
      _cachedLanguageOptions = data;
      return data;
    }
    return [];
  }

  Future<List<Map<String, String>>> fetchTimezoneOptions({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedTimezoneOptions != null) {
      return _cachedTimezoneOptions!;
    }
    final client = await OdooSessionManager.getClient();
    if (client == null) throw Exception('No active Odoo session');
    final result = await OdooSessionManager.safeCallKw({
      'model': 'res.partner',
      'method': 'fields_get',
      'args': [],
      'kwargs': {},
    });
    if (result is Map &&
        result['tz'] != null &&
        result['tz']['selection'] is List) {
      final data = (result['tz']['selection'] as List)
          .map(
            (e) => {
              'value': e[0]?.toString() ?? '',
              'label': e[1]?.toString() ?? '',
            },
          )
          .where((m) => m['value']!.isNotEmpty && m['label']!.isNotEmpty)
          .toList();
      _cachedTimezoneOptions = data;
      return data;
    }
    return [];
  }

  Future<List<Map<String, String>>> fetchStateOptions({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedStateOptions != null) {
      return _cachedStateOptions!;
    }
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');
      final result = await OdooSessionManager.safeCallKw({
        'model': 'res.country.state',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'fields': ['id', 'name'],
        },
      });
      if (result is List) {
        final data = result
            .map(
              (e) => {
                'value': e['id']?.toString() ?? '',
                'label': e['name']?.toString() ?? '',
              },
            )
            .where((m) => m['value']!.isNotEmpty && m['label']!.isNotEmpty)
            .toList();
        _cachedStateOptions = data;
        return data;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchContacts({
    required List<dynamic> domain,
    required List<String> fields,
    int limit = 40,
    int offset = 0,
    String order = 'name asc',
  }) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');

      final result = await OdooSessionManager.safeCallKw({
        'model': 'res.partner',
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

  Future<int> getContactCount(List<dynamic> domain) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');

      final result = await OdooSessionManager.safeCallKw({
        'model': 'res.partner',
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
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');

      final result = await OdooSessionManager.safeCallKw({
        'model': 'res.partner',
        'method': 'read_group',
        'args': [domain],
        'kwargs': {
          'fields': ['id'],
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
}
