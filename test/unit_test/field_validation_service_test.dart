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

    test('extractInvalidField should read the dotted domain-leaf form', () {
      expect(
        FieldValidationService.extractInvalidField(
          'Invalid field res.partner.customer_rank in leaf '
          "(\'customer_rank\', \'>\', 0)",
        ),
        'customer_rank',
      );
      expect(
        FieldValidationService.extractInvalidField(
          'Invalid field res.partner.credit_limit',
        ),
        'credit_limit',
      );
    });

    test('isDomainFieldError should separate domain errors from field lists', () {
      expect(
        FieldValidationService.isDomainFieldError(
          'Invalid field res.partner.customer_rank in leaf',
        ),
        true,
      );
      expect(
        FieldValidationService.isDomainFieldError(
          "Invalid field 'credit' on model 'res.partner'",
        ),
        false,
      );
    });

    test('isFieldValidationError should ignore a bare Odoo Server Error', () {
      expect(
        FieldValidationService.isFieldValidationError(
          'Odoo Server Error: AccessError - not allowed',
        ),
        false,
      );
    });

    test('extractInaccessibleFields should parse Odoo 17/18 and 19 wording', () {
      expect(
        FieldValidationService.extractInaccessibleFields(
          'You do not have enough rights to access the fields '
          '"credit,credit_limit" on Contact (res.partner).',
        ),
        ['credit', 'credit_limit'],
      );
      expect(
        FieldValidationService.extractInaccessibleFields(
          'You do not have enough rights to access the field "credit_limit"',
        ),
        ['credit_limit'],
      );
      expect(
        FieldValidationService.extractInaccessibleFields('Connection timeout'),
        isEmpty,
      );
    });

    test('a domain field error is not retried with pruned fields', () async {
      var attempts = 0;
      await expectLater(
        FieldValidationService.executeWithFieldValidation<List<String>>(
          model: 'res.partner',
          initialFields: const ['id', 'name'],
          apiCall: (fields) async {
            attempts++;
            throw Exception('Invalid field res.partner.customer_rank in leaf');
          },
        ),
        throwsA(isA<Exception>()),
      );
      expect(attempts, 1);
    });

    test('an inaccessible field is pruned and the rest are kept', () async {
      FieldValidationService.clearInvalidFieldsCache('res.partner');
      final seen = <List<String>>[];
      final result =
          await FieldValidationService.executeWithFieldValidation<String>(
        model: 'res.partner',
        initialFields: const ['id', 'name', 'email', 'credit', 'credit_limit'],
        apiCall: (fields) async {
          seen.add(List<String>.from(fields));
          if (fields.contains('credit')) {
            throw Exception(
              'You do not have enough rights to access the fields '
              '"credit,credit_limit" on Contact (res.partner).',
            );
          }
          return 'ok';
        },
      );
      expect(result, 'ok');
      expect(seen.last, ['id', 'name', 'email']);
      FieldValidationService.clearInvalidFieldsCache('res.partner');
    });
  });
}
