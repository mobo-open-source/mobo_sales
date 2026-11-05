/// The `account.move` domain behind the invoice list: the move types it lists,
/// the scope it was opened for, the status filters, the dates and the search.
///
/// Pure, so what each filter and each combination returns can be checked
/// without a screen.
///
/// The status filters are alternatives: an invoice is shown when it matches any
/// of the ones switched on. Each is a complete domain of its own, and the
/// alternatives are joined with one `|` per join (n filters take n - 1), not
/// one per token — a filter written as `& a b` is three tokens, and counting
/// tokens produced a domain with too many operators that Odoo rejects.
List<dynamic> invoiceListDomain({
  int? customerId,
  String? saleOrderName,
  bool overdueOnly = false,
  bool unpaidOnly = false,
  Set<String> statusFilters = const {},
  DateTime? startDate,
  DateTime? endDate,
  String searchQuery = '',
  DateTime? today,
}) {
  final domain = <dynamic>[
    [
      'move_type',
      'in',
      ['out_invoice', 'out_refund'],
    ],
  ];

  if (customerId != null) {
    domain.add(['partner_id', '=', customerId]);
  }

  if (saleOrderName != null && saleOrderName.isNotEmpty) {
    domain.add(['invoice_origin', 'ilike', saleOrderName.trim()]);
  }

  if (overdueOnly) {
    domain.addAll([
      ['state', '=', 'posted'],
      [
        'payment_state',
        'in',
        ['not_paid', 'partial'],
      ],
      ['invoice_date_due', '<', _day(today ?? DateTime.now())],
    ]);
  }

  if (unpaidOnly) {
    domain.addAll([
      ['state', '=', 'posted'],
      [
        'payment_state',
        'in',
        ['not_paid', 'partial'],
      ],
    ]);
  }

  final alternatives = <List<dynamic>>[
    for (final filter in statusFilters)
      if (_statusDomain(filter) case final leaves?) leaves,
  ];
  if (alternatives.isNotEmpty) {
    domain.addAll([
      for (var i = 0; i < alternatives.length - 1; i++) '|',
      for (final leaves in alternatives) ...leaves,
    ]);
  }

  if (startDate != null) domain.add(['invoice_date', '>=', _day(startDate)]);
  if (endDate != null) domain.add(['invoice_date', '<=', _day(endDate)]);

  final query = searchQuery.trim();
  if (query.isNotEmpty) {
    domain.addAll([
      '|',
      ['name', 'ilike', query],
      ['partner_id.name', 'ilike', query],
    ]);
  }

  return domain;
}

/// One status filter as a complete domain, or null for a key it does not know.
List<dynamic>? _statusDomain(String filter) {
  switch (filter) {
    case 'draft':
      return [
        ['state', '=', 'draft'],
      ];
    case 'posted':
      // Posted, whatever its payment: Odoo's own "Posted" filter. "Not Paid"
      // below is the narrower one; both used to be the same domain.
      return [
        ['state', '=', 'posted'],
      ];
    case 'paid':
      return [
        ['payment_state', '=', 'paid'],
      ];
    case 'partial':
      return [
        ['payment_state', '=', 'partial'],
      ];
    case 'not_paid':
      return [
        '&',
        ['state', '=', 'posted'],
        ['payment_state', '=', 'not_paid'],
      ];
    case 'in_payment':
      return [
        ['payment_state', '=', 'in_payment'],
      ];
    case 'reversed':
      return [
        ['payment_state', '=', 'reversed'],
      ];
    case 'blocked':
      return [
        ['payment_state', '=', 'blocked'],
      ];
    case 'cancelled':
      return [
        ['state', '=', 'cancel'],
      ];
  }
  return null;
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
