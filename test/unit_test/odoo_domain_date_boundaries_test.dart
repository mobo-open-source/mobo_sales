import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mobo_sales/utils/invoice_filter_domain.dart';
import 'package:mobo_sales/utils/odoo_date.dart';

/// Reading a date out of Odoo and sending one back in are the same bug twice.
///
/// A `Datetime` column holds naive UTC, so a filter built from the user's local
/// midnight has to be converted before it is sent — otherwise Odoo reads the
/// local wall clock as UTC and the window lands hours off. East of UTC that
/// loses records at the start of the range; west of it, records from the day
/// before leak in.
///
/// A `Date` column has no timezone at all, so the same conversion applied to it
/// is the bug rather than the fix: it turns the 6th into the 5th.
void main() {
  group('a Datetime filter boundary is converted to UTC', () {
    test('local midnight is sent as the matching UTC instant', () {
      final localMidnight = DateTime(2026, 11, 6);

      expect(
        OdooDate.formatDatetime(localMidnight),
        DateFormat('yyyy-MM-dd HH:mm:ss').format(localMidnight.toUtc()),
      );
    });

    test('away from UTC that is genuinely different text', () {
      final localMidnight = DateTime(2026, 11, 6);

      if (localMidnight.timeZoneOffset == Duration.zero) {
        return; // nothing to shift; the assertion above already covers it
      }
      expect(
        OdooDate.formatDatetime(localMidnight),
        isNot('2026-11-06 00:00:00'),
        reason: 'sending the local wall clock is what this prevents',
      );
    });

    test('the end of a range keeps its 23:59:59, shifted', () {
      final endOfDay = DateTime(2026, 11, 20, 23, 59, 59);

      expect(
        OdooDate.formatDatetime(endOfDay),
        DateFormat('yyyy-MM-dd HH:mm:ss').format(endOfDay.toUtc()),
      );
    });
  });

  group('a Date filter boundary is left alone', () {
    test('invoice_date is the day the user picked', () {
      final domain = invoiceListDomain(
        startDate: DateTime(2026, 11, 6),
        endDate: DateTime(2026, 11, 20),
      );

      expect(domain, contains(equals(['invoice_date', '>=', '2026-11-06'])));
      expect(domain, contains(equals(['invoice_date', '<=', '2026-11-20'])));
    });

    test('an overdue cutoff is today, not today in UTC', () {
      final domain = invoiceListDomain(
        overdueOnly: true,
        today: DateTime(2026, 11, 6),
      );

      expect(domain, contains(equals(['invoice_date_due', '<', '2026-11-06'])));
    });
  });
}
