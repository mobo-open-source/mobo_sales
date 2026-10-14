import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/providers/contact_provider.dart';
import 'package:mobo_sales/providers/currency_provider.dart';
import 'package:mobo_sales/providers/invoice_creation_provider.dart';
import 'package:mobo_sales/screens/invoices/create_invoice_screen.dart';
import 'package:mobo_sales/services/connectivity_service.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/services/session_service.dart';
import 'package:mobo_sales/widgets/custom_snackbar.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockContactProvider extends Mock implements ContactProvider {}

class _MockConnectivity extends Mock implements ConnectivityService {}

class _MockSession extends Mock implements SessionService {}

/// Editing an invoice that has a line with no product — a down payment — on a
/// server that cannot take `product_id: 0` (Odoo 20 answers `'int' object has
/// no attribute 'origin'`). Nothing sent to Odoo may carry such an id, and the
/// invoice's own due date, payment term and lines must come back as they were.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (call) async => ['wifi'],
        );
  });

  late HttpServer server;
  late List<Map<String, dynamic>> asked;

  Iterable<Map<String, dynamic>> calls(String model, String method) =>
      asked.where((c) => c['model'] == model && c['method'] == method);

  /// Every `invoice_line_ids` entry sent in a create (the tax calculation
  /// makes a temporary invoice) or a write.
  Iterable<Map<String, dynamic>> sentLines() sync* {
    for (final call in [
      ...calls('account.move', 'create'),
      ...calls('account.move', 'write'),
    ]) {
      final args = call['args'] as List;
      final values =
          (call['method'] == 'create' ? args.first : args.last) as Map;
      for (final command in (values['invoice_line_ids'] as List? ?? const [])) {
        final vals = (command as List).last;
        if (vals is Map) yield Map<String, dynamic>.from(vals);
      }
    }
  }

  Future<void> startServer() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final params = Map<String, dynamic>.from(body['params'] as Map);
        asked.add(params);
        final model = params['model'];
        final method = params['method'];

        dynamic result = [];
        if (method == 'check_access_rights' || method == 'has_access') {
          result = true;
        } else if (method == 'search_count') {
          result = 0;
        } else if (model == 'res.partner') {
          result = [
            {'id': 7, 'name': 'Azure Interior'},
          ];
        } else if (model == 'account.move.line' && method == 'read') {
          result = [
            {
              'id': 210,
              'product_id': false,
              'name': 'Down payment of 44.0%',
              'quantity': 2.0,
              'price_unit': 379.5,
              'price_subtotal': 759.0,
              'product_uom_id': false,
              'tax_ids': <int>[],
              'discount': 0.0,
              'display_type': 'product',
            },
            {
              'id': 211,
              'product_id': [4, 'Desk'],
              'name': 'Desk\nWith three drawers',
              'quantity': 3.0,
              'price_unit': 50.0,
              'price_subtotal': 135.0,
              'product_uom_id': [1, 'Units'],
              'tax_ids': [2],
              'discount': 10.0,
              'display_type': 'product',
            },
          ];
        } else if (model == 'res.currency') {
          result = [
            {'id': 1},
          ];
        } else if (model == 'account.move' && method == 'create') {
          result = 99;
        } else if (model == 'account.move' && method == 'read') {
          result = [
            {'amount_untaxed': 894.0, 'amount_tax': 0.0, 'amount_total': 894.0},
          ];
        } else if (model == 'account.move') {
          result = true;
        } else if (model == 'account.payment.term') {
          result = [
            {'id': 3, 'name': '30 Days'},
          ];
        }
        request.response
          ..persistentConnection = false
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
          );
        await request.response.close();
      }),
    );
  }

  Future<void> settle(WidgetTester tester, [int rounds = 12]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Runs the real network and the screen until [done], or for a while.
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 80 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  late CreateInvoiceProvider provider;

  Future<void> openEdit(WidgetTester tester) async {
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      onError?.call(details);
    };
    addTearDown(() => FlutterError.onError = onError);

    asked = [];
    await tester.runAsync(startServer);
    addTearDown(() => tester.runAsync(() => server.close(force: true)));
    SharedPreferences.setMockInitialValues({
      'isLoggedIn': true,
      'sessionId': 'sess123',
      'userLogin': 'admin',
      'password': 'x',
      'database': 'shop',
      'serverUrl': 'http://127.0.0.1:${server.port}',
      'userId': 2,
      'userName': 'Admin',
      'serverVersion': '20.0',
      'expiresAt': DateTime.now()
          .add(const Duration(hours: 5))
          .toIso8601String(),
    });
    OdooSessionManager.clearClientCache();

    final currency = await tester.runAsync(() async => CurrencyProvider());
    addTearDown(() => currency!.dispose());
    provider = (await tester.runAsync(() async => CreateInvoiceProvider()))!;
    addTearDown(provider.dispose);

    final contacts = _MockContactProvider();
    when(() => contacts.contacts).thenReturn([]);
    when(() => contacts.isServerUnreachable).thenReturn(false);
    final connectivity = _MockConnectivity();
    when(() => connectivity.isConnected).thenReturn(true);
    final session = _MockSession();
    when(() => session.hasValidSession).thenReturn(true);

    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CreateInvoiceProvider>.value(value: provider),
          ChangeNotifierProvider<CurrencyProvider>.value(value: currency!),
          ChangeNotifierProvider<ContactProvider>.value(value: contacts),
          ChangeNotifierProvider<ConnectivityService>.value(
            value: connectivity,
          ),
          ChangeNotifierProvider<SessionService>.value(value: session),
        ],
        child: MaterialApp(
          home: CreateInvoiceScreen(
            invoiceToEdit: {
              'id': 73,
              'name': false,
              'state': 'draft',
              'partner_id': [7, 'Azure Interior'],
              'invoice_date': '2026-10-12',
              'invoice_date_due': '2026-12-01',
              'invoice_payment_term_id': [3, '30 Days'],
              // Odoo keeps the note as HTML.
              'narration': '<p>xcds</p>',
              'invoice_line_ids': [210, 211],
            },
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    // The product lists the screen asks for are on their way too.
    await settle(tester, 25);
    CustomSnackbar.dismiss();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('the invoice\'s own lines, due date and term come back as they '
      'were, and nothing is priced with product 0', (tester) async {
    await openEdit(tester);
    await until(tester, () => calls('account.move', 'unlink').isNotEmpty);

    final lines = provider.invoiceLines;
    expect(lines, hasLength(2));
    expect(lines[0]['product_name'], 'Down payment of 44.0%');
    expect(lines[0]['product_id'], isNull, reason: 'no product, not product 0');
    expect(lines[1]['product_id'], 4);
    expect(lines[1]['discount'], 10.0);
    expect(provider.dueDate, DateTime(2026, 12, 1));
    expect(provider.selectedPaymentTerm?.id, 3);
    // The form replaces its skeleton once the load has finished.
    await settle(tester, 6);
    // The note is shown as the text it is, not as Odoo's HTML.
    expect(find.text('xcds'), findsOneWidget);
    expect(find.textContaining('<p>'), findsNothing);

    // The tax calculation sends a temporary invoice: its lines must be valid.
    expect(calls('account.move', 'create'), isNotEmpty);
    for (final line in sentLines()) {
      expect(line['product_id'], anyOf(isNull, greaterThan(0)));
      expect(
        line.containsKey('product_uom_id') && line['product_uom_id'] == null,
        isFalse,
      );
    }
    final downPayment = sentLines().firstWhere(
      (l) => l['name'] == 'Down payment of 44.0%',
    );
    expect(downPayment.containsKey('product_id'), isFalse);
    await close(tester);
  });

  testWidgets('saving updates the lines where they are, keeps the due date and '
      'sends no product 0', (tester) async {
    await openEdit(tester);

    await until(tester, () => calls('account.move', 'unlink').isNotEmpty);
    // The form is "as loaded" once the load has finished and said so.
    await settle(tester, 6);
    provider.updateInvoiceLine(1, 4.0, 50.0);
    await until(tester, () => calls('account.move', 'unlink').length >= 2);
    bool updateEnabled() {
      final button = find.ancestor(
        of: find.text('Update Invoice'),
        matching: find.byWidgetPredicate((w) => w is ElevatedButton),
      );
      return button.evaluate().isNotEmpty &&
          tester.widget<ElevatedButton>(button).onPressed != null;
    }

    await until(tester, updateEnabled);
    expect(updateEnabled(), isTrue, reason: 'there is something to save');
    await tester.tap(find.text('Update Invoice'));
    await until(tester, () => calls('account.move', 'write').isNotEmpty);
    await settle(tester, 6);

    final writes = calls('account.move', 'write').toList();
    expect(writes, hasLength(1), reason: 'the invoice was written');
    final values = Map<String, dynamic>.from(
      (writes.single['args'] as List).last as Map,
    );
    expect(values['invoice_date_due'], '2026-12-01', reason: 'not +30 days');
    expect(values['invoice_payment_term_id'], 3);
    expect(
      values.containsKey('narration'),
      isFalse,
      reason: 'the note was not touched, so Odoo\'s own HTML is left alone',
    );

    final commands = (values['invoice_line_ids'] as List).cast<List>();
    expect(
      commands.map((c) => c[0]),
      [1, 1],
      reason: 'both lines updated in place, none deleted and recreated',
    );
    expect(commands.map((c) => c[1]), [210, 211]);
    final down = commands[0][2] as Map;
    expect(down.containsKey('product_id'), isFalse);
    expect(down['name'], 'Down payment of 44.0%');
    final desk = commands[1][2] as Map;
    expect(desk['product_id'], 4);
    expect(desk['quantity'], 4.0);
    expect(desk['discount'], 10.0);
    expect(desk['product_uom_id'], 1);
    for (final line in sentLines()) {
      expect(line['product_id'], anyOf(isNull, greaterThan(0)));
    }
    await close(tester);
  });

  testWidgets('a note that was edited is saved as HTML', (tester) async {
    await openEdit(tester);
    await until(tester, () => calls('account.move', 'unlink').isNotEmpty);
    await settle(tester, 6);

    await tester.enterText(find.text('xcds'), 'Pay by Friday\n\nThanks & bye');
    await settle(tester, 6);
    bool updateEnabled() {
      final button = find.ancestor(
        of: find.text('Update Invoice'),
        matching: find.byWidgetPredicate((w) => w is ElevatedButton),
      );
      return button.evaluate().isNotEmpty &&
          tester.widget<ElevatedButton>(button).onPressed != null;
    }

    await until(tester, updateEnabled);
    await tester.tap(find.text('Update Invoice'));
    await until(tester, () => calls('account.move', 'write').isNotEmpty);

    final values = Map<String, dynamic>.from(
      (calls('account.move', 'write').single['args'] as List).last as Map,
    );
    expect(values['narration'], '<p>Pay by Friday</p><p>Thanks &amp; bye</p>');
    await close(tester);
  });
}
