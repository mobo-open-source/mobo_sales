import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mobo_sales/services/delivery_service.dart';

/// Cancelling a delivery painted the screen red with "type 'bool' is not a
/// subtype of type 'String'", and validating one told the user to go and
/// finish the job in Odoo on a desktop.

/// The guard the Deadline row now uses, in the form the screen applies it.
String? odooDateTime(dynamic value) {
  if (value == null || value is bool) return null;
  final parsed = DateTime.tryParse(value.toString());
  if (parsed == null) return null;
  return DateFormat('MMM dd, yyyy HH:mm').format(parsed);
}

void main() {
  group('an unset Odoo datetime never reaches DateTime.parse', () {
    test("false is Odoo's null, and is not a date", () {
      // Cancelling a delivery clears date_deadline, which comes back false.
      expect(odooDateTime(false), isNull);
      expect(odooDateTime(null), isNull);
    });

    test('a real datetime still formats', () {
      expect(odooDateTime('2026-11-06 14:30:00'), 'Nov 06, 2026 14:30');
    });

    test('a string that is not a date is dropped, not thrown', () {
      expect(odooDateTime('not a date'), isNull);
      expect(odooDateTime(''), isNull);
    });

    test('the old code threw on exactly this', () {
      expect(() => DateTime.parse(false as dynamic), throwsA(isA<TypeError>()));
    });
  });

  group('the SMS question is answerable in the app', () {
    test('it has its own outcome, distinct from "go and use Odoo"', () {
      expect(
        DeliveryValidationOutcome.needsSmsChoice,
        isNot(DeliveryValidationOutcome.needsConfirmationInOdoo),
      );
    });

    test("Odoo's own wizard record is carried, not a new one", () {
      // send_sms re-validates the pickings named in the action's context, so a
      // wizard this app created would have nothing to validate.
      const result = DeliveryValidationResult(
        DeliveryValidationOutcome.needsSmsChoice,
        wizardId: 42,
        wizardContext: {'button_validate_picking_ids': [7]},
      );

      expect(result.wizardId, 42);
      expect(result.wizardContext!['button_validate_picking_ids'], [7]);
      expect(result.isValidated, isFalse);
    });
  });
}
