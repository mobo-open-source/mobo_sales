import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/widgets/custom_text_field.dart';
import 'package:mobo_sales/widgets/dispose_when_unmounted.dart';

/// Counts how many times it has been disposed, and when.
class _Probe extends TextEditingController {
  _Probe({super.text});
  int disposals = 0;

  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

void main() {
  late BuildContext host;

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
  }

  /// The Edit Address dialogs' shape: fields built from [CustomTextField], a
  /// Cancel that pops, and the controllers owned by [DisposeWhenUnmounted].
  void openDialog(_Probe a, _Probe b) {
    showDialog<void>(
      context: host,
      builder: (dialogContext) => DisposeWhenUnmounted(
        controllers: [a, b],
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomTextField(
                controller: a,
                labelText: 'Street',
                validator: (_) => null,
              ),
              CustomTextField(
                controller: b,
                labelText: 'City',
                validator: (_) => null,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets(
    'closing the dialog while the keyboard hides does not touch a disposed controller',
    (tester) async {
      final a = _Probe(text: 'abc');
      final b = _Probe(text: 'xyz');
      await pumpHost(tester);
      openDialog(a, b);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextFormField).first);
      await tester.pump();
      addTearDown(tester.view.resetViewInsets);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      // The dialog is animating out and the keyboard is going away: the fields
      // rebuild in these frames.
      tester.view.viewInsets = const FakeViewPadding(bottom: 150);
      await tester.pump(const Duration(milliseconds: 50));
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the controllers survive the exit animation and go once the dialog is gone',
    (tester) async {
      final a = _Probe(text: 'abc');
      final b = _Probe(text: 'xyz');
      await pumpHost(tester);
      openDialog(a, b);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: 'still animating out',
      );
      expect([a.disposals, b.disposals], [0, 0], reason: 'not disposed yet');

      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        [a.disposals, b.disposals],
        [1, 1],
        reason: 'disposed exactly once',
      );
    },
  );

  testWidgets('keeps the controllers alive while the widget stays mounted', (
    tester,
  ) async {
    final c = _Probe();
    await tester.pumpWidget(
      MaterialApp(
        home: DisposeWhenUnmounted(
          controllers: [c],
          child: Material(child: TextField(controller: c)),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'typing');
    await tester.pump();
    expect(c.text, 'typing');
    expect(c.disposals, 0);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(c.disposals, 1);
  });
}
