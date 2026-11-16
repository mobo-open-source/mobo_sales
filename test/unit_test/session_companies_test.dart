import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/session_companies.dart';

/// `user_companies` exactly as `/web/session/get_session_info` builds it.
/// The shape is the same in 17.0, 18.0, 19.0 and 20.0; 19 and 20 add
/// `currency_id` per entry, which this must simply ignore.
Map<String, dynamic> sessionInfo({
  Object? currentCompany = 1,
  Map<String, dynamic>? allowed,
  bool withCurrency = false,
}) => {
  'uid': 2,
  'user_companies': {
    'current_company': currentCompany,
    'allowed_companies':
        allowed ??
        {
          '1': {
            'id': 1,
            'name': 'My Company',
            'sequence': 10,
            'parent_id': false,
            if (withCurrency) 'currency_id': 1,
          },
          '3': {
            'id': 3,
            'name': 'Branch Office',
            'sequence': 20,
            'parent_id': 1,
            if (withCurrency) 'currency_id': 1,
          },
        },
  },
};

void main() {
  group('reading the companies the server already told us about', () {
    test('both companies come back, with their names', () {
      final parsed = parseSessionCompanies(sessionInfo())!;
      expect(parsed.ids, [1, 3]);
      expect(parsed.companies.map((c) => c['name']), [
        'My Company',
        'Branch Office',
      ]);
      expect(parsed.currentId, 1);
    });

    test('Odoo 19 and 20 add currency_id, which changes nothing here', () {
      final parsed = parseSessionCompanies(sessionInfo(withCurrency: true))!;
      expect(parsed.ids, [1, 3]);
      expect(parsed.currentId, 1);
    });

    test('ordered by sequence, the way Odoo orders its own switcher', () {
      final parsed = parseSessionCompanies(
        sessionInfo(
          allowed: {
            '7': {'id': 7, 'name': 'Zulu', 'sequence': 1},
            '2': {'id': 2, 'name': 'Alpha', 'sequence': 9},
          },
        ),
      )!;
      expect(parsed.ids, [7, 2], reason: 'sequence wins over the name');
    });

    test('equal sequences fall back to the name', () {
      final parsed = parseSessionCompanies(
        sessionInfo(
          allowed: {
            '7': {'id': 7, 'name': 'Zulu', 'sequence': 5},
            '2': {'id': 2, 'name': 'Alpha', 'sequence': 5},
          },
        ),
      )!;
      expect(parsed.ids, [2, 7]);
    });

    test('an id that only appears as the key is still read', () {
      final parsed = parseSessionCompanies(
        sessionInfo(
          allowed: {
            '4': {'name': 'Keyed Only'},
          },
        ),
      )!;
      expect(parsed.ids, [4]);
      expect(parsed.companies.single['name'], 'Keyed Only');
    });

    test('a company with no name is shown by its id, never blank', () {
      final parsed = parseSessionCompanies(
        sessionInfo(
          allowed: {
            '9': {'id': 9},
          },
        ),
      )!;
      expect(parsed.companies.single['name'], 'Company 9');
    });

    test('current_company false means "not said", not company zero', () {
      // Odoo writes an unset many2one as `false` over JSON-RPC.
      final parsed = parseSessionCompanies(sessionInfo(currentCompany: false))!;
      expect(parsed.currentId, isNull);
      expect(parsed.ids, [1, 3]);
    });
  });

  group('null means "this reply does not tell us"', () {
    // The caller has to keep "could not load" apart from "has none": showing
    // an empty company list for a failed read is what made a working account
    // look empty.
    test('a reply with no user_companies at all', () {
      expect(parseSessionCompanies({'uid': 2}), isNull);
    });

    test('an empty allowed_companies', () {
      expect(
        parseSessionCompanies(sessionInfo(allowed: <String, dynamic>{})),
        isNull,
      );
    });

    test('a null reply', () {
      expect(parseSessionCompanies(null), isNull);
    });

    test('allowed_companies that is not a map', () {
      expect(
        parseSessionCompanies({
          'user_companies': {'allowed_companies': <dynamic>[]},
        }),
        isNull,
      );
    });

    test('entries that carry no usable id', () {
      expect(
        parseSessionCompanies({
          'user_companies': {
            'allowed_companies': {
              'not-a-number': {'name': 'Nameless'},
            },
          },
        }),
        isNull,
      );
    });
  });
}
