/// The name of the group that holds the records with no value for the field
/// being grouped by: the salesperson of an unassigned customer, the category of
/// a product without one, a quotation with no expiration date.
///
/// It is what Odoo's own web client calls that group on every release from 17
/// to 20 (`None`), and what every group-by in the app now shows. A group's name
/// is also the key its records are loaded under, so the name a group is listed
/// with and the one its domain is built from have to be this same value.
const String kEmptyGroupLabel = 'None';

/// Names for the granularity Odoo adds to a date group field (`field:year`).
const Map<String, String> kDateGranularityLabels = {
  'year': 'Year',
  'quarter': 'Quarter',
  'month': 'Month',
  'week': 'Week',
  'day': 'Day',
};

/// A readable name for a Group By field, never the technical one.
///
/// [known] holds the screen's own names for plain fields. A date field with a
/// granularity (`date_order:year`) reads "Order Date: Year", and a field nobody
/// named is made readable (`some_field_id` becomes "Some Field").
String groupByDisplayLabel(String? field, [Map<String, String> known = const {}]) {
  if (field == null || field.isEmpty) return '';
  final direct = known[field];
  if (direct != null) return direct;
  final colon = field.indexOf(':');
  if (colon > 0) {
    final base = field.substring(0, colon);
    final unit = field.substring(colon + 1);
    final baseLabel = groupByDisplayLabel(base, known);
    final unitLabel = kDateGranularityLabels[unit] ??
        (unit.isEmpty ? unit : unit[0].toUpperCase() + unit.substring(1));
    return '$baseLabel: $unitLabel';
  }
  var name = field;
  if (name.endsWith('_ids')) {
    name = name.substring(0, name.length - 4);
  } else if (name.endsWith('_id')) {
    name = name.substring(0, name.length - 3);
  }
  return name
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
