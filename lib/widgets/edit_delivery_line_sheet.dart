import 'package:flutter/material.dart';

import '../shared/design/mobo_tokens.dart';
import '../shared/widgets/mobo/mobo_dialog_buttons.dart';
import '../utils/quantity_format.dart';

/// What the user changed on a delivery line. A null field was left alone.
class DeliveryLineEdit {
  const DeliveryLineEdit({this.quantity, this.demand});

  final double? quantity;
  final double? demand;
}

/// Lets the user change a delivery line, as the Quantity and Demand columns of
/// Odoo's transfer form do.
///
/// [canEditQuantity] is false for a tracked product, whose quantity is the sum
/// of its lot or serial numbers and is set there. [canEditDemand] follows the
/// backend (the demand is locked on a locked transfer).
///
/// Returns what changed, or null when dismissed or nothing changed.
Future<DeliveryLineEdit?> showEditDeliveryLineSheet(
  BuildContext context, {
  required String productName,
  required String unit,
  required double demand,
  required double quantity,
  required bool canEditQuantity,
  required bool canEditDemand,
}) {
  return showModalBottomSheet<DeliveryLineEdit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.mobo.surface,
    // Wide screens get a centred sheet rather than one stretched edge to edge.
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(MoboRadius.sheetTop),
      ),
    ),
    builder: (_) => _EditDeliveryLineSheet(
      productName: productName,
      unit: unit,
      demand: demand,
      quantity: quantity,
      canEditQuantity: canEditQuantity,
      canEditDemand: canEditDemand,
    ),
  );
}

class _EditDeliveryLineSheet extends StatefulWidget {
  const _EditDeliveryLineSheet({
    required this.productName,
    required this.unit,
    required this.demand,
    required this.quantity,
    required this.canEditQuantity,
    required this.canEditDemand,
  });

  final String productName;
  final String unit;
  final double demand;
  final double quantity;
  final bool canEditQuantity;
  final bool canEditDemand;

  @override
  State<_EditDeliveryLineSheet> createState() => _EditDeliveryLineSheetState();
}

class _EditDeliveryLineSheetState extends State<_EditDeliveryLineSheet> {
  late final TextEditingController _quantity = TextEditingController(
    text: formatQuantity(widget.quantity),
  );
  late final TextEditingController _demand = TextEditingController(
    text: formatQuantity(widget.demand),
  );

  @override
  void dispose() {
    _quantity.dispose();
    _demand.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController c) => double.tryParse(c.text.trim());

  double get _quantityValue => _parse(_quantity) ?? 0;
  double get _demandValue => _parse(_demand) ?? 0;

  /// Why the values cannot be saved, or null.
  String? get _problem {
    if (widget.canEditQuantity && _parse(_quantity) == null) {
      return 'Enter a quantity.';
    }
    if (widget.canEditDemand && _parse(_demand) == null) {
      return 'Enter a demand.';
    }
    if (widget.canEditDemand && _demandValue <= 0) {
      return 'The demand must be more than zero.';
    }
    return null;
  }

  bool get _quantityChanged =>
      widget.canEditQuantity && (_quantityValue - widget.quantity).abs() > 1e-9;

  bool get _demandChanged =>
      widget.canEditDemand && (_demandValue - widget.demand).abs() > 1e-9;

  void _step(TextEditingController c, double delta) {
    c.text = stepQuantity(c.text, delta);
    setState(() {});
  }

  void _save() {
    Navigator.of(context).pop(
      DeliveryLineEdit(
        quantity: _quantityChanged ? _quantityValue : null,
        demand: _demandChanged ? _demandValue : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mobo;
    final problem = _problem;
    final over =
        widget.canEditQuantity &&
        _demandValue > 0 &&
        _quantityValue > _demandValue + 1e-9;
    final canSave = problem == null && (_quantityChanged || _demandChanged);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            MoboSpacing.page,
            10,
            MoboSpacing.page,
            MoboSpacing.page,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(MoboRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit Line',
                      style: MoboType.h3(colors.textPrimary),
                    ),
                  ),
                  _RoundIconButton(
                    icon: Icons.close,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ProductCard(
                name: widget.productName,
                demand: widget.demand,
                unit: widget.unit,
              ),
              const SizedBox(height: MoboSpacing.fieldGap + 4),
              _StepperField(
                fieldKey: const Key('line-quantity'),
                label: 'Quantity to deliver',
                controller: _quantity,
                unit: widget.unit,
                enabled: widget.canEditQuantity,
                onChanged: () => setState(() {}),
                onStep: (d) => _step(_quantity, d),
                note: widget.canEditQuantity
                    ? 'Enter what you are delivering, even when the warehouse '
                          'shows no stock.'
                    : 'Set by the lot or serial numbers: use Select on the '
                          'product.',
                noteIcon: widget.canEditQuantity
                    ? Icons.info_outline
                    : Icons.lock_outline,
                warning: over ? 'More than the demand.' : null,
              ),
              const SizedBox(height: MoboSpacing.fieldGap + 4),
              _StepperField(
                fieldKey: const Key('line-demand'),
                label: 'Demand',
                controller: _demand,
                unit: widget.unit,
                enabled: widget.canEditDemand,
                onChanged: () => setState(() {}),
                onStep: (d) => _step(_demand, d),
                note: widget.canEditDemand
                    ? null
                    : 'The demand is locked. Unlock the delivery from the menu '
                          'to change it.',
                noteIcon: Icons.lock_outline,
              ),
              if (problem != null) ...[
                const SizedBox(height: 12),
                _Message(
                  text: problem,
                  color: colors.error,
                  icon: Icons.error_outline,
                ),
              ],
              const SizedBox(height: MoboSpacing.page),
              MoboDialogButtons(
                secondaryLabel: 'Cancel',
                onSecondary: () => Navigator.of(context).pop(),
                primaryLabel: 'Save',
                onPrimary: canSave ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The product being edited, with its demand, in a tinted card.
class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.name,
    required this.demand,
    required this.unit,
  });

  final String name;
  final double demand;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobo;
    final demandText = unit.isEmpty
        ? formatQuantity(demand)
        : '${formatQuantity(demand)} $unit';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(MoboRadius.card),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(MoboRadius.field),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 20,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MoboType.fieldValue(
                    colors.isDark ? Colors.white : const Color(0xFF101010),
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Demand: $demandText',
                  style: MoboType.hint(colors.textSecondary, size: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled number field with a minus and a plus button either side.
class _StepperField extends StatefulWidget {
  const _StepperField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.unit,
    required this.enabled,
    required this.onChanged,
    required this.onStep,
    this.note,
    this.noteIcon = Icons.info_outline,
    this.warning,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final String unit;
  final bool enabled;
  final VoidCallback onChanged;
  final ValueChanged<double> onStep;
  final String? note;
  final IconData noteIcon;
  final String? warning;

  @override
  State<_StepperField> createState() => _StepperFieldState();
}

class _StepperFieldState extends State<_StepperField> {
  late final FocusNode _focus = FocusNode()..addListener(_onFocus);

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mobo;
    final focused = _focus.hasFocus;
    final warning = widget.warning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: MoboType.label(
            colors.textPrimary,
          ).copyWith(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Opacity(
          opacity: widget.enabled ? 1 : 0.6,
          child: Row(
            children: [
              _RoundIconButton(
                icon: Icons.remove,
                tooltip: 'Decrease',
                filled: true,
                onPressed: widget.enabled ? () => widget.onStep(-1) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: MoboSpacing.iconButton,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: colors.inputFill,
                    borderRadius: BorderRadius.circular(MoboRadius.field),
                    border: Border.all(
                      color: warning != null
                          ? MoboStatusColors.orange
                          : focused
                          ? colors.primary
                          : Colors.transparent,
                      width: focused || warning != null ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: widget.fieldKey,
                          controller: widget.controller,
                          focusNode: _focus,
                          enabled: widget.enabled,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [QuantityInputFormatter()],
                          style: MoboType.fieldValue(
                            colors.textPrimary,
                          ).copyWith(fontSize: 20, fontWeight: FontWeight.w700),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                          onChanged: (_) => widget.onChanged(),
                        ),
                      ),
                      if (widget.unit.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          widget.unit,
                          style: MoboType.body(colors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _RoundIconButton(
                icon: Icons.add,
                tooltip: 'Increase',
                filled: true,
                onPressed: widget.enabled ? () => widget.onStep(1) : null,
              ),
            ],
          ),
        ),
        if (warning != null) ...[
          const SizedBox(height: 8),
          _Message(
            text: warning,
            color: MoboStatusColors.orange,
            icon: Icons.warning_amber_rounded,
          ),
        ],
        if (widget.note != null) ...[
          const SizedBox(height: 8),
          _Message(
            text: widget.note!,
            color: colors.textSecondary,
            icon: widget.noteIcon,
          ),
        ],
      ],
    );
  }
}

/// A small icon and a line of text: a hint, a warning or an error.
class _Message extends StatelessWidget {
  const _Message({required this.text, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: MoboType.hint(color, size: 12.5))),
      ],
    );
  }
}

/// A round icon button: the stepper's minus and plus, and the close button.
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Tinted with the brand colour (the stepper) rather than the neutral fill
  /// the close button uses.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobo;
    final enabled = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled && enabled ? colors.primaryTint : colors.inputFill,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: MoboSpacing.iconButton,
            height: MoboSpacing.iconButton,
            child: Icon(
              icon,
              size: 22,
              color: filled && enabled
                  ? colors.primary
                  : colors.textSecondary.withValues(alpha: enabled ? 1 : 0.6),
            ),
          ),
        ),
      ),
    );
  }
}
