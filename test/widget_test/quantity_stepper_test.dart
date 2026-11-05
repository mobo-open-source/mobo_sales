import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/widgets/quantity_stepper.dart';

/// The quantity box of an order line, at the width it has in a phone's row.
void main() {
  Future<List<double>> pump(
    WidgetTester tester,
    double initial, {
    double width = 150,
  }) async {
    final reported = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: QuantityStepper(
                initialValue: initial,
                onChanged: reported.add,
              ),
            ),
          ),
        ),
      ),
    );
    return reported;
  }

  String shown(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  double fontSize(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).style!.fontSize!;

  testWidgets('shows the quantity and steps by one', (tester) async {
    final reported = await pump(tester, 5);
    expect(shown(tester), '5');

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(shown(tester), '6');
    await tester.tap(find.byIcon(Icons.remove));
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(shown(tester), '4');
    expect(reported, [6, 5, 4]);
  });

  testWidgets('a large quantity is written out whole, at any step', (
    tester,
  ) async {
    await pump(tester, 1234567890);
    expect(shown(tester), '1234567890');

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(shown(tester), '1234567891');
    await tester.tap(find.byIcon(Icons.remove));
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(shown(tester), '1234567889');
  });

  testWidgets('an eight-digit quantity does not turn into 1e+7 or 1e7', (
    tester,
  ) async {
    await pump(tester, 10000000);
    expect(shown(tester), '10000000');
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(shown(tester), '9999999');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(shown(tester), '10000000');
  });

  testWidgets('a fraction steps without float noise', (tester) async {
    await pump(tester, 1.1);
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(shown(tester), '0.1');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(shown(tester), '1.1');
  });

  testWidgets('it stops at zero', (tester) async {
    final reported = await pump(tester, 1);
    await tester.tap(find.byIcon(Icons.remove));
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(shown(tester), '0');
    expect(reported.last, 0);
  });

  testWidgets('a large number shrinks to fit the narrow field', (tester) async {
    await pump(tester, 5);
    final normal = fontSize(tester);

    await tester.pumpWidget(const SizedBox());
    await pump(tester, 123456789012);
    await tester.pump();
    expect(fontSize(tester), lessThan(normal));
    expect(tester.takeException(), isNull, reason: 'no overflow');
  });

  testWidgets('typing is limited to a quantity', (tester) async {
    final reported = await pump(tester, 1);
    await tester.enterText(find.byType(TextField), '12ab.5');
    await tester.pump();
    expect(shown(tester), isNot(contains('a')));

    await tester.enterText(find.byType(TextField), '2,5');
    await tester.pump();
    expect(shown(tester), '2.5');
    expect(reported.last, 2.5);
  });

  testWidgets('a half-typed field keeps the last quantity', (tester) async {
    final reported = await pump(tester, 3);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(reported, isEmpty, reason: 'empty is not a quantity yet');

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(shown(tester), '1');
  });
}
