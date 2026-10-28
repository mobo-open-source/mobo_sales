import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/shared/widgets/mobo/mobo_dialog_buttons.dart';

/// The two buttons every dialog ends in have to survive a narrow phone.
///
/// A tester reported the "Create Draft" action on the invoice dialog looking
/// wrong: two equal halves of a 280pt dialog leave each button about 86pt for
/// its label, and "Create Draft" at 16pt bold wants more than that, so it was
/// quietly cut to "Create Dra…".
void main() {
  /// Renders the pair inside a box [width] wide, as a dialog's footer would.
  Future<void> pumpAt(
    WidgetTester tester,
    double width, {
    String primary = 'Create Draft',
    String secondary = 'Cancel',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: MoboDialogButtons(
                secondaryLabel: secondary,
                onSecondary: () {},
                primaryLabel: primary,
                onPrimary: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The painted width of [text] on screen, with any scaling applied.
  double paintedWidth(WidgetTester tester, String text) =>
      tester.getRect(find.text(text)).width;

  testWidgets('a long label is shown whole, not cut short', (tester) async {
    // An AlertDialog on a 360pt phone: 360 - 80 inset - 48 actions padding.
    await pumpAt(tester, 232);

    for (final text in ['Cancel', 'Create Draft']) {
      final button = find.ancestor(
        of: find.text(text),
        matching: find.byType(SizedBox),
      );
      final room = tester.getSize(button.first).width;
      expect(
        paintedWidth(tester, text),
        lessThanOrEqualTo(room + 0.5),
        reason: '"$text" paints wider than its button, so it is clipped',
      );
      // The whole string is still in the tree — nothing was replaced by "…".
      expect(find.text(text), findsOneWidget);
    }
  });

  testWidgets('the longest label in the app fits too', (tester) async {
    await pumpAt(tester, 232, primary: 'Register Payment');
    expect(find.text('Register Payment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a large text scale does not break it', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpAt(tester, 232);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Create Draft'), findsOneWidget);
  });

  testWidgets('it lays out inside a real AlertDialog', (tester) async {
    // AlertDialog measures its actions with intrinsic dimensions, which some
    // layout widgets cannot answer. Putting one of those here threw during
    // layout in every dialog in the app, so this guards the footer against
    // being rebuilt that way again.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Create Invoice'),
                  content: const Text('Select Invoice Type'),
                  actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  actions: [
                    MoboDialogButtons(
                      secondaryLabel: 'Cancel',
                      onSecondary: () {},
                      primaryLabel: 'Create Draft',
                      onPrimary: () {},
                    ),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Create Draft'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('both actions still fire', (tester) async {
    var cancelled = false;
    var created = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 232,
              child: MoboDialogButtons(
                secondaryLabel: 'Cancel',
                onSecondary: () => cancelled = true,
                primaryLabel: 'Create Draft',
                onPrimary: () => created = true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Create Draft'));
    await tester.tap(find.text('Cancel'));

    expect(created, isTrue);
    expect(cancelled, isTrue);
  });
}
