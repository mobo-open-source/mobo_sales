import 'package:flutter/material.dart';

class LazyLoadIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final AlignmentGeometry alignment;
  final TextDirection? textDirection;
  final StackFit sizing;

  const LazyLoadIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.alignment = AlignmentDirectional.topStart,
    this.textDirection,
    this.sizing = StackFit.loose,
  });

  @override
  _LazyLoadIndexedStackState createState() => _LazyLoadIndexedStackState();
}

class _LazyLoadIndexedStackState extends State<LazyLoadIndexedStack> {
  late List<bool> _activatedFlags;

  @override
  void initState() {
    super.initState();

    _activatedFlags = List.generate(
      widget.children.length,
      (i) => i == widget.index,
    );
  }

  @override
  void didUpdateWidget(LazyLoadIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.index != widget.index) {
      if (widget.index >= 0 && widget.index < _activatedFlags.length) {
        if (!_activatedFlags[widget.index]) {
          setState(() {
            _activatedFlags[widget.index] = true;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      alignment: widget.alignment,
      textDirection: widget.textDirection,
      sizing: widget.sizing,
      children: List.generate(widget.children.length, (i) {
        return _activatedFlags[i]
            ? widget.children[i]
            : const SizedBox.shrink();
      }),
    );
  }
}
