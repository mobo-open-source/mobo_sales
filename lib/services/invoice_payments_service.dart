import 'dart:convert';

import 'odoo_session_manager.dart';
import '../models/payment.dart';
import '../utils/odoo_date.dart';

/// One "Paid on" line of Odoo's payments widget under an invoice's totals
/// (`account.move.invoice_payments_widget`): an amount already matched with
/// the invoice.
class InvoicePaidLine {
  final DateTime? date;
  final double amount;

  /// The journal entry it came from, with its reference, as Odoo shows it in
  /// the line's popover (e.g. `PBNK1/2026/00002 (INV/2026/00011)`).
  final String? reference;

  const InvoicePaidLine({
    required this.date,
    required this.amount,
    this.reference,
  });
}

/// One payment linked to an invoice, as Odoo's Payments list shows it.
class InvoicePaymentRow {
  final int id;
  final String name;
  final DateTime? date;
  final String? journalName;
  final String? methodName;
  final double amount;

  /// The payment's currency code, e.g. `USD`, when Odoo gave one.
  final String? currencyCode;

  /// The raw `account.payment.state` (`in_process`, `paid`, `posted`, ...).
  final String state;

  const InvoicePaymentRow({
    required this.id,
    required this.name,
    required this.date,
    required this.journalName,
    required this.methodName,
    required this.amount,
    required this.currencyCode,
    required this.state,
  });

  /// Whether this payment is registered but not matched with the bank yet
  /// on [generation] — what Odoo's Pay wizard warns about ("Make sure you
  /// don't pay twice").
  ///
  /// The state that means this is named differently per release, so it comes
  /// from [Payment.unmatchedState] rather than from a literal here: on Odoo
  /// 20 the literal `in_process` matches nothing at all, and `paid` means
  /// the opposite of what it means on 18 and 19.
  bool isUnmatchedOn(int generation) =>
      state == Payment.unmatchedState(generation);

  factory InvoicePaymentRow.fromJson(Map<String, dynamic> json) {
    String? m2oName(Object? value) =>
        value is List && value.length > 1 ? value[1].toString() : null;
    final name = json['name'];
    return InvoicePaymentRow(
      id: json['id'] as int,
      name: name is String && name.isNotEmpty ? name : 'Draft Payment',
      date: OdooDate.parseDate(json['date']),
      journalName: m2oName(json['journal_id']),
      methodName: m2oName(json['payment_method_line_id']),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currencyCode: m2oName(json['currency_id']),
      state: json['state'] is String ? json['state'] as String : 'draft',
    );
  }
}

/// What Odoo shows about an invoice's payments.
class InvoicePaymentInfo {
  /// The "Paid on" lines under the totals.
  final List<InvoicePaidLine> paidLines;

  /// The invoice's payments (`account.move.reconciled_payment_ids`), newest
  /// first. Empty on Odoo 17, which has no such field.
  final List<InvoicePaymentRow> payments;

  /// Whether the server has Odoo's Payments button on invoices
  /// (`payment_count`, Odoo 18+). Odoo 17 has none, so neither does the app.
  final bool hasPaymentsButton;

  /// The Odoo generation these states were read from, because the same state
  /// string does not mean the same thing on 18/19 and on 20. 0 when the
  /// server version could not be read, which claims nothing.
  final int generation;

  const InvoicePaymentInfo({
    this.paidLines = const [],
    this.payments = const [],
    this.hasPaymentsButton = false,
    this.generation = 0,
  });

  static const empty = InvoicePaymentInfo();

  /// Payments in progress: what Odoo's Pay wizard warns about.
  List<InvoicePaymentRow> get inProgress =>
      payments.where((p) => p.isUnmatchedOn(generation)).toList();
}

/// Reads an invoice's payments the way Odoo's invoice form shows them.
///
/// Every read goes to the invoice's own links, never to the customer's other
/// payments: a list built from `partner_id` showed payments of other invoices
/// as if they belonged to this one.
class InvoicePaymentsService {
  InvoicePaymentsService._();

  static const _moveFields = [
    'invoice_payments_widget',
    'reconciled_payment_ids',
    'payment_count',
  ];

  static const _paymentFields = [
    'name',
    'date',
    'journal_id',
    'payment_method_line_id',
    'amount',
    'currency_id',
    'state',
  ];

  /// Loads the payment info of the invoice with [invoiceId].
  ///
  /// Throws when the server cannot be reached or refuses the read; callers
  /// decide how to show that. A field the server's version lacks is not an
  /// error: it is left out and the matching part of the info stays empty.
  static Future<InvoicePaymentInfo> fetch(int invoiceId) async {
    final available = await OdooSessionManager.safeCallKw({
      'model': 'account.move',
      'method': 'fields_get',
      'args': [_moveFields],
      'kwargs': {
        'attributes': ['type'],
      },
    });
    final fields = _moveFields
        .where((f) => available is Map && available.containsKey(f))
        .toList();
    if (fields.isEmpty) return InvoicePaymentInfo.empty;

    final moves = await OdooSessionManager.safeCallKw({
      'model': 'account.move',
      'method': 'read',
      'args': [
        [invoiceId],
        fields,
      ],
      'kwargs': {},
    });
    if (moves is! List || moves.isEmpty) return InvoicePaymentInfo.empty;
    final move = Map<String, dynamic>.from(moves.first as Map);

    final paymentIds = (move['reconciled_payment_ids'] is List)
        ? (move['reconciled_payment_ids'] as List).whereType<int>().toList()
        : <int>[];

    var payments = <InvoicePaymentRow>[];
    if (paymentIds.isNotEmpty) {
      final rows = await OdooSessionManager.safeCallKw({
        'model': 'account.payment',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', paymentIds],
          ],
          _paymentFields,
        ],
        // Odoo's own order for payments (`account.payment._order`).
        'kwargs': {'order': 'date desc, name desc'},
      });
      if (rows is List) {
        payments = rows
            .whereType<Map>()
            .map(
              (r) => InvoicePaymentRow.fromJson(Map<String, dynamic>.from(r)),
            )
            .toList();
      }
    }

    return InvoicePaymentInfo(
      paidLines: parsePaymentsWidget(move['invoice_payments_widget']),
      payments: payments,
      hasPaymentsButton: fields.contains('payment_count'),
      generation: await OdooSessionManager.serverGeneration(),
    );
  }

  /// The "Paid on" lines of an `invoice_payments_widget` value.
  ///
  /// Odoo sends `false` when there is nothing to show, a JSON object on 17+,
  /// and a JSON string on older servers; anything unreadable yields no lines
  /// rather than an error, since the totals above them are still right.
  static List<InvoicePaidLine> parsePaymentsWidget(Object? raw) {
    Object? value = raw;
    if (value is String) {
      if (value.isEmpty || value == 'false') return const [];
      try {
        value = jsonDecode(value);
      } catch (_) {
        return const [];
      }
    }
    if (value is! Map) return const [];
    final content = value['content'];
    if (content is! List) return const [];

    final lines = <InvoicePaidLine>[];
    for (final item in content) {
      if (item is! Map) continue;
      final amount = item['amount'];
      if (amount is! num) continue;
      final ref = item['ref'];
      lines.add(
        InvoicePaidLine(
          date: OdooDate.parseDate(item['date']),
          amount: amount.toDouble(),
          reference: ref is String && ref.isNotEmpty ? ref : null,
        ),
      );
    }
    return lines;
  }

  /// Odoo's label for an `account.payment.state` value.
  ///
  /// The table is [Payment.stateLabel], which the rest of the app already
  /// reads payment states through. A second copy here went out of step with
  /// it: it had no case for Odoo 20's `reconciled` and printed the raw
  /// technical word.
  static String stateLabel(String state) => Payment.stateLabel(state);
}
