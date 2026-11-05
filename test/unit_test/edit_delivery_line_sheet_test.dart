import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/widgets/edit_delivery_line_sheet.dart';

DeliveryLineEdit? returned;

Future<void> open(
  WidgetTester tester, {
  double demand = 10,
  double quantity = 0,
  bool canEditQuantity = true,
  bool canEditDemand = false,
}) async {
  returned = null;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              returned = await showEditDeliveryLineSheet(
                context,
                productName: 'Widget',
                unit: 'Units',
                demand: demand,
                quantity: quantity,
                canEditQuantity: canEditQuantity,
                canEditDemand: canEditDemand,
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

Finder save() => find.widgetWithText(ElevatedButton, 'Save');

void main() {
  testWidgets('Save is off until something changes', (tester) async {
    await open(tester);
    expect(tester.widget<ElevatedButton>(save()).onPressed, isNull);
  });

  testWidgets('typing a quantity on a line with none returns it', (
    tester,
  ) async {
    await open(tester, demand: 10, quantity: 0);
    await tester.enterText(find.byKey(const Key('line-quantity')), '4');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(save()).onPressed, isNotNull);

    await tester.tap(save());
    await tester.pumpAndSettle();
    expect(returned?.quantity, 4);
    expect(returned?.demand, isNull);
  });

  testWidgets('the stepper changes the quantity', (tester) async {
    await open(tester, demand: 10, quantity: 2);
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pump();
    await tester.tap(save());
    await tester.pumpAndSettle();
    expect(returned?.quantity, 3);
  });

  testWidgets('more than the demand is allowed but flagged', (tester) async {
    await open(tester, demand: 5, quantity: 0);
    await tester.enterText(find.byKey(const Key('line-quantity')), '8');
    await tester.pump();
    expect(find.text('More than the demand.'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(save()).onPressed, isNotNull);
  });

  testWidgets('a locked demand cannot be edited', (tester) async {
    await open(tester, canEditDemand: false);
    final demand = tester.widget<TextField>(
      find.byKey(const Key('line-demand')),
    );
    expect(demand.enabled, isFalse);
    expect(find.textContaining('The demand is locked'), findsOneWidget);
  });

  testWidgets('an unlocked demand is edited and returned', (tester) async {
    await open(tester, demand: 10, quantity: 0, canEditDemand: true);
    await tester.enterText(find.byKey(const Key('line-demand')), '6');
    await tester.pump();
    await tester.tap(save());
    await tester.pumpAndSettle();
    expect(returned?.demand, 6);
    expect(returned?.quantity, isNull);
  });

  testWidgets('a demand of zero is refused', (tester) async {
    await open(tester, canEditDemand: true);
    await tester.enterText(find.byKey(const Key('line-demand')), '0');
    await tester.pump();
    expect(find.text('The demand must be more than zero.'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(save()).onPressed, isNull);
  });

  testWidgets('a tracked product sets its quantity through its numbers', (
    tester,
  ) async {
    await open(tester, canEditQuantity: false);
    final quantity = tester.widget<TextField>(
      find.byKey(const Key('line-quantity')),
    );
    expect(quantity.enabled, isFalse);
    expect(
      find.textContaining('Set by the lot or serial numbers'),
      findsOneWidget,
    );
  });

  testWidgets('shows the product, its demand and Cancel / Save', (
    tester,
  ) async {
    await open(tester, demand: 10, quantity: 2);
    expect(find.text('Edit Line'), findsOneWidget);
    expect(find.text('Widget'), findsOneWidget);
    expect(find.text('Demand: 10 Units'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(returned, isNull);
  });

  testWidgets('fits a small phone with the keyboard up', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 480 * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.viewInsets = const FakeViewPadding(bottom: 250 * 3);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
    await open(tester, demand: 10, quantity: 2, canEditDemand: true);
    expect(tester.takeException(), isNull);
  });
}
