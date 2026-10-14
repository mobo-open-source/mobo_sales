import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/quotation_status.dart';

void main() {
  QuotationStatus of(String state) =>
      QuotationStatus.of(state, fallback: Colors.purple);

  test('every state of a sale order has its own label and colour', () {
    expect(of('draft').label, 'Quotation');
    expect(of('sent').label, 'Sent');
    expect(of('sale').label, 'Sale Order');
    expect(of('done').label, 'Locked', reason: 'Odoo 17 only');
    expect(of('cancel').label, 'Cancelled');
    expect(of('cancel').color, Colors.red);
    expect(of('sale').color, Colors.green);
    expect(of('draft').color, Colors.orange);
    expect(of('sent').color, Colors.blue);
  });

  test('a cancelled order never reads as a quotation', () {
    expect(of('cancel').label, isNot('Quotation'));
  });

  test('an unknown state reads as its name, in the fallback colour', () {
    expect(of('waiting').label, 'Waiting');
    expect(of('waiting').color, Colors.purple);
    expect(of('').label, 'Unknown');
  });
}
