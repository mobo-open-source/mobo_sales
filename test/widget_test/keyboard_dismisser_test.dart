import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/shared/widgets/mobo/mobo_select_field.dart';
import 'package:mobo_sales/widgets/keyboard_dismisser.dart';

void main() {
  // Mounted the way the app does it: around the whole Navigator.
  Widget app(Widget home) => MaterialApp(
    builder: (context, child) => KeyboardDismisser(child: child),
    home: home,
  );

  FocusNode? focused() => FocusManager.instance.primaryFocus;

  /// Whether a text input holds the focus (which is what keeps the keyboard up).
  bool typing() =>
      focused()?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

  Widget form({
    required TextEditingController a,
    required TextEditingController b,
    VoidCallback? onButton,
  }) => Scaffold(
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(key: const Key('a'), controller: a),
        const SizedBox(height: 16),
        TextField(key: const Key('b'), controller: b),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: onButton ?? () {}, child: const Text('BTN')),
        const SizedBox(height: 16),
        const Card(
          child: Padding(padding: EdgeInsets.all(40), child: Text('A CARD')),
        ),
        const SizedBox(height: 600),
      ],
    ),
  );

  testWidgets('tapping empty space or a card closes the keyboard', (
    tester,
  ) async {
    final a = TextEditingController(), b = TextEditingController();
    await tester.pumpWidget(app(form(a: a, b: b)));

    await tester.tap(find.byKey(const Key('a')));
    await tester.pump();
    expect(typing(), isTrue);

    await tester.tap(find.text('A CARD'));
    await tester.pump();
    expect(typing(), isFalse, reason: 'tap on a card');

    await tester.tap(find.byKey(const Key('b')));
    await tester.pump();
    expect(typing(), isTrue);
    await tester.tapAt(const Offset(780, 10));
    await tester.pump();
    expect(typing(), isFalse, reason: 'tap on empty space');
  });

  testWidgets('tapping a field keeps the focus there; another field takes it', (
    tester,
  ) async {
    final a = TextEditingController(), b = TextEditingController();
    await tester.pumpWidget(app(form(a: a, b: b)));

    await tester.tap(find.byKey(const Key('a')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('a')));
    await tester.pump();
    expect(typing(), isTrue, reason: 'tapping the same field');

    await tester.tap(find.byKey(const Key('b')));
    await tester.pump();
    expect(typing(), isTrue, reason: 'moved to the other field');
    await tester.enterText(find.byKey(const Key('b')), 'hello');
    expect(b.text, 'hello');
    expect(a.text, isEmpty);
  });

  testWidgets(
    'a button still works, and a scroll does not close the keyboard',
    (tester) async {
      final a = TextEditingController(), b = TextEditingController();
      var pressed = 0;
      await tester.pumpWidget(app(form(a: a, b: b, onButton: () => pressed++)));

      await tester.tap(find.byKey(const Key('a')));
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, -40));
      await tester.pump();
      expect(typing(), isTrue, reason: 'scrolling is not a tap');

      await tester.tap(find.text('BTN'));
      await tester.pump();
      expect(pressed, 1, reason: 'the button got its tap');
    },
  );

  testWidgets('works inside a dialog and a bottom sheet too', (tester) async {
    final a = TextEditingController(), b = TextEditingController();
    late BuildContext host;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) {
            host = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );

    showDialog<void>(
      context: host,
      builder: (_) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(key: const Key('d'), controller: a),
            const Text('DIALOG TEXT'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('d')));
    await tester.pump();
    expect(typing(), isTrue);
    await tester.tap(find.text('DIALOG TEXT'));
    await tester.pump();
    expect(typing(), isFalse, reason: 'dialog text');

    Navigator.pop(host);
    await tester.pumpAndSettle();

    showModalBottomSheet<void>(
      context: host,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(key: const Key('s'), controller: b),
            const SizedBox(height: 20),
            const Text('SHEET TEXT'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('s')));
    await tester.pump();
    expect(typing(), isTrue);
    await tester.tap(find.text('SHEET TEXT'));
    await tester.pump();
    expect(typing(), isFalse, reason: 'sheet text');
  });

  testWidgets('a searchable Mobo dropdown still takes typing and a pick', (
    tester,
  ) async {
    String? value;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: MoboSelectField<String>(
                label: 'Customer',
                searchable: true,
                value: value,
                options: const [
                  MoboOption(value: 'a', label: 'Azure Interior'),
                  MoboOption(value: 'b', label: 'Deco Addict'),
                ],
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'Dec');
    await tester.pump(const Duration(milliseconds: 100));
    expect(typing(), isTrue, reason: 'still typing in the search box');

    // A row of the list is tapped: the dropdown's own tap, not ours.
    await tester.tap(find.text('Deco Addict'));
    await tester.pumpAndSettle();
    expect(value, 'b');
  });
}
