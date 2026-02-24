/// Represents a sale order (quotation) from Odoo.
class Quote {
  final int? id;
  final String name;
  final int? customerId;
  final String? customerName;
  final List<QuoteLine> lines;
  final double subtotal;
  final double taxAmount;
  final double total;
  final String status;
  final DateTime? dateOrder;
  final DateTime? validityDate;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<Map<String, dynamic>>? relatedInvoices;
  final String? invoiceStatus;
  final dynamic currencyId;
  final String? currencyName;
  final Map<String, dynamic>? extraData;

  Quote({
    this.id,
    required this.name,
    this.customerId,
    this.customerName,
    required this.lines,
    required this.subtotal,
    required this.taxAmount,
    required this.total,
    required this.status,
    this.dateOrder,
    this.validityDate,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.relatedInvoices,
    this.invoiceStatus,
    this.currencyId,
    this.currencyName,
    this.extraData,
  });

  /// Constructs a [Quote] from a raw Odoo JSON map, including its order lines.
  factory Quote.fromJson(Map<String, dynamic> json) {
    return Quote(
      id: json['id'],
      name: (json['name'] != null && json['name'] != false)
          ? json['name'].toString()
          : '',
      customerId:
          json['partner_id'] is List && (json['partner_id'] as List).isNotEmpty
          ? json['partner_id'][0]
          : (json['partner_id'] is int ? json['partner_id'] : null),
      customerName:
          json['partner_id'] is List && (json['partner_id'] as List).length > 1
          ? json['partner_id'][1]?.toString()
          : null,
      lines:
          (json['order_line'] as List<dynamic>?)
              ?.map((line) {
                if (line is Map<String, dynamic>) {
                  return QuoteLine.fromJson(line);
                }

                return null;
              })
              .whereType<QuoteLine>()
              .toList() ??
          [],
      subtotal: (json['amount_untaxed'] ?? 0.0).toDouble(),
      taxAmount: (json['amount_tax'] ?? 0.0).toDouble(),
      total: (json['amount_total'] ?? 0.0).toDouble(),
      status: (json['state'] != null && json['state'] != false)
          ? json['state'].toString()
          : 'draft',
      dateOrder: (json['date_order'] != null && json['date_order'] != false)
          ? DateTime.parse(json['date_order'].toString())
          : null,
      validityDate:
          (json['validity_date'] != null && json['validity_date'] != false)
          ? DateTime.parse(json['validity_date'].toString())
          : null,
      notes: (json['note'] != null && json['note'] != false)
          ? json['note'].toString()
          : null,
      createdAt: (json['create_date'] != null && json['create_date'] != false)
          ? DateTime.parse(json['create_date'].toString())
          : null,
      updatedAt: (json['write_date'] != null && json['write_date'] != false)
          ? DateTime.parse(json['write_date'].toString())
          : null,
      relatedInvoices: json['related_invoices'] is List
          ? (json['related_invoices'] as List)
                .map((i) => Map<String, dynamic>.from(i))
                .toList()
          : null,
      invoiceStatus:
          (json['invoice_status'] != null && json['invoice_status'] != false)
          ? json['invoice_status'].toString()
          : null,
      currencyId: json['currency_id'],
      currencyName:
          json['currency_id'] is List &&
              (json['currency_id'] as List).length > 1
          ? json['currency_id'][1]?.toString()
          : null,
      extraData: json,
    );
  }

  /// Serialises this quotation to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    final map = {
      'id': id,
      'name': name,
      'partner_id': customerId,
      'order_line': lines.map((line) => line.toJson()).toList(),
      'amount_untaxed': subtotal,
      'amount_tax': taxAmount,
      'amount_total': total,
      'state': status,
      'date_order': dateOrder?.toIso8601String(),
      'validity_date': validityDate?.toIso8601String(),
      'note': notes,
      'invoice_status': invoiceStatus,
    };
    if (extraData != null) {
      map.addAll(extraData!);
    }
    return map;
  }
}

/// Represents a single line item within a [Quote].
class QuoteLine {
  final int? id;
  final int? productId;
  final String? productName;
  final double quantity;
  final double unitPrice;
  final double subtotal;
  final String? description;

  QuoteLine({
    this.id,
    this.productId,
    this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    this.description,
  });

  /// Constructs a [QuoteLine] from a raw Odoo JSON map.
  factory QuoteLine.fromJson(Map<String, dynamic> json) {
    return QuoteLine(
      id: json['id'],
      productId: json['product_id']?[0],
      productName: json['product_id']?[1],
      quantity: (json['product_uom_qty'] ?? 0.0).toDouble(),
      unitPrice: (json['price_unit'] ?? 0.0).toDouble(),
      subtotal: (json['price_subtotal'] ?? 0.0).toDouble(),
      description: json['name'],
    );
  }

  /// Serialises this line item to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'product_uom_qty': quantity,
      'price_unit': unitPrice,
      'price_subtotal': subtotal,
      'name': description,
    };
  }

  /// Returns a copy of this line with the specified fields overridden.
  QuoteLine copyWith({
    int? id,
    int? productId,
    String? productName,
    double? quantity,
    double? unitPrice,
    double? subtotal,
    String? description,
  }) {
    return QuoteLine(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      subtotal: subtotal ?? this.subtotal,
      description: description ?? this.description,
    );
  }
}

/// Extension providing [copyWith] on [Quote].
extension QuoteExtension on Quote {
  /// Returns a copy of this quotation with the specified fields overridden.
  Quote copyWith({
    int? id,
    String? name,
    int? customerId,
    String? customerName,
    List<QuoteLine>? lines,
    double? subtotal,
    double? taxAmount,
    double? total,
    String? status,
    DateTime? dateOrder,
    DateTime? validityDate,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Map<String, dynamic>>? relatedInvoices,
    String? invoiceStatus,
    Map<String, dynamic>? extraData,
  }) {
    return Quote(
      id: id ?? this.id,
      name: name ?? this.name,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      lines: lines ?? this.lines,
      subtotal: subtotal ?? this.subtotal,
      taxAmount: taxAmount ?? this.taxAmount,
      total: total ?? this.total,
      status: status ?? this.status,
      dateOrder: dateOrder ?? this.dateOrder,
      validityDate: validityDate ?? this.validityDate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      relatedInvoices: relatedInvoices ?? this.relatedInvoices,
      invoiceStatus: invoiceStatus ?? this.invoiceStatus,
      extraData: extraData ?? this.extraData,
    );
  }
}
