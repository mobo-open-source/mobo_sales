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
}
