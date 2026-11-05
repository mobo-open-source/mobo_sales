import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/group_labels.dart';
import 'package:mobo_sales/utils/invoice_group.dart';

void main() {
  group('invoiceGroupByLabel', () {
    test('every option the Group By sheet offers has a readable name', () {
      expect(invoiceGroupByLabel('state'), 'Status');
      expect(invoiceGroupByLabel('invoice_user_id'), 'Salesperson');
      expect(invoiceGroupByLabel('partner_id'), 'Partner');
      expect(invoiceGroupByLabel('team_id'), 'Sales Team');
      expect(invoiceGroupByLabel('company_id'), 'Company');
    });

    test('an unknown field is made readable, never shown as the raw name', () {
      expect(invoiceGroupByLabel('some_field_id'), 'Some Field');
      expect(invoiceGroupByLabel('x_studio_region'), 'X Studio Region');
      expect(invoiceGroupByLabel(null), '');
    });
  });

  group('invoiceGroupKeyFromReadGroup', () {
    test(
      'a salesperson group is labelled with the salesperson, not Unassigned',
      () {
        expect(
          invoiceGroupKeyFromReadGroup({
            'invoice_user_id': [2, 'Mitchell Admin'],
            '__count': 3,
          }, 'invoice_user_id'),
          'Mitchell Admin',
        );
      },
    );

    test('records with nothing assigned are in the group Odoo calls None', () {
      // The backend's own name for the empty group (`None`, on Odoo 17 to 20),
      // the same for every field, not a different word for each.
      for (final field in const [
        'invoice_user_id',
        'team_id',
        'company_id',
        'partner_id',
      ]) {
        expect(
          invoiceGroupKeyFromReadGroup({field: false}, field),
          'None',
          reason: field,
        );
      }
      expect(kEmptyGroupLabel, 'None');
    });

    test('team and company groups keep their own names', () {
      expect(
        invoiceGroupKeyFromReadGroup({
          'team_id': [1, 'Sales'],
        }, 'team_id'),
        'Sales',
      );
      expect(
        invoiceGroupKeyFromReadGroup({
          'company_id': [1, 'My Company'],
        }, 'company_id'),
        'My Company',
      );
    });

    test('distinct salespeople give distinct groups', () {
      final a = invoiceGroupKeyFromReadGroup({
        'invoice_user_id': [2, 'A'],
      }, 'invoice_user_id');
      final b = invoiceGroupKeyFromReadGroup({
        'invoice_user_id': [3, 'B'],
      }, 'invoice_user_id');
      expect(a, isNot(b));
    });

    test('status groups still read as before', () {
      expect(
        invoiceGroupKeyFromReadGroup({'state': 'draft'}, 'state'),
        'Draft',
      );
      expect(
        invoiceGroupKeyFromReadGroup({'state': 'posted'}, 'state'),
        'Posted',
      );
      expect(
        invoiceGroupKeyFromReadGroup({'state': 'cancel'}, 'state'),
        'Cancelled',
      );
    });
  });
}
