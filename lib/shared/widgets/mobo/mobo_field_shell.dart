import 'package:flutter/material.dart';

import '../../design/mobo_tokens.dart';

/// The chrome every Mobo select and text field sits in, so they cannot drift
/// apart from each other.
///
/// Takes [isFocused] as a plain flag rather than requiring a `FocusNode`:
/// the dropdowns own their open/closed state and drive the focus border from
/// it directly, with no focus node involved.
class MoboFieldShell extends StatelessWidget {
  const MoboFieldShell({
    super.key,
    required this.child,
    this.label,
    this.isRequired = false,
    this.isFocused = false,
    this.errorText,
    this.enabled = true,
    this.onTap,
  });

  /// The field's own content — a value row, a chip row, a `TextField`.
  final Widget child;

  final String? label;

  /// Appends a red ` *` after [label].
  final bool isRequired;

  /// Draws the focus border. Open dropdowns pass true.
  final bool isFocused;

  final String? errorText;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobo;
    final hasError = errorText != null && errorText!.isNotEmpty;

    final field = Container(
      constraints: const BoxConstraints(minHeight: MoboSpacing.fieldMinHeight),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(MoboRadius.field),
        border: Border.all(
          color: hasError
              ? colors.error
              : isFocused
              ? colors.primary
              : Colors.transparent,
          width: hasError || isFocused ? 1.5 : 1,
        ),
      ),
      child: child,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label!,
                    style: MoboType.label(colors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // A separate Text rather than a rich span, so the label is
                // still findable by its own words.
                if (isRequired) Text(' *', style: MoboType.label(colors.error)),
              ],
            ),
          ),
        ],
        Opacity(
          opacity: enabled ? 1 : 0.6,
          child: onTap == null || !enabled
              ? field
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: field,
                ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              errorText!,
              style: MoboType.hint(colors.error, size: 12),
            ),
          ),
      ],
    );
  }
}

/// The search box used inside an overlay panel and the filter sheet.
///
/// Shares the field shell's shape — radius 12, [MoboColors.inputFill], a
/// transparent border that becomes the brand colour on focus — but draws no
/// Material border of its own on any state, so the shell's border is the only
/// one on screen.
class MoboPanelSearchBox extends StatefulWidget {
  const MoboPanelSearchBox({
    super.key,
    required this.onChanged,
    this.controller,
    this.hintText = 'Search...',
    this.autofocus = false,
  });

  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final String hintText;
  final bool autofocus;

  @override
  State<MoboPanelSearchBox> createState() => _MoboPanelSearchBoxState();
}

class _MoboPanelSearchBoxState extends State<MoboPanelSearchBox> {
  late final FocusNode _focusNode = FocusNode()..addListener(_onFocusChanged);

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final colors = context.mobo;

    return Container(
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(MoboRadius.field),
        border: Border.all(
          color: _focusNode.hasFocus ? colors.primary : Colors.transparent,
          width: _focusNode.hasFocus ? 1.5 : 1,
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onChanged: widget.onChanged,
        style: MoboType.body(colors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hintText,
          hintStyle: MoboType.hint(colors.textSecondary),
          prefixIcon: Icon(Icons.search, size: 20, color: colors.textSecondary),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          // All three, so no state falls back to the theme's outline and
          // draws a second border inside the container's own.
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}
