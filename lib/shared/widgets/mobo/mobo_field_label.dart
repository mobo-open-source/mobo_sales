import 'package:flutter/material.dart';

import '../../design/mobo_tokens.dart';

/// A form field's label, with the red required star when [isRequired].
///
/// The same mark [MoboFieldShell] draws on the Mobo select fields, for the
/// fields that are not built on it: [CustomTextField], date selectors, and any
/// `InputDecoration.label`. A required field then reads the same wherever it
/// sits on a form.
///
/// The star is a separate `Text` rather than a rich span, so the label is
/// still findable by its own words.
class MoboFieldLabel extends StatelessWidget {
  const MoboFieldLabel(
    this.text, {
    super.key,
    this.isRequired = false,
    this.style,
  });

  final String text;

  /// Appends a red ` *` after [text].
  final bool isRequired;

  /// The label's own style. The star reuses it, in the error colour, so it
  /// keeps the label's size and font. Defaults to the ambient text style, which
  /// is what an `InputDecoration.label` wants.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final starStyle = (style ?? DefaultTextStyle.of(context).style).copyWith(
      color: context.mobo.error,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(text, style: style, overflow: TextOverflow.ellipsis),
        ),
        if (isRequired) Text(' *', style: starStyle),
      ],
    );
  }
}
