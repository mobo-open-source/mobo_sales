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
