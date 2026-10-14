import 'odoo_session_manager.dart';

/// Caches each Odoo model's field definitions, so the app can ask the server
/// what it accepts instead of encoding rules per Odoo release.
///
/// Odoo rejects a write naming a field the model does not define, and it
/// rejects the *entire* call — one stale name loses every other value in the
/// same request. Which fields exist changes between releases: 19 dropped both
/// `mobile` and `title` from `res.partner`. Discovering the schema keeps the
/// app working on versions that did not exist when it was written.
class OdooSchemaService {
  OdooSchemaService._();

  /// Shared instance. The cache is per account and cleared when the signed-in
  /// account changes, so one server's schema is never applied to another's.
  static final OdooSchemaService instance = OdooSchemaService._();

  static const Duration _timeout = Duration(seconds: 30);

  final Map<String, Map<String, Map<String, dynamic>>> _cache = {};
  String? _accountKey;

  /// Forgets everything learned about the previous account's server.
  void reset() {
    _cache.clear();
    _accountKey = null;
  }

  Future<void> _ensureCurrentAccount() async {
    final session = await OdooSessionManager.getCurrentSession();
    final key = session == null
        ? null
        : '${session.serverUrl}|${session.database}|${session.userId}';
    if (_accountKey != key) {
      _accountKey = key;
      _cache.clear();
    }
  }

  /// [model]'s fields, keyed by name. Empty when the schema cannot be read,
  /// which every caller must treat as "unknown" rather than "no fields".
  ///
  /// Only a successful probe is cached, so a dropped connection is retried on
  /// the next call rather than pinning the session to "unknown" and leaving
  /// every caller on its fallback behaviour for the rest of the session.
  Future<Map<String, Map<String, dynamic>>> fieldsOf(String model) async {
    await _ensureCurrentAccount();
    final cached = _cache[model];
    if (cached != null) return cached;

    try {
      final result = await OdooSessionManager.safeCallKw({
        'model': model,
        'method': 'fields_get',
        'args': [
          <String>[],
          ['type', 'readonly', 'relation'],
        ],
        'kwargs': const {},
      }).timeout(_timeout);

      if (result is Map && result.isNotEmpty) {
        final described = result.map(
          (key, value) => MapEntry(
            '$key',
            value is Map
                ? Map<String, dynamic>.from(value)
                : <String, dynamic>{},
          ),
        );
        _cache[model] = described;
        return described;
      }
    } catch (_) {}
    return const {};
  }

  /// Whether [model] defines [field] and will accept a value for it.
  ///
  /// True while the schema is unknown, so a failed probe leaves a screen
  /// looking exactly as it did rather than hiding inputs at random.
  Future<bool> isWritable(String model, String field) async {
    final fields = await fieldsOf(model);
    if (fields.isEmpty) return true;
    final describe = fields[field];
    return describe != null && describe['readonly'] != true;
  }

  /// Drops entries [model] will not accept, so one of them cannot take the
  /// whole write down with it. Returns [values] untouched when the schema is
  /// unknown, leaving behaviour unchanged rather than silently sending less.
  Future<Map<String, dynamic>> writableValues(
    String model,
    Map<String, dynamic> values,
  ) async {
    if (values.isEmpty) return values;
    final fields = await fieldsOf(model);
    if (fields.isEmpty) return values;

    final accepted = <String, dynamic>{};
    values.forEach((key, value) {
      final describe = fields[key];
      if (describe == null) return;
      if (describe['readonly'] == true) return;
      accepted[key] = value;
    });
    return accepted;
  }

  /// Keeps only the field names [model] defines, for a read.
  ///
  /// Reads are all-or-nothing too: asking for one field the model dropped
  /// fails the whole request and takes every other value with it.
  Future<List<String>> readableFields(String model, List<String> wanted) async {
    final fields = await fieldsOf(model);
    if (fields.isEmpty) return wanted;
    return wanted.where(fields.containsKey).toList();
  }
}
