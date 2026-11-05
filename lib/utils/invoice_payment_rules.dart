/// When a payment may be registered on an invoice, and in which direction, as
/// Odoo's own Register Payment button and wizard (`account.payment.register`)
/// decide it. Pure, so the rules can be tested without a server.
library;

/// The move types Odoo offers Register Payment on.
const Set<String> kPayableMoveTypes = {
  'out_invoice',
  'out_refund',
  'in_invoice',
  'in_refund',
  'out_receipt',
  'in_receipt',
};

/// The `payment_state` values on which Odoo shows Register Payment.
///
/// Odoo 17 shows it for `not_paid` and `partial` only. Odoo 18 and later also
/// show it for `in_payment` (see the `account_invoice_payment_btn` button of
/// `account_move_views.xml` in each version). `paid`, `reversed`, `blocked` and
/// `invoicing_legacy` never do.
Set<String> payablePaymentStates(int majorVersion) => {
  'not_paid',
  'partial',
  if (majorVersion >= 18) 'in_payment',
};

/// Whether a payment can be registered on an invoice with these values.
///
/// [moveType] may be null when the caller does not know it; it then does not
/// stand in the way. [amountResidual] is what is still to pay: with nothing
/// left, the wizard refuses ("nothing left to pay"), so the app does not offer
/// it. [majorVersion] is the Odoo major version of the server; when it is
/// unknown (0) the stricter Odoo 17 list applies.
bool canRegisterPayment({
  required String state,
  required String paymentState,
  required double amountResidual,
  String? moveType,
  int majorVersion = 0,
}) {
  if (state.toLowerCase() != 'posted') return false;
  if (!payablePaymentStates(
    majorVersion,
  ).contains(paymentState.toLowerCase())) {
    return false;
  }
  if (moveType != null &&
      moveType.isNotEmpty &&
      !kPayableMoveTypes.contains(moveType)) {
    return false;
  }
  return amountResidual > 0;
}

/// The direction of the payment for [moveType]: a customer invoice is paid by
/// an inbound payment, a customer credit note is refunded by an outbound one,
/// and the other way round for vendor documents. Unknown types count as a
/// customer invoice.
({String paymentType, String partnerType}) paymentDirectionFor(
  String? moveType,
) {
  switch (moveType) {
    case 'out_refund':
      return (paymentType: 'outbound', partnerType: 'customer');
    case 'in_invoice':
    case 'in_receipt':
      return (paymentType: 'outbound', partnerType: 'supplier');
    case 'in_refund':
      return (paymentType: 'inbound', partnerType: 'supplier');
    default:
      return (paymentType: 'inbound', partnerType: 'customer');
  }
}

/// Whether [difference] is a real difference in a currency with [decimals]
/// decimal places: what is left after rounding to the currency is not zero.
/// (Odoo's `currency.is_zero`.) A fixed 0.01 was wrong for currencies with
/// three decimals (KWD, BHD) or none (JPY).
bool isPaymentDifference(double difference, int decimals) {
  var scale = 1.0;
  for (var i = 0; i < decimals; i++) {
    scale *= 10;
  }
  return (difference.abs() * scale).round() != 0;
}
