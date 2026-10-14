import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/shared/widgets/mobo/mobo_dialog_buttons.dart';
import 'package:mobo_sales/utils/app_theme.dart';

void main() {
  Widget host(MoboDialogButtons buttons) => MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: Center(child: AlertDialog(actions: [buttons])),
    ),
  );

  testWidgets(
    'outlined secondary on the left, filled primary on the right, equal width',
    (tester) async {
      await tester.pumpWidget(
        host(
          MoboDialogButtons(
            secondaryLabel: 'Cancel',
            onSecondary: () {},
            primaryLabel: 'Save',
            onPrimary: () {},
          ),
        ),
      );

      final left = tester.getRect(find.byType(OutlinedButton));
      final right = tester.getRect(find.byType(ElevatedButton));
      expect(left.right, lessThan(right.left));
      expect(left.width, right.width);
      expect(left.height, 48);
      expect(right.height, 48);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('each button calls its own callback', (tester) async {
    var cancelled = 0, saved = 0;
    await tester.pumpWidget(
      host(
        MoboDialogButtons(
          secondaryLabel: 'Cancel',
          onSecondary: () => cancelled++,
          primaryLabel: 'Save',
          onPrimary: () => saved++,
        ),
      ),
    );
    await tester.tap(find.text('Cancel'));
    await tester.tap(find.text('Save'));
    expect([cancelled, saved], [1, 1]);
  });

  testWidgets(
    'null primary disables it; loading shows a spinner and blocks both',
    (tester) async {
      await tester.pumpWidget(
        host(
          MoboDialogButtons(
            secondaryLabel: 'Cancel',
            onSecondary: () {},
            primaryLabel: 'Save',
            onPrimary: null,
          ),
        ),
      );
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );

      await tester.pumpWidget(
        host(
          MoboDialogButtons(
            secondaryLabel: 'Cancel',
            onSecondary: () {},
            primaryLabel: 'Save',
            onPrimary: () {},
            isLoading: true,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
    },
  );
}
