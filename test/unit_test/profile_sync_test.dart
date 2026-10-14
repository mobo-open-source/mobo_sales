import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/services/profile_version_stamp.dart';
import 'package:mobo_sales/services/session_service.dart';

void main() {
  group('jsonRpcEnvelope', () {
    test('wraps a bare call_kw payload in a JSON-RPC request', () {
      final body = OdooSessionManager.jsonRpcEnvelope({
        'model': 'res.users',
        'method': 'read',
        'args': [
          [1],
          ['name'],
        ],
        'kwargs': {},
      });
      expect(body['jsonrpc'], '2.0');
      expect(body['method'], 'call');
      expect(body['id'], isA<int>());
      final params = body['params'] as Map;
      expect(params['model'], 'res.users');
      expect(params['method'], 'read');
    });

    test('leaves a whole request as it is', () {
      final request = {
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {'model': 'res.users'},
        'id': 7,
      };
      expect(
        identical(OdooSessionManager.jsonRpcEnvelope(request), request),
        isTrue,
      );
    });
  });

  group('SessionService.applyIdentity', () {
    Map<String, dynamic> account() => {
      'name': '1',
      'userName': '1',
      'imageBase64': null,
      'database': 'barcode',
    };

    test('replaces the login-as-name with the real name under both keys', () {
      final a = account();
      final changed = SessionService.applyIdentity(
        a,
        const UserIdentity(name: 'Mitchel Admin'),
      );
      expect(changed, isTrue);
      expect(a['name'], 'Mitchel Admin');
      expect(a['userName'], 'Mitchel Admin');
      expect(a['database'], 'barcode', reason: 'nothing else is touched');
    });

    test('a new photo is stored, and a removed one clears it', () {
      final a = account();
      expect(
        SessionService.applyIdentity(
          a,
          const UserIdentity(imageBase64: 'AAAA'),
        ),
        isTrue,
      );
      expect(a['imageBase64'], 'AAAA');

      expect(SessionService.applyIdentity(a, const UserIdentity()), isTrue);
      expect(a['imageBase64'], isNull, reason: 'the user removed it');
    });

    test('a missing name keeps the stored one', () {
      final a = account()
        ..['name'] = 'Kept'
        ..['userName'] = 'Kept';
      SessionService.applyIdentity(a, const UserIdentity(imageBase64: 'AAAA'));
      expect(a['name'], 'Kept');
      expect(a['userName'], 'Kept');
    });

    test('reports no change when nothing differs', () {
      final a = {'name': 'Ann', 'userName': 'Ann', 'imageBase64': 'AAAA'};
      expect(
        SessionService.applyIdentity(
          a,
          const UserIdentity(name: 'Ann', imageBase64: 'AAAA'),
        ),
        isFalse,
      );
    });
  });

  group('profileVersionStamp', () {
    test('joins the user and partner write dates', () async {
      final asked = <String>[];
      final stamp = await profileVersionStamp(
        (p) async {
          asked.add(p['model'] as String);
          return [
            {
              'write_date': p['model'] == 'res.users'
                  ? '2026-10-01 10:00:00'
                  : '2026-10-09 09:00:00',
            },
          ];
        },
        uid: 2,
        partnerId: 3,
      );
      expect(stamp, '2026-10-01 10:00:00|2026-10-09 09:00:00');
      expect(asked, ['res.users', 'res.partner']);
    });

    test('a photo changed on the partner changes the stamp', () async {
      Future<String?> stampWith(String partnerDate) => profileVersionStamp(
        (p) async => [
          {'write_date': p['model'] == 'res.users' ? 'same' : partnerDate},
        ],
        uid: 2,
        partnerId: 3,
      );
      expect(await stampWith('t1'), isNot(await stampWith('t2')));
    });

    test('without a partner id only the user date is used', () async {
      final stamp = await profileVersionStamp(
        (p) async => [
          {'write_date': 'u'},
        ],
        uid: 2,
      );
      expect(stamp, 'u|');
    });

    test('null when the user date cannot be read', () async {
      expect(
        await profileVersionStamp((_) async => throw Exception('down'), uid: 2),
        isNull,
      );
      expect(await profileVersionStamp((_) async => [], uid: 2), isNull);
    });
  });

  group('partnerIdOf', () {
    test('reads a many2one pair or a bare id', () {
      expect(
        partnerIdOf({
          'partner_id': [5, 'Ann'],
        }),
        5,
      );
      expect(partnerIdOf({'partner_id': 6}), 6);
      expect(partnerIdOf({'partner_id': false}), isNull);
      expect(partnerIdOf(null), isNull);
    });
  });

  group('profileCacheKey', () {
    test('is one key per account and the one the settings provider uses', () {
      expect(
        profileCacheKey(database: 'my-db.v2', userId: 7),
        'user_profile_my_db_v2_7',
      );
      expect(
        profileCacheKey(database: 'a', userId: 1),
        isNot(profileCacheKey(database: 'a', userId: 2)),
        reason: 'two users of one database do not share a copy',
      );
      expect(
        profileCacheKey(database: 'a', userId: 1),
        isNot(profileCacheKey(database: 'b', userId: 1)),
        reason: 'the same user id on two databases is two people',
      );
    });
  });
}
