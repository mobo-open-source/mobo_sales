import 'package:flutter/material.dart';

/// Closes the keyboard and drops the focus when the user taps anywhere that is
/// not itself something to tap or type in — a card, a label, empty space.
///
/// It goes once, around the whole app (`MaterialApp.builder`), so every screen,
/// dialog and sheet behaves the same without each one carrying its own
/// `GestureDetector`.
///
/// Only a tap nothing else claims reaches it. A text field keeps the focus it
/// was just given, a tap on another field moves the focus there, and a button,
/// a row or a menu item does what it does: they all win the tap before this
/// does. A scroll or a drag is not a tap and is left alone.
class KeyboardDismisser extends StatelessWidget {
  const KeyboardDismisser({super.key, required this.child});

  final Widget? child;

  /// Drops the focus, which closes the keyboard.
  static void dismiss() => FocusManager.instance.primaryFocus?.unfocus();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: dismiss,
      child: child,
    );
  }
}
