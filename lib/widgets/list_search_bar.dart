import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hugeicons/hugeicons.dart' show HugeIcons;

/// The search field and filter button shared by every list page.
///
/// Matches the mobo Delivery design: a 48pt field carrying the search glyph,
/// with the filter entry point as its own square button beside it rather than
/// occupying the field's leading slot.
class ListSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onFilterTap;

  /// Disables the field and both buttons while a page is loading.
  final bool enabled;

  /// Replaces the default clear behaviour for pages that also have to reset
  /// paging or refetch, rather than only emptying the field.
  final VoidCallback? onClear;

  /// Extra controls rendered inside the field, before the clear button —
  /// voice search and barcode scanning on the products list.
  final List<Widget> trailing;

  /// Chips describing the active filters, shown under the row when present.
  final Widget? activeFiltersRow;

  /// Replaces the filter glyph in the square side button. The stock list scans
  /// a barcode there, having no filters of its own. Providing it keeps the
  /// button in place even while its callback is null, so a page that disables
  /// the button mid-action does not collapse the row.
  final Widget? sideButtonChild;
  final VoidCallback? onSideButtonTap;

  const ListSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.onFilterTap,
    this.enabled = true,
    this.onClear,
    this.trailing = const [],
    this.activeFiltersRow,
    this.sideButtonChild,
    this.onSideButtonTap,
  });

  /// The tone of the filter glyph. Controls placed inside the field — voice
  /// search, barcode — use it too so the whole row reads as one set.
  static Color actionIconColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Colors.white
      : const Color(0xFF1A1A1A);

  @override
  State<ListSearchBar> createState() => _ListSearchBarState();
}

class _ListSearchBarState extends State<ListSearchBar> {
  /// Design drop-shadow: X 3, Y 11, blur 8.5, spread -3, black @ 4%.
  static final List<BoxShadow> _designShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      offset: const Offset(3, 11),
      blurRadius: 8.5,
      spreadRadius: -3,
    ),
  ];

  static const double _height = 48;
  static const double _radius = 12;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(ListSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// Keeps the clear button in step with the field when the text is changed by
  /// the page itself rather than by typing.
  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _handleClear() {
    if (widget.onClear != null) {
      widget.onClear!();
      return;
    }
    widget.controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? Colors.grey[850]! : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xff1E1E1E);
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0xFF99A1AF);
    final iconColor = isDark
        ? Colors.white.withValues(alpha: 0.70)
        : const Color(0xFF99A1AF);
    final filterIconColor = ListSearchBar.actionIconColor(context);
    final hasSideButton =
        widget.sideButtonChild != null ||
        widget.onFilterTap != null ||
        widget.onSideButtonTap != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSearchField(
                  surface,
                  textColor,
                  hintColor,
                  iconColor,
                ),
              ),
              if (hasSideButton) ...[
                const SizedBox(width: 10),
                _buildSideButton(surface, filterIconColor),
              ],
            ],
          ),
          if (widget.activeFiltersRow != null) ...[
            const SizedBox(height: 6),
            widget.activeFiltersRow!,
          ],
        ],
      ),
    );
  }

  Widget _buildSearchField(
    Color surface,
    Color textColor,
    Color hintColor,
    Color iconColor,
  ) {
    final showClear = widget.controller.text.isNotEmpty;
    final hasSuffix = showClear || widget.trailing.isNotEmpty;

    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: _designShadow,
      ),
      child: TextField(
        controller: widget.controller,
        enabled: widget.enabled,
        onChanged: widget.onChanged,
        style: TextStyle(fontSize: 14, color: textColor),
        decoration: InputDecoration(
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
          hintText: widget.hintText,
          hintStyle: TextStyle(
            color: hintColor,
            fontWeight: FontWeight.w400,
            fontSize: 14,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 8),
            child: SvgPicture.asset(
              'assets/icons/search.svg',
              width: 20,
              height: 20,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
          suffixIcon: hasSuffix
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ...widget.trailing,
                    if (showClear)
                      IconButton(
                        splashRadius: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        icon: Icon(
                          HugeIcons.strokeRoundedCancel01,
                          size: 18,
                          color: iconColor,
                        ),
                        onPressed: widget.enabled ? _handleClear : null,
                      ),
                    const SizedBox(width: 12),
                  ],
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          filled: false,
        ),
      ),
    );
  }

  Widget _buildSideButton(Color surface, Color iconColor) {
    return Container(
      width: _height,
      height: _height,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: _designShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_radius),
          onTap: widget.enabled
              ? (widget.onSideButtonTap ?? widget.onFilterTap)
              : null,
          child: Center(
            child:
                widget.sideButtonChild ??
                SvgPicture.asset(
                  'assets/icons/new_filter.svg',
                  width: 18,
                  height: 18,
                  colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                ),
          ),
        ),
      ),
    );
  }
}
