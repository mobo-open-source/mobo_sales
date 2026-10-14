import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/shared/widgets/mobo/mobo_bottom_action_bar.dart';
import 'package:mobo_sales/utils/app_theme.dart';

/// The bar is what keeps a form's submit button on screen while the form
/// scrolls, so the thing worth proving is that it does not move with the body.
void main() {
  Widget form({required VoidCallback onSave, ThemeData? theme}) => MaterialApp(
    theme: theme ?? AppTheme.lightTheme,
    home: Scaffold(
      body: ListView(
        children: [
          for (var i = 0; i < 40; i++)
            SizedBox(height: 60, child: Text('Field $i')),
        ],
      ),
      bottomNavigationBar: MoboBottomActionBar(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(onPressed: onSave, child: const Text('Save')),
        ),
      ),
    ),
  );

  testWidgets('submit button stays at the bottom while the form scrolls', (
    tester,
  ) async {
    await tester.pumpWidget(form(onSave: () {}));

    final before = tester.getRect(find.text('Save'));
    expect(before.bottom, lessThanOrEqualTo(600));

    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();

    // The content moved a long way; the button did not.
    expect(find.text('Field 0'), findsNothing);
    expect(tester.getRect(find.text('Save')), before);
  });

  testWidgets('submit button is tappable from anywhere in the scroll', (
    tester,
  ) async {
    var saved = 0;
    await tester.pumpWidget(form(onSave: () => saved++));

    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));

    expect(saved, 1);
  });

  testWidgets('renders in the dark theme without exceptions', (tester) async {
    await tester.pumpWidget(form(onSave: () {}, theme: AppTheme.darkTheme));
    expect(find.text('Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
