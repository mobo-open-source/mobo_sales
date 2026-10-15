import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/widgets/create_action_gate.dart';

void main() {
  group('createBlockedReason', () {
    test('a working list with a session allows the action', () {
      expect(
        createBlockedReason(isConnected: true, hasSession: true),
        isNull,
      );
    });

    test('offline is named as offline, not as a session problem', () {
      final reason = createBlockedReason(
        isConnected: false,
        hasSession: true,
      );
      expect(reason, contains('offline'));
    });

    test('offline wins even with no session, since it is the first fix', () {
      expect(
        createBlockedReason(isConnected: false, hasSession: false),
        contains('offline'),
      );
    });

    test('no session asks the user to log in', () {
      expect(
        createBlockedReason(isConnected: true, hasSession: false),
        contains('log in again'),
      );
    });

    test('a session failure on the list blocks it too', () {
      // The RPC layer surfaces this as a plain Exception, which is why the
      // list and the button have to agree on how it is recognised.
      final reason = createBlockedReason(
        isConnected: true,
        hasSession: true,
        listError: Exception('Odoo Session Expired: Session expired'),
      );
      expect(reason, contains('log in again'));
    });

    test('an unreachable server is named as the server', () {
      final reason = createBlockedReason(
        isConnected: true,
        hasSession: true,
        listError: Exception('SocketException: Connection refused'),
      );
      expect(reason, isNotNull);
      expect(reason, contains('server'));
    });

    test('an ordinary application error does not block creating', () {
      // Odoo returns "Odoo Server Error" for validation and access failures.
      // Those say nothing about whether a new record can be started.
      expect(
        createBlockedReason(
          isConnected: true,
          hasSession: true,
          listError: Exception('Odoo Server Error: invalid domain'),
        ),
        isNull,
      );
    });
  });
}
