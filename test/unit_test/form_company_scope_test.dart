import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/models/company_scope.dart';
import 'package:mobo_sales/models/sale_order_compat.dart';

/// The pickers of a create form offer what Odoo's own form offers: a
/// `check_company` field takes records of the record's company or of none
/// (`_check_company_domain`, Odoo 17-20).
void main() {
  group('companyCheckDomain', () {
    test("is Odoo's form domain for a known company", () {
      expect(companyCheckDomain(14), [
        '|',
        ['company_id', '=', false],
        ['company_id', '=', 14],
      ]);
    });

    test('leaves a search alone when the company is not known', () {
      expect(companyCheckDomain(null), isEmpty);
      expect(companyCheckDomain(0), isEmpty);
    });
  });

  group('saleLineProductIsCompanyChecked', () {
    test('17 and 18 do not limit the product to the company', () {
      expect(saleLineProductIsCompanyChecked(17), isFalse);
      expect(saleLineProductIsCompanyChecked(18), isFalse);
    });

    test('19 and 20 do', () {
      expect(saleLineProductIsCompanyChecked(19), isTrue);
      expect(saleLineProductIsCompanyChecked(20), isTrue);
    });

    test('an unknown server keeps the list as it was', () {
      expect(saleLineProductIsCompanyChecked(0), isFalse);
    });
  });
}
