import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/field_validation_service.dart';
import 'package:mobo_sales/services/odoo_error_classifier.dart';
import 'package:mobo_sales/services/odoo_error_handler.dart';

/// The wording of Odoo's ORM errors, taken from the source of each release
/// (file:line in the Odoo 17 / 18 / 19 / 20 trees), run through the three
/// layers that read them: [FieldValidationService] (prunes a field Odoo refused),
/// [OdooErrorHandler] (user-facing message) and [OdooErrorClassifier] ("is the
/// server down?").
void main() {
  /// How `OdooSessionManager.callKwWithCompany` hands an RPC error on:
  /// "<message>: <data.message>".
  String viaCallKw(String dataMessage) =>
      'Exception: Odoo Server Error: $dataMessage';

  /// How odoo_rpc's `OdooException` prints: the whole error map. Odoo 20 sends
  /// `code: 0` where 17 to 19 sent 200, and puts `debug` (the traceback, which
  /// quotes the source line that raised) last instead of before `message`.
  String viaOdooRpc(String name, String dataMessage, {int code = 0}) =>
      'OdooException: {code: $code, message: Odoo Server Error, data: '
      '{name: $name, message: $dataMessage, arguments: [$dataMessage], '
      'context: {}, debug: Traceback (most recent call last):\n'
      '  File "odoo/orm/models.py", line 3203, in _fetch_field\n'
      '    raise ValueError(f"Invalid field {field_name!r} on {self._name!r}")\n'
      'ValueError: $dataMessage\n}}';

  group('an unknown field in a field list', () {
    // field, message, where Odoo raises it
    const cases = [
      // 17: models.py:3908, 18: models.py:3301
      ('mobile', "Invalid field 'mobile' on model 'res.partner'"),
      // 19: orm/models.py:3853, 20: orm/models.py:3203 (read)
      ('mobile', "Invalid field 'mobile' on 'res.partner'"),
      // 19: orm/models.py:4383, 20: orm/models.py:3854 and 4131 (write, create)
      ('x_studio_note', "Invalid field 'x_studio_note' in 'res.partner'"),
      // 18/19/20 _read_group_orderby and order by: "on model"
      ('x_rank', "Invalid field 'x_rank' on model 'sale.order'"),
      // 20: orm/models.py:2101, an aggregate such as 'x_amount:sum'
      (
        'x_amount',
        "Invalid field 'x_amount' on model 'sale.order' for 'x_amount:sum'.",
      ),
    ];

    test('is recognised and named, however the error reaches the app', () {
      for (final (field, message) in cases) {
        for (final error in [
          message,
          viaCallKw(message),
          viaOdooRpc('builtins.ValueError', message),
          viaOdooRpc('builtins.ValueError', message, code: 200),
        ]) {
          expect(
            FieldValidationService.isFieldValidationError(error),
            isTrue,
            reason: error,
          );
          expect(
            FieldValidationService.extractInvalidField(error),
            field,
            reason: error,
          );
          expect(
            FieldValidationService.isDomainFieldError(error),
            isFalse,
            reason: error,
          );
        }
      }
    });

    test('is pruned from the request and the call retried', () async {
      FieldValidationService.clearInvalidFieldsCache('res.users');
      final seen = <List<String>>[];

      final result =
          await FieldValidationService.executeWithFieldValidation<String>(
            model: 'res.users',
            initialFields: const ['id', 'name', 'mobile', 'phone'],
            apiCall: (fields) async {
              seen.add(List<String>.from(fields));
              if (fields.contains('mobile')) {
                throw Exception(
                  viaCallKw("Invalid field 'mobile' on 'res.users'"),
                );
              }
              return 'ok';
            },
          );

      expect(result, 'ok');
      expect(seen.last, ['id', 'name', 'phone']);
      FieldValidationService.clearInvalidFieldsCache('res.users');
    });
  });

  group('an unknown field in a domain', () {
    const cases = [
      // 17: osv/expression.py:390, 18: osv/expression.py:386 ("leaf")
      "Invalid field res.partner.customer_rank in leaf "
          "('customer_rank', '>', 0)",
      // 17: osv/expression.py:1492, 18: models.py:3154 (quoted, "domain term")
      "Invalid field 'customer_rank' in domain term "
          "('customer_rank', '>', 0)",
      // 19: orm/domains.py:916, 20: orm/domains.py:969 ("condition")
      "Invalid field res.partner.customer_rank in condition "
          "('customer_rank', '>', 0)",
    ];

    test('is told apart from a field-list error and the field named', () {
      for (final message in cases) {
        for (final error in [
          message,
          viaCallKw(message),
          viaOdooRpc('builtins.ValueError', message),
        ]) {
          expect(
            FieldValidationService.isDomainFieldError(error),
            isTrue,
            reason: error,
          );
          expect(
            FieldValidationService.extractInvalidField(error),
            'customer_rank',
            reason: error,
          );
        }
      }
    });

    test(
      'Odoo 20 conditions are not retried with a pruned field list',
      () async {
        var attempts = 0;
        await expectLater(
          FieldValidationService.executeWithFieldValidation<void>(
            model: 'res.partner',
            initialFields: const ['id', 'name'],
            apiCall: (fields) async {
              attempts++;
              throw Exception(
                viaCallKw(
                  'Invalid field res.partner.customer_rank in condition '
                  "('customer_rank', '>', 0)",
                ),
              );
            },
          ),
          throwsA(isA<Exception>()),
        );
        expect(attempts, 1);
      },
    );

    test('other Odoo 20 condition errors are domain problems too', () async {
      // orm/domains.py:1022 `_raise("Field has no SQL representation because
      // it is not stored")`, which appends " in condition (...)".
      const message =
          'Field has no SQL representation because it is not stored in '
          "condition ('x_total', '>', 5)";
      expect(FieldValidationService.isDomainFieldError(message), isTrue);
      expect(FieldValidationService.isFieldValidationError(message), isFalse);

      var attempts = 0;
      await expectLater(
        FieldValidationService.executeWithFieldValidation<void>(
          model: 'sale.order',
          initialFields: const ['id', 'name'],
          apiCall: (fields) async {
            attempts++;
            throw Exception(viaCallKw(message));
          },
        ),
        throwsA(isA<Exception>()),
      );
      expect(attempts, 1, reason: 'no minimal-fields retry for a domain error');
    });
  });

  group('access errors', () {
    // 17/18 name every field of the group, 19 and 20 the one that failed
    // (odoo/orm/models.py:2761 in 20).
    const fieldAccess20 =
        'You do not have enough rights to access the field "credit_limit" on '
        'Contact (res.partner). Please contact your system administrator.'
        '\n\nOperation: read';
    // 17 (odoo/models.py:3504): '...administrator.\n\n(Operation: read)';
    // 18 words the last line without the parentheses, like 19 and 20.
    const fieldAccess17 =
        'You do not have enough rights to access the fields "credit,'
        'credit_limit" on Contact (res.partner). Please contact your system '
        'administrator.\n\n(Operation: read)';
    // odoo/addons/base/models/ir_access.py:49 and 330-347 in 20
    // (ir.model.access up to 19 words it the same way).
    const modelAccess =
        "You are not allowed to access 'Contact' (res.partner) records."
        '\n\nThis operation is allowed for the following groups:'
        '\n\t- Contact Creation\n\nContact your administrator to request '
        'access if necessary.';
    // ir_access.py:423-437 in 20; ir.rule._make_access_error up to 19.
    const recordAccess =
        'Uh-oh! Looks like you have stumbled upon some top-secret records.'
        "\n\nSorry, Mitchell Admin (id=2) doesn't have 'read' access to:"
        '\n- Sales Order (sale.order)\n\nIf you really, really need access, '
        'perhaps you can win over your friendly administrator with a batch of '
        'freshly baked cookies.';

    test('a field-level error names the fields to drop', () {
      expect(FieldValidationService.extractInaccessibleFields(fieldAccess20), [
        'credit_limit',
      ]);
      expect(FieldValidationService.extractInaccessibleFields(fieldAccess17), [
        'credit',
        'credit_limit',
      ]);
      for (final message in [fieldAccess20, fieldAccess17]) {
        for (final error in [
          viaCallKw(message),
          viaOdooRpc('odoo.exceptions.AccessError', message),
        ]) {
          expect(
            FieldValidationService.extractInaccessibleFields(error),
            isNotEmpty,
            reason: error,
          );
        }
      }
    });

    test('every wording is an access error, via either transport', () {
      for (final message in [
        fieldAccess20,
        fieldAccess17,
        modelAccess,
        recordAccess,
      ]) {
        expect(
          OdooErrorHandler.isAccessError(viaCallKw(message)),
          isTrue,
          reason: message,
        );
        expect(
          OdooErrorHandler.isAccessError(
            viaOdooRpc('odoo.exceptions.AccessError', message),
          ),
          isTrue,
          reason: message,
        );
      }
    });

    test('the user is told "Access Denied", not "Operation Failed"', () {
      for (final message in [modelAccess, recordAccess, fieldAccess20]) {
        final text = OdooErrorHandler.toUserMessage(viaCallKw(message));
        expect(text, contains('Access Denied'), reason: message);
      }
    });

    test('are application errors, not a server that is down', () {
      for (final message in [
        fieldAccess20,
        fieldAccess17,
        modelAccess,
        recordAccess,
      ]) {
        expect(
          OdooErrorClassifier.isServerUnreachable(viaCallKw(message)),
          isFalse,
          reason: message,
        );
        expect(
          OdooErrorClassifier.isServerUnreachable(
            viaOdooRpc('odoo.exceptions.AccessError', message),
          ),
          isFalse,
          reason: message,
        );
      }
    });
  });

  group('a method that Odoo 20 removed', () {
    // odoo/orm/models.py:214, get_public_method: check_access_rights is gone.
    const message =
        "The method 'res.partner.check_access_rights' does not exist";

    test('is neither a field problem nor a refusal', () {
      final error = viaCallKw(message);
      expect(FieldValidationService.isFieldValidationError(error), isFalse);
      expect(FieldValidationService.isDomainFieldError(error), isFalse);
      expect(OdooErrorHandler.isAccessError(error), isFalse);
      expect(OdooErrorClassifier.isServerUnreachable(error), isFalse);
    });
  });

  group('database and session errors', () {
    test('Odoo 20 refuses an unknown database as "Database not found."', () {
      // addons/web/controllers/session.py: raise AccessError("Database not
      // found.") when db_filter([db]) is empty.
      expect(
        OdooErrorClassifier.isServerUnreachable(
          viaOdooRpc('odoo.exceptions.AccessError', 'Database not found.'),
        ),
        isTrue,
      );
    });

    test('a wrong password still reads as "access denied"', () {
      // odoo/exceptions.py: AccessDenied.__init__(message="Access Denied")
      final error = viaOdooRpc('odoo.exceptions.AccessDenied', 'Access Denied');
      expect(error.toLowerCase(), contains('access denied'));
      expect(OdooErrorClassifier.isServerUnreachable(error), isFalse);
    });
  });
}
