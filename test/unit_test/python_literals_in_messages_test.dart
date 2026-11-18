import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/odoo_error_handler.dart';

/// Odoo writes a field's empty value into its messages as Python's `False` or
/// `None`. The person holding the phone must never read those words.
void main() {
  group('withoutPythonLiterals', () {
    test('drops the empty value a module wrote into its sentence', () {
      expect(
        OdooErrorHandler.withoutPythonLiterals(
          'The warehouse False is not one of the warehouses of the branch '
          'الرياض.\n\nPlease pick one of: Branch Al-Riyadh, Expire Al-Riyadh.',
        ),
        'The warehouse is not one of the warehouses of the branch الرياض.'
        '\n\nPlease pick one of: Branch Al-Riyadh, Expire Al-Riyadh.',
      );
    });

    test('drops a quoted or bracketed empty value and closes the gap', () {
      expect(
        OdooErrorHandler.withoutPythonLiterals('Value “False” is not valid.'),
        'Value is not valid.',
      );
      expect(
        OdooErrorHandler.withoutPythonLiterals("The field 'None' is required."),
        'The field is required.',
      );
      expect(
        OdooErrorHandler.withoutPythonLiterals('Journal (False) is missing.'),
        'Journal is missing.',
      );
    });

    test("drops JSON's false too", () {
      expect(
        OdooErrorHandler.withoutPythonLiterals('Warehouse false not found.'),
        'Warehouse not found.',
      );
    });

    test('keeps "None of" — it is English, not a value', () {
      const sentence = 'None of the selected products can be sold.';
      expect(OdooErrorHandler.withoutPythonLiterals(sentence), sentence);
    });

    test('leaves words that only contain the letters alone', () {
      const sentence = 'isFalse and Falsehood are not values.';
      expect(OdooErrorHandler.withoutPythonLiterals(sentence), sentence);
    });

    test('returns a message without such a value exactly as it was', () {
      const message =
          '⚙️ Configuration Required\n\n'
          '   • Type: SALE\n'
          '   • Name: Customer Invoices';
      expect(OdooErrorHandler.withoutPythonLiterals(message), message);
    });
  });

  group('the messages users see never carry an empty value', () {
    const serverError =
        'OdooException: {code: 0, message: Odoo Server Error, data: {name: '
        'odoo.exceptions.ValidationError, message: The warehouse False is not '
        'one of the warehouses of the branch الرياض.\n\nPlease pick one of: '
        'Branch Al-Riyadh, Consignment - Warehouse., arguments: [The warehouse '
        'False is not one of the warehouses], context: {}, debug: Traceback}}';

    test('in a dialog message', () {
      final message = OdooErrorHandler.toUserMessage(serverError);
      expect(message, isNot(contains('False')));
      expect(message, contains('The warehouse is not one of the warehouses'));
    });

    test('in a snackbar message', () {
      final message = OdooErrorHandler.toSnackbarMessage(serverError);
      expect(message, isNot(contains('False')));
      expect(message, contains('The warehouse is not one of the warehouses'));
    });

    test('a sentence that was nothing but an empty value falls back', () {
      final message = OdooErrorHandler.toUserMessage(
        'odoo.exceptions.UserError: False',
        defaultMessage: 'Could not save. Please try again.',
      );
      expect(message, 'Could not save. Please try again.');
    });
  });
}
