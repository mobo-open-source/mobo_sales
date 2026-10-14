import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobo_sales/models/quote.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/widgets/custom_snackbar.dart';
import 'package:mobo_sales/widgets/signature_widget.dart';

/// Signing a quotation changes it on the server: the lists and the pages open
/// behind this one have to hear of it, and only once the server has accepted it.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // A 1x1 PNG, so the stored signature can be shown.
  const pixel =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

  late List<DataChange> heard;
  late DataChangeSubscription subscription;
  late List<Map<String, dynamic>> writes;
  late List<Map<String, dynamic>> reported;

  Quote signedQuote() => Quote(
    id: 7,
    name: 'S00007',
    lines: const [],
    subtotal: 0,
    taxAmount: 0,
    total: 0,
    status: 'draft',
    extraData: {
      'signed_by': 'Ada',
      'signed_on': '2026-10-01 10:00:00',
      'signature': pixel,
    },
  );

  setUp(() {
    heard = [];
    writes = [];
    reported = [];
  });

  tearDown(() {
    subscription.cancel();
    CustomSnackbar.dismiss();
  });

  Future<void> pumpWidget(
    WidgetTester tester,
    Future<dynamic> Function(Map<String, dynamic>) callKw,
  ) async {
    // Listening happens inside the test, so the listener's timer runs on the
    // test's clock.
    subscription = DataChangeBus.instance.listen(
      debounce: Duration.zero,
      onChange: (burst) => heard.addAll(burst),
    );
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignatureWidget(
            quotation: signedQuote(),
            callKw: callKw,
            onSignatureUpdated: reported.add,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The message would take itself away after three seconds.
  Future<void> clearMessage(WidgetTester tester) async {
    CustomSnackbar.dismiss();
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save Signature'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('a saved signature announces the quotation', (tester) async {
    await pumpWidget(tester, (payload) async {
      writes.add(payload);
      return true;
    });

    await save(tester);

    expect(writes, hasLength(1));
    expect(writes.single['model'], 'sale.order');
    expect(writes.single['args'][0], [7]);
    // Odoo keeps the time in UTC, whatever zone this runs in.
    expect(writes.single['args'][1]['signed_on'], '2026-10-01 10:00:00');
    expect(writes.single['args'][1]['signed_by'], 'Ada');
    expect(reported, hasLength(1));
    expect(heard, hasLength(1));
    expect(heard.single.entity, DataEntity.quotation);
    expect(heard.single.kind, DataChangeKind.updated);
    expect(heard.single.id, 7);
    await clearMessage(tester);
  });

  testWidgets('a signature the server refuses announces nothing', (
    tester,
  ) async {
    await pumpWidget(tester, (payload) async {
      throw Exception('AccessError');
    });

    await save(tester);

    expect(reported, isEmpty);
    expect(heard, isEmpty);
    expect(
      find.text(
        "You don't have permission to do this. Please contact your administrator.",
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Exception'), findsNothing);
    await clearMessage(tester);
  });
}
