import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/shared/widgets/mobo/mobo_select_form_field.dart';
import 'package:mobo_sales/utils/app_theme.dart';

/// [MoboSelectFormField] exists so a screen can swap a `DropdownButtonFormField`
/// for the Mobo select without losing `Form.validate()`.
void main() {
  const options = [
    MoboOption(value: 1, label: 'Alice'),
    MoboOption(value: 2, label: 'Bob'),
  ];

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.lightTheme,
    // A form lives in a scroll view; the field is built for unbounded height.
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets(
    'validator error shows on validate and clears once a value is picked',
    (tester) async {
      final formKey = GlobalKey<FormState>();
      int? value;

      await tester.pumpWidget(
        host(
          Form(
            key: formKey,
            child: StatefulBuilder(
              builder: (context, setState) => MoboSelectFormField<int>(
                label: 'Customer',
                options: options,
                value: value,
                onChanged: (v) => setState(() => value = v),
                validator: (v) => v == null ? 'Please select a customer' : null,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Please select a customer'), findsNothing);

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Please select a customer'), findsOneWidget);

      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();

      expect(value, 2);
      expect(formKey.currentState!.validate(), isTrue);
      await tester.pump();
      expect(find.text('Please select a customer'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a value changed by the parent reaches the validator', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    final value = ValueNotifier<int?>(null);
    addTearDown(value.dispose);

    await tester.pumpWidget(
      host(
        Form(
          key: formKey,
          child: ValueListenableBuilder<int?>(
            valueListenable: value,
            builder: (context, current, _) => MoboSelectFormField<int>(
              options: options,
              value: current,
              onChanged: (_) {},
              validator: (v) => v == null ? 'required' : null,
            ),
          ),
        ),
      ),
    );

    expect(formKey.currentState!.validate(), isFalse);

    // Set from outside — a provider loading a default, say — not by the user.
    value.value = 1;
    await tester.pump();

    expect(formKey.currentState!.validate(), isTrue);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('clear button reports null and the validator sees it', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    int? value = 1;

    await tester.pumpWidget(
      host(
        Form(
          key: formKey,
          child: StatefulBuilder(
            builder: (context, setState) => MoboSelectFormField<int>(
              options: options,
              value: value,
              onChanged: (v) => setState(() => value = v),
              validator: (v) => v == null ? 'required' : null,
            ),
          ),
        ),
      ),
    );

    expect(formKey.currentState!.validate(), isTrue);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(value, isNull);
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('required'), findsOneWidget);
  });

  testWidgets('disabled field cannot be opened', (tester) async {
    await tester.pumpWidget(
      host(
        MoboSelectFormField<int>(
          options: options,
          value: null,
          enabled: false,
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsNothing);
  });
}
