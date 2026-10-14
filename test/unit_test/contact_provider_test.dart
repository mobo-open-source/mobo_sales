import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobo_sales/models/contact.dart';
import 'package:mobo_sales/providers/contact_provider.dart';
import 'package:mobo_sales/services/customer_service.dart';
import '../mocks/mock_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContactProvider provider;
  late MockCustomerService mockCustomerService;
  late MockConnectivityService mockConnectivityService;
  late MockSessionService mockSessionService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockCustomerService = MockCustomerService();
    mockConnectivityService = MockConnectivityService();
    mockSessionService = MockSessionService();

    provider = ContactProvider(
      customerService: mockCustomerService,
      connectivityService: mockConnectivityService,
      sessionService: mockSessionService,
    );

    when(() => mockConnectivityService.isConnected).thenReturn(true);
    when(() => mockSessionService.hasValidSession).thenReturn(true);
  });

  group('ContactProvider Tests', () {
    test('Initial state should be empty', () {
      expect(provider.contacts, isEmpty);
      expect(provider.isLoading, false);
      expect(provider.error, isNull);
    });

    test('fetchContacts success', () async {
      final mockContactData = [
        {
          'id': 1,
          'name': 'Contact 1',
          'phone': '123456',
          'email': 'test@example.com',
          'is_company': false,
          'active': true,
        },
      ];

      when(
        () => mockCustomerService.getContactCount(any()),
      ).thenAnswer((_) async => 1);
      when(
        () => mockCustomerService.fetchContacts(
          domain: any(named: 'domain'),
          fields: any(named: 'fields'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => mockContactData);

      await provider.fetchContacts();

      expect(provider.contacts.length, 1);
      expect(provider.contacts[0].name, 'Contact 1');
      expect(provider.isLoading, false);
      expect(provider.error, isNull);
    });

    test('fetchContacts failure', () async {
      when(
        () => mockCustomerService.getContactCount(any()),
      ).thenAnswer((_) async => 0);
      when(
        () => mockCustomerService.fetchContacts(
          domain: any(named: 'domain'),
          fields: any(named: 'fields'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenThrow(Exception('Fetch error'));

      await provider.fetchContacts();

      expect(provider.contacts, isEmpty);
      expect(provider.error, contains('Fetch error'));
      expect(provider.isLoading, false);
    });

    test('fetchContacts no connection', () async {
      when(() => mockConnectivityService.isConnected).thenReturn(false);

      await provider.fetchContacts();

      expect(provider.error, contains('No internet connection'));
      expect(provider.isLoading, false);
    });

    test('clearFilters should reset filters', () {
      // Odoo's own default: the list opens customers-only.
      expect(provider.showCustomersOnly, true);

      provider.setFilterState(showArchivedOnly: true, showCompaniesOnly: true);
      expect(provider.showArchivedOnly, true);
      expect(provider.showCompaniesOnly, true);

      // Clearing takes every filter off, "Customers only" with the rest.
      provider.clearFilters();
      expect(provider.showArchivedOnly, false);
      expect(provider.showCustomersOnly, false);
      expect(provider.showCompaniesOnly, false);
    });

    group('the domain matches Odoo\'s Customers list', () {
      setUp(() {
        when(
          () => mockCustomerService.getContactCount(any()),
        ).thenAnswer((_) async => 0);
        when(
          () => mockCustomerService.fetchContacts(
            domain: any(named: 'domain'),
            fields: any(named: 'fields'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).thenAnswer((_) async => []);
      });

      Future<List<dynamic>> domainSentFor(Map<String, dynamic>? filters) async {
        await provider.fetchContacts(filters: filters);
        expect(provider.error, isNull);
        final captured = verify(
          () => mockCustomerService.fetchContacts(
            domain: captureAny(named: 'domain'),
            fields: any(named: 'fields'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          ),
        ).captured;
        return List<dynamic>.from(captured.single as List);
      }

      bool namesActive(List<dynamic> domain) =>
          domain.whereType<List>().any((leaf) => leaf.first == 'active');

      test(
        'with no filters it names no `active` leaf, so Odoo hides archived',
        () async {
          final domain = await domainSentFor(null);

          expect(namesActive(domain), isFalse);
          expect(domain, contains(equals(['customer_rank', '>', 0])));
        },
      );

      test(
        'Archived asks for `active = False`, which is what shows them',
        () async {
          final domain = await domainSentFor({'showArchivedOnly': true});

          expect(domain, contains(equals(['active', '=', false])));
          expect(
            domain.whereType<List>().where((l) => l.first == 'active'),
            hasLength(1),
          );
          expect(domain, contains(equals(['customer_rank', '>', 0])));
        },
      );

      test(
        'Customers only on keeps `customer_rank > 0`, with or without the key',
        () async {
          final domain = await domainSentFor({'showCustomersOnly': true});

          expect(domain, contains(equals(['customer_rank', '>', 0])));
        },
      );

      test(
        'Customers only off takes `customer_rank > 0` away, as removing the facet does',
        () async {
          final domain = await domainSentFor({'showCustomersOnly': false});

          expect(
            domain.whereType<List>().where((l) => l.first == 'customer_rank'),
            isEmpty,
          );
          expect(namesActive(domain), isFalse);
        },
      );

      test('Customers only off and Archived combine', () async {
        final domain = await domainSentFor({
          'showCustomersOnly': false,
          'showArchivedOnly': true,
        });

        expect(domain, contains(equals(['active', '=', false])));
        expect(
          domain.whereType<List>().where((l) => l.first == 'customer_rank'),
          isEmpty,
        );
      });

      test(
        'the list reads complete_name, so contacts show their company',
        () async {
          await provider.fetchContacts();
          final captured = verify(
            () => mockCustomerService.fetchContacts(
              domain: any(named: 'domain'),
              fields: captureAny(named: 'fields'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            ),
          ).captured;

          expect(
            List<String>.from(captured.single as List),
            contains('complete_name'),
          );
        },
      );
    });
  });

  group('Contact.listName', () {
    test('a contact under a company shows "Company, Contact"', () {
      final contact = Contact.fromJson({
        'id': 7,
        'name': 'Addison Olson',
        'complete_name': 'Acme Corporation, Addison Olson',
      });

      expect(contact.name, 'Addison Olson');
      expect(contact.listName, 'Acme Corporation, Addison Olson');
    });

    test('falls back to the name when the server sent none', () {
      expect(
        Contact.fromJson({'id': 1, 'name': 'OpenWood'}).listName,
        'OpenWood',
      );
      // Odoo sends `false` for an empty char.
      expect(
        Contact.fromJson({
          'id': 1,
          'name': 'OpenWood',
          'complete_name': false,
        }).listName,
        'OpenWood',
      );
      expect(
        Contact.fromJson({
          'id': 1,
          'name': 'OpenWood',
          'complete_name': '  ',
        }).listName,
        'OpenWood',
      );
    });

    test('survives copyWith', () {
      final contact = Contact.fromJson({
        'id': 7,
        'name': 'Addison Olson',
        'complete_name': 'Acme Corporation, Addison Olson',
      }).copyWith(email: 'a@b.c');

      expect(contact.listName, 'Acme Corporation, Addison Olson');
    });
  });

  group('CustomerService.fetchContacts', () {
    test(
      'lists in the order Odoo does, newest first among equal names',
      () async {
        final sent = <Map<String, dynamic>>[];
        final service = CustomerService.forTesting(
          callKw: (payload) async {
            sent.add(payload);
            return <Map<String, dynamic>>[];
          },
        );

        await service.fetchContacts(domain: const [], fields: const ['id']);

        final kwargs = sent.single['kwargs'] as Map<String, dynamic>;
        expect(kwargs['order'], 'complete_name asc, id desc');
      },
    );
  });
}
