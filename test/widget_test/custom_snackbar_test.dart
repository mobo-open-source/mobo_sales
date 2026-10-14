import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/main.dart' show navigatorKey;
import 'package:mobo_sales/widgets/custom_snackbar.dart';

/// A widget test that always ends with the snackbar gone: its auto-dismiss
/// timer would otherwise still be pending when the framework checks.
void snackTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      CustomSnackbar.dismiss();
      await tester.pump();
    }
  });
}

void main() {
  Widget app({GlobalKey<NavigatorState>? key, required Widget home}) =>
      MaterialApp(navigatorKey: key, home: home);

  /// A page with a button; tapping it runs [onTap] with the page's context.
  Widget page(void Function(BuildContext) onTap, {String label = 'GO'}) =>
      Builder(
        builder: (context) => Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: ElevatedButton(
              onPressed: () => onTap(context),
              child: Text(label),
            ),
          ),
        ),
      );

  snackTest('shows the message and takes itself away after its time', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        key: navigatorKey,
        home: page(
          (c) => CustomSnackbar.show(
            context: c,
            title: 'Success',
            message: 'Quotation updated successfully',
            type: SnackbarType.success,
            duration: const Duration(seconds: 1),
          ),
        ),
      ),
    );
    await tester.tap(find.text('GO'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Success'), findsOneWidget);
    expect(find.text('Quotation updated successfully'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('Quotation updated successfully'), findsNothing);
  });

  snackTest('is not a route: the navigator stack does not change', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        key: navigatorKey,
        home: page((c) => CustomSnackbar.showSuccess(c, 'Saved')),
      ),
    );
    await tester.tap(find.text('GO'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Saved'), findsOneWidget);
    expect(navigatorKey.currentState!.canPop(), isFalse, reason: 'no route');
  });

  snackTest('a pop right after showing pops the PAGE, not the message', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        key: navigatorKey,
        home: page(
          (home) => Navigator.push(
            home,
            MaterialPageRoute(
              builder: (_) => page((c) {
                // Exactly the cancel / convert flow: message, then close.
                CustomSnackbar.showSuccess(c, 'Quotation cancelled');
                Navigator.of(c).pop(true);
              }, label: 'CANCEL'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();
    expect(find.text('CANCEL'), findsOneWidget);

    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    expect(find.text('CANCEL'), findsNothing, reason: 'the page closed');
    expect(find.text('GO'), findsOneWidget, reason: 'back on the first page');
    expect(
      find.text('Quotation cancelled'),
      findsOneWidget,
      reason: 'and the message is still up',
    );
  });

  snackTest('shows even when the screen that asked has been popped', (
    tester,
  ) async {
    late BuildContext poppedContext;
    await tester.pumpWidget(
      app(
        key: navigatorKey,
        home: page(
          (home) => Navigator.push(
            home,
            MaterialPageRoute(
              builder: (_) => page((c) {
                poppedContext = c;
                Navigator.of(c).pop();
              }, label: 'CLOSE'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
    expect(poppedContext.mounted, isFalse);

    CustomSnackbar.showSuccess(poppedContext, 'Deleted successfully');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Deleted successfully'), findsOneWidget);
  });

  snackTest('does not block the screen behind it', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      app(
        key: navigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                ElevatedButton(
                  onPressed: () {
                    taps++;
                    CustomSnackbar.showInfo(context, 'Tapped $taps');
                  },
                  child: const Text('TAP'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('TAP'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('TAP'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(taps, 2, reason: 'the second tap reached the button');
    expect(find.text('Tapped 2'), findsOneWidget);
    expect(
      find.text('Tapped 1'),
      findsNothing,
      reason: 'replaced, not stacked',
    );
  });

  snackTest('the ✕ and a swipe both dismiss it', (tester) async {
    await tester.pumpWidget(
      app(
        key: navigatorKey,
        home: page((c) => CustomSnackbar.showError(c, 'Something failed')),
      ),
    );
    await tester.tap(find.text('GO'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Something failed'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Something failed'), findsNothing);

    await tester.tap(find.text('GO'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(find.text('Something failed'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Something failed'), findsNothing);
  });

  snackTest('works without the app navigator key, from the screen overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(home: page((c) => CustomSnackbar.showWarning(c, 'Heads up'))),
    );
    await tester.tap(find.text('GO'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Heads up'), findsOneWidget);
  });

  snackTest('a long message scrolls inside the card, no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        key: navigatorKey,
        home: page(
          (c) => CustomSnackbar.showError(c, 'The server said no. ' * 60),
        ),
      ),
    );
    await tester.tap(find.text('GO'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
