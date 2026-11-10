import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobo_sales/providers/currency_provider.dart';
import 'package:mobo_sales/providers/invoice_details_provider_enterprise.dart';
import 'package:mobo_sales/screens/invoices/invoice_details_screen.dart';
import 'package:mobo_sales/widgets/loading_dialog.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/services/permission_service.dart';

import '../mocks/mock_services.dart';

void main() {
  late DataChangeBus bus;
  late MockInvoiceDetailsService service;
  late MockPermissionService permissions;
  late InvoiceDetailsProvider provider;
  late Map<String, dynamic> serverInvoice;
  var shimmerSeen = false;
  var reads = 0;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bus = DataChangeBus.forTesting();
    service = MockInvoiceDetailsService();
    permissions = MockPermissionService();
    for (final op in ['account.move', 'account.payment.register']) {
      when(() => permissions.canWrite(op)).thenAnswer((_) async => true);
      when(() => permissions.canUnlink(op)).thenAnswer((_) async => true);
      when(() => permissions.canCreate(op)).thenAnswer((_) async => true);
    }
    PermissionService.instance = permissions;

    serverInvoice = {
      'id': 1,
      'name': 'INV/0001',
      'state': 'draft',
      'payment_state': 'not_paid',
      'amount_total': 100.0,
      'amount_residual': 100.0,
      'partner_id': [3, 'Acme'],
    };
    reads = 0;
    when(() => service.fetchInvoiceDetails(1)).thenAnswer((_) async {
      reads++;
      return Map<String, dynamic>.from(serverInvoice);
    });
    when(() => service.fetchPartnerDetails(any())).thenAnswer((_) async => {});
    when(() => service.fetchInvoiceLines(any())).thenAnswer((_) async => []);

    provider = InvoiceDetailsProvider(
      invoiceDetailsService: service,
      permissionService: permissions,
      bus: bus,
    );
    shimmerSeen = false;
    provider.addListener(() {
      if (provider.isLoading) shimmerSeen = true;
    });
  });

  Future<void> pumpPage(WidgetTester tester) async {
    // The page listens on the app's bus, which is what the producers use.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<InvoiceDetailsProvider>.value(value: provider),
          ChangeNotifierProvider<CurrencyProvider>(
            create: (_) => CurrencyProvider(),
          ),
        ],
        child: const MaterialApp(home: InvoiceDetailsPage(invoiceId: '1')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    shimmerSeen = false;
  }

  Future<void> afterChange(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('an action keeps the invoice on screen', (tester) async {
    // A tester saw "Processing..." over a page of grey blocks: an action set
    // the same loading flag the first read uses, so the invoice was replaced
    // by the first-load skeleton underneath the dialog. Odoo leaves the
    // record where it is.
    await pumpPage(tester);
    expect(find.text('INV/0001'), findsWidgets);

    // Held open so the page can be looked at mid-action.
    final posting = Completer<String?>();
    when(() => service.postInvoice(1)).thenAnswer((_) => posting.future);
    when(() => permissions.hasGroup(any())).thenAnswer((_) async => true);

    final done = provider.postInvoice(
      tester.element(find.byType(InvoiceDetailsPage)),
      '1',
    );
    await tester.pump();
    await tester.pump();

    expect(provider.isLoading, isTrue, reason: 'the action is running');
    expect(
      find.text('INV/0001'),
      findsWidgets,
      reason: 'the invoice went blank while the action ran',
    );

    posting.complete(null);
    await done;
    await afterChange(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancelling from the menu keeps the page under the popup', (
    tester,
  ) async {
    // Confirm, cancel and reset are reachable only from the overflow menu,
    // so this drives the menu rather than `_buildSecondaryActionButtons`,
    // which the analyzer reports as unreferenced.
    tester.view.physicalSize = const Size(1344, 2992);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // The open menu overflows its own box by 48px at every width tried. That
    // is a separate layout bug; it is swallowed here so it cannot mask the
    // navigator assertions below.
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    await pumpPage(tester);

    final menu = find.byType(PopupMenuButton<String>);
    expect(menu, findsOneWidget, reason: 'the overflow menu is on the page');
    await tester.tap(menu);
    // Not pumpAndSettle: the page keeps a shimmer running, so nothing ever
    // settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final item = find.text('Cancel Invoice').last;
    expect(item, findsOneWidget, reason: 'a draft invoice can be cancelled');

    final cancelling = Completer<void>();
    when(() => service.cancelInvoice(1)).thenAnswer((_) => cancelling.future);

    await tester.tap(item);
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Cancelling Invoice...'),
      findsOneWidget,
      reason: 'the app\'s one loading popup is up',
    );
    expect(
      find.byType(InvoiceDetailsPage),
      findsOneWidget,
      reason: 'the page must still be under the popup, not popped off',
    );
    expect(
      find.byType(LoadingCard),
      findsOneWidget,
      reason: 'one spinner, not two: the page used to paint its own scrim '
          'under this popup whenever `isProcessing` was set',
    );
    expect(
      find.text('INV/0001'),
      findsWidgets,
      reason: 'and it still shows the invoice, not a blank skeleton',
    );

    cancelling.complete();
    await tester.pump();
    await afterChange(tester);

    expect(
      find.text('Cancelling Invoice...'),
      findsNothing,
      reason: 'the popup closes itself',
    );
    expect(
      find.byType(InvoiceDetailsPage),
      findsOneWidget,
      reason: 'and takes nothing with it',
    );

    // The success snackbar holds a 3s timer; let it run out before the tree
    // goes away.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed action does not replace the invoice with an error '
      'page', (tester) async {
    // The failure already arrives as a message; taking the whole page as
    // well, with a Retry button, is the "nothing extra" the backend does not
    // do either.
    await pumpPage(tester);

    when(() => permissions.canUnlink('account.move'))
        .thenAnswer((_) async => true);
    when(() => service.deleteInvoice(1)).thenThrow(
      Exception('{code: 200, data: {name: odoo.exceptions.UserError, '
          'message: You cannot delete an entry which has been posted once., '
          'arguments: [x]}}'),
    );

    final ok = await provider.deleteInvoice(
      tester.element(find.byType(InvoiceDetailsPage)),
      '1',
    );
    await afterChange(tester);

    expect(ok, isFalse);
    expect(
      provider.errorMessage,
      contains('You cannot delete an entry which has been posted once.'),
      reason: "Odoo's own sentence must survive",
    );
    expect(
      find.text('INV/0001'),
      findsWidgets,
      reason: 'the invoice is still there to look at',
    );
    expect(find.text('Retry'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an invoice changed from somewhere else is reloaded in place, '
      'with no loading state in between', (tester) async {
    await pumpPage(tester);
    expect(provider.invoiceState, 'draft');
    final readsBefore = reads;

    serverInvoice['state'] = 'posted';
    DataChangeBus.instance.invoiceChanged(1);
    await afterChange(tester);

    expect(provider.invoiceState, 'posted');
    expect(reads, readsBefore + 1);
    expect(shimmerSeen, isFalse, reason: 'it reloads quietly');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a payment, from anywhere, reloads it too', (tester) async {
    await pumpPage(tester);
    final readsBefore = reads;

    serverInvoice['payment_state'] = 'paid';
    serverInvoice['amount_residual'] = 0.0;
    DataChangeBus.instance.paymentChanged(9);
    await afterChange(tester);

    expect(provider.paymentState, 'paid');
    expect(provider.amountResidual, 0.0);
    expect(reads, readsBefore + 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('what the page\'s own provider announced is not reloaded a '
      'second time', (tester) async {
    await pumpPage(tester);
    final readsBefore = reads;

    DataChangeBus.instance.invoiceChanged(1, origin: provider);
    await afterChange(tester);

    expect(reads, readsBefore);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('another invoice\'s change is not this page\'s business', (
    tester,
  ) async {
    await pumpPage(tester);
    final readsBefore = reads;

    DataChangeBus.instance.invoiceChanged(2);
    DataChangeBus.instance.publish(DataEntity.customer, DataChangeKind.updated);
    await afterChange(tester);

    expect(reads, readsBefore);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a burst is one reload', (tester) async {
    await pumpPage(tester);
    final readsBefore = reads;

    DataChangeBus.instance.invoiceChanged(1);
    DataChangeBus.instance.paymentChanged(9);
    DataChangeBus.instance.invoiceChanged(null);
    await afterChange(tester);

    expect(reads, readsBefore + 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an invoice deleted from somewhere else shows as not found', (
    tester,
  ) async {
    await pumpPage(tester);

    when(() => service.fetchInvoiceDetails(1)).thenAnswer((_) async => {});
    DataChangeBus.instance.invoiceChanged(1, kind: DataChangeKind.deleted);
    await afterChange(tester);

    expect(provider.invoice, isNull);
    expect(provider.errorMessage, contains('not found'));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a page that was left stops listening', (tester) async {
    await pumpPage(tester);
    await tester.pumpWidget(const SizedBox());
    final readsBefore = reads;

    DataChangeBus.instance.invoiceChanged(1);
    await afterChange(tester);

    expect(reads, readsBefore);
  });
}
