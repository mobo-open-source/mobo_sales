// Drives the real PaymentService against a real Odoo server.
//
// Skipped unless LIVE_ODOO_URL is set, so the ordinary `flutter test` run
// never needs a server. To run it, seed a database (see the invoices json it
// reads), start Odoo, then:
//
//   LIVE_ODOO_URL=http://localhost:8173 LIVE_ODOO_DB=zz_pay19 \
//   LIVE_ODOO_LOGIN=admin LIVE_ODOO_PASSWORD=<password> \
//   LIVE_IDS=/path/to/live_19.json flutter test test/live/payment_live_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/services/payment_service.dart';
import 'package:mobo_sales/services/permission_service.dart';
import 'package:mobo_sales/utils/invoice_payment_rules.dart';
import 'package:odoo_rpc/odoo_rpc.dart';

import '../mocks/mock_services.dart';

final _env = Platform.environment;
final _url = _env['LIVE_ODOO_URL'];

/// How a request to create the payment goes wrong.
enum _Loss { none, answerLostAfterPaid, requestLostBeforeServer }

/// The real client, except that `action_create_payments` can lose its answer
/// (the server did the work) or never reach the server.
class _LossyClient {
  _LossyClient(this.inner);

  final OdooClient inner;
  _Loss loss = _Loss.none;
  int createPaymentCalls = 0;

  Future<dynamic> callKw(Map payload) async {
    final isCreate =
        payload['model'] == 'account.payment.register' &&
        payload['method'] == 'action_create_payments';
    if (!isCreate) return inner.callKw(payload);

    createPaymentCalls++;
    switch (loss) {
      case _Loss.none:
        return inner.callKw(payload);
      case _Loss.answerLostAfterPaid:
        await inner.callKw(payload); // the server records the payment...
        throw TimeoutException('request timed out'); // ...the answer is lost
      case _Loss.requestLostBeforeServer:
        throw TimeoutException('request timed out');
    }
  }
}

void main() {
  late OdooClient odoo;
  late _LossyClient client;
  late Map<String, int> ids;
  late int generation;

  Future<Map<String, dynamic>> invoice(String key) async {
    final rows = await odoo.callKw({
      'model': 'account.move',
      'method': 'read',
      'args': [
        [ids[key]],
        [
          'name',
          'state',
          'payment_state',
          'amount_residual',
          'move_type',
          'partner_id',
        ],
      ],
      'kwargs': {},
    });
    return Map<String, dynamic>.from((rows as List).first as Map);
  }

  /// The payments of the test customer with this [amount], newest first.
  Future<List<Map<String, dynamic>>> paymentsOf(
    String key,
    double amount,
  ) async {
    final inv = await invoice(key);
    final rows = await odoo.callKw({
      'model': 'account.payment',
      'method': 'search_read',
      'args': [
        [
          ['partner_id', '=', (inv['partner_id'] as List).first],
          ['amount', '=', amount],
        ],
        ['amount', 'payment_type', 'journal_id', 'move_id', 'partner_type'],
      ],
      'kwargs': {'order': 'id desc'},
    });
    return [for (final r in rows as List) Map<String, dynamic>.from(r as Map)];
  }

  Future<String> journalType(dynamic journalId) async {
    final rows = await odoo.callKw({
      'model': 'account.journal',
      'method': 'read',
      'args': [
        [(journalId as List).first],
        ['type'],
      ],
      'kwargs': {},
    });
    return (rows as List).first['type'] as String;
  }

  Future<String> moveRef(dynamic moveId) async {
    final rows = await odoo.callKw({
      'model': 'account.move',
      'method': 'read',
      'args': [
        [(moveId as List).first],
        ['ref'],
      ],
      'kwargs': {},
    });
    final ref = (rows as List).first['ref'];
    return ref is String ? ref : '';
  }

  Future<PaymentResult> pay(
    String key,
    double amount, {
    String method = 'bank',
    String memo = '',
  }) => PaymentService.createPaymentWithOdooFlow(
    invoiceId: ids[key]!,
    amount: amount,
    paymentMethod: PaymentMethodData(id: 1, name: method, type: method),
    paymentDate: DateTime.now(),
    options: PaymentOptions(memo: memo),
  );

  final skip = _url == null
      ? 'set LIVE_ODOO_URL to run against a server'
      : null;

  group('against a live Odoo', skip: skip, () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      HttpOverrides.global = null; // the test binding blocks real network calls
      registerFallbackValue(<String, dynamic>{});

      final seed =
          jsonDecode(File(_env['LIVE_IDS']!).readAsStringSync()) as Map;
      ids = Map<String, int>.from(seed['ids'] as Map);
      generation =
          int.tryParse(
            RegExp(r'\d+').firstMatch(seed['version'].toString())!.group(0)!,
          ) ??
          0;

      odoo = OdooClient(_url!);
      await odoo.authenticate(
        _env['LIVE_ODOO_DB']!,
        _env['LIVE_ODOO_LOGIN']!,
        _env['LIVE_ODOO_PASSWORD']!,
      );

      client = _LossyClient(odoo);
      final permissions = MockPermissionService();
      when(
        () => permissions.canCreate('account.payment.register'),
      ).thenAnswer((_) async => true);
      PermissionService.instance = permissions;
      PaymentService.bus = DataChangeBus.forTesting();
      PaymentService.clientProvider = () async => client;
    });

    tearDownAll(() {
      PaymentService.clientProvider = () async => null;
    });

    setUp(() => client.loss = _Loss.none);

    test('a partial payment registers once, with the memo in Odoo\'s own '
        'field, from a bank journal', () async {
      final result = await pay('partial', 300, memo: 'Part 1 of 2');

      expect(result.success, isTrue, reason: result.errorMessage);
      final inv = await invoice('partial');
      expect(inv['amount_residual'], 700);
      expect(inv['payment_state'], 'partial');

      final payments = await paymentsOf('partial', 300);
      expect(payments, hasLength(1));
      expect(payments.first['payment_type'], 'inbound');
      expect(await journalType(payments.first['journal_id']), 'bank');
      expect(await moveRef(payments.first['move_id']), contains('Part 1 of 2'));

      // Register Payment is still offered, by Odoo's own rule.
      expect(
        canRegisterPayment(
          state: inv['state'],
          paymentState: inv['payment_state'],
          amountResidual: (inv['amount_residual'] as num).toDouble(),
          moveType: inv['move_type'],
          majorVersion: generation,
        ),
        isTrue,
      );
    });

    test('the answer to the payment is lost after Odoo recorded it: the '
        'invoice is paid ONCE (the blocker of the review)', () async {
      final owed = ((await invoice('lost_after'))['amount_residual'] as num)
          .toDouble();
      client.loss = _Loss.answerLostAfterPaid;
      client.createPaymentCalls = 0;

      final result = await pay('lost_after', 310);

      expect(client.createPaymentCalls, 1, reason: 'never run a second time');
      expect(result.success, isTrue, reason: 'a payment of 310 now exists');
      expect(
        await paymentsOf('lost_after', 310),
        hasLength(1),
        reason: 'a repeat would have made two',
      );
      // The residual drops by 310 once; Odoo 19 may keep it while the
      // payment is only "in process". It never drops twice.
      final residual = ((await invoice('lost_after'))['amount_residual'] as num)
          .toDouble();
      expect(residual, anyOf(owed, owed - 310));
    });

    test('the request never reaches Odoo: reported as being processed, '
        'nothing is paid', () async {
      client.loss = _Loss.requestLostBeforeServer;
      client.createPaymentCalls = 0;

      final result = await pay('lost_before', 320);

      expect(client.createPaymentCalls, 1);
      expect(result.success, isFalse);
      expect(result.warnings, contains('timeout_but_processing'));
      expect((await invoice('lost_before'))['amount_residual'], 1000);
    });

    test('cash is paid from a cash journal', () async {
      final result = await pay('cash', 400, method: 'cash');

      expect(result.success, isTrue, reason: result.errorMessage);
      final payments = await paymentsOf('cash', 400);
      expect(payments, hasLength(1));
      expect(await journalType(payments.first['journal_id']), 'cash');
      expect((await invoice('cash'))['amount_residual'], 0);
      expect((await invoice('cash'))['payment_state'], 'paid');
    });

    test(
      'a credit note is refunded: an outbound payment, not inbound',
      () async {
        final before = await invoice('refund');
        expect(before['move_type'], 'out_refund');

        final result = await pay('refund', 500);

        expect(result.success, isTrue, reason: result.errorMessage);
        final payments = await paymentsOf('refund', 500);
        expect(payments, hasLength(1));
        expect(payments.first['payment_type'], 'outbound');
        expect(payments.first['partner_type'], 'customer');
        expect((await invoice('refund'))['amount_residual'], 0);
      },
    );

    test('an overpayment is accepted, as Odoo accepts it', () async {
      final result = await pay('over', 150);

      expect(result.success, isTrue, reason: result.errorMessage);
      final payments = await paymentsOf('over', 150);
      expect(payments, hasLength(1));
      final inv = await invoice('over');
      expect(inv['amount_residual'], 0);
    });

    test('a memo typed by the user is the payment\'s memo', () async {
      await pay('memo', 200, memo: 'Cheque 1234');
      final payments = await paymentsOf('memo', 200);
      expect(payments, hasLength(1));
      expect(await moveRef(payments.first['move_id']), contains('Cheque 1234'));
    });

    test(
      'no memo typed: Odoo\'s own memo (the invoice number) is kept',
      () async {
        final inv = await invoice('nomemo');
        await pay('nomemo', 250, memo: '');
        final payments = await paymentsOf('nomemo', 250);
        expect(payments, hasLength(1));
        expect(await moveRef(payments.first['move_id']), contains(inv['name']));
      },
    );

    test('an invoice with nothing left to pay is refused by Odoo with its own '
        'reason, and nothing more is paid', () async {
      final result = await pay('over', 50);

      expect(result.success, isFalse);
      expect(result.warnings, isNot(contains('timeout_but_processing')));
      expect(result.errorMessage, isNotEmpty);
      expect(await paymentsOf('over', 50), isEmpty);
    });

    test('a draft invoice is refused before anything is sent', () async {
      client.createPaymentCalls = 0;
      await expectLater(
        pay('draft', 10),
        throwsA(
          isA<PaymentError>().having(
            (e) => e.message,
            'message',
            contains('must be posted'),
          ),
        ),
      );
      expect(client.createPaymentCalls, 0);
    });

    test('Register Payment is not offered once there is nothing to pay, '
        'whatever the payment state says', () async {
      for (final key in ['cash', 'refund', 'over', 'memo', 'nomemo']) {
        final inv = await invoice(key);
        expect(
          canRegisterPayment(
            state: inv['state'],
            paymentState: inv['payment_state'],
            amountResidual: (inv['amount_residual'] as num).toDouble(),
            moveType: inv['move_type'],
            majorVersion: generation,
          ),
          isFalse,
          reason: '$key is ${inv['payment_state']}',
        );
      }
    });

    test('the currency\'s decimals are read from the server', () async {
      final rows = await odoo.callKw({
        'model': 'res.currency',
        'method': 'search_read',
        'args': [
          [
            ['active', '=', true],
          ],
          ['decimal_places'],
        ],
        'kwargs': {'limit': 1},
      });
      final currency = (rows as List).first as Map;
      expect(
        await PaymentService.currencyDecimals(currency['id'] as int),
        currency['decimal_places'],
      );
    });
  });
}
