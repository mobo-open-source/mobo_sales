import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobo_sales/providers/invoice_creation_provider.dart';
import 'package:mobo_sales/models/contact.dart';
import 'package:mobo_sales/models/product.dart';
import '../mocks/mock_services.dart';

void main() {
  late MockCustomerService mockCustomerService;
  late MockProductService mockProductService;
  late MockInvoiceService mockInvoiceService;
  late CreateInvoiceProvider provider;

  setUp(() {
    mockCustomerService = MockCustomerService();
    mockProductService = MockProductService();
    mockInvoiceService = MockInvoiceService();

    provider = CreateInvoiceProvider(
      customerService: mockCustomerService,
      productService: mockProductService,
      invoiceService: mockInvoiceService,
    );
  });

  group('InvoiceCreationProvider Tests', () {
    test('Initial state is correct', () {
      expect(provider.isLoading, false);
      expect(provider.customers, isEmpty);
      expect(provider.saleOrders, isEmpty);
      expect(provider.products, isEmpty);
      expect(provider.invoiceLines, isEmpty);
      expect(provider.isCreatingInvoice, false);
    });

    test('fetchCustomers calls CustomerService', () async {
      final mockCustomers = [
        Contact(id: 1, name: 'Customer A'),
        Contact(id: 2, name: 'Customer B'),
      ];
      when(
        () => mockCustomerService.fetchAllCustomers(
          searchQuery: any(named: 'searchQuery'),
        ),
      ).thenAnswer((_) async => mockCustomers);

      await provider.fetchCustomers();

      verify(
        () => mockCustomerService.fetchAllCustomers(
          searchQuery: any(named: 'searchQuery'),
        ),
      ).called(1);
      expect(provider.customers.length, 2);
      expect(provider.customers.first.name, 'Customer A');
      expect(provider.filteredCustomers.length, 2);
    });

    test('fetchProducts calls ProductService', () async {
      final mockProducts = [
        {
          'id': 1,
          'name': 'Product A',
          'list_price': 100.0,
          'product_variant_count': 1,
          'qty_available': 10,
          'default_code': 'P001',
        },
      ];
      when(
        () => mockProductService.getProductCount(any()),
      ).thenAnswer((_) async => 1);
      when(
        () => mockProductService.fetchProducts(
          domain: any(named: 'domain'),
          fields: any(named: 'fields'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
          order: any(named: 'order'),
        ),
      ).thenAnswer((_) async => mockProducts);

      await provider.fetchProducts(category: 'all');

      verify(
        () => mockProductService.fetchProducts(
          domain: any(named: 'domain'),
          fields: any(named: 'fields'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
          order: any(named: 'order'),
        ),
      ).called(1);
      expect(provider.getProductsForCategory('all').length, 1);
      expect(provider.getProductsForCategory('all').first.name, 'Product A');
    });

    test('fetchPaymentTerms calls InvoiceService', () async {
      final mockTerms = [
        {'id': 1, 'name': 'Immediate Payment'},
        {'id': 2, 'name': '30 Days'},
      ];
      when(
        () => mockInvoiceService.fetchPaymentTerms(),
      ).thenAnswer((_) async => mockTerms);

      await provider.fetchPaymentTerms();

      verify(() => mockInvoiceService.fetchPaymentTerms()).called(1);
      expect(provider.paymentTerms.length, 2);
      expect(provider.paymentTerms.first.name, 'Immediate Payment');
    });

    test('addInvoiceLine adds line correctly', () async {
      final product = Product(
        id: '1',
        name: 'Test Product',
        listPrice: 50.0,
        qtyAvailable: 10,
        variantCount: 0,
        defaultCode: 'T001',
        taxId: 1,
      );

      when(
        () => mockProductService.fetchProductData(
          any(),
          fields: any(named: 'fields'),
        ),
      ).thenAnswer(
        (_) async => {
          'taxes_id': [1],
        },
      );

      when(
        () => mockInvoiceService.getCurrencyId(any()),
      ).thenAnswer((_) async => 1);
      when(() => mockInvoiceService.calculateTax(any())).thenAnswer(
        (_) async => {
          'amount_untaxed': 100.0,
          'amount_tax': 10.0,
          'amount_total': 110.0,
        },
      );

      provider.setSelectedCustomer(Contact(id: 1, name: 'Test Customer'));

      await provider.addInvoiceLine(product, 2.0, 50.0);

      expect(provider.invoiceLines.length, 1);
      expect(provider.invoiceLines.first['product_name'], 'Test Product');
      expect(provider.invoiceLines.first['quantity'], 2.0);
      expect(provider.invoiceLines.first['subtotal'], 100.0);
    });
  });
}
