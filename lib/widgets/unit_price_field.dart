import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/currency_provider.dart';
import '../utils/quantity_format.dart';

/// The unit price box of an order or invoice line, with the currency in front.
///
/// Reports every change of the text as a price. Built for the narrow half of a
/// row: a large amount shrinks the text to fit instead of being clipped behind
/// the currency, and only digits and one point can be typed.
class UnitPriceField extends StatefulWidget {
  const UnitPriceField({
    super.key,
    required this.initialValue,
    required this.onChanged,
    required this.currencyLabel,
    this.fillInDark = false,
  });

  final double initialValue;
  final ValueChanged<double> onChanged;

  /// What is written in front of the amount: the currency code or its symbol.
  final String Function(CurrencyProvider currency) currencyLabel;

  /// Fills the box in dark mode, as the invoice form does.
  final bool fillInDark;

  @override
  State<UnitPriceField> createState() => _UnitPriceFieldState();
}

class _UnitPriceFieldState extends State<UnitPriceField> {
  late final TextEditingController _controller = TextEditingController(
    text: formatPrice(widget.initialValue),
  );
  final _focusNode = FocusNode();

  /// The text last looked at: the controller also notifies for focus and the
  /// caret, which are not a new price.
  late String _lastText = _controller.text;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onPriceChanged);
    // Focus decides between the digits and their short form.
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.removeListener(_onPriceChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onPriceChanged() {
    if (_controller.text == _lastText) return;
    _lastText = _controller.text;
    // An emptied or half-typed field is a price of nothing, as it always was.
    widget.onChanged(double.tryParse(_controller.text) ?? 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: color, width: width),
        );
    final idle = isDark ? Colors.grey[600]! : theme.dividerColor;

    return SizedBox(
      height: 40,
      child: Consumer<CurrencyProvider>(
        builder: (context, currency, _) {
          final label = widget.currencyLabel(currency);
          return LayoutBuilder(
            builder: (context, box) => ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) {
                // A large price is shown short (1.5 L, 2 Cr) while the field
                // is not being edited; focusing it brings the digits back.
                final compact = _focusNode.hasFocus
                    ? null
                    : compactQuantity(double.tryParse(value.text) ?? 0);
                final style = theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white : null,
                  // The room left after the currency and the padding.
                  fontSize: quantityFontSize(
                    value.text.length,
                    width: box.maxWidth - 40 - label.length * 8,
                  ),
                );
                final field = TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [QuantityInputFormatter()],
                  style: compact == null
                      ? style
                      : style?.copyWith(color: Colors.transparent),
                  decoration: InputDecoration(
                    filled: widget.fillInDark && isDark,
                    fillColor: widget.fillInDark && isDark
                        ? Colors.grey[800]
                        : null,
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(
                        left: 12,
                        right: 8,
                        top: 12,
                        bottom: 12,
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.grey,
                        ),
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 0,
                      minHeight: 0,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    border: border(idle),
                    enabledBorder: border(idle),
                    focusedBorder: border(
                      isDark ? Colors.blue[300]! : theme.primaryColor,
                      1.5,
                    ),
                    isDense: true,
                  ),
                  onTap: () {
                    _controller.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _controller.text.length,
                    );
                  },
                );
                if (compact == null) return field;
                return Stack(
                  alignment: Alignment.centerRight,
                  children: [
                    field,
                    // Taps fall through to the field underneath.
                    IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          compact,
                          maxLines: 1,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDark ? Colors.white : null,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
