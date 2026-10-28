import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobo_sales/models/quote.dart';
import 'package:mobo_sales/widgets/custom_snackbar.dart';
import 'package:mobo_sales/widgets/signature_widget.dart';

/// A signature is only drawn where Odoo would take one.
///
/// Odoo never captures this in the backend at all — its "Customer Signature"
/// page is developer-only and `invisible="1"` on 17, 18 and 19, and gone in
/// 20 — the customer signs on the portal, and only while
/// `_has_to_be_signed()` holds. The app asks the same question, so a
/// confirmed order shows what is on file and no pen. A tester found a live
/// capture pad on a confirmed Sales Order.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // The message would take itself away after three seconds.
  tearDown(CustomSnackbar.dismiss);

  // A 1x1 PNG, so a stored signature can be shown.
  const pixel =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

  Quote quote({String state = 'draft', bool signed = false}) => Quote(
    id: 7,
    name: 'S00007',
    lines: const [],
    subtotal: 0,
    taxAmount: 0,
    total: 0,
    status: state,
    extraData: signed
        ? {
            'signed_by': 'Ada',
            'signed_on': '2026-10-01 10:00:00',
            'signature': pixel,
          }
        : const {},
  );

  Future<void> pump(
    WidgetTester tester, {
    required bool canSign,
    Quote? order,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignatureWidget(
            canSign: canSign,
            quotation: order ?? quote(),
            onSignatureUpdated: (_) {},
            callKw: (_) async => true,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a signable quotation offers a pen', (tester) async {
    await pump(tester, canSign: true);

    expect(find.text('Sign'), findsOneWidget);
  });

  testWidgets('an order Odoo would refuse offers none', (tester) async {
    await pump(
      tester,
      canSign: false,
      order: quote(state: 'sale'),
    );

    expect(find.text('Sign'), findsNothing);
    expect(find.text('Sign again'), findsNothing);
    expect(
      find.text('Not signed yet'),
      findsOneWidget,
      reason: 'it still says where the signature would be',
    );
  });

  testWidgets('a signed order shows the signature, not a canvas', (
    tester,
  ) async {
    await pump(tester, canSign: false, order: quote(signed: true));

    expect(find.byType(Image), findsWidgets);
    expect(find.text('Sign'), findsNothing);
    expect(find.text('Not signed yet'), findsNothing);
  });

  testWidgets('re-signing is offered only while Odoo allows it', (
    tester,
  ) async {
    // `canSign` is false for an order that already has a signature, so this
    // is the narrow case of a signature captured but not yet saved.
    await pump(tester, canSign: true, order: quote(signed: true));

    expect(find.text('Sign again'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
  });

  /// The Save button's fill, which says whether it can be pressed.
  Color? saveColour(WidgetTester tester) {
    final button = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Save Signature'),
        matching: find.byType(ElevatedButton),
      ),
    );
    return button.style?.backgroundColor?.resolve(<WidgetState>{});
  }

  testWidgets('Save is greyed until there is something to save', (
    tester,
  ) async {
    // A tester saw a full-strength Save button on an order that could not be
    // signed, and on one with nothing captured yet.
    await pump(tester, canSign: true);
    final blocked = saveColour(tester);

    await pump(tester, canSign: false, order: quote(signed: true));
    expect(saveColour(tester), blocked, reason: 'both read as off');

    expect(blocked, isNot(const Color(0xFFC03355)));
  });

  testWidgets('tapping a blocked Save says why', (tester) async {
    await pump(tester, canSign: false, order: quote(signed: true));

    await tester.tap(find.text('Save Signature'));
    await tester.pump();

    expect(find.textContaining('already signed'), findsOneWidget);
    CustomSnackbar.dismiss();
    await tester.pump();
  });

  testWidgets('nothing captured yet says that instead', (tester) async {
    await pump(tester, canSign: true);

    await tester.tap(find.text('Save Signature'));
    await tester.pump();

    expect(find.textContaining('Tap Sign'), findsOneWidget);
    CustomSnackbar.dismiss();
    await tester.pump();
  });

  testWidgets('nothing draws inline any more', (tester) async {
    // The canvas moved into a dialog: inline it got whatever height the tab
    // strip had left, and the export crops to the ink, so a stroke squeezed
    // into that space came back cropped and stretched.
    await pump(tester, canSign: true);

    expect(find.text('Capture'), findsNothing);
    expect(find.text('Upload'), findsNothing);
  });
}
