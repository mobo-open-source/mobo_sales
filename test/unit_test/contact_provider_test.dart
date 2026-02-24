import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobo_sales/providers/contact_provider.dart';
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
      provider.setFilterState(showActiveOnly: false, showCompaniesOnly: true);
      expect(provider.showActiveOnly, false);
      expect(provider.showCompaniesOnly, true);

      provider.clearFilters();
      expect(provider.showActiveOnly, true);
      expect(provider.showCompaniesOnly, false);
    });
  });
}
