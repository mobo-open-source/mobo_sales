import 'package:flutter/widgets.dart';

/// One option in a Mobo select field, single or multiple.
///
/// Lives in its own file because both fields need it and neither owns it.
class MoboOption<T> {
  const MoboOption({
    required this.value,
    required this.label,
    this.leading,
    this.subtitle,
    this.trailing,
  });

  final T value;

  /// What the user reads, and what a local search matches against.
  final String label;

  /// Optional avatar or colour dot shown before the label, in both the closed
  /// field and the panel row.
  final Widget? leading;

  /// A second line under the label, in the panel only — a product's reference
  /// and price, for instance. The closed field shows the label alone, since it
  /// has one line to work with.
  final String? subtitle;

  /// Shown at the end of the panel row, for a figure that belongs to the
  /// option rather than to the choice: stock on hand, a count, a status.
  final Widget? trailing;
}
