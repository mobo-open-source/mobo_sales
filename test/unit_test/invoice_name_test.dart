import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/models/invoice.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/services/invoice_service.dart';
import 'package:mobo_sales/utils/invoice_name.dart';

/// A draft invoice has no number: Odoo 17 leaves `name` as `/`, Odoo 18 to 20
/// as `False`. It is called by its state, never "false" or "/".
void main() {
  group('invoiceDisplayName', () {
    test('is the number once there is one', () {
      expect(invoiceDisplayName('INV/2026/0001', 'posted'), 'INV/2026/0001');
      expect(invoiceDisplayName(' INV/2026/0001 ', 'posted'), 'INV/2026/0001');
    });

    test('is the state for an invoice with no number', () {
      for (final empty in [false, null, '', '/', ' ', 'false']) {
        expect(invoiceDisplayName(empty, 'draft'), 'Draft', reason: '$empty');
      }
      expect(invoiceDisplayName(false, 'cancel'), 'Cancelled');
      expect(invoiceDisplayName(false, 'posted'), 'Posted');
      expect(invoiceDisplayName(false, null), 'Draft');
    });

    test('says whether it is a number, and words the success message', () {
      expect(invoiceHasNumber('INV/2026/0001'), isTrue);
      expect(invoiceHasNumber('Draft'), isFalse);
      expect(
        invoiceCreatedMessage('INV/2026/0001'),
        'Invoice INV/2026/0001 created successfully',
      );
      expect(invoiceCreatedMessage('Draft'), 'Invoice created successfully');
      expect(
        invoiceCreatedMessage('Draft', kind: 'Draft invoice'),
        'Draft invoice created successfully',
      );
    });
  });

  test('an invoice read from Odoo with no number is "Draft"', () {
    for (final name in [false, '/']) {
      final invoice = Invoice.fromJson({
        'id': 5,
        'name': name,
        'state': 'draft',
        'partner_id': [7, 'Azure Interior'],
      });
      expect(invoice.name, 'Draft', reason: 'name: $name');
    }
  });

  group('the name shown when an invoice is created', () {
    Future<String?> nameOf(Object? name, String state) {
      final service = InvoiceService.forTesting(
        callKw: (payload) async => [
          {'id': 5, 'name': name, 'state': state},
        ],
        bus: DataChangeBus.forTesting(),
      );
      return service.getInvoiceName(5);
    }

    test(
      'is "Draft" for an invoice Odoo has not numbered, not "false"',
      () async {
        expect(await nameOf(false, 'draft'), 'Draft');
        expect(await nameOf('/', 'draft'), 'Draft');
      },
    );

    test('is the number when there is one', () async {
      expect(await nameOf('INV/2026/0001', 'posted'), 'INV/2026/0001');
    });
  });
}
