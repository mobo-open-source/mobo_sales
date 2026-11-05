import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/delivery_lot_service.dart';

/// The same names Odoo's own `generate_lot_names` gives (checked against Odoo
/// 18, 19 and 20 in the backend): the last run of digits counts up and keeps
/// its zero padding.
void main() {
  test('counts up the last number and keeps the zero padding', () {
    expect(generateLotNamesLocally('ZSN-009', 3), [
      'ZSN-009',
      'ZSN-010',
      'ZSN-011',
    ]);
    expect(generateLotNamesLocally('SN0099', 2), ['SN0099', 'SN0100']);
  });

  test('a prefix and a suffix are kept around the number', () {
    expect(generateLotNamesLocally('BAV023B00001S', 2), [
      'BAV023B00001S',
      'BAV023B00002S',
    ]);
  });

  test('a name with no number gets a zero added first', () {
    expect(generateLotNamesLocally('ABC', 3), ['ABC0', 'ABC1', 'ABC2']);
  });

  test('nothing is made for a count of zero or less', () {
    expect(generateLotNamesLocally('SN-001', 0), isEmpty);
    expect(generateLotNamesLocally('SN-001', -2), isEmpty);
  });
}
