import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobo_sales/models/contact.dart';
import 'package:mobo_sales/providers/last_opened_provider.dart';
import 'package:mobo_sales/screens/customers/edit_customer_screen.dart';
import 'package:mobo_sales/services/connectivity_service.dart';
import 'package:mobo_sales/services/customer_service.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/services/permission_service.dart';
import 'package:mobo_sales/services/session_service.dart';
import 'package:mobo_sales/widgets/custom_snackbar.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks/mock_services.dart';

/// Saving an edited customer tells the user, takes them back to the page they
/// came from with the saved customer, and announces the change on the bus.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late MockConnectivityService connectivity;
  late MockSessionService session;
  late MockPermissionService permissions;
  late PermissionService savedPermissions;
  late CustomerService savedService;
  late List<Map<String, dynamic>> writes;
  late List<DataChange> heard;
  DataChangeSubscription? subscription;
  late DataChangeBus bus;
  late bool serverAccepts;

  /// When set, the server refuses the write with this message.
  String? serverRefusal;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    writes = [];
    heard = [];
    serverAccepts = true;
    serverRefusal = null;
    bus = DataChangeBus.forTesting();

    savedPermissions = PermissionService.instance;
    permissions = MockPermissionService();
    when(() => permissions.canWrite(any())).thenAnswer((_) async => true);
    when(() => permissions.canCreate(any())).thenAnswer((_) async => true);
    when(() => permissions.canRead(any())).thenAnswer((_) async => true);
    PermissionService.instance = permissions;

    savedService = CustomerService.instance;
    CustomerService.instance = CustomerService.forTesting(
      bus: bus,
      callKw: (payload) async {
        final method = payload['method'];
        if (method == 'write') {
          writes.add(payload);
          if (serverRefusal != null) throw Exception(serverRefusal);
          return serverAccepts;
        }
        if (method == 'read') {
          return [
            {'id': 1, 'name': 'Ada King', 'email': 'ada@example.com'},
          ];
        }
        if (method == 'fields_get') {
          return {
            'name': {'type': 'char', 'readonly': false},
            'email': {'type': 'char', 'readonly': false},
            'active': {'type': 'boolean', 'readonly': false},
            'customer_rank': {'type': 'integer', 'readonly': false},
            'is_company': {'type': 'boolean', 'readonly': false},
          };
        }
        return <dynamic>[];
      },
    );

    connectivity = MockConnectivityService();
    when(() => connectivity.isConnected).thenReturn(true);
    when(() => connectivity.isInitialized).thenReturn(true);
    session = MockSessionService();
    when(() => session.hasValidSession).thenReturn(true);
    when(() => session.isInitialized).thenReturn(true);
    when(() => session.isCheckingSession).thenReturn(false);
    when(() => session.isServerUnreachable).thenReturn(false);
  });

  tearDown(() {
    subscription?.cancel();
    PermissionService.instance = savedPermissions;
    CustomerService.instance = savedService;
  });

  /// A page that opens the edit form and shows what it hands back.
  Widget app(ValueNotifier<Object?> result) => MultiProvider(
    providers: [
      ChangeNotifierProvider<SessionService>.value(value: session),
      ChangeNotifierProvider<ConnectivityService>.value(value: connectivity),
      ChangeNotifierProvider<LastOpenedProvider>(
        create: (_) => LastOpenedProvider(),
      ),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result.value = await Navigator.push<Object?>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditCustomerScreen(
                      callKw: (payload) async =>
                          payload['model'] == 'res.country'
                          ? [
                              {'id': 1, 'name': 'France', 'code': 'FR'},
                            ]
                          : <dynamic>[],
                      contact: Contact(
                        id: 1,
                        name: 'Ada Lovelace',
                        email: 'ada@example.com',
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Open the form'),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> pumpFor(WidgetTester tester, Duration total) async {
    var elapsed = Duration.zero;
    while (elapsed < total) {
      // Real time passes too: the session lookups go through platform channels.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      elapsed += const Duration(milliseconds: 50);
    }
  }

  testWidgets('a saved edit says so, goes back, and is announced', (
    tester,
  ) async {
    final result = ValueNotifier<Object?>(null);
    // Listening happens inside the test, so the listener's timer runs on the
    // test's clock.
    subscription = bus.listen(
      debounce: Duration.zero,
      onChange: (burst) => heard.addAll(burst),
    );

    Future<void> scenario() async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(result));
      await tester.tap(find.text('Open the form'));
      await pumpFor(tester, const Duration(seconds: 2));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ada Lovelace'),
        'Ada King',
      );
      await tester.pump();
      // The option lists cannot load in a test, and the warning that says so
      // sits over the button: clear it so the save can be tapped.
      CustomSnackbar.dismiss();
      await tester.pump();
      await tester.tap(find.text('Save Changes'));
      await pumpFor(tester, const Duration(seconds: 2));
    }

    // The form asks Google Fonts for its typeface; a test has no network, and
    // the failed fetch surfaces as an error of its own. Those are set aside;
    // any other error still fails the test.
    final otherErrors = <Object>[];
    await runZonedGuarded(scenario, (error, stack) {
      final text = error.toString();
      if (!text.contains('google_fonts') && !text.contains('GoogleFonts')) {
        otherErrors.add(error);
      }
    });
    expect(otherErrors, isEmpty);

    expect(writes, hasLength(1));
    // The form is gone: the page that opened it is showing again...
    expect(find.text('Open the form'), findsOneWidget);
    expect(find.text('Save Changes'), findsNothing);
    // ...with the saved customer handed back,
    expect(result.value, isA<Contact>());
    expect((result.value as Contact).name, 'Ada King');
    // ...and the confirmation on screen, where the pop did not take it away.
    expect(find.text('Customer updated successfully'), findsOneWidget);
    // The change was announced for every other screen.
    expect(heard.map((c) => (c.entity, c.kind, c.id)), [
      (DataEntity.customer, DataChangeKind.updated, 1),
    ]);

    // The message would take itself away after three seconds.
    CustomSnackbar.dismiss();
    await tester.pump();
  });

  testWidgets('a refused save says why in plain words, and stays on the form', (
    tester,
  ) async {
    final result = ValueNotifier<Object?>(null);
    serverRefusal =
        'Odoo Server Error: The VAT number [XX123] for partner [Ada] does not '
        'seem to be valid.';

    Future<void> scenario() async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(result));
      await tester.tap(find.text('Open the form'));
      await pumpFor(tester, const Duration(seconds: 2));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ada Lovelace'),
        'Ada King',
      );
      await tester.pump();
      CustomSnackbar.dismiss();
      await tester.pump();
      await tester.tap(find.text('Save Changes'));
      await pumpFor(tester, const Duration(seconds: 2));
    }

    final otherErrors = <Object>[];
    await runZonedGuarded(scenario, (error, stack) {
      final text = error.toString();
      if (!text.contains('google_fonts') && !text.contains('GoogleFonts')) {
        otherErrors.add(error);
      }
    });
    expect(otherErrors, isEmpty);

    expect(writes, hasLength(1));
    // Odoo's own sentence, with nothing of the exception around it.
    expect(
      find.text(
        'The VAT number [XX123] for partner [Ada] does not seem to be valid.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('Odoo Server Error'), findsNothing);
    // The user is still on the form, with their edit.
    expect(find.text('Save Changes'), findsOneWidget);
    expect(result.value, isNull);

    CustomSnackbar.dismiss();
    await tester.pump();
  });
}
