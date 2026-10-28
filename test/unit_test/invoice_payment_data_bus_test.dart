import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobo_sales/models/contact.dart';
import 'package:mobo_sales/models/product.dart';
import 'package:mobo_sales/models/quote.dart';
import 'package:mobo_sales/providers/invoice_creation_provider.dart';
import 'package:mobo_sales/providers/invoice_details_provider_enterprise.dart';
import 'package:mobo_sales/services/invoice_details_service.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/services/invoice_service.dart';
import 'package:mobo_sales/services/payment_service.dart';
import 'package:mobo_sales/services/permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks/mock_services.dart';

/// A context that is not mounted, so the providers skip the rating prompt.
class _UnmountedContext extends Fake implements BuildContext {
  @override
  bool get mounted => false;
}

/// Collects what a bus announces.
class _Heard {
  _Heard(DataChangeBus bus) {
    _subscription = bus.listen(
      debounce: Duration.zero,
      onChange: (burst) => changes.addAll(burst),
    );
  }

  late final DataChangeSubscription _subscription;
  final List<DataChange> changes = [];

  Iterable<DataChange> of(DataEntity entity) =>
      changes.where((c) => c.entity == entity);

  void cancel() => _subscription.cancel();
}

/// Lets the bus deliver (it is asynchronous, and the listener debounces by a
/// zero-length timer).
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late DataChangeBus bus;
  late _Heard heard;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bus = DataChangeBus.forTesting();
    heard = _Heard(bus);
  });

  tearDown(() => heard.cancel());

  group('InvoiceDetailsProvider announces what the server accepted', () {
    late MockInvoiceDetailsService service;
    late MockPermissionService permissions;
    late InvoiceDetailsProvider provider;

    void stubReload(Map<String, dynamic> data) {
      when(
        () => service.fetchInvoiceDetails(1),
      ).thenAnswer((_) async => Map<String, dynamic>.from(data));
      when(
        () => service.fetchPartnerDetails(any()),
      ).thenAnswer((_) async => {});
      when(() => service.fetchInvoiceLines(any())).thenAnswer((_) async => []);
    }

    setUp(() {
      service = MockInvoiceDetailsService();
      permissions = MockPermissionService();
      when(
        () => permissions.canWrite('account.move'),
      ).thenAnswer((_) async => true);
      when(
        () => permissions.canUnlink('account.move'),
      ).thenAnswer((_) async => true);
      // Posting also needs Odoo's Invoicing group; these tests are about the
      // announcement, so the user has it.
      when(
        () => permissions.hasGroup(kInvoicingGroup),
      ).thenAnswer((_) async => true);
      provider = InvoiceDetailsProvider(
        invoiceDetailsService: service,
        permissionService: permissions,
        bus: bus,
      );
    });

    test('confirming announces the invoice, from the provider, once the server '
        'has posted it, and not before', () async {
      provider.setInvoiceData({'id': 1, 'state': 'draft'});
      // Null is "posted"; a non-null value is the step Odoo stopped at.
      final posting = Completer<String?>();
      when(() => service.postInvoice(1)).thenAnswer((_) => posting.future);
      stubReload({'id': 1, 'state': 'posted'});

      final result = provider.postInvoice(_UnmountedContext(), '1');
      await settle();
      expect(heard.changes, isEmpty, reason: 'the server has not answered');

      posting.complete(null);
      expect(await result, isTrue);
      await settle();

      expect(heard.changes, hasLength(1));
      final change = heard.changes.single;
      expect(change.entity, DataEntity.invoice);
      expect(change.kind, DataChangeKind.updated);
      expect(change.id, 1);
      expect(
        identical(change.origin, provider),
        isTrue,
        reason: 'so the page that drives the provider can skip it',
      );
      expect(provider.invoiceState, 'posted');
    });

    test('a refused confirmation announces nothing', () async {
      provider.setInvoiceData({'id': 1, 'state': 'draft'});
      when(() => service.postInvoice(1)).thenThrow(Exception('locked'));

      expect(await provider.postInvoice(_UnmountedContext(), '1'), isFalse);
      await settle();

      expect(heard.changes, isEmpty);
    });

    test('cancelling an invoice made from a sale order also announces the '
        'sale orders', () async {
      provider.setInvoiceData({
        'id': 1,
        'state': 'posted',
        'invoice_origin': 'S00007',
      });
      when(() => service.cancelInvoice(1)).thenAnswer((_) async {});
      stubReload({'id': 1, 'state': 'cancel', 'invoice_origin': 'S00007'});

      expect(await provider.cancelInvoice(_UnmountedContext(), '1'), isTrue);
      await settle();

      expect(heard.of(DataEntity.invoice).single.id, 1);
      expect(heard.of(DataEntity.quotation), hasLength(1));
      expect(
        heard.of(DataEntity.quotation).single.id,
        isNull,
        reason: 'the order is not known, so every quotation list refreshes',
      );
    });

    test('cancelling a plain invoice leaves the sale orders alone', () async {
      provider.setInvoiceData({'id': 1, 'state': 'posted'});
      when(() => service.cancelInvoice(1)).thenAnswer((_) async {});
      stubReload({'id': 1, 'state': 'cancel'});

      await provider.cancelInvoice(_UnmountedContext(), '1');
      await settle();

      expect(heard.of(DataEntity.invoice), hasLength(1));
      expect(heard.of(DataEntity.quotation), isEmpty);
    });

    test('deleting announces a deleted invoice', () async {
      provider.setInvoiceData({
        'id': 1,
        'state': 'draft',
        'invoice_origin': 'S00007',
      });
      when(() => service.deleteInvoice(1)).thenAnswer((_) async {});

      expect(await provider.deleteInvoice(_UnmountedContext(), '1'), isTrue);
      await settle();

      final invoice = heard.of(DataEntity.invoice).single;
      expect(invoice.kind, DataChangeKind.deleted);
      expect(invoice.id, 1);
      expect(heard.of(DataEntity.quotation), hasLength(1));
    });

    test('a posted invoice is reset to draft in one call, no cancel first '
        '(it used to fail every time)', () async {
      provider.setInvoiceData({'id': 1, 'state': 'posted'});
      when(() => service.resetToDraft(1)).thenAnswer((_) async {});
      stubReload({'id': 1, 'state': 'draft'});

      final ok = await provider.resetToDraft(_UnmountedContext(), '1');
      await settle();

      expect(ok, isTrue);
      expect(provider.invoiceState, 'draft');
      verify(() => service.resetToDraft(1)).called(1);
      verifyNever(() => service.cancelInvoice(any()));
      expect(heard.of(DataEntity.invoice).single.kind, DataChangeKind.updated);
    });

    test('a silent reload swaps the data in place: no loading state, nothing '
        'cleared, and a failed reload leaves what is there', () async {
      provider.setInvoiceData({'id': 1, 'name': 'INV/1', 'state': 'draft'});
      final reload = Completer<Map<String, dynamic>>();
      when(
        () => service.fetchInvoiceDetails(1),
      ).thenAnswer((_) => reload.future);
      when(
        () => service.fetchPartnerDetails(any()),
      ).thenAnswer((_) async => {});
      when(() => service.fetchInvoiceLines(any())).thenAnswer((_) async => []);

      var loadingSeen = false;
      provider.addListener(() {
        if (provider.isLoading) loadingSeen = true;
      });

      final done = provider.fetchInvoiceDetails(
        _UnmountedContext(),
        '1',
        silent: true,
      );
      await settle();
      expect(provider.invoice, isNotNull, reason: 'not cleared while loading');
      expect(provider.isLoading, isFalse);

      reload.complete({'id': 1, 'name': 'INV/1', 'state': 'posted'});
      await done;

      expect(provider.invoiceState, 'posted');
      expect(loadingSeen, isFalse);

      // A reload that fails keeps the page as it was and raises no error.
      when(
        () => service.fetchInvoiceDetails(1),
      ).thenThrow(Exception('offline'));
      await provider.fetchInvoiceDetails(
        _UnmountedContext(),
        '1',
        silent: true,
      );
      expect(provider.invoiceState, 'posted');
      expect(provider.errorMessage, isEmpty);
    });

    test('a silent reload of an invoice deleted elsewhere says so', () async {
      provider.setInvoiceData({'id': 1, 'state': 'draft'});
      when(() => service.fetchInvoiceDetails(1)).thenAnswer((_) async => {});

      await provider.fetchInvoiceDetails(
        _UnmountedContext(),
        '1',
        silent: true,
      );

      expect(provider.invoice, isNull);
      expect(provider.errorMessage, contains('not found'));
    });
  });

  group('CreateInvoiceProvider announces a new invoice', () {
    late MockCustomerService customers;
    late MockProductService products;
    late MockInvoiceService invoices;
    late CreateInvoiceProvider provider;

    setUp(() {
      customers = MockCustomerService();
      products = MockProductService();
      invoices = MockInvoiceService();
      provider = CreateInvoiceProvider(
        customerService: customers,
        productService: products,
        invoiceService: invoices,
        bus: bus,
      );
      when(() => invoices.getCurrencyId(any())).thenAnswer((_) async => 1);
      when(
        () => invoices.getInvoiceName(any()),
      ).thenAnswer((_) async => 'INV/1');
      when(
        () => invoices.fetchSaleOrders(domain: any(named: 'domain')),
      ).thenAnswer((_) async => []);
      when(
        () => invoices.linkInvoiceToSaleOrder(any(), any()),
      ).thenAnswer((_) async {});
    });

    /// A line for the direct (no sale order) invoice.
    Future<void> addDirectLine() async {
      when(
        () => products.fetchProductData(any(), fields: any(named: 'fields')),
      ).thenAnswer(
        (_) async => {
          'taxes_id': [1],
        },
      );
      when(() => invoices.calculateTax(any())).thenAnswer(
        (_) async => {
          'amount_untaxed': 10.0,
          'amount_tax': 1.0,
          'amount_total': 11.0,
        },
      );
      await provider.addInvoiceLine(
        Product(
          id: '3',
          name: 'Widget',
          listPrice: 10.0,
          qtyAvailable: 10,
          variantCount: 0,
          defaultCode: 'W001',
          taxId: 1,
        ),
        1.0,
        10.0,
      );
    }

    /// Puts sale order 7 (customer 5, one line to invoice) on the provider.
    Future<void> selectSaleOrder() async {
      when(() => invoices.fetchSaleOrderDetails(7)).thenAnswer(
        (_) async => {
          'id': 7,
          'name': 'S00007',
          'partner_id': [5, 'Customer'],
          'order_line': [11],
          'amount_untaxed': 100.0,
          'amount_tax': 0.0,
          'amount_total': 100.0,
        },
      );
      when(() => invoices.fetchSaleOrderLines([11])).thenAnswer(
        (_) async => [
          {
            'id': 11,
            'product_id': [3, 'Widget'],
            'name': 'Widget',
            'product_uom_qty': 1.0,
            'qty_to_invoice': 1.0,
            'price_unit': 100.0,
            'price_subtotal': 100.0,
            'price_total': 100.0,
            'tax_ids': <int>[],
            'product_uom_id': [1, 'Units'],
          },
        ],
      );
      when(
        () => customers.fetchCustomerDetails(5),
      ).thenAnswer((_) async => Contact(id: 5, name: 'Customer'));
      await provider.setSelectedSaleOrder(
        Quote(
          id: 7,
          name: 'S00007',
          customerId: 5,
          lines: const [],
          subtotal: 100,
          taxAmount: 0,
          total: 100,
          status: 'sale',
        ),
      );
    }

    test('an invoice made from a sale order announces the invoice and that '
        'order, as soon as the wizard has produced it', () async {
      await selectSaleOrder();
      when(
        () => invoices.createAdvancePaymentWizard(any()),
      ).thenAnswer((_) async => 90);
      when(
        () => invoices.executeAdvancePaymentWizard(90),
      ).thenAnswer((_) async => {'res_id': 55});

      await provider.createInvoice(_UnmountedContext());
      await settle();

      expect(provider.errorMessage, isEmpty);
      final invoice = heard.of(DataEntity.invoice).single;
      expect(invoice.kind, DataChangeKind.created);
      expect(invoice.id, 55);
      expect(heard.of(DataEntity.quotation).single.id, 7);
    });

    test(
      'a down payment invoice announces the invoice and its sale order',
      () async {
        await selectSaleOrder();
        when(() => invoices.createInvoice(any())).thenAnswer((_) async => 56);

        await provider.createInvoice(
          _UnmountedContext(),
          invoiceType: 'percentage',
          downPaymentPercentage: 10,
        );
        await settle();

        expect(provider.errorMessage, isEmpty);
        expect(heard.of(DataEntity.invoice).single.id, 56);
        expect(heard.of(DataEntity.quotation).single.id, 7);
      },
    );

    test('a direct invoice is announced before the steps that tidy up after '
        'it, and no sale order is', () async {
      provider.setSelectedCustomer(Contact(id: 5, name: 'Customer'));
      await addDirectLine();
      when(() => invoices.createInvoice(any())).thenAnswer((_) async => 57);
      final naming = Completer<String?>();
      when(() => invoices.getInvoiceName(57)).thenAnswer((_) => naming.future);

      final creating = provider.createInvoice(_UnmountedContext());
      await settle();

      // The invoice exists on the server; the name read is still pending.
      expect(heard.of(DataEntity.invoice).single.id, 57);
      expect(heard.of(DataEntity.quotation), isEmpty);

      naming.complete('INV/57');
      await creating;
      expect(provider.lastCreatedInvoiceName, 'INV/57');
    });

    test('a refused link to the sale order does not turn a created invoice '
        'into a failure', () async {
      await selectSaleOrder();
      when(() => invoices.createInvoice(any())).thenAnswer((_) async => 58);
      when(
        () => invoices.linkInvoiceToSaleOrder(7, 58),
      ).thenThrow(Exception('access denied'));

      await provider.createInvoice(
        _UnmountedContext(),
        invoiceType: 'fixed',
        downPaymentAmount: 25,
      );
      await settle();

      expect(provider.errorMessage, isEmpty);
      expect(provider.lastCreatedInvoiceId, 58);
      expect(heard.of(DataEntity.invoice).single.id, 58);
    });

    test(
      'notes typed on a direct invoice go to Odoo as its HTML narration',
      () async {
        provider.setSelectedCustomer(Contact(id: 5, name: 'Customer'));
        await addDirectLine();
        when(() => invoices.createInvoice(any())).thenAnswer((_) async => 60);
        when(
          () => invoices.getInvoiceName(60),
        ).thenAnswer((_) async => 'Draft');

        provider.setNotes('Pay in 30 days\n\nThanks & <regards>');
        await provider.createInvoice(_UnmountedContext());

        final sent = verify(
          () => invoices.createInvoice(captureAny()),
        ).captured.whereType<Map>().last;
        expect(
          sent['narration'],
          '<p>Pay in 30 days</p><p>Thanks &amp; &lt;regards&gt;</p>',
        );
      },
    );

    test('no notes, no narration', () async {
      provider.setSelectedCustomer(Contact(id: 5, name: 'Customer'));
      await addDirectLine();
      when(() => invoices.createInvoice(any())).thenAnswer((_) async => 61);
      when(() => invoices.getInvoiceName(61)).thenAnswer((_) async => 'Draft');

      provider.setNotes('   ');
      await provider.createInvoice(_UnmountedContext());

      final sent = verify(
        () => invoices.createInvoice(captureAny()),
      ).captured.whereType<Map>().last;
      expect(sent.containsKey('narration'), isFalse);
    });

    test('notes on a down payment invoice are sent with it', () async {
      await selectSaleOrder();
      when(() => invoices.createInvoice(any())).thenAnswer((_) async => 62);

      provider.setNotes('Deposit received');
      await provider.createInvoice(
        _UnmountedContext(),
        invoiceType: 'percentage',
        downPaymentPercentage: 10,
      );

      final sent = verify(
        () => invoices.createInvoice(captureAny()),
      ).captured.whereType<Map>().last;
      expect(sent['narration'], '<p>Deposit received</p>');
    });

    test(
      'notes on an invoice the wizard made are written to it afterwards',
      () async {
        await selectSaleOrder();
        when(
          () => invoices.createAdvancePaymentWizard(any()),
        ).thenAnswer((_) async => 90);
        when(
          () => invoices.executeAdvancePaymentWizard(90),
        ).thenAnswer((_) async => {'res_id': 63});
        when(
          () => invoices.updateInvoice(any(), any()),
        ).thenAnswer((_) async {});

        provider.setNotes('For the March order');
        await provider.createInvoice(_UnmountedContext());

        verify(
          () => invoices.updateInvoice(63, {
            'narration': '<p>For the March order</p>',
          }),
        ).called(1);
      },
    );

    test('a failed creation announces nothing', () async {
      provider.setSelectedCustomer(Contact(id: 5, name: 'Customer'));
      await addDirectLine();
      when(() => invoices.createInvoice(any())).thenThrow(Exception('boom'));

      await provider.createInvoice(_UnmountedContext());
      await settle();

      expect(provider.errorMessage, isNotEmpty);
      expect(heard.changes, isEmpty);
    });
  });

  group('InvoiceService', () {
    late List<Map<String, dynamic>> calls;
    late InvoiceService service;

    setUp(() {
      calls = [];
      service = InvoiceService.forTesting(
        bus: bus,
        callKw: (payload) async {
          calls.add(payload);
          if (payload['method'] == 'create') return 900;
          if (payload['method'] == 'read') {
            return [
              {'amount_untaxed': 1.0, 'amount_tax': 0.1, 'amount_total': 1.1},
            ];
          }
          return true;
        },
      );
    });

    test('updating an invoice writes it, then announces it', () async {
      await service.updateInvoice(12, {'partner_id': 3});
      await settle();

      expect(calls.single['method'], 'write');
      expect(calls.single['args'], [
        [12],
        {'partner_id': 3},
      ]);
      expect(heard.changes.single.entity, DataEntity.invoice);
      expect(heard.changes.single.id, 12);
      expect(heard.changes.single.kind, DataChangeKind.updated);
    });

    test('a refused update announces nothing', () async {
      final failing = InvoiceService.forTesting(
        bus: bus,
        callKw: (_) async => throw Exception('access denied'),
      );

      await expectLater(failing.updateInvoice(12, {}), throwsException);
      await settle();

      expect(heard.changes, isEmpty);
    });

    test(
      'the throwaway invoice behind the tax estimate is never announced',
      () async {
        final tax = await service.calculateTax({'partner_id': 3});
        await settle();

        expect(tax['amount_total'], 1.1);
        expect(
          calls.map((c) => c['method']),
          containsAllInOrder(['create', 'read', 'unlink']),
        );
        expect(heard.changes, isEmpty);
      },
    );
  });

  group('PaymentService announces a registered payment', () {
    late MockOdooClient client;
    late MockPermissionService permissions;
    late List<String> methods;
    var failStatusRead = false;

    setUp(() {
      client = MockOdooClient();
      permissions = MockPermissionService();
      methods = [];
      failStatusRead = false;
      when(
        () => permissions.canCreate('account.payment.register'),
      ).thenAnswer((_) async => true);
      PermissionService.instance = permissions;
      PaymentService.bus = bus;
      PaymentService.clientProvider = () async => client;

      registerFallbackValue(<String, dynamic>{});
      when(() => client.callKw(any())).thenAnswer((invocation) async {
        final payload = invocation.positionalArguments.first as Map;
        final model = payload['model'];
        final method = payload['method'];
        methods.add('$model.$method');
        switch ('$model.$method') {
          case 'account.move.search_read':
            if (failStatusRead &&
                (payload['args'] as List).last is List &&
                ((payload['args'] as List).last as List).contains(
                  'payment_state',
                ) &&
                ((payload['args'] as List).last as List).contains('state')) {
              throw Exception('read failed');
            }
            return [
              {
                'id': 7,
                'partner_id': [3, 'Customer'],
                'company_id': [1, 'Company'],
                'amount_residual': 0.0,
                'name': 'INV/7',
                'state': 'posted',
                'payment_state': 'paid',
              },
            ];
          case 'account.journal.search_read':
            return [
              {'id': 21, 'name': 'Bank', 'type': 'bank'},
            ];
          case 'account.payment.method.line.search_read':
            return [
              {'id': 31, 'name': 'Manual'},
            ];
          case 'account.payment.register.create':
            return 41;
          case 'account.payment.register.action_create_payments':
            return {'res_id': 77};
        }
        return [];
      });
    });

    tearDown(() {
      PaymentService.bus = DataChangeBus.instance;
      PaymentService.clientProvider = _defaultClientProvider;
    });

    test('a recorded payment announces the payment and its invoice', () async {
      final result = await PaymentService.createPayment(
        invoiceId: 7,
        amount: 100,
        paymentMethod: 'bank',
        paymentDate: DateTime(2026, 10, 9),
      );
      await settle();

      expect(result['success'], isTrue);
      final payment = heard.of(DataEntity.payment).single;
      expect(payment.kind, DataChangeKind.created);
      expect(payment.id, 77);
      final invoice = heard.of(DataEntity.invoice).single;
      expect(invoice.id, 7, reason: 'its payment state and residual changed');
      expect(invoice.kind, DataChangeKind.updated);
    });

    test(
      'the payment is announced even when reading the invoice back fails, '
      'and the call still succeeds (it must not be recorded twice)',
      () async {
        failStatusRead = true;

        final result = await PaymentService.createPayment(
          invoiceId: 7,
          amount: 100,
          paymentMethod: 'bank',
          paymentDate: DateTime(2026, 10, 9),
        );
        await settle();

        expect(result['success'], isTrue);
        expect(heard.of(DataEntity.payment), hasLength(1));
        expect(heard.of(DataEntity.invoice), hasLength(1));
        expect(
          methods.where(
            (m) => m == 'account.payment.register.action_create_payments',
          ),
          hasLength(1),
        );
      },
    );

    test('nothing is announced when the server refuses the payment', () async {
      when(() => client.callKw(any())).thenAnswer((invocation) async {
        final payload = invocation.positionalArguments.first as Map;
        if (payload['model'] == 'account.payment.register' &&
            payload['method'] == 'action_create_payments') {
          throw Exception('The payment amount exceeds the balance');
        }
        if (payload['model'] == 'account.payment.register') return 41;
        if (payload['model'] == 'account.journal') {
          return [
            {'id': 21},
          ];
        }
        if (payload['model'] == 'account.payment.method.line') {
          return [
            {'id': 31},
          ];
        }
        return [
          {
            'id': 7,
            'partner_id': [3, 'Customer'],
            'company_id': [1, 'Company'],
          },
        ];
      });

      await expectLater(
        PaymentService.createPayment(
          invoiceId: 7,
          amount: 100,
          paymentMethod: 'bank',
          paymentDate: DateTime(2026, 10, 9),
        ),
        throwsException,
      );
      await settle();

      expect(heard.changes, isEmpty);
    });

    test(
      'reconciling a payment announces the payment and the invoice',
      () async {
        when(() => client.callKw(any())).thenAnswer((invocation) async {
          final payload = invocation.positionalArguments.first as Map;
          if (payload['method'] == 'reconcile') return true;
          return [
            {'id': 1, 'debit': 0.0, 'credit': 10.0, 'amount_residual': 10.0},
          ];
        });

        expect(await PaymentService.reconcilePayment(77, 7), isTrue);
        await settle();

        expect(heard.of(DataEntity.payment).single.id, 77);
        expect(
          heard.of(DataEntity.payment).single.kind,
          DataChangeKind.updated,
        );
        expect(heard.of(DataEntity.invoice).single.id, 7);
      },
    );
  });
}

Future<dynamic> _defaultClientProvider() async => null;
