import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/contact.dart';
import '../utils/odoo_version.dart';
import 'data_change_bus.dart';
import 'field_validation_service.dart';
import 'odoo_compat.dart';
import 'odoo_session_manager.dart';
import 'permission_service.dart';

// ---------------------------------------------------------------------------
// res.partner across Odoo versions
//
// The customer screens ask for the same handful of fields from several places.
// Odoo has been taking some of them away (`mobile` and `title` in 19,
// `company_type` and `company_name` in 20), and a read or write naming a field
// the server no longer has fails as a whole. Every field list therefore goes
// through [partnerReadFieldsFor] and every write through [partnerValuesFor] or
// [partnerWritableValues], which are plain functions so the version table can
// be tested without a server.
// ---------------------------------------------------------------------------

/// `res.partner` fields read for a single customer (after create/update, for
/// the quote and invoice pickers).
const List<String> kCustomerDetailFields = [
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
];

/// `res.partner` fields read for the customer typeahead (thumbnail image, no
/// coordinates).
const List<String> kCustomerListFields = [
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
  'image_128',
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
];

/// `res.partner` fields read by [CustomerService.searchCustomers].
const List<String> kCustomerSearchFields = [
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
];

/// `res.partner` fields the customer details screen reads.
const List<String> kCustomerScreenFields = [
  'id',
  'name',
  'email',
  'phone',
  'mobile',
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
  'create_date',
  'write_date',
  'is_company',
  'company_name',
  'vat',
  'company_type',
  'industry_id',
  'customer_rank',
  'user_id',
  'property_payment_term_id',
  'credit_limit',
  'property_product_pricelist',
  'title',
  'lang',
  'tz',
  'comment',
  'active',
  'type',
  'category_id',
];

/// `res.partner` fields the customer list reads, one page at a time.
const List<String> kContactListFields = [
  'id',
  'name',
  'complete_name',
  'phone',
  'email',
  'street',
  'street2',
  'city',
  'state_id',
  'zip',
  'country_id',
  'image_128',
  'is_company',
  'company_name',
  'company_id',
  'active',
  'type',
  'user_id',
  'category_id',
  'create_date',
  'write_date',
  'credit_limit',
  'credit',
];

/// The order Odoo itself lists partners in (`res.partner._order`, Odoo 17-20):
/// by `complete_name` ("Company, Contact" for a contact under a company), so a
/// contact sorts beside its company, with the newest first among equal names.
const String kPartnerListOrder = 'complete_name asc, id desc';

/// [fields] as this server's generation can read them.
///
/// * `mobile` and `title` are dropped from Odoo 19, `company_type` from 20.
/// * `company_name` is replaced, from Odoo 20, by `parent_name`: the free-text
///   company of a contact became the "Company Employer" relation (`parent_id`),
///   and `parent_name` is its name, which [Contact.fromJson] reads where
///   `company_name` used to be. `company_type` needs no stand-in: it is derived
///   from `is_company`, which every list here also asks for.
///
/// An unknown generation (0) keeps every field, as the app always did; the
/// field pruning in [FieldValidationService] recovers if the server disagrees.
List<String> partnerReadFieldsFor(List<String> fields, int generation) {
  final out = <String>[];
  void add(String field) {
    if (!out.contains(field)) out.add(field);
  }

  for (final field in fields) {
    switch (field) {
      case 'mobile':
        if (odooHasPartnerMobile(generation)) add(field);
      case 'title':
        if (odooHasPartnerTitle(generation)) add(field);
      case 'company_type':
        if (odooHasPartnerCompanyType(generation)) add(field);
      case 'company_name':
        add(odooHasPartnerCompanyName(generation) ? field : 'parent_name');
      default:
        add(field);
    }
  }
  return out;
}

/// [values] without what a `res.partner` write or create cannot carry on this
/// generation: `mobile`, `title`, `company_type`, `company_name`, and
/// `is_company`. In Odoo 20 that one is computed from the tax ID and the
/// parent: the schema calls it read-only, a create ignores it, and a written
/// value is overwritten as soon as the tax ID is written again (which every
/// edit does). The removed fields would fail the whole call: `KeyError` on a
/// write, `Invalid field` on a create.
Map<String, dynamic> partnerValuesFor(
  Map<String, dynamic> values,
  int generation,
) {
  final out = Map<String, dynamic>.from(values);
  if (!odooHasPartnerMobile(generation)) out.remove('mobile');
  if (!odooHasPartnerTitle(generation)) out.remove('title');
  if (!odooHasPartnerCompanyType(generation)) out.remove('company_type');
  if (!odooHasPartnerCompanyName(generation)) out.remove('company_name');
  if (!odooPartnerIsCompanyWritable(generation)) out.remove('is_company');
  return out;
}

/// What a write can carry: the server's own schema decides when it could be
/// read (a field it does not define, or defines read-only, is dropped), and
/// the version table when it could not (an empty [schema]).
Map<String, dynamic> partnerWritableValues(
  Map<String, dynamic> values, {
  required Map<String, Map<String, dynamic>> schema,
  required int generation,
}) {
  if (schema.isEmpty) return partnerValuesFor(values, generation);

  final accepted = <String, dynamic>{};
  values.forEach((key, value) {
    final describe = schema[key];
    if (describe == null) return;
    if (describe['readonly'] == true) return;
    accepted[key] = value;
  });
  return accepted;
}

/// Whether [schema] (a `fields_get` of `res.partner`) says [field] exists and
/// can be written. [whenUnknown] answers when the schema could not be read.
bool partnerFieldWritableIn(
  Map<String, Map<String, dynamic>> schema,
  String field, {
  required bool whenUnknown,
}) {
  if (schema.isEmpty) return whenUnknown;
  final describe = schema[field];
  return describe != null && describe['readonly'] != true;
}

/// Whether [edited], what the form holds, differs from [original], what the
/// contact was loaded with. Odoo sends `false` for an empty char and [Contact]
/// keeps it as the string `'false'`, so that and null both count as empty.
bool partnerTextChanged(String? original, String edited) {
  String clean(String? value) =>
      (value == null || value.trim().toLowerCase() == 'false')
      ? ''
      : value.trim();
  return clean(original) != clean(edited);
}

/// The domain leaf that matches a contact by the name of its company.
///
/// Up to Odoo 19 that is the free-text `company_name`. Odoo 20 removed the
/// field, and naming it in a domain makes the whole search fail, so the
/// company is the parent partner (`parent_id`) there.
List<dynamic> partnerCompanyLeaf(String query, int generation) {
  return odooHasPartnerCompanyName(generation)
      ? ['company_name', 'ilike', query]
      : ['parent_id.name', 'ilike', query];
}

class CustomerService {
  static CustomerService? _instance;
  static CustomerService get instance => _instance ??= CustomerService._();

  /// Replaces the shared service, for tests.
  @visibleForTesting
  static set instance(CustomerService service) => _instance = service;

  CustomerService._()
    : _callKw = OdooSessionManager.safeCallKw,
      _hasSession = _liveHasSession,
      _serverGeneration = OdooSessionManager.serverGeneration,
      _bus = DataChangeBus.instance;

  /// A service that sends its calls through [callKw] and announces its changes
  /// on [bus], for tests. [hasSession] and [serverGeneration] stand in for the
  /// signed-in session (a session that exists, on Odoo 17, by default).
  @visibleForTesting
  CustomerService.forTesting({
    required Future<dynamic> Function(Map<String, dynamic> payload) callKw,
    DataChangeBus? bus,
    Future<bool> Function()? hasSession,
    Future<int> Function()? serverGeneration,
  }) : _callKw = callKw,
       _hasSession = hasSession ?? (() async => true),
       _serverGeneration = serverGeneration ?? (() async => 17),
       _bus = bus ?? DataChangeBus.forTesting();

  final Future<dynamic> Function(Map<String, dynamic> payload) _callKw;
  final Future<bool> Function() _hasSession;
  final Future<int> Function() _serverGeneration;
  final DataChangeBus _bus;

  static Future<bool> _liveHasSession() async =>
      await OdooSessionManager.getClient() != null;

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
      if (!await _hasSession()) {
        throw Exception('No active Odoo session');
      }

      final generation = await _serverGeneration();
      final result =
          await FieldValidationService.executeWithFieldValidation<dynamic>(
            model: 'res.partner',
            initialFields: partnerReadFieldsFor(
              kCustomerDetailFields,
              generation,
            ),
            apiCall: (fields) => _callKw({
              'model': 'res.partner',
              'method': 'read',
              'args': [customerId],
              'kwargs': {'fields': fields},
            }),
          );

      if (result is List && result.isNotEmpty) {
        return Contact.fromJson(Map<String, dynamic>.from(result[0]));
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Contact>> fetchAllCustomers({
    String? searchQuery,
    int? limit,
  }) async {
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

      final generation = await OdooSessionManager.serverGeneration();
      final result =
          await FieldValidationService.executeWithFieldValidation<dynamic>(
            model: 'res.partner',
            initialFields: partnerReadFieldsFor(
              kCustomerListFields,
              generation,
            ),
            apiCall: (fields) => OdooSessionManager.safeCallKw({
              'model': 'res.partner',
              'method': 'search_read',
              'args': [domain],
              'kwargs': {
                'limit': limit ?? 200,
                'fields': fields,
                'order': 'name asc',
              },
            }),
          );

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

  Map<String, Map<String, dynamic>>? _partnerFieldsCache;
  String? _partnerFieldsAccountKey;

  /// This server's `res.partner` schema, cached per account.
  ///
  /// Asked for rather than assumed. Odoo rejects a write naming a field the
  /// model does not define, and it rejects the *entire* call — so one stale
  /// field name loses every other value in the same request. Which fields
  /// exist genuinely differs: Odoo 19 dropped both `mobile` and `title` from
  /// `res.partner`, Odoo 20 dropped `company_type` and `company_name` and made
  /// `is_company` a computed (read-only) field, and `currency_id` is computed
  /// and cannot be written.
  Future<Map<String, Map<String, dynamic>>> _partnerFields() async {
    final session = await OdooSessionManager.getCurrentSession();
    final accountKey = session == null
        ? null
        : '${session.serverUrl}|${session.database}|${session.userId}';
    if (_partnerFieldsAccountKey != accountKey) {
      _partnerFieldsAccountKey = accountKey;
      _partnerFieldsCache = null;
    }
    final cached = _partnerFieldsCache;
    if (cached != null) return cached;

    try {
      final result = await _callKw({
        'model': 'res.partner',
        'method': 'fields_get',
        'args': [
          <String>[],
          ['type', 'readonly'],
        ],
        'kwargs': const {},
      }).timeout(const Duration(seconds: 30));

      if (result is Map && result.isNotEmpty) {
        final described = result.map(
          (key, value) => MapEntry(
            '$key',
            value is Map
                ? Map<String, dynamic>.from(value)
                : <String, dynamic>{},
          ),
        );
        _partnerFieldsCache = described;
        return described;
      }
    } catch (_) {}
    return const {};
  }

  /// Drops values this server will not accept, so one of them cannot take the
  /// whole write down with it. When the schema could not be read, the version
  /// table stands in for it (see [partnerValuesFor]).
  Future<Map<String, dynamic>> _writableValues(
    Map<String, dynamic> values,
  ) async {
    final schema = await _partnerFields();
    final generation = await _serverGeneration();
    return partnerWritableValues(
      values,
      schema: schema,
      generation: generation,
    );
  }

  /// Whether this server defines [field] on `res.partner` and will accept a
  /// value for it, so a screen can leave out an input the server cannot store.
  ///
  /// [whenUnknown] is the answer while the schema is unknown. It defaults to
  /// true so a failed probe shows the form as it always was rather than hiding
  /// fields at random; a caller that knows the server's version passes what
  /// that version supports instead.
  Future<bool> isPartnerFieldWritable(
    String field, {
    bool whenUnknown = true,
  }) async {
    final schema = await _partnerFields();
    return partnerFieldWritableIn(schema, field, whenUnknown: whenUnknown);
  }

  Future<Contact?> createCustomer(Map<String, dynamic> customerData) async {
    try {
      final canCreate = await PermissionService.instance.canCreate(
        'res.partner',
      );
      if (!canCreate) {
        throw Exception('You do not have permission to create customers.');
      }
      if (!await _hasSession()) {
        throw Exception('No active Odoo session');
      }

      final result = await _callKw({
        'model': 'res.partner',
        'method': 'create',
        'args': [await _writableValues(customerData)],
        'kwargs': {},
      });

      if (result != null) {
        // Announced as soon as the server has the record, before the read-back
        // below: a read that then fails (a field the user may not see) leaves
        // the customer created, and every list must still show it.
        _bus.publish(
          DataEntity.customer,
          DataChangeKind.created,
          id: result is int ? result : null,
        );
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
      if (!await _hasSession()) {
        throw Exception('No active Odoo session');
      }

      final result = await _callKw({
        'model': 'res.partner',
        'method': 'write',
        'args': [
          [customerId],
          await _writableValues(customerData),
        ],
        'kwargs': {},
      });

      if (result == true) {
        _bus.publish(
          DataEntity.customer,
          DataChangeKind.updated,
          id: customerId,
        );
      }
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
      if (!await _hasSession()) {
        throw Exception('No active Odoo session');
      }

      final result = await _callKw({
        'model': 'res.partner',
        'method': 'write',
        'args': [
          [customerId],
          {'active': false},
        ],
        'kwargs': {},
      });

      if (result == true) {
        // Archived: gone from every list, whatever the word the screen uses.
        _bus.publish(
          DataEntity.customer,
          DataChangeKind.deleted,
          id: customerId,
        );
      }
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

      final generation = await OdooSessionManager.serverGeneration();
      if (company != null && company.isNotEmpty) {
        domain.add(partnerCompanyLeaf(company, generation));
      }

      if (isCompany != null) {
        domain.add(['is_company', '=', isCompany]);
      }

      final result =
          await FieldValidationService.executeWithFieldValidation<dynamic>(
            model: 'res.partner',
            initialFields: partnerReadFieldsFor(
              kCustomerSearchFields,
              generation,
            ),
            apiCall: (fields) => OdooSessionManager.safeCallKw({
              'model': 'res.partner',
              'method': 'search_read',
              'args': [domain],
              'kwargs': {'fields': fields, 'order': 'name asc'},
            }),
          );

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
      // Odoo 19 removed the model along with the field; nothing to ask for.
      if (!odooHasPartnerTitle(await OdooSessionManager.serverGeneration())) {
        return [];
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
    // Odoo 20 removed the field (a partner is a company by its VAT instead), so
    // there is no list of types to offer and no reason to fetch the schema.
    if (!odooHasPartnerCompanyType(
      await OdooSessionManager.serverGeneration(),
    )) {
      return [];
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
    String order = kPartnerListOrder,
  }) async {
    try {
      if (!await _hasSession()) throw Exception('No active Odoo session');

      final result = await _callKw({
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

      // Odoo 19 deprecated `read_group` and 20 gave it a new signature; the
      // helper sends the call each version takes and hands back the old rows
      // (group value under the field name, `__count`).
      return await OdooCompat.readGroup(
        model: 'res.partner',
        domain: domain,
        fields: const ['id'],
        groupby: [groupBy],
        callKw: OdooSessionManager.safeCallKw,
      );
    } catch (e) {
      rethrow;
    }
  }
}
