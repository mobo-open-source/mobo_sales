import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/invoice_details_service.dart';
import 'package:mobo_sales/services/invoice_service.dart';
import 'package:mobo_sales/services/odoo_compat.dart';
import 'package:mobo_sales/services/payment_service.dart';

void main() {
  group('PaymentService.writeoffAccountDomain', () {
    List<String> fieldsOf(List<dynamic> domain) => [
      for (final leaf in domain) (leaf as List).first as String,
    ];

    test('Odoo 17 filters on company_id and deprecated', () {
      final domain = PaymentService.writeoffAccountDomain(
        generation: 17,
        companyId: 3,
      );
      expect(domain, [
        ['company_id', '=', 3],
        [
          'account_type',
          'in',
          ['expense', 'asset_current', 'income_other'],
        ],
        ['deprecated', '=', false],
      ]);
    });

    test('an unknown version gets the Odoo 17 domain, as before', () {
      expect(
        PaymentService.writeoffAccountDomain(generation: 0, companyId: 1),
        PaymentService.writeoffAccountDomain(generation: 17, companyId: 1),
      );
    });

    test('Odoo 18 has company_ids but still deprecated', () {
      final domain = PaymentService.writeoffAccountDomain(
        generation: 18,
        companyId: 3,
      );
      expect(domain.first, ['company_ids', 'parent_of', 3]);
      expect(fieldsOf(domain), ['company_ids', 'account_type', 'deprecated']);
    });

    test('Odoo 19 and 20 have neither company_id nor deprecated', () {
      for (final generation in [19, 20]) {
        final domain = PaymentService.writeoffAccountDomain(
          generation: generation,
          companyId: 3,
        );
        expect(domain.first, ['company_ids', 'parent_of', 3]);
        expect(fieldsOf(domain), [
          'company_ids',
          'account_type',
        ], reason: 'generation $generation');
      }
    });

    test('never names a field the release does not define', () {
      // account.account, as read from the Odoo source of each release.
      const fieldsByGeneration = {
        17: {'company_id', 'deprecated', 'account_type'},
        18: {'company_ids', 'deprecated', 'account_type'},
        19: {'company_ids', 'active', 'account_type'},
        20: {'company_ids', 'active', 'account_type'},
      };
      fieldsByGeneration.forEach((generation, defined) {
        final used = fieldsOf(
          PaymentService.writeoffAccountDomain(
            generation: generation,
            companyId: 1,
          ),
        );
        expect(defined.containsAll(used), isTrue, reason: 'Odoo $generation');
      });
    });
  });

  group('InvoiceService.customerPrefillFields', () {
    test('Odoo 17 and 18 read mobile and company_name', () {
      for (final generation in [0, 17, 18]) {
        final fields = InvoiceService.customerPrefillFields(generation);
        expect(fields, contains('mobile'), reason: 'generation $generation');
        expect(
          fields,
          contains('company_name'),
          reason: 'generation $generation',
        );
      }
    });

    test('Odoo 19 has no mobile', () {
      final fields = InvoiceService.customerPrefillFields(19);
      expect(fields, isNot(contains('mobile')));
      expect(fields, contains('company_name'));
    });

    test('Odoo 20 has neither mobile nor company_name', () {
      final fields = InvoiceService.customerPrefillFields(20);
      expect(fields, isNot(contains('mobile')));
      expect(fields, isNot(contains('company_name')));
    });

    test('every release still reads the contact card', () {
      for (final generation in [0, 17, 18, 19, 20]) {
        expect(
          InvoiceService.customerPrefillFields(generation),
          containsAll([
            'id',
            'name',
            'email',
            'phone',
            'street',
            'street2',
            'city',
            'state_id',
            'zip',
            'country_id',
            'image_1920',
            'vat',
          ]),
          reason: 'generation $generation',
        );
      }
    });
  });

  group('sale.order.line tax and unit-of-measure field order', () {
    test('Odoo 19 and 20 try the new names first', () {
      for (final generation in [19, 20]) {
        expect(InvoiceService.saleOrderLineTaxFieldAliases(generation), [
          'tax_ids',
          'tax_id',
        ]);
        expect(InvoiceService.saleOrderLineUomFieldAliases(generation), [
          'product_uom_id',
          'product_uom',
        ]);
      }
    });

    test('Odoo 17, 18 and an unknown version keep the original order', () {
      for (final generation in [0, 17, 18]) {
        expect(InvoiceService.saleOrderLineTaxFieldAliases(generation), [
          'tax_id',
          'tax_ids',
        ]);
        expect(InvoiceService.saleOrderLineUomFieldAliases(generation), [
          'product_uom',
          'product_uom_id',
        ]);
      }
    });

    test('both names stay in the list, so the read can still fall back', () {
      for (final generation in [0, 17, 18, 19, 20]) {
        expect(
          InvoiceService.saleOrderLineTaxFieldAliases(generation),
          unorderedEquals(['tax_id', 'tax_ids']),
        );
        expect(
          InvoiceService.saleOrderLineUomFieldAliases(generation),
          unorderedEquals(['product_uom', 'product_uom_id']),
        );
      }
    });
  });

  group('InvoiceDetailsService.isMissingMethodError', () {
    test('recognises how each release reports a method it does not have', () {
      final messages = [
        // 17 and 18: odoo/api.py call_kw.
        "Odoo Server Error: The method 'action_draft' does not exist on the model 'account.move'",
        // 19 and 20: get_public_method.
        "Odoo Server Error: The method 'account.move.action_draft' does not exist",
        "type object 'account.move' has no attribute 'action_draft'",
        'builtins.AttributeError: action_draft',
      ];
      for (final message in messages) {
        expect(
          InvoiceDetailsService.isMissingMethodError(Exception(message)),
          isTrue,
          reason: message,
        );
      }
    });

    test('does not mistake Odoo refusing the action for a missing method', () {
      final messages = [
        'Odoo Server Error: Only posted/cancelled journal entries can be reset to draft.',
        'Odoo Server Error: You cannot reset to draft an invoice with a reconciled payment.',
        'Odoo Server Error: Record does not exist or has been deleted.',
        'You do not have permission to cancel invoices.',
      ];
      for (final message in messages) {
        expect(
          InvoiceDetailsService.isMissingMethodError(Exception(message)),
          isFalse,
          reason: message,
        );
      }
    });
  });

  group('invoice list group summary through OdooCompat.readGroup', () {
    test('Odoo 20 asks formatted_read_group for counts only', () async {
      Map<String, dynamic>? sent;
      final rows = await OdooCompat.readGroup(
        model: 'account.move',
        domain: [
          [
            'move_type',
            'in',
            ['out_invoice', 'out_refund'],
          ],
        ],
        // What the invoice list asks for: no aggregate, only the row count.
        fields: ['id'],
        groupby: ['partner_id'],
        generation: 20,
        callKw: (payload) async {
          sent = payload;
          return [
            {
              'partner_id': [7, 'Azure Interior'],
              '__count': 3,
              '__extra_domain': [
                ['partner_id', '=', 7],
              ],
            },
            {'partner_id': false, '__count': 1, '__extra_domain': []},
          ];
        },
      );

      expect(sent!['model'], 'account.move');
      expect(sent!['method'], 'formatted_read_group');
      final kwargs = sent!['kwargs'] as Map;
      expect(kwargs['groupby'], ['partner_id']);
      expect(kwargs['aggregates'], ['__count']);

      // The list screen reads these keys.
      expect(rows[0]['partner_id'], [7, 'Azure Interior']);
      expect(rows[0]['__count'], 3);
      expect(rows[1]['partner_id'], false);
      expect(rows[1]['__count'], 1);
    });

    test('Odoo 17 and 18 still send the classic read_group', () async {
      for (final generation in [17, 18]) {
        Map<String, dynamic>? sent;
        final rows = await OdooCompat.readGroup(
          model: 'account.move',
          domain: [],
          fields: ['id'],
          groupby: ['state'],
          generation: generation,
          callKw: (payload) async {
            sent = payload;
            return [
              {'state': 'posted', '__count': 4},
            ];
          },
        );

        expect(sent!['method'], 'read_group', reason: 'Odoo $generation');
        final kwargs = sent!['kwargs'] as Map;
        expect(kwargs['fields'], ['id']);
        expect(kwargs['groupby'], ['state']);
        expect(kwargs['lazy'], false);
        expect(rows.single['state'], 'posted');
        expect(rows.single['__count'], 4);
      }
    });
  });
}
