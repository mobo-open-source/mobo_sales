import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobo_sales/models/contact.dart';
import 'package:mobo_sales/providers/contact_provider.dart';
import 'package:mobo_sales/services/customer_service.dart';
import '../mocks/mock_services.dart';

/// Fields Odoo took out of `res.partner`, by the generation that did it.
const _goneIn19 = ['mobile', 'title'];
const _goneIn20 = ['company_type', 'company_name'];

void main() {
  final allFieldSets = <String, List<String>>{
    'details': kCustomerDetailFields,
    'typeahead': kCustomerListFields,
    'search': kCustomerSearchFields,
    'details screen': kCustomerScreenFields,
    'customer list': kContactListFields,
  };

  group('partnerReadFieldsFor', () {
    test('Odoo 17 and 18 read every field, in order', () {
      for (final entry in allFieldSets.entries) {
        for (final generation in [17, 18]) {
          expect(
            partnerReadFieldsFor(entry.value, generation),
            entry.value,
            reason: '${entry.key} on $generation',
          );
        }
      }
    });

    test('an unknown version keeps every field, as the app always did', () {
      for (final entry in allFieldSets.entries) {
        expect(partnerReadFieldsFor(entry.value, 0), entry.value);
      }
    });

    test('Odoo 19 drops mobile and title and nothing else', () {
      final fields = partnerReadFieldsFor(kCustomerScreenFields, 19);
      expect(fields, isNot(contains('mobile')));
      expect(fields, isNot(contains('title')));
      expect(fields, contains('company_name'));
      expect(fields, contains('company_type'));
      expect(fields.length, kCustomerScreenFields.length - _goneIn19.length);
    });

    test('Odoo 20 asks for none of the fields Odoo removed', () {
      for (final entry in allFieldSets.entries) {
        final fields = partnerReadFieldsFor(entry.value, 20);
        for (final gone in [..._goneIn19, ..._goneIn20]) {
          expect(fields, isNot(contains(gone)), reason: '${entry.key}: $gone');
        }
      }
    });

    test('Odoo 20 reads the parent company name where company_name was', () {
      final fields = partnerReadFieldsFor(kCustomerDetailFields, 20);
      expect(fields.where((f) => f == 'parent_name'), hasLength(1));
      // Nothing before company_name is removed, so it keeps its place.
      expect(
        fields.indexOf('parent_name'),
        kCustomerDetailFields.indexOf('company_name'),
      );
    });

    test('Odoo 17 to 19 never ask for parent_name', () {
      for (final entry in allFieldSets.entries) {
        for (final generation in [0, 17, 18, 19]) {
          expect(
            partnerReadFieldsFor(entry.value, generation),
            isNot(contains('parent_name')),
            reason: '${entry.key} on $generation',
          );
        }
      }
    });

    test('Odoo 20 keeps what it still needs to derive the company', () {
      for (final entry in allFieldSets.entries) {
        expect(
          partnerReadFieldsFor(entry.value, 20),
          contains('is_company'),
          reason: entry.key,
        );
      }
    });

    test('a field list that already has parent_name does not get it twice', () {
      final fields = partnerReadFieldsFor([
        'id',
        'company_name',
        'parent_name',
        'mobile',
      ], 20);
      expect(fields, ['id', 'parent_name']);
    });

    test('does not modify the list it is given', () {
      final original = List<String>.of(kCustomerScreenFields);
      partnerReadFieldsFor(original, 20);
      expect(original, kCustomerScreenFields);
    });
  });

  group('partnerValuesFor', () {
    final form = <String, dynamic>{
      'name': 'Acme',
      'vat': 'BE0477472701',
      'mobile': '123',
      'title': 1,
      'company_name': 'Acme Ltd',
      'company_type': 'company',
      'is_company': true,
      'customer_rank': 1,
    };

    test('Odoo 17, 18 and an unknown version send everything', () {
      for (final generation in [0, 17, 18]) {
        expect(partnerValuesFor(form, generation), form);
      }
    });

    test('Odoo 19 drops mobile and title', () {
      final out = partnerValuesFor(form, 19);
      expect(out.keys, isNot(contains('mobile')));
      expect(out.keys, isNot(contains('title')));
      expect(out['company_name'], 'Acme Ltd');
      expect(out['company_type'], 'company');
      expect(out['is_company'], true);
    });

    test('Odoo 20 drops what no longer exists or no longer sticks', () {
      final out = partnerValuesFor(form, 20);
      expect(out.keys.toSet(), {'name', 'vat', 'customer_rank'});
    });

    test('does not modify the map it is given', () {
      final copy = Map<String, dynamic>.of(form);
      partnerValuesFor(form, 20);
      expect(form, copy);
    });
  });

  group('partnerWritableValues', () {
    // The shape `fields_get(attributes=['type', 'readonly'])` returns.
    final schema20 = <String, Map<String, dynamic>>{
      'name': {'type': 'char', 'readonly': false},
      'vat': {'type': 'char', 'readonly': false},
      'is_company': {'type': 'boolean', 'readonly': true},
      'currency_id': {'type': 'many2one', 'readonly': true},
      'customer_rank': {'type': 'integer', 'readonly': false},
    };

    test('the schema decides when it is known', () {
      final out = partnerWritableValues(
        {
          'name': 'Acme',
          'is_company': true,
          'currency_id': 3,
          'company_name': 'x',
          'customer_rank': 1,
        },
        schema: schema20,
        generation: 20,
      );
      expect(out, {'name': 'Acme', 'customer_rank': 1});
    });

    test('the schema wins over the version table', () {
      // A server that says it has company_type gets it, whatever it reports.
      final out = partnerWritableValues(
        {'company_type': 'company'},
        schema: {
          'company_type': {'type': 'selection', 'readonly': false},
        },
        generation: 20,
      );
      expect(out, {'company_type': 'company'});
    });

    test('the version table stands in when the schema could not be read', () {
      final values = {
        'name': 'Acme',
        'company_type': 'company',
        'company_name': 'Acme Ltd',
        'is_company': true,
      };
      expect(partnerWritableValues(values, schema: const {}, generation: 20), {
        'name': 'Acme',
      });
      expect(
        partnerWritableValues(values, schema: const {}, generation: 18),
        values,
      );
      expect(
        partnerWritableValues(values, schema: const {}, generation: 0),
        values,
      );
    });
  });

  group('partnerFieldWritableIn', () {
    final schema = <String, Map<String, dynamic>>{
      'tz': {'readonly': false},
      'is_company': {'readonly': true},
    };

    test('a writable field is, a read-only or missing one is not', () {
      expect(partnerFieldWritableIn(schema, 'tz', whenUnknown: false), isTrue);
      expect(
        partnerFieldWritableIn(schema, 'is_company', whenUnknown: true),
        isFalse,
      );
      expect(
        partnerFieldWritableIn(schema, 'mobile', whenUnknown: true),
        isFalse,
      );
    });

    test('whenUnknown answers only while the schema is unknown', () {
      expect(partnerFieldWritableIn({}, 'mobile', whenUnknown: true), isTrue);
      expect(partnerFieldWritableIn({}, 'mobile', whenUnknown: false), isFalse);
    });
  });

  group('partnerTextChanged', () {
    test('the same text, however Odoo says empty, is not a change', () {
      expect(partnerTextChanged('BE0477472701', 'BE0477472701'), isFalse);
      expect(partnerTextChanged('BE0477472701', '  BE0477472701 '), isFalse);
      expect(partnerTextChanged(null, ''), isFalse);
      expect(partnerTextChanged('false', ''), isFalse);
      expect(partnerTextChanged('False', '  '), isFalse);
    });

    test('a different text is', () {
      expect(partnerTextChanged('BE0477472701', 'BE0477472702'), isTrue);
      expect(partnerTextChanged(null, 'BE0477472701'), isTrue);
      expect(partnerTextChanged('false', 'x'), isTrue);
      expect(partnerTextChanged('x', ''), isTrue);
    });
  });

  group('partnerCompanyLeaf', () {
    test('up to Odoo 19 it searches the free-text company_name', () {
      for (final generation in [0, 17, 18, 19]) {
        expect(partnerCompanyLeaf('acme', generation), [
          'company_name',
          'ilike',
          'acme',
        ]);
      }
    });

    test('Odoo 20 searches the name of the parent company', () {
      expect(partnerCompanyLeaf('acme', 20), [
        'parent_id.name',
        'ilike',
        'acme',
      ]);
    });
  });

  group('Contact.fromJson across Odoo versions', () {
    test(
      'Odoo 20 person: company type from is_company, company from parent',
      () {
        final contact = Contact.fromJson({
          'id': 5,
          'name': 'Jane',
          'is_company': false,
          'parent_name': 'Acme Ltd',
        });
        expect(contact.isCompany, false);
        expect(contact.companyType, 'person');
        expect(contact.companyName, 'Acme Ltd');
      },
    );

    test('Odoo 20 company: no parent, so no company name', () {
      final contact = Contact.fromJson({
        'id': 7,
        'name': 'Acme Ltd',
        'is_company': true,
        'parent_name': false,
      });
      expect(contact.companyType, 'company');
      expect(contact.companyName, isNull);
      expect(contact.displayName, 'Acme Ltd');
    });

    test('data that only carries parent_id is not reinterpreted', () {
      // Other screens read parent_id for their own purposes; it must not turn
      // into a company name there.
      final contact = Contact.fromJson({
        'id': 5,
        'name': 'Jane',
        'is_company': true,
        'parent_id': [7, 'Holding'],
      });
      expect(contact.companyName, isNull);
    });

    test('Odoo 17 to 19 keep what the server sent', () {
      final contact = Contact.fromJson({
        'id': 5,
        'name': 'Jane',
        'is_company': false,
        'company_type': 'person',
        'company_name': 'Acme Inc',
      });
      expect(contact.companyType, 'person');
      expect(contact.companyName, 'Acme Inc');
    });

    test('an explicit company_type is not overridden by is_company', () {
      final contact = Contact.fromJson({
        'id': 5,
        'name': 'x',
        'is_company': false,
        'company_type': 'company',
      });
      expect(contact.companyType, 'company');
    });

    test('an unset company_name stays the string the callers test for', () {
      // Odoo sends false for an empty char; the screens compare with 'false'.
      final contact = Contact.fromJson({
        'id': 5,
        'name': 'x',
        'company_name': false,
        'parent_name': 'Acme',
      });
      expect(contact.companyName, 'false');
    });

    test('the Odoo company a partner belongs to still comes first', () {
      final contact = Contact.fromJson({
        'id': 5,
        'name': 'x',
        'company_id': [1, 'My Company'],
        'parent_name': 'Acme',
      });
      expect(contact.companyName, 'My Company');
      expect(contact.companyId, 1);
    });

    test('is tolerant of missing and malformed data', () {
      final bare = Contact.fromJson({'id': 1, 'name': 'x'});
      expect(bare.companyType, isNull, reason: 'unknown, not guessed');
      expect(bare.companyName, isNull);

      for (final parent in [
        false,
        null,
        '',
        7,
        <dynamic>[],
        [3],
      ]) {
        final contact = Contact.fromJson({
          'id': 1,
          'name': 'x',
          'is_company': false,
          'parent_name': parent,
        });
        expect(contact.companyName, isNull, reason: 'parent_name: $parent');
      }

      final falseType = Contact.fromJson({
        'id': 1,
        'name': 'x',
        'is_company': true,
        'company_type': false,
      });
      expect(falseType.companyType, 'company');
    });

    test(
      'Odoo 20 sends a binary field as a dict: the photo is its content',
      () {
        final contact = Contact.fromJson({
          'id': 5,
          'name': 'Jane',
          'image_128': {
            'content': 'iVBORw0KGgo=',
            'size': 8,
            'filename': 'a.png',
          },
        });
        expect(contact.imageUrl, 'iVBORw0KGgo=');

        final big = Contact.fromJson({
          'id': 5,
          'name': 'Jane',
          'image_1920': {'content': 'AAAA', 'size': 3},
        });
        expect(big.imageUrl, 'AAAA');
      },
    );

    test('Odoo 17 to 19 send base64 text, or false for no photo', () {
      final withPhoto = Contact.fromJson({
        'id': 1,
        'name': 'x',
        'image_128': 'iVBORw0KGgo=',
      });
      expect(withPhoto.imageUrl, 'iVBORw0KGgo=');

      // Unchanged: callers compare with the string 'false'.
      final without = Contact.fromJson({
        'id': 1,
        'name': 'x',
        'image_128': false,
      });
      expect(without.imageUrl, 'false');

      expect(Contact.fromJson({'id': 1, 'name': 'x'}).imageUrl, isNull);
    });

    test('a photo dict without content means no photo', () {
      for (final dict in [
        {'size': 10, 'checksum': 'abc'},
        {'content': '', 'size': 0},
        {'content': 5},
      ]) {
        final contact = Contact.fromJson({
          'id': 1,
          'name': 'x',
          'image_128': dict,
        });
        expect(contact.imageUrl, isNull, reason: '$dict');
      }
    });

    test('survives the round trip the recent-customers list makes', () {
      final original = Contact.fromJson({
        'id': 5,
        'name': 'Jane',
        'is_company': false,
        'parent_name': 'Acme Ltd',
        'image_128': {'content': 'AAAA', 'size': 3},
      });
      final again = Contact.fromJson(original.toJson());
      expect(again.companyName, 'Acme Ltd');
      expect(again.companyType, 'person');
      expect(again.imageUrl, 'AAAA');
    });
  });

  // Rows as an Odoo 20 server (19.5a1) returned them for the fields the
  // customer screens ask for on that generation; only the picture's base64 text
  // is shortened. They pin the parsing to the real wire format.
  group('Contact.fromJson on rows captured from a real Odoo 20 server', () {
    final company = <String, dynamic>{
      'id': 10,
      'name': 'Acme Corporation',
      'phone': '(603)-996-3829',
      'email': 'acme_corp@yourcompany.example.com',
      'website': 'http://www.acme-example-company.com',
      'function': false,
      'street': '77 Santa Barbara Rd',
      'street2': false,
      'city': 'Pleasant Hill',
      'state_id': [13, 'California (US)'],
      'zip': '94523',
      'country_id': [233, 'United States'],
      'image_128': {'content': 'iVBORw0KGgo=', 'size': 10692},
      'partner_latitude': 0.0,
      'partner_longitude': 0.0,
      'is_company': true,
      'parent_name': false,
      'vat': 'US12345673',
      'industry_id': false,
      'customer_rank': 14,
      'user_id': false,
      'property_payment_term_id': [4, '30 Days'],
      'credit_limit': 0.0,
      'credit': 48012.5,
      'currency_id': [1, 'USD'],
      'lang': 'en_US',
      'tz': false,
      'comment': false,
      'active': true,
      'type': 'contact',
      'create_date': '2026-09-29 10:23:30',
      'write_date': '2026-10-06 06:22:35',
      'category_id': [7],
      'company_id': false,
    };
    final person = <String, dynamic>{
      ...company,
      'id': 37,
      'name': 'Addison Olson',
      'function': 'Sales Representative',
      'is_company': false,
      'parent_name': 'Acme Corporation',
      'customer_rank': 0,
      'website': false,
      'category_id': [],
      'image_128': {'content': '/9j/4AAQSkZJRgAB', 'size': 4291},
    };
    final loner = <String, dynamic>{
      ...company,
      'id': 14,
      'name': 'LightsUp',
      'is_company': false,
      'vat': false,
      'state_id': false,
      'property_payment_term_id': false,
      'category_id': [],
    };

    test('a company', () {
      final c = Contact.fromJson(company);
      expect(c.isCompany, isTrue);
      expect(c.companyType, 'company');
      expect(c.companyName, isNull);
      expect(c.displayName, 'Acme Corporation');
      expect(c.vat, 'US12345673');
      expect(c.state, 'California (US)');
      expect(c.stateId, 13);
      expect(c.country, 'United States');
      expect(c.customerRank, '14');
      expect(c.paymentTerms, '30 Days');
      expect(c.paymentTermId, 4);
      expect(c.currency, 'USD');
      expect(c.totalReceivable, 48012.5);
      expect(c.categoryIds, [7]);
      expect(c.createdAt, DateTime.parse('2026-09-29 10:23:30'));
      expect(c.imageUrl, 'iVBORw0KGgo=');
      expect(c.hasValidCoordinates(), isFalse);
    });

    test('a person who works for a company', () {
      final c = Contact.fromJson(person);
      expect(c.isCompany, isFalse);
      expect(c.companyType, 'person');
      expect(c.companyName, 'Acme Corporation');
      expect(c.function, 'Sales Representative');
      expect(c.imageUrl, '/9j/4AAQSkZJRgAB');
    });

    test('a person with no company and no tax ID', () {
      final c = Contact.fromJson(loner);
      expect(c.isCompany, isFalse);
      expect(c.companyType, 'person');
      expect(c.companyName, isNull);
      expect(c.vat, 'false');
      expect(c.state, isNull);
      expect(c.stateId, isNull);
      expect(c.paymentTerms, isNull);
    });
  });

  group('ContactProvider on the connected generation', () {
    late MockCustomerService service;
    late MockConnectivityService connectivity;
    late MockSessionService session;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = MockCustomerService();
      connectivity = MockConnectivityService();
      session = MockSessionService();
      when(() => connectivity.isConnected).thenReturn(true);
      when(() => session.hasValidSession).thenReturn(true);
      when(() => service.getContactCount(any())).thenAnswer((_) async => 0);
      when(
        () => service.fetchContacts(
          domain: any(named: 'domain'),
          fields: any(named: 'fields'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => []);
    });

    /// The `domain` and `fields` the provider sent to the service.
    Future<(List<dynamic>, List<String>)> sentFor(int generation) async {
      final provider = ContactProvider(
        customerService: service,
        connectivityService: connectivity,
        sessionService: session,
        serverGeneration: () async => generation,
      );
      await provider.fetchContacts(searchQuery: 'acme');
      expect(provider.error, isNull);

      final captured = verify(
        () => service.fetchContacts(
          domain: captureAny(named: 'domain'),
          fields: captureAny(named: 'fields'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).captured;
      return (
        List<dynamic>.from(captured[0] as List),
        List<String>.from(captured[1] as List),
      );
    }

    test(
      'Odoo 20: no removed field in the read, company search by parent',
      () async {
        final (domain, fields) = await sentFor(20);

        expect(fields, isNot(contains('company_name')));
        expect(fields, contains('parent_name'));
        expect(fields, contains('is_company'));
        expect(domain, contains(equals(['parent_id.name', 'ilike', 'acme'])));
        expect(
          domain.whereType<List>().where((l) => l.first == 'company_name'),
          isEmpty,
        );
      },
    );

    test(
      'Odoo 19: unchanged, company_name in the read and the search',
      () async {
        final (domain, fields) = await sentFor(19);

        expect(fields, contains('company_name'));
        expect(fields, isNot(contains('parent_name')));
        expect(domain, contains(equals(['company_name', 'ilike', 'acme'])));
      },
    );

    test('an unknown version behaves as before', () async {
      final (domain, fields) = await sentFor(0);

      expect(fields, kContactListFields);
      expect(domain, contains(equals(['company_name', 'ilike', 'acme'])));
    });

    test('the customer filter is kept on every generation', () async {
      for (final generation in [19, 20]) {
        clearInteractions(service);
        final (domain, _) = await sentFor(generation);
        expect(domain.last, ['customer_rank', '>', 0]);
      }
    });
  });
}
