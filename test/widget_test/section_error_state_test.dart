import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/widgets/connection_status_widget.dart';
import 'package:mobo_sales/widgets/section_error_state.dart';

/// A quotation whose order lines never arrived said "No order lines found."
/// directly above its own total of $646.88. Failed and empty are different
/// facts.
Future<void> _pump(WidgetTester tester, String? error, VoidCallback onRetry) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SectionErrorState(error: error, onRetry: onRetry),
        ),
      ),
    );

void main() {
  testWidgets('a panel failure never reads as an empty panel', (tester) async {
    await _pump(tester, 'SocketException: Connection refused', () {});

    expect(find.text('No order lines found.'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('it borrows the full-screen wording', (tester) async {
    await _pump(tester, 'SocketException: Connection refused', () {});

    final generic = ConnectionStatusWidget.cantReachServer;
    expect(find.text(generic['title']!), findsOneWidget);
    expect(find.text(generic['message']!), findsOneWidget);
  });

  testWidgets('the raw exception is never on screen', (tester) async {
    await _pump(
      tester,
      'Exception: ClientException with SocketException: Connection refused '
      '(OS Error: Connection refused, errno = 111)',
      () {},
    );

    expect(find.textContaining('errno'), findsNothing);
    expect(find.textContaining('ClientException'), findsNothing);
  });

  testWidgets('a business error keeps its own words', (tester) async {
    await _pump(tester, 'You cannot modify a confirmed order.', () {});

    expect(find.text('You cannot modify a confirmed order.'), findsOneWidget);
  });

  testWidgets('Retry asks again', (tester) async {
    var retries = 0;
    await _pump(tester, 'SocketException: Connection refused', () => retries++);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(retries, 1);
  });
}
