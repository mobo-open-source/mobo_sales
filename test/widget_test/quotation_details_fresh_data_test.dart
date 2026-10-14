import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/models/quote.dart';
import 'package:mobo_sales/providers/currency_provider.dart';
import 'package:mobo_sales/providers/last_opened_provider.dart';
import 'package:mobo_sales/providers/quotation_provider.dart';
import 'package:mobo_sales/screens/quotations/quotation_details_screen.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/widgets/custom_snackbar.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks/mock_services.dart';

/// The quotation's page and the list behind it show what the database holds:
/// the page when it opens (whatever copy it was handed), after an action on it
/// and after a change made elsewhere; the list under its filter.
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
  late QuotationProvider provider;
  late Map<int, Map<String, dynamic>> orders;
  late List<String> asked;

  /// When set, confirming the order fails with this server message.
  String? confirmError;

  /// What the server says about the order's signature: whether it has the
  /// fields at all, whether a signature is required, and what is on file.
  late bool serverHasSignatureFields;
  late bool requireSignature;
  String? signedBy;

  Map<String, dynamic> row(int id, String state, double total) => {
    'id': id,
    'name': 'S0000$id',
    'partner_id': [7, 'Azure Interior'],
    'date_order': '2026-10-01 10:00:00',
    'validity_date': '2099-12-31',
    'state': state,
    'amount_total': total,
    'amount_untaxed': total,
    'amount_tax': 0.0,
    'currency_id': [1, 'USD'],
    'order_line': <int>[],
    'invoice_status': 'no',
    'delivery_status': 'pending',
  };

  /// The orders a domain keeps; only its `state` leaves are honoured.
  List<Map<String, dynamic>> matching(List domain) {
    final states = <List>[
      for (final leaf in domain)
        if (leaf is List && leaf.length == 3 && leaf[0] == 'state')
          leaf[2] is List ? leaf[2] as List : [leaf[2]],
    ];
    return [
      for (final order in orders.values)
        if (states.every((allowed) => allowed.contains(order['state']))) order,
    ];
  }

  Future<void> startServer() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final params = (body['params'] as Map?) ?? {};
        final model = params['model'];
        final method = params['method'];
        asked.add('$model.$method');

        dynamic result = [];
        Map<String, dynamic>? serverError;
        if (method == 'check_access_rights' || method == 'has_access') {
          result = true;
        } else if (model == 'sale.order') {
          switch (method) {
            case 'search_count':
              result = matching(params['args'][0] as List).length;
            case 'search_read':
              result = matching(params['args'][0] as List);
            case 'read':
              final ids = (params['args'][0] as List).cast<int>();
              final fields = (params['kwargs']?['fields'] as List?) ?? const [];
              final signatureAsked = fields.where(
                (f) => const [
                  'require_signature',
                  'signed_by',
                  'signed_on',
                  'signature',
                ].contains(f),
              );
              if (signatureAsked.isNotEmpty && !serverHasSignatureFields) {
                serverError = {
                  'code': 200,
                  'message': 'Odoo Server Error',
                  'data': {
                    'name': 'builtins.ValueError',
                    'message':
                        "Invalid field '${signatureAsked.first}' on model "
                        "'sale.order'",
                  },
                };
              } else {
                result = [
                  for (final id in ids)
                    if (orders[id] != null)
                      {
                        ...orders[id]!,
                        if (signatureAsked.isNotEmpty) ...{
                          'require_signature': requireSignature,
                          'signed_by': signedBy ?? false,
                          'signed_on': signedBy == null
                              ? false
                              : '2026-10-01 10:00:00',
                          'signature': false,
                        },
                      },
                ];
              }
            case 'action_confirm' when confirmError != null:
              serverError = {
                'code': 200,
                'message': 'Odoo Server Error',
                'data': {
                  'name': 'odoo.exceptions.RedirectWarning',
                  'message': confirmError,
                },
              };
            case 'action_confirm':
              orders[(params['args'][0] as List).first as int]!['state'] =
                  'sale';
              result = true;
            case 'action_cancel':
              orders[(params['args'][0] as List).first as int]!['state'] =
                  'cancel';
              result = true;
          }
        } else if (model == 'res.partner') {
          result = [
            {'id': 7, 'name': 'Azure Interior'},
          ];
        }
        request.response
          ..persistentConnection = false
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              if (serverError != null)
                'error': serverError
              else
                'result': result,
            }),
          );
        await request.response.close();
      }),
    );
  }

  /// Lets the real network and the screen run.
  Future<void> settle(WidgetTester tester, [int rounds = 10]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Runs the real network and the screen until [done], or for a while.
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 60 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Opens the page's menu and picks [item].
  Future<void> pickFromMenu(WidgetTester tester, String item) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text(item));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> open(
    WidgetTester tester, {
    required String stateInTheListsCopy,
  }) async {
    // The test font is wider than the real one, so the menu rows overflow
    // here; that is about the font, not about what these tests check.
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      onError?.call(details);
    };
    addTearDown(() => FlutterError.onError = onError);

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
      'serverVersion': '18.0',
      'expiresAt': DateTime.now()
          .add(const Duration(hours: 5))
          .toIso8601String(),
    });
    OdooSessionManager.clearClientCache();

    final connectivity = MockConnectivityService();
    when(() => connectivity.isConnected).thenReturn(true);
    provider = QuotationProvider(
      quotationService: MockQuotationService(),
      connectivityService: connectivity,
    );
    addTearDown(provider.dispose);
    await tester.runAsync(
      () => provider.loadQuotations(filters: {'quotation'}),
    );

    // Made outside the test's fake clock: it asks the server for the currency
    // as soon as it exists, and that request must run on the real one.
    final currency = await tester.runAsync(() async => CurrencyProvider());
    addTearDown(() => currency!.dispose());

    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<QuotationProvider>.value(value: provider),
          ChangeNotifierProvider<CurrencyProvider>.value(value: currency!),
          ChangeNotifierProvider<LastOpenedProvider>(
            create: (_) => LastOpenedProvider(),
          ),
        ],
        child: MaterialApp(
          home: QuotationDetailScreen(
            quotation: Quote.fromJson(row(1, stateInTheListsCopy, 100)),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Finder titleIs(String title) =>
      find.descendant(of: find.byType(AppBar), matching: find.text(title));

  setUp(() {
    confirmError = null;
    serverHasSignatureFields = true;
    requireSignature = true;
    signedBy = null;
    orders = {1: row(1, 'draft', 100), 2: row(2, 'sent', 200)};
    asked = [];
  });

  /// Ends every test by taking the screen down and letting its timers run out.
  Future<void> close(WidgetTester tester) async {
    // Let what is still on its way finish before the screen goes.
    await settle(tester, 15);
    CustomSnackbar.dismiss();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('opened with an old copy, it shows what the database holds', (
    tester,
  ) async {
    // The list (or a dashboard card) last saw it as a quotation; meanwhile it
    // was confirmed somewhere else.
    orders[1]!['state'] = 'sale';
    await open(tester, stateInTheListsCopy: 'draft');

    expect(titleIs('Sale Order'), findsOneWidget);
    expect(titleIs('Quotation'), findsNothing);
    expect(asked, contains('sale.order.read'), reason: 'it read the order');
    await close(tester);
  });

  testWidgets('a change made elsewhere shows without a pull-down', (
    tester,
  ) async {
    await open(tester, stateInTheListsCopy: 'draft');
    expect(titleIs('Quotation'), findsOneWidget);

    orders[1]!['state'] = 'sale';
    DataChangeBus.instance.quotationChanged(1);
    await until(tester, () => titleIs('Sale Order').evaluate().isNotEmpty);

    expect(titleIs('Sale Order'), findsOneWidget);
    await close(tester);
  });

  testWidgets('converting to a sale order updates the page and takes the '
      'order out of a list filtered to quotations', (tester) async {
    await open(tester, stateInTheListsCopy: 'draft');
    expect(provider.allQuotations.map((q) => q.id), [1, 2]);
    expect(provider.totalQuotations, 2);
    expect(titleIs('Quotation'), findsOneWidget);

    await pickFromMenu(tester, 'Convert to Sale Order');
    await tester.tap(find.text('Convert'));
    await until(
      tester,
      () =>
          titleIs('Sale Order').evaluate().isNotEmpty &&
          provider.totalQuotations == 1,
    );

    expect(titleIs('Sale Order'), findsOneWidget, reason: 'the page');
    expect(provider.allQuotations.map((q) => q.id), [
      2,
    ], reason: 'the list, under its filter');
    expect(provider.totalQuotations, 1, reason: 'the count');
    await close(tester);
  });

  testWidgets('cancelling updates the list under its filter too', (
    tester,
  ) async {
    await open(tester, stateInTheListsCopy: 'draft');

    await pickFromMenu(tester, 'Cancel Quotation');
    // The dialog's buttons are "Back" and "Cancel".
    await tester.tap(find.text('Cancel').last);
    await until(tester, () => provider.totalQuotations == 1);

    expect(orders[1]!['state'], 'cancel');
    expect(provider.allQuotations.map((q) => q.id), [2]);
    expect(provider.totalQuotations, 1);
    await close(tester);
  });

  testWidgets('a failed conversion shows only its reason, in a snackbar', (
    tester,
  ) async {
    // Odoo's "go to Warehouses" warning, as it reached the old dialog: the
    // message, then the action id, the button label and a context.
    confirmError =
        'Please create a warehouse for company My US Company.\n'
        '257\nGo to Warehouses\nNone';
    await open(tester, stateInTheListsCopy: 'draft');

    await pickFromMenu(tester, 'Convert to Sale Order');
    await tester.tap(find.text('Convert'));
    await until(
      tester,
      () => find
          .text('Please create a warehouse for company My US Company.')
          .evaluate()
          .isNotEmpty,
    );

    expect(
      find.text('Please create a warehouse for company My US Company.'),
      findsOneWidget,
    );
    expect(find.text('Error'), findsOneWidget, reason: 'the snackbar\'s title');
    expect(find.byType(AlertDialog), findsNothing, reason: 'no dialog');
    expect(find.text('Conversion Failed'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('Go to Warehouses'), findsNothing);
    expect(orders[1]!['state'], 'draft');
    await close(tester);
  });

  group('the Signature tab', () {
    testWidgets('is there when the order asks for a signature', (tester) async {
      requireSignature = true;
      await open(tester, stateInTheListsCopy: 'draft');

      expect(find.text('Signature'), findsOneWidget);
      expect(find.text('Other Info'), findsOneWidget);
      await close(tester);
    });

    testWidgets('is there when the order is already signed, whatever it asks', (
      tester,
    ) async {
      requireSignature = false;
      signedBy = 'Abigail Peterson';
      await open(tester, stateInTheListsCopy: 'draft');

      expect(find.text('Signature'), findsOneWidget);
      await close(tester);
    });

    testWidgets('is not there when the order neither needs nor has one', (
      tester,
    ) async {
      requireSignature = false;
      await open(tester, stateInTheListsCopy: 'draft');

      expect(find.text('Signature'), findsNothing);
      expect(find.text('Quote Builder'), findsOneWidget);
      expect(find.text('Other Info'), findsOneWidget);
      await close(tester);
    });

    testWidgets('is not there on a server without the signature fields', (
      tester,
    ) async {
      serverHasSignatureFields = false;
      await open(tester, stateInTheListsCopy: 'draft');
      // The read drops the fields the server refuses, one at a time.
      await until(tester, () => find.text('Other Info').evaluate().isNotEmpty);
      await settle(tester, 5);

      expect(find.text('Signature'), findsNothing);
      expect(find.text('Other Info'), findsOneWidget);
      await close(tester);
    });

    testWidgets('appears when a change elsewhere turns the requirement on, '
        'and goes when it is turned off', (tester) async {
      requireSignature = false;
      await open(tester, stateInTheListsCopy: 'draft');
      expect(find.text('Signature'), findsNothing);

      requireSignature = true;
      DataChangeBus.instance.quotationChanged(1);
      await until(tester, () => find.text('Signature').evaluate().isNotEmpty);
      expect(find.text('Signature'), findsOneWidget);

      requireSignature = false;
      DataChangeBus.instance.quotationChanged(1);
      await until(tester, () => find.text('Signature').evaluate().isEmpty);
      expect(find.text('Signature'), findsNothing);
      await close(tester);
    });

    testWidgets('can be opened and shows who signed', (tester) async {
      requireSignature = true;
      signedBy = 'Abigail Peterson';
      await open(tester, stateInTheListsCopy: 'draft');

      // The tab row scrolls sideways and the test font is wide.
      await tester.ensureVisible(find.text('Signature'));
      await tester.pump();
      await tester.tap(find.text('Signature'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Signed By'), findsOneWidget);
      expect(find.text('Abigail Peterson'), findsOneWidget);
      await close(tester);
    });
  });

  group('the status capsule and the menu', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('a cancelled quotation says Cancelled, and cannot be cancelled '
        'again', (tester) async {
      orders[1]!['state'] = 'cancel';
      await open(tester, stateInTheListsCopy: 'draft');

      expect(find.text('Cancelled'), findsOneWidget, reason: 'the capsule');
      expect(titleIs('Quotation'), findsOneWidget, reason: 'the title');

      await openMenu(tester);
      expect(find.text('Cancel Quotation'), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Convert to Sale Order'), findsNothing);
      await close(tester);
    });

    testWidgets(
      'a sent quotation says Sent and can be cancelled or confirmed',
      (tester) async {
        orders[1]!['state'] = 'sent';
        await open(tester, stateInTheListsCopy: 'draft');

        expect(find.text('Sent'), findsOneWidget);
        await openMenu(tester);
        expect(find.text('Cancel Quotation'), findsOneWidget);
        expect(find.text('Convert to Sale Order'), findsOneWidget);
        await close(tester);
      },
    );

    testWidgets('a quotation says Quotation, a confirmed order Sale Order', (
      tester,
    ) async {
      await open(tester, stateInTheListsCopy: 'draft');
      // The title and the capsule.
      expect(find.text('Quotation'), findsNWidgets(2));

      orders[1]!['state'] = 'sale';
      DataChangeBus.instance.quotationChanged(1);
      await until(tester, () => find.text('Sale Order').evaluate().length == 2);
      expect(find.text('Sale Order'), findsNWidgets(2));
      expect(find.text('Quotation'), findsNothing);
      await close(tester);
    });
  });

  group('the edit button', () {
    Finder editButton() => find.byTooltip('Edit Quotation');

    testWidgets('is there for a quotation, draft or sent', (tester) async {
      await open(tester, stateInTheListsCopy: 'draft');
      expect(editButton(), findsOneWidget);
      await close(tester);
    });

    testWidgets('is there for a sent quotation', (tester) async {
      orders[1]!['state'] = 'sent';
      await open(tester, stateInTheListsCopy: 'draft');
      expect(editButton(), findsOneWidget);
      await close(tester);
    });

    testWidgets('is not there for a confirmed sale order', (tester) async {
      orders[1]!['state'] = 'sale';
      await open(tester, stateInTheListsCopy: 'draft');
      expect(titleIs('Sale Order'), findsOneWidget);
      expect(editButton(), findsNothing);
      await close(tester);
    });

    testWidgets('is not there for a cancelled one', (tester) async {
      orders[1]!['state'] = 'cancel';
      await open(tester, stateInTheListsCopy: 'draft');
      expect(editButton(), findsNothing);
      await close(tester);
    });

    testWidgets('goes when the quotation is confirmed', (tester) async {
      await open(tester, stateInTheListsCopy: 'draft');
      expect(editButton(), findsOneWidget);

      orders[1]!['state'] = 'sale';
      DataChangeBus.instance.quotationChanged(1);
      await until(tester, () => editButton().evaluate().isEmpty);
      expect(editButton(), findsNothing);
      await close(tester);
    });
  });
}
