import 'package:flutter/services.dart';

/// How many digits a quantity may have before and after the point.
///
/// Odoo keeps a quantity in a float with the unit's precision (up to five
/// places); twelve whole digits is past any real order and keeps the number
/// inside what a double holds exactly.
const int kQuantityMaxIntegerDigits = 12;
const int kQuantityMaxDecimals = 6;

/// A quantity as text: whole numbers without a point, fractions without
/// trailing zeros, and never an exponent.
///
/// `double.toString` was used for this, and it is wrong in both directions: it
/// writes `1.0` for a whole number it was handed as a double, `1e+21` for a
/// very large one, and the float noise `0.10000000000000009` once a `1.1` had
/// one subtracted from it.
String formatQuantity(double value) {
  if (!value.isFinite || value == 0) return '0';
  if (value.abs() >= 1e21) return BigInt.from(value).toString();

  final text = _shortest(value, 0);
  return text == '-0' ? '0' : text;
}

/// The fewest decimals, from [minDecimals] up to [kQuantityMaxDecimals], that
/// still read back as exactly [value]; where none do (the value carries float
/// noise, as `1.1 - 1` does) it is rounded to [kQuantityMaxDecimals] and the
/// trailing zeros dropped down to [minDecimals].
///
/// Rounding to the maximum straight away gave `999999999999.98999` for a large
/// amount that is, as written, `999999999999.99`.
String _shortest(double value, int minDecimals) {
  for (var d = minDecimals; d <= kQuantityMaxDecimals; d++) {
    final text = value.toStringAsFixed(d);
    if (double.parse(text) == value) return text;
  }
  final fixed = value.toStringAsFixed(kQuantityMaxDecimals);
  final point = fixed.indexOf('.');
  var end = fixed.length;
  while (end > point + 1 + minDecimals && fixed.codeUnitAt(end - 1) == 0x30) {
    end--;
  }
  final cut = fixed.substring(0, end);
  return cut.endsWith('.') ? cut.substring(0, cut.length - 1) : cut;
}

/// From this quantity up, a field that is not being edited shows
/// [compactQuantity] instead of every digit: one lakh.
const double kCompactQuantityFrom = 100000;

/// [value] in the Indian short form — `1.5 L` for lakhs, `2.5 Cr` for crores —
/// or null when it is below [kCompactQuantityFrom] and is shown in full.
///
/// A quantity of twelve digits does not fit the narrow box of an order line,
/// which showed only a run of zeros; this keeps it readable. Two decimals at
/// most, trailing zeros dropped (`1 L`, not `1.00 L`).
String? compactQuantity(double value) {
  if (!value.isFinite || value < kCompactQuantityFrom) return null;
  final (divisor, unit) = value >= 1e7 ? (1e7, 'Cr') : (1e5, 'L');
  var text = (value / divisor).toStringAsFixed(2);
  if (text.contains('.')) {
    text = text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
  return '$text $unit';
}

/// The text of [current] moved by [delta] (the +/- buttons), never below zero.
///
/// The sum is rounded to the precision [formatQuantity] writes, so stepping a
/// fractional quantity does not pick up float noise. An empty or half-typed
/// field steps from [whenEmpty].
String stepQuantity(String current, double delta, {double whenEmpty = 0}) {
  final value = double.tryParse(current.trim()) ?? whenEmpty;
  final stepped = value + delta;
  return formatQuantity(stepped < 0 ? 0 : stepped);
}

/// Lets a quantity be typed: digits and one point (a comma is taken as the
/// point, as some keyboards offer only that), within
/// [kQuantityMaxIntegerDigits] and [kQuantityMaxDecimals].
class QuantityInputFormatter extends TextInputFormatter {
  static final RegExp _shape = RegExp(
    '^\\d{0,$kQuantityMaxIntegerDigits}(\\.\\d{0,$kQuantityMaxDecimals})?\$',
  );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(',', '.');
    if (!_shape.hasMatch(text)) return oldValue;
    return text == newValue.text ? newValue : newValue.copyWith(text: text);
  }
}

/// The font size a quantity of [length] characters is drawn at in a field
/// [width] wide: [base] while it fits, smaller as it grows, never below 8 — so
/// a large quantity is shown whole rather than clipped at both ends.
///
/// A digit is about 0.6 of the font size wide; that is a little more than most
/// fonts need, which errs on the side of fitting.
double quantityFontSize(int length, {double base = 14, required double width}) {
  if (length <= 0 || width <= 0) return base;
  final fitting = width / (length * 0.6);
  return fitting >= base ? base : fitting.clamp(8.0, base);
}

/// A unit price as text for its input: at least two decimals, at most
/// [kQuantityMaxDecimals], never an exponent.
///
/// `toStringAsFixed(2)` was used, which writes `1e+21` for a very large price
/// and rounds a price of 0.125 to 0.13 on the way in.
String formatPrice(double value) {
  if (!value.isFinite || value < 0) return '0.00';
  if (value >= 1e21) return '${BigInt.from(value)}.00';
  return _shortest(value, 2);
}
