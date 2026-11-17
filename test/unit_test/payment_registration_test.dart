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
    this.keepsAmount = true,
    this.wizardCurrency = 1,
    this.odoo17 = false,
    this.refusesToOpen = false,
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

  /// False models a server that ignores the amount it is given.
  final bool keepsAmount;

  /// The currency the wizard pays in.
  int wizardCurrency;

  /// Odoo 17: the wizard has no `actionable_errors`.
  final bool odoo17;

  /// Odoo refuses to open the wizard (e.g. nothing left to pay).
  final bool refusesToOpen;

  /// Payments of this invoice still in progress, which Odoo 18+ warns about.
  bool hasPaymentsInProgress = false;

  /// The customer's payments, oldest first.
  final List<Map<String, dynamic>> payments = [
    {'id': 5, 'amount': 50.0},
  ];

  final List<Map<String, dynamic>> calls = [];

  /// The values the app set on the wizard that are still in effect. A key
  /// that is missing holds Odoo's computed default (the amount: what is due).
  Map<String, dynamic> wizardValues = {};
  final List<Map<String, dynamic>> wizardWrites = [];

  Iterable<Map<String, dynamic>> called(String model, String method) => calls
      .where((c) => c['model'] == model && c['method'] == method)
      .cast<Map<String, dynamic>>();

  /// What the wizard would pay now.
  double get wizardAmount =>
      (wizardValues['amount'] as num?)?.toDouble() ?? residual;

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
      case 'account.payment.register.fields_get':
        return {
          for (final f in args.first as List)
            if (!(odoo17 && f == 'actionable_errors')) f: {'type': 'x'},
        };
      case 'account.payment.register.create':
        if (refusesToOpen) {
          throw Exception(
            'OdooException: odoo.exceptions.UserError: You can\'t register a '
            'payment because there is nothing left to pay.',
          );
        }
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
            'amount': wizardAmount,
            'communication': wizardValues['communication'] ?? 'INV/7',
            'payment_difference': residual - wizardAmount,
            if (!odoo17)
              'actionable_errors': hasPaymentsInProgress
                  ? {
                      'unpaid_matched_payments': {
                        'message':
                            "There are payments in progress. Make sure you "
                            "don't pay twice.",
                        'action_text': 'Check them',
                        'level': 'danger',
                      },
                    }
                  : {},
            'currency_id': [
              wizardCurrency,
              wizardCurrency == 1 ? 'USD' : 'EUR',
            ],
            'payment_difference_handling':
                wizardValues['payment_difference_handling'] ?? 'open',
            'writeoff_account_id': wizardValues['writeoff_account_id'] is int
                ? [wizardValues['writeoff_account_id'], 'Write-off']
                : false,
          },
        ];
      case 'account.journal.search_read':
        return journals;
      case 'account.payment.register.write':
        final values = Map<String, dynamic>.from(args[1] as Map);
        wizardWrites.add(values);
        if (values['journal_id'] is int) {
          wizardJournal = values['journal_id'] as int;
          final journal = journals.firstWhere((j) => j['id'] == wizardJournal);
          if (journal['currency_id'] is List) {
            wizardCurrency = (journal['currency_id'] as List).first as int;
          }
          // As Odoo does: amount depends on currency_id, which depends on
          // journal_id, and the difference handling (18+) on the amount. A
          // field written in the same call is not recomputed.
          if (!values.containsKey('amount')) wizardValues.remove('amount');
          if (!values.containsKey('payment_difference_handling')) {
            wizardValues.remove('payment_difference_handling');
          }
        }
        if (values.containsKey('amount') &&
            !values.containsKey('payment_difference_handling')) {
          wizardValues.remove('payment_difference_handling');
        }
        for (final entry in values.entries) {
          if (entry.key == 'journal_id') continue;
          if (entry.key == 'amount' && !keepsAmount) continue;
          wizardValues[entry.key] = entry.value;
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
          final amount = wizardAmount;
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
    PaymentService.clearBehaviorCache();
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
      expect(
        odoo.wizardWrites.where((w) => w.containsKey('journal_id')),
        isEmpty,
      );
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
      expect(
        odoo.wizardWrites.where((w) => w.containsKey('journal_id')),
        isEmpty,
      );
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

  group('the amount paid is the amount entered', () {
    test('cash on a wizard that opened on a bank journal records 350, not '
        'the whole amount due', () async {
      // The reported case: 350 typed, cash chosen, 750 recorded. Changing
      // the journal makes Odoo recompute the amount, so it is written after.
      odoo = _FakeOdoo(wizardJournal: 21);
      odoo.residual = 750;
      final result = await pay(amount: 350, method: 'cash');
      expect(result.success, isTrue);
      expect(odoo.paymentsCreated, 1);
      expect(odoo.payments.last['amount'], 350);
      expect(odoo.residual, 400);
    });

    test('the journal is settled before the amount is written', () async {
      odoo = _FakeOdoo(wizardJournal: 21);
      await pay(amount: 300, method: 'cash');
      final journalWrite = odoo.wizardWrites.indexWhere(
        (w) => w.containsKey('journal_id'),
      );
      final amountWrite = odoo.wizardWrites.indexWhere(
        (w) => w.containsKey('amount'),
      );
      expect(journalWrite, isNonNegative);
      expect(amountWrite, greaterThan(journalWrite));
      final create = odoo.called('account.payment.register', 'create').single;
      expect((create['args'] as List).first, isNot(contains('amount')));
    });

    test('a write-off survives the switch to a cash journal', () async {
      odoo = _FakeOdoo(wizardJournal: 21);
      await pay(
        amount: 990,
        method: 'cash',
        handling: PaymentDifferenceHandling.writeOff,
        writeOff: WriteOffConfig(accountId: 55, label: 'Rounding'),
      );
      expect(odoo.paymentsCreated, 1);
      expect(odoo.wizardValues['payment_difference_handling'], 'reconcile');
      expect(odoo.payments.last['amount'], 990);
    });

    test(
      'a server that does not keep the amount gets no payment at all',
      () async {
        odoo = _FakeOdoo(keepsAmount: false);
        await expectLater(
          pay(amount: 350),
          throwsA(
            isA<PaymentError>().having(
              (e) => e.message,
              'message',
              contains('did not keep the amount'),
            ),
          ),
        );
        expect(odoo.paymentsCreated, 0);
      },
    );

    test('a cash journal in the invoice\'s currency is preferred over one '
        'in another currency', () async {
      odoo = _FakeOdoo(
        wizardJournal: 21,
        journals: [
          {'id': 21, 'name': 'Bank', 'type': 'bank', 'currency_id': false},
          {
            'id': 31,
            'name': 'Cash EUR',
            'type': 'cash',
            'currency_id': [2, 'EUR'],
          },
          {'id': 22, 'name': 'Cash', 'type': 'cash', 'currency_id': false},
        ],
      );
      final result = await pay(amount: 300, method: 'cash');
      expect(result.success, isTrue);
      expect(odoo.wizardWrites.first, {'journal_id': 22});
    });

    test('the only cash journal paying in another currency is refused, not '
        'paid in the wrong currency', () async {
      odoo = _FakeOdoo(
        wizardJournal: 21,
        journals: [
          {'id': 21, 'name': 'Bank', 'type': 'bank', 'currency_id': false},
          {
            'id': 31,
            'name': 'Cash EUR',
            'type': 'cash',
            'currency_id': [2, 'EUR'],
          },
        ],
      );
      await expectLater(
        pay(amount: 300, method: 'cash'),
        throwsA(
          isA<PaymentError>().having(
            (e) => e.message,
            'message',
            contains('EUR'),
          ),
        ),
      );
      expect(odoo.paymentsCreated, 0);
    });
  });

  group('what Odoo proposes, read without paying', () {
    test('a payment in progress: Odoo still proposes the whole amount due, '
        'and warns instead', () async {
      odoo = _FakeOdoo(residualDrops: false);
      odoo.residual = 750;
      odoo.hasPaymentsInProgress = true;

      final preview = await PaymentService.previewPayment(7);

      expect(preview.amount, 750);
      expect(preview.memo, 'INV/7');
      expect(preview.alerts.single.isPaymentsInProgress, isTrue);
      expect(preview.alerts.single.level, 'danger');
      expect(preview.alerts.single.message, contains("don't pay twice"));
      expect(preview.alerts.single.actionText, 'Check them');
      expect(odoo.paymentsCreated, 0, reason: 'a preview never pays');
    });

    test('nothing in progress: no alert', () async {
      final preview = await PaymentService.previewPayment(7);
      expect(preview.alerts, isEmpty);
    });

    test('Odoo 17 has no alerts field, and it is not asked for', () async {
      odoo = _FakeOdoo(odoo17: true);
      final preview = await PaymentService.previewPayment(7);
      expect(preview.alerts, isEmpty);
      final read = odoo.called('account.payment.register', 'read').single;
      expect(
        ((read['args'] as List)[1] as List),
        isNot(contains('actionable_errors')),
      );
    });

    test('the difference for a typed amount is Odoo\'s own', () async {
      odoo.residual = 750;
      final preview = await PaymentService.previewPayment(7);
      expect(preview.difference, 0);
      expect(await PaymentService.previewDifference(preview, 350), 400);
      expect(await PaymentService.previewDifference(preview, 800), -50);
      expect(odoo.paymentsCreated, 0);
    });

    test('Odoo refusing to open the wizard is reported in its words', () async {
      odoo = _FakeOdoo(refusesToOpen: true);
      await expectLater(
        PaymentService.previewPayment(7),
        throwsA(predicate((e) => e.toString().contains('nothing left to pay'))),
      );
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

  group("the Pay wizard's payments-in-progress alert", () {
    /// `actionable_errors` as Odoo sends it, keyed the way [generation]
    /// keys it.
    Map<String, dynamic> actionableErrors(String key) => {
      key: {
        'message':
            "There are payments in progress. Make sure you don't pay "
            'twice.',
        'level': 'danger',
        'action_text': 'Check them',
      },
    };

    test('is recognised under the key each release uses', () {
      // 18 and 19 call it `unpaid_matched_payments`; 20 renamed it to
      // `unreconciled_matched_payments`. Matching only the first left the
      // alert on screen with no way to act on it on Odoo 20.
      for (final key in const [
        'unpaid_matched_payments',
        'unreconciled_matched_payments',
      ]) {
        final alert = PaymentAlert.fromActionableErrors(
          actionableErrors(key),
        ).single;
        expect(alert.isPaymentsInProgress, isTrue, reason: key);
        expect(alert.level, 'danger');
        expect(alert.actionText, 'Check them');
      }
    });

    test('another alert is not mistaken for it', () {
      final alert = PaymentAlert.fromActionableErrors(
        actionableErrors('some_other_problem'),
      ).single;
      expect(alert.isPaymentsInProgress, isFalse);
      expect(alert.message, contains("don't pay"));
    });

    test('an entry with no message is dropped', () {
      expect(
        PaymentAlert.fromActionableErrors({
          'x': {'level': 'danger'},
          'y': 'not a map',
        }),
        isEmpty,
      );
      expect(PaymentAlert.fromActionableErrors(false), isEmpty);
    });
  });
}
