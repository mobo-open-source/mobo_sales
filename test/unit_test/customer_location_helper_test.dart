import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/utils/customer_location_helper.dart';
import 'package:mobo_sales/models/contact.dart';
import 'package:mobo_sales/services/session_service.dart';
import 'package:odoo_rpc/odoo_rpc.dart';

class MockSessionService extends Mock implements SessionService {}

class MockOdooClient extends Mock implements OdooClient {}

void main() {
  late MockSessionService mockSessionService;
  late MockOdooClient mockOdooClient;

  setUpAll(() {
    registerFallbackValue(Uri.parse('http://localhost'));
  });

  setUp(() {
    mockSessionService = MockSessionService();
    mockOdooClient = MockOdooClient();

    when(
      () => mockSessionService.client,
    ).thenAnswer((_) async => mockOdooClient);
  });

  testWidgets('handleCustomerLocation shows warning when no address provided', (
    WidgetTester tester,
  ) async {
    final contact = Contact(
      id: 1,
      name: 'Test Customer',
      street: null,
      city: null,
      zip: null,
    );

    bool updated = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<SessionService>.value(
            value: mockSessionService,
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => handleCustomerLocation(
                    context: context,
                    parentContext: context,
                    contact: contact,
                    onContactUpdated: (_) => updated = true,
                  ),
                  child: const Text('Check Location'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Check Location'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Warning'), findsOneWidget);
    expect(
      find.text('Cannot geolocalize: No address available for this customer.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 5));
    expect(updated, isFalse);
  });

  testWidgets('handleCustomerLocation shows dialog when coordinates missing', (
    WidgetTester tester,
  ) async {
    final contact = Contact(
      id: 1,
      name: 'Test Customer',
      street: '123 Test St',
      city: 'Test City',
      zip: '12345',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<SessionService>.value(
            value: mockSessionService,
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => handleCustomerLocation(
                    context: context,
                    parentContext: context,
                    contact: contact,
                    onContactUpdated: (_) {},
                  ),
                  child: const Text('Check Location'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Check Location'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Geolocalize Customer'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('handleCustomerLocation performs geolocalization on server', (
    WidgetTester tester,
  ) async {
    final contact = Contact(
      id: 1,
      name: 'Test Customer',
      street: '123 Test St',
      city: 'Test City',
      zip: '12345',
    );

    Contact? updatedContact;

    when(() => mockOdooClient.callKw(any())).thenAnswer((invocation) async {
      final params = invocation.positionalArguments[0] as Map<String, dynamic>;
      if (params['method'] == 'geo_localize') return true;
      if (params['method'] == 'search_read') {
        return [
          {'id': 1, 'partner_latitude': 12.345, 'partner_longitude': 67.890},
        ];
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<SessionService>.value(
            value: mockSessionService,
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => handleCustomerLocation(
                    context: context,
                    parentContext: context,
                    contact: contact,
                    onContactUpdated: (c) => updatedContact = c,
                  ),
                  child: const Text('Check Location'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Check Location'));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Geolocalize'));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(updatedContact, isNotNull);
    expect(updatedContact!.latitude, 12.345);
    expect(updatedContact!.longitude, 67.890);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('handleCustomerLocation launches maps when coordinates exist', (
    WidgetTester tester,
  ) async {
    final contact = Contact(
      id: 1,
      name: 'Test Customer',
      latitude: 10.0,
      longitude: 20.0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<SessionService>.value(
            value: mockSessionService,
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => handleCustomerLocation(
                    context: context,
                    parentContext: context,
                    contact: contact,
                    onContactUpdated: (_) {},
                  ),
                  child: const Text('Check Location'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Check Location'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Geolocalize Customer'), findsNothing);
  });
}
