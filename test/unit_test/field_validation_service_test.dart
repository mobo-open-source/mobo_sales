import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/field_validation_service.dart';

void main() {
  group('FieldValidationService Tests', () {
    test(
      'extractInvalidField should extract field name from Odoo error message',
      () {
        const errorMessage =
            "Invalid field 'x_custom_field' on model 'sale.order'";
        final result = FieldValidationService.extractInvalidField(errorMessage);
        expect(result, 'x_custom_field');
      },
    );

    test('extractInvalidField should return null if no match found', () {
      const errorMessage = "Some other random error";
      final result = FieldValidationService.extractInvalidField(errorMessage);
      expect(result, null);
    });

    test(
      'isFieldValidationError should return true for known Odoo field errors',
      () {
        expect(
          FieldValidationService.isFieldValidationError("Invalid field 'name'"),
          true,
        );
        expect(
          FieldValidationService.isFieldValidationError(
            "Field \"name\" does not exist",
          ),
          true,
        );
        expect(
          FieldValidationService.isFieldValidationError("Unknown field: name"),
          true,
        );
      },
    );

    test('isFieldValidationError should return false for other errors', () {
      expect(
        FieldValidationService.isFieldValidationError("Connection timeout"),
        false,
      );
    });

    test('getValidatedFields should return safe fields by default', () {
      final fields = FieldValidationService.getValidatedFields('sale.order');
      expect(fields, contains('id'));
      expect(fields, contains('name'));
      expect(fields, contains('amount_total'));
    });

    test(
      'markFieldAsInvalid should filter out the field in subsequent calls',
      () {
        FieldValidationService.clearInvalidFieldsCache('sale.order');

        final initialFields = FieldValidationService.getValidatedFields(
          'sale.order',
        );
        expect(initialFields, contains('amount_total'));

        FieldValidationService.markFieldAsInvalid('sale.order', 'amount_total');

        final updatedFields = FieldValidationService.getValidatedFields(
          'sale.order',
        );
        expect(updatedFields, isNot(contains('amount_total')));
      },
    );
  });
}
