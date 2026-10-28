import '../models/delivery.dart';
import 'odoo_session_manager.dart';

/// What came back from validating a delivery.
enum DeliveryValidationOutcome {
  /// The picking is `done`.
  validated,

  /// Odoo answered with a wizard — a backorder to confirm, a quality check, a
  /// reception report — and the picking is not done yet.
  needsConfirmationInOdoo,
}

class DeliveryValidationResult {
  const DeliveryValidationResult(this.outcome, {this.step, this.state});

  final DeliveryValidationOutcome outcome;

  /// The wizard's title, when Odoo named one.
  final String? step;

  /// The picking's state after the attempt.
  final String? state;

  bool get isValidated => outcome == DeliveryValidationOutcome.validated;
}

/// Delivery (`stock.picking`) actions for the sales app.
///
/// The validation sequence follows what Odoo's own web client does when the
/// Validate button is pressed, rather than forcing the transfer through:
/// reserve what is on hand, mark the reserved moves as picked, then validate.
/// Quantities are deliberately *not* raised to the full demand — on a
/// customer delivery that would ship stock the warehouse does not have.
class DeliveryService {
  DeliveryService._();

  static final DeliveryService instance = DeliveryService._();

  /// Validates the delivery with [pickingId].
  ///
  /// Throws whatever Odoo refuses with — an unreserved transfer, a lock date,
  /// missing rights — so the caller can show the server's own words.
  Future<DeliveryValidationResult> validateDelivery(int pickingId) async {
    final generation = await OdooSessionManager.serverGeneration();
    final context = confirmPickingContext(generation);

    // Reserve whatever is on hand. Odoo raises "Nothing to check the
    // availability for" when every move is already reserved or done, which is
    // a normal state for a delivery that is ready — not a reason to stop.
    try {
      await OdooSessionManager.safeCallKw({
        'model': 'stock.picking',
        'method': 'action_assign',
        'args': [
          [pickingId],
        ],
        'kwargs': {'context': context},
      });
    } catch (_) {}

    await _markReservedMovesPicked(pickingId);

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
  Future<void> _markReservedMovesPicked(int pickingId) async {
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
    if (moveIds is! List || moveIds.isEmpty) return;

    final moves = await OdooSessionManager.safeCallKw({
      'model': 'stock.move',
      'method': 'read',
      'args': [
        moveIds,
        ['state', 'quantity', 'picked'],
      ],
      'kwargs': {},
    });
    if (moves is! List) return;

    final toPick = <int>[];
    for (final move in moves.cast<Map<String, dynamic>>()) {
      final state = move['state'];
      if (state == 'done' || state == 'cancel') continue;
      final quantity = (move['quantity'] as num?) ?? 0;
      if (quantity <= 0) continue;
      if (move['picked'] == true) continue;
      toPick.add(move['id'] as int);
    }
    if (toPick.isEmpty) return;

    await OdooSessionManager.safeCallKw({
      'model': 'stock.move',
      'method': 'write',
      'args': [
        toPick,
        {'picked': true},
      ],
      'kwargs': {},
    });
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
