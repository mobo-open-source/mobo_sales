import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/odoo_partner_domains.dart';
import 'package:mobo_sales/utils/odoo_version.dart';

void main() {
  group('relatedCompanyDomain', () {
    test('up to Odoo 19 offers the partners flagged as companies', () {
      for (final generation in [17, 18, 19]) {
        expect(relatedCompanyDomain(generation), [
          ['is_company', '=', true],
        ], reason: 'Odoo $generation');
      }
    });

    test('an unknown version keeps the behaviour of every release so far', () {
      expect(relatedCompanyDomain(0), [
        ['is_company', '=', true],
      ]);
    });

    test('Odoo 20 offers the partners that have no parent', () {
      // is_company is computed from the VAT there; a company without one
      // would be missing from the list.
      expect(relatedCompanyDomain(20), [
        ['parent_id', '=', false],
      ]);
      expect(relatedCompanyDomain(21), [
        ['parent_id', '=', false],
      ]);
    });

    test('adds the name search, trimmed, and ignores a blank one', () {
      expect(relatedCompanyDomain(19, query: '  Azure '), [
        ['is_company', '=', true],
        ['name', 'ilike', 'Azure'],
      ]);
      expect(relatedCompanyDomain(20, query: 'Azure'), [
        ['parent_id', '=', false],
        ['name', 'ilike', 'Azure'],
      ]);
      expect(relatedCompanyDomain(20, query: '   '), [
        ['parent_id', '=', false],
      ]);
    });

    test('follows the generation the server version reads as', () {
      // 19.5a1 is the Odoo 20 development tree.
      expect(relatedCompanyDomain(odooGeneration('19.5a1')), [
        ['parent_id', '=', false],
      ]);
      expect(relatedCompanyDomain(odooGeneration('19.0')), [
        ['is_company', '=', true],
      ]);
    });
  });
}
