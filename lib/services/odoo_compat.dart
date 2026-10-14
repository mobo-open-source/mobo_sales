import '../utils/odoo_version.dart';
import 'odoo_session_manager.dart';

/// Sends one `call_kw` payload (`model`, `method`, `args`, `kwargs`).
typedef OdooCallKw = Future<dynamic> Function(Map<String, dynamic> payload);

/// ORM calls whose shape differs between Odoo versions, behind one interface.
///
/// Each helper takes the call the way the app has always made it and returns
/// the result in the shape the app has always read, so a screen never has to
/// know which Odoo it is talking to. The version decision itself lives in
/// `odoo_version.dart`; the payload building and result reshaping live here as
/// plain functions so they can be tested without a server.
class OdooCompat {
  OdooCompat._();

  // -------------------------------------------------------------------------
  // Grouped reads
  // -------------------------------------------------------------------------

  /// `read_group` in the Odoo 17/18 result shape, on every version.
  ///
  /// [fields], [groupby], [orderby], [limit] mean what they did in the old
  /// `read_group(domain, fields, groupby, …, lazy=False)`; groups are always
  /// split by every [groupby] entry (`lazy` false), which is the only way the
  /// app has used it. Each returned row carries:
  ///
  /// * the group value under each [groupby] spec — `[id, name]` for a
  ///   many2one, the display label for a date granularity (`'October 2026'`),
  ///   the raw value otherwise;
  /// * `__count`;
  /// * each aggregate under its field name (`amount_total:sum` -> `amount_total`)
  ///   and under its full spec;
  /// * `__domain`, the domain selecting the group.
  ///
  /// Odoo 19 deprecated `read_group` and Odoo 20 gave it a new signature and
  /// tuple results, so from 19 this goes through `formatted_read_group`, which
  /// is identical in 19 and 20. An unknown version tries the old call and
  /// falls back when the server says it does not understand it.
  static Future<List<Map<String, dynamic>>> readGroup({
    required String model,
    required List<dynamic> domain,
    required List<String> fields,
    required List<String> groupby,
    String? orderby,
    int? limit,
    Map<String, dynamic>? context,
    OdooCallKw? callKw,
    int? generation,
  }) async {
    final call = callKw ?? OdooSessionManager.safeCallKw;
    final gen = generation ?? await OdooSessionManager.serverGeneration();

    Future<List<Map<String, dynamic>>> viaFormatted() async {
      final aggregates = readGroupAggregates(fields);
      final result = await call(
        formattedReadGroupPayload(
          model: model,
          domain: domain,
          groupby: groupby,
          aggregates: aggregates,
          orderby: orderby,
          limit: limit,
          context: context,
        ),
      );
      return normalizeFormattedGroups(
        result,
        groupby: groupby,
        aggregates: aggregates,
      );
    }

    Future<List<Map<String, dynamic>>> viaClassic() async {
      final result = await call({
        'model': model,
        'method': 'read_group',
        'args': [domain],
        'kwargs': {
          'fields': fields,
          'groupby': groupby,
          'lazy': false,
          if (orderby != null) 'orderby': orderby,
          if (limit != null) 'limit': limit,
          if (context != null) 'context': context,
        },
      });
      return result is List
          ? [
              for (final row in result)
                if (row is Map) Map<String, dynamic>.from(row),
            ]
          : <Map<String, dynamic>>[];
    }

    if (odooUsesFormattedReadGroup(gen)) return viaFormatted();
    if (gen != 0) return viaClassic();

    // Unknown version: the classic call is what every release up to 18 takes.
    // Odoo 20 refuses it by its arguments, so retry the other way then.
    try {
      return await viaClassic();
    } catch (e) {
      if (looksLikeReadGroupSignatureError(e)) return viaFormatted();
      rethrow;
    }
  }

  /// Whether [error] is a server refusing the old `read_group` arguments.
  static bool looksLikeReadGroupSignatureError(Object error) {
    final text = error.toString();
    return text.contains('unexpected keyword argument') ||
        text.contains('missing 1 required positional argument') ||
        text.contains('read_group');
  }

  /// The aggregate specs (`field:agg`) among an old-style `read_group` `fields`
  /// list. Plain field names there are the group-by fields themselves or fields
  /// the old call summed implicitly; the app always asks for sums explicitly.
  /// `alias:agg(field)` is rewritten to `field:agg`.
  static List<String> readGroupAggregates(List<String> fields) {
    final aggregates = <String>[];
    for (final spec in fields) {
      final alias = RegExp(r'^(\w+):(\w+)\((\w+)\)$').firstMatch(spec);
      if (alias != null) {
        aggregates.add('${alias.group(3)}:${alias.group(2)}');
      } else if (spec.contains(':') && !spec.contains('(')) {
        aggregates.add(spec);
      }
    }
    return aggregates;
  }

  /// The `formatted_read_group` payload for an old-style grouped read.
  static Map<String, dynamic> formattedReadGroupPayload({
    required String model,
    required List<dynamic> domain,
    required List<String> groupby,
    required List<String> aggregates,
    String? orderby,
    int? limit,
    Map<String, dynamic>? context,
  }) {
    return {
      'model': model,
      'method': 'formatted_read_group',
      'args': [domain],
      'kwargs': {
        'groupby': groupby,
        'aggregates': [...aggregates, '__count'],
        if (orderby != null) 'order': orderby,
        if (limit != null) 'limit': limit,
        if (context != null) 'context': context,
      },
    };
  }

  static const _timeGranularities = {
    'hour',
    'day',
    'week',
    'month',
    'quarter',
    'year',
  };

  /// Reshapes `formatted_read_group` rows into the old `read_group` shape; see
  /// [readGroup] for what a row holds.
  static List<Map<String, dynamic>> normalizeFormattedGroups(
    dynamic rows, {
    required List<String> groupby,
    required List<String> aggregates,
  }) {
    if (rows is! List) return <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);

      for (final spec in groupby) {
        final value = row[spec];
        final granularity = spec.contains(':') ? spec.split(':').last : null;
        // A date group arrives as [startDate, label]; the old call gave just
        // the label, and that is what the app parses.
        if (value is List &&
            value.length == 2 &&
            granularity != null &&
            _timeGranularities.contains(granularity)) {
          row[spec] = value[1];
        }
      }

      row['__count'] = row['__count'] ?? 0;
      for (final spec in aggregates) {
        row[spec.split(':').first] = row[spec];
      }
      row['__domain'] = row['__extra_domain'] ?? const [];
      out.add(row);
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Access checks
  // -------------------------------------------------------------------------

  /// Whether the current user may perform [operation] (`read`, `create`,
  /// `write`, `unlink`) on [model], as the old `check_access_rights` answered.
  ///
  /// `check_access_rights` was deprecated in Odoo 19 and removed in 20, where
  /// `has_access` is the public check. A failed *call* is not a "no": it
  /// throws, so a caller can tell "not allowed" from "could not ask".
  static Future<bool> hasAccess({
    required String model,
    required String operation,
    OdooCallKw? callKw,
    int? generation,
  }) async {
    final call = callKw ?? OdooSessionManager.safeCallKw;
    final gen = generation ?? await OdooSessionManager.serverGeneration();

    Future<bool> viaHasAccess() async {
      final result = await call({
        'model': model,
        'method': 'has_access',
        // An instance method over RPC: an empty id list asks about the model.
        'args': [<int>[], operation],
        'kwargs': <String, dynamic>{},
      });
      return result == true;
    }

    Future<bool> viaCheckAccessRights() async {
      final result = await call({
        'model': model,
        'method': 'check_access_rights',
        'args': [operation],
        'kwargs': {'raise_exception': false},
      });
      return result == true;
    }

    if (odooUsesHasAccess(gen)) return viaHasAccess();
    if (gen != 0) return viaCheckAccessRights();

    // Unknown version: the old check first, the new one if it is gone.
    try {
      return await viaCheckAccessRights();
    } catch (e) {
      final text = e.toString();
      if (text.contains('check_access_rights') ||
          text.contains('has no attribute') ||
          text.contains('does not exist')) {
        return viaHasAccess();
      }
      rethrow;
    }
  }
}
