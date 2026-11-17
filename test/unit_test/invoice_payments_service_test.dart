import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/models/payment.dart';
import 'package:mobo_sales/services/invoice_payments_service.dart';

void main() {
  group('parsePaymentsWidget', () {
    test('reads the "Paid on" lines Odoo 17+ sends as an object', () {
      final lines = InvoicePaymentsService.parsePaymentsWidget({
        'title': 'Less Payment',
        'outstanding': false,
        'content': [
          {
            'name': 'Customer Payment',
            'amount': 200.0,
            'date': '2026-11-12',
            'ref': 'PBNK1/2026/00002 (INV/2026/00011)',
          },
          {'amount': 21, 'date': false},
        ],
      });

      expect(lines, hasLength(2));
      expect(lines[0].amount, 200.0);
      expect(lines[0].date, DateTime(2026, 11, 12));
      expect(lines[0].reference, 'PBNK1/2026/00002 (INV/2026/00011)');
      expect(lines[1].amount, 21.0);
      expect(lines[1].date, isNull);
    });

    test('reads the JSON string older servers send', () {
      final lines = InvoicePaymentsService.parsePaymentsWidget(
        '{"content": [{"amount": 50.5, "date": "2026-01-02"}]}',
      );
      expect(lines.single.amount, 50.5);
    });

    test('nothing to show yields no lines, never an error', () {
      for (final raw in [false, null, '', 'false', 'not json', 42, {}]) {
        expect(InvoicePaymentsService.parsePaymentsWidget(raw), isEmpty);
      }
      expect(
        InvoicePaymentsService.parsePaymentsWidget({
          'content': [
            'junk',
            {'amount': 'x'},
          ],
        }),
        isEmpty,
      );
    });
  });

  group('payments in progress', () {
    InvoicePaymentRow row(int id, String state) => InvoicePaymentRow.fromJson({
      'id': id,
      'name': 'PAY0000$id',
      'date': '2026-11-17',
      'journal_id': [7, 'Bank'],
      'payment_method_line_id': [3, 'Manual Payment'],
      'amount': 1721.0,
      'currency_id': [2, 'USD'],
      'state': state,
    });

    test('Odoo 18 and 19: in_process is in progress, paid is settled', () {
      for (final generation in [18, 19]) {
        final info = InvoicePaymentInfo(
          payments: [
            row(4, 'in_process'),
            row(5, 'paid'),
            row(6, 'in_process'),
          ],
          hasPaymentsButton: true,
          generation: generation,
        );
        expect(info.inProgress.map((p) => p.id), [
          4,
          6,
        ], reason: 'Odoo $generation');
      }
    });

    test('Odoo 20: paid is in progress and reconciled is settled', () {
      // 20 renamed the pair. `_compute_state` is the same code as 19's: 19
      // promotes in_process --> paid, 20 promotes paid --> reconciled. So
      // `paid` means the opposite thing on the two releases.
      final info = InvoicePaymentInfo(
        payments: [row(4, 'paid'), row(5, 'reconciled'), row(6, 'paid')],
        hasPaymentsButton: true,
        generation: 20,
      );
      expect(info.inProgress.map((p) => p.id), [4, 6]);
    });

    test('a settled payment is never reported as in progress', () {
      expect(
        InvoicePaymentInfo(
          payments: [row(5, 'paid')],
          generation: 19,
        ).inProgress,
        isEmpty,
        reason: 'on 19 `paid` is the settled end of the pair',
      );
      expect(
        InvoicePaymentInfo(
          payments: [row(5, 'reconciled')],
          generation: 20,
        ).inProgress,
        isEmpty,
      );
    });

    test('Odoo 17 states never count as in progress', () {
      final info = InvoicePaymentInfo(
        payments: [row(1, 'posted'), row(2, 'draft'), row(3, 'cancel')],
        generation: 17,
      );
      expect(info.inProgress, isEmpty);
    });

    test('an unreadable server version claims nothing', () {
      final info = InvoicePaymentInfo(
        payments: [row(4, 'in_process'), row(5, 'paid')],
      );
      expect(
        info.inProgress,
        isEmpty,
        reason: 'generation 0 must not guess which release wrote the state',
      );
    });

    test('a row reads Odoo\'s many2one pairs and tolerates false', () {
      final p = row(4, 'in_process');
      expect(p.journalName, 'Bank');
      expect(p.methodName, 'Manual Payment');
      expect(p.currencyCode, 'USD');
      expect(p.date, DateTime(2026, 11, 17));

      final bare = InvoicePaymentRow.fromJson({
        'id': 9,
        'name': false,
        'date': false,
        'journal_id': false,
        'payment_method_line_id': false,
        'amount': 10,
        'currency_id': false,
        'state': false,
      });
      expect(bare.name, 'Draft Payment');
      expect(bare.journalName, isNull);
      expect(bare.date, isNull);
      expect(bare.state, 'draft');
      expect(bare.amount, 10.0);
    });
  });

  group('state labels', () {
    /// Every `account.payment.state` the four supported releases define,
    /// read from Odoo's own selection lists.
    const odooStates = {
      // 17: account.payment _inherits account.move, so these are move states.
      'draft': 'Draft',
      'posted': 'Posted',
      'cancel': 'Cancelled',
      // 18 and 19.
      'in_process': 'In Process',
      'paid': 'Paid',
      'canceled': 'Canceled',
      'rejected': 'Rejected',
      // 20 replaces in_process with reconciled.
      'reconciled': 'Reconciled',
    };

    test('every state Odoo 17 to 20 defines has Odoo\'s own label', () {
      odooStates.forEach((state, label) {
        expect(InvoicePaymentsService.stateLabel(state), label, reason: state);
      });
    });

    test('the service and the rest of the app share one table', () {
      // Two tables drifted apart once already: the second had no case for
      // Odoo 20's `reconciled` and printed the raw technical word.
      for (final state in odooStates.keys) {
        expect(
          InvoicePaymentsService.stateLabel(state),
          Payment.stateLabel(state),
          reason: state,
        );
      }
    });

    test('a state no release defines is shown as it came', () {
      expect(
        InvoicePaymentsService.stateLabel('some_new_state'),
        'some_new_state',
      );
    });
  });
}
