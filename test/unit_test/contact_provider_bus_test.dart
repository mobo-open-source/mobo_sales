import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobo_sales/providers/contact_provider.dart';
import 'package:mobo_sales/services/data_change_bus.dart';

import '../mocks/mock_services.dart';

/// The customer list keeps up with customers created, edited and archived
/// anywhere in the app, without going back to its loading skeleton.
void main() {
  late DataChangeBus bus;
  late MockCustomerService customers;
  late MockConnectivityService connectivity;
  late MockSessionService session;
  late ContactProvider provider;

  /// What the "server" holds, in the order it is listed.
  late List<Map<String, dynamic>> server;
  late List<List<dynamic>> domainsRead;
  late List<int> offsetsRead;
  var failReads = false;

  Map<String, dynamic> row(int id, String name) => {
    'id': id,
    'name': name,
    'is_company': false,
    'active': true,
  };

  Future<void> afterDebounce() => Future<void>.delayed(
    ContactProvider.changeDebounce + const Duration(milliseconds: 150),
  );

  setUp(() {
    bus = DataChangeBus.forTesting();
    customers = MockCustomerService();
    connectivity = MockConnectivityService();
    session = MockSessionService();
    server = [row(1, 'Ada')];
    domainsRead = [];
    offsetsRead = [];
    failReads = false;

    when(() => connectivity.isConnected).thenReturn(true);
    when(() => session.hasValidSession).thenReturn(true);
    when(
      () => customers.getContactCount(any()),
    ).thenAnswer((_) async => server.length);
    when(
      () => customers.fetchContacts(
        domain: any(named: 'domain'),
        fields: any(named: 'fields'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer((invocation) async {
      if (failReads) throw Exception('connection reset');
      final limit = invocation.namedArguments[#limit] as int;
      final offset = invocation.namedArguments[#offset] as int;
      domainsRead.add(invocation.namedArguments[#domain] as List<dynamic>);
      offsetsRead.add(offset);
      return server.skip(offset).take(limit).toList();
    });

    provider = ContactProvider(
      customerService: customers,
      connectivityService: connectivity,
      sessionService: session,
      serverGeneration: () async => 17,
      bus: bus,
    );
  });

  tearDown(() => provider.dispose());

  test('a customer created elsewhere shows up, with no loading state', () async {
    await provider.fetchContacts();
    expect(provider.contacts.map((c) => c.name), ['Ada']);

    final seenLoading = <bool>[];
    final seenCounts = <int>[];
    provider.addListener(() {
      seenLoading.add(provider.isLoading || provider.isSearching);
      seenCounts.add(provider.contacts.length);
    });

    server = [row(1, 'Ada'), row(2, 'Grace')];
    bus.publish(DataEntity.customer, DataChangeKind.created, id: 2);
    await afterDebounce();

    expect(provider.contacts.map((c) => c.name), ['Ada', 'Grace']);
    expect(provider.totalContacts, 2);
    expect(seenLoading, isNotEmpty);
    expect(seenLoading, everyElement(isFalse));
    // The rows never blanked out on the way: no notification saw an empty list.
    expect(seenCounts, everyElement(greaterThan(0)));
  });

  test('an edit shows the new name; an archive takes the row out', () async {
    server = [row(1, 'Ada'), row(2, 'Grace')];
    await provider.fetchContacts();

    server = [row(1, 'Ada Lovelace'), row(2, 'Grace')];
    bus.publish(DataEntity.customer, DataChangeKind.updated, id: 1);
    await afterDebounce();
    expect(provider.contacts.map((c) => c.name), ['Ada Lovelace', 'Grace']);

    server = [row(1, 'Ada Lovelace')];
    bus.publish(DataEntity.customer, DataChangeKind.deleted, id: 2);
    await afterDebounce();
    expect(provider.contacts.map((c) => c.id), [1]);
    expect(provider.totalContacts, 1);
  });

  test('a burst of customer events is read once', () async {
    await provider.fetchContacts();
    domainsRead.clear();

    server = [row(1, 'Ada'), row(2, 'Grace'), row(3, 'Alan')];
    bus.publish(DataEntity.customer, DataChangeKind.created, id: 2);
    bus.publish(DataEntity.customer, DataChangeKind.created, id: 3);
    bus.publish(DataEntity.customer, DataChangeKind.updated, id: 1);
    await afterDebounce();

    expect(domainsRead, hasLength(1));
    expect(provider.contacts, hasLength(3));
  });

  test('other kinds of change are not its business', () async {
    await provider.fetchContacts();
    domainsRead.clear();

    bus.quotationChanged(5);
    bus.invoiceChanged(6);
    bus.paymentChanged(7);
    await afterDebounce();

    expect(domainsRead, isEmpty);
  });

  test('before the first load there is nothing to bring up to date', () async {
    bus.publish(DataEntity.customer, DataChangeKind.created, id: 2);
    await afterDebounce();

    expect(domainsRead, isEmpty);
    expect(provider.hasInitiallyLoaded, isFalse);
  });

  test('it reads again with the search the list was read with', () async {
    await provider.fetchContacts(searchQuery: 'ada');
    domainsRead.clear();

    // Something else resets the provider's current search without reading
    // (the quote picker does); the list on screen is still the 'ada' one.
    provider.clearSearchState();

    bus.publish(DataEntity.customer, DataChangeKind.updated, id: 1);
    await afterDebounce();

    expect(domainsRead, hasLength(1));
    expect(domainsRead.single.toString(), contains('ada'));
  });

  test('the page the user is on is kept', () async {
    server = [for (var i = 1; i <= 60; i++) row(i, 'Customer $i')];
    await provider.fetchContacts();
    await provider.goToNextPage();
    expect(provider.currentPage, 1);
    expect(provider.contacts.first.id, 41);
    offsetsRead.clear();

    server = [
      row(100, 'New'),
      ...[for (var i = 1; i <= 60; i++) row(i, 'Customer $i')],
    ];
    bus.publish(DataEntity.customer, DataChangeKind.created, id: 100);
    await afterDebounce();

    expect(provider.currentPage, 1);
    expect(offsetsRead, [40]);
    expect(provider.contacts.first.id, 40);
  });

  test(
    'when the page is emptied the last page that is left is shown',
    () async {
      server = [for (var i = 1; i <= 50; i++) row(i, 'Customer $i')];
      await provider.fetchContacts();
      await provider.goToNextPage();
      expect(provider.currentPage, 1);
      expect(provider.contacts, hasLength(10));

      server = [for (var i = 1; i <= 40; i++) row(i, 'Customer $i')];
      bus.publish(DataEntity.customer, DataChangeKind.deleted, id: 50);
      await afterDebounce();

      expect(provider.currentPage, 0);
      expect(provider.contacts, hasLength(40));
      expect(provider.totalContacts, 40);
      expect(provider.canGoToNextPage, isFalse);
    },
  );

  test('a read that fails leaves the rows and says nothing', () async {
    await provider.fetchContacts();

    failReads = true;
    bus.publish(DataEntity.customer, DataChangeKind.updated, id: 1);
    await afterDebounce();

    expect(provider.contacts.map((c) => c.name), ['Ada']);
    expect(provider.error, isNull);
    expect(provider.isLoading, isFalse);
  });

  test('it asks nothing once the provider is gone', () async {
    await provider.fetchContacts();
    domainsRead.clear();

    provider.dispose();
    bus.publish(DataEntity.customer, DataChangeKind.updated, id: 1);
    await afterDebounce();

    expect(domainsRead, isEmpty);
    // tearDown disposes a second time; a ChangeNotifier may only be disposed
    // once, so make that a fresh one.
    provider = ContactProvider(
      customerService: customers,
      connectivityService: connectivity,
      sessionService: session,
      serverGeneration: () async => 17,
      bus: bus,
    );
  });

  test('removeContact drops the row and one from the count at once', () async {
    server = [row(1, 'Ada'), row(2, 'Grace')];
    await provider.fetchContacts();
    // The total is counted alongside the first read and lands a moment later.
    await Future<void>.delayed(Duration.zero);
    expect(provider.totalContacts, 2);

    var notified = 0;
    provider.addListener(() => notified++);
    provider.removeContact(1);

    expect(provider.contacts.map((c) => c.id), [2]);
    expect(provider.totalContacts, 1);
    expect(notified, 1);
  });
}
