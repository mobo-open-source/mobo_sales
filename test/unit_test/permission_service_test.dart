import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/odoo_compat.dart';
import 'package:mobo_sales/services/permission_service.dart';

void main() {
  /// A stand-in for the Odoo server's access checks: [granted] holds
  /// `model:operation` pairs the user may perform, and the methods the server
  /// knows are [methods]. Calling a method the server lacks fails the way Odoo
  /// 20 does for the removed `check_access_rights`.
  ({OdooCallKw callKw, List<Map<String, dynamic>> calls}) fakeServer({
    required Set<String> granted,
    Set<String> methods = const {'has_access', 'check_access_rights'},
  }) {
    final calls = <Map<String, dynamic>>[];
    Future<dynamic> callKw(Map<String, dynamic> payload) async {
      calls.add(payload);
      final method = payload['method'] as String;
      final model = payload['model'] as String;
      if (!methods.contains(method)) {
        throw Exception(
          'Odoo Server Error: AttributeError: '
          "The method '$model.$method' does not exist",
        );
      }
      final args = payload['args'] as List;
      final operation = (method == 'has_access' ? args[1] : args[0]) as String;
      return granted.contains('$model:$operation');
    }

    return (callKw: callKw, calls: calls);
  }

  group('PermissionService.can on Odoo 20', () {
    test('asks has_access, which is the check Odoo 20 still has', () async {
      final server = fakeServer(
        granted: {'sale.order:create'},
        methods: {'has_access'},
      );
      final service = PermissionService.forTesting(
        callKw: server.callKw,
        generation: 20,
      );

      expect(await service.canCreate('sale.order'), isTrue);

      expect(server.calls, hasLength(1));
      expect(server.calls.single['model'], 'sale.order');
      expect(server.calls.single['method'], 'has_access');
      expect(server.calls.single['args'], [<int>[], 'create']);
    });

    test('maps each convenience method to its operation', () async {
      final server = fakeServer(
        granted: {
          'res.partner:read',
          'res.partner:write',
          'res.partner:create',
          'res.partner:unlink',
        },
        methods: {'has_access'},
      );
      final service = PermissionService.forTesting(
        callKw: server.callKw,
        generation: 20,
      );

      expect(await service.canRead('res.partner'), isTrue);
      expect(await service.canWrite('res.partner'), isTrue);
      expect(await service.canCreate('res.partner'), isTrue);
      expect(await service.canUnlink('res.partner'), isTrue);
      expect(server.calls.map((c) => (c['args'] as List)[1]), [
        'read',
        'write',
        'create',
        'unlink',
      ]);
    });

    test('answers false for an operation the user lacks', () async {
      final server = fakeServer(
        granted: {'res.partner:read'},
        methods: {'has_access'},
      );
      final service = PermissionService.forTesting(
        callKw: server.callKw,
        generation: 20,
      );

      expect(await service.canRead('res.partner'), isTrue);
      expect(await service.canUnlink('res.partner'), isFalse);
    });

    test('a server version we cannot read still works: has_access after a '
        'missing check_access_rights', () async {
      final server = fakeServer(
        granted: {'sale.order:write'},
        methods: {'has_access'},
      );
      final service = PermissionService.forTesting(
        callKw: server.callKw,
        generation: 0,
      );

      expect(await service.canWrite('sale.order'), isTrue);
      expect(server.calls.map((c) => c['method']), [
        'check_access_rights',
        'has_access',
      ]);
    });
  });

  group('PermissionService.can on Odoo 17', () {
    test('keeps asking check_access_rights without raising', () async {
      final server = fakeServer(
        granted: {'account.move:write'},
        methods: {'check_access_rights'},
      );
      final service = PermissionService.forTesting(
        callKw: server.callKw,
        generation: 17,
      );

      expect(await service.canWrite('account.move'), isTrue);

      expect(server.calls.single['method'], 'check_access_rights');
      expect(server.calls.single['args'], ['write']);
      expect((server.calls.single['kwargs'] as Map)['raise_exception'], false);
    });
  });

  group('PermissionService caching', () {
    test('remembers an answer for five minutes, a "no" included', () async {
      var now = DateTime(2026, 10, 9, 9);
      final server = fakeServer(
        granted: {'res.partner:read'},
        methods: {'has_access'},
      );
      final service = PermissionService.forTesting(
        callKw: server.callKw,
        generation: 20,
        clock: () => now,
      );

      expect(await service.canRead('res.partner'), isTrue);
      expect(await service.canUnlink('res.partner'), isFalse);
      expect(server.calls, hasLength(2));

      now = now.add(const Duration(minutes: 4, seconds: 59));
      expect(await service.canRead('res.partner'), isTrue);
      expect(await service.canUnlink('res.partner'), isFalse);
      expect(server.calls, hasLength(2), reason: 'still inside the lifetime');

      now = now.add(const Duration(seconds: 2));
      expect(await service.canRead('res.partner'), isTrue);
      expect(server.calls, hasLength(3), reason: 'expired, so asked again');
    });

    test('does not remember a failure to ask', () async {
      var failing = true;
      final calls = <Map<String, dynamic>>[];
      final service = PermissionService.forTesting(
        generation: 20,
        callKw: (payload) async {
          calls.add(payload);
          if (failing) throw Exception('SocketException: Connection refused');
          return true;
        },
      );

      expect(await service.canCreate('sale.order'), isFalse);

      failing = false;
      expect(await service.canCreate('sale.order'), isTrue);
      expect(calls, hasLength(2), reason: 'the failure was not cached');
    });

    test('a non-boolean reply is "no", as it always was', () async {
      final service = PermissionService.forTesting(
        generation: 20,
        callKw: (_) async => null,
      );

      expect(await service.canRead('res.partner'), isFalse);
    });

    test('clearCache makes the next question go to the server again', () async {
      final server = fakeServer(
        granted: {'res.partner:read'},
        methods: {'has_access'},
      );
      final service = PermissionService.forTesting(
        callKw: server.callKw,
        generation: 20,
      );

      await service.canRead('res.partner');
      await service.canRead('res.partner');
      expect(server.calls, hasLength(1));

      service.clearCache();
      await service.canRead('res.partner');
      expect(server.calls, hasLength(2));
    });
  });

  group('PermissionService.ensureCan', () {
    test('returns when allowed and throws the message when denied', () async {
      final server = fakeServer(
        granted: {'sale.order:create'},
        methods: {'has_access'},
      );
      final service = PermissionService.forTesting(
        callKw: server.callKw,
        generation: 20,
      );

      await service.ensureCan('sale.order', 'create');
      await expectLater(
        service.ensureCan('sale.order', 'unlink'),
        throwsA(
          predicate(
            (e) => e.toString().contains('permission to unlink on sale.order'),
          ),
        ),
      );
      await expectLater(
        service.ensureCan(
          'sale.order',
          'unlink',
          onDeniedMessage: 'Ask your manager.',
        ),
        throwsA(predicate((e) => e.toString().contains('Ask your manager.'))),
      );
    });
  });

  group('PermissionService.hasGroup', () {
    /// A server that answers `has_group` for whichever call shape the
    /// release uses, and records what it was sent.
    ({OdooCallKw callKw, List<Map<String, dynamic>> calls}) groupServer({
      required Set<String> memberOf,
      required int expectUserIdArgument,
    }) {
      final calls = <Map<String, dynamic>>[];
      Future<dynamic> callKw(Map<String, dynamic> payload) async {
        calls.add(payload);
        final args = payload['args'] as List;
        // Odoo 17 takes only the external id; 18+ take the user id first.
        // Sending the wrong shape is a TypeError on the server, not a "no".
        if (expectUserIdArgument == 1) {
          if (args.length != 2 || args[0] is! int) {
            throw Exception('TypeError: has_group() missing the user');
          }
          return memberOf.contains(args[1]);
        }
        if (args.length != 1 || args[0] is! String) {
          throw Exception('TypeError: has_group() takes 2 positional args');
        }
        return memberOf.contains(args[0]);
      }

      return (callKw: callKw, calls: calls);
    }

    test('Odoo 17 is asked without a user id', () async {
      final server = groupServer(
        memberOf: {'account.group_account_invoice'},
        expectUserIdArgument: 0,
      );
      final service = PermissionService.forTesting(
        callKw: server.callKw,
        generation: 17,
        userId: 7,
      );

      expect(await service.hasGroup('account.group_account_invoice'), isTrue);
      expect(server.calls.single['model'], 'res.users');
      expect(server.calls.single['method'], 'has_group');
      expect(server.calls.single['args'], ['account.group_account_invoice']);
    });

    test('Odoo 18, 19 and 20 are handed the user id first', () async {
      for (final generation in [18, 19, 20]) {
        final server = groupServer(
          memberOf: {'account.group_account_invoice'},
          expectUserIdArgument: 1,
        );
        final service = PermissionService.forTesting(
          callKw: server.callKw,
          generation: generation,
          userId: 7,
        );

        expect(
          await service.hasGroup('account.group_account_invoice'),
          isTrue,
          reason: 'generation $generation',
        );
        expect(server.calls.single['args'], [
          7,
          'account.group_account_invoice',
        ]);
      }
    });

    test('an unknown version takes the shape all but 17 use', () async {
      final server = groupServer(memberOf: {}, expectUserIdArgument: 1);
      final service = PermissionService.forTesting(
        callKw: server.callKw,
        generation: 0,
        userId: 7,
      );

      expect(await service.hasGroup('account.group_account_invoice'), isFalse);
      expect(server.calls.single['args'], [7, 'account.group_account_invoice']);
    });

    test('a user outside the group is not a member', () async {
      final server = groupServer(
        memberOf: {'sales_team.group_sale_salesman'},
        expectUserIdArgument: 1,
      );
      final service = PermissionService.forTesting(
        callKw: server.callKw,
        generation: 18,
        userId: 7,
      );

      expect(await service.hasGroup('account.group_account_invoice'), isFalse);
    });

    test('a call that fails answers false and is not remembered', () async {
      var attempts = 0;
      Future<dynamic> callKw(Map<String, dynamic> payload) async {
        attempts++;
        throw Exception('connection reset');
      }

      final service = PermissionService.forTesting(
        callKw: callKw,
        generation: 18,
        userId: 7,
      );

      expect(await service.hasGroup('account.group_account_invoice'), isFalse);
      expect(await service.hasGroup('account.group_account_invoice'), isFalse);
      expect(attempts, 2, reason: 'a failure must not be cached as a "no"');
    });

    test('an answer is remembered, so the button does not re-ask', () async {
      final server = groupServer(
        memberOf: {'account.group_account_invoice'},
        expectUserIdArgument: 1,
      );
      final service = PermissionService.forTesting(
        callKw: server.callKw,
        generation: 18,
        userId: 7,
      );

      await service.hasGroup('account.group_account_invoice');
      await service.hasGroup('account.group_account_invoice');
      expect(server.calls.length, 1);
    });
  });
}
