import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobo_sales/providers/currency_provider.dart';
import 'package:mobo_sales/providers/invoice_details_provider_enterprise.dart';
import 'package:mobo_sales/screens/invoices/invoice_details_screen.dart';
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
