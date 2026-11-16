import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The screens where a person asks to be signed out, by name.
///
/// `logout()` clears every saved account on the device, so it belongs to the
/// Logout button and to nothing else.
const userInitiatedLogoutFiles = {
  'lib/screens/others/settings_screen.dart',
  'lib/screens/others/profile_screen.dart',
};

OdooSessionModel session() => OdooSessionModel(
  sessionId: '',
  userLogin: 'cybroplay@gmail.com',
  password: 'secret',
  serverUrl: 'https://mobo.easyinstance.com',
  database: 'Mobo_Test',
  userId: 2,
);

List<Map<String, dynamic>> twoAccounts() => [
  {
    'userId': '2',
    'userName': 'Mobo Test',
    'serverUrl': 'https://mobo.easyinstance.com',
    'database': 'Mobo_Test',
    'password': 'secret',
  },
  {
    'userId': '7',
    'userName': 'Someone Else',
    'serverUrl': 'https://mobo.easyinstance.com',
    'database': 'Mobo_Test',
    'password': 'other',
  },
];

void main() {
  late SessionService service;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    service = SessionService.instance;
    service.seedStoredAccountsForTesting(twoAccounts());
    service.setCurrentSessionForTesting(session());
  });

  group('a sign-out nobody asked for', () {
    test('ends the session and keeps every saved account', () async {
      await service.endSessionKeepingAccounts();

      expect(service.currentSession, isNull);
      expect(
        service.storedAccounts,
        hasLength(2),
        reason:
            'one account with a stale password must not take the other '
            'accounts on the device with it',
      );
    });

    test('leaves the saved passwords alone', () async {
      await service.endSessionKeepingAccounts();

      expect(
        service.storedAccounts.map((a) => a['password']),
        ['secret', 'other'],
        reason: 'without these the account switcher cannot get back in',
      );
    });
  });

  group('a sign-out the user asked for', () {
    test('clears the saved accounts, as the Logout button means to', () async {
      await service.logout(showNotice: false);

      expect(service.currentSession, isNull);
      expect(service.storedAccounts, isEmpty);
    });
  });

  group('the rule, enforced on the source', () {
    test('only the Logout button calls logout()', () {
      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (userInitiatedLogoutFiles.contains(entity.path)) continue;

        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // `OdooSessionManager.logout()` only ends the server session; it is
          // the SessionService one that deletes the saved accounts.
          if (line.contains('OdooSessionManager.logout(')) continue;
          if (line.contains('Future<void> logout(')) continue;
          if (line.trimLeft().startsWith('//')) continue;
          if (line.contains('logout()')) {
            offenders.add('${entity.path}:${i + 1}: ${line.trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'an automatic sign-out goes through '
            'endSessionKeepingAccounts(); logout() wipes the device',
      );
    });
  });
}
