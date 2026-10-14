import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/data_change_bus.dart';

void main() {
  late DataChangeBus bus;

  setUp(() => bus = DataChangeBus.forTesting());

  test('a listener hears a change, and which one', () async {
    final heard = <DataChange>[];
    final sub = bus.listen(
      debounce: Duration.zero,
      onChange: (burst) => heard.addAll(burst),
    );
    bus.quotationChanged(7, kind: DataChangeKind.deleted);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(heard, hasLength(1));
    expect(heard.single.entity, DataEntity.quotation);
    expect(heard.single.kind, DataChangeKind.deleted);
    expect(heard.single.id, 7);
    sub.cancel();
  });

  test('a burst is one call carrying every change', () async {
    final calls = <List<DataChange>>[];
    final sub = bus.listen(
      debounce: const Duration(milliseconds: 60),
      onChange: calls.add,
    );
    bus.quotationChanged(1);
    bus.invoiceChanged(2, kind: DataChangeKind.created);
    bus.paymentChanged(3);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(calls, hasLength(1));
    expect(calls.single.map((c) => c.entity), [
      DataEntity.quotation,
      DataEntity.invoice,
      DataEntity.payment,
    ]);
    sub.cancel();
  });

  test('two bursts apart are two calls', () async {
    var calls = 0;
    final sub = bus.listen(
      debounce: const Duration(milliseconds: 30),
      onChange: (_) => calls++,
    );
    bus.quotationChanged(1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    bus.quotationChanged(1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(calls, 2);
    sub.cancel();
  });

  test('where filters what a listener hears', () async {
    final heard = <DataChange>[];
    final sub = bus.listen(
      where: (c) => c.isInvoice,
      debounce: Duration.zero,
      onChange: heard.addAll,
    );
    bus.quotationChanged(1);
    bus.invoiceChanged(2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(heard.map((c) => c.id), [2]);
    sub.cancel();
  });

  test('cancel stops it, and drops a call that was waiting', () async {
    var calls = 0;
    final sub = bus.listen(
      debounce: const Duration(milliseconds: 50),
      onChange: (_) => calls++,
    );
    bus.quotationChanged(1);
    sub.cancel();
    sub.cancel(); // twice is harmless
    bus.quotationChanged(2);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(calls, 0);
  });

  test('a listener can skip what it published itself', () async {
    final me = Object();
    final heard = <int?>[];
    final sub = bus.listen(
      where: (c) => c.origin != me,
      debounce: Duration.zero,
      onChange: (b) => heard.addAll(b.map((c) => c.id)),
    );
    bus.quotationChanged(1, origin: me);
    bus.quotationChanged(2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(heard, [2]);
    sub.cancel();
  });

  test('which changes can move the dashboard', () {
    bool dash(DataEntity e) =>
        DataChange(e, DataChangeKind.updated).affectsDashboard;
    expect(dash(DataEntity.quotation), isTrue);
    expect(dash(DataEntity.invoice), isTrue);
    expect(dash(DataEntity.payment), isTrue);
    expect(dash(DataEntity.customer), isTrue);
    expect(
      dash(DataEntity.product),
      isTrue,
      reason: 'the dashboard counts products and names the best sellers',
    );
    expect(
      dash(DataEntity.profile),
      isFalse,
      reason: 'the user\'s own profile moves no figure on the dashboard',
    );
  });

  test('a profile change is announced as one, and only as one', () async {
    final heard = <DataChange>[];
    final sub = bus.listen(
      where: (c) => c.isProfile,
      debounce: Duration.zero,
      onChange: heard.addAll,
    );
    final origin = Object();
    bus.profileChanged(origin: origin);
    bus.productChanged(5);
    bus.quotationChanged(1);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(heard, hasLength(1));
    expect(heard.single.entity, DataEntity.profile);
    expect(heard.single.kind, DataChangeKind.updated);
    expect(identical(heard.single.origin, origin), isTrue);
    sub.cancel();
  });

  test('a product change is announced with its kind and id', () {
    final heard = <DataChange>[];
    final sub = bus.listen(debounce: Duration.zero, onChange: heard.addAll);
    bus.productChanged(5);
    bus.productChanged(6, kind: DataChangeKind.created);
    return Future<void>.delayed(const Duration(milliseconds: 20)).then((_) {
      expect(heard.every((c) => c.isProduct), isTrue);
      expect(heard.map((c) => (c.kind, c.id)), [
        (DataChangeKind.updated, 5),
        (DataChangeKind.created, 6),
      ]);
      sub.cancel();
    });
  });

  test('publishing with nobody listening is harmless', () {
    bus.quotationChanged(1);
    DataChangeBus.instance.invoiceChanged(null);
  });

  test('a change is covered by a refresh that began after it', () async {
    final heard = <DataChange>[];
    final sub = bus.listen(debounce: Duration.zero, onChange: heard.addAll);
    bus.quotationChanged(1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final refreshStarted = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    bus.quotationChanged(1);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(heard, hasLength(2));
    expect(heard[0].isCoveredByRefreshStartedAt(refreshStarted), isTrue);
    expect(heard[1].isCoveredByRefreshStartedAt(refreshStarted), isFalse);
    expect(heard[1].isCoveredByRefreshStartedAt(null), isFalse);
    sub.cancel();
  });
}
