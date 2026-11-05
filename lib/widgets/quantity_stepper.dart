import 'package:flutter/material.dart';

import '../utils/quantity_format.dart';

/// The quantity box of an order or invoice line: a number field with a minus
/// and a plus beside it.
///
/// Reports every valid value as it is typed or stepped. Built for the narrow
/// half of a row: the text shrinks as the number grows instead of being clipped.
class QuantityStepper extends StatefulWidget {
  final double initialValue;
  final ValueChanged<double> onChanged;

  const QuantityStepper({
    super.key,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<QuantityStepper> createState() => _QuantityStepperState();
}

class _QuantityStepperState extends State<QuantityStepper> {
  late TextEditingController _controller;

  /// Drives the outer outline: the field itself draws no border, so the box
  /// around the stepper is what shows focus, as the unit price field's does.
  final _focusNode = FocusNode();

  /// The text last looked at. The controller also notifies when the field is
  /// only focused or the caret moves; those must not be reported as a quantity.
  late String _lastText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: formatQuantity(widget.initialValue),
    );
    _lastText = _controller.text;
    _controller.addListener(_onQuantityChanged);
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.removeListener(_onQuantityChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQuantityChanged() {
    if (_controller.text == _lastText) return;
    _lastText = _controller.text;
    // An empty or half-typed field is not a quantity yet, so the line keeps
    // the one it has; 0 is a real value, though — it is how Odoo wants a line
    // of a confirmed order removed, which this screen tells the user to do.
    final value = double.tryParse(_controller.text);
    if (value == null || value < 0) return;
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: 40,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.white,
          border: Border.all(
            color: _focusNode.hasFocus
                ? (isDark ? Colors.blue[300]! : theme.primaryColor)
                : (isDark ? Colors.grey[600]! : theme.dividerColor),
            width: _focusNode.hasFocus ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove, size: 18),
              onPressed: () {
                // Rounded to the quantity's own precision, so a 1.1 steps to
                // 0.1 and not 0.10000000000000009.
                _controller.text = stepQuantity(
                  _controller.text,
                  -1,
                  whenEmpty: 1,
                );
              },
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(6),
                  ),
                ),
              ),
            ),
            Expanded(
              // The text shrinks as the quantity grows: a field this narrow
              // showed only the middle of a large number, clipped at both ends.
              child: LayoutBuilder(
                builder: (context, box) =>
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (context, value, _) {
                        // A long quantity is shown short (1.5 L, 2 Cr) while
                        // the field is not being edited; focusing it brings
                        // the digits back to type into.
                        final compact = _focusNode.hasFocus
                            ? null
                            : compactQuantity(double.tryParse(value.text) ?? 0);
                        final style = theme.textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.white : null,
                          fontSize: quantityFontSize(
                            value.text.length,
                            width: box.maxWidth - 8,
                          ),
                        );
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [QuantityInputFormatter()],
                              style: compact == null
                                  ? style
                                  : style?.copyWith(color: Colors.transparent),
                              decoration: const InputDecoration(
                                // Every state, not just `border`: the app
                                // theme's focused border would otherwise draw
                                // a second outline inside the box.
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                                filled: false,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 4,
                                ),
                                isDense: true,
                                counterText: '',
                              ),
                            ),
                            if (compact != null)
                              // Taps fall through to the field underneath.
                              IgnorePointer(
                                child: Text(
                                  compact,
                                  maxLines: 1,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: isDark ? Colors.white : null,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              onPressed: () {
                _controller.text = stepQuantity(_controller.text, 1);
              },
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
