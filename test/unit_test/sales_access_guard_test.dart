import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/sales_access.dart';
import 'package:mobo_sales/services/sales_access_guard.dart';

void main() {
  late DateTime now;
  late int checks;
  late List<SalesAccessStatus> signedOutFor;
  late SalesAccessException? problem;
  late bool signedIn;
  late Object? checkError;

  SalesAccessGuard guard() => SalesAccessGuard(
    accessCheck: () async {
      checks++;
      if (checkError != null) throw checkError!;
      return problem;
    },
    signOut: (p) async => signedOutFor.add(p.status),
    hasSession: () async => signedIn,
    clock: () => now,
  );

  setUp(() {
    now = DateTime.utc(2026, 11, 4, 12);
    checks = 0;
    signedOutFor = [];
    problem = null;
    signedIn = true;
    checkError = null;
  });

  test('signs out with the reason when the Sales app is gone', () async {
    problem = const SalesAccessException.moduleMissing();
    await guard().checkNow();
    expect(signedOutFor, [SalesAccessStatus.moduleMissing]);
  });

  test('signs out when the user lost Sales access', () async {
    problem = const SalesAccessException.denied();
    await guard().checkNow();
    expect(signedOutFor, [SalesAccessStatus.denied]);
  });

  test('leaves a user with access alone', () async {
    await guard().checkNow();
    expect(checks, 1);
    expect(signedOutFor, isEmpty);
  });

  test('does nothing when nobody is signed in', () async {
    signedIn = false;
    problem = const SalesAccessException.moduleMissing();
    await guard().checkNow();
    expect(checks, 0);
    expect(signedOutFor, isEmpty);
  });

  test('stays on any error', () async {
    checkError = Exception('offline');
    await guard().checkNow();
    expect(signedOutFor, isEmpty);
  });

  test('skips a second check right after the first', () async {
    final g = guard();
    await g.checkNow();
    await g.checkNow();
    expect(checks, 1);
    now = now.add(SalesAccessGuard.minInterval);
    await g.checkNow();
    expect(checks, 2);
  });
}
