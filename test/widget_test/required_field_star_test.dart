import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/shared/widgets/mobo/mobo_field_label.dart';
import 'package:mobo_sales/shared/widgets/mobo/mobo_select_field.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import 'package:mobo_sales/widgets/custom_date_picker.dart';
import 'package:mobo_sales/widgets/custom_text_field.dart';

/// The red star is how a form says "you cannot submit without this", so it has
/// to appear on every kind of field and only where asked for.
void main() {
  const red = Color(0xFFEF4444);

  Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
    theme: theme ?? AppTheme.lightTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  Color? starColor(WidgetTester tester) =>
      tester.widget<Text>(find.text(' *')).style?.color;

  testWidgets('MoboFieldLabel draws a red star only when required', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const MoboFieldLabel('Name', isRequired: true)),
    );
    expect(find.text('Name'), findsOneWidget);
    expect(find.text(' *'), findsOneWidget);
    expect(starColor(tester), red);

    await tester.pumpWidget(host(const MoboFieldLabel('Name')));
    expect(find.text('Name'), findsOneWidget);
    expect(find.text(' *'), findsNothing);
  });

  testWidgets('the star keeps the label\'s own font size', (tester) async {
    await tester.pumpWidget(
      host(
        const MoboFieldLabel(
          'Name',
          isRequired: true,
          style: TextStyle(fontSize: 19, color: Colors.grey),
        ),
      ),
    );

    final star = tester.widget<Text>(find.text(' *')).style!;
    expect(star.fontSize, 19);
    expect(star.color, red);
    // The label itself is untouched.
    expect(tester.widget<Text>(find.text('Name')).style!.color, Colors.grey);
  });

  testWidgets('CustomTextField shows the star when required', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CustomTextField(
          controller: controller,
          labelText: 'Product Name',
          isRequired: true,
          validator: (_) => null,
        ),
      ),
    );
    expect(find.text('Product Name'), findsOneWidget);
    expect(find.text(' *'), findsOneWidget);
    expect(starColor(tester), red);
  });

  testWidgets('CustomTextField has no star unless asked', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        CustomTextField(
          controller: controller,
          labelText: 'Notes',
          validator: (_) => null,
        ),
      ),
    );
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text(' *'), findsNothing);
  });

  testWidgets('CustomDateSelector shows the star when required', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        CustomDateSelector(
          onTap: () {},
          selectedDate: DateTime(2026, 1, 2),
          labelText: 'Invoice Date',
          isRequired: true,
        ),
      ),
    );
    expect(find.text('Invoice Date'), findsOneWidget);
    expect(find.text(' *'), findsOneWidget);
    expect(starColor(tester), red);
  });

  testWidgets('the star is the same red on a Mobo select, light and dark', (
    tester,
  ) async {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      await tester.pumpWidget(
        host(
          MoboSelectField<int>(
            label: 'Country',
            isRequired: true,
            options: const [MoboOption(value: 1, label: 'India')],
            value: null,
            onChanged: (_) {},
          ),
          theme: theme,
        ),
      );
      expect(find.text(' *'), findsOneWidget);
      expect(starColor(tester), red);
    }
  });

  testWidgets('works as an InputDecoration label, which floats', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        TextFormField(
          decoration: const InputDecoration(
            label: MoboFieldLabel('Amount', isRequired: true),
          ),
        ),
      ),
    );
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text(' *'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
