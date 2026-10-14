import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobo_sales/models/contact.dart';
import 'package:mobo_sales/widgets/customer_typeahead.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final azure = Contact(id: 1, name: 'Azure Interior');
  final deco = Contact(id: 2, name: 'Deco Addict');

  Future<void> pump(
    WidgetTester tester, {
    Contact? selected,
    bool allowClear = true,
    bool enabled = true,
    ValueChanged<Contact>? onSelected,
    Future<List<Contact>> Function(String? query, int limit)? search,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: CustomerTypeAhead(
              labelText: 'Customer',
              isRequired: true,
              selectedCustomer: selected,
              allowClear: allowClear,
              enabled: enabled,
              search: search,
              onCustomerSelected: onSelected ?? (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the chosen customer in the field, avatar and name', (
    tester,
  ) async {
    await pump(tester, selected: azure);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Azure Interior');
    expect(find.byType(CircleAvatar), findsOneWidget, reason: 'the avatar');
    expect(find.text('A'), findsOneWidget, reason: 'initial for no photo');
    expect(find.text('Customer'), findsOneWidget);
  });

  testWidgets('a required field shows the chevron, not a clear button', (
    tester,
  ) async {
    await pump(tester, selected: azure, allowClear: false);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);

    await pump(tester, selected: azure, allowClear: true);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('the icon gives way to the avatar once someone is chosen', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(CircleAvatar), findsNothing);
    final iconsEmpty = find.byType(Icon).evaluate().length;

    await pump(tester, selected: azure);
    // The user icon is gone; the avatar took its place.
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.byType(Icon).evaluate().length, lessThanOrEqualTo(iconsEmpty));
  });

  testWidgets('follows a customer the screen sets or changes later', (
    tester,
  ) async {
    await pump(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );

    await pump(tester, selected: azure);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Azure Interior',
    );

    await pump(tester, selected: deco);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Deco Addict',
    );
    expect(find.text('D'), findsOneWidget);
  });

  testWidgets('a locked field does not open', (tester) async {
    await pump(tester, selected: azure, enabled: false);
    await tester.tap(find.byType(TextField), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No customers found'), findsNothing);
    expect(find.text('Search...'), findsNothing);
  });

  group('opening the list with a customer already chosen', () {
    final others = [
      Contact(id: 3, name: 'Gemini Furniture'),
      Contact(id: 4, name: 'Ready Mat'),
      Contact(id: 5, name: 'Wood Corner'),
    ];
    final everyone = [azure, ...others];

    testWidgets('shows every customer, the chosen one first and ticked', (
      tester,
    ) async {
      final asked = <String?>[];
      await pump(
        tester,
        selected: others[1],
        search: (q, limit) async {
          asked.add(q);
          return everyone;
        },
      );

      await tester.tap(find.byType(TextField));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(asked, [null], reason: 'one request, for the unfiltered page');
      for (final c in everyone) {
        expect(find.text(c.name), findsWidgets, reason: c.name);
      }
      expect(find.text('No customers found'), findsNothing);

      // The chosen customer is the first row, ahead of the others.
      final chosenY = tester.getTopLeft(find.text('Ready Mat').last).dy;
      for (final c in [azure, others[0], others[2]]) {
        expect(
          tester.getTopLeft(find.text(c.name).last).dy,
          greaterThan(chosenY),
          reason: '${c.name} is below the chosen customer',
        );
      }
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('reopening after a search shows the whole list again', (
      tester,
    ) async {
      final asked = <String?>[];
      await pump(
        tester,
        selected: azure,
        search: (q, limit) async {
          asked.add(q);
          return q == null
              ? everyone
              : everyone.where((c) => c.name.contains(q)).toList();
        },
      );

      await tester.tap(find.byType(TextField));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'Wood');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Wood Corner'), findsWidgets);
      expect(find.text('Ready Mat'), findsNothing);

      // Close it (tap the page), then open it again.
      await tester.tapAt(const Offset(4, 4));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(TextField));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(asked.last, isNull, reason: 'asked for the unfiltered page again');
      expect(find.text('Ready Mat'), findsWidgets);
    });

    testWidgets('does not ask twice when the list is already the full page', (
      tester,
    ) async {
      var requests = 0;
      await pump(
        tester,
        selected: azure,
        search: (q, limit) async {
          requests++;
          return everyone;
        },
      );
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byType(TextField));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tapAt(const Offset(4, 4));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(requests, 1);
    });
  });
}
