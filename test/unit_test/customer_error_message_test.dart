import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/customer_error_message.dart';

/// What a user reads when saving a customer fails: Odoo's own sentence when it
/// gave one, plain words for the rest, never an exception.
void main() {
  String edit(Object error) => customerErrorMessage(error, isEdit: true);
  String create(Object error) => customerErrorMessage(error, isEdit: false);

  group("Odoo's own validation sentence", () {
    test('is shown as it is, without the wrapping around it', () {
      expect(
        edit(
          Exception(
            'Odoo Server Error: The VAT number [XX123] for partner [Ada] does '
            'not seem to be valid.\nNote: the expected format is FR12345678901',
          ),
        ),
        'The VAT number [XX123] for partner [Ada] does not seem to be valid. '
        'Note: the expected format is FR12345678901',
      );
      expect(
        edit(
          Exception(
            'Odoo Server Error: Invalid Email! Please enter a valid email address.',
          ),
        ),
        'Invalid Email! Please enter a valid email address.',
      );
    });

    test('is not replaced by a guess from words that happen to be in it', () {
      // "email" and "phone" in the text used to turn any validation error into
      // "Please enter a valid email address".
      expect(
        edit(
          Exception(
            'Odoo Server Error: A contact needs a phone or an email to be '
            'reachable.',
          ),
        ),
        'A contact needs a phone or an email to be reachable.',
      );
    });
  });

  group('permissions', () {
    test('say what the user cannot do, not which model or method', () {
      expect(
        edit(Exception('You do not have permission to modify customers.')),
        "You don't have permission to edit customers. Please contact your "
        'administrator.',
      );
      expect(
        create(Exception('You do not have permission to create customers.')),
        "You don't have permission to create customers. Please contact your "
        'administrator.',
      );
      expect(
        edit(
          Exception(
            'Odoo Server Error: You do not have enough rights to access the '
            'field "credit_limit" on Contact (res.partner).',
          ),
        ),
        "You don't have permission to change the credit limit.",
      );
    });

    test('an Odoo access error reads the same whichever form it came from', () {
      const error =
          "Odoo Server Error: You are not allowed to modify 'Contact' "
          '(res.partner) records.';
      expect(
        edit(Exception(error)),
        "You don't have permission to edit this customer. Please contact "
        'your administrator.',
      );
      expect(
        create(Exception(error)),
        "You don't have permission to create this customer. Please contact "
        'your administrator.',
      );
    });
  });

  group('values that have to be unique', () {
    test('name the one that is taken', () {
      expect(
        create(
          Exception(
            'Odoo Server Error: duplicate key value violates unique '
            'constraint "res_partner_email_key"\n'
            'DETAIL: Key (email)=(a@b.c) already exists.',
          ),
        ),
        'A customer with this email address already exists.',
      );
      expect(
        edit(
          Exception('duplicate key value ... Key (vat)=(FR1) already exists.'),
        ),
        'A customer with this VAT number already exists.',
      );
      expect(
        edit(
          Exception(
            'Odoo Server Error: duplicate key value violates unique constraint "x"',
          ),
        ),
        'A customer with the same details already exists.',
      );
    });
  });

  group('everything else', () {
    test('a lost connection or session is said plainly', () {
      expect(
        edit(Exception('SocketException: Failed host lookup')),
        'Could not reach the server. Please check your internet connection '
        'and try again.',
      );
      expect(
        edit(Exception('Session expired')),
        'Your session has expired. Please log in again.',
      );
    });

    test('a database rule is put in words', () {
      expect(
        edit(
          Exception(
            'Odoo Server Error: null value in column "name" violates not-null constraint',
          ),
        ),
        'A required value is missing. Please fill in all required fields.',
      );
    });

    test('an unreadable error falls back to the action that failed', () {
      expect(
        edit(Exception('')),
        'Could not update the customer. Please try again.',
      );
      expect(
        create(Exception('')),
        'Could not create the customer. Please try again.',
      );
    });
  });
}
