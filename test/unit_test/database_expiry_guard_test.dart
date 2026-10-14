import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/database_expiry_guard.dart';

void main() {
  late DateTime now;
  late int checks;
  late int signOuts;
  late bool expired;
  late bool signedIn;
  late Object? checkError;

  DatabaseExpiryGuard guard({Future<bool> Function()? check}) =>
      DatabaseExpiryGuard(
        expiryCheck:
            check ??
            () async {
              checks++;
              if (checkError != null) throw checkError!;
              return expired;
            },
        signOut: () async => signOuts++,
        hasSession: () async => signedIn,
        clock: () => now,
      );

  setUp(() {
    now = DateTime.utc(2026, 10, 12, 12);
    checks = 0;
    signOuts = 0;
    expired = false;
    signedIn = true;
    checkError = null;
  });

  test('signs the account out when the database has expired', () async {
    expired = true;
    await guard().checkNow();
    expect(checks, 1);
    expect(signOuts, 1);
  });

  test('leaves a valid database alone', () async {
    await guard().checkNow();
    expect(checks, 1);
    expect(signOuts, 0);
  });

  test('does nothing when nobody is signed in', () async {
    signedIn = false;
    expired = true;
    await guard().checkNow();
    expect(checks, 0);
    expect(signOuts, 0);
  });

  test('stays on any error: the user is let in', () async {
    checkError = Exception('offline');
    await guard().checkNow();
    expect(signOuts, 0);
  });

  test('an error from the sign-out itself is not thrown', () async {
    expired = true;
    final failing = DatabaseExpiryGuard(
      expiryCheck: () async => true,
      signOut: () async => throw Exception('prefs'),
      hasSession: () async => true,
      clock: () => now,
    );
    await failing.checkNow();
  });

  test('a second call within 30 seconds does not ask again', () async {
    final g = guard();
    await g.checkNow();
    now = now.add(const Duration(seconds: 29));
    await g.checkNow();
    expect(checks, 1);

    now = now.add(const Duration(seconds: 2));
    await g.checkNow();
    expect(checks, 2, reason: 'after 30 s it asks again');
  });

  test('a check that failed still counts as asked', () async {
    checkError = Exception('offline');
    final g = guard();
    await g.checkNow();
    await g.checkNow();
    expect(checks, 1);
  });

  test('ignoreRecentCheck asks again at once', () async {
    final g = guard();
    await g.checkNow();
    await g.checkNow(ignoreRecentCheck: true);
    expect(checks, 2);
  });

  test('a call while one is running is ignored', () async {
    final slow = <void Function()>[];
    var asked = 0;
    final g = DatabaseExpiryGuard(
      expiryCheck: () async {
        asked++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return false;
      },
      signOut: () async => signOuts++,
      hasSession: () async => true,
      clock: () => now,
    );
    final first = g.checkNow();
    await g.checkNow(ignoreRecentCheck: true);
    await first;
    expect(asked, 1);
    expect(slow, isEmpty);
  });

  test(
    'a person signed out and back in is checked again after the pause',
    () async {
      final g = guard();
      expired = true;
      await g.checkNow();
      expect(signOuts, 1);

      signedIn = false;
      now = now.add(const Duration(minutes: 5));
      await g.checkNow();
      expect(checks, 1, reason: 'nobody signed in: not asked');

      signedIn = true;
      expired = false;
      await g.checkNow();
      expect(checks, 2);
    },
  );
}
