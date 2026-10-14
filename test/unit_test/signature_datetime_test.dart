import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/widgets/signature_widget.dart';

/// Odoo keeps `signed_on` in UTC (`2026-10-01 10:00:00`, no zone). The tab
/// shows it in the user's time zone and writes it back in UTC, whatever zone
/// the phone is in.
void main() {
  test('a datetime from Odoo is read as UTC', () {
    final moment = parseOdooDatetime('2026-10-01 10:00:00')!;
    final utc = moment.toUtc();
    expect(
      [utc.year, utc.month, utc.day, utc.hour, utc.minute],
      [2026, 10, 1, 10, 0],
    );
    expect(moment.isUtc, isFalse, reason: 'shown in the local zone');
  });

  test('what is written back is the same moment, in UTC', () {
    expect(
      formatOdooDatetime(parseOdooDatetime('2026-10-01 10:00:00')!),
      '2026-10-01 10:00:00',
    );
    // A moment picked in the user's zone goes out as its UTC time.
    final picked = DateTime.utc(2026, 3, 5, 23, 30).toLocal();
    expect(formatOdooDatetime(picked), '2026-03-05 23:30:00');
  });

  test('a zone, a T and a blank are all understood', () {
    expect(
      parseOdooDatetime('2026-10-01T10:00:00Z')!.toUtc(),
      DateTime.utc(2026, 10, 1, 10),
    );
    expect(parseOdooDatetime('  '), isNull);
    expect(parseOdooDatetime('not a date'), isNull);
  });
}
