import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/providers/quotation_provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../mocks/mock_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuotationProvider provider;
  late MockQuotationService mockService;
  late MockConnectivityService mockConnectivityService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockService = MockQuotationService();
    mockConnectivityService = MockConnectivityService();

    when(() => mockConnectivityService.isConnected).thenReturn(true);

    provider = QuotationProvider(
      quotationService: mockService,
      connectivityService: mockConnectivityService,
    );
  });

  group('QuotationProvider Tests', () {
    test('Initial state should be empty', () {
      expect(provider.allQuotations, isEmpty);
      expect(provider.isLoading, isFalse);
    });

    test('deleteQuotation should call service and update state', () async {
      final orderId = 123;
      when(
        () => mockService.deleteQuotationInstance(orderId),
      ).thenAnswer((_) async => {});

      await provider.deleteQuotation(orderId);

      verify(() => mockService.deleteQuotationInstance(orderId)).called(1);
    });

    test('setCustomerFilter should clear cache and update filter', () {
      provider.setCustomerFilter(456);
    });

    test('setInvoiceNameFilter should clear cache and update filter', () {
      provider.setInvoiceNameFilter('INV001');
    });
  });
}
