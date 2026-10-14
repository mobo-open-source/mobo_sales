import 'package:flutter/material.dart';

/// How a sale order's `state` reads and looks, wherever the app shows it: the
/// list's cards and the capsule on the details page.
///
/// `draft` is the quotation proper, `sent` a quotation that was emailed, `sale`
/// the confirmed order, `cancel` a cancelled one. `done` is "Locked" and
/// exists in Odoo 17 only: from 18 a locked order stays `sale` and has a
/// `locked` flag instead.
class QuotationStatus {
  const QuotationStatus(this.label, this.color);

  final String label;
  final Color color;

  /// The status for [state]. A state the app does not know reads as its own
  /// name, in [fallback] colour.
  static QuotationStatus of(String state, {required Color fallback}) {
    switch (state) {
      case 'draft':
        return const QuotationStatus('Quotation', Colors.orange);
      case 'sent':
        return const QuotationStatus('Sent', Colors.blue);
      case 'sale':
        return const QuotationStatus('Sale Order', Colors.green);
      case 'done':
        return const QuotationStatus('Locked', Colors.green);
      case 'cancel':
        return const QuotationStatus('Cancelled', Colors.red);
      case 'expired':
        return const QuotationStatus('Expired', Colors.grey);
      default:
        return QuotationStatus(
          state.isNotEmpty
              ? '${state[0].toUpperCase()}${state.substring(1)}'
              : 'Unknown',
          fallback,
        );
    }
  }
}
