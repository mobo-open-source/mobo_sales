import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../../models/delivery.dart';
import '../../services/data_change_bus.dart';
import '../../services/delivery_lot_service.dart';
import '../../services/delivery_service.dart';
import '../../services/odoo_session_manager.dart';
import '../../services/permission_service.dart';
import '../../shared/widgets/mobo/mobo_bottom_action_bar.dart';
import '../../shared/widgets/mobo/mobo_dialog_buttons.dart';
import '../../utils/guarded_action.dart';
import '../../utils/quantity_format.dart';
import '../../widgets/edit_delivery_line_sheet.dart';
import '../../widgets/lot_selection_sheet.dart';
import '../../widgets/custom_snackbar.dart';

class DeliveryDetailsScreen extends StatefulWidget {
  final int deliveryId;

  const DeliveryDetailsScreen({super.key, required this.deliveryId});

  @override
  State<DeliveryDetailsScreen> createState() => _DeliveryDetailsScreenState();
}

class _DeliveryDetailsScreenState extends State<DeliveryDetailsScreen> {
  Map<String, dynamic>? _deliveryData;
  List<Map<String, dynamic>> _productMoves = [];

  /// `serial`, `lot` or `none` by product id.
  Map<int, String> _tracking = {};

  /// The lots reserved on each move, by move id.
  Map<int, List<MoveLot>> _moveLots = {};

  /// Tracked products whose reserved quantity has no lot or serial number yet.
  List<String> _missingLots = [];

  /// What the delivery's operation type allows for lots and serial numbers.
  LotOptions _lotOptions = const LotOptions();
  bool _isLoading = true;
  String? _errorMessage;

  /// Write access to `stock.picking`, read once. Null until it is known, so
  /// the Validate button does not flicker in disabled and then enable.
  bool? _canValidate;

  /// True while the page was left in a state the list should re-read.
  bool _didChange = false;

  @override
  void initState() {
    super.initState();
    _fetchDeliveryDetails();
    _checkValidatePermission();
  }

  Future<void> _checkValidatePermission() async {
    final can = await PermissionService.instance.canWrite('stock.picking');
    if (!mounted) return;
    setState(() => _canValidate = can);
  }

  String get _state => _deliveryData?['state']?.toString() ?? '';

  bool get _canShowValidate =>
      _deliveryData != null && kValidatableDeliveryStates.contains(_state);

  /// The quantity on the open lines: what Validate would deliver.
  double get _totalQuantity {
    var total = 0.0;
    for (final move in _productMoves) {
      final state = move['state']?.toString();
      if (state == 'done' || state == 'cancel') continue;
      total += ((move['quantity'] as num?) ?? 0).toDouble();
    }
    return total;
  }

  /// Whether Validate can work now, by Odoo's own rule.
  bool get _validateReady => canValidateDelivery(_state, _totalQuantity);

  /// Whether the lines can be edited: the user may write, and the delivery is
  /// still open.
  bool get _canEditLines =>
      _canValidate == true && kValidatableDeliveryStates.contains(_state);

  Future<void> _validateDelivery() async {
    final name = _safeString(_deliveryData?['name'], 'this delivery');

    final confirmed = await _showValidateDialog(name);
    if (confirmed != true || !mounted) return;

    final result = await runGuardedAction<DeliveryValidationResult>(
      context: context,
      message: 'Confirming delivery...',
      subtitle: 'Validating the transfer in Odoo',
      failurePrefix: 'Failed to confirm delivery',
      action: () =>
          DeliveryService.instance.validateDelivery(widget.deliveryId),
    );

    if (result == null || !mounted) return;

    if (result.outcome == DeliveryValidationOutcome.notReserved) {
      await _showNotReservedDialog(name);
      return;
    }
    if (result.outcome == DeliveryValidationOutcome.needsBackorder) {
      await _resolveBackorder(name, result);
      return;
    }
    if (result.outcome == DeliveryValidationOutcome.lotsRequired) {
      await _fetchDeliveryDetails();
      if (mounted) {
        CustomSnackbar.showWarning(
          context,
          'Select the lot/serial numbers first: '
          '${result.step ?? 'tracked products'}.',
        );
      }
      return;
    }

    _didChange = true;
    // A delivered order changes its sale order's delivery status, which the
    // quotation list and details both show.
    DataChangeBus.instance.publish(
      DataEntity.quotation,
      DataChangeKind.updated,
      origin: this,
    );

    if (result.isValidated) {
      CustomSnackbar.showSuccess(context, '$name confirmed');
    } else {
      // Odoo stopped to ask something it can only ask in its own UI — a
      // backorder, a quality check. Saying so beats reporting a success the
      // picking did not have.
      final step = result.step;
      CustomSnackbar.showInfo(
        context,
        'Odoo needs another confirmation to finish $name'
        '${step != null && step.isNotEmpty ? ' ($step)' : ''}. '
        'Please complete it in Odoo.',
      );
    }

    await _fetchDeliveryDetails();
  }

  /// Less than the demand is being delivered. Odoo asks whether to keep the
  /// rest in a backorder; this asks the same and sends the answer.
  Future<void> _resolveBackorder(
    String name,
    DeliveryValidationResult result,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: Text(
          'Create a backorder?',
          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Theme.of(ctx).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Less than the demand of $name is being delivered. A backorder keeps '
          'the rest to deliver later; without one it is dropped.',
          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
            color: isDark
                ? Colors.grey[300]
                : Theme.of(ctx).colorScheme.onSurfaceVariant,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Create Backorder'),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('No Backorder'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (answer == null || !mounted) {
      // Nothing was validated; the quantities typed so far stay on the lines.
      await _fetchDeliveryDetails();
      return;
    }

    final done = await runGuardedAction<DeliveryValidationResult>(
      context: context,
      message: 'Confirming delivery...',
      failurePrefix: 'Failed to confirm delivery',
      action: () => DeliveryService.instance.resolveBackorder(
        widget.deliveryId,
        createBackorder: answer,
        context: result.wizardContext ?? const {},
      ),
    );
    if (done == null || !mounted) return;

    _didChange = true;
    DataChangeBus.instance.publish(
      DataEntity.quotation,
      DataChangeKind.updated,
      origin: this,
    );
    if (done.isValidated) {
      CustomSnackbar.showSuccess(
        context,
        answer ? '$name confirmed, backorder created' : '$name confirmed',
      );
    } else {
      CustomSnackbar.showInfo(
        context,
        'Odoo needs another confirmation to finish $name. Please complete it '
        'in Odoo.',
      );
    }
    await _fetchDeliveryDetails();
  }

  /// Explains why nothing was validated: no stock is reserved at the source.
  Future<void> _showNotReservedDialog(String name) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        icon: Icon(
          HugeIcons.strokeRoundedAlert02,
          color: Colors.orange[700],
          size: 36,
        ),
        title: Text(
          'No quantity to deliver',
          textAlign: TextAlign.center,
          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Theme.of(ctx).colorScheme.onSurface,
          ),
        ),
        content: Text(
          '$name cannot be confirmed because none of its products has a '
          'quantity to deliver.\n\n'
          'Edit a product line to enter the quantity, or receive stock and '
          'use Check Availability, then confirm the delivery again.',
          textAlign: TextAlign.center,
          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
            color: isDark
                ? Colors.grey[300]
                : Theme.of(ctx).colorScheme.onSurfaceVariant,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'OK',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Runs one of Odoo's other transfer buttons, then re-reads the page.
  Future<void> _runAction({
    required String message,
    required String failurePrefix,
    required Future<void> Function() action,
    String? successMessage,
  }) async {
    final ok = await runGuardedAction<bool>(
      context: context,
      message: message,
      failurePrefix: failurePrefix,
      action: () async {
        await action();
        return true;
      },
    );
    if (ok != true || !mounted) return;
    _didChange = true;
    DataChangeBus.instance.publish(
      DataEntity.quotation,
      DataChangeKind.updated,
      origin: this,
    );
    await _fetchDeliveryDetails();
    if (mounted && successMessage != null) {
      CustomSnackbar.showSuccess(context, successMessage);
    }
  }

  Future<void> _checkAvailability() async {
    String? state;
    final ok = await runGuardedAction<bool>(
      context: context,
      message: 'Checking availability...',
      failurePrefix: 'Failed to check availability',
      action: () async {
        state = await DeliveryService.instance.checkAvailability(
          widget.deliveryId,
        );
        return true;
      },
    );
    if (ok != true || !mounted) return;
    _didChange = true;
    await _fetchDeliveryDetails();
    if (!mounted) return;
    if (isDeliveryReady(state ?? '')) {
      CustomSnackbar.showSuccess(context, 'Stock reserved. Ready to confirm.');
    } else {
      CustomSnackbar.showWarning(
        context,
        'The products are still not available at the source location.',
      );
    }
  }

  Future<void> _markAsTodo() => _runAction(
    message: 'Updating delivery...',
    failurePrefix: 'Failed to mark as To Do',
    action: () => DeliveryService.instance.markAsTodo(widget.deliveryId),
  );

  Future<void> _unreserve() => _runAction(
    message: 'Releasing reserved stock...',
    failurePrefix: 'Failed to unreserve',
    successMessage: 'Reserved stock released',
    action: () => DeliveryService.instance.unreserve(widget.deliveryId),
  );

  Future<void> _cancelDelivery() async {
    final name = _safeString(_deliveryData?['name'], 'this delivery');
    final confirmed = await _confirmDialog(
      title: 'Cancel Delivery',
      body:
          'Cancel $name? Its reserved stock is released and it can no '
          'longer be delivered.',
      secondary: 'Keep',
      primary: 'Cancel Delivery',
    );
    if (confirmed != true || !mounted) return;
    await _runAction(
      message: 'Cancelling delivery...',
      failurePrefix: 'Failed to cancel delivery',
      successMessage: '$name cancelled',
      action: () => DeliveryService.instance.cancel(widget.deliveryId),
    );
  }

  Future<void> _toggleLock() => _runAction(
    message: 'Updating delivery...',
    failurePrefix: 'Failed to change the lock',
    action: () => DeliveryService.instance.toggleLock(widget.deliveryId),
  );

  /// Edits one line the way Odoo's transfer form does: the quantity to deliver
  /// (also when there is no stock, which is how such a delivery gets
  /// validated), and the demand while the delivery is unlocked.
  Future<void> _editLine(Map<String, dynamic> move) async {
    final product = move['product_id'];
    final tracked =
        product is List &&
        product.isNotEmpty &&
        (_tracking[product[0] as int] ?? 'none') != 'none';
    final uomValue = move['product_uom'] ?? move['uom_id'];
    final unit = uomValue is List && uomValue.length > 1
        ? uomValue[1].toString()
        : '';
    final moveState = move['state']?.toString() ?? '';
    final canEditDemand =
        moveState == 'draft' || _deliveryData?['is_locked'] != true;

    final edit = await showEditDeliveryLineSheet(
      context,
      productName: _safeString(move['product_id']),
      unit: unit,
      demand: ((move['product_uom_qty'] as num?) ?? 0).toDouble(),
      quantity: ((move['quantity'] as num?) ?? 0).toDouble(),
      canEditQuantity: !tracked,
      canEditDemand: canEditDemand,
    );
    if (edit == null || !mounted) return;

    await _runAction(
      message: 'Saving line...',
      failurePrefix: 'Failed to save the line',
      action: () => DeliveryService.instance.updateMove(
        move['id'] as int,
        quantity: edit.quantity,
        demand: edit.demand,
      ),
    );
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String body,
    required String secondary,
    required String primary,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: Text(
          title,
          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Theme.of(ctx).colorScheme.onSurface,
          ),
        ),
        content: Text(
          body,
          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
            color: isDark
                ? Colors.grey[300]
                : Theme.of(ctx).colorScheme.onSurfaceVariant,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        actions: [
          MoboDialogButtons(
            secondaryLabel: secondary,
            onSecondary: () => Navigator.of(ctx).pop(false),
            primaryLabel: primary,
            onPrimary: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showValidateDialog(String name) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: Text(
          'Confirm Delivery',
          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Theme.of(ctx).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Validate $name? The quantities on its lines will be delivered and '
          'stock updated. If less than the demand is delivered, you can keep '
          'the rest as a backorder.',
          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
            color: isDark
                ? Colors.grey[300]
                : Theme.of(ctx).colorScheme.onSurfaceVariant,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        actions: [
          MoboDialogButtons(
            secondaryLabel: 'Cancel',
            onSecondary: () => Navigator.of(ctx).pop(false),
            primaryLabel: 'Validate',
            onPrimary: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchDeliveryDetails() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      // The list of a picking's moves is `move_ids_without_package` up to
      // Odoo 18 and `move_ids` from 19, where the old field no longer exists.
      final generation = await OdooSessionManager.serverGeneration();
      final movesField = pickingMovesField(generation);

      List<String> fieldsToFetch = [
        'name',
        'state',
        'partner_id',
        'scheduled_date',
        'date_deadline',
        'date_done',
        'origin',
        'picking_type_code',
        'picking_type_id',
        'location_id',
        'location_dest_id',
        movesField,
        'note',
        'priority',
        'user_id',
        'company_id',
        'backorder_id',
        'is_locked',
      ];

      dynamic result;
      int retryCount = 0;
      const int maxRetries = 3;

      while (retryCount < maxRetries) {
        try {
          result = await client.callKw({
            'model': 'stock.picking',
            'method': 'read',
            'args': [
              [widget.deliveryId],
            ],
            'kwargs': {'fields': fieldsToFetch},
          });
          break;
        } catch (e) {
          if (e.toString().contains('Invalid field')) {
            final fieldMatch = RegExp(
              r"Invalid field '([^']+)' on",
            ).firstMatch(e.toString());
            final invalidField = fieldMatch?.group(1);
            if (invalidField != null && fieldsToFetch.contains(invalidField)) {
              fieldsToFetch.remove(invalidField);
              retryCount++;
              await Future.delayed(const Duration(milliseconds: 300));
              continue;
            }
          }

          rethrow;
        }
      }

      if (!mounted) return;

      if (result is List && result.isNotEmpty) {
        final deliveryData = result[0] as Map<String, dynamic>;

        List<Map<String, dynamic>> moves = [];

        List<dynamic>? moveIds;
        if (deliveryData[movesField] != null &&
            deliveryData[movesField] is List &&
            (deliveryData[movesField] as List).isNotEmpty) {
          moveIds = deliveryData[movesField];
        } else {
          try {
            final moveSearchResult = await client.callKw({
              'model': 'stock.move',
              'method': 'search',
              'args': [
                [
                  ['picking_id', '=', widget.deliveryId],
                ],
              ],
              'kwargs': {'limit': 50},
            });
            if (moveSearchResult is List && moveSearchResult.isNotEmpty) {
              moveIds = moveSearchResult;
            }
          } catch (e) {}
        }

        if (moveIds != null && moveIds.isNotEmpty) {
          // The unit of a move is `product_uom` up to Odoo 19 and `uom_id`
          // from 20. A read naming a field the server lacks fails entirely,
          // which left the product list empty, so try each candidate in turn.
          for (final uomField in stockMoveUomFields(generation)) {
            try {
              final moveResult = await client.callKw({
                'model': 'stock.move',
                'method': 'read',
                'args': [moveIds],
                'kwargs': {
                  'fields': [
                    'product_id',
                    'product_uom_qty',
                    'quantity',
                    uomField,
                    'state',
                    'description_picking',
                  ],
                },
              });
              if (moveResult is List) {
                moves = moveResult.cast<Map<String, dynamic>>();
              }
              break;
            } catch (e) {}
          }
        }

        // Lot and serial numbers. Not needed to show the page, so a failure
        // here leaves the products listed without them.
        var tracking = <int, String>{};
        var moveLots = <int, List<MoveLot>>{};
        var missing = <String>[];
        var lotOptions = const LotOptions();
        try {
          tracking = await DeliveryLotService.instance.tracking([
            for (final move in moves)
              if (move['product_id'] is List) move['product_id'][0] as int,
          ]);
          if (tracking.values.any((t) => t != 'none')) {
            moveLots = await DeliveryLotService.instance.moveLots(
              widget.deliveryId,
            );
            missing = await DeliveryLotService.instance.productsMissingLots(
              widget.deliveryId,
            );
            final type = deliveryData['picking_type_id'];
            if (type is List && type.isNotEmpty) {
              lotOptions = await DeliveryLotService.instance.lotOptions(
                type[0] as int,
              );
            }
          }
        } catch (_) {}

        if (!mounted) return;
        setState(() {
          _deliveryData = deliveryData;
          _productMoves = moves;
          _tracking = tracking;
          _moveLots = moveLots;
          _missingLots = missing;
          _lotOptions = lotOptions;
          _isLoading = false;
        });
      } else {
        throw Exception('Delivery not found');
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  String _safeString(dynamic value, [String defaultValue = 'N/A']) {
    if (value == null || value == false) return defaultValue;
    if (value is List && value.length > 1) return value[1].toString();
    if (value is String) return value;
    return value.toString();
  }

  Color _getStateColor(String state) {
    switch (state) {
      case 'done':
        return Colors.green;
      case 'assigned':
        return Colors.blue;
      case 'confirmed':
        return Colors.orange;
      case 'cancel':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStateLabel(String state) {
    switch (state) {
      case 'draft':
        return 'Draft';
      case 'waiting':
        return 'Waiting';
      case 'confirmed':
        return 'Confirmed';
      case 'assigned':
        return 'Ready';
      case 'done':
        return 'Done';
      case 'cancel':
        return 'Cancelled';
      default:
        return state;
    }
  }

  String _getPriorityLabel(String priority) {
    switch (priority) {
      case '0':
        return 'Normal';
      case '1':
        return 'Urgent';
      case '2':
        return 'Very Urgent';
      default:
        return 'Normal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _didChange);
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          title: Text(
            'Delivery Details',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          leading: IconButton(
            onPressed: () => Navigator.pop(context, _didChange),
            icon: Icon(
              HugeIcons.strokeRoundedArrowLeft01,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          backgroundColor: backgroundColor,
          foregroundColor: isDark
              ? Colors.white
              : Theme.of(context).primaryColor,
          elevation: 0,
          actions: [_buildMoreMenu(isDark)],
        ),
        body: _isLoading
            ? _buildShimmerLoading(isDark)
            : _errorMessage != null
            ? _buildErrorState(isDark)
            : _deliveryData != null
            ? _buildDeliveryDetails(isDark)
            : const SizedBox.shrink(),
        bottomNavigationBar: _isLoading || !_canShowValidate
            ? null
            : MoboBottomActionBar(child: _buildActionBar(isDark)),
      ),
    );
  }

  /// Odoo's transfer action menu: Mark as To Do, Check Availability,
  /// Unreserve and Cancel, each shown in the states Odoo shows it in.
  Widget _buildMoreMenu(bool isDark) {
    final hasData = _deliveryData != null;
    final canTodo = hasData && _state == 'draft';
    final canCheck = hasData && kCheckAvailabilityStates.contains(_state);
    final canUnreserve =
        hasData && kUnreservableDeliveryStates.contains(_state);
    final canCancel = hasData && kCancellableDeliveryStates.contains(_state);
    // Odoo's Unlock / Lock: the demand of the lines can only be changed on an
    // unlocked delivery.
    final locked = _deliveryData?['is_locked'];
    final canToggleLock =
        hasData && locked is bool && _state != 'done' && _state != 'cancel';
    if (_isLoading ||
        _canValidate != true ||
        !(canTodo || canCheck || canUnreserve || canCancel || canToggleLock)) {
      return const SizedBox.shrink();
    }

    final textColor = isDark ? Colors.white : Colors.black87;
    PopupMenuItem<String> item(String value, IconData icon, String label) =>
        PopupMenuItem(
          value: value,
          child: Row(
            children: [
              Icon(icon, size: 20, color: textColor),
              const SizedBox(width: 12),
              Text(label, style: TextStyle(color: textColor)),
            ],
          ),
        );

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: isDark ? Colors.white : Colors.black),
      // Plain surface: the theme's tinted popup colour read as a brand-coloured
      // block behind the items.
      color: isDark ? Colors.grey[900] : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        switch (value) {
          case 'todo':
            _markAsTodo();
          case 'check':
            _checkAvailability();
          case 'unreserve':
            _unreserve();
          case 'lock':
            _toggleLock();
          case 'cancel':
            _cancelDelivery();
        }
      },
      itemBuilder: (_) => [
        if (canTodo)
          item(
            'todo',
            HugeIcons.strokeRoundedCheckmarkCircle02,
            'Mark as To Do',
          ),
        if (canCheck)
          item(
            'check',
            HugeIcons.strokeRoundedPackageSearch,
            'Check Availability',
          ),
        if (canUnreserve)
          item('unreserve', HugeIcons.strokeRoundedPackageRemove, 'Unreserve'),
        if (canToggleLock)
          item(
            'lock',
            locked == true ? Icons.lock_open_outlined : Icons.lock_outline,
            locked == true ? 'Unlock' : 'Lock',
          ),
        if (canCancel)
          item('cancel', HugeIcons.strokeRoundedCancel01, 'Cancel Delivery'),
      ],
    );
  }

  /// The pinned action: Validate, disabled until the lines carry a quantity,
  /// as in Odoo. The steps that get a transfer ready — Check Availability, or
  /// typing a quantity on a line — are the menu and the line's Edit button.
  Widget _buildActionBar(bool isDark) {
    final ready = _validateReady;
    final lotsMissing = ready && _missingLots.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lotsMissing)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Select the lot/serial numbers for ${_missingLots.join(', ')} '
              'before confirming.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ),
        if (!ready)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'No quantity to deliver yet. Edit a product line to enter the '
              'quantity, or use Check Availability in the menu once stock '
              'arrives.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey[700],
              ),
            ),
          ),
        _buildValidateButton(isDark),
      ],
    );
  }

  Widget _buildValidateButton(bool isDark) {
    final primaryColor = Theme.of(context).primaryColor;
    // Null means the check has not come back yet; the button waits rather
    // than offering an action that would be refused.
    final enabled = _canValidate == true;
    // Odoo's Validate only works once a quantity is on the lines, so until
    // then the button is disabled rather than offered and refused.
    final ready = _validateReady;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _canValidate == null || !ready || _missingLots.isNotEmpty
            ? null
            : enabled
            ? _validateDelivery
            : () => CustomSnackbar.showError(
                context,
                'Permission Denied: You do not have permission to validate '
                'deliveries (stock.picking write). Please contact your '
                'administrator.',
              ),
        icon: const Icon(
          HugeIcons.strokeRoundedCheckmarkCircle02,
          color: Colors.white,
          size: 20,
        ),
        label: const Text(
          'Confirm Delivery',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          disabledBackgroundColor: isDark
              ? Colors.grey[700]!
              : Colors.grey[400]!,
        ),
      ),
    );
  }

  Widget _buildShimmerLoading(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Shimmer.fromColors(
            baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
            highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Shimmer.fromColors(
            baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
            highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
            child: Container(
              height: 300,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Shimmer.fromColors(
            baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
            highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
              const SizedBox(height: 16),
              Text(
                'Error Loading Delivery',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Unknown error',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchDeliveryDetails,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeliveryDetails(bool isDark) {
    final state = _safeString(_deliveryData!['state'], 'draft');
    final stateColor = _getStateColor(state);

    return RefreshIndicator(
      onRefresh: _fetchDeliveryDetails,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionCard(
              title: 'Delivery Information',
              icon: HugeIcons.strokeRoundedPackageDelivered,
              iconColor: isDark ? Colors.white70 : Colors.grey[800],
              isDark: isDark,
              headerAction: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: stateColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: stateColor.withOpacity(0.25),
                    width: 1,
                  ),
                ),
                child: Text(
                  _getStateLabel(state),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: stateColor,
                  ),
                ),
              ),
              children: [
                if (_deliveryData!['partner_id'] != null)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedUser,
                    'Customer',
                    _safeString(_deliveryData!['partner_id']),
                  ),
                if (_deliveryData!['picking_type_id'] != null)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedPackage,
                    'Operation Type',
                    _safeString(_deliveryData!['picking_type_id']),
                  ),
                if (_deliveryData!['origin'] != null)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedFileAttachment,
                    'Source Document',
                    _safeString(_deliveryData!['origin']),
                  ),
                if (_deliveryData!['backorder_id'] != null &&
                    _deliveryData!['backorder_id'] != false)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedPackageRemove,
                    'Backorder of',
                    _safeString(_deliveryData!['backorder_id']),
                  ),
                if (_deliveryData!['priority'] != null &&
                    _deliveryData!['priority'] != '0')
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedFlag02,
                    'Priority',
                    _getPriorityLabel(_deliveryData!['priority'].toString()),
                  ),
                if (_deliveryData!['scheduled_date'] != null)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedCalendar03,
                    'Scheduled Date',
                    DateFormat(
                      'MMM dd, yyyy HH:mm',
                    ).format(DateTime.parse(_deliveryData!['scheduled_date'])),
                  ),
                if (_deliveryData!['date_deadline'] != null)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedAlarmClock,
                    'Deadline',
                    DateFormat(
                      'MMM dd, yyyy HH:mm',
                    ).format(DateTime.parse(_deliveryData!['date_deadline'])),
                  ),
                if (_deliveryData!['date_done'] != null &&
                    _deliveryData!['date_done'] != false)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedCheckmarkCircle02,
                    'Done Date',
                    DateFormat(
                      'MMM dd, yyyy HH:mm',
                    ).format(DateTime.parse(_deliveryData!['date_done'])),
                  ),
                if (_deliveryData!['location_id'] != null)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedLocation01,
                    'From',
                    _safeString(_deliveryData!['location_id']),
                  ),
                if (_deliveryData!['location_dest_id'] != null)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedLocation03,
                    'To',
                    _safeString(_deliveryData!['location_dest_id']),
                  ),
                if (_deliveryData!['user_id'] != null)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedUserCircle,
                    'Responsible',
                    _safeString(_deliveryData!['user_id']),
                  ),
              ],
            ),

            if (_productMoves.isNotEmpty)
              _buildSectionCard(
                title: 'Products (${_productMoves.length})',
                icon: HugeIcons.strokeRoundedPackage,
                iconColor: isDark ? Colors.white70 : Colors.grey[800],
                isDark: isDark,
                children: [_buildMovesTable(isDark)],
              ),

            if (_deliveryData!['note'] != null &&
                _deliveryData!['note'] != false)
              _buildSectionCard(
                title: 'Notes',
                icon: HugeIcons.strokeRoundedNote,
                iconColor: isDark ? Colors.white70 : Colors.grey[800],
                isDark: isDark,
                children: [
                  Text(
                    _safeString(_deliveryData!['note']),
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                      height: 1.5,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color? iconColor,
    required bool isDark,
    required List<Widget> children,
    Widget? headerAction,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              if (headerAction != null) headerAction,
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(bool isDark, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.grey[200] : Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The delivery's lines as a table, the way the order lines of a quotation
  /// are shown: Product, Demand, Quantity and Status in columns, the quantity
  /// in a pill. Tapping the quantity (or the demand) edits the line, or, for a
  /// tracked product, chooses its lot or serial numbers.
  Widget _buildMovesTable(bool isDark) {
    final border = isDark ? Colors.grey[700]! : Colors.grey[300]!;
    final headStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: isDark ? Colors.white : Colors.grey[800],
    );

    Widget head(String text) => TableCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(text, style: headStyle),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder(horizontalInside: BorderSide(color: border)),
          columnWidths: const {
            0: FixedColumnWidth(175),
            1: FixedColumnWidth(125),
            2: FixedColumnWidth(130),
            3: FixedColumnWidth(150),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF3A3A3A)
                    : const Color(0xFFF8F9FA),
              ),
              children: [
                head('Product'),
                head('Quantity'),
                head('Demand'),
                head('Status'),
              ],
            ),
            for (var i = 0; i < _productMoves.length; i++)
              _buildMoveRow(i, _productMoves[i], isDark),
          ],
        ),
      ),
    );
  }

  TableRow _buildMoveRow(int index, Map<String, dynamic> move, bool isDark) {
    final demand = ((move['product_uom_qty'] as num?) ?? 0).toDouble();
    final quantity = ((move['quantity'] as num?) ?? 0).toDouble();
    // `product_uom` up to Odoo 19, `uom_id` from 20.
    final uomValue = move['product_uom'] ?? move['uom_id'];
    final unit = uomValue is List && uomValue.length > 1
        ? uomValue[1].toString()
        : '';
    final state = move['state']?.toString() ?? 'draft';
    final text = isDark ? Colors.grey[300] : Colors.grey[700];

    final product = move['product_id'];
    final tracked =
        product is List &&
        product.isNotEmpty &&
        (_tracking[product[0] as int] ?? 'none') != 'none';
    final canEdit =
        _canEditLines &&
        state != 'done' &&
        state != 'cancel' &&
        move['id'] is int;

    // Tracked: the quantity is the sum of the lots, so it is set there.
    void onTap() => tracked && _canValidate == true
        ? _selectLots(move, _tracking[product[0] as int] == 'serial')
        : _editLine(move);

    Widget cell(Widget child, {VoidCallback? tap}) => TableCell(
      child: InkWell(
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Align(alignment: Alignment.centerLeft, child: child),
        ),
      ),
    );

    final (stateLabel, stateColor) = switch (state) {
      'done' => ('Done', Colors.green),
      'assigned' => ('Available', Colors.green),
      'partially_available' => ('Partially Available', Colors.orange),
      'cancel' => ('Cancelled', Colors.grey),
      'draft' => ('Draft', Colors.grey),
      _ => ('Not Available', Colors.red),
    };

    return TableRow(
      children: [
        TableCell(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${index + 1}.',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: text,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _safeString(move['product_id']),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: text,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
                ..._buildLotSection(move, isDark),
              ],
            ),
          ),
        ),
        cell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatQuantity(quantity),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (canEdit) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.edit, size: 13, color: Colors.white70),
                ],
              ],
            ),
          ),
          tap: canEdit ? onTap : null,
        ),
        cell(
          Text(
            unit.isEmpty
                ? formatQuantity(demand)
                : '${formatQuantity(demand)} $unit',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: text,
            ),
          ),
          tap: canEdit ? () => _editLine(move) : null,
        ),
        cell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: stateColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: stateColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              stateLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: stateColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The lot or serial numbers of a tracked line, and the button to choose
  /// them. Empty for an untracked product.
  List<Widget> _buildLotSection(Map<String, dynamic> move, bool isDark) {
    final product = move['product_id'];
    if (product is! List || product.isEmpty) return const [];
    final tracking = _tracking[product[0] as int] ?? 'none';
    if (tracking == 'none') return const [];

    final lots = _moveLots[move['id'] as int] ?? const <MoveLot>[];
    final named = lots.where((l) => l.lotId != null).toList();
    final missing =
        lots.any((l) => l.lotId == null && l.quantity > 0) || lots.isEmpty;
    final state = move['state']?.toString() ?? '';
    final editable =
        _canValidate == true &&
        const {
          'assigned',
          'confirmed',
          'waiting',
          'partially_available',
        }.contains(state) &&
        kValidatableDeliveryStates.contains(_state);
    final muted = isDark ? Colors.grey[400] : Colors.grey[600];
    final label = tracking == 'serial' ? 'Serial Numbers' : 'Lots';

    return [
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ),
          if (editable)
            TextButton(
              onPressed: () => _selectLots(move, tracking == 'serial'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                named.isEmpty ? 'Select' : 'Change',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
      if (named.isEmpty)
        Text(
          missing && state != 'done'
              ? 'Required: no ${label.toLowerCase()} selected'
              : 'None',
          style: TextStyle(
            fontSize: 12,
            color: missing && state != 'done' ? Colors.red : muted,
          ),
        )
      else
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final lot in named)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tracking == 'serial'
                      ? lot.name
                      : '${lot.name} × ${formatQuantity(lot.quantity)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
    ];
  }

  Future<void> _selectLots(Map<String, dynamic> move, bool isSerial) async {
    final product = move['product_id'] as List;
    final productId = product[0] as int;
    final moveId = move['id'] as int;
    final locationId = _deliveryData?['location_id'] is List
        ? (_deliveryData!['location_id'] as List)[0] as int
        : null;
    final destinationId = _deliveryData?['location_dest_id'] is List
        ? (_deliveryData!['location_dest_id'] as List)[0] as int
        : null;
    if (locationId == null || destinationId == null) {
      CustomSnackbar.showError(context, 'The delivery has no source location.');
      return;
    }

    final current = <int, double>{
      for (final lot in _moveLots[moveId] ?? const <MoveLot>[])
        if (lot.lotId != null) lot.lotId!: lot.quantity,
    };

    final options = _lotOptions;
    final companyId = _deliveryData?['company_id'] is List
        ? (_deliveryData!['company_id'] as List)[0] as int
        : null;

    // What there is to pick from and, where the delivery may create lots, the
    // number Odoo would suggest to start from.
    final loaded =
        await runGuardedAction<({List<LotStock> lots, String? next})>(
          context: context,
          message: 'Loading ${isSerial ? 'serial numbers' : 'lots'}...',
          failurePrefix: 'Failed to load lots',
          action: () async {
            final lots = options.canUseExisting
                ? await DeliveryLotService.instance.availableLots(
                    productId: productId,
                    locationId: locationId,
                    ownReserved: current,
                  )
                : <LotStock>[];
            final next = options.canCreate && isSerial
                ? await DeliveryLotService.instance.nextSerial(
                    productId,
                    companyId,
                  )
                : null;
            return (lots: lots, next: next);
          },
        );
    if (loaded == null || !mounted) return;

    final demand = ((move['product_uom_qty'] as num?) ?? 0).toDouble();
    final chosen = await showLotSelectionSheet(
      context,
      productName: _safeString(move['product_id']),
      demand: demand,
      isSerial: isSerial,
      lots: loaded.lots,
      selected: current,
      canCreate: options.canCreate,
      canUseExisting: options.canUseExisting,
      suggestedFirst: loaded.next,
      generate: DeliveryLotService.instance.generateNames,
    );
    if (chosen == null || !mounted) return;

    await _runAction(
      message: 'Saving selection...',
      failurePrefix: 'Failed to save the selection',
      successMessage: 'Selection saved',
      action: () => DeliveryLotService.instance.saveLots(
        pickingId: widget.deliveryId,
        moveId: moveId,
        productId: productId,
        locationId: locationId,
        destinationId: destinationId,
        lots: chosen.existing,
        newLots: chosen.created,
        companyId: companyId,
      ),
    );
  }
}
