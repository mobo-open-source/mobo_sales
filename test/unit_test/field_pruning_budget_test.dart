import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/field_validation_service.dart';
import 'package:mobo_sales/widgets/connection_status_widget.dart';

/// A tester opened a sale order and got Odoo's entire Python traceback on
/// screen — file paths, line numbers, `KeyError: 'delivery_status'` — over the
/// top of the order, overflowing by 504 pixels.
///
/// Two faults met. The read gave up one attempt early, and whatever it gave
/// up with was printed verbatim.
String odooInvalidField(String field) =>
    "OdooException: [code: 0, message: Odoo Server Error, data: "
    "{name: builtins.ValueError, message: Invalid field '$field' on "
    "'sale.order', debug: Traceback (most recent call last):\n"
    '  File "/usr/lib/python3/dist-packages/odoo/orm/models.py", line 3857, '
    "in _determine_fields_to_fetch\n    field = self._fields[field_name]\n"
    "KeyError: '$field'}]";

void main() {
  setUp(FieldValidationService.clearInvalidFieldsCache);

  group('a read survives every optional field being absent', () {
    /// Odoo names exactly one invalid field per reply, so n missing fields
    /// need n+1 round trips.
    Future<String> readAsking(
      List<String> asked,
      Set<String> missing,
      List<int> attemptSizes,
    ) {
      return FieldValidationService.executeWithFieldValidation<String>(
        model: 'sale.order',
        initialFields: asked,
        apiCall: (fields) async {
          attemptSizes.add(fields.length);
          for (final f in fields) {
            if (missing.contains(f)) throw Exception(odooInvalidField(f));
          }
          return 'OK';
        },
      );
    }

    test('the three the quotation page asks for', () async {
      final sizes = <int>[];

      await expectLater(
        readAsking(
          const [
            'id', 'name', 'state',
            'amount_discount', 'amount_delivery', 'delivery_status',
          ],
          const {'amount_discount', 'amount_delivery', 'delivery_status'},
          sizes,
        ),
        completion('OK'),
      );

      expect(sizes.length, 4, reason: 'one round trip per field, plus the win');
      expect(sizes.last, 3);
    });

    test('more missing fields than the retry budget', () async {
      final sizes = <int>[];
      const absent = {'a', 'b', 'c', 'd', 'e', 'f'};

      await expectLater(
        readAsking(const ['id', 'a', 'b', 'c', 'd', 'e', 'f'], absent, sizes),
        completion('OK'),
      );
    });

    test('a failure that pruning cannot fix still gives up', () async {
      await expectLater(
        FieldValidationService.executeWithFieldValidation<String>(
          model: 'sale.order',
          initialFields: const ['id', 'name'],
          apiCall: (_) async => throw Exception('AccessError: not allowed'),
        ),
        throwsA(isA<Exception>()),
        reason: 'the budget still has to stop somewhere',
      );
    });
  });

  test('a traceback is never what the user reads', () {
    final info = ConnectionStatusWidget.errorInfoFor(
      odooInvalidField('delivery_status'),
    );

    expect(info['message'], isNot(contains('Traceback')));
    expect(info['message'], isNot(contains('dist-packages')));
    expect(info['message'], isNot(contains('KeyError')));
    expect(info['message']!.length, lessThan(200));
  });
}
