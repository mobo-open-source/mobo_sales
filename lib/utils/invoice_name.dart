/// What to call an invoice: its number once it has one, otherwise its state.
///
/// A draft invoice has no number yet. Odoo 17 leaves `name` as `/`, Odoo 18 to
/// 20 as `False` (which arrives as the text "false" if turned into a string
/// carelessly). The number is given when the invoice is posted, so until then
/// the invoice is called by what it is — "Draft", as Odoo itself does.
String invoiceDisplayName(Object? name, Object? state) {
  if (name is String) {
    final text = name.trim();
    if (text.isNotEmpty && text != '/' && text.toLowerCase() != 'false') {
      return text;
    }
  }
  switch (state) {
    case 'posted':
      return 'Posted';
    case 'cancel':
      return 'Cancelled';
    default:
      return 'Draft';
  }
}

/// Whether [displayName] (from [invoiceDisplayName]) is a number the invoice
/// was given, as opposed to the state it is called by while it has none.
bool invoiceHasNumber(String displayName) =>
    !const {'Draft', 'Posted', 'Cancelled'}.contains(displayName);

/// The sentence that says an invoice was created: with its number when it has
/// one ("Invoice INV/2026/0001 created successfully"), without when it is a
/// draft ("Invoice created successfully"). [kind] is "Invoice" or "Draft
/// invoice".
String invoiceCreatedMessage(String displayName, {String kind = 'Invoice'}) =>
    invoiceHasNumber(displayName)
    ? '$kind $displayName created successfully'
    : '$kind created successfully';
