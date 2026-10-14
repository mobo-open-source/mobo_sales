import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../design/mobo_tokens.dart';
import 'mobo_field_shell.dart';
import 'mobo_option.dart';
import 'mobo_overlay_panel.dart';

export 'mobo_option.dart';

/// A one-value picker.
///
/// Tap the field, pick from the panel anchored to it, and it closes — there
/// is no Done step, because there is nothing to batch for a single choice.
///
/// [searchable] turns the closed field itself into the search box, matching the
/// create/edit form dropdown — one input per list, and it is already where the
/// user is looking. The chosen value is restored to the field the moment focus
/// leaves, so a half-typed query never lingers looking like the selection.
class MoboSelectField<T> extends StatefulWidget {
  const MoboSelectField({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
    this.hintText = 'Select',
    this.isRequired = false,
    this.errorText,
    this.enabled = true,
    this.searchable = false,
    this.allowClear = true,
    this.prefixIcon,
    this.prefixHugeIcon,
    this.onSearchChanged,
    this.searchHintText = 'Search...',
    this.isLoading = false,
    this.emptyText = 'No matches',
    this.onOpened,
  });

  final List<MoboOption<T>> options;
  final T? value;
  final ValueChanged<T?> onChanged;

  final String? label;
  final String hintText;
  final bool isRequired;
  final String? errorText;
  final bool enabled;

  /// Off by default — a search box over three options is clutter, not a
  /// convenience. Turn it on per call site, by option count.
  ///
  /// Supplying [onSearchChanged] turns it on regardless: a caller that fetches
  /// on every keystroke has nothing to fetch with otherwise.
  final bool searchable;

  /// False for a field the record cannot be saved without — the chevron then
  /// always shows in place of the clear button.
  final bool allowClear;

  final IconData? prefixIcon;

  /// A HugeIcons stroke icon, drawn instead of [prefixIcon] when supplied.
  ///
  /// `IconData` here, where mobo_rental declares `List<List<dynamic>>`: that is
  /// the shape of `HugeIcons.*` in hugeicons 1.x, whereas this app is on
  /// 0.0.11, whose icons and `HugeIcon.icon` are `IconData`. A call site passes
  /// `HugeIcons.strokeRounded…` unchanged under either version.
  final IconData? prefixHugeIcon;

  /// Supply this and the caller's results *are* the filter: options are shown
  /// as they arrive rather than being filtered again locally. This is the hook
  /// for a server-side search.
  final ValueChanged<String>? onSearchChanged;

  final String searchHintText;

  /// Draws a spinner in place of the list. Only meaningful alongside
  /// [onSearchChanged], where results are being awaited.
  final bool isLoading;

  /// Shown when the list is empty — worth overriding where an empty list is
  /// the starting state rather than a failed search.
  final String emptyText;

  /// Called each time the list opens, after it is on screen. For a server-backed
  /// list that has to show the whole list on open — not what the last search
  /// left behind, and not just the chosen value it already holds.
  final VoidCallback? onOpened;

  @override
  State<MoboSelectField<T>> createState() => _MoboSelectFieldState<T>();
}

class _MoboSelectFieldState<T> extends State<MoboSelectField<T>>
    with MoboOverlayPanelMixin<MoboSelectField<T>> {
  late final TextEditingController _searchController = TextEditingController(
    text: _selectedLabel,
  );
  late final FocusNode _searchFocusNode = FocusNode()
    ..addListener(_onSearchFocusChanged);

  String _query = '';

  /// The label of the option the user last picked here.
  ///
  /// The field's text cannot be derived from [widget.options] alone. A
  /// server-backed list is replaced on every query — and the create-order form
  /// clears it outright once a customer is chosen — so by the time the field
  /// redraws, the chosen value is often absent from the options and the lookup
  /// returns nothing. This is then the only record of what the value means.
  String? _pickedLabel;

  /// What the closed field should show.
  String get _selectedLabel {
    if (widget.value == null) return '';
    return _selected?.label ?? _pickedLabel ?? '';
  }

  bool get _searchable => widget.searchable || widget.onSearchChanged != null;

  MoboOption<T>? get _selected {
    for (final option in widget.options) {
      if (option.value == widget.value) return option;
    }
    return null;
  }

  List<MoboOption<T>> get _visibleOptions {
    // With a search callback the caller has already done the filtering.
    final matches = (widget.onSearchChanged != null || _query.isEmpty)
        ? [...widget.options]
        : widget.options
              .where(
                (option) =>
                    option.label.toLowerCase().contains(_query.toLowerCase()),
              )
              .toList();

    // The current value goes to the top, so it is visible the moment the panel
    // opens rather than somewhere down a list the user has to scroll.
    final selectedIndex = matches.indexWhere((o) => o.value == widget.value);
    if (selectedIndex > 0) {
      matches.insert(0, matches.removeAt(selectedIndex));
    }

    return matches;
  }

  @override
  void didUpdateWidget(covariant MoboSelectField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent owns the value, so a change made elsewhere has to reach the
    // field's text — unless the user is mid-query, which must not be clobbered.
    if (oldWidget.value != widget.value && !_searchFocusNode.hasFocus) {
      // A value set from elsewhere is not the one picked here, so the
      // remembered label no longer describes it.
      if (_selected != null) _pickedLabel = _selected!.label;
      _searchController.text = _selectedLabel;
    }
    // Options and the spinner both arrive while the panel is open.
    if (oldWidget.options != widget.options ||
        oldWidget.isLoading != widget.isLoading) {
      refreshPanel();
    }
  }

  @override
  void dispose() {
    disposePanel();
    _searchFocusNode
      ..removeListener(_onSearchFocusChanged)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (_searchFocusNode.hasFocus) {
      if (!isPanelOpen) _open();
      // Select-all, so the first keystroke replaces the current value rather
      // than appending to it.
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchController.text.length,
      );
    } else {
      _searchController.text = _selectedLabel;
      _query = '';
      refreshPanel();
    }
    if (mounted) setState(() {});
  }

  void _onQueryChanged(String value) {
    _query = value;
    widget.onSearchChanged?.call(value);
    // The panel is a sibling in the Overlay, so it needs telling separately.
    setState(() {});
    refreshPanel();
  }

  void _open() {
    // A stale query would filter the list down before the user has typed.
    _query = '';
    openPanel(
      searchable: _searchable,
      builder: _buildPanel,
      onBarrierTap: _searchable ? _closeAndUnfocus : null,
      onFieldTap: _tapClearWhileOpen,
    );

    // A server-backed field starts with nothing to show, so opening it said
    // "No results found" until the user typed — as if the search had already
    // run and failed. Ask for the unfiltered first page instead.
    if (widget.onSearchChanged != null && widget.options.isEmpty) {
      widget.onSearchChanged!('');
    }
    widget.onOpened?.call();
  }

  void _toggle() {
    if (!widget.enabled) return;
    if (isPanelOpen) {
      _closeAndUnfocus();
    } else if (_searchable) {
      _searchFocusNode.requestFocus();
    } else {
      _open();
    }
  }

  /// Unfocuses the search box before closing the panel, so a tap-outside
  /// dismiss leaves the field in the same state as picking an option or
  /// tapping the chevron does. Left out, the field stays focused with the
  /// panel gone — tapping it again fires no focus change, so the panel never
  /// reopens, and typing updates the query with no panel left to show it in.
  void _closeAndUnfocus() {
    _searchFocusNode.unfocus();
    closePanel();
  }

  void _pick(MoboOption<T> option) {
    // Recorded before unfocusing: `unfocus()` runs the focus listener
    // synchronously, and that restores the field's text from the current
    // value — which the parent has not been told about yet.
    _pickedLabel = option.label;
    _query = '';
    _searchController.text = option.label;
    _searchFocusNode.unfocus();
    closePanel();
    widget.onChanged(option.value);
  }

  void _clear() {
    _pickedLabel = null;
    _query = '';
    _searchController.clear();
    _searchFocusNode.unfocus();
    closePanel();
    widget.onChanged(null);
  }

  final GlobalKey _clearKey = GlobalKey();

  /// The panel's barrier covers the field, so it hands taps to this first: one
  /// on the clear button must clear, not just close the panel.
  bool _tapClearWhileOpen(Offset global) {
    final box = _clearKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (!rect.contains(global)) return false;
    if (_searchable && _query.isNotEmpty) {
      _clearQuery();
    } else {
      _clear();
    }
    return true;
  }

  /// Empties what the user has typed, keeping the field focused and the panel
  /// open, so the full list comes back without losing their place.
  void _clearQuery() {
    _query = '';
    _searchController.clear();
    widget.onSearchChanged?.call('');
    setState(() {});
    refreshPanel();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mobo;
    final selected = _selected;

    return CompositedTransformTarget(
      link: layerLink,
      child: MoboFieldShell(
        label: widget.label,
        isRequired: widget.isRequired,
        errorText: widget.errorText,
        enabled: widget.enabled,
        isFocused: isPanelOpen,
        // A searchable field is a text input: the shell must not eat the tap
        // that places the caret.
        onTap: _searchable ? null : _toggle,
        child: Row(
          children: [
            if (widget.prefixHugeIcon != null) ...[
              HugeIcon(
                icon: widget.prefixHugeIcon!,
                size: 20,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 8),
            ] else if (widget.prefixIcon != null) ...[
              Icon(widget.prefixIcon, size: 20, color: colors.textSecondary),
              const SizedBox(width: 8),
            ],
            if (selected?.leading != null) ...[
              selected!.leading!,
              const SizedBox(width: 10),
            ],
            Expanded(
              child: _searchable
                  ? _buildSearchInput(colors)
                  : Text(
                      selected?.label ?? widget.hintText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: selected == null
                          ? MoboType.hint(
                              colors.isDark
                                  ? Colors.grey[400]!
                                  : Colors.grey[600]!,
                              size: 15,
                            )
                          : MoboType.fieldValue(colors.textPrimary),
                    ),
            ),
            _buildTrailing(colors, selected),
          ],
        ),
      ),
    );
  }

  Widget _buildTrailing(MoboColors colors, MoboOption<T>? selected) {
    // Typed text clears first: on a searchable field the first tap empties the
    // query, and only then does a tap clear the chosen value.
    final hasQuery = _searchable && _query.isNotEmpty;
    final canClear =
        widget.enabled && (hasQuery || (widget.allowClear && selected != null));

    // One icon at a time: the clear button while there is something to clear,
    // the chevron otherwise. The field itself still opens the list.
    if (canClear) {
      // A 36pt target: the bare 20px glyph is half the size a fingertip
      // needs, and a near-miss reopens the list instead of clearing.
      return Semantics(
        button: true,
        label: 'Clear',
        child: SizedBox(
          key: _clearKey,
          width: MoboSpacing.minTouchTarget,
          height: MoboSpacing.minTouchTarget,
          child: InkWell(
            onTap: hasQuery ? _clearQuery : _clear,
            borderRadius: BorderRadius.circular(MoboRadius.pill),
            child: Icon(Icons.close, size: 18, color: colors.textSecondary),
          ),
        ),
      );
    }

    // Its own target, so the chevron still opens and closes the panel once the
    // field itself is busy being a text input.
    return GestureDetector(
      onTap: widget.enabled ? _toggle : null,
      behavior: HitTestBehavior.opaque,
      child: Icon(
        isPanelOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
        color: colors.textSecondary,
      ),
    );
  }

  /// The closed field, doubling as the search box.
  Widget _buildSearchInput(MoboColors colors) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      enabled: widget.enabled,
      onChanged: _onQueryChanged,
      style: MoboType.fieldValue(colors.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        isCollapsed: true,
        hintText: widget.hintText,
        hintStyle: MoboType.hint(
          colors.isDark ? Colors.grey[400]! : Colors.grey[600]!,
          size: 15,
        ),
        // Every state, or one falls back to the theme outline and draws a
        // second border inside the shell's own.
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
      ),
    );
  }

  Widget _buildPanel(BuildContext context, double maxHeight) {
    final colors = context.mobo;

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
        child: _buildList(colors, _visibleOptions),
      ),
    );
  }

  Widget _buildList(MoboColors colors, List<MoboOption<T>> options) {
    if (widget.isLoading && options.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        // heightFactor, or the panel stretches to its maximum around a single
        // line and leaves a tall empty box under it.
        child: Center(
          heightFactor: 1,
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          ),
        ),
      );
    }

    if (options.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          heightFactor: 1,
          child: Text(
            widget.emptyText,
            style: MoboType.body(colors.textSecondary),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: options.length,
      itemBuilder: (context, index) {
        final option = options[index];
        final isSelected = option.value == widget.value;

        return InkWell(
          onTap: () => _pick(option),
          child: Container(
            color: isSelected ? colors.primaryTint : null,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (option.leading != null) ...[
                  option.leading!,
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            MoboType.fieldValue(
                              isSelected ? colors.primary : colors.textPrimary,
                            ).copyWith(
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                      ),
                      if (option.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          option.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MoboType.meta(colors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                if (option.trailing != null) ...[
                  const SizedBox(width: 10),
                  option.trailing!,
                ],
                // Only the selected row carries a mark.
                if (isSelected)
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 14,
                      color: Colors.white,
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
