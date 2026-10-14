import 'package:flutter/widgets.dart';

/// Disposes [controllers] when this widget leaves the tree — not before.
///
/// A dialog that disposes its fields' controllers the moment it pops itself is
/// disposing them while it is still on screen: a popped route animates out for
/// a moment, the keyboard is hiding, and the fields rebuild in that window. A
/// field that finds its controller already disposed asserts "A
/// TextEditingController was used after being disposed".
///
/// Wrap the dialog in this and the controllers go only once the dialog's own
/// widgets have been unmounted (children first), when nothing can touch them.
class DisposeWhenUnmounted extends StatefulWidget {
  const DisposeWhenUnmounted({
    super.key,
    required this.controllers,
    required this.child,
  });

  final List<ChangeNotifier> controllers;
  final Widget child;

  @override
  State<DisposeWhenUnmounted> createState() => _DisposeWhenUnmountedState();
}

class _DisposeWhenUnmountedState extends State<DisposeWhenUnmounted> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
