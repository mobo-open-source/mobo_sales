import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/sales_access.dart';
import 'package:mobo_sales/widgets/access_denied_dialog.dart';

void main() {
  late BuildContext host;

  Future<void> pumpHost(
    WidgetTester tester, {
    ThemeData? theme,
    Size? size,
  }) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? ThemeData.light(),
        home: Builder(
          builder: (context) {
            host = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
  }

  testWidgets('no Sales access: Access Denied, with the paragraph and button', (
    tester,
  ) async {
    await pumpHost(tester);
    AccessDeniedDialog.showFor(host, const SalesAccessException.denied());
    await tester.pumpAndSettle();

    expect(find.text('Access Denied'), findsOneWidget);
    expect(
      find.textContaining("doesn't have access to the Sales app"),
      findsOneWidget,
    );
    expect(find.textContaining('contact your administrator'), findsOneWidget);
    expect(find.text('Back to Login'), findsOneWidget);
  });

  testWidgets('no Sales module: Module Missing, naming the module', (
    tester,
  ) async {
    await pumpHost(tester);
    AccessDeniedDialog.showFor(
      host,
      const SalesAccessException.moduleMissing(),
    );
    await tester.pumpAndSettle();

    expect(find.text('Module Missing'), findsOneWidget);
    expect(
      find.textContaining('The required "Sales" module is not installed'),
      findsOneWidget,
    );
    expect(find.text('Back to Login'), findsOneWidget);
  });

  testWidgets('a portal user: Portal Access Not Allowed', (tester) async {
    await pumpHost(tester);
    AccessDeniedDialog.showFor(host, const SalesAccessException.portalUser());
    await tester.pumpAndSettle();

    expect(find.text('Portal Access Not Allowed'), findsOneWidget);
    expect(find.textContaining('portal user'), findsOneWidget);
    expect(find.textContaining('internal user account'), findsOneWidget);
    expect(find.text('Back to Login'), findsOneWidget);
  });

  testWidgets('an access check that could not be made says to try again', (
    tester,
  ) async {
    await pumpHost(tester);
    AccessDeniedDialog.showFor(host, const SalesAccessException.unverified());
    await tester.pumpAndSettle();

    expect(find.text('Unable to Verify Access'), findsOneWidget);
    expect(find.textContaining('try again'), findsOneWidget);
  });

  testWidgets(
    'the layout: red ⓘ and the title on one line, button full width',
    (tester) async {
      await pumpHost(tester, size: const Size(411, 800));
      AccessDeniedDialog.showFor(
        host,
        const SalesAccessException.moduleMissing(),
      );
      await tester.pumpAndSettle();

      final icon = find.byIcon(Icons.error_outline);
      expect(icon, findsOneWidget);
      // Icon and title share a row: same vertical centre, icon first.
      expect(
        (tester.getCenter(icon).dy -
                tester.getCenter(find.text('Module Missing')).dy)
            .abs(),
        lessThan(4),
      );
      expect(
        tester.getCenter(icon).dx,
        lessThan(tester.getCenter(find.text('Module Missing')).dx),
      );

      // The card, then the paragraph left-aligned under the title row, and a
      // button that spans the card between its paddings.
      final card = tester.getRect(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(card.width, 411 - 56, reason: '28 of margin each side on a phone');
      final button = tester.getRect(find.byType(ElevatedButton));
      expect(button.width, closeTo(card.width - 48, 1), reason: 'full width');
      expect(button.height, 52);
      expect(
        tester.widget<Text>(find.text('Module Missing')).style!.fontWeight,
        FontWeight.w600,
      );
      expect(
        tester
            .getTopLeft(find.textContaining('The required "Sales" module'))
            .dx,
        closeTo(card.left + 24, 1),
        reason: 'paragraph starts at the card padding',
      );
    },
  );

  testWidgets('on a tablet the card keeps a phone\'s width', (tester) async {
    await pumpHost(tester, size: const Size(1000, 800));
    AccessDeniedDialog.showFor(host, const SalesAccessException.denied());
    await tester.pumpAndSettle();
    final card = tester.getRect(
      find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first,
    );
    expect(card.width, lessThanOrEqualTo(440));
  });

  testWidgets('the button reads OK where the user is already inside the app', (
    tester,
  ) async {
    await pumpHost(tester);
    AccessDeniedDialog.showFor(
      host,
      const SalesAccessException.denied(),
      buttonLabel: 'OK',
    );
    await tester.pumpAndSettle();
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Back to Login'), findsNothing);
  });

  testWidgets('the button closes it and hands control back', (tester) async {
    await pumpHost(tester);
    var closed = false;
    AccessDeniedDialog.showFor(
      host,
      const SalesAccessException.denied(),
    ).then((_) => closed = true);
    await tester.pumpAndSettle();
    expect(closed, isFalse);

    await tester.tap(find.text('Back to Login'));
    await tester.pumpAndSettle();
    expect(find.byType(AccessDeniedDialog), findsNothing);
    expect(closed, isTrue);
  });

  testWidgets('it cannot be dismissed by tapping outside or going back', (
    tester,
  ) async {
    await pumpHost(tester);
    AccessDeniedDialog.showFor(host, const SalesAccessException.denied());
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byType(AccessDeniedDialog), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AccessDeniedDialog), findsOneWidget);
  });

  testWidgets('showIfAccessError only takes the access errors', (tester) async {
    await pumpHost(tester);

    expect(
      await AccessDeniedDialog.showIfAccessError(host, Exception('timeout')),
      isFalse,
    );
    await tester.pump();
    expect(find.byType(AccessDeniedDialog), findsNothing);

    final taken = AccessDeniedDialog.showIfAccessError(
      host,
      const SalesAccessException.portalUser(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AccessDeniedDialog), findsOneWidget);
    await tester.tap(find.text('Back to Login'));
    await tester.pumpAndSettle();
    expect(await taken, isTrue);
  });

  testWidgets('fits a small phone, light and dark, for every outcome', (
    tester,
  ) async {
    for (final theme in [ThemeData.light(), ThemeData.dark()]) {
      for (final error in const [
        SalesAccessException.denied(),
        SalesAccessException.moduleMissing(),
        SalesAccessException.portalUser(),
        SalesAccessException.unverified(),
      ]) {
        await pumpHost(tester, theme: theme, size: const Size(320, 480));
        AccessDeniedDialog.showFor(host, error);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${error.status}');
        await tester.tap(find.text('Back to Login'));
        await tester.pumpAndSettle();
      }
    }
  });
}
