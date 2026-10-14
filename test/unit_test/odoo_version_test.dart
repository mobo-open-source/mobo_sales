import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/odoo_version.dart';

void main() {
  group('odooMajorVersion (the number as written)', () {
    test('reads the shapes Odoo reports', () {
      expect(odooMajorVersion('17.0'), 17);
      expect(odooMajorVersion('17.0+e'), 17);
      expect(odooMajorVersion('saas~16.3'), 16);
      expect(odooMajorVersion('19.5a1'), 19);
      expect(odooMajorVersion('20.0'), 20);
    });
    test('0 when it cannot be read', () {
      expect(odooMajorVersion(null), 0);
      expect(odooMajorVersion(''), 0);
      expect(odooMajorVersion('unknown'), 0);
    });
  });

  group('odooGeneration', () {
    test('an Odoo 20 pre-release counts as 20', () {
      expect(odooGeneration('19.5a1'), 20);
      expect(odooGeneration('19.5'), 20);
      expect(odooGeneration('saas~19.5'), 20);
      expect(odooGeneration('19.5a1+e'), 20);
      expect(odooGeneration('19.9'), 20);
    });
    test('19.0 to 19.4 are still 19', () {
      expect(odooGeneration('19.0'), 19);
      expect(odooGeneration('saas~19.1'), 19);
      expect(odooGeneration('saas~19.4'), 19);
      expect(odooGeneration('19.0+e'), 19);
    });
    test('released versions are themselves', () {
      expect(odooGeneration('20.0'), 20);
      expect(odooGeneration('20.0+e'), 20);
      expect(odooGeneration('21.0'), 21);
      expect(odooGeneration('18.0'), 18);
      expect(odooGeneration('17.0'), 17);
      expect(odooGeneration('saas~16.3'), 16);
    });
    test('a bare major number works', () {
      expect(odooGeneration('19'), 19);
      expect(odooGeneration('20'), 20);
    });
    test('0 when it cannot be read', () {
      expect(odooGeneration(null), 0);
      expect(odooGeneration(''), 0);
      expect(odooGeneration('nonsense'), 0);
    });
  });

  group('capabilities by generation', () {
    String row(bool Function(int) f) => [
      for (final g in [0, 17, 18, 19, 20]) f(g) ? 'Y' : 'n',
    ].join();
    // Columns: unknown, 17, 18, 19, 20.

    test('res.partner.mobile: gone from 19', () {
      expect(row(odooHasPartnerMobile), 'YYYnn');
    });
    test('res.partner.title: gone from 19', () {
      expect(row(odooHasPartnerTitle), 'YYYnn');
    });
    test('res.partner.company_type and company_name: gone from 20', () {
      expect(row(odooHasPartnerCompanyType), 'YYYYn');
      expect(row(odooHasPartnerCompanyName), 'YYYYn');
    });
    test('is_company is only writable before 20', () {
      expect(row(odooPartnerIsCompanyWritable), 'YYYYn');
    });
    test('formatted_read_group from 19; unknown keeps the old read_group', () {
      expect(row(odooUsesFormattedReadGroup), 'nnnYY');
    });
    test('has_access from 18; unknown keeps check_access_rights', () {
      expect(row(odooUsesHasAccess), 'nnYYY');
    });
    test('an Odoo 20 pre-release gets the Odoo 20 answers', () {
      final g = odooGeneration('19.5a1');
      expect(odooHasPartnerCompanyType(g), isFalse);
      expect(odooUsesFormattedReadGroup(g), isTrue);
      expect(odooUsesHasAccess(g), isTrue);
      expect(odooHasPartnerMobile(g), isFalse);
    });
  });
}
