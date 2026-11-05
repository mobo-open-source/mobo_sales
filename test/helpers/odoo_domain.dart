/// Evaluates an Odoo domain against plain records, so a filter is tested by
/// what it returns.
///
/// Prefix notation as Odoo reads it (`|`, `&`, `!`; leaves are ANDed). A
/// many2one value is a `[id, name]` pair and compares by its id. As in Odoo,
/// records with `active == false` are hidden unless the domain names `active`.
class OdooDomain {
  OdooDomain(this.records);

  final List<Map<String, dynamic>> records;

  /// Fields the fake does not have; naming one is an error, as on a server.
  Set<String> missingFields = {};

  List<Map<String, dynamic>> search(List domain) {
    final namesActive = _mentions(domain, 'active');
    return [
      for (final r in records)
        if ((namesActive || r['active'] != false) && _matches(r, domain)) r,
    ];
  }

  bool _mentions(List domain, String field) => domain.any(
    (item) => item is List && item.isNotEmpty && item.first == field,
  );

  bool _matches(Map<String, dynamic> record, List domain) {
    var i = 0;
    bool next() {
      if (i >= domain.length) throw StateError('domain ends early: $domain');
      final item = domain[i++];
      if (item == '|') {
        final a = next();
        final b = next();
        return a || b;
      }
      if (item == '&') {
        final a = next();
        final b = next();
        return a && b;
      }
      if (item == '!') return !next();
      return _leaf(record, item as List);
    }

    var ok = true;
    while (i < domain.length) {
      ok = next() && ok;
    }
    return ok;
  }

  dynamic _value(Map<String, dynamic> r, String field) {
    final v = r[field];
    if (v is List && v.length == 2 && v.first is int) return v.first;
    return v;
  }

  bool _leaf(Map<String, dynamic> record, List leaf) {
    if (leaf.length != 3) throw StateError('bad leaf $leaf');
    final field = leaf[0] as String;
    if (missingFields.contains(field)) {
      throw Exception('Invalid field $field');
    }
    final op = leaf[1] as String;
    final want = leaf[2];
    final have = _value(record, field);
    int cmp() {
      if (have == null || have == false) return -2;
      return (have as Comparable).compareTo(want);
    }

    switch (op) {
      case '=':
        return have == want;
      case '!=':
        return have != want;
      case 'in':
        return (want as List).contains(have);
      case '<':
        return cmp() == -1;
      case '<=':
        return cmp() == -1 || cmp() == 0;
      case '>':
        return cmp() == 1;
      case '>=':
        return cmp() == 1 || cmp() == 0;
      case 'ilike':
        return have is String &&
            have.toLowerCase().contains((want as String).toLowerCase());
    }
    throw StateError('operator $op is not handled by the fake');
  }
}
