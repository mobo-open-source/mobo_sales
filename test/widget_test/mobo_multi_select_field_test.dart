import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/shared/widgets/mobo/mobo_checkbox.dart';
import 'package:mobo_sales/shared/widgets/mobo/mobo_multi_select_field.dart';
import 'package:mobo_sales/utils/app_theme.dart';

/// The multi-select panel shows each option with the Mobo checkbox at the end
/// of its row; the row's own tap does the toggling.
void main() {
  const options = [
    MoboOption(value: 1, label: 'Alice'),
    MoboOption(value: 2, label: 'Bob'),
    MoboOption(value: 3, label: 'Carol'),
  ];

  Widget host({
    required List<int> values,
    required ValueChanged<List<int>> onChanged,
  }) => MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SingleChildScrollView(
        child: MoboMultiSelectField<int>(
          title: 'Pick people',
          options: options,
          values: values,
          onChanged: onChanged,
        ),
      ),
    ),
  );

  List<bool?> boxes(WidgetTester tester) => [
    for (final box in tester.widgetList<MoboCheckbox>(
      find.byType(MoboCheckbox),
    ))
      box.value,
  ];

  testWidgets('each row ends in a checkbox showing whether it is chosen', (
    tester,
  ) async {
    await tester.pumpWidget(host(values: const [2], onChanged: (_) {}));
    await tester.tap(find.byType(MoboMultiSelectField<int>));
    await tester.pumpAndSettle();

    expect(find.text('Pick people'), findsOneWidget);
    expect(boxes(tester), [false, true, false]);

    // Each box sits at the right-hand end of its row, after the label.
    final aliceRow = tester.getRect(find.text('Alice').last);
    final firstBox = tester.getRect(find.byType(MoboCheckbox).first);
    expect(firstBox.left, greaterThan(aliceRow.right));
    expect(firstBox.size, const Size(24, 24));
  });

  testWidgets('tapping a row toggles its box, and Done commits the choice', (
    tester,
  ) async {
    List<int>? committed;
    await tester.pumpWidget(
      host(values: const [2], onChanged: (v) => committed = v),
    );
    await tester.tap(find.byType(MoboMultiSelectField<int>));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alice').last);
    await tester.pumpAndSettle();
    expect(boxes(tester), [true, true, false]);
    expect(committed, isNull, reason: 'nothing is committed before Done');

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(committed, [2, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clear All unticks every box', (tester) async {
    await tester.pumpWidget(host(values: const [1, 3], onChanged: (_) {}));
    await tester.tap(find.byType(MoboMultiSelectField<int>));
    await tester.pumpAndSettle();
    expect(boxes(tester), [true, false, true]);

    await tester.tap(find.text('Clear All'));
    await tester.pumpAndSettle();
    expect(boxes(tester), [false, false, false]);
  });
}
