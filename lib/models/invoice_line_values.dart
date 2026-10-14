// How a line of the invoice form becomes `account.move.line` values, and how an
// `account.move.line` row becomes a line of the form again.
//
// The fields involved are the same in Odoo 17, 18, 19 and 20 (account_move_line.py
// in each tree): `product_id`, `product_uom_id`, `name`, `quantity`,
// `price_unit`, `discount`, `tax_ids` and `display_type`. What differs between
// the versions is not the names but how much a careless value costs: Odoo 20
// fails with `'int' object has no attribute 'origin'` on a line whose
// `product_id` is `0`, so a line without a product must say so by leaving the
// field out, never by sending an id of 0 (or a null unit of measure).

/// A positive record id out of the loose shapes Odoo and the form use: `7`,
/// `'7'`, `[7, 'Name']`. Null for `false`, `0`, a negative number, or anything
/// else — "no record".
int? _recordId(Object? value) {
  if (value is List) {
    return value.isEmpty ? null : _recordId(value.first);
  }
  final id = value is num ? value.toInt() : int.tryParse('$value');
  return id != null && id > 0 ? id : null;
}

/// The two `display_type`s that make a line a heading or a remark instead of a
/// billed item.
bool _isNote(Object? displayType) =>
    displayType == 'line_section' || displayType == 'line_note';

/// A line of the invoice form, as the provider keeps it, from an
/// `account.move.line` [row] read with `product_id`, `name`, `quantity`,
/// `price_unit`, `discount`, `display_type`, `product_uom_id` and `tax_ids`.
///
/// The line keeps everything the row said about itself — its own taxes, unit of
/// measure, discount and description — and its id (`move_line_id`), so saving
/// the form changes that line and does not replace it. A line with no product
/// (a down payment, a free-text item) has no `product_id`; a section or a note
/// has a `display_type`.
Map<String, dynamic> invoiceLineFromMoveLine(Map<String, dynamic> row) {
  final productId = _recordId(row['product_id']);
  final productName =
      row['product_id'] is List &&
          (row['product_id'] as List).length > 1 &&
          row['product_id'][1] != null
      ? row['product_id'][1].toString()
      : null;
  final name = row['name'] is String && (row['name'] as String).isNotEmpty
      ? row['name'] as String
      : null;
  final quantity = (row['quantity'] as num?)?.toDouble() ?? 1.0;
  final unitPrice = (row['price_unit'] as num?)?.toDouble() ?? 0.0;
  final displayType = _isNote(row['display_type'])
      ? row['display_type'] as String
      : null;
  final uomId = _recordId(row['product_uom_id']);
  final taxes = row['tax_ids'] is List
      ? [
          for (final tax in row['tax_ids'] as List)
            if (_recordId(tax) != null) _recordId(tax)!,
        ]
      : <int>[];
  final label = productName ?? name ?? 'Unnamed line';

  return {
    if (_recordId(row['id']) != null) 'move_line_id': _recordId(row['id']),
    'display_type': ?displayType,
    'product_id': productId,
    'product_name': label,
    // What the invoice says on the line, kept when it is more than the
    // product's name.
    'description': ?(name != null && name != label ? name : null),
    'quantity': displayType != null ? 0.0 : quantity,
    'unit_price': displayType != null ? 0.0 : unitPrice,
    'subtotal': displayType != null ? 0.0 : quantity * unitPrice,
    'tax_ids': taxes,
    'product_uom_id': ?uomId,
    'discount': (row['discount'] as num?)?.toDouble() ?? 0.0,
    'product_data': {'id': productId, 'name': label, 'list_price': unitPrice},
  };
}

/// The `account.move.line` values for [line], a line of the form.
///
/// A section or a note is its type and its text. Any other line is its text,
/// quantity and unit price, plus what it has: the product and its unit of
/// measure only when they are real records, a discount only when there is one.
/// Taxes go in as an explicit set (`tax_ids`) when [withTaxes] is true — the
/// form knows its lines' taxes, so what is saved is what the user saw — and
/// for a line without a product always, since there is no product to say which
/// apply. [forUpdate] leaves `display_type` out: it is set when a line is
/// created and is not Odoo's to change afterwards.
Map<String, dynamic> invoiceLineValues(
  Map<String, dynamic> line, {
  bool withTaxes = true,
  bool forUpdate = false,
}) {
  final displayType = _isNote(line['display_type'])
      ? line['display_type'] as String
      : null;
  final description = line['description'];
  final label = description is String && description.isNotEmpty
      ? description
      : line['product_name']?.toString() ?? '';

  if (displayType != null) {
    return {if (!forUpdate) 'display_type': displayType, 'name': label};
  }

  final productId = _recordId(line['product_id']);
  final uomId = productId == null ? null : _recordId(line['product_uom_id']);
  final discount = (line['discount'] as num?)?.toDouble() ?? 0.0;
  final taxIds = line['tax_ids'] is List
      ? [
          for (final tax in line['tax_ids'] as List)
            if (_recordId(tax) != null) _recordId(tax)!,
        ]
      : <int>[];

  return {
    'name': label,
    'quantity': (line['quantity'] as num?)?.toDouble() ?? 1.0,
    'price_unit': (line['unit_price'] as num?)?.toDouble() ?? 0.0,
    'product_id': ?productId,
    'product_uom_id': ?uomId,
    if (discount != 0) 'discount': discount,
    if (withTaxes || productId == null)
      'tax_ids': [
        [6, 0, taxIds],
      ],
  };
}

/// The `invoice_line_ids` commands that turn the invoice's [existingLineIds]
/// into [lines].
///
/// A line that came from the invoice (it has a `move_line_id`) is updated in
/// place — `[1, id, values]` — so what Odoo hangs on it stays: the link to the
/// sale order line it bills, its analytic distribution. A new line is created
/// (`[0, 0, values]`); an existing one the form no longer has is deleted
/// (`[2, id, false]`).
List<List<dynamic>> invoiceLineCommands(
  Iterable<int> existingLineIds,
  Iterable<Map<String, dynamic>> lines,
) {
  final existing = existingLineIds.toSet();
  final kept = <int>{};
  final commands = <List<dynamic>>[];

  for (final line in lines) {
    final id = _recordId(line['move_line_id']);
    if (id != null && existing.contains(id)) {
      kept.add(id);
      commands.add([1, id, invoiceLineValues(line, forUpdate: true)]);
    } else {
      commands.add([0, 0, invoiceLineValues(line)]);
    }
  }

  return [
    for (final id in existing)
      if (!kept.contains(id)) [2, id, false],
    ...commands,
  ];
}
