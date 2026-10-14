import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/database_expiry.dart';

/// The Odoo web client's rule is `Math.round(daysLeft) <= 0`, daysLeft being the
/// seconds until the date over 86400: expired once less than half a day is left.
void main() {
  // A fixed "now": 2026-10-12 12:00:00 UTC.
  final now = DateTime.utc(2026, 10, 12, 12);

  bool expired(Object? value) => DatabaseExpiry.hasExpired(value, now: now);

  group('hasExpired', () {
    test('a date in the past is expired', () {
      expect(expired('2026-10-01 00:00:00'), isTrue);
      expect(expired('2020-01-01'), isTrue);
    });

    test('a date in the future is not', () {
      expect(expired('2026-11-12 00:00:00'), isFalse);
      expect(expired('2027-01-01'), isFalse);
    });

    test('a date alone counts as midnight UTC', () {
      // Midnight starting 2026-10-13 is 12 hours away: exactly the edge.
      expect(expired('2026-10-13'), isFalse);
      expect(
        expired('2026-10-12'),
        isTrue,
        reason: 'midnight was 12 hours ago',
      );
    });

    test('exactly now is expired', () {
      expect(expired('2026-10-12 12:00:00'), isTrue);
    });

    test('less than twelve hours left is expired, exactly twelve is not', () {
      // 11 h 59 m left.
      expect(expired('2026-10-13 00:00:00'), isFalse, reason: '12 h left');
      expect(expired('2026-10-12 23:59:00'), isTrue, reason: '11 h 59 m left');
      expect(expired('2026-10-13 00:00:01'), isFalse);
    });

    test('twelve hours past is expired, as is anything after', () {
      expect(expired('2026-10-12 00:00:00'), isTrue);
      expect(expired('2026-10-11 23:59:59'), isTrue);
    });

    test('the ISO "T" form and a fractional-second tail read the same', () {
      expect(expired('2026-10-01T00:00:00'), isTrue);
      expect(expired('2026-11-12T00:00:00'), isFalse);
      expect(expired('2026-10-01 00:00:00.123456'), isTrue);
      expect(expired('2026-11-12 00:00:00.5'), isFalse);
      expect(expired('2026-10-01T00:00:00Z'), isTrue);
    });

    test('the date is UTC, whatever zone the phone is in', () {
      // The same moment is expired or not regardless of the local clock: only
      // [now] and the string decide.
      expect(
        DatabaseExpiry.hasExpired(
          '2026-10-12 12:00:00',
          now: DateTime.parse('2026-10-12T17:30:00+05:30'),
        ),
        isTrue,
      );
    });

    test('nothing readable is never expired', () {
      for (final value in [
        null,
        false,
        true,
        '',
        'never',
        42,
        0,
        '2026-13-45',
      ]) {
        expect(expired(value), isFalse, reason: '$value');
      }
    });
  });

  group('check', () {
    Future<dynamic> info(Object? value, {bool withKey = true}) async => {
      'uid': 7,
      if (withKey) 'expiration_date': value,
    };

    test('is true when the session info says the date has passed', () async {
      expect(
        await DatabaseExpiry.check(
          readSessionInfo: () => info('2020-01-01'),
          readParameter: () => throw StateError('not asked'),
          now: now,
        ),
        isTrue,
      );
    });

    test('is false when the date is ahead', () async {
      expect(
        await DatabaseExpiry.check(
          readSessionInfo: () => info('2027-01-01 00:00:00'),
          readParameter: () => throw StateError('not asked'),
          now: now,
        ),
        isFalse,
      );
    });

    test('is false on Community, and the parameter is not read', () async {
      var parameterReads = 0;
      expect(
        await DatabaseExpiry.check(
          readSessionInfo: () => info(null, withKey: false),
          readParameter: () async {
            parameterReads++;
            return '2020-01-01';
          },
          now: now,
        ),
        isFalse,
      );
      expect(parameterReads, 0);
    });

    test('is false when the key is there with Odoo\'s "no value"', () async {
      var parameterReads = 0;
      expect(
        await DatabaseExpiry.check(
          readSessionInfo: () => info(false),
          readParameter: () async {
            parameterReads++;
            return '2020-01-01';
          },
          now: now,
        ),
        isFalse,
      );
      expect(parameterReads, 0);
    });

    test(
      'falls back to the parameter only when the session info failed',
      () async {
        expect(
          await DatabaseExpiry.check(
            readSessionInfo: () => throw Exception('boom'),
            readParameter: () async => '2020-01-01',
            now: now,
          ),
          isTrue,
        );
        expect(
          await DatabaseExpiry.check(
            readSessionInfo: () => throw Exception('boom'),
            readParameter: () async => '2027-01-01',
            now: now,
          ),
          isFalse,
        );
      },
    );

    test('an unexpected answer is not expired', () async {
      expect(
        await DatabaseExpiry.check(
          readSessionInfo: () async => 'not a map',
          readParameter: () => throw StateError('not asked'),
          now: now,
        ),
        isFalse,
      );
    });

    test('everything failing is not expired', () async {
      expect(
        await DatabaseExpiry.check(
          readSessionInfo: () => throw Exception('offline'),
          readParameter: () => throw Exception('offline'),
          now: now,
        ),
        isFalse,
      );
    });
  });

  test('the exception is the message', () {
    expect(
      const DatabaseExpiredException().toString(),
      'This database has expired. Please contact your administrator or Odoo to '
      'renew the subscription.',
    );
    expect(
      DatabaseExpiredException.message,
      const DatabaseExpiredException().toString(),
    );
  });
}
