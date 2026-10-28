import '../utils/odoo_version.dart';

// What differs between Odoo generations in the records the quotation screens
// read and write: sale order lines, fiscal positions, online payment, delivery
// status, attachments, the PDF quote builder and the customer read.
//
// Everything here is a plain function of an Odoo *generation* (see
// `odooGeneration`), so the version decision is made in one place, can be
// tested without a server, and an unknown generation (0) keeps taking the
// path the app took before it knew about versions.

// ---------------------------------------------------------------------------
// sale.order.line renames (Odoo 19)
// ---------------------------------------------------------------------------

/// The `sale.order.line` field names Odoo 19 changed: `product_uom` became
/// `product_uom_id` and `tax_id` became `tax_ids`. Both moved together, so a
/// server has exactly one of the two spellings.
class SaleLineFields {
  const SaleLineFields._(this.uom, this.tax);

  /// The unit-of-measure many2one.
  final String uom;

  /// The taxes many2many.
  final String tax;

  /// Odoo 17 and 18.
  static const legacy = SaleLineFields._('product_uom', 'tax_id');

  /// Odoo 19 and 20.
  static const current = SaleLineFields._('product_uom_id', 'tax_ids');

  /// The spellings worth trying for [generation], most likely first.
  ///
  /// A known generation has one. An unknown one (0) tries the 17/18 names
  /// first, as the app always did, then the 19/20 names, so it still works
  /// against whichever server answers.
  static List<SaleLineFields> candidates(int generation) {
    if (generation == 0) return const [legacy, current];
    return generation >= 19 ? const [current] : const [legacy];
  }
}

/// The `order_line` create commands for the lines of a quote form.
///
/// Each [lines] entry is a form line (`product_id`, `product_name`, `quantity`,
/// `unit_price`, `uom_id`); the unit of measure goes under [uomField], which is
/// `product_uom` up to Odoo 18 and `product_uom_id` from 19 (see
/// [SaleLineFields]). A line without a product is skipped, and a missing unit
/// falls back to id 1, as the form always did. [toId] reads an id out of the
/// loose shapes the form keeps (`7`, `'7'`, `[7, 'Units']`).
List<List<dynamic>> saleOrderLineCommands(
  Iterable<Map<String, dynamic>> lines,
  String uomField,
  int? Function(dynamic value) toId,
) {
  final commands = <List<dynamic>>[];

  for (final line in lines) {
    final productId = toId(line['product_id']);
    if (productId == null) continue;

    commands.add([
      0,
      0,
      {
        'product_id': productId,
        'name': line['product_name'],
        'product_uom_qty': line['quantity'],
        'price_unit': line['unit_price'],
        uomField: toId(line['uom_id']) ?? 1,
      },
    ]);
  }

  return commands;
}

// ---------------------------------------------------------------------------
// Fiscal positions
// ---------------------------------------------------------------------------

/// Whether `account.fiscal.position.tax` (one row per source -> destination
/// tax) exists. Odoo 19 dropped it: a fiscal position now lists its destination
/// taxes in `tax_ids` and the mapping is resolved by `map_tax` on the server.
///
/// The quote form only needs the mapping to estimate tax, and an order created
/// without an explicit `fiscal_position_id` gets the customer's fiscal
/// position and the mapped taxes from Odoo itself. So from 19 the estimate
/// leaves the position to the server, where up to 18 it pinned it to none.
bool saleUsesFiscalPositionTaxModel(int generation) =>
    generation == 0 || generation < 19;

// ---------------------------------------------------------------------------
// Online payment
// ---------------------------------------------------------------------------

/// The `sale.order` fields that say whether online payment is required.
///
/// Up to Odoo 19 that is the boolean `require_payment`. Odoo 20 removed it:
/// payment is required exactly when `prepayment_percent` (which every
/// generation has) is above zero. An unknown generation asks for both and
/// uses whichever the server returns.
List<String> saleOrderPaymentFields(int generation) {
  if (generation == 0) return const ['require_payment', 'prepayment_percent'];
  return generation >= 20
      ? const ['prepayment_percent']
      : const ['require_payment'];
}

/// [row] with `require_payment` filled in from `prepayment_percent` when the
/// server did not send it (Odoo 20). A row that has `require_payment` is
/// returned as it came.
Map<String, dynamic> withRequirePayment(Map<String, dynamic> row) {
  if (row.containsKey('require_payment')) return row;
  final percent = row['prepayment_percent'];
  if (percent is num) row['require_payment'] = percent > 0;
  return row;
}

// ---------------------------------------------------------------------------
// Customer signature
// ---------------------------------------------------------------------------

/// The `sale.order` fields behind the signature tab. They are the same in
/// Odoo 17, 18, 19 and 20 (`require_signature` computed from the company's
/// online-signature setting; `signature` an image stored as an attachment;
/// `signed_by`, `signed_on`), so there is no version switch, only whether the
/// server has them.
const List<String> saleOrderSignatureFields = [
  'require_signature',
  'signed_by',
  'signed_on',
  'signature',
];

/// Whether [value] is a value Odoo would call set, rather than its `false`.
bool _isSet(dynamic value) {
  if (value == null || value == false) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return true;
}

/// Whether the order [row] was read from has a signature on file.
bool _carriesSignature(Map<String, dynamic> row) =>
    _isSet(row['signed_by']) ||
    _isSet(row['signed_on']) ||
    _isSet(row['signature']);

/// Whether the signature tab has anything to offer for the order [row] was
/// read from (a read of [saleOrderSignatureFields], `state` and
/// [saleOrderExpiryField]).
///
/// Either the order can still be signed, or it carries a signature to show.
/// An order that asks for a signature but can no longer be given one — it was
/// confirmed, or it expired — has neither, and a tab holding "Not signed yet"
/// and nothing to press is a dead end a tester rightly reported.
///
/// A server without any of the fields has nothing to read and no tab.
bool saleOrderShowsSignature(Map<String, dynamic> row) {
  if (!saleOrderSignatureFields.any(row.containsKey)) return false;
  return saleOrderHasToBeSigned(row) || _carriesSignature(row);
}

/// The extra field [saleOrderHasToBeSigned] needs beside the signature ones.
///
/// `is_expired` is computed and not stored, so it cannot be searched — but it
/// reads back fine, which is better than re-deriving "past its validity date"
/// here and getting the timezone wrong.
const String saleOrderExpiryField = 'is_expired';

/// Whether Odoo would accept a signature for this order right now.
///
/// This is Odoo's `sale.order._has_to_be_signed()`, which is the same in 17,
/// 18, 19 and 20:
///
/// ```python
/// return (self.state in ['draft', 'sent']
///         and not self.is_expired
///         and self.require_signature
///         and not self.signature)
/// ```
///
/// Odoo enforces it on the portal, the only place a sale order is ever
/// signed; the app asks the same question before offering to capture one, so
/// a confirmed, expired or already-signed order is shown its signature rather
/// than a pen.
///
/// [row] is an order read with [saleOrderSignatureFields], [state] and
/// [saleOrderExpiryField]. A row missing `is_expired` — a server that refused
/// the field — is treated as not expired, which is what the app assumed
/// before it asked at all.
bool saleOrderHasToBeSigned(Map<String, dynamic> row) {
  final state = row['state']?.toString();
  if (state != 'draft' && state != 'sent') return false;
  if (row[saleOrderExpiryField] == true) return false;
  if (row['require_signature'] != true) return false;
  return !_isSet(row['signature']);
}

// ---------------------------------------------------------------------------
// Delivery status
// ---------------------------------------------------------------------------

/// The domain leaf for the list's "Delivered" and "To Deliver" filters.
///
/// `sale.order.delivery_status` is `pending`, `started`, `partial` or `full`
/// in every generation from 17 to 20. A leaf comparing it with any other text
/// matches nothing, silently.
List<dynamic>? deliveryStatusLeaf(String filter) {
  switch (filter) {
    case 'delivered':
      return ['delivery_status', '=', 'full'];
    case 'to_deliver':
      return [
        'delivery_status',
        'in',
        ['pending', 'started', 'partial'],
      ];
  }
  return null;
}

// ---------------------------------------------------------------------------
// Attachments
// ---------------------------------------------------------------------------

/// The `ir.attachment` field a file is stored in.
///
/// Odoo 20 removed `datas` (base64): creating an attachment with it succeeds
/// and stores an *empty* file, with only a server-side warning. The file goes
/// in `raw`, which takes the same base64 text over RPC. Up to 19 `raw` expects
/// raw bytes, so `datas` stays.
String attachmentContentField(int generation) =>
    generation >= 20 ? 'raw' : 'datas';

/// The values for creating a binary attachment on a sale order.
Map<String, dynamic> attachmentCreateValues({
  required int generation,
  required int orderId,
  required String name,
  required String base64Data,
  required String mimetype,
  String? description,
}) {
  return {
    'name': name,
    'type': 'binary',
    attachmentContentField(generation): base64Data,
    'res_model': 'sale.order',
    'res_id': orderId,
    'mimetype': mimetype,
    if (description != null) 'description': description,
  };
}

// ---------------------------------------------------------------------------
// PDF quote builder
// ---------------------------------------------------------------------------

/// Whether the server saves the quote builder selection through the
/// `sale.order.save_included_pdf` method.
///
/// Only Odoo 18 has it (the method is marked dead code there). Odoo 19 and 20
/// removed it and the web client writes `quotation_document_ids` and the lines'
/// `product_document_ids` directly; 17 has no quote builder at all.
bool quoteBuilderSavesViaMethod(int generation) => generation == 18;

/// Whether [error] is the server saying `save_included_pdf` does not exist.
bool quoteBuilderMethodMissing(Object error) {
  final text = error.toString();
  return text.contains('save_included_pdf') &&
      (text.contains('does not exist') ||
          text.contains('has no attribute') ||
          text.contains('AttributeError'));
}

/// The writes that leave a quotation with exactly the chosen quote builder
/// documents.
class QuoteBuilderWrites {
  const QuoteBuilderWrites({
    required this.orderValues,
    required this.lineValues,
  });

  /// Values for `sale.order.write`: the chosen headers and footers.
  final Map<String, dynamic> orderValues;

  /// Values for `sale.order.line.write`, per line id: that line's chosen
  /// product documents. A line with none chosen is written empty, which is how
  /// a document is deselected.
  final Map<int, Map<String, dynamic>> lineValues;
}

/// Builds the direct writes for a quote builder selection.
///
/// [lineIds] is every line that offers documents; a line missing from
/// [productDocsByLine] had all its documents deselected and is cleared.
QuoteBuilderWrites buildQuoteBuilderWrites({
  required Iterable<int> headerIds,
  required Iterable<int> footerIds,
  required Map<int, Set<int>> productDocsByLine,
  required Iterable<int> lineIds,
}) {
  List<int> sorted(Iterable<int> ids) => ({...ids}.toList()..sort());
  final lines = {...lineIds, ...productDocsByLine.keys}.toList()..sort();
  return QuoteBuilderWrites(
    orderValues: {
      'quotation_document_ids': [
        [
          6,
          0,
          sorted([...headerIds, ...footerIds]),
        ],
      ],
    },
    lineValues: {
      for (final id in lines)
        id: {
          'product_document_ids': [
            [6, 0, sorted(productDocsByLine[id] ?? const <int>{})],
          ],
        },
    },
  );
}

// ---------------------------------------------------------------------------
// Partner reads
// ---------------------------------------------------------------------------

/// The `res.partner` fields the quote form reads to show an existing quote's
/// customer. One unknown field fails the whole read, so a field the server has
/// dropped must not be asked for: `company_name` is gone in Odoo 20 (the
/// employer is `parent_id`).
List<String> quoteCustomerFields(int generation) {
  return [
    'name',
    'email',
    'phone',
    'street',
    'street2',
    'city',
    'state_id',
    'zip',
    'country_id',
    'vat',
    odooHasPartnerCompanyName(generation) ? 'company_name' : 'parent_id',
    'image_1920',
  ];
}
