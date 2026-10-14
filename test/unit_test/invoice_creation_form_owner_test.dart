import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/models/contact.dart';
import 'package:mobo_sales/providers/invoice_creation_provider.dart';

import '../mocks/mock_services.dart';

/// The create-invoice form lives in one provider for the whole app. What one
/// create or edit screen leaves in it must never show on the next one.
void main() {
  late CreateInvoiceProvider provider;

  setUp(() {
    provider = CreateInvoiceProvider(
      customerService: MockCustomerService(),
      productService: MockProductService(),
      invoiceService: MockInvoiceService(),
    );
  });

  /// An invoice half made (or opened for editing): a customer and a date.
  void fillIn() {
    provider.setSelectedCustomer(Contact(id: 7, name: 'Azure Interior'));
    provider.setInvoiceDate(DateTime(2020, 1, 15));
  }

  test('a screen that opens finds the form empty', () {
    fillIn();
    expect(provider.selectedCustomer, isNotNull);

    provider.claimForm(Object());

    expect(provider.selectedCustomer, isNull);
    expect(provider.invoiceLines, isEmpty);
    expect(provider.invoiceDate?.year, DateTime.now().year);
  });

  test('a screen that closes empties it', () {
    final screen = Object();
    provider.claimForm(screen);
    fillIn();

    provider.releaseForm(screen);

    expect(provider.selectedCustomer, isNull);
  });

  test(
    'a screen that closes after the next one opened leaves its form alone',
    () {
      // The old screen's release runs a frame after it closed; the new screen
      // may have opened (and been filled in) by then.
      final old = Object();
      final next = Object();
      provider.claimForm(old);
      fillIn();

      provider.claimForm(next);
      fillIn();
      provider.releaseForm(old);

      expect(
        provider.selectedCustomer?.id,
        7,
        reason: 'the new screen\'s form',
      );
    },
  );

  test('opening, filling in, closing and opening again never carries over', () {
    final first = Object();
    provider.claimForm(first);
    fillIn();
    provider.releaseForm(first);

    provider.claimForm(Object());

    expect(provider.selectedCustomer, isNull);
    expect(provider.errorMessage, isEmpty);
    expect(provider.lastCreatedInvoiceName, isNull);
  });

  test('the form is emptied without telling anyone while a screen is being '
      'built, and told otherwise', () {
    var told = 0;
    provider.addListener(() => told++);

    provider.claimForm(Object());
    expect(told, 0, reason: 'a screen being built is not told');

    final screen = Object();
    provider.claimForm(screen);
    provider.releaseForm(screen);
    expect(told, 1, reason: 'a closed one tells the listeners once');
  });
}
