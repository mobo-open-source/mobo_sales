import 'package:intl/intl.dart';

/// Conversion between Odoo's datetime strings and Dart `DateTime`.
///
/// Getting this wrong shifts every timestamp in the app by the device's UTC
/// offset. Ported from `mobo_template`'s `OdooDate`, with its tests.
///
/// Appending `Z` to everything is correct for a `Datetime` and **wrong for a
/// `Date`**: a module full of due dates turns the 7th into the 6th west of
/// UTC.
///
/// ### The two Odoo field types behave differently
///
/// | Odoo field | wire format | timezone |
/// |---|---|---|
/// | `Datetime` | `'2026-09-07 05:15:00'` | **naive UTC** — no offset, but it *is* UTC |
/// | `Date` | `'2026-09-07'` | **no timezone at all** — a calendar date |
///
/// A `Datetime` must be shifted to local for display and back to UTC for
/// writing. A `Date` must **not** be shifted: a due date of the 7th is the 7th
/// in Kolkata and in São Paulo. Shifting it is how a due date silently becomes
/// the 6th for half the world.
abstract final class OdooDate {
  /// Odoo's `Datetime` wire format.
  static const String datetimeFormat = 'yyyy-MM-dd HH:mm:ss';

  /// Odoo's `Date` wire format.
  static const String dateFormat = 'yyyy-MM-dd';

  static final DateFormat _datetime = DateFormat(datetimeFormat);
  static final DateFormat _date = DateFormat(dateFormat);

  /// Parses an Odoo `Datetime` into a **local** `DateTime`.
  ///
  /// The string carries no offset but means UTC, so it is parsed as UTC and
  /// then converted. Returns null for null, empty, Odoo's `false`, or anything
  /// unparseable — never throws.
  static DateTime? parseDatetime(Object? raw) {
    final String? text = _clean(raw);
    if (text == null) return null;
    final String normalised = text.replaceFirst('T', ' ').split('.').first;
    try {
      return _datetime.parseUtc(normalised).toLocal();
    } on FormatException {
      final DateTime? parsed = DateTime.tryParse(text);
      return parsed?.toLocal();
    }
  }

  /// Parses an Odoo `Date` into a `DateTime` at local midnight.
  ///
  /// **No timezone shift**, deliberately — see the class docs. The result is
  /// local midnight so date arithmetic and `DateFormat` behave, but the
  /// calendar day always matches what Odoo sent.
  static DateTime? parseDate(Object? raw) {
    final String? text = _clean(raw);
    if (text == null) return null;
    final String dayOnly = text.split(' ').first.split('T').first;
    try {
      final DateTime d = _date.parseStrict(dayOnly);
      return DateTime(d.year, d.month, d.day);
    } on FormatException {
      return null;
    }
  }

  /// Formats a `DateTime` as an Odoo `Datetime` string for writing back.
  ///
  /// Converts to UTC first, then drops the offset — the inverse of
  /// [parseDatetime].
  static String formatDatetime(DateTime value) =>
      _datetime.format(value.toUtc());

  /// Formats a `DateTime` as an Odoo `Date` string.
  ///
  /// Uses the **local** calendar date with no conversion, matching
  /// [parseDate]. Passing a UTC-converted value here is the bug this exists to
  /// prevent.
  static String formatDate(DateTime value) =>
      _date.format(DateTime(value.year, value.month, value.day));

  /// Formats an Odoo `Datetime` string straight to a display string in local
  /// time, e.g. `'07 Sep 2026, 10:45'`.
  static String? formatForDisplay(
    Object? raw, {
    String pattern = 'dd MMM yyyy, HH:mm',
    String? locale,
  }) {
    final DateTime? local = parseDatetime(raw);
    if (local == null) return null;
    return DateFormat(pattern, locale).format(local);
  }

  /// Formats an Odoo `Date` string for display, e.g. `'07 Sep 2026'`.
  static String? formatDateForDisplay(
    Object? raw, {
    String pattern = 'dd MMM yyyy',
    String? locale,
  }) {
    final DateTime? day = parseDate(raw);
    if (day == null) return null;
    return DateFormat(pattern, locale).format(day);
  }

  /// Today as an Odoo `Date` string, in the device's calendar.
  static String todayForOdoo() => formatDate(DateTime.now());

  /// Now as an Odoo `Datetime` string.
  static String nowForOdoo() => formatDatetime(DateTime.now());

  /// Odoo returns `false` for an unset field, which arrives as a bool or the
  /// string `'false'`.
  static String? _clean(Object? raw) {
    if (raw == null || raw is bool) return null;
    final String text = raw.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'false') return null;
    return text;
  }
}
