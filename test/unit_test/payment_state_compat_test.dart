import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/models/invoice.dart';
import 'package:mobo_sales/models/payment.dart';

/// `account.payment.state` is not the same list on every Odoo release, and a
/// state a release does not have is not an error: it silently matches nothing.
/// These are the values each release really has (read from the Odoo source).
const _odoo17 = ['draft', 'posted', 'cancel'];
const _odoo18And19 = ['draft', 'in_process', 'paid', 'canceled', 'rejected'];
const _odoo20 = ['draft', 'paid', 'reconciled', 'canceled', 'rejected'];

Payment _payment(String state, {bool isReconciled = false, double? amount}) {
  return Payment.fromJson({
    'id': 1,
    'name': 'PBNK1/2026/0001',
    'amount': amount ?? 100.0,
    'state': state,
    'payment_type': 'inbound',
    'partner_type': 'customer',
    'is_reconciled': isReconciled,
  });
}

void main() {
  group('Payment.parseOdooState', () {
    test('Odoo 17 vocabulary', () {
      expect(Payment.parseOdooState('draft'), OdooPaymentState.draft);
      expect(Payment.parseOdooState('posted'), OdooPaymentState.posted);
      expect(Payment.parseOdooState('cancel'), OdooPaymentState.cancelled);
    });

    test('Odoo 18 and 19 vocabulary', () {
      expect(Payment.parseOdooState('draft'), OdooPaymentState.draft);
      expect(Payment.parseOdooState('in_process'), OdooPaymentState.posted);
      expect(Payment.parseOdooState('paid'), OdooPaymentState.posted);
      expect(Payment.parseOdooState('canceled'), OdooPaymentState.cancelled);
      expect(Payment.parseOdooState('rejected'), OdooPaymentState.cancelled);
    });

    test('Odoo 20 vocabulary', () {
      expect(Payment.parseOdooState('draft'), OdooPaymentState.draft);
      expect(Payment.parseOdooState('paid'), OdooPaymentState.posted);
      expect(Payment.parseOdooState('reconciled'), OdooPaymentState.reconciled);
      expect(Payment.parseOdooState('canceled'), OdooPaymentState.cancelled);
      expect(Payment.parseOdooState('rejected'), OdooPaymentState.cancelled);
    });

    test('keeps the legacy values and ignores case', () {
      expect(Payment.parseOdooState('sent'), OdooPaymentState.sent);
      expect(Payment.parseOdooState('cancelled'), OdooPaymentState.cancelled);
      expect(Payment.parseOdooState('POSTED'), OdooPaymentState.posted);
    });

    test('an unknown state is a draft, as before', () {
      expect(Payment.parseOdooState('something_new'), OdooPaymentState.draft);
      expect(Payment.parseOdooState(''), OdooPaymentState.draft);
    });
  });

  group('Payment.isPostedState', () {
    test('is true for a posted payment on every release', () {
      expect(Payment.isPostedState('posted'), isTrue);
      expect(Payment.isPostedState('in_process'), isTrue);
      expect(Payment.isPostedState('paid'), isTrue);
    });

    test('is false for the other states and for non-strings', () {
      for (final state in [
        'draft',
        'reconciled',
        'cancel',
        'canceled',
        'rejected',
      ]) {
        expect(Payment.isPostedState(state), isFalse, reason: state);
      }
      expect(Payment.isPostedState(null), isFalse);
      expect(Payment.isPostedState(false), isFalse);
    });
  });

  group('Payment.confirmedStates (search domain values)', () {
    test('finds every confirmed payment of every release', () {
      // A search domain that misses one of these is the 17 -> 18 and 19 -> 20
      // regression: it listed no payment at all.
      for (final state in {..._odoo17, ..._odoo18And19, ..._odoo20}) {
        final parsed = Payment.parseOdooState(state);
        final isConfirmed =
            parsed == OdooPaymentState.posted ||
            parsed == OdooPaymentState.reconciled ||
            parsed == OdooPaymentState.sent;
        expect(
          Payment.confirmedStates.contains(state),
          isConfirmed,
          reason: '$state parses as $parsed',
        );
      }
    });

    test('names the states Odoo 20 gives a registered payment', () {
      expect(Payment.confirmedStates, containsAll(['paid', 'reconciled']));
    });

    test('keeps the Odoo 17 values the app always searched for', () {
      expect(Payment.confirmedStates, containsAll(['posted', 'sent']));
    });
  });

  group('Payment status on every release', () {
    test('a registered payment not yet reconciled is "In Payment"', () {
      // 17: posted, 18/19: in_process, 20: paid.
      for (final state in ['posted', 'in_process', 'paid']) {
        final payment = _payment(state);
        expect(payment.isInPayment, isTrue, reason: state);
        expect(payment.isFullyReconciled, isFalse, reason: state);
        expect(payment.statusDisplay, 'In Payment', reason: state);
      }
    });

    test('a reconciled payment is "Reconciled"', () {
      // 17/18/19: posted or paid with is_reconciled, 20: reconciled.
      for (final state in ['posted', 'paid']) {
        final payment = _payment(state, isReconciled: true);
        expect(payment.isFullyReconciled, isTrue, reason: state);
        expect(payment.isInPayment, isFalse, reason: state);
        expect(payment.statusDisplay, 'Reconciled', reason: state);
      }
      final settled = _payment('reconciled');
      expect(settled.isFullyReconciled, isTrue);
      expect(settled.statusDisplay, 'Reconciled');
    });

    test('a cancelled or rejected payment is neither pending nor paid', () {
      for (final state in ['cancel', 'canceled', 'rejected']) {
        final payment = _payment(state);
        expect(payment.isCancelled, isTrue, reason: state);
        expect(payment.isInPayment, isFalse, reason: state);
        expect(payment.isFullyReconciled, isFalse, reason: state);
      }
      expect(_payment('canceled').statusDisplay, 'Cancelled');
      expect(_payment('rejected').statusDisplay, 'Rejected');
    });

    test('a draft payment is a draft', () {
      final payment = _payment('draft');
      expect(payment.isDraft, isTrue);
      expect(payment.statusDisplay, 'Draft');
    });

    test('the raw state is kept for round trips', () {
      expect(_payment('paid').toJson()['state'], 'paid');
      expect(_payment('paid').state, 'paid');
    });
  });

  group('Invoice payment summary on Odoo 20 states', () {
    test('adds paid and pending amounts from the 20 payment states', () {
      final invoice = Invoice.fromJson({
        'id': 7,
        'name': 'INV/2026/0007',
        'state': 'posted',
        'payment_state': 'partial',
        'amount_total': 100.0,
        'payments': [
          {
            'id': 1,
            'name': 'PBNK1/2026/0001',
            'amount': 60.0,
            'state': 'reconciled',
            'payment_type': 'inbound',
            'partner_type': 'customer',
          },
          {
            'id': 2,
            'name': 'PBNK1/2026/0002',
            'amount': 25.0,
            'state': 'paid',
            'is_reconciled': false,
            'payment_type': 'inbound',
            'partner_type': 'customer',
            'requires_manual_reconciliation': true,
          },
        ],
      });

      expect(invoice.paymentSummary.totalPaid, 60.0);
      expect(invoice.paymentSummary.totalPending, 25.0);
      expect(invoice.paymentSummary.totalRemaining, 15.0);
      expect(invoice.requiresReconciliation, isTrue);
      expect(invoice.hasInPaymentTransactions, isTrue);
    });
  });

  group('odooAccountMoveHasChecked', () {
    test('asks for the flag up to Odoo 19, not on Odoo 20', () {
      expect(odooAccountMoveHasChecked(0), isTrue);
      expect(odooAccountMoveHasChecked(17), isTrue);
      expect(odooAccountMoveHasChecked(18), isTrue);
      expect(odooAccountMoveHasChecked(19), isTrue);
      expect(odooAccountMoveHasChecked(20), isFalse);
    });
  });
}
