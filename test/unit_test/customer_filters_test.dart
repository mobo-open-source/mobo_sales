import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/providers/contact_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/odoo_domain.dart';
import '../mocks/mock_services.dart';

/// The customers list filters, by what they return: each one and the
/// combinations the filter sheet allows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContactProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = ContactProvider(
      customerService: MockCustomerService(),
      connectivityService: MockConnectivityService(),
      sessionService: MockSessionService(),
    );
  });

  Map<String, dynamic> c(
    int id,
    String name, {
    int rank = 1,
    bool company = false,
    bool active = true,
    String created = '2026-10-01 09:00:00',
    String email = '',
    String phone = '',
    String companyName = '',
  }) => {
    'id': id,
    'name': name,
    'customer_rank': rank,
    'is_company': company,
    'active': active,
    'create_date': created,
    'email': email,
    'phone': phone,
    'company_name': companyName,
    'parent_id.name': companyName,
  };

  final odoo = OdooDomain([
    c(1, 'Azure Interior', company: true, email: 'a@azure.com'),
    c(2, 'Ada Lovelace', created: '2026-10-10 09:00:00', phone: '555-0102'),
    c(3, 'Deco Addict', company: true, created: '2026-10-20 09:00:00'),
    c(4, 'Prospect Only', rank: 0, company: true),
    c(5, 'Old Customer', active: false, created: '2026-09-01 09:00:00'),
    c(
      6,
      'Old Company',
      company: true,
      active: false,
      created: '2026-10-12 09:00:00',
    ),
    c(7, 'Bob Prospect', rank: 0),
    c(8, 'Archived Prospect', rank: 0, active: false),
    c(9, 'Cara Staff', companyName: 'Azure Interior', email: 'c@azure.com'),
  ]);

  List<int> shown({
    bool customersOnly = true,
    bool archived = false,
    bool companies = false,
    bool individuals = false,
    bool credit = false,
    DateTime? start,
    DateTime? end,
    String search = '',
    int generation = 17,
    List<int> breachIds = const [2, 3, 5],
  }) {
    provider.creditBreachIdsForTest = breachIds;
    final domain = provider.domainFor(search, {
      'showCustomersOnly': customersOnly,
      if (archived) 'showArchivedOnly': true,
      if (companies) 'showCompaniesOnly': true,
      if (individuals) 'showIndividualsOnly': true,
      if (credit) 'showCreditBreachesOnly': true,
      if (start != null) 'startDate': start,
      if (end != null) 'endDate': end,
    }, generation);
    return odoo.search(domain).map((r) => r['id'] as int).toList()..sort();
  }

  group('each filter', () {
    test('default: active customers', () {
      expect(shown(), [1, 2, 3, 9]);
    });
    test('Customers only off: every active contact', () {
      expect(shown(customersOnly: false), [1, 2, 3, 4, 7, 9]);
    });
    test('Archived', () => expect(shown(archived: true), [5, 6]));
    test('Archived without Customers only', () {
      expect(shown(archived: true, customersOnly: false), [5, 6, 8]);
    });
    test('Companies', () => expect(shown(companies: true), [1, 3]));
    test('Individuals', () => expect(shown(individuals: true), [2, 9]));
    test('Credit Breaches: only those over their limit', () {
      expect(shown(credit: true), [2, 3]);
    });
    test('Credit Breaches with none over the limit is an empty list', () {
      expect(shown(credit: true, breachIds: const []), isEmpty);
    });
    test('Date Range', () {
      expect(shown(start: DateTime(2026, 10, 5), end: DateTime(2026, 10, 31)), [
        2,
        3,
      ]);
      expect(shown(start: DateTime(2026, 10, 15)), [3]);
      expect(shown(end: DateTime(2026, 10, 2)), [1, 9]);
    });
  });

  group('filters together', () {
    test('Customers only is a switch, with the others on or off', () {
      expect(shown(companies: true, customersOnly: false), [1, 3, 4]);
      expect(shown(individuals: true, customersOnly: false), [2, 7, 9]);
    });
    test('Archived with Companies', () {
      expect(shown(archived: true, companies: true), [6]);
    });
    test('Archived with Individuals', () {
      expect(shown(archived: true, individuals: true), [5]);
    });
    test('Archived with Credit Breaches', () {
      expect(shown(archived: true, credit: true), [5]);
    });
    test('Companies with Credit Breaches', () {
      expect(shown(companies: true, credit: true), [3]);
    });
    test('Individuals with Credit Breaches', () {
      expect(shown(individuals: true, credit: true), [2]);
    });
    test('Companies with a date range', () {
      expect(
        shown(
          companies: true,
          start: DateTime(2026, 10, 15),
          end: DateTime(2026, 10, 31),
        ),
        [3],
      );
    });
    test('Archived with a date range', () {
      expect(shown(archived: true, start: DateTime(2026, 10, 1)), [6]);
    });
    test('Credit Breaches, Companies and a date range', () {
      expect(
        shown(credit: true, companies: true, start: DateTime(2026, 10, 15)),
        [3],
      );
    });
    test('Archived, Companies, Credit Breaches and dates', () {
      expect(
        shown(
          archived: true,
          companies: true,
          credit: true,
          breachIds: const [5, 6],
          start: DateTime(2026, 10, 1),
        ),
        [6],
      );
    });
    test('Companies and Individuals together are Odoo-contradictory', () {
      // The sheet switches one off when the other is chosen, so the pair is
      // never sent; sent anyway it matches nothing, not everything.
      expect(shown(companies: true, individuals: true), isEmpty);
    });
  });

  group('search with the filters', () {
    test('by name, email, phone', () {
      expect(shown(search: 'azure'), [1, 9]);
      expect(shown(search: 'lovelace'), [2]);
      expect(shown(search: '555-01'), [2]);
      expect(shown(search: 'c@azure'), [9]);
    });
    test('by company: its own name on 17, its parent on 20', () {
      expect(shown(search: 'azure', individuals: true), [9]);
      expect(shown(search: 'azure', individuals: true, generation: 20), [9]);
    });
    test('with Companies, Archived and a date range', () {
      expect(shown(search: 'azure', companies: true), [1]);
      expect(shown(search: 'old', archived: true), [5, 6]);
      expect(shown(search: 'old', archived: true, companies: true), [6]);
      expect(
        shown(search: 'a', companies: true, start: DateTime(2026, 10, 15)),
        [3],
      );
    });
    test('with Credit Breaches', () {
      expect(shown(search: 'a', credit: true), [2, 3]);
      expect(shown(search: 'deco', credit: true), [3]);
    });
  });
}
