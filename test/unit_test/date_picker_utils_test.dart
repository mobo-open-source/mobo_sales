import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/date_picker_utils.dart';

void main() {
  testWidgets('showStandardDatePicker renders correctly', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () =>
                    DatePickerUtils.showStandardDatePicker(context: context),
                child: const Text('Show Picker'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show Picker'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);

    final theme = Theme.of(tester.element(find.byType(DatePickerDialog)));
    expect(theme.dialogBackgroundColor, isNotNull);
  });

  testWidgets('showStandardTimePicker renders correctly', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () =>
                    DatePickerUtils.showStandardTimePicker(context: context),
                child: const Text('Show Time Picker'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show Time Picker'));
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsOneWidget);
  });
}
