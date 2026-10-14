import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/shared/widgets/mobo/mobo_multi_select_field.dart';
import 'package:mobo_sales/shared/widgets/mobo/mobo_select_field.dart';
import 'package:mobo_sales/utils/app_theme.dart';

void main() {
  const options = [
    MoboOption(value: 1, label: 'Alice'),
    MoboOption(value: 2, label: 'Bob'),
  ];

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  group('single select', () {
    testWidgets(
      'shows the clear button in place of the chevron once it has a value',
      (tester) async {
        await tester.pumpWidget(
          host(
            MoboSelectField<int>(
              options: options,
              value: null,
              onChanged: (_) {},
            ),
          ),
        );
        expect(find.byIcon(Icons.close), findsNothing);
        expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);

        await tester.pumpWidget(
          host(
            MoboSelectField<int>(options: options, value: 1, onChanged: (_) {}),
          ),
        );
        expect(find.byIcon(Icons.close), findsOneWidget);
        expect(
          find.byIcon(Icons.arrow_drop_down),
          findsNothing,
          reason: 'one icon at a time',
        );
      },
    );

    testWidgets('clear reports null without opening the list', (tester) async {
      int? value = 1;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (c, set) => MoboSelectField<int>(
              options: options,
              value: value,
              onChanged: (v) => set(() => value = v),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(value, isNull);
      expect(find.text('Bob'), findsNothing, reason: 'panel stayed closed');
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('disabled or allowClear:false hides it', (tester) async {
      await tester.pumpWidget(
        host(
          MoboSelectField<int>(
            options: options,
            value: 1,
            enabled: false,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.byIcon(Icons.close), findsNothing);
      await tester.pumpWidget(
        host(
          MoboSelectField<int>(
            options: options,
            value: 1,
            allowClear: false,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('searchable: typed text clears first, then the value', (
      tester,
    ) async {
      int? value = 1;
      final searches = <String>[];
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (c, set) => MoboSelectField<int>(
              options: options,
              value: value,
              searchable: true,
              onSearchChanged: searches.add,
              onChanged: (v) => set(() => value = v),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bo');
      await tester.pumpAndSettle();
      expect(searches.last, 'bo');

      // First tap: empties the query, keeps the value and the open panel.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(searches.last, '');
      expect(value, 1);
      expect(find.text('Bob'), findsOneWidget, reason: 'full list is back');

      // Second tap: nothing typed now, so it clears the value.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(value, isNull);
    });
  });

  group('multi select', () {
    testWidgets('clear button empties the selection', (tester) async {
      List<int> values = [1, 2];
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (c, set) => MoboMultiSelectField<int>(
              options: options,
              values: values,
              onChanged: (v) => set(() => values = v),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.close), findsWidgets);

      await tester.tap(find.bySemanticsLabel('Clear all'));
      await tester.pumpAndSettle();

      expect(values, isEmpty);
      expect(find.text('Pick'), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
