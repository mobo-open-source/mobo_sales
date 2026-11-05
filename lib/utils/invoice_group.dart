import 'group_labels.dart';

/// The user-facing name of a group-by field on the invoice list. Keyed by the
/// field names the Group By sheet offers; any other field is made readable
/// rather than shown as its technical name.
const Map<String, String> kInvoiceGroupByLabels = {
  'state': 'Status',
  'invoice_user_id': 'Salesperson',
  'partner_id': 'Partner',
  'team_id': 'Sales Team',
  'company_id': 'Company',
  'payment_state': 'Payment Status',
  'currency_id': 'Currency',
  'invoice_date': 'Invoice Date',
  'invoice_date_due': 'Due Date',
};

String invoiceGroupByLabel(String? groupBy) =>
    groupByDisplayLabel(groupBy, kInvoiceGroupByLabels);

/// The label of one group of `read_group` rows, given as the row's [group]
/// map. A many2one arrives as `[id, name]` and an empty one as `false`; either
/// way the value is passed through, so only the records with nothing assigned
/// get the "unassigned" label.
String invoiceGroupKeyFromReadGroup(
  Map<dynamic, dynamic> group,
  String groupByField,
) {
  try {
    final value = group[groupByField];
    final data = <String, dynamic>{groupByField: value};
    if (groupByField == 'state') data['payment_state'] = '';
    return invoiceGroupKey(data, groupByField);
  } catch (e) {
    return 'Unknown';
  }
}

/// The group label of an invoice row, by [groupByField].
String invoiceGroupKey(Map<String, dynamic> data, String groupByField) {
  switch (groupByField) {
    case 'state':
      final state = data['state']?.toString().toLowerCase() ?? '';
      switch (state) {
        case 'draft':
          return 'Draft';
        case 'cancel':
          return 'Cancelled';
        case 'sent':
          return 'Sent';
        case 'posted':
          final paymentState =
              data['payment_state']?.toString().toLowerCase() ?? '';
          switch (paymentState) {
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
              return 'Posted';
          }
        default:
          return state.isNotEmpty ? state : kEmptyGroupLabel;
      }
    case 'invoice_user_id':
      if (data['invoice_user_id'] is List &&
          data['invoice_user_id'].length >= 2) {
        return data['invoice_user_id'][1].toString();
      }
      return kEmptyGroupLabel;
    case 'partner_id':
      if (data['partner_id'] is List && data['partner_id'].length >= 2) {
        return data['partner_id'][1].toString();
      }
      return kEmptyGroupLabel;
    case 'team_id':
      if (data['team_id'] is List && data['team_id'].length >= 2) {
        return data['team_id'][1].toString();
      }
      return kEmptyGroupLabel;
    case 'company_id':
      if (data['company_id'] is List && data['company_id'].length >= 2) {
        return data['company_id'][1].toString();
      }
      return kEmptyGroupLabel;
    default:
      return kEmptyGroupLabel;
  }
}
