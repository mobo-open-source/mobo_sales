import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/services/payment_service.dart';
import 'package:mobo_sales/services/permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks/mock_services.dart';

/// How the fake server answers `action_create_payments`.
enum _Answer {
  /// Records the payment and answers.
  ok,

  /// Records the payment, then the answer is lost (a timeout).
  paidThenTimeout,

  /// Never records it, and the answer is lost.
  lostBeforePaid,

  /// Refuses it, as a UserError.
  refuse,
}

/// A small stand-in for Odoo's `account.payment.register` wizard and the
/// invoice behind it, recording every call.
class _FakeOdoo {
  _FakeOdoo({
    this.moveType = 'out_invoice',
    this.answer = _Answer.ok,
    List<Map<String, dynamic>>? journals,
    this.wizardJournal = 21,
    this.residualDrops = true,
  }) : journals =
           journals ??
           [
             {'id': 21, 'name': 'Bank', 'type': 'bank'},
             {'id': 22, 'name': 'Cash', 'type': 'cash'},
           ];

  double residual = 1000;
  final String moveType;
  _Answer answer;
  final List<Map<String, dynamic>> journals;
  int wizardJournal;

  /// Odoo 19 keeps an invoice's residual while its payment is only "in
  /// process"; set false to model that.
  final bool residualDrops;

  /// The customer's payments, oldest first.
  final List<Map<String, dynamic>> payments = [
    {'id': 5, 'amount': 50.0},
  ];

  final List<Map<String, dynamic>> calls = [];
  Map<String, dynamic> wizardValues = {};
  final List<Map<String, dynamic>> wizardWrites = [];

  Iterable<Map<String, dynamic>> called(String model, String method) => calls
      .where((c) => c['model'] == model && c['method'] == method)
      .cast<Map<String, dynamic>>();

  int get paymentsCreated =>
      called('account.payment.register', 'action_create_payments').length;

  Future<dynamic> handle(Map payload) async {
    final model = payload['model'];
    final method = payload['method'];
    final args = payload['args'] as List;
    calls.add(Map<String, dynamic>.from(payload));

    switch ('$model.$method') {
      case 'account.move.search_read':
        final fields = args[1] as List;
        return [
          {
            'id': 7,
            'partner_id': [3, 'Customer'],
            'company_id': [1, 'Company'],
            'currency_id': [1, 'USD'],
            'amount_residual': residual,
            'amount_total': 1000.0,
            'name': 'INV/7',
            'state': 'posted',
            'payment_state': residual <= 0 ? 'paid' : 'partial',
            'move_type': moveType,
            if (fields.contains('id')) 'id': 7,
          },
        ];
      case 'account.payment.register.create':
        wizardValues = Map<String, dynamic>.from(args.first as Map);
        return 41;
      case 'account.payment.register.read':
        return [
          {
            'id': 41,
            'journal_id': [wizardJournal, 'x'],
            'payment_method_line_id': [wizardJournal + 100, 'Manual'],
            'available_journal_ids': [for (final j in journals) j['id']],
            'available_payment_method_line_ids': [wizardJournal + 100],
          },
        ];
      case 'account.journal.search_read':
        return journals;
      case 'account.payment.register.write':
        final values = Map<String, dynamic>.from(args[1] as Map);
        wizardWrites.add(values);
        if (values['journal_id'] is int) {
          wizardJournal = values['journal_id'] as int;
        }
        return true;
      case 'account.payment.search_read':
        final domain = args.first as List;
        var found = [...payments];
        for (final term in domain) {
          final field = term[0];
          final op = term[1];
          final value = term[2];
          if (field == 'id' && op == '>') {
            found = found.where((p) => p['id'] > value).toList();
          } else if (field == 'amount' && op == '>=') {
            found = found.where((p) => p['amount'] >= value).toList();
          } else if (field == 'amount' && op == '<=') {
            found = found.where((p) => p['amount'] <= value).toList();
          }
        }
        found.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
        return found;
      case 'account.payment.register.action_create_payments':
        void record() {
          final amount = (wizardValues['amount'] as num).toDouble();
          if (residualDrops) residual -= amount;
          payments.add({'id': 60 + payments.length, 'amount': amount});
        }
        switch (answer) {
          case _Answer.ok:
            record();
            return {'res_id': 77};
          case _Answer.paidThenTimeout:
            record();
            throw TimeoutException('request timed out');
          case _Answer.lostBeforePaid:
            throw TimeoutException('request timed out');
          case _Answer.refuse:
            throw Exception(
              'OdooException: odoo.exceptions.UserError: You cannot pay this.',
            );
        }
      case 'res.currency.read':
        return [
          {'id': 1, 'decimal_places': 3},
        ];
    }
    return [];
  }
}

void main() {
  late MockOdooClient client;
  late _FakeOdoo odoo;
  late DataChangeBus bus;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    client = MockOdooClient();
    odoo = _FakeOdoo();
    bus = DataChangeBus.forTesting();

    final permissions = MockPermissionService();
    when(
      () => permissions.canCreate('account.payment.register'),
    ).thenAnswer((_) async => true);
    PermissionService.instance = permissions;

    PaymentService.bus = bus;
    PaymentService.clientProvider = () async => client;
    when(() => client.callKw(any())).thenAnswer(
      (invocation) => odoo.handle(invocation.positionalArguments.first as Map),
    );
  });

  tearDown(() {
    PaymentService.bus = DataChangeBus.instance;
    PaymentService.clientProvider = () async => null;
  });

  Future<PaymentResult> pay({
    double amount = 300,
    String method = 'bank',
    String memo = '',
    PaymentDifferenceHandling handling = PaymentDifferenceHandling.keepOpen,
    WriteOffConfig? writeOff,
  }) => PaymentService.createPaymentWithOdooFlow(
    invoiceId: 7,
    amount: amount,
    paymentMethod: PaymentMethodData(id: 1, name: method, type: method),
    paymentDate: DateTime(2026, 11, 4),
    options: PaymentOptions(
      memo: memo,
      differenceHandling: handling,
      writeOffConfig: writeOff,
    ),
  );

  group('a failed answer never registers the payment twice', () {
    test('timeout after the payment was recorded: no second payment, and the '
        'invoice is reported as paid', () async {
      odoo.answer = _Answer.paidThenTimeout;

      final result = await pay(amount: 300); // 300 of 1000: the review's case

      expect(odoo.paymentsCreated, 1, reason: 'the wizard is run once');
      expect(odoo.residual, 700, reason: 'one payment of 300, not two');
      expect(result.success, isTrue, reason: 'the invoice owes less now');
    });

    test('Odoo 19 keeps the residual of an "in process" payment: a new payment '
        'still shows that it was made, and it is not repeated', () async {
      odoo = _FakeOdoo(residualDrops: false, answer: _Answer.paidThenTimeout);

      final result = await pay(amount: 300);

      expect(odoo.paymentsCreated, 1);
      expect(odoo.residual, 1000, reason: 'the residual did not move');
      expect(result.success, isTrue, reason: 'but a payment of 300 appeared');
    });

    test('in that mode a payment that never reached the server is still '
        'only "being processed"', () async {
      odoo = _FakeOdoo(residualDrops: false, answer: _Answer.lostBeforePaid);

      final result = await pay(amount: 300);

      expect(odoo.paymentsCreated, 1);
      expect(result.success, isFalse);
      expect(result.warnings, contains('timeout_but_processing'));
    });

    test(
      'an older payment of the same amount is not mistaken for this one',
      () async {
        odoo = _FakeOdoo(residualDrops: false, answer: _Answer.lostBeforePaid);
        odoo.payments.add({'id': 9, 'amount': 300.0}); // before this attempt

        final result = await pay(amount: 300);

        expect(result.success, isFalse);
        expect(result.warnings, contains('timeout_but_processing'));
      },
    );

    test('timeout with nothing recorded: being processed, still one attempt, '
        'and nothing is announced as paid', () async {
      odoo.answer = _Answer.lostBeforePaid;

      final result = await pay(amount: 300);

      expect(odoo.paymentsCreated, 1);
      expect(odoo.residual, 1000);
      expect(result.success, isFalse);
      expect(result.warnings, contains('timeout_but_processing'));
    });

    test('the server refusing it is a plain failure, with its own reason and '
        'no second attempt', () async {
      odoo.answer = _Answer.refuse;

      final result = await pay(amount: 300);

      expect(odoo.paymentsCreated, 1);
      expect(result.success, isFalse);
      expect(result.warnings, isNot(contains('timeout_but_processing')));
      expect(result.errorMessage, contains('cannot pay this'));
    });

    test(
      'a failure before the payment is sent leaves nothing behind',
      () async {
        when(() => client.callKw(any())).thenAnswer((invocation) async {
          final payload = invocation.positionalArguments.first as Map;
          if (payload['model'] == 'account.payment.register' &&
              payload['method'] == 'create') {
            throw Exception('connection error');
          }
          return odoo.handle(payload);
        });

        final result = await pay(amount: 300);

        expect(odoo.paymentsCreated, 0);
        expect(result.success, isFalse);
        expect(
          result.warnings,
          isNot(contains('timeout_but_processing')),
          reason: 'it was never sent, so it cannot be processing',
        );
      },
    );
  });

  group('what is sent to Odoo\'s wizard', () {
    test('the memo goes in Odoo\'s `communication` field', () async {
      await pay(memo: '  Cash on delivery  ');
      expect(odoo.wizardValues['communication'], 'Cash on delivery');
    });

    test('no memo typed: none is invented, so Odoo fills in its own', () async {
      await pay(memo: '');
      expect(odoo.wizardValues.containsKey('communication'), isFalse);
    });

    test(
      'only what the user chose is sent: no hard-coded direction, partner or '
      'journal',
      () async {
        await pay();
        final sent = odoo.wizardValues.keys.toSet();
        expect(sent, containsAll(['amount', 'payment_date']));
        for (final hardCoded in [
          'payment_type',
          'partner_type',
          'partner_id',
          'company_id',
          'journal_id',
          'payment_method_line_id',
        ]) {
          expect(sent, isNot(contains(hardCoded)), reason: hardCoded);
        }
        final create = odoo.called('account.payment.register', 'create').single;
        final context = (create['kwargs'] as Map)['context'] as Map;
        expect(context.containsKey('default_payment_type'), isFalse);
        expect(context['active_ids'], [7]);
        expect(context['allowed_company_ids'], [1]);
      },
    );

    test('a credit note is not forced to inbound', () async {
      odoo = _FakeOdoo(moveType: 'out_refund');
      await pay();
      expect(odoo.wizardValues.containsKey('payment_type'), isFalse);
      final create = odoo.called('account.payment.register', 'create').single;
      final context = (create['kwargs'] as Map)['context'] as Map;
      expect(context.containsKey('default_payment_type'), isFalse);
    });

    test('a write-off is sent only when chosen', () async {
      await pay(
        handling: PaymentDifferenceHandling.writeOff,
        writeOff: WriteOffConfig(accountId: 55, label: 'Rounding'),
      );
      expect(odoo.wizardValues['payment_difference_handling'], 'reconcile');
      expect(odoo.wizardValues['writeoff_account_id'], 55);
      expect(odoo.wizardValues['writeoff_label'], 'Rounding');
    });

    test('an overpayment is allowed, as it is in Odoo', () async {
      final result = await pay(amount: 1500);
      expect(result.success, isTrue);
      expect(odoo.paymentsCreated, 1);
    });
  });

  group('the journal', () {
    test('the wizard\'s own (preferred) journal stays when it is of the chosen '
        'type', () async {
      odoo = _FakeOdoo(wizardJournal: 21);
      await pay(method: 'bank');
      expect(odoo.wizardWrites, isEmpty);
    });

    test('cash picks a cash journal the wizard offers', () async {
      odoo = _FakeOdoo(wizardJournal: 21);
      await pay(method: 'cash');
      expect(odoo.wizardWrites.first, {'journal_id': 22});
    });

    test(
      'the first journal of the type, in the order Odoo lists them',
      () async {
        odoo = _FakeOdoo(
          wizardJournal: 21,
          journals: [
            {'id': 21, 'name': 'Bank A', 'type': 'bank'},
            {'id': 30, 'name': 'Cash B', 'type': 'cash'},
            {'id': 22, 'name': 'Cash A', 'type': 'cash'},
          ],
        );
        await pay(method: 'cash');
        expect(odoo.wizardWrites.first, {'journal_id': 30});
      },
    );

    test('a preferred cash journal is kept when cash was chosen', () async {
      odoo = _FakeOdoo(wizardJournal: 22);
      await pay(method: 'cash');
      expect(odoo.wizardWrites, isEmpty);
    });

    test('asking for a type the company has no journal of is an error, not a '
        'silent switch to another type', () async {
      odoo = _FakeOdoo(
        journals: [
          {'id': 21, 'name': 'Bank', 'type': 'bank'},
        ],
      );
      await expectLater(
        pay(method: 'cash'),
        throwsA(
          isA<PaymentError>().having(
            (e) => e.message,
            'message',
            contains('No cash journal'),
          ),
        ),
      );
      expect(odoo.paymentsCreated, 0);
    });
  });

  group('currency decimals', () {
    test('are read from the currency, and cached', () async {
      expect(await PaymentService.currencyDecimals(1), 3);
      expect(await PaymentService.currencyDecimals(1), 3);
      expect(odoo.called('res.currency', 'read'), hasLength(1));
    });

    test('are two when there is no currency', () async {
      expect(await PaymentService.currencyDecimals(null), 2);
    });
  });
}
