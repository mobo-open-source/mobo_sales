import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobo_sales/providers/settings_provider.dart';
import '../mocks/mock_services.dart';

void main() {
  late MockSettingsService mockSettingsService;
  late SettingsProvider provider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockSettingsService = MockSettingsService();
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsProvider Tests', () {
    test('Initialization loads local settings', () async {
      SharedPreferences.setMockInitialValues({
        'selected_language': 'fr_FR',
        'enable_notifications': false,
      });

      when(
        () => mockSettingsService.fetchUserProfile(),
      ).thenAnswer((_) async => null);
      when(
        () => mockSettingsService.fetchAvailableLanguages(),
      ).thenAnswer((_) async => []);
      when(
        () => mockSettingsService.fetchAvailableCurrencies(),
      ).thenAnswer((_) async => []);
      when(
        () => mockSettingsService.fetchAvailableTimezones(),
      ).thenAnswer((_) async => []);

      provider = SettingsProvider(settingsService: mockSettingsService);
      await provider.initialize();

      expect(provider.selectedLanguage, 'fr_FR');
      expect(provider.enableNotifications, false);
    });

    test('fetchAvailableLanguages success updates list', () async {
      final languages = [
        {'code': 'en_US', 'name': 'English'},
      ];
      when(
        () => mockSettingsService.fetchAvailableLanguages(),
      ).thenAnswer((_) async => languages);

      provider = SettingsProvider(settingsService: mockSettingsService);
      await provider.fetchAvailableLanguages();

      expect(provider.availableLanguages, languages);
      expect(provider.languagesUpdatedAt, isNotNull);
    });

    test('fetchAvailableLanguages failure sets default list', () async {
      when(
        () => mockSettingsService.fetchAvailableLanguages(),
      ).thenThrow(Exception('API Fail'));

      provider = SettingsProvider(settingsService: mockSettingsService);
      await provider.fetchAvailableLanguages();

      expect(provider.availableLanguages, isNotEmpty);
      expect(
        provider.availableLanguages.any((l) => l['code'] == 'en_US'),
        true,
      );
    });

    test('fetchUserProfile updates profile and company info', () async {
      final userProfile = {
        'id': 1,
        'name': 'User',
        'company_id': [1, 'Company'],
      };
      final companyInfo = {
        'id': 1,
        'currency_id': [2, 'EUR'],
      };

      when(
        () => mockSettingsService.fetchUserProfile(),
      ).thenAnswer((_) async => userProfile);
      when(
        () => mockSettingsService.fetchCompanyInfo(1),
      ).thenAnswer((_) async => companyInfo);

      provider = SettingsProvider(settingsService: mockSettingsService);
      await provider.fetchUserProfile();

      expect(provider.userProfile, userProfile);
      expect(provider.companyInfo, companyInfo);
      expect(provider.selectedCurrency, 'EUR');
    });

    test(
      'updateUserPreferences calls service and updates local state',
      () async {
        final initialProfile = {'id': 1, 'lang': 'en_US'};
        when(
          () => mockSettingsService.fetchUserProfile(),
        ).thenAnswer((_) async => initialProfile);

        provider = SettingsProvider(settingsService: mockSettingsService);
        await provider.fetchUserProfile();

        when(
          () => mockSettingsService.updateUserPreferences(any(), any()),
        ).thenAnswer((_) async {});

        await provider.updateUserPreferences(language: 'fr_FR');

        verify(
          () => mockSettingsService.updateUserPreferences(1, {'lang': 'fr_FR'}),
        ).called(1);
        expect(provider.selectedLanguage, 'fr_FR');
        expect(provider.userProfile!['lang'], 'fr_FR');
      },
    );
  });
}
