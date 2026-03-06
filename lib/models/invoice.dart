import 'package:flutter/material.dart';
import 'payment.dart';

enum OdooInvoicePaymentState {
  notPaid,
  inPayment,
  paid,
  partial,
  reversed,
  blocked,
}

/// Summarises payment activity for an invoice (amounts paid, pending, remaining).
class PaymentSummary {
  final double totalPaid;
  final double totalPending;
  final double totalRemaining;
  final int paymentCount;
  final DateTime? lastPaymentDate;
  final List<Payment> payments;

  PaymentSummary({
    required this.totalPaid,
    required this.totalPending,
    required this.totalRemaining,
    required this.paymentCount,
    this.lastPaymentDate,
    required this.payments,
  });

  /// Computes a [PaymentSummary] from a list of [payments] and the [invoiceTotal].
  factory PaymentSummary.fromPayments(
    List<Payment> payments,
    double invoiceTotal,
  ) {
    final totalPaid = payments
        .where((p) => p.isFullyReconciled)
        .fold(0.0, (sum, p) => sum + p.amount);

    final totalPending = payments
        .where((p) => p.isInPayment)
        .fold(0.0, (sum, p) => sum + p.amount);

    final totalRemaining = (invoiceTotal - totalPaid - totalPending).clamp(
      0.0,
      double.infinity,
    );

    final lastPaymentDate = payments
        .where((p) => p.paymentDate != null)
        .map((p) => p.paymentDate!)
        .fold<DateTime?>(
          null,
          (latest, date) =>
              latest == null || date.isAfter(latest) ? date : latest,
        );

    return PaymentSummary(
      totalPaid: totalPaid,
      totalPending: totalPending,
      totalRemaining: totalRemaining,
      paymentCount: payments.length,
      lastPaymentDate: lastPaymentDate,
      payments: payments,
    );
  }
}

/// Determines whether an invoice's payments require manual reconciliation in Odoo.
class ReconciliationRequirement {
  final bool isRequired;
  final String reason;
  final List<Payment> pendingPayments;

  ReconciliationRequirement({
    required this.isRequired,
    required this.reason,
    required this.pendingPayments,
  });

  /// Builds a [ReconciliationRequirement] by inspecting the given [payments].
  factory ReconciliationRequirement.fromPayments(List<Payment>? payments) {
    final paymentList = payments ?? <Payment>[];
    final pendingPayments = paymentList
        .where((p) => p.requiresReconciliation)
        .toList();
    final isRequired = pendingPayments.isNotEmpty;

    String reason = '';
    if (isRequired) {
      if (pendingPayments.length == 1) {
        reason = 'Payment requires reconciliation in Odoo';
      } else {
        reason =
            '${pendingPayments.length} payments require reconciliation in Odoo';
      }
    }

    return ReconciliationRequirement(
      isRequired: isRequired,
      reason: reason,
      pendingPayments: pendingPayments,
    );
  }
}

/// Represents an `account.move` invoice from Odoo.
class Invoice {
  final int? id;
  final String name;
  final int? customerId;
  final String customerName;
  final String? customerEmail;
  final String? customerPhone;
  final String? customerAddress;
  final List<InvoiceLine> lines;
  final List<TaxLine> taxLines;
  final double subtotal;
  final double taxAmount;
  final double total;
  final double amountPaid;
  final double amountResidual;
  final String status;
  final String paymentState;
  final bool? isMoveSent;
  final DateTime? invoiceDate;
  final DateTime? dueDate;
  final String? reference;
  final String? origin;
  final String? salesperson;
  final String? paymentTerm;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<dynamic>? currencyId;
  final List<Map<String, dynamic>>? relatedSaleOrders;

  final List<Payment> payments;
  final PaymentSummary paymentSummary;
  final ReconciliationRequirement reconciliationRequirement;

  final OdooInvoicePaymentState odooPaymentState;
  final DateTime? lastPaymentSync;

  Invoice({
    this.id,
    required this.name,
    this.customerId,
    required this.customerName,
    this.customerEmail,
    this.customerPhone,
    this.customerAddress,
    required this.lines,
    required this.taxLines,
    required this.subtotal,
    required this.taxAmount,
    required this.total,
    required this.amountPaid,
    required this.amountResidual,
    required this.status,
    required this.paymentState,
    this.isMoveSent,
    this.invoiceDate,
    this.dueDate,
    this.reference,
    this.origin,
    this.salesperson,
    this.paymentTerm,
    this.createdAt,
    this.updatedAt,
    this.currencyId,
    this.relatedSaleOrders,
    List<Payment>? payments,
    PaymentSummary? paymentSummary,
    ReconciliationRequirement? reconciliationRequirement,
    OdooInvoicePaymentState? odooPaymentState,
    this.lastPaymentSync,
  }) : payments = payments ?? <Payment>[],
       paymentSummary =
           paymentSummary ??
           PaymentSummary.fromPayments(payments ?? <Payment>[], total),
       reconciliationRequirement =
           reconciliationRequirement ??
           ReconciliationRequirement.fromPayments(payments),
       odooPaymentState =
           odooPaymentState ?? parseOdooPaymentState(paymentState);

  /// Constructs an [Invoice] from a raw Odoo JSON map, including lines and payments.
  factory Invoice.fromJson(Map<String, dynamic> json) {
    int? customerId;
    String customerName = 'Unknown';

    if (json['partner_id'] is List && json['partner_id'].isNotEmpty) {
      customerId = json['partner_id'][0];
      customerName =
          (json['partner_id'][1] != null && json['partner_id'][1] != false)
          ? json['partner_id'][1].toString()
          : 'Unknown';
    } else if (json['partner_id'] is int) {
      customerId = json['partner_id'];
    }

    final invoiceName = (json['name'] != false && json['name'] != null)
        ? json['name'].toString()
        : 'Draft';
    final state = (json['state'] != null && json['state'] != false)
        ? json['state'].toString()
        : 'draft';
    final paymentState =
        (json['payment_state'] != null && json['payment_state'] != false)
        ? json['payment_state'].toString()
        : 'unknown';
    final total = (json['amount_total'] ?? 0.0).toDouble();

    final payments =
        (json['payments'] as List<dynamic>?)
            ?.map((payment) {
              if (payment is Map<String, dynamic>) {
                return Payment.fromJson(payment);
              }
              return null;
            })
            .whereType<Payment>()
            .toList() ??
        <Payment>[];

    if (state == 'sent' ||
        invoiceName.toString().contains('00043') ||
        invoiceName.toString().contains('00041')) {}

    return Invoice(
      id: json['id'],
      name: invoiceName,
      customerId: customerId,
      customerName: customerName,
      customerEmail:
          (json['partner_email'] != null && json['partner_email'] != false)
          ? json['partner_email'].toString()
          : null,
      customerPhone:
          (json['partner_phone'] != null && json['partner_phone'] != false)
          ? json['partner_phone'].toString()
          : null,
      customerAddress:
          (json['partner_address'] != null && json['partner_address'] != false)
          ? json['partner_address'].toString()
          : null,
      lines: (json['line_details'] as List<dynamic>?) != null
          ? (json['line_details'] as List<dynamic>)
                .map((line) {
                  if (line is Map<String, dynamic>) {
                    return InvoiceLine.fromJson(line);
                  }
                  return null;
                })
                .whereType<InvoiceLine>()
                .toList()
          : (json['invoice_line_ids'] is List &&
                (json['invoice_line_ids'] as List).isNotEmpty &&
                (json['invoice_line_ids'] as List).first is Map)
          ? (json['invoice_line_ids'] as List<dynamic>)
                .map((line) {
                  if (line is Map<String, dynamic>) {
                    return InvoiceLine.fromJson(line);
                  }
                  return null;
                })
                .whereType<InvoiceLine>()
                .toList()
          : [],
      taxLines:
          (json['tax_line_ids'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map((tax) => TaxLine.fromJson(tax))
              .toList() ??
          [],
      subtotal: (json['amount_untaxed'] ?? 0.0).toDouble(),
      taxAmount: (json['amount_tax'] ?? 0.0).toDouble(),
      total: total,
      amountPaid: (json['amount_paid'] ?? 0.0).toDouble(),
      amountResidual: json['amount_residual'] != null
          ? (json['amount_residual'] as num).toDouble()
          : total,
      status: state,
      paymentState: paymentState,
      isMoveSent: json['is_move_sent'] is bool ? json['is_move_sent'] : null,
      invoiceDate: json['invoice_date'] != false && json['invoice_date'] != null
          ? DateTime.parse(json['invoice_date'].toString())
          : null,
      dueDate:
          json['invoice_date_due'] != false && json['invoice_date_due'] != null
          ? DateTime.parse(json['invoice_date_due'].toString())
          : null,
      reference: (json['ref'] != null && json['ref'] != false)
          ? json['ref'].toString()
          : null,
      origin:
          (json['invoice_origin'] != null && json['invoice_origin'] != false)
          ? json['invoice_origin'].toString()
          : null,
      salesperson: (json['salesperson'] != null && json['salesperson'] != false)
          ? json['salesperson'].toString()
          : null,
      paymentTerm:
          (json['payment_term'] != null && json['payment_term'] != false)
          ? json['payment_term'].toString()
          : null,
      createdAt: (json['create_date'] != null && json['create_date'] != false)
          ? DateTime.parse(json['create_date'].toString())
          : null,
      updatedAt: (json['write_date'] != null && json['write_date'] != false)
          ? DateTime.parse(json['write_date'].toString())
          : null,
      currencyId: json['currency_id'] as List<dynamic>?,
      relatedSaleOrders: json['related_sale_orders'] is List
          ? (json['related_sale_orders'] as List)
                .map((o) => Map<String, dynamic>.from(o))
                .toList()
          : null,
      payments: payments,
      paymentSummary: PaymentSummary.fromPayments(payments, total),
      reconciliationRequirement: ReconciliationRequirement.fromPayments(
        payments,
      ),
      odooPaymentState: parseOdooPaymentState(paymentState),
      lastPaymentSync:
          json['last_payment_sync'] != null &&
              json['last_payment_sync'] != false
          ? DateTime.parse(json['last_payment_sync'].toString())
          : null,
    );
  }

  /// Serialises this invoice to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'partner_id': customerId,
      'partner_email': customerEmail,
      'partner_phone': customerPhone,
      'partner_address': customerAddress,
      'invoice_line_ids': lines.map((line) => line.toJson()).toList(),
      'tax_line_ids': taxLines.map((tax) => tax.toJson()).toList(),
      'amount_untaxed': subtotal,
      'amount_tax': taxAmount,
      'amount_total': total,
      'amount_paid': amountPaid,
      'amount_residual': amountResidual,
      'state': status,
      'payment_state': paymentState,
      'is_move_sent': isMoveSent,
      'invoice_date': invoiceDate?.toIso8601String(),
      'invoice_date_due': dueDate?.toIso8601String(),
      'ref': reference,
      'invoice_origin': origin,
      'salesperson': salesperson,
      'payment_term': paymentTerm,
      'currency_id': currencyId,
      'payments': payments.map((payment) => payment.toJson()).toList(),
      'odoo_payment_state': odooPaymentState.name,
      'last_payment_sync': lastPaymentSync?.toIso8601String(),
    };
  }

  /// Whether any associated payments are currently in the payment process.
  bool get hasInPaymentTransactions => payments.any((p) => p.isInPayment);

  /// Whether this invoice has payments that need to be reconciled in Odoo.
  bool get requiresReconciliation {
    try {
      return reconciliationRequirement.isRequired;
    } catch (e) {
      return payments.any((p) => p.isInPayment);
    }
  }

  /// Returns a user-facing display string for the invoice's current payment status.
  String get paymentStatusDisplay => _getOdooPaymentStatusDisplay();

  /// Whether this invoice is fully paid.
  bool get isPaid => paymentState == 'paid';

  /// Whether this invoice is partially paid.
  bool get isPartiallyPaid => paymentState == 'partial';

  /// Whether this invoice is currently in payment.
  bool get isInPayment => paymentState == 'in_payment';

  /// Whether this invoice has not been paid at all.
  bool get isNotPaid => paymentState == 'not_paid';

  /// Whether this invoice is past its due date and not yet paid.
  bool get isOverdue =>
      dueDate != null && dueDate!.isBefore(DateTime.now()) && !isPaid;

  /// Returns the paid proportion of the total invoice as a value between 0 and 1.
  double get paymentProgress {
    if (total <= 0) return 0.0;
    return (paymentSummary.totalPaid / total).clamp(0.0, 1.0);
  }

  /// Whether this invoice is fully paid according to Odoo's payment state.
  bool get isFullyPaid => odooPaymentState == OdooInvoicePaymentState.paid;

  /// Whether this invoice has only partially paid payments.
  bool get hasPartialPayments =>
      odooPaymentState == OdooInvoicePaymentState.partial;

  /// Whether payments on this invoice are currently blocked.
  bool get hasBlockedPayments =>
      odooPaymentState == OdooInvoicePaymentState.blocked;

  /// Whether payments on this invoice have been reversed.
  bool get hasReversedPayments =>
      odooPaymentState == OdooInvoicePaymentState.reversed;

  String _getOdooPaymentStatusDisplay() {
    if (name.contains('00043') || name.contains('00041') || status == 'sent') {}

    switch (status.toLowerCase()) {
      case 'draft':
        return 'Draft';
      case 'cancel':
        return 'Cancelled';
      case 'sent':
        if (name.contains('00043') || name.contains('00041')) {}
        return 'Sent';
      case 'posted':
        switch (paymentState.toLowerCase()) {
          case 'paid':
            return 'Paid';
          case 'partial':
            return 'Partially Paid';
          case 'reversed':
            return 'Reversed';
          case 'in_payment':
            return 'In Payment';
          case 'blocked':
            return 'Blocked';
          default:
            if (isMoveSent == true) {
              if (name.contains('00043') || name.contains('00041')) {}
              return 'Sent';
            }

            return 'Posted';
        }
      default:
        if (name.contains('00043') || name.contains('00041')) {}
        return status;
    }
  }

  /// Returns the [OdooInvoicePaymentState] corresponding to the [paymentState] string.
  static OdooInvoicePaymentState parseOdooPaymentState(String paymentState) {
    switch (paymentState.toLowerCase()) {
      case 'not_paid':
        return OdooInvoicePaymentState.notPaid;
      case 'in_payment':
        return OdooInvoicePaymentState.inPayment;
      case 'paid':
        return OdooInvoicePaymentState.paid;
      case 'partial':
        return OdooInvoicePaymentState.partial;
      case 'reversed':
        return OdooInvoicePaymentState.reversed;
      case 'blocked':
        return OdooInvoicePaymentState.blocked;
      default:
        return OdooInvoicePaymentState.notPaid;
    }
  }

  Color get paymentStatusColor {
    switch (status.toLowerCase()) {
      case 'draft':
        return const Color(0xFF17A2B8);
      case 'cancel':
        return const Color(0xFFF44336);
      case 'sent':
        return const Color(0xFF6C757D);
      case 'posted':
        switch (paymentState.toLowerCase()) {
          case 'paid':
            return const Color(0xFF4CAF50);
          case 'partial':
            return const Color(0xFFFF9800);
          case 'reversed':
            return const Color(0xFF4CAF50);
          case 'in_payment':
            return const Color(0xFF4CAF50);
          case 'blocked':
            return const Color(0xFF9C27B0);
          default:
            return const Color(0xFF6C757D);
        }
      default:
        return const Color(0xFF6C757D);
    }
  }
}

/// Represents a single line on an `account.move` invoice.
class InvoiceLine {
  final int? id;
  final int? productId;
  final String? productName;
  final double quantity;
  final double unitPrice;
  final double? discount;
  final double subtotal;
  final String? description;

  InvoiceLine({
    this.id,
    this.productId,
    this.productName,
    required this.quantity,
    required this.unitPrice,
    this.discount,
    required this.subtotal,
    this.description,
  });

  /// Constructs an [InvoiceLine] from a raw Odoo JSON map.
  factory InvoiceLine.fromJson(Map<String, dynamic> json) {
    int? productId;
    String? productName;

    if (json['product_id'] is List && json['product_id'].isNotEmpty) {
      productId = json['product_id'][0];
      productName =
          (json['product_id'][1] != null && json['product_id'][1] != false)
          ? json['product_id'][1].toString()
          : null;
    } else if (json['product_id'] is int) {
      productId = json['product_id'];
    }

    return InvoiceLine(
      id: json['id'] is int ? json['id'] : null,
      productId: productId,
      productName: productName,
      quantity: (json['quantity'] as num? ?? 0.0).toDouble(),
      unitPrice: (json['price_unit'] as num? ?? 0.0).toDouble(),
      discount: (json['discount'] as num? ?? 0.0).toDouble(),
      subtotal: (json['price_subtotal'] as num? ?? 0.0).toDouble(),
      description: (json['name'] != null && json['name'] != false)
          ? json['name'].toString()
          : '',
    );
  }

  /// Serialises this invoice line to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'quantity': quantity,
      'price_unit': unitPrice,
      'discount': discount,
      'price_subtotal': subtotal,
      'name': description,
    };
  }
}

/// Represents a tax summary line on an invoice.
class TaxLine {
  final int? id;
  final String name;
  final double taxRate;
  final double amount;

  TaxLine({
    this.id,
    required this.name,
    required this.taxRate,
    required this.amount,
  });

  /// Constructs a [TaxLine] from a raw Odoo JSON map.
  factory TaxLine.fromJson(Map<String, dynamic> json) {
    return TaxLine(
      id: json['id'],
      name: json['name'] ?? 'Unknown Tax',
      taxRate: (json['tax_rate'] ?? 0.0).toDouble(),
      amount: (json['amount'] ?? 0.0).toDouble(),
    );
  }

  /// Serialises this tax line to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'tax_rate': taxRate, 'amount': amount};
  }
}
