import 'package:flutter/material.dart';

import '../../design/mobo_tokens.dart';

/// The Mobo checkbox: a rounded square with a brand-coloured outline that fills
/// with the brand colour and a white check once selected.
///
/// Built to the design spec, at its 24 dp reference size:
///
/// | state          | fill            | outline        | mark            |
/// |----------------|-----------------|----------------|-----------------|
/// | default        | surface (white) | 1.5 dp brand   | —               |
/// | hover / press  | `#FAE6E8` tint  | 1.5 dp brand   | —               |
/// | selected       | brand           | (same as fill) | white check     |
/// | indeterminate  | brand           | (same as fill) | white dash      |
///
/// Corner radius is a third of the size (8 dp), and the check and dash use
/// the same 1.5 dp round-capped stroke as the outline. Everything scales with
/// [size], so a larger box keeps the same proportions.
///
/// Hover is what a mouse sees; on a touch screen the same tint shows while the
/// box is pressed, so it reads as responding to the finger.
///
/// This is the bare box. For a form field with its label, use
/// [MoboCheckboxField].
class MoboCheckbox extends StatefulWidget {
  const MoboCheckbox({
    super.key,
    required this.value,
    this.onChanged,
    this.tristate = false,
    this.enabled = true,
    this.size = 24,
    this.tapTargetSize,
  });

  /// `true` is selected, `false` unselected. `null` is indeterminate, and only
  /// when [tristate] is set; otherwise it reads as unselected.
  final bool? value;

  /// Called with the next value when the box is tapped.
  ///
  /// Null makes the box a pure display of [value] — for a row whose own tap
  /// does the toggling. It is drawn at full strength; set [enabled] to false
  /// to dim it.
  final ValueChanged<bool?>? onChanged;

  /// Whether a tap also cycles through the indeterminate state
  /// (unselected → selected → indeterminate → unselected).
  final bool tristate;

  /// False dims the box and ignores taps.
  final bool enabled;

  /// Edge length of the box. The design's reference size is 24.
  final double size;

  /// Edge length of the area that takes taps, and of the space the box
  /// occupies in layout, with the box centred in it. Defaults to [size].
  ///
  /// Raise it (48 is the usual minimum) for a checkbox that stands alone and
  /// has to be hit with a fingertip. A box inside a tappable row needs no such
  /// padding.
  final double? tapTargetSize;

  @override
  State<MoboCheckbox> createState() => _MoboCheckboxState();
}

class _MoboCheckboxState extends State<MoboCheckbox> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _interactive => widget.enabled && widget.onChanged != null;

  bool? get _value => widget.tristate ? widget.value : (widget.value ?? false);

  void _toggle() {
    final next = switch (_value) {
      false => true,
      true => widget.tristate ? null : false,
      null => false,
    };
    widget.onChanged!(next);
  }

  @override
  void didUpdateWidget(covariant MoboCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A box that stopped being interactive while hovered or pressed would
    // otherwise be left wearing the highlight.
    if (!_interactive) {
      _hovered = false;
      _pressed = false;
      _focused = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget box = _CheckboxBox(
      value: _value,
      size: widget.size,
      highlighted: _hovered || _pressed,
      focused: _focused,
      enabled: widget.enabled,
    );

    final target = widget.tapTargetSize ?? widget.size;
    if (target > widget.size) {
      box = SizedBox.square(
        dimension: target,
        child: Center(child: box),
      );
    }

    box = Semantics(
      checked: _value == true,
      mixed: _value == null,
      enabled: _interactive,
      child: ExcludeSemantics(child: box),
    );

    if (!_interactive) return box;

    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (hovered) => setState(() => _hovered = hovered),
      onShowFocusHighlight: (focused) => setState(() => _focused = focused),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _toggle();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _toggle,
        child: box,
      ),
    );
  }
}

/// A checkbox field for a form: the label at the start of the row and the box
/// at the far end, the whole row tappable.
///
/// This is how every checkbox in a form should sit, so they line up with each
/// other and with the right edge of the text fields above and below. A null
/// [onChanged] disables the row.
class MoboCheckboxField extends StatefulWidget {
  const MoboCheckboxField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  State<MoboCheckboxField> createState() => _MoboCheckboxFieldState();
}

class _MoboCheckboxFieldState extends State<MoboCheckboxField> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onChanged != null;

  void _toggle() => widget.onChanged!(!widget.value);

  @override
  Widget build(BuildContext context) {
    final colors = context.mobo;

    return Semantics(
      container: true,
      label: widget.label,
      checked: widget.value,
      enabled: _enabled,
      onTap: _enabled ? _toggle : null,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: _enabled ? 1 : _disabledOpacity,
          // Its own Material, so the ripple is painted above whatever card or
          // container the field sits in rather than hidden under it.
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(MoboRadius.field),
              onTap: _enabled ? _toggle : null,
              onHighlightChanged: (pressed) =>
                  setState(() => _pressed = pressed),
              onHover: (hovered) => setState(() => _hovered = hovered),
              onFocusChange: (focused) => setState(() => _focused = focused),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: MoboSpacing.fieldMinHeight,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MoboType.label(colors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _CheckboxBox(
                      value: widget.value,
                      highlighted: _enabled && (_hovered || _pressed),
                      focused: _enabled && _focused,
                      // The row is dimmed as a whole above.
                      enabled: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A disabled control is dimmed to this, as the Mobo field shell is.
const double _disabledOpacity = 0.6;

/// The tint a hovered or pressed box takes on in the light theme, from the
/// design spec.
const Color _lightHoverFill = Color(0xFFFAE6E8);

/// The box itself — fill, outline and mark — with no gesture handling.
class _CheckboxBox extends StatelessWidget {
  const _CheckboxBox({
    required this.value,
    required this.highlighted,
    required this.focused,
    required this.enabled,
    this.size = 24,
  });

  /// `true` selected, `false` unselected, `null` indeterminate.
  final bool? value;
  final bool highlighted;
  final bool focused;
  final bool enabled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobo;
    final filled = value != false;
    final stroke = size * _strokeRatio;

    final Color fill;
    if (filled) {
      fill = colors.primary;
    } else if (highlighted) {
      fill = colors.isDark ? colors.primaryTint : _lightHoverFill;
    } else {
      fill = colors.surface;
    }

    final box = AnimatedContainer(
      duration: _animation,
      curve: Curves.easeOut,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(size * _radiusRatio),
        // Painted inside the box, so it stays `size` wide. Once selected the
        // outline is the fill's own colour, which is why the spec shows none.
        border: Border.all(color: colors.primary, width: stroke),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.28),
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      // The check draws itself in; the dash, being a different mark, is just
      // there.
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: value == true ? 1 : 0),
        duration: _animation,
        curve: Curves.easeOut,
        builder: (context, progress, _) => CustomPaint(
          painter: _MarkPainter(
            checkProgress: progress,
            dash: value == null,
            color: Colors.white,
            strokeWidth: stroke,
            boxSize: size,
          ),
        ),
      ),
    );

    return enabled ? box : Opacity(opacity: _disabledOpacity, child: box);
  }
}

const Duration _animation = Duration(milliseconds: 120);

/// Corner radius and stroke weight as a fraction of the box, which at the
/// 24 dp reference size give the spec's 8 dp radius and 1.5 dp strokes.
const double _radiusRatio = 1 / 3;
const double _strokeRatio = 0.0625;

/// Draws the check (or the dash) in the box, to the spec's proportions.
class _MarkPainter extends CustomPainter {
  const _MarkPainter({
    required this.checkProgress,
    required this.dash,
    required this.color,
    required this.strokeWidth,
    required this.boxSize,
  });

  /// 0 draws nothing, 1 the whole check.
  final double checkProgress;
  final bool dash;
  final Color color;
  final double strokeWidth;

  /// Edge of the whole box. The canvas handed to [paint] is smaller: the box's
  /// outline is its decoration's border, which insets the child by its width.
  /// The mark is proportioned to the whole box, so [paint] steps back out.
  final double boxSize;

  // The check's three points, as fractions of the box, fitted to the design
  // spec: two 45° strokes meeting at a vertex below and left of centre, the
  // mark centred in the box and about 0.49 of its width across.
  static const _checkStart = Offset(0.2577, 0.5350);
  static const _checkVertex = Offset(0.3943, 0.6740);
  static const _checkEnd = Offset(0.7450, 0.3245);

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final inset = (boxSize - canvasSize.width) / 2;
    canvas.translate(-inset, -inset);
    final size = Size.square(boxSize);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Offset at(Offset f) => Offset(f.dx * size.width, f.dy * size.height);

    if (dash) {
      canvas.drawLine(
        Offset(_checkStart.dx * size.width, size.height / 2),
        Offset(_checkEnd.dx * size.width, size.height / 2),
        paint,
      );
      return;
    }

    if (checkProgress <= 0) return;

    final check = Path()
      ..moveTo(at(_checkStart).dx, at(_checkStart).dy)
      ..lineTo(at(_checkVertex).dx, at(_checkVertex).dy)
      ..lineTo(at(_checkEnd).dx, at(_checkEnd).dy);

    final metric = check.computeMetrics().single;
    canvas.drawPath(
      metric.extractPath(0, metric.length * checkProgress.clamp(0.0, 1.0)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.checkProgress != checkProgress ||
      old.dash != dash ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.boxSize != boxSize;
}
