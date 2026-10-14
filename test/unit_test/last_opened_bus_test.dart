import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/providers/last_opened_provider.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The bus waits 350 ms for a burst to end before it calls its listeners.
const _afterDebounce = Duration(milliseconds: 500);

LastOpenedItem _item(String type, int id, {String? title}) => LastOpenedItem(
  id: '${type}_$id',
  type: type,
  title: title ?? '$type $id',
  subtitle: 'for someone',
  route: '/${type}_details',
  data: {'id': id},
  lastAccessed: DateTime(2026, 1, 1).add(Duration(minutes: id)),
  iconKey: 'page',
);

Future<List<String>> _storedIds([String key = 'last_opened_items']) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(key);
  if (raw == null) return const [];
  return (json.decode(raw) as List).map((e) => e['id'] as String).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DataChangeBus bus;
  late LastOpenedProvider provider;

  Future<void> openProviderWith(List<LastOpenedItem> items) async {
    SharedPreferences.setMockInitialValues({
      'last_opened_items': json.encode(items.map((i) => i.toJson()).toList()),
    });
    provider = LastOpenedProvider(bus: bus);
    await Future.delayed(Duration.zero);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bus = DataChangeBus.forTesting();
  });

  tearDown(() {
    provider.dispose();
  });

  group('LastOpenedProvider and the data change bus', () {
    test('a deleted quotation is removed and the list persisted', () async {
      await openProviderWith([
        _item('quotation', 7),
        _item('invoice', 3),
        _item('customer', 9),
      ]);
      expect(provider.items.map((i) => i.id), contains('quotation_7'));

      var notified = 0;
      provider.addListener(() => notified++);

      bus.quotationChanged(7, kind: DataChangeKind.deleted);
      await Future.delayed(_afterDebounce);

      expect(provider.items.map((i) => i.id), ['customer_9', 'invoice_3']);
      expect(await _storedIds(), ['customer_9', 'invoice_3']);
      expect(notified, 1);
    });

    test('a deleted invoice is removed and the list persisted', () async {
      await openProviderWith([_item('invoice', 3), _item('quotation', 7)]);

      bus.invoiceChanged(3, kind: DataChangeKind.deleted);
      await Future.delayed(_afterDebounce);

      expect(provider.items.map((i) => i.id), ['quotation_7']);
      expect(await _storedIds(), ['quotation_7']);
    });

    test('only the item of the matching type is removed', () async {
      // The same server id on a quotation and on an invoice: two records.
      await openProviderWith([_item('quotation', 5), _item('invoice', 5)]);

      bus.quotationChanged(5, kind: DataChangeKind.deleted);
      await Future.delayed(_afterDebounce);

      expect(provider.items.map((i) => i.id), ['invoice_5']);

      bus.invoiceChanged(5, kind: DataChangeKind.deleted);
      await Future.delayed(_afterDebounce);

      expect(provider.items, isEmpty);
      expect(await _storedIds(), isEmpty);
    });

    test('a burst of deletions is one notification', () async {
      await openProviderWith([
        _item('quotation', 1),
        _item('quotation', 2),
        _item('quotation', 3),
      ]);
      var notified = 0;
      provider.addListener(() => notified++);

      bus.quotationChanged(1, kind: DataChangeKind.deleted);
      bus.quotationChanged(2, kind: DataChangeKind.deleted);
      await Future.delayed(_afterDebounce);

      expect(provider.items.map((i) => i.id), ['quotation_3']);
      expect(notified, 1);
    });

    test('an update keeps the item but tells listeners', () async {
      await openProviderWith([_item('quotation', 7, title: 'S00007')]);
      var notified = 0;
      provider.addListener(() => notified++);

      bus.quotationChanged(7); // updated

      await Future.delayed(_afterDebounce);

      expect(provider.items.length, 1);
      expect(provider.items.single.id, 'quotation_7');
      expect(provider.items.single.title, 'S00007');
      expect(await _storedIds(), ['quotation_7']);
      expect(notified, 1);
    });

    test('an item that is not in the list changes nothing', () async {
      await openProviderWith([_item('quotation', 7)]);
      var notified = 0;
      provider.addListener(() => notified++);

      bus.quotationChanged(99, kind: DataChangeKind.deleted);
      await Future.delayed(_afterDebounce);

      expect(provider.items.map((i) => i.id), ['quotation_7']);
      expect(notified, 0);
    });

    test('other entities, creations and id-less events are ignored', () async {
      await openProviderWith([
        _item('quotation', 7),
        _item('invoice', 7),
        _item('customer', 7),
      ]);
      var notified = 0;
      provider.addListener(() => notified++);

      bus.quotationChanged(7, kind: DataChangeKind.created);
      bus.invoiceChanged(null, kind: DataChangeKind.deleted);
      bus.paymentChanged(7, kind: DataChangeKind.deleted);
      bus.publish(DataEntity.customer, DataChangeKind.deleted, id: 7);
      bus.publish(DataEntity.product, DataChangeKind.deleted, id: 7);
      await Future.delayed(_afterDebounce);

      expect(provider.items.length, 3);
      expect(notified, 0);
    });

    test(
      'a deletion right after construction is not lost to the load',
      () async {
        SharedPreferences.setMockInitialValues({
          'last_opened_items': json.encode([
            _item('quotation', 7).toJson(),
            _item('invoice', 3).toJson(),
          ]),
        });
        provider = LastOpenedProvider(bus: bus);
        // No wait: the stored list has not been read yet.
        bus.quotationChanged(7, kind: DataChangeKind.deleted);
        await Future.delayed(_afterDebounce);

        expect(provider.items.map((i) => i.id), ['invoice_3']);
        expect(await _storedIds(), ['invoice_3']);
      },
    );

    test('the removal is saved under the active session key', () async {
      final seeded = [_item('quotation', 7), _item('invoice', 3)];
      SharedPreferences.setMockInitialValues({
        'last_opened_items_acct': json.encode(
          seeded.map((i) => i.toJson()).toList(),
        ),
      });
      provider = LastOpenedProvider(bus: bus);
      provider.updateSession('acct');
      await Future.delayed(Duration.zero);
      expect(provider.items.length, 2);

      bus.quotationChanged(7, kind: DataChangeKind.deleted);
      await Future.delayed(_afterDebounce);

      expect(await _storedIds('last_opened_items_acct'), ['invoice_3']);
      expect(await _storedIds(), isEmpty);
    });

    test('a disposed provider no longer listens', () async {
      await openProviderWith([_item('quotation', 7)]);
      provider.dispose();

      bus.quotationChanged(7, kind: DataChangeKind.deleted);
      await Future.delayed(_afterDebounce);

      // Nothing was touched and nothing threw on the disposed notifier.
      expect(await _storedIds(), ['quotation_7']);

      // tearDown disposes once more; rebuild a live one so that is harmless.
      provider = LastOpenedProvider(bus: bus);
    });

    test('with no bus given it listens on the app-wide one', () async {
      SharedPreferences.setMockInitialValues({
        'last_opened_items': json.encode([
          _item('quotation', 7).toJson(),
          _item('invoice', 3).toJson(),
        ]),
      });
      provider = LastOpenedProvider();
      await Future.delayed(Duration.zero);
      expect(provider.items.length, 2);

      DataChangeBus.instance.quotationChanged(7, kind: DataChangeKind.deleted);
      await Future.delayed(_afterDebounce);

      expect(provider.items.map((i) => i.id), ['invoice_3']);
    });
  });
}
