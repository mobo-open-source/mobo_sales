import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/models/invoice_line_values.dart';

/// The lines of an invoice, as Odoo 17, 18, 19 and 20 take them. The fields
/// are the same in all four (account_move_line.py); what must never happen is
/// a line with no product being sent with `product_id: 0`, which Odoo 20 answers
/// with `'int' object has no attribute 'origin'`.
void main() {
  // The line from the failing Odoo 20 log: a down payment, which has no
  // product, read back from account.move.line.
  final downPayment = <String, dynamic>{
    'id': 210,
    'product_id': false,
    'name': 'Down payment of 44.0%',
    'quantity': 2.0,
    'price_unit': 379.5,
    'price_subtotal': 759.0,
    'product_uom_id': false,
    'tax_ids': <int>[],
    'discount': 0.0,
    'display_type': 'product',
  };

  /// No value of a line's `product_id` / `product_uom_id` is ever 0 or null.
  void expectNoEmptyRecords(Map<String, dynamic> values) {
    for (final key in ['product_id', 'product_uom_id']) {
      if (values.containsKey(key)) {
        expect(values[key], isA<int>(), reason: key);
        expect(values[key] as int, greaterThan(0), reason: key);
      }
    }
  }

  group('a line with no product', () {
    test('is read as a line with no product, not as product 0', () {
      final line = invoiceLineFromMoveLine(downPayment);
      expect(line['product_id'], isNull);
      expect(line['product_name'], 'Down payment of 44.0%');
      expect(line['quantity'], 2.0);
      expect(line['unit_price'], 379.5);
      expect(line['move_line_id'], 210);
    });

    test('is sent without a product or a unit of measure', () {
      final values = invoiceLineValues(invoiceLineFromMoveLine(downPayment));
      expect(values.containsKey('product_id'), isFalse);
      expect(values.containsKey('product_uom_id'), isFalse);
      expect(values['name'], 'Down payment of 44.0%');
      expect(values['quantity'], 2.0);
      expect(values['price_unit'], 379.5);
      expectNoEmptyRecords(values);
    });

    test('keeps its own taxes, even when it is only priced', () {
      final line = invoiceLineFromMoveLine({
        ...downPayment,
        'tax_ids': [4, 9],
      });
      for (final withTaxes in [true, false]) {
        expect(
          invoiceLineValues(line, withTaxes: withTaxes)['tax_ids'],
          [
            [
              6,
              0,
              [4, 9],
            ],
          ],
          reason: 'withTaxes: $withTaxes',
        );
      }
    });

    test('never sends a product id of 0, whatever the form holds', () {
      for (final empty in [0, null, false, '0', -1, '']) {
        final values = invoiceLineValues({
          'product_id': empty,
          'product_name': 'Delivery',
          'quantity': 1.0,
          'unit_price': 5.0,
          'product_uom_id': empty,
        });
        expect(values.containsKey('product_id'), isFalse, reason: '$empty');
        expect(values.containsKey('product_uom_id'), isFalse, reason: '$empty');
      }
    });
  });

  group('a line with a product', () {
    final desk = <String, dynamic>{
      'id': 11,
      'product_id': [4, '[DESK] Desk'],
      'name': '[DESK] Desk\nWith three drawers',
      'quantity': 3.0,
      'price_unit': 50.0,
      'product_uom_id': [1, 'Units'],
      'tax_ids': [2],
      'discount': 10.0,
      'display_type': 'product',
    };

    test('keeps its product, unit, taxes, discount and description', () {
      final line = invoiceLineFromMoveLine(desk);
      expect(line['product_id'], 4);
      expect(line['product_uom_id'], 1);
      expect(line['tax_ids'], [2]);
      expect(line['discount'], 10.0);
      expect(line['product_name'], '[DESK] Desk');
      expect(line['description'], '[DESK] Desk\nWith three drawers');

      final values = invoiceLineValues(line);
      expect(values['product_id'], 4);
      expect(values['product_uom_id'], 1);
      expect(values['discount'], 10.0);
      expect(values['name'], '[DESK] Desk\nWith three drawers');
      expect(values['tax_ids'], [
        [
          6,
          0,
          [2],
        ],
      ]);
      expectNoEmptyRecords(values);
    });

    test('leaves the product\'s taxes to Odoo when it is only priced', () {
      final values = invoiceLineValues(
        invoiceLineFromMoveLine(desk),
        withTaxes: false,
      );
      expect(values.containsKey('tax_ids'), isFalse);
      expect(values['product_id'], 4);
    });

    test('a new line from the form has no discount or description to send', () {
      final values = invoiceLineValues({
        'product_id': 8,
        'product_name': 'Chair',
        'quantity': 1.0,
        'unit_price': 20.0,
        'product_uom_id': 1,
        'tax_ids': <int>[],
      });
      expect(values, {
        'name': 'Chair',
        'quantity': 1.0,
        'price_unit': 20.0,
        'product_id': 8,
        'product_uom_id': 1,
        'tax_ids': [
          [6, 0, <int>[]],
        ],
      });
    });
  });

  group('sections and notes', () {
    test('stay what they are: a type and a text, nothing billed', () {
      for (final type in ['line_section', 'line_note']) {
        final line = invoiceLineFromMoveLine({
          'id': 3,
          'product_id': false,
          'name': 'Optional extras',
          'quantity': 0.0,
          'price_unit': 0.0,
          'display_type': type,
        });
        expect(line['display_type'], type);
        expect(invoiceLineValues(line), {
          'display_type': type,
          'name': 'Optional extras',
        });
        expect(
          invoiceLineValues(line, forUpdate: true),
          {'name': 'Optional extras'},
          reason: 'display_type is not changed after creation',
        );
      }
    });
  });

  group('the commands that save an invoice', () {
    Map<String, dynamic> line(int? id, String name) => {
      'move_line_id': ?id,
      'product_id': null,
      'product_name': name,
      'quantity': 1.0,
      'unit_price': 10.0,
      'tax_ids': <int>[],
    };

    test('update the lines that were there, create the new, delete the '
        'removed', () {
      final commands = invoiceLineCommands(
        [210, 211, 212],
        [line(211, 'kept'), line(null, 'new')],
      );

      expect(commands.map((c) => c[0]), [2, 2, 1, 0]);
      expect(commands[0], [2, 210, false]);
      expect(commands[1], [2, 212, false]);
      expect(commands[2][1], 211);
      expect((commands[2][2] as Map)['name'], 'kept');
      expect(commands[3][1], 0);
      expect((commands[3][2] as Map)['name'], 'new');
    });

    test('keep a down payment line where it is, without a product', () {
      final commands = invoiceLineCommands(
        [210],
        [invoiceLineFromMoveLine(downPayment)],
      );

      expect(commands, hasLength(1));
      expect(commands.single[0], 1, reason: 'updated in place');
      expect(commands.single[1], 210);
      final values = commands.single[2] as Map<String, dynamic>;
      expect(values.containsKey('product_id'), isFalse);
      expect(values.containsKey('product_uom_id'), isFalse);
      expectNoEmptyRecords(values);
    });

    test(
      'a line the invoice did not have is created, even with a stale id',
      () {
        final commands = invoiceLineCommands([1], [line(99, 'strange')]);
        expect(commands.map((c) => c[0]), [2, 0]);
      },
    );

    test('keep the order of the lines', () {
      final commands = invoiceLineCommands([], [
        line(null, 'a'),
        line(null, 'b'),
        line(null, 'c'),
      ]);
      expect(commands.map((c) => (c[2] as Map)['name']), ['a', 'b', 'c']);
    });
  });
}
