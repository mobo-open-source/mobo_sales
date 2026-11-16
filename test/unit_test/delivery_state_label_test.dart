import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/models/delivery.dart';

/// `stock.picking.state` as Odoo declares it, read from
/// `addons/stock/models/stock_picking.py`. Identical in 17.0, 18.0, 19.0 and
/// 20.0, so one table covers every version the app supports.
const Map<String, String> odooPickingStateLabels = {
  'draft': 'Draft',
  'waiting': 'Waiting Another Operation',
  'confirmed': 'Waiting',
  'assigned': 'Ready',
  'done': 'Done',
  'cancel': 'Cancelled',
};

Delivery _picking(String state) => Delivery(
  id: 1,
  name: 'WH/OUT/0001',
  state: state,
  pickingTypeCode: 'outgoing',
);

void main() {
  group('a picking is labelled the way Odoo labels it', () {
    odooPickingStateLabels.forEach((state, label) {
      test('$state reads as "$label"', () {
        expect(deliveryStateLabel(state), label);
        expect(_picking(state).getStateLabel(), label);
      });
    });

    test('an unknown state is shown as it came, not hidden', () {
      expect(deliveryStateLabel('some_future_state'), 'some_future_state');
    });
  });

  group('the two that misread if guessed from the technical name', () {
    // The reported bug: a delivery nobody had validated was shown as
    // "Confirmed", because `confirmed` was read as the English word rather
    // than as Odoo's state. In Odoo it means the transfer is waiting for
    // stock.
    test('`confirmed` is never shown as "Confirmed"', () {
      expect(deliveryStateLabel('confirmed'), 'Waiting');
      expect(deliveryStateLabel('confirmed'), isNot('Confirmed'));
    });

    test(
      '`waiting` says what it waits on, so it cannot be read as the other',
      () {
        expect(deliveryStateLabel('waiting'), 'Waiting Another Operation');
        expect(
          deliveryStateLabel('waiting'),
          isNot(deliveryStateLabel('confirmed')),
          reason: 'two different states must not share one label',
        );
      },
    );

    test('only `done` means the delivery actually happened', () {
      final doneLabels = odooPickingStateLabels.entries
          .where((e) => e.value == 'Done')
          .map((e) => e.key)
          .toList();
      expect(doneLabels, ['done']);
    });
  });

  test('every state the app offers to filter on has a label', () {
    // The filter chips and the detail page read the same table, so a status
    // the user can filter by is always a status they can see.
    for (final state in kDeliveryStateLabels.keys) {
      expect(
        odooPickingStateLabels.containsKey(state),
        isTrue,
        reason: '$state is not a stock.picking state',
      );
    }
    expect(kDeliveryStateLabels, odooPickingStateLabels);
  });
}
