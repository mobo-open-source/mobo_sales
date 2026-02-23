/// Standard Odoo payment states.
enum OdooPaymentState { draft, posted, sent, reconciled, cancelled }

/// Internal reconciliation status within the app.
enum ReconciliationStatus { notRequired, pending, partial, complete, failed }

/// Represents a single reconciliation line linking a payment to an invoice.
class ReconciliationLine {
  final int? id;
  final int paymentId;
  final int invoiceId;
  final double amount;
  final DateTime? reconcileDate;
  final bool isFullReconciliation;

  ReconciliationLine({
    this.id,
    required this.paymentId,
    required this.invoiceId,
    required this.amount,
    this.reconcileDate,
    this.isFullReconciliation = false,
  });

  /// Constructs a [ReconciliationLine] from a raw Odoo JSON map.
  factory ReconciliationLine.fromJson(Map<String, dynamic> json) {
    return ReconciliationLine(
      id: json['id'],
      paymentId: json['payment_id'] is List
          ? json['payment_id'][0]
          : json['payment_id'],
      invoiceId: json['invoice_id'] is List
          ? json['invoice_id'][0]
          : json['invoice_id'],
      amount: (json['amount'] ?? 0.0).toDouble(),
      reconcileDate:
          json['reconcile_date'] != null && json['reconcile_date'] != false
          ? DateTime.parse(json['reconcile_date'])
          : null,
      isFullReconciliation: json['is_full_reconciliation'] ?? false,
    );
  }

  /// Serialises this reconciliation line to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'payment_id': paymentId,
      'invoice_id': invoiceId,
      'amount': amount,
      'reconcile_date': reconcileDate?.toIso8601String(),
      'is_full_reconciliation': isFullReconciliation,
    };
  }
}

/// Represents an `account.payment` record from Odoo.
class Payment {
  final int? id;
  final String name;
  final double amount;
  final String state;
  final String paymentType;
  final String partnerType;
  final int? partnerId;
  final String? partnerName;
  final int? journalId;
  final String? journalName;
  final int? paymentMethodLineId;
  final String? paymentMethodName;
  final DateTime? paymentDate;
  final String? communication;
  final String? reference;
  final int? companyId;
  final List<dynamic>? currencyId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isReconciled;
  final List<int> reconciledInvoiceIds;
  final double reconciledAmount;

  final ReconciliationStatus reconciliationStatus;
  final List<ReconciliationLine> reconciliationLines;
  final DateTime? reconciliationDate;
  final bool requiresManualReconciliation;

  final OdooPaymentState odooState;
  final String? odooReference;
  final Map<String, dynamic>? odooMetadata;

  Payment({
    this.id,
    required this.name,
    required this.amount,
    required this.state,
    required this.paymentType,
    required this.partnerType,
    this.partnerId,
    this.partnerName,
    this.journalId,
    this.journalName,
    this.paymentMethodLineId,
    this.paymentMethodName,
    this.paymentDate,
    this.communication,
    this.reference,
    this.companyId,
    this.currencyId,
    this.createdAt,
    this.updatedAt,
    this.isReconciled = false,
    this.reconciledInvoiceIds = const [],
    this.reconciledAmount = 0.0,
    this.reconciliationStatus = ReconciliationStatus.notRequired,
    this.reconciliationLines = const [],
    this.reconciliationDate,
    this.requiresManualReconciliation = false,
    OdooPaymentState? odooState,
    this.odooReference,
    this.odooMetadata,
  }) : odooState = odooState ?? parseOdooState(state);

  /// Constructs a [Payment] from a raw Odoo JSON map.
  factory Payment.fromJson(Map<String, dynamic> json) {
    final state = json['state'] ?? 'draft';
    final isReconciled = json['is_reconciled'] ?? false;
    final reconciliationLines =
        (json['reconciliation_lines'] as List<dynamic>?)
            ?.map((line) => ReconciliationLine.fromJson(line))
            .toList() ??
        <ReconciliationLine>[];

    return Payment(
      id: json['id'],
      name: (json['name'] != null && json['name'] != false)
          ? json['name'].toString()
          : 'Draft Payment',
      amount: (json['amount'] ?? 0.0).toDouble(),
      state: state,
      paymentType: json['payment_type'] ?? 'inbound',
      partnerType: json['partner_type'] ?? 'customer',
      partnerId: json['partner_id'] is List
          ? json['partner_id'][0]
          : json['partner_id'],
      partnerName: json['partner_id'] is List && json['partner_id'].length > 1
          ? json['partner_id'][1]
          : null,
      journalId: json['journal_id'] is List
          ? json['journal_id'][0]
          : json['journal_id'],
      journalName: json['journal_id'] is List && json['journal_id'].length > 1
          ? json['journal_id'][1]
          : null,
      paymentMethodLineId: json['payment_method_line_id'] is List
          ? json['payment_method_line_id'][0]
          : json['payment_method_line_id'],
      paymentMethodName:
          json['payment_method_line_id'] is List &&
              json['payment_method_line_id'].length > 1
          ? json['payment_method_line_id'][1]
          : null,
      paymentDate: json['date'] != null && json['date'] != false
          ? DateTime.parse(json['date'])
          : null,
      communication:
          (json['communication'] != null && json['communication'] != false)
          ? json['communication'].toString()
          : null,
      reference: (json['ref'] != null && json['ref'] != false)
          ? json['ref'].toString()
          : null,
      companyId: json['company_id'] is List
          ? json['company_id'][0]
          : json['company_id'],
      currencyId: json['currency_id'] as List<dynamic>?,
      createdAt: json['create_date'] != null
          ? DateTime.parse(json['create_date'])
          : null,
      updatedAt: json['write_date'] != null
          ? DateTime.parse(json['write_date'])
          : null,
      isReconciled: isReconciled,
      reconciledInvoiceIds: json['reconciled_invoice_ids'] != null
          ? List<int>.from(json['reconciled_invoice_ids'])
          : [],
      reconciledAmount: (json['reconciled_amount'] ?? 0.0).toDouble(),
      reconciliationStatus: parseReconciliationStatus(
        json['reconciliation_status'],
      ),
      reconciliationLines: reconciliationLines,
      reconciliationDate:
          json['reconciliation_date'] != null &&
              json['reconciliation_date'] != false
          ? DateTime.parse(json['reconciliation_date'])
          : null,
      requiresManualReconciliation:
          json['requires_manual_reconciliation'] ?? false,
      odooState: parseOdooState(state),
      odooReference: json['odoo_reference'],
      odooMetadata: json['odoo_metadata'] as Map<String, dynamic>?,
    );
  }

  /// Serialises this payment to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'state': state,
      'payment_type': paymentType,
      'partner_type': partnerType,
      'partner_id': partnerId,
      'journal_id': journalId,
      'payment_method_line_id': paymentMethodLineId,
      'date': paymentDate?.toIso8601String(),
      'communication': communication,
      'ref': reference,
      'company_id': companyId,
      'currency_id': currencyId,
      'is_reconciled': isReconciled,
      'reconciled_invoice_ids': reconciledInvoiceIds,
      'reconciled_amount': reconciledAmount,
      'reconciliation_status': reconciliationStatus.name,
      'reconciliation_lines': reconciliationLines
          .map((line) => line.toJson())
          .toList(),
      'reconciliation_date': reconciliationDate?.toIso8601String(),
      'requires_manual_reconciliation': requiresManualReconciliation,
      'odoo_state': odooState.name,
      'odoo_reference': odooReference,
      'odoo_metadata': odooMetadata,
    };
  }

  /// Whether this payment is posted but not yet reconciled.
  bool get isInPayment => odooState == OdooPaymentState.posted && !isReconciled;

  /// Whether this payment requires manual reconciliation.
  bool get requiresReconciliation =>
      isInPayment && requiresManualReconciliation;

  /// Returns a user-facing display string for this payment's current status.
  String get statusDisplayText => _getOdooStatusDisplay();

  /// Whether this payment has been fully reconciled.
  bool get isFullyReconciled =>
      (odooState == OdooPaymentState.posted && isReconciled) ||
      odooState == OdooPaymentState.reconciled;

  /// Whether this payment can be manually reconciled in Odoo.
  bool get canReconcile =>
      odooState == OdooPaymentState.posted && !isReconciled;

  /// Whether this payment is in the `draft` state.
  bool get isDraft => odooState == OdooPaymentState.draft;

  /// Whether this payment is in the `posted` state.
  bool get isPosted => odooState == OdooPaymentState.posted;

  /// Whether this payment has been cancelled.
  bool get isCancelled => odooState == OdooPaymentState.cancelled;

  /// Returns the reconciled proportion of this payment as a value between 0 and 1.
  double get reconciliationProgress {
    if (reconciliationLines.isEmpty) return 0.0;
    final totalReconciled = reconciliationLines
        .where((line) => line.isFullReconciliation)
        .fold(0.0, (sum, line) => sum + line.amount);
    return amount > 0 ? (totalReconciled / amount).clamp(0.0, 1.0) : 0.0;
  }

  String _getOdooStatusDisplay() {
    switch (odooState) {
      case OdooPaymentState.draft:
        return 'Draft';
      case OdooPaymentState.posted:
        if (isReconciled) {
          return 'Reconciled';
        } else {
          return 'In Payment';
        }
      case OdooPaymentState.sent:
        return 'Sent';
      case OdooPaymentState.reconciled:
        return 'Reconciled';
      case OdooPaymentState.cancelled:
        return 'Cancelled';
    }
  }

  /// Returns the [OdooPaymentState] corresponding to the [state] string.
  static OdooPaymentState parseOdooState(String state) {
    switch (state.toLowerCase()) {
      case 'draft':
        return OdooPaymentState.draft;
      case 'posted':
        return OdooPaymentState.posted;
      case 'sent':
        return OdooPaymentState.sent;
      case 'reconciled':
        return OdooPaymentState.reconciled;
      case 'cancelled':
        return OdooPaymentState.cancelled;
      default:
        return OdooPaymentState.draft;
    }
  }

  /// Returns the [ReconciliationStatus] corresponding to the [status] string.
  static ReconciliationStatus parseReconciliationStatus(String? status) {
    if (status == null) return ReconciliationStatus.notRequired;
    switch (status.toLowerCase()) {
      case 'not_required':
        return ReconciliationStatus.notRequired;
      case 'pending':
        return ReconciliationStatus.pending;
      case 'partial':
        return ReconciliationStatus.partial;
      case 'complete':
        return ReconciliationStatus.complete;
      case 'failed':
        return ReconciliationStatus.failed;
      default:
        return ReconciliationStatus.notRequired;
    }
  }

  /// Alias for [statusDisplayText] — returns the user-facing payment status string.
  String get statusDisplay => statusDisplayText;
}
