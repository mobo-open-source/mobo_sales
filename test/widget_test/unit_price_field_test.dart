import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/providers/currency_provider.dart';
import 'package:mobo_sales/widgets/unit_price_field.dart';
import 'package:provider/provider.dart';

/// The unit price box of a line, at the width it has in a phone's row.
void main() {
  late CurrencyProvider currency;

  setUp(() => currency = CurrencyProvider());

  Future<List<double>> pump(
    WidgetTester tester,
    double initial, {
    double width = 150,
  }) async {
    final reported = <double>[];
    await tester.pumpWidget(
      ChangeNotifierProvider<CurrencyProvider>.value(
        value: currency,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: UnitPriceField(
                  initialValue: initial,
                  onChanged: reported.add,
                  currencyLabel: (c) => 'USD',
                ),
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

  testWidgets('shows the price with two decimals', (tester) async {
    await pump(tester, 12.5);
    expect(shown(tester), '12.50');
  });

  testWidgets('a large price is shown whole, not in exponent form', (
    tester,
  ) async {
    await pump(tester, 1234567890);
    expect(shown(tester), '1234567890.00');

    await tester.pumpWidget(const SizedBox());
    await pump(tester, 1e22);
    expect(shown(tester), '10000000000000000000000.00');
  });

  testWidgets('a large price shrinks to fit and does not overflow', (
    tester,
  ) async {
    await pump(tester, 5);
    final normal = fontSize(tester);

    await tester.pumpWidget(const SizedBox());
    await pump(tester, 999999999999.99);
    expect(fontSize(tester), lessThan(normal));
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing a large amount reports it exactly', (tester) async {
    final reported = await pump(tester, 1);
    await tester.enterText(find.byType(TextField), '123456789012.5');
    await tester.pump();

    expect(reported.last, 123456789012.5);
    expect(shown(tester), '123456789012.5');
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing is limited to a price', (tester) async {
    final reported = await pump(tester, 1);
    await tester.enterText(find.byType(TextField), '5');
    await tester.enterText(find.byType(TextField), '5x');
    await tester.pump();
    expect(shown(tester), '5');

    await tester.enterText(find.byType(TextField), '1,234');
    await tester.pump();
    expect(shown(tester), '1.234');
    expect(reported.last, 1.234);

    await tester.enterText(find.byType(TextField), '1234567890123');
    await tester.pump();
    expect(shown(tester), '1.234', reason: 'past twelve whole digits');
  });

  testWidgets('an emptied field is a price of nothing', (tester) async {
    final reported = await pump(tester, 7);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(reported.last, 0);
  });

  testWidgets('focusing the field does not report a price', (tester) async {
    final reported = await pump(tester, 7);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(reported, isEmpty);
  });
}
