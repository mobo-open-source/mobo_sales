import 'dart:async';

/// What Odoo's own form fills in on a new record, for the app to send along
/// when it creates one.
///
/// Odoo's web client never builds a record from scratch. Its form first asks
/// the server — `onchange` with no changed field — and the server answers with
/// every default, every computed value and whatever the onchange methods set,
/// those of the modules installed on that database included. The app builds
/// its records itself, so a value that a database fills only through its form
/// was missing from what the app saved, and a rule that needs it refused the
/// record.
///
/// This asks the server the same question, the same way, for the many2one
/// fields the caller does not send, and returns the answers to add. On a
/// standard database these are the values `create` would compute on its own,
/// so the saved record does not change; on a customised one the record gets
/// what the web form would have given it.
///
/// It never stands in the way of a save: when the server cannot answer — an
/// older or unusual server, a module error, no reply in time — it returns
/// nothing, and the caller creates the record exactly as it did before.
///
/// The call is the same on Odoo 17 to 20:
/// `model.onchange([], values, [], fields_spec)`, answering a many2one asked
/// for with `{}` as its id, or `false` when empty.
class OdooFormDefaults {
  OdooFormDefaults._();

  /// The candidate fields of each model, per account: the schema does not
  /// change while the app runs, and asking for it before every save would
  /// double the cost of the call.
  static final Map<String, List<String>> _candidates = {};

  /// Values for the many2one fields of a new [model] record that [values]
  /// does not set, as Odoo's own form would fill them in.
  ///
  /// [values] is what the caller is about to create, without its one2many and
  /// many2many lines. [context] must be the one the record is created with,
  /// so the answer is for the same company. [accountKey] names the database
  /// and user the schema is cached under.
  ///
  /// Only fields the record can be saved with are returned — stored, not
  /// read-only — and only those the server gave a value, so a field left empty
  /// is still left to `create`.
  static Future<Map<String, int>> missingMany2oneValues({
    required Future<dynamic> Function(Map<String, dynamic> params) callKw,
    required String model,
    required Map<String, dynamic> values,
    required String accountKey,
    Map<String, dynamic> context = const {},
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      return await _ask(
        callKw: callKw,
        model: model,
        values: values,
        accountKey: accountKey,
        context: context,
      ).timeout(timeout);
    } catch (_) {
      return const {};
    }
  }

  static Future<Map<String, int>> _ask({
    required Future<dynamic> Function(Map<String, dynamic> params) callKw,
    required String model,
    required Map<String, dynamic> values,
    required String accountKey,
    required Map<String, dynamic> context,
  }) async {
    final cacheKey = '$accountKey|$model';
    var candidates = _candidates[cacheKey];
    if (candidates == null) {
      final fields = await callKw({
        'model': model,
        'method': 'fields_get',
        'args': [],
        'kwargs': {
          'attributes': ['type', 'store', 'readonly'],
          'context': context,
        },
      });
      if (fields is! Map) return const {};
      candidates = savableMany2oneFields(fields);
      _candidates[cacheKey] = candidates;
    }

    final wanted = [
      for (final name in candidates)
        if (!values.containsKey(name)) name,
    ];
    if (wanted.isEmpty) return const {};

    final answer = await callKw({
      'model': model,
      'method': 'onchange',
      'args': [
        <int>[],
        values,
        <String>[],
        {for (final name in wanted) name: <String, dynamic>{}},
      ],
      'kwargs': {'context': context},
    });
    if (answer is! Map) return const {};
    final filled = answer['value'];
    if (filled is! Map) return const {};
    return many2oneIdsFrom(filled, wanted);
  }

  /// The fields of a `fields_get` answer that are many2one, stored and not
  /// read-only: those a record can be created with.
  static List<String> savableMany2oneFields(Map fields) {
    final out = <String>[];
    fields.forEach((name, definition) {
      if (name is! String || definition is! Map) return;
      if (definition['type'] != 'many2one') return;
      if (definition['store'] != true) return;
      if (definition['readonly'] == true) return;
      out.add(name);
    });
    out.sort();
    return out;
  }

  /// The ids an `onchange` answer gives for [fields], skipping those it left
  /// empty or does not mention.
  ///
  /// A many2one asked for with `{}` comes back as its id. The `[id, name]`
  /// pair of a plain `read` and the `{id, display_name}` map of a richer
  /// spec are read too, so a server that answers in either still works.
  static Map<String, int> many2oneIdsFrom(Map filled, Iterable<String> fields) {
    final out = <String, int>{};
    for (final name in fields) {
      final id = _idOf(filled[name]);
      if (id != null) out[name] = id;
    }
    return out;
  }

  static int? _idOf(Object? value) {
    Object? id = value;
    if (value is List && value.isNotEmpty) id = value.first;
    if (value is Map) id = value['id'];
    return id is int && id > 0 ? id : null;
  }

  /// Forgets the cached schemas, as on logout or a switch of account.
  static void clearCache() => _candidates.clear();
}
