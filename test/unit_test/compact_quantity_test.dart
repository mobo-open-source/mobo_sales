import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/quantity_format.dart';

void main() {
  test('compactQuantity shows lakhs and crores from one lakh up', () {
    expect(compactQuantity(99999), isNull);
    expect(compactQuantity(100000), '1 L');
    expect(compactQuantity(150000), '1.5 L');
    expect(compactQuantity(123456), '1.23 L');
    expect(compactQuantity(10000000), '1 Cr');
    expect(compactQuantity(25000000), '2.5 Cr');
    expect(compactQuantity(1e12), '100000 Cr');
    expect(compactQuantity(0), isNull);
  });
}
