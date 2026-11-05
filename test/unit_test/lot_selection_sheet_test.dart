import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/delivery_lot_service.dart';
import 'package:mobo_sales/widgets/lot_selection_sheet.dart';

/// What the sheet handed back when it closed; null while open or dismissed.
LotSelection? returned;

Future<void> open(
  WidgetTester tester, {
  required bool isSerial,
  required double demand,
  required List<LotStock> lots,
  Map<int, double> selected = const {},
  bool canCreate = false,
  bool canUseExisting = true,
  String? suggestedFirst,
  Future<List<String>> Function(String first, int count)? generate,
}) async {
  returned = null;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              returned = await showLotSelectionSheet(
                context,
                productName: 'Widget',
                demand: demand,
                isSerial: isSerial,
                lots: lots,
                selected: selected,
                canCreate: canCreate,
                canUseExisting: canUseExisting,
                suggestedFirst: suggestedFirst,
                generate: generate,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  const serials = [
    LotStock(lotId: 1, name: 'S1', available: 1),
    LotStock(lotId: 2, name: 'S2', available: 1),
    LotStock(lotId: 3, name: 'S3', available: 1),
  ];

  testWidgets('serials: cannot tick more than the demand', (tester) async {
    await open(tester, isSerial: true, demand: 2, lots: serials);
    expect(find.text('Select Serial Numbers'), findsOneWidget);

    await tester.tap(find.text('S1'));
    await tester.tap(find.text('S2'));
    await tester.pump();
    await tester.tap(find.text('S3'));
    await tester.pump();

    final boxes = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .map((c) => c.value)
        .toList();
    expect(boxes, [true, true, false]);
    expect(find.text('Selected 2 of 2'), findsOneWidget);
  });

  testWidgets('Save is disabled until something is selected', (tester) async {
    await open(tester, isSerial: true, demand: 2, lots: serials);
    final save = find.widgetWithText(ElevatedButton, 'Save');
    expect(tester.widget<ElevatedButton>(save).onPressed, isNull);

    await tester.tap(find.text('S1'));
    await tester.pump();
    expect(tester.widget<ElevatedButton>(save).onPressed, isNotNull);
  });

  testWidgets('lots: a quantity above what the lot has free blocks Save', (
    tester,
  ) async {
    await open(
      tester,
      isSerial: false,
      demand: 10,
      lots: const [LotStock(lotId: 7, name: 'L7', available: 5)],
    );
    await tester.tap(find.text('L7'));
    await tester.pump();
    // Ticking fills in what it can: the lot's 5.
    expect(find.text('Selected 5 of 10'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '8');
    await tester.pump();
    expect(find.textContaining('has only 5'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Save'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('an existing selection is shown ticked, and Save returns it', (
    tester,
  ) async {
    await open(
      tester,
      isSerial: false,
      demand: 4,
      lots: const [LotStock(lotId: 7, name: 'L7', available: 9)],
      selected: const {7: 4},
    );
    expect(find.text('Selected 4 of 4'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    expect(returned?.existing, {7: 4.0});
  });

  testWidgets('serials: Save returns one unit per ticked serial', (
    tester,
  ) async {
    await open(tester, isSerial: true, demand: 2, lots: serials);
    await tester.tap(find.text('S1'));
    await tester.tap(find.text('S3'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    expect(returned?.existing, {1: 1.0, 3: 1.0});
  });

  testWidgets('no lots with stock says so', (tester) async {
    await open(tester, isSerial: false, demand: 1, lots: const []);
    expect(find.textContaining('have stock at the source'), findsOneWidget);
  });

  group('creating new numbers (the operation type may create lots)', () {
    Future<List<String>> fakeGenerate(String first, int count) async =>
        generateLotNamesLocally(first, count);

    testWidgets('Generate makes the numbers from the first one', (
      tester,
    ) async {
      await open(
        tester,
        isSerial: true,
        demand: 3,
        lots: const [],
        canCreate: true,
        suggestedFirst: 'SN-009',
        generate: fakeGenerate,
      );
      // Odoo's suggestion is already in the first box, and the count is the
      // demand.
      expect(find.widgetWithText(TextField, 'SN-009'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lot-generate')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'SN-009'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'SN-010'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'SN-011'), findsOneWidget);
      expect(find.text('Selected 3 of 3'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();
      expect(returned?.created, {'SN-009': 1.0, 'SN-010': 1.0, 'SN-011': 1.0});
      expect(returned?.existing, isEmpty);
    });

    testWidgets('generating more than the demand is refused', (tester) async {
      await open(
        tester,
        isSerial: true,
        demand: 2,
        lots: const [],
        canCreate: true,
        suggestedFirst: 'SN-001',
        generate: fakeGenerate,
      );
      await tester.enterText(find.byKey(const Key('lot-count')), '5');
      await tester.tap(find.byKey(const Key('lot-generate')));
      await tester.pumpAndSettle();
      expect(find.textContaining('more than the demand'), findsOneWidget);
      expect(find.text('Selected 0 of 2'), findsOneWidget);
    });

    testWidgets('a lot is typed with its quantity', (tester) async {
      await open(
        tester,
        isSerial: false,
        demand: 10,
        lots: const [],
        canCreate: true,
      );
      await tester.enterText(find.byKey(const Key('lot-name')), 'LOT-NEW');
      await tester.enterText(find.byKey(const Key('lot-new-qty')), '6');
      await tester.tap(find.byKey(const Key('lot-add')));
      await tester.pumpAndSettle();
      expect(find.text('LOT-NEW × 6'), findsOneWidget);
      expect(find.text('Selected 6 of 10'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();
      expect(returned?.created, {'LOT-NEW': 6.0});
    });

    testWidgets('new numbers and ticked stock add up to one selection', (
      tester,
    ) async {
      await open(
        tester,
        isSerial: true,
        demand: 2,
        lots: serials,
        canCreate: true,
        generate: fakeGenerate,
      );
      await tester.tap(find.text('S1'));
      await tester.enterText(find.byKey(const Key('lot-name')), 'NEW-1');
      await tester.tap(find.byKey(const Key('lot-add')));
      await tester.pumpAndSettle();
      expect(find.text('Selected 2 of 2'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();
      expect(returned?.existing, {1: 1.0});
      expect(returned?.created, {'NEW-1': 1.0});
    });

    testWidgets('an operation type that cannot create shows no creation form', (
      tester,
    ) async {
      await open(tester, isSerial: true, demand: 2, lots: serials);
      expect(find.byKey(const Key('lot-generate')), findsNothing);
      expect(find.byKey(const Key('lot-add')), findsNothing);
    });

    testWidgets('a type that only creates hides the stock list', (
      tester,
    ) async {
      await open(
        tester,
        isSerial: true,
        demand: 2,
        lots: serials,
        canCreate: true,
        canUseExisting: false,
      );
      expect(find.text('S1'), findsNothing);
      expect(find.byKey(const Key('lot-add')), findsOneWidget);
    });
  });
}
