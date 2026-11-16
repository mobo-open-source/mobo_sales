/// The companies a user may work in, as `/web/session/get_session_info` reports
/// them.
///
/// Odoo's own web client draws its company switcher from this, and it is the
/// steadier source of the two the app could use:
///
///  * `res.users.read(['company_id', 'company_ids'])` goes through Odoo's
///    override of `read` on `res.users`, which only elevates to sudo when
///    *every* requested field is in `SELF_READABLE_FIELDS`. `company_ids` is
///    not in that list in 17, 18 or 19, and 20 dropped the mechanism, so asking
///    for both fields at once runs the read under the user's own rights and a
///    restricted user gets nothing back.
///  * `session_info` is built for the logged-in user by the server — from
///    `user.company_ids` in 17 and 18, and through `.sudo()` in 19 and 20 — so
///    there is no access decision to lose.
///
/// The shape is the same in 17.0, 18.0, 19.0 and 20.0:
///
/// ```json
/// "user_companies": {
///   "current_company": 1,
///   "allowed_companies": {"1": {"id": 1, "name": "My Company", ...}}
/// }
/// ```
///
/// so this needs no per-version dialect. 19 and 20 add `currency_id` to each
/// entry, which is extra, not different.
class SessionCompanies {
  const SessionCompanies({required this.companies, required this.currentId});

  /// `{id, name}` per company, ordered by Odoo's `sequence` then name, which is
  /// the order its own switcher uses.
  final List<Map<String, dynamic>> companies;

  /// The company the server considers active, or null when it did not say.
  final int? currentId;

  bool get isEmpty => companies.isEmpty;

  List<int> get ids => companies.map((c) => c['id'] as int).toList();
}

/// Reads [sessionInfo]'s `user_companies`, or null when it holds none.
///
/// Null means "this reply does not tell us", which is not the same as "the user
/// has no companies" — the caller has to keep the two apart, because showing
/// an empty company list for a failed read is what made a working account look
/// like it had no companies at all.
SessionCompanies? parseSessionCompanies(Map<String, dynamic>? sessionInfo) {
  final raw = sessionInfo?['user_companies'];
  if (raw is! Map) return null;

  final allowed = raw['allowed_companies'];
  if (allowed is! Map || allowed.isEmpty) return null;

  final parsed = <Map<String, dynamic>>[];
  for (final entry in allowed.entries) {
    final value = entry.value;
    if (value is! Map) continue;

    // The key is the id as a string; the body repeats it as an int. Either can
    // be missing on a trimmed reply, so take whichever is there.
    final id = _asInt(value['id']) ?? _asInt(entry.key);
    if (id == null) continue;

    final name = value['name'];
    parsed.add({
      'id': id,
      'name': name is String && name.isNotEmpty ? name : 'Company $id',
      if (_asInt(value['sequence']) != null)
        'sequence': _asInt(value['sequence']),
    });
  }

  if (parsed.isEmpty) return null;

  parsed.sort((a, b) {
    final bySequence = ((a['sequence'] as int?) ?? 0).compareTo(
      (b['sequence'] as int?) ?? 0,
    );
    if (bySequence != 0) return bySequence;
    return (a['name'] as String).compareTo(b['name'] as String);
  });

  return SessionCompanies(
    companies: parsed,
    currentId: _asInt(raw['current_company']),
  );
}

/// Odoo writes ids as ints over JSON-RPC, but a trimmed or proxied reply can
/// carry them as strings, and `current_company` is `false` when unset.
int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}
