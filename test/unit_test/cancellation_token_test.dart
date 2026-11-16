import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/cancellation_token.dart';

void main() {
  test('starts uncancelled', () {
    expect(CancellationToken().isCancelled, isFalse);
  });

  test('cancel is one-way and tells everyone listening', () {
    final token = CancellationToken();
    var calls = 0;
    token.addListener(() => calls++);

    token.cancel();
    expect(token.isCancelled, isTrue);
    expect(calls, 1);
  });

  test('cancelling twice fires the listeners once', () {
    // A Cancel button and a back gesture are both wired to it, and the user
    // can manage both: the popup must not be closed twice, which would take
    // the page underneath with it.
    final token = CancellationToken();
    var calls = 0;
    token.addListener(() => calls++);

    token.cancel();
    token.cancel();
    expect(calls, 1);
  });

  test('a listener added after the fact runs straight away', () {
    final token = CancellationToken()..cancel();
    var called = false;
    token.addListener(() => called = true);
    expect(called, isTrue);
  });

  test('throwIfCancelled is silent until it is not', () {
    final token = CancellationToken();
    expect(token.throwIfCancelled, returnsNormally);

    token.cancel();
    expect(token.throwIfCancelled, throwsA(isA<OperationCancelled>()));
  });

  test(
    'every listener runs even though one throws is not promised, but all are called in order',
    () {
      final token = CancellationToken();
      final order = <int>[];
      token.addListener(() => order.add(1));
      token.addListener(() => order.add(2));
      token.cancel();
      expect(order, [1, 2]);
    },
  );
}
