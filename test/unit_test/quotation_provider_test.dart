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

  group('clearSearch', () {
    test('empties the field', () {
      provider.searchController.text = 'S00042';
      provider.clearSearch();

      expect(provider.searchController.text, isEmpty);
    });

    test('leaves no debounced reload behind', () async {
      // The bug: clearing the controller armed the 500ms debounce installed
      // in the constructor, so the page reloaded a second time after the one
      // it had already asked for — and the first of the two still carried the
      // query that had just been cleared.
      provider.searchController.text = 'S00042';
      provider.clearSearch();

      var notifications = 0;
      provider.addListener(() => notifications++);

      // Well past the debounce window.
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(notifications, 0);
      expect(provider.searchController.text, isEmpty);
    });

    test('typing still reloads, so the debounce is only cancelled', () async {
      provider.clearSearch();

      var notifications = 0;
      provider.addListener(() => notifications++);

      provider.searchController.text = 'S00042';
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(notifications, greaterThan(0));
    });
  });
}
