import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/invoice_payment_rules.dart';

void main() {
  bool can({
    String state = 'posted',
    String paymentState = 'not_paid',
    double residual = 100,
    String? moveType = 'out_invoice',
    int version = 19,
  }) => canRegisterPayment(
    state: state,
    paymentState: paymentState,
    amountResidual: residual,
    moveType: moveType,
    majorVersion: version,
  );

  group('when Register Payment is offered (Odoo account_move_views.xml)', () {
    test('a posted, unpaid or partly paid invoice can be paid', () {
      for (final v in [17, 18, 19, 20]) {
        expect(can(version: v), isTrue);
        expect(can(paymentState: 'partial', version: v), isTrue);
      }
    });

    test('in_payment is offered from Odoo 18, not on 17', () {
      expect(can(paymentState: 'in_payment', version: 17), isFalse);
      for (final v in [18, 19, 20]) {
        expect(can(paymentState: 'in_payment', version: v), isTrue);
      }
    });

    test('an unknown version takes the stricter Odoo 17 list', () {
      expect(can(paymentState: 'in_payment', version: 0), isFalse);
      expect(can(version: 0), isTrue);
    });

    test('paid, reversed, blocked and legacy invoices are not offered', () {
      for (final state in ['paid', 'reversed', 'blocked', 'invoicing_legacy']) {
        for (final v in [17, 18, 19, 20]) {
          expect(
            can(paymentState: state, version: v),
            isFalse,
            reason: '$state on $v',
          );
        }
      }
    });

    test('a draft or cancelled invoice is not offered', () {
      expect(can(state: 'draft'), isFalse);
      expect(can(state: 'cancel'), isFalse);
    });

    test('nothing left to pay is not offered', () {
      expect(can(residual: 0), isFalse);
    });

    test('only payable kinds of document are offered', () {
      for (final type in kPayableMoveTypes) {
        expect(can(moveType: type), isTrue, reason: type);
      }
      expect(can(moveType: 'entry'), isFalse);
      expect(can(moveType: null), isTrue, reason: 'unknown does not block');
    });
  });

  group('the direction of the payment', () {
    test('a customer invoice is collected', () {
      final d = paymentDirectionFor('out_invoice');
      expect(d.paymentType, 'inbound');
      expect(d.partnerType, 'customer');
    });

    test('a customer credit note is refunded: outbound', () {
      final d = paymentDirectionFor('out_refund');
      expect(d.paymentType, 'outbound');
      expect(d.partnerType, 'customer');
    });

    test('vendor documents go the other way round', () {
      expect(paymentDirectionFor('in_invoice').paymentType, 'outbound');
      expect(paymentDirectionFor('in_invoice').partnerType, 'supplier');
      expect(paymentDirectionFor('in_refund').paymentType, 'inbound');
    });
  });

  group('what counts as a payment difference', () {
    test('two decimals: a cent is a difference, noise is not', () {
      expect(isPaymentDifference(0.01, 2), isTrue);
      expect(isPaymentDifference(0.004, 2), isFalse);
      expect(isPaymentDifference(-0.01, 2), isTrue);
      expect(isPaymentDifference(0, 2), isFalse);
    });

    test('three decimals (KWD, BHD): 0.005 is a difference', () {
      expect(isPaymentDifference(0.005, 3), isTrue);
      expect(isPaymentDifference(0.005, 2), isTrue);
      expect(isPaymentDifference(0.0004, 3), isFalse);
    });

    test('no decimals (JPY): under a half yen is not', () {
      expect(isPaymentDifference(1, 0), isTrue);
      expect(isPaymentDifference(0.4, 0), isFalse);
    });
  });
}
