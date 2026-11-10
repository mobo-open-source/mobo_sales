import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/odoo_date.dart';

/// Getting Odoo datetimes wrong by a timezone is the classic Odoo mobile bug,
/// so these tests are written to be correct in **any** local zone: the oracle
/// is always `DateTime.utc(...).toLocal()`, which is the definition of what
/// naive-UTC parsing should produce.
///
/// The zone-specific cases (a half-hour offset, and a DST boundary) are gated
/// on the runner's actual zone and are exercised by `tool/test_timezones.sh`,
/// which runs this file under `UTC`, `Asia/Kolkata` (+05:30) and
/// `America/New_York` (DST).
void main() {
  final Duration localOffset = DateTime(2026, 6, 1).timeZoneOffset;

  group('parseDatetime — naive UTC in, local out', () {
    test('parses the wire format as UTC and converts to local', () {
      final DateTime? got = OdooDate.parseDatetime('2026-09-07 05:15:00');
      expect(got, DateTime.utc(2026, 9, 7, 5, 15).toLocal());
      expect(got!.isUtc, isFalse);
    });

    test('is not a no-op unless the runner really is on UTC', () {
      final DateTime? got = OdooDate.parseDatetime('2026-09-07 05:15:00');
      if (localOffset == Duration.zero) {
        expect(got!.hour, 5);
      } else {
        expect(
          got!.hour == 5 && got.minute == 15,
          isFalse,
          reason: 'a naive-UTC string was treated as local — this is the bug',
        );
      }
    });

    test('tolerates an ISO T separator', () {
      expect(
        OdooDate.parseDatetime('2026-09-07T05:15:00'),
        DateTime.utc(2026, 9, 7, 5, 15).toLocal(),
      );
    });

    test('tolerates fractional seconds', () {
      expect(
        OdooDate.parseDatetime('2026-09-07 05:15:00.123456'),
        DateTime.utc(2026, 9, 7, 5, 15).toLocal(),
      );
    });

    test('honours an explicit offset when one is present', () {
      // Already-offset strings come from a few Odoo endpoints and from
      // write-backs; Dart's parser handles them, and the result must still be
      // the same instant.
      expect(
        OdooDate.parseDatetime('2026-09-07T05:15:00Z'),
        DateTime.utc(2026, 9, 7, 5, 15).toLocal(),
      );
    });

    test('returns null for Odoo\'s absent values, never throws', () {
      expect(OdooDate.parseDatetime(null), isNull);
      expect(OdooDate.parseDatetime(false), isNull);
      expect(OdooDate.parseDatetime('false'), isNull);
      expect(OdooDate.parseDatetime(''), isNull);
      expect(OdooDate.parseDatetime('   '), isNull);
      expect(OdooDate.parseDatetime('not a date'), isNull);
      expect(OdooDate.parseDatetime(12345), isNull);
    });
  });

  group('formatDatetime — local in, naive UTC out', () {
    test('is the exact inverse of parseDatetime', () {
      const String wire = '2026-09-07 05:15:00';
      expect(
        OdooDate.formatDatetime(OdooDate.parseDatetime(wire)!),
        wire,
      );
    });

    test('round-trips across a whole year of instants', () {
      // Any drift in either direction shows up as an inequality here,
      // including across whatever DST transitions the runner's zone has.
      for (int day = 1; day <= 365; day += 7) {
        final DateTime instant = DateTime.utc(2026).add(
          Duration(days: day, hours: 13, minutes: 47),
        );
        final String wire = OdooDate.formatDatetime(instant);
        expect(
          OdooDate.parseDatetime(wire),
          instant.toLocal(),
          reason: 'round-trip drifted on day $day',
        );
      }
    });

    test('converts to UTC before dropping the offset', () {
      final DateTime local = DateTime.utc(2026, 9, 7, 5, 15).toLocal();
      expect(OdooDate.formatDatetime(local), '2026-09-07 05:15:00');
    });
  });

  group('Date fields are NOT timezone-shifted', () {
    test('parseDate keeps the calendar day Odoo sent', () {
      final DateTime? got = OdooDate.parseDate('2026-09-07');
      expect(got, isNotNull);
      expect(got!.year, 2026);
      expect(got.month, 9);
      expect(
        got.day,
        7,
        reason: 'shifting a Date is how a due date becomes the 6th for half '
            'the world',
      );
      expect(got.hour, 0);
      expect(got.isUtc, isFalse);
    });

    test('a Date near midnight does not roll over in any zone', () {
      // The failure mode: parsing '2026-01-01' as UTC midnight then converting
      // to local, which lands on 2025-12-31 for any negative offset.
      for (final String wire in <String>[
        '2026-01-01',
        '2026-12-31',
        '2026-03-08',
        '2026-11-01',
      ]) {
        final DateTime got = OdooDate.parseDate(wire)!;
        expect(OdooDate.formatDate(got), wire, reason: wire);
      }
    });

    test('parseDate ignores a time component if Odoo sends one', () {
      expect(OdooDate.parseDate('2026-09-07 23:59:59')!.day, 7);
      expect(OdooDate.parseDate('2026-09-07T23:59:59')!.day, 7);
    });

    test('formatDate uses the local calendar date, no conversion', () {
      expect(OdooDate.formatDate(DateTime(2026, 9, 7, 23, 59)), '2026-09-07');
      expect(OdooDate.formatDate(DateTime(2026, 9, 7, 0, 1)), '2026-09-07');
    });

    test('returns null for absent values', () {
      expect(OdooDate.parseDate(null), isNull);
      expect(OdooDate.parseDate(false), isNull);
      expect(OdooDate.parseDate('false'), isNull);
      expect(OdooDate.parseDate('2026-13-45'), isNull);
    });

    test('a Datetime and a Date on the same wire day can differ — correctly', () {
      // This is the whole point of the two functions being separate.
      final DateTime dt = OdooDate.parseDatetime('2026-09-07 23:30:00')!;
      final DateTime d = OdooDate.parseDate('2026-09-07')!;
      expect(d.day, 7);
      if (localOffset > Duration.zero) {
        expect(
          dt.day,
          8,
          reason: 'a 23:30 UTC timestamp is the next day at a positive offset',
        );
      }
    });
  });

  group('display formatting', () {
    test('formats a Datetime in local time', () {
      final String? got = OdooDate.formatForDisplay(
        '2026-09-07 05:15:00',
        pattern: 'yyyy-MM-dd HH:mm',
      );
      final DateTime local = DateTime.utc(2026, 9, 7, 5, 15).toLocal();
      expect(got, '${OdooDate.formatDate(local)} '
          '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}');
    });

    test('formats a Date without shifting', () {
      expect(
        OdooDate.formatDateForDisplay('2026-09-07', pattern: 'yyyy-MM-dd'),
        '2026-09-07',
      );
    });

    test('returns null rather than a placeholder for absent input', () {
      expect(OdooDate.formatForDisplay(false), isNull);
      expect(OdooDate.formatDateForDisplay(null), isNull);
    });
  });

  group('now/today helpers', () {
    test('nowForOdoo is parseable and round-trips', () {
      final String wire = OdooDate.nowForOdoo();
      expect(OdooDate.parseDatetime(wire), isNotNull);
      expect(wire, matches(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'));
    });

    test('todayForOdoo matches the local calendar day', () {
      final DateTime now = DateTime.now();
      expect(OdooDate.todayForOdoo(), OdooDate.formatDate(now));
    });
  });

  group('zone-specific cases (gated on the runner\'s zone)', () {
    test('+05:30 — a half-hour offset does not truncate to the hour', () {
      if (localOffset != const Duration(hours: 5, minutes: 30)) {
        return; // run via tool/test_timezones.sh with TZ=Asia/Kolkata
      }
      expect(
        OdooDate.parseDatetime('2026-09-07 05:15:00'),
        DateTime(2026, 9, 7, 10, 45),
        reason: 'IST is +5:30, so 05:15Z is 10:45 — an hours-only '
            'implementation would give 10:15',
      );
      expect(
        OdooDate.formatDatetime(DateTime(2026, 9, 7, 10, 45)),
        '2026-09-07 05:15:00',
      );
    });

    test('DST — the same wall clock maps to different instants', () {
      // America/New_York: EST (-5) before 2026-03-08 07:00Z, EDT (-4) after.
      final bool isNewYork =
          DateTime(2026).timeZoneOffset == const Duration(hours: -5) &&
          DateTime(2026, 7).timeZoneOffset == const Duration(hours: -4);
      if (!isNewYork) {
        return; // run via tool/test_timezones.sh with TZ=America/New_York
      }

      // 06:30Z on the transition day is 01:30 EST (still standard time).
      expect(
        OdooDate.parseDatetime('2026-03-08 06:30:00'),
        DateTime.utc(2026, 3, 8, 6, 30).toLocal(),
      );
      expect(OdooDate.parseDatetime('2026-03-08 06:30:00')!.hour, 1);

      // 07:30Z is 03:30 EDT — 02:xx never exists on this date.
      expect(OdooDate.parseDatetime('2026-03-08 07:30:00')!.hour, 3);

      // A winter and a summer timestamp with the same wall clock differ by an
      // hour in UTC, and the round-trip must survive both.
      for (final String wire in <String>[
        '2026-01-15 12:00:00',
        '2026-07-15 12:00:00',
        '2026-03-08 06:30:00',
        '2026-03-08 07:30:00',
        '2026-11-01 05:30:00',
        '2026-11-01 06:30:00',
      ]) {
        expect(
          OdooDate.formatDatetime(OdooDate.parseDatetime(wire)!),
          wire,
          reason: 'DST round-trip failed for $wire',
        );
      }

      // And a Date on the transition day is still that date.
      expect(
        OdooDate.formatDate(OdooDate.parseDate('2026-03-08')!),
        '2026-03-08',
      );
    });
  });
}
