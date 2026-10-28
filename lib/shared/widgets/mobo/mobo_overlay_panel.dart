import 'package:flutter/material.dart';

/// Panel placement for the Mobo select fields.
///
/// This is what keeps a dropdown usable on a long scrolling form: the panel
/// follows the field as the page scrolls, flips above it when there is no
/// room below, and scrolls internally rather than overflowing the screen.
mixin MoboOverlayPanelMixin<T extends StatefulWidget> on State<T> {
  /// Gap between the field and its panel, on whichever side it opens.
  static const double _gap = 6;

  /// The panel's own chrome — title, search, buttons — is this tall. Capping
  /// below it would overflow that chrome instead of scrolling the list.
  static const double _minPanelHeight = 180;

  static const double _maxPanelHeight = 320;

  final LayerLink layerLink = LayerLink();
  OverlayEntry? _entry;

  bool get isPanelOpen => _entry != null;

  /// Closes the panel once something is pushed over this field's route.
  ///
  /// The panel is an [OverlayEntry] of its own, inserted on top of every
  /// entry the Navigator holds. A route pushed afterwards — a dialog, a sheet,
  /// another page — goes in directly above the *route* entries, which leaves
  /// it underneath the panel: an open dropdown would sit over the "Unsaved
  /// Changes" dialog. Reading [ModalRoute.of] here subscribes this field to
  /// the route's status, so pushing over it brings us back to close the panel.
  ///
  /// The close itself has to wait for the frame to finish, same as
  /// [refreshPanel]: this fires mid-build, while the Navigator is still
  /// assembling the very frame that pushed the new route, and splicing the
  /// entry out of the Overlay in the middle of that corrupts it — surfacing
  /// downstream as duplicate `OverlayEntry` global keys and widgets built in
  /// the wrong build scope.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent && isPanelOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => closePanel());
    }
  }

  /// Opens the panel anchored to this field.
  ///
  /// [builder] is handed the height the panel must fit inside; it is the
  /// caller's job to make its list scroll within that.
  ///
  /// [onBarrierTap] runs instead of [closePanel] when the user dismisses the
  /// panel by tapping outside it. Defaulting straight to [closePanel] is
  /// wrong for a searchable field: its search box is a live [TextField], and
  /// closing the panel without also unfocusing that field leaves it focused
  /// with nothing open — a state indistinguishable from any other focused,
  /// closed field. Tapping it again then does nothing, because focus never
  /// changes, and [openPanel] is only ever called from a focus listener.
  /// Typing does even less: the query reaches the caller, but there is no
  /// panel left for [refreshPanel] to update, so the results are invisible.
  /// A caller with a live search field should pass a callback that unfocuses
  /// it before calling [closePanel].
  ///
  /// The barrier covers the field too, so a tap on something in the field that
  /// should still work while the panel is open — a clear button — would only
  /// dismiss the panel. [onFieldTap] sees every barrier tap first, with its
  /// position, and returns true if it handled it; otherwise the panel is
  /// dismissed as usual.
  void openPanel({
    required Widget Function(BuildContext context, double maxHeight) builder,
    bool searchable = false,
    VoidCallback? onBarrierTap,
    bool Function(Offset globalPosition)? onFieldTap,
  }) {
    if (_entry != null) return;
    final dismiss = onBarrierTap ?? closePanel;

    // An open keyboard would push a panel that cannot use it off screen.
    if (!searchable) FocusScope.of(context).unfocus();

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    _entry = OverlayEntry(
      builder: (overlayContext) {
        final panel = _measurePanel(overlayContext);
        if (panel == null) return const SizedBox.shrink();

        return Stack(
          children: [
            // Tapping anywhere off the panel dismisses it.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (details) {
                  if (onFieldTap?.call(details.globalPosition) ?? false) return;
                  dismiss();
                },
              ),
            ),
            Positioned(
              width: panel.width,
              child: CompositedTransformFollower(
                link: layerLink,
                showWhenUnlinked: false,
                targetAnchor: panel.openUpward
                    ? Alignment.topLeft
                    : Alignment.bottomLeft,
                followerAnchor: panel.openUpward
                    ? Alignment.bottomLeft
                    : Alignment.topLeft,
                offset: Offset(0, panel.openUpward ? -_gap : _gap),
                child: builder(overlayContext, panel.maxHeight),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_entry!);
    if (mounted) setState(() {});
  }

  /// Where the panel may go and how tall it may be, measured against the
  /// screen as it is right now.
  ///
  /// Measured on every build of the overlay rather than once when it opens,
  /// for two reasons. A searchable panel is opened from a focus listener, so
  /// the keyboard is only *starting* to come up and [MediaQueryData.viewInsets]
  /// still reads zero; and the keyboard then animates, changing the space
  /// available for several frames afterwards. Sizing the panel once, against
  /// a screen the keyboard was about to cover, left its lower rows underneath
  /// the keyboard — visible after a scroll, but never tappable, because the
  /// keyboard takes the touch. The last option in a list was the one that
  /// could not be chosen.
  ({bool openUpward, double maxHeight, double width})? _measurePanel(
    BuildContext overlayContext,
  ) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;

    final fieldSize = box.size;
    final fieldTop = box.localToGlobal(Offset.zero).dy;
    final media = MediaQuery.of(overlayContext);

    // `viewInsets.bottom` is the keyboard. `padding.bottom` is what is left of
    // the safe area beside it — Flutter already zeroes that while the keyboard
    // covers it, so the two do not double-count.
    final spaceBelow =
        media.size.height -
        media.viewInsets.bottom -
        media.padding.bottom -
        (fieldTop + fieldSize.height);
    final spaceAbove = fieldTop - media.padding.top - media.viewInsets.top;

    final openUpward =
        spaceBelow < _minPanelHeight + _gap && spaceAbove > spaceBelow;
    final available = openUpward ? spaceAbove : spaceBelow;

    return (
      openUpward: openUpward,
      maxHeight: (available - _gap - 8).clamp(_minPanelHeight, _maxPanelHeight),
      width: fieldSize.width,
    );
  }

  void closePanel() {
    if (_entry == null) return;
    _entry!.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  /// Rebuilds the open panel.
  ///
  /// Deferred to after the frame because the entry is a sibling of this
  /// widget rather than a descendant: marking it dirty while this widget is
  /// building throws.
  void refreshPanel() {
    if (_entry == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entry?.markNeedsBuild();
    });
  }

  /// Removes the entry without touching state. Call from [dispose] — going
  /// through [closePanel] there would `setState` on a defunct widget.
  void disposePanel() {
    _entry?.remove();
    _entry = null;
  }
}
