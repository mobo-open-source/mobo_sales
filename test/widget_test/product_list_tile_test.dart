import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/widgets/product_list_tile.dart';
import 'package:mobo_sales/models/product.dart';
import 'package:mobo_sales/providers/currency_provider.dart';
import 'package:intl/intl.dart';

class MockCurrencyProvider extends Mock implements CurrencyProvider {}

void main() {
  late MockCurrencyProvider mockCurrencyProvider;

  setUp(() {
    mockCurrencyProvider = MockCurrencyProvider();
    when(() => mockCurrencyProvider.currency).thenReturn('USD');
    when(
      () => mockCurrencyProvider.currencyFormat,
    ).thenReturn(NumberFormat.currency(symbol: '\$'));
    when(
      () => mockCurrencyProvider.formatAmount(
        any(),
        currency: any(named: 'currency'),
      ),
    ).thenReturn('\$0.00');
  });

  Widget createWidgetUnderTest(Product product, {VoidCallback? onTap}) {
    return ChangeNotifierProvider<CurrencyProvider>.value(
      value: mockCurrencyProvider,
      child: MaterialApp(
        home: Scaffold(
          body: ProductListTile(
            id: product.id,
            name: product.name,
            listPrice: product.listPrice,
            qtyAvailable: product.qtyAvailable,
            defaultCode: product.defaultCode,
            variantCount: product.variantCount,
            isDark: false,
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  testWidgets('should display product details correctly', (
    WidgetTester tester,
  ) async {
    final product = Product(
      id: '1',
      name: 'Test Product',
      listPrice: 99.99,
      qtyAvailable: 10,
      variantCount: 0,
      defaultCode: 'TP001',
    );

    await tester.pumpWidget(createWidgetUnderTest(product));

    expect(find.text('Test Product'), findsOneWidget);
    expect(find.text('\$0.00'), findsOneWidget);
    expect(find.text('10 in stock'), findsOneWidget);
    expect(find.text('SKU: TP001'), findsOneWidget);
  });

  testWidgets('should show out of stock color when qty is 0', (
    WidgetTester tester,
  ) async {
    final product = Product(
      id: '1',
      name: 'Test Product',
      listPrice: 99.99,
      qtyAvailable: 0,
      variantCount: 0,
      defaultCode: '',
    );

    await tester.pumpWidget(createWidgetUnderTest(product));

    final qtyText = find.text('0 in stock');
    expect(qtyText, findsOneWidget);

    final textWidget = tester.widget<Text>(qtyText);
    expect(textWidget.style?.color, equals(Colors.red[700]));
  });

  testWidgets('should trigger onTap when tapped', (WidgetTester tester) async {
    bool tapped = false;
    final product = Product(
      id: '1',
      name: 'Test Product',
      listPrice: 99.99,
      qtyAvailable: 10,
      variantCount: 0,
      defaultCode: '',
    );

    await tester.pumpWidget(
      createWidgetUnderTest(product, onTap: () => tapped = true),
    );

    await tester.tap(find.byType(ProductListTile));
    expect(tapped, isTrue);
  });
}
