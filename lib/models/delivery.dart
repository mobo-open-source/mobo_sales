/// Represents a stock picking (delivery, receipt, or internal transfer) from Odoo.
class Delivery {
  final int id;
  final String name;
  final String state;
  final String? partnerName;
  final int? partnerId;
  final String? scheduledDate;
  final String? dateDeadline;
  final String? origin;
  final String pickingTypeCode;
  final String? locationName;
  final String? locationDestName;
  final int? pickingTypeId;

  Delivery({
    required this.id,
    required this.name,
    required this.state,
    this.partnerName,
    this.partnerId,
    this.scheduledDate,
    this.dateDeadline,
    this.origin,
    required this.pickingTypeCode,
    this.locationName,
    this.locationDestName,
    this.pickingTypeId,
  });

  /// Constructs a [Delivery] from a raw Odoo JSON map.
  factory Delivery.fromJson(Map<String, dynamic> json) {
    return Delivery(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'N/A',
      state: json['state'] as String? ?? 'draft',
      partnerName:
          json['partner_id'] is List && (json['partner_id'] as List).length > 1
          ? json['partner_id'][1] as String
          : null,
      partnerId:
          json['partner_id'] is List && (json['partner_id'] as List).isNotEmpty
          ? json['partner_id'][0] as int
          : json['partner_id'] as int?,
      scheduledDate: json['scheduled_date'] as String?,
      dateDeadline: json['date_deadline'] as String?,
      origin: json['origin'] as String?,
      pickingTypeCode: json['picking_type_code'] as String? ?? 'outgoing',
      locationName:
          json['location_id'] is List &&
              (json['location_id'] as List).length > 1
          ? json['location_id'][1] as String
          : null,
      locationDestName:
          json['location_dest_id'] is List &&
              (json['location_dest_id'] as List).length > 1
          ? json['location_dest_id'][1] as String
          : null,
      pickingTypeId:
          json['picking_type_id'] is List &&
              (json['picking_type_id'] as List).isNotEmpty
          ? json['picking_type_id'][0] as int
          : json['picking_type_id'] as int?,
    );
  }

  /// Returns a human-readable label for the current [state] (e.g. 'Ready', 'Done').
  String getStateLabel() {
    switch (state) {
      case 'draft':
        return 'Draft';
      case 'waiting':
        return 'Waiting';
      case 'confirmed':
        return 'Confirmed';
      case 'assigned':
        return 'Ready';
      case 'done':
        return 'Done';
      case 'cancel':
        return 'Cancelled';
      default:
        return state;
    }
  }

  /// Returns a human-readable label for the picking type (e.g. 'Delivery', 'Receipt').
  String getTypeLabel() {
    switch (pickingTypeCode) {
      case 'incoming':
        return 'Receipt';
      case 'outgoing':
        return 'Delivery';
      case 'internal':
        return 'Internal Transfer';
      default:
        return pickingTypeCode;
    }
  }
}

// ---------------------------------------------------------------------------
// Field names that differ between Odoo versions. Plain functions of an Odoo
// generation (see `odooGeneration` in utils/odoo_version.dart), so the version
// decision can be tested without a server.
// ---------------------------------------------------------------------------

/// The `stock.picking` one2many that lists a picking's moves, for an Odoo
/// [generation].
///
/// Odoo 17 and 18 read the operations list from `move_ids_without_package`
/// (the moves outside a package level). Odoo 19 dropped that field and lists
/// `move_ids` directly, so asking for the old name there fails the whole read.
/// An unknown generation (0) keeps the older name; the caller prunes a field
/// the server rejects.
String pickingMovesField(int generation) =>
    generation >= 19 ? 'move_ids' : 'move_ids_without_package';

/// The `stock.move` unit-of-measure field to read, for an Odoo [generation],
/// in the order to try them.
///
/// The field was `product_uom` up to Odoo 19 and is `uom_id` from 20, where
/// the old name no longer exists. An unknown generation (0) tries the older
/// name first, then the newer.
List<String> stockMoveUomFields(int generation) {
  if (generation >= 20) return const ['uom_id'];
  if (generation == 0) return const ['product_uom', 'uom_id'];
  return const ['product_uom'];
}

/// The context a picking must be confirmed or reserved with, for an Odoo
/// [generation].
///
/// Odoo 20 added a zero-demand check to `stock.picking.action_confirm`: a
/// picking holding a move with no demand opens a wizard instead of
/// confirming, and over RPC that wizard comes back as a window action rather
/// than an error. `skip_zero_demand_check` is the key Odoo's own
/// `action_assign` passes to suppress it. Releases before 20 have no such
/// check and ignore the key, so an unknown generation (0) sends nothing.
Map<String, dynamic> confirmPickingContext(int generation) =>
    generation >= 20 ? const {'skip_zero_demand_check': true} : const {};

/// The `stock.picking` states a delivery can still be validated from.
///
/// `draft` is absent on purpose: Odoo's own `button_validate` confirms a
/// draft picking first, but a sales delivery is created already confirmed, so
/// a draft one here means something unusual that is better handled in Odoo.
const Set<String> kValidatableDeliveryStates = {
  'confirmed',
  'waiting',
  'assigned',
};
