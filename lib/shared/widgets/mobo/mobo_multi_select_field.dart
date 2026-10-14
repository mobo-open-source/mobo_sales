import 'package:flutter/material.dart';

import '../../design/mobo_tokens.dart';
import 'mobo_checkbox.dart';
import 'mobo_field_shell.dart';
import 'mobo_option.dart';
import 'mobo_overlay_panel.dart';

export 'mobo_option.dart';

/// A many-value picker.
///
/// Shares the shell and panel geometry with the single-select field; what
/// differs is the chip row on the closed field and the Done step, which
/// commits the whole selection at once instead of closing on every tap.
class MoboMultiSelectField<T> extends StatefulWidget {
  const MoboMultiSelectField({
    super.key,
    required this.options,
    required this.values,
    required this.onChanged,
    this.label,
    this.hintText = 'Select',
    this.title = 'Select',
    this.isRequired = false,
    this.errorText,
    this.enabled = true,
    this.searchable = false,
    this.maxVisibleChips = 3,
    this.searchHintText = 'Search...',
  });

  final List<MoboOption<T>> options;
  final List<T> values;
  final ValueChanged<List<T>> onChanged;

  final String? label;
  final String hintText;

  /// Panel heading.
  final String title;

  final bool isRequired;
  final String? errorText;
  final bool enabled;

  /// Off by default — a search box over three options is clutter, not a
  /// convenience. Turn it on per call site, by option count.
  final bool searchable;

  /// Hard ceiling on chips in the closed field, whichever bites first
  /// alongside what actually fits on one line.
  final int maxVisibleChips;

  final String searchHintText;

  @override
  State<MoboMultiSelectField<T>> createState() =>
      _MoboMultiSelectFieldState<T>();
}

class _MoboMultiSelectFieldState<T> extends State<MoboMultiSelectField<T>>
    with MoboOverlayPanelMixin<MoboMultiSelectField<T>> {
  /// The in-panel selection, committed to the caller only on Done.
  late List<T> _draft = List<T>.from(widget.values);
  String _query = '';

  @override
  void didUpdateWidget(covariant MoboMultiSelectField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!isPanelOpen && oldWidget.values != widget.values) {
      _draft = List<T>.from(widget.values);
    }
    if (oldWidget.options != widget.options) refreshPanel();
  }

  @override
  void dispose() {
    disposePanel();
    super.dispose();
  }

  List<MoboOption<T>> get _selectedOptions => widget.options
      .where((option) => widget.values.contains(option.value))
      .toList();

  List<MoboOption<T>> get _visibleOptions {
    if (_query.isEmpty) return widget.options;
    final query = _query.toLowerCase();
    return widget.options
        .where((option) => option.label.toLowerCase().contains(query))
        .toList();
  }

  void _toggle() {
    if (!widget.enabled) return;
    if (isPanelOpen) {
      closePanel();
      return;
    }
    _draft = List<T>.from(widget.values);
    _query = '';
    openPanel(
      searchable: widget.searchable,
      builder: _buildPanel,
      onFieldTap: _tapClearWhileOpen,
    );
  }

  final GlobalKey _clearKey = GlobalKey();

  void _clearAll() {
    closePanel();
    widget.onChanged(<T>[]);
  }

  /// The panel's barrier covers the field, so it hands taps to this first: one
  /// on the clear button must clear, not just close the panel.
  bool _tapClearWhileOpen(Offset global) {
    final box = _clearKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return false;
    if (!(box.localToGlobal(Offset.zero) & box.size).contains(global)) {
      return false;
    }
    _clearAll();
    return true;
  }

  void _removeValue(T value) {
    final next = List<T>.from(widget.values)..remove(value);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mobo;
    final selected = _selectedOptions;

    return CompositedTransformTarget(
      link: layerLink,
      child: MoboFieldShell(
        label: widget.label,
        isRequired: widget.isRequired,
        errorText: widget.errorText,
        enabled: widget.enabled,
        isFocused: isPanelOpen,
        onTap: _toggle,
        child: Row(
          children: [
            Expanded(
              child: selected.isEmpty
                  ? Text(
                      widget.hintText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MoboType.hint(
                        colors.isDark ? Colors.grey[400]! : Colors.grey[600]!,
                      ),
                    )
                  : _ChipRow<T>(
                      options: selected,
                      maxVisibleChips: widget.maxVisibleChips,
                      enabled: widget.enabled,
                      onRemove: _removeValue,
                    ),
            ),
            // One icon at a time: clear while there is a selection, the
            // chevron otherwise.
            if (selected.isNotEmpty && widget.enabled)
              // Its own target, so tapping it clears rather than opening the
              // panel the rest of the field opens.
              Semantics(
                button: true,
                label: 'Clear all',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _clearAll,
                  child: SizedBox(
                    key: _clearKey,
                    width: MoboSpacing.minTouchTarget,
                    height: MoboSpacing.minTouchTarget,
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              )
            else
              Icon(
                isPanelOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                color: colors.textSecondary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context, double maxHeight) {
    final colors = context.mobo;

    // The panel keeps its own draft state, so ticking a box does not rebuild
    // the whole form behind it.
    return StatefulBuilder(
      builder: (context, setPanelState) {
        void toggleValue(T value) {
          setPanelState(() {
            if (_draft.contains(value)) {
              _draft.remove(value);
            } else {
              _draft.add(value);
            }
          });
        }

        final options = _visibleOptions;

        return Material(
          elevation: 4,
          color: colors.popupSurface,
          surfaceTintColor: Colors.transparent,
          borderRadius: BorderRadius.circular(MoboRadius.field),
          child: Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(MoboRadius.field),
              border: Border.all(color: colors.divider),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.title,
                      style: MoboType.fieldValue(
                        colors.textPrimary,
                      ).copyWith(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                if (widget.searchable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: MoboPanelSearchBox(
                      hintText: widget.searchHintText,
                      onChanged: (value) {
                        _query = value;
                        setPanelState(() {});
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Neutral, not brand-coloured: Done is the action being
                      // invited, and two primary buttons would compete.
                      // Disabled rather than hidden, so Done never shifts
                      // position as the selection changes.
                      TextButton(
                        onPressed: _draft.isEmpty
                            ? null
                            : () => setPanelState(() => _draft.clear()),
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Clear All',
                          style: MoboType.fieldValue(
                            colors.textPrimary,
                          ).copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          widget.onChanged(List<T>.from(_draft));
                          closePanel();
                        },
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Done',
                          style: MoboType.fieldValue(
                            colors.primary,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.divider),
                Flexible(
                  child: options.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'No matches',
                              style: MoboType.body(colors.textSecondary),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options[index];
                            final isChecked = _draft.contains(option.value);

                            return InkWell(
                              onTap: () => toggleValue(option.value),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    if (option.leading != null) ...[
                                      option.leading!,
                                      const SizedBox(width: 10),
                                    ],
                                    Expanded(
                                      child: Text(
                                        option.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: MoboType.fieldValue(
                                          colors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // The row's own tap toggles; this only shows the result.
                                    MoboCheckbox(value: isChecked),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The closed field's chip row — one line, always.
///
/// A `Wrap` would let chips run onto a second and third row and grow the
/// field down the form; four tags is enough to do it. So the labels are
/// measured instead, and anything that does not fit collapses into a single
/// `+N more` capsule.
class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.options,
    required this.maxVisibleChips,
    required this.enabled,
    required this.onRemove,
  });

  final List<MoboOption<T>> options;
  final int maxVisibleChips;
  final bool enabled;
  final ValueChanged<T> onRemove;

  /// A chip's own chrome around its label: padding 10 + 4, the 14px close
  /// icon, and the 10px that follows it.
  static const double _chipChrome = 10 + 4 + 14 + 10;
  static const double _chipGap = 6;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobo;
    final textScaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        double widthOf(String label) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: MoboType.chip(colors.primary)),
            maxLines: 1,
            textDirection: Directionality.of(context),
            textScaler: textScaler,
          )..layout();
          return painter.width + _chipChrome;
        }

        final available = constraints.maxWidth;
        var used = 0.0;
        var visibleCount = 0;

        for (var i = 0; i < options.length && i < maxVisibleChips; i++) {
          final chipWidth = widthOf(options[i].label);
          final gap = visibleCount == 0 ? 0.0 : _chipGap;
          final hiddenAfterThis = options.length - (i + 1);

          // Room has to be reserved for the "+N more" capsule whenever
          // anything would be hidden, or the capsule becomes the thing that
          // overflows.
          var needed = used + gap + chipWidth;
          if (hiddenAfterThis > 0) {
            final overflowPainter = TextPainter(
              text: TextSpan(
                text: '+$hiddenAfterThis more',
                style: MoboType.chip(colors.textSecondary),
              ),
              maxLines: 1,
              textDirection: Directionality.of(context),
              textScaler: textScaler,
            )..layout();
            needed += _chipGap + overflowPainter.width + 20;
          }

          if (needed > available && visibleCount > 0) break;

          used += gap + chipWidth;
          visibleCount++;
        }

        // Always at least one chip: a field reading only "+5 more" says less
        // than a name plus a count.
        if (visibleCount == 0) visibleCount = 1;

        final hidden = options.length - visibleCount;

        return Row(
          children: [
            for (var i = 0; i < visibleCount; i++) ...[
              if (i > 0) const SizedBox(width: _chipGap),
              Flexible(
                child: _SelectedChip(
                  label: options[i].label,
                  onRemove: enabled ? () => onRemove(options[i].value) : null,
                ),
              ),
            ],
            if (hidden > 0) ...[
              const SizedBox(width: _chipGap),
              _OverflowChip(count: hidden),
            ],
          ],
        );
      },
    );
  }
}

class _SelectedChip extends StatelessWidget {
  const _SelectedChip({required this.label, this.onRemove});

  final String label;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobo;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(MoboRadius.chip),
        border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MoboType.chip(colors.primary),
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: Icon(Icons.close, size: 14, color: colors.primary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Neutral on purpose — it must read as a count, not as another selected
/// value.
class _OverflowChip extends StatelessWidget {
  const _OverflowChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobo;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.isDark ? Colors.grey[800] : Colors.grey[200],
        borderRadius: BorderRadius.circular(MoboRadius.chip),
      ),
      child: Text(
        '+$count more',
        style: MoboType.chip(
          colors.isDark ? Colors.grey[300]! : Colors.grey[700]!,
        ),
      ),
    );
  }
}
