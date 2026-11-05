import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/odoo_error_handler.dart';

void main() {
  test('nothing to invoice reads as a plain warning message', () {
    final e = Exception(
      'OdooException: UserError: Cannot create an invoice. No items are '
      'available to invoice.',
    );
    final user = OdooErrorHandler.toUserMessage(e);
    final snack = OdooErrorHandler.toSnackbarMessage(user);
    expect(OdooErrorHandler.isNothingToInvoice(snack), isTrue);
    expect(snack.startsWith('Nothing to invoice yet.'), isTrue);
    expect(snack.contains('Odoo'), isFalse);
  });
}
