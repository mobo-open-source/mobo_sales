import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A session with no network behind it.
///
/// `sessionId` is empty on purpose: the identity read inside `storeAccount`
/// returns immediately without it, so these tests exercise the storage rules
/// and nothing else.
OdooSessionModel session({
  int? userId = 2,
  String serverUrl = 'https://mobo.easyinstance.com',
  String login = 'cybroplay@gmail.com',
  String password = 'secret',
}) => OdooSessionModel(
  sessionId: '',
  userLogin: login,
  password: password,
  serverUrl: serverUrl,
  database: 'Mobo_Test',
  userId: userId,
);

void main() {
  late SessionService service;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    service = SessionService.instance;
    service.seedStoredAccountsForTesting([]);
    service.setCurrentSessionForTesting(null);
  });

  group('what counts as a user id', () {
    test('0 is not a user, however it is spelled', () {
      // Odoo user ids start at 1. `0` is what `(session.userId ?? 0)` wrote
      // for a session the app had not identified yet.
      expect(SessionService.isUsableUserId(0), isFalse);
      expect(SessionService.isUsableUserId('0'), isFalse);
      expect(SessionService.isUsableUserId(null), isFalse);
      expect(SessionService.isUsableUserId(''), isFalse);
      expect(SessionService.isUsableUserId('null'), isFalse);
      expect(SessionService.isUsableUserId('  '), isFalse);
    });

    test('a real id is accepted as int or string', () {
      expect(SessionService.isUsableUserId(2), isTrue);
      expect(SessionService.isUsableUserId('2'), isTrue);
    });
  });

  group('one identity for a session and its stored row', () {
    test('a raw session URL matches the normalised stored one', () {
      // The session keeps the URL as it was typed; storage holds the
      // normalised one. Compared directly these read as two accounts.
      final stored = {
        'userId': '2',
        'serverUrl': 'https://mobo.easyinstance.com',
        'database': 'Mobo_Test',
      };

      for (final typed in [
        'https://mobo.easyinstance.com/',
        'https://MOBO.EasyInstance.com',
        'mobo.easyinstance.com',
      ]) {
        expect(
          SessionService.sessionAccountKey(session(serverUrl: typed)),
          SessionService.storedAccountKey(stored),
          reason: '"$typed" is the same account as the stored row',
        );
      }
    });

    test('a different user on the same server is a different account', () {
      expect(
        SessionService.sessionAccountKey(session(userId: 2)),
        isNot(SessionService.sessionAccountKey(session(userId: 7))),
      );
    });
  });

  group('no phantom account is ever created', () {
    test('a session with no user id is not stored at all', () async {
      await service.storeAccount(session(userId: null), 'secret');
      await service.storeAccount(session(userId: 0), 'secret');

      expect(
        service.storedAccounts,
        isEmpty,
        reason:
            'storing it under a fabricated id 0 is what produced the '
            'duplicate row in the account list',
      );
    });

    test('the same account stored twice stays one row', () async {
      await service.storeAccount(session(), 'secret');
      await service.storeAccount(
        session(serverUrl: 'https://mobo.easyinstance.com/'),
        'secret',
      );

      expect(service.storedAccounts, hasLength(1));
    });
  });

  group('an auto-store does not damage what is already saved', () {
    test('an empty password leaves the saved one alone', () async {
      await service.storeAccount(session(), 'secret');

      // This is the call every auto-store makes: `storeAccount(session, '')`.
      await service.storeAccount(session(), '');

      expect(service.storedAccounts.single['password'], 'secret');
    });

    test('a real password still replaces the old one', () async {
      await service.storeAccount(session(), 'secret');
      await service.storeAccount(session(), 'newer');

      expect(service.storedAccounts.single['password'], 'newer');
    });

    test('a name already read stays when the identity read fails', () async {
      service.seedStoredAccountsForTesting([
        {
          'userId': '2',
          'userName': 'Mobo Test',
          'serverUrl': 'https://mobo.easyinstance.com',
          'database': 'Mobo_Test',
          'password': 'secret',
        },
      ]);

      await service.storeAccount(session(), '');

      expect(
        service.storedAccounts.single['userName'],
        'Mobo Test',
        reason:
            'falling back to the login would downgrade the account list '
            'to an email address',
      );
    });
  });

  group('devices already carrying a phantom row are repaired', () {
    test('cleanup removes the id-0 row and keeps the real one', () async {
      // Exactly what this emulator held: one login, stored twice.
      service.seedStoredAccountsForTesting([
        {
          'userId': '0',
          'userName': 'Mobo Test',
          'serverUrl': 'https://mobo.easyinstance.com',
          'database': 'Mobo_Test',
          'password': '',
        },
        {
          'userId': '2',
          'userName': 'Mobo Test',
          'serverUrl': 'https://mobo.easyinstance.com',
          'database': 'Mobo_Test',
          'password': 'secret',
        },
      ]);

      await service.cleanupCorruptedAccounts();

      expect(service.storedAccounts, hasLength(1));
      expect(service.storedAccounts.single['userId'], '2');
    });

    test('a healthy pair of accounts is left alone', () async {
      service.seedStoredAccountsForTesting([
        {
          'userId': '2',
          'serverUrl': 'https://mobo.easyinstance.com',
          'database': 'Mobo_Test',
        },
        {
          'userId': '7',
          'serverUrl': 'https://mobo.easyinstance.com',
          'database': 'Mobo_Test',
        },
      ]);

      await service.cleanupCorruptedAccounts();

      expect(service.storedAccounts, hasLength(2));
    });
  });

  group('which row the account list calls current', () {
    test('the stored row is current for a differently spelled URL', () {
      service.setCurrentSessionForTesting(
        session(serverUrl: 'https://mobo.easyinstance.com/'),
      );

      expect(
        service.isCurrentAccount({
          'userId': '2',
          'serverUrl': 'https://mobo.easyinstance.com',
          'database': 'Mobo_Test',
        }),
        isTrue,
      );
    });

    test('another user on the same server is not current', () {
      service.setCurrentSessionForTesting(session(userId: 2));

      expect(
        service.isCurrentAccount({
          'userId': '7',
          'serverUrl': 'https://mobo.easyinstance.com',
          'database': 'Mobo_Test',
        }),
        isFalse,
      );
    });
  });
}
