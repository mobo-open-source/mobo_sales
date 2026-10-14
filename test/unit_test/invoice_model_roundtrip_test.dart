import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/models/invoice.dart';

void main() {
  test('an invoice read back from its own map keeps its customer\'s name', () {
    // The details page changes a field in place (a payment state, say) by
    // writing the invoice to a map, merging, and reading it back; the customer
    // must not turn into "Unknown" on the way.
    final invoice = Invoice.fromJson({
      'id': 5,
      'name': 'INV/0005',
      'partner_id': [7, 'Azure Interior'],
      'state': 'posted',
      'payment_state': 'not_paid',
      'amount_total': 100.0,
    });

    final again = Invoice.fromJson({
      ...invoice.toJson(),
      'payment_state': 'paid',
    });

    expect(again.customerId, 7);
    expect(again.customerName, 'Azure Interior');
    expect(again.paymentState, 'paid');
  });
}
