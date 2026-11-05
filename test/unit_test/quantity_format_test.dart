import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/quantity_format.dart';

void main() {
  group('formatQuantity', () {
    test('whole numbers have no point', () {
      expect(formatQuantity(1), '1');
      expect(formatQuantity(1000), '1000');
      expect(formatQuantity(0), '0');
    });

    test('large quantities are written out, never in exponent form', () {
      expect(formatQuantity(10000000), '10000000');
      expect(formatQuantity(1234567890), '1234567890');
      expect(formatQuantity(123456789012), '123456789012');
      expect(formatQuantity(1e15), '1000000000000000');
      expect(formatQuantity(1e21), '1000000000000000000000');
      expect(formatQuantity(1e25).contains('e'), isFalse);
    });

    test('fractions keep their digits and lose trailing zeros', () {
      expect(formatQuantity(2.5), '2.5');
      expect(formatQuantity(0.125), '0.125');
      expect(formatQuantity(12345678.5), '12345678.5');
      expect(formatQuantity(1.50), '1.5');
    });

    test('float noise is not shown', () {
      expect(formatQuantity(1.1 - 1), '0.1');
      expect(formatQuantity(0.1 + 0.2), '0.3');
      expect(formatQuantity(3 * 1.1), '3.3');
    });

    test('nothing odd for a value that is not a quantity', () {
      expect(formatQuantity(double.nan), '0');
      expect(formatQuantity(double.infinity), '0');
      expect(formatQuantity(-0.0), '0');
    });
  });

  group('stepQuantity', () {
    test('adds and subtracts one', () {
      expect(stepQuantity('5', 1), '6');
      expect(stepQuantity('5', -1), '4');
    });

    test('keeps fractions exact', () {
      expect(stepQuantity('2.5', 1), '3.5');
      expect(stepQuantity('2.5', -1), '1.5');
      expect(stepQuantity('1.1', -1), '0.1');
      expect(stepQuantity('0.1', 1), '1.1');
    });

    test('large values step by one', () {
      expect(stepQuantity('9999999', 1), '10000000');
      expect(stepQuantity('10000000', -1), '9999999');
      expect(stepQuantity('123456789012', 1), '123456789013');
      expect(stepQuantity('1234567890', -1), '1234567889');
    });

    test('never goes below zero', () {
      expect(stepQuantity('0', -1), '0');
      expect(stepQuantity('0.5', -1), '0');
    });

    test('an empty or half-typed field steps from the given start', () {
      expect(stepQuantity('', 1), '1');
      expect(stepQuantity('', -1, whenEmpty: 1), '0');
      expect(stepQuantity('.', 1), '1');
      expect(stepQuantity('abc', 1), '1');
    });
  });

  group('QuantityInputFormatter', () {
    TextEditingValue type(String from, String to) =>
        QuantityInputFormatter().formatEditUpdate(
          TextEditingValue(text: from),
          TextEditingValue(text: to),
        );

    test('lets digits and one point through', () {
      expect(type('', '5').text, '5');
      expect(type('5', '5.').text, '5.');
      expect(type('5.', '5.25').text, '5.25');
      expect(type('', '.5').text, '.5');
    });

    test('takes a comma as the point', () {
      expect(type('5', '5,5').text, '5.5');
    });

    test('refuses what is not a quantity', () {
      expect(type('5', '5a').text, '5');
      expect(type('5', '-5').text, '5');
      expect(type('5.5', '5.5.').text, '5.5');
      expect(type('5', '5e3').text, '5');
    });

    test('stops at twelve whole digits and six decimals', () {
      expect(type('123456789012', '1234567890123').text, '123456789012');
      expect(type('1.123456', '1.1234567').text, '1.123456');
    });
  });

  group('quantityFontSize', () {
    test('full size while the number fits', () {
      expect(quantityFontSize(1, width: 90), 14);
      expect(quantityFontSize(8, width: 90), 14);
    });
    test('shrinks as it grows, but not below legible', () {
      expect(quantityFontSize(12, width: 90), lessThan(14));
      expect(
        quantityFontSize(16, width: 90),
        lessThan(quantityFontSize(12, width: 90)),
      );
      expect(quantityFontSize(60, width: 90), 8);
    });
    test('a wider field keeps the full size longer', () {
      expect(quantityFontSize(12, width: 200), 14);
    });
  });

  group('formatPrice', () {
    test('always has at least two decimals', () {
      expect(formatPrice(0), '0.00');
      expect(formatPrice(5), '5.00');
      expect(formatPrice(12.5), '12.50');
    });
    test('keeps more decimals when the price has them', () {
      expect(formatPrice(0.125), '0.125');
      expect(formatPrice(1.2345), '1.2345');
    });
    test('a large price is written out whole', () {
      expect(formatPrice(1234567890), '1234567890.00');
      expect(formatPrice(999999999999.99), '999999999999.99');
      expect(formatPrice(1e21), '1000000000000000000000.00');
      expect(formatPrice(1e25).contains('e'), isFalse);
    });
    test('no float noise', () {
      expect(formatPrice(0.1 + 0.2), '0.30');
    });
    test('nothing odd for a value that is not a price', () {
      expect(formatPrice(double.nan), '0.00');
      expect(formatPrice(-3), '0.00');
    });
  });
}
