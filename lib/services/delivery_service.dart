import '../models/delivery.dart';
import 'delivery_lot_service.dart';
import 'odoo_session_manager.dart';

/// What came back from validating a delivery.
enum DeliveryValidationOutcome {
  /// The picking is `done`.
  validated,

  /// Odoo answered with a wizard — a backorder to confirm, a quality check, a
  /// reception report — and the picking is not done yet.
  needsConfirmationInOdoo,

  /// None of the picking's stock is reserved, so there is nothing to ship.
  /// Nothing was changed in Odoo.
  notReserved,

  /// A tracked product's reserved quantity has no lot or serial number, which
  /// Odoo refuses to validate. [DeliveryValidationResult.step] names them.
  lotsRequired,

  /// Less than the demand is being delivered, so Odoo asks whether to keep the
  /// rest in a backorder. [DeliveryValidationResult.wizardContext] is what
  /// answers it (see [DeliveryService.resolveBackorder]).
  needsBackorder,
}

class DeliveryValidationResult {
  const DeliveryValidationResult(
    this.outcome, {
    this.step,
    this.state,
    this.wizardContext,
  });

  final DeliveryValidationOutcome outcome;

  /// The wizard's title, when Odoo named one.
  final String? step;

  /// The picking's state after the attempt.
  final String? state;

  /// The context Odoo attached to the backorder question, to answer it with.
  final Map<String, dynamic>? wizardContext;

  bool get isValidated => outcome == DeliveryValidationOutcome.validated;
}

/// Delivery (`stock.picking`) actions for the sales app.
///
/// The validation sequence follows what Odoo's own web client does when the
/// Validate button is pressed: mark the moves that have a quantity as picked,
/// then validate. Nothing is reserved on the way — Check Availability is its
/// own button, as in Odoo, and a quantity the user typed on a line stands. A
/// draft delivery goes straight to Odoo's own validation, which confirms it and
/// fills in the demand itself.
class DeliveryService {
  DeliveryService._();

  static final DeliveryService instance = DeliveryService._();

  /// Marks a draft delivery as To Do (`action_confirm`).
  Future<void> markAsTodo(int pickingId) => _call(pickingId, 'action_confirm');

  /// Reserves what is on hand (`action_assign`), as Check Availability does.
  ///
  /// Never raises for "nothing available": the picking simply stays as it was.
  Future<String?> checkAvailability(int pickingId) async {
    await _call(pickingId, 'action_assign');
    return _readState(pickingId);
  }

  /// Locks or unlocks the delivery (`action_toggle_is_locked`): the demand of
  /// its lines can only be changed while it is unlocked.
  Future<void> toggleLock(int pickingId) =>
      _call(pickingId, 'action_toggle_is_locked');

  /// Releases the reserved stock (`do_unreserve`).
  Future<void> unreserve(int pickingId) => _call(pickingId, 'do_unreserve');

  /// Cancels the delivery (`action_cancel`).
  Future<void> cancel(int pickingId) => _call(pickingId, 'action_cancel');

  Future<void> _call(int pickingId, String method) async {
    final generation = await OdooSessionManager.serverGeneration();
    await OdooSessionManager.safeCallKw({
      'model': 'stock.picking',
      'method': method,
      'args': [
        [pickingId],
      ],
      'kwargs': {'context': confirmPickingContext(generation)},
    });
  }

  /// Sets the quantity to deliver and/or the demand of the delivery line
  /// [moveId], as editing the line in Odoo's transfer form does.
  ///
  /// A quantity typed by hand reserves it on the line even when the warehouse
  /// has none (which is how Odoo lets a delivery with no stock be validated),
  /// and marks the line picked so it is not left out of the validation.
  Future<void> updateMove(
    int moveId, {
    double? quantity,
    double? demand,
  }) async {
    final values = <String, dynamic>{
      'product_uom_qty': ?demand,
      'quantity': ?quantity,
      if (quantity != null) 'picked': quantity > 0,
    };
    if (values.isEmpty) return;
    await OdooSessionManager.safeCallKw({
      'model': 'stock.move',
      'method': 'write',
      'args': [
        [moveId],
        values,
      ],
      'kwargs': {},
    });
  }

  /// Answers Odoo's backorder question for [pickingId]: keep what is left of
  /// the demand in a new backorder, or not ([createBackorder] false), then
  /// validates. [context] is the one Odoo sent with the question.
  Future<DeliveryValidationResult> resolveBackorder(
    int pickingId, {
    required bool createBackorder,
    Map<String, dynamic> context = const {},
  }) async {
    final wizardId = await OdooSessionManager.safeCallKw({
      'model': 'stock.backorder.confirmation',
      'method': 'create',
      'args': [
        {
          'pick_ids': [
            [4, pickingId],
          ],
        },
      ],
      'kwargs': {'context': context},
    });
    await OdooSessionManager.safeCallKw({
      'model': 'stock.backorder.confirmation',
      'method': createBackorder ? 'process' : 'process_cancel_backorder',
      'args': [
        [wizardId],
      ],
      'kwargs': {'context': context},
    });
    final state = await _readState(pickingId);
    return DeliveryValidationResult(
      state == 'done'
          ? DeliveryValidationOutcome.validated
          : DeliveryValidationOutcome.needsConfirmationInOdoo,
      state: state,
    );
  }

  /// Validates the delivery with [pickingId].
  ///
  /// Throws whatever Odoo refuses with — an unreserved transfer, a lock date,
  /// missing rights — so the caller can show the server's own words.
  Future<DeliveryValidationResult> validateDelivery(int pickingId) async {
    final generation = await OdooSessionManager.serverGeneration();
    final context = confirmPickingContext(generation);

    // A draft delivery is Odoo's to validate: it confirms it first and fills
    // each empty line with its demand. Everything else must already carry a
    // quantity, reserved by Check Availability or typed on the line.
    final startState = await _readState(pickingId);
    if (startState != 'draft') {
      final reserved = await _markReservedMovesPicked(pickingId);

      // No quantity at all: Odoo would refuse with its "zero quantity transfer"
      // joke, which says nothing about what to do, so this is reported as its
      // own outcome for the caller to explain rather than as a failure.
      if (reserved <= 0) {
        return const DeliveryValidationResult(
          DeliveryValidationOutcome.notReserved,
        );
      }
    }

    // A tracked product has to leave with its lot or serial number. Odoo
    // would refuse with an error naming them; say so before asking it.
    try {
      final missing = await DeliveryLotService.instance.productsMissingLots(
        pickingId,
      );
      if (missing.isNotEmpty) {
        return DeliveryValidationResult(
          DeliveryValidationOutcome.lotsRequired,
          step: missing.join(', '),
        );
      }
    } catch (_) {}

    final result = await OdooSessionManager.safeCallKw({
      'model': 'stock.picking',
      'method': 'button_validate',
      'args': [
        [pickingId],
      ],
      'kwargs': {'context': context},
    });

    if (result == true) {
      return const DeliveryValidationResult(
        DeliveryValidationOutcome.validated,
        state: 'done',
      );
    }

    // Anything else is an action. Some of them still mean the transfer went
    // through (an autoprint job, a reception report), so the picking's own
    // state decides rather than the shape of the action.
    final state = await _readState(pickingId);
    if (state == 'done') {
      return DeliveryValidationResult(
        DeliveryValidationOutcome.validated,
        state: state,
      );
    }

    // Less than the demand: Odoo asks whether to keep the rest in a backorder.
    if (result is Map &&
        result['res_model'] == 'stock.backorder.confirmation') {
      final ctx = result['context'];
      return DeliveryValidationResult(
        DeliveryValidationOutcome.needsBackorder,
        state: state,
        wizardContext: ctx is Map ? Map<String, dynamic>.from(ctx) : const {},
      );
    }

    return DeliveryValidationResult(
      DeliveryValidationOutcome.needsConfirmationInOdoo,
      step: result is Map ? result['name']?.toString() : null,
      state: state,
    );
  }

  /// Flags every move holding a reserved quantity as picked.
  ///
  /// Odoo 17 onwards only completes a move that is `picked`; the rest are
  /// split into a backorder. The web client sets it as lines are ticked,
  /// which an RPC validate never does, so a transfer validated from here
  /// would otherwise come out empty with everything moved to a backorder.
  ///
  /// Returns the total quantity reserved across the picking's open moves.
  Future<double> _markReservedMovesPicked(int pickingId) async {
    // `move_ids`, not the `pickingMovesField` the details page reads: that one
    // is `move_ids_without_package` up to Odoo 18, which leaves out the moves
    // inside a package level. Validating has to see every move, and `move_ids`
    // is spelt the same way on 17 through 20.
    final picking = await OdooSessionManager.safeCallKw({
      'model': 'stock.picking',
      'method': 'read',
      'args': [
        [pickingId],
        ['move_ids'],
      ],
      'kwargs': {},
    });

    final moveIds = (picking is List && picking.isNotEmpty)
        ? picking.first['move_ids']
        : null;
    if (moveIds is! List || moveIds.isEmpty) return 0;

    final moves = await OdooSessionManager.safeCallKw({
      'model': 'stock.move',
      'method': 'read',
      'args': [
        moveIds,
        ['state', 'quantity', 'picked'],
      ],
      'kwargs': {},
    });
    if (moves is! List) return 0;

    final toPick = <int>[];
    var reserved = 0.0;
    for (final move in moves.cast<Map<String, dynamic>>()) {
      final state = move['state'];
      if (state == 'done' || state == 'cancel') continue;
      final quantity = (move['quantity'] as num?) ?? 0;
      if (quantity <= 0) continue;
      reserved += quantity.toDouble();
      if (move['picked'] == true) continue;
      toPick.add(move['id'] as int);
    }
    if (toPick.isEmpty) return reserved;

    await OdooSessionManager.safeCallKw({
      'model': 'stock.move',
      'method': 'write',
      'args': [
        toPick,
        {'picked': true},
      ],
      'kwargs': {},
    });

    return reserved;
  }

  Future<String?> _readState(int pickingId) async {
    try {
      final rows = await OdooSessionManager.safeCallKw({
        'model': 'stock.picking',
        'method': 'read',
        'args': [
          [pickingId],
          ['state'],
        ],
        'kwargs': {},
      });
      if (rows is List && rows.isNotEmpty) {
        return rows.first['state']?.toString();
      }
    } catch (_) {}
    return null;
  }
}
