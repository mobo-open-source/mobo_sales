import 'odoo_compat.dart';

/// A value that changes whenever the signed-in user's profile changes on the
/// server, for deciding whether a cached copy is still current; null when it
/// cannot be read.
///
/// A user's name, login and email live on the `res.users` row, but the photo,
/// phone, address and the rest live on the linked `res.partner`. Changing the
/// photo on the web writes the partner and leaves the user's `write_date`
/// where it was, so a cache keyed on the user's date alone keeps showing the
/// old photo. The stamp joins both dates.
Future<String?> profileVersionStamp(
  OdooCallKw callKw, {
  required int uid,
  int? partnerId,
}) async {
  Future<String?> writeDate(String model, int id) async {
    try {
      final rows = await callKw({
        'model': model,
        'method': 'search_read',
        'args': [
          [
            ['id', '=', id],
          ],
          ['write_date'],
        ],
        'kwargs': {'limit': 1},
      });
      if (rows is List && rows.isNotEmpty && rows.first is Map) {
        final value = (rows.first as Map)['write_date'];
        return value is String && value.isNotEmpty ? value : null;
      }
    } catch (_) {}
    return null;
  }

  final userDate = await writeDate('res.users', uid);
  if (userDate == null) return null;
  final partnerDate = partnerId == null
      ? null
      : await writeDate('res.partner', partnerId);
  return '$userDate|${partnerDate ?? ''}';
}

/// The partner id inside a `res.users` row's `partner_id` many2one
/// (`[id, name]`), or null.
int? partnerIdOf(Map<String, dynamic>? userData) {
  final value = userData?['partner_id'];
  if (value is List && value.isNotEmpty && value.first is int) {
    return value.first as int;
  }
  if (value is int) return value;
  return null;
}

/// The key the profile of [userId] on [database] is cached under, in shared
/// preferences. One key per account: a single shared key would hand the last
/// account's name, email and photo to whichever account opens the screen next.
String profileCacheKey({required String database, required int userId}) {
  final cleanDb = database.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
  return 'user_profile_${cleanDb}_$userId';
}
