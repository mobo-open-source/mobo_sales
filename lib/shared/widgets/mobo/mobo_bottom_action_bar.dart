import 'package:flutter/material.dart';

import '../../design/mobo_tokens.dart';

/// The bar a create/edit form pins its submit button in.
///
/// Hand it to `Scaffold.bottomNavigationBar` so the action stays on screen
/// while the form scrolls behind it, instead of sitting at the end of a long
/// list where it has to be hunted for. It rides above the keyboard, so Save is
/// still reachable while a field is being typed in.
///
/// [child] is the button, or a `Row` of `Expanded` buttons for a Cancel/Save
/// pair. Its look is the caller's to keep; this only supplies the surface,
/// the hairline and shadow that separate it from the content, the page
/// gutter, and the bottom safe area.
class MoboBottomActionBar extends StatelessWidget {
  const MoboBottomActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MoboSpacing.page,
          vertical: 12,
        ),
        child: child,
      ),
    );
  }
}
