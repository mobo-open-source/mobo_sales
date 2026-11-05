import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/delivery_lot_service.dart';

void main() {
  test('Odoo 17 to 19 send the text none for an untracked product', () {
    expect(normalizeTracking('none'), 'none');
    expect(normalizeTracking('lot'), 'lot');
    expect(normalizeTracking('serial'), 'serial');
  });

  test('Odoo 20 sends false for an untracked product: that is not tracked', () {
    expect(normalizeTracking(false), 'none');
    expect(normalizeTracking(null), 'none');
    expect(normalizeTracking(''), 'none');
  });
}
