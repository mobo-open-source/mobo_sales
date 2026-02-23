import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobo_sales/providers/currency_provider.dart';
import '../mocks/mock_services.dart';

void main() {
  late MockCurrencyService mockCurrencyService;
  late CurrencyProvider provider;

  setUp(() {
    mockCurrencyService = MockCurrencyService();
  });

  group('CurrencyProvider Tests', () {
    test('Initial state is correct', () {
      when(
        () => mockCurrencyService.fetchCompanyCurrency(),
      ).thenAnswer((_) async => null);

      provider = CurrencyProvider(currencyService: mockCurrencyService);

      expect(provider.currency, 'USD');
      expect(provider.isLoading, true);
      expect(provider.error, null);
    });

    test('fetchCompanyCurrency success updates currency', () async {
      when(
        () => mockCurrencyService.fetchCompanyCurrency(),
      ).thenAnswer((_) async => {'id': 2, 'name': 'EUR'});

      provider = CurrencyProvider(currencyService: mockCurrencyService);

      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(provider.currency, 'EUR');
      expect(provider.companyCurrencyId, 'EUR');
      expect(provider.isLoading, false);
      expect(provider.error, null);

      expect(provider.currencyFormat.locale.startsWith('de'), true);

      expect(provider.getCurrencySymbol(provider.currency), '€');
    });

    test('fetchCompanyCurrency failure sets error', () async {
      when(
        () => mockCurrencyService.fetchCompanyCurrency(),
      ).thenThrow(Exception('API Error'));

      provider = CurrencyProvider(currencyService: mockCurrencyService);

      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(provider.error, contains('API Error'));
      expect(provider.isLoading, false);
      expect(provider.currency, 'USD');
    });

    test('getCurrencySymbol returns correct symbols', () {
      when(
        () => mockCurrencyService.fetchCompanyCurrency(),
      ).thenAnswer((_) async => null);
      provider = CurrencyProvider(currencyService: mockCurrencyService);

      expect(provider.getCurrencySymbol('USD'), '\$');
      expect(provider.getCurrencySymbol('EUR'), '€');
      expect(provider.getCurrencySymbol('INR'), '₹');
      expect(provider.getCurrencySymbol('UNKNOWN'), 'UNKNOWN');
    });

    test('formatAmount formats correctly', () {
      when(
        () => mockCurrencyService.fetchCompanyCurrency(),
      ).thenAnswer((_) async => null);
      provider = CurrencyProvider(currencyService: mockCurrencyService);

      expect(provider.formatAmount(100.50), contains('100.50'));
      expect(provider.formatAmount(100.50), contains('\$'));

      expect(provider.formatAmount(50.0, currency: 'EUR'), contains('50,00'));
      expect(provider.formatAmount(50.0, currency: 'EUR'), contains('€'));
    });

    test('clearData resets state', () async {
      when(
        () => mockCurrencyService.fetchCompanyCurrency(),
      ).thenAnswer((_) async => {'id': 2, 'name': 'EUR'});
      provider = CurrencyProvider(currencyService: mockCurrencyService);
      await Future.delayed(Duration.zero);

      expect(provider.currency, 'EUR');

      await provider.clearData();

      expect(provider.currency, 'USD');
      expect(provider.error, null);
      expect(provider.companyCurrencyIdList, null);
    });
  });
}
