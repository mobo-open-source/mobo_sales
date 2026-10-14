import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/sales_access.dart';

/// A server that answers the two questions [SalesAccess.check] asks.
class _FakeServer {
  _FakeServer({
    this.moduleInstalled = true,
    this.inGroup = true,
    this.internal = true,
    this.acceptsRecordShape = true,
    this.acceptsModelShape = true,
    this.probeThrows = false,
    this.groupThrows = false,
    this.groupAnswer,
  });

  final bool moduleInstalled;
  final bool inGroup;

  /// Whether the user is an internal one (in `base.group_user`).
  final bool internal;

  /// Odoo 18+ takes `has_group([uid], group)`; 17 takes `has_group(group)`.
  final bool acceptsRecordShape;
  final bool acceptsModelShape;
  final bool probeThrows;
  final bool groupThrows;

  /// Replaces the yes or no with something else (a malformed answer).
  final dynamic groupAnswer;

  final calls = <String>[];
  final groupArgs = <List<dynamic>>[];

  Future<Map<String, dynamic>> rpc(
    String model,
    String method,
    List<dynamic> args,
  ) async {
    calls.add('$model.$method');
    if (model == 'ir.model.data') {
      if (probeThrows) throw Exception('no network');
      if (!moduleInstalled) {
        return {
          'error': {
            'message': 'Odoo Server Error',
            'data': {
              'name': 'builtins.ValueError',
              'message':
                  'External ID not found in the system: ${args[0]}.${args[1]}',
            },
          },
        };
      }
      return {
        'result': ['ir.ui.menu', 42],
      };
    }

    final asked = args.last as String;
    if (asked == SalesAccess.groupXmlId) groupArgs.add(args);
    if (groupThrows) throw Exception('no network');
    final recordShape = args.length == 2;
    if (recordShape ? !acceptsRecordShape : !acceptsModelShape) {
      return {
        'error': {
          'message': 'Odoo Server Error',
          'data': {'name': 'builtins.TypeError', 'message': 'bad arguments'},
        },
      };
    }
    if (asked == SalesAccess.internalGroupXmlId) return {'result': internal};
    return {'result': groupAnswer ?? inGroup};
  }
}

void main() {
  Future<SalesAccessStatus> check(_FakeServer server, {int major = 18}) =>
      SalesAccess.check(majorVersion: major, userId: 7, rpc: server.rpc);

  group('what the two questions add up to', () {
    test('module installed and user in the group: granted', () async {
      expect(await check(_FakeServer()), SalesAccessStatus.granted);
    });

    test('user not in the group (Sales: No): denied', () async {
      expect(
        await check(_FakeServer(inGroup: false)),
        SalesAccessStatus.denied,
      );
    });

    test('no Sales module: moduleMissing, whatever the group says', () async {
      expect(
        await check(_FakeServer(moduleInstalled: false)),
        SalesAccessStatus.moduleMissing,
      );
      expect(
        await check(_FakeServer(moduleInstalled: false, inGroup: false)),
        SalesAccessStatus.moduleMissing,
      );
      // On 18+ has_group fails outright for a group nobody created.
      expect(
        await check(
          _FakeServer(
            moduleInstalled: false,
            acceptsRecordShape: false,
            acceptsModelShape: false,
          ),
        ),
        SalesAccessStatus.moduleMissing,
      );
    });

    test(
      'a server that cannot be reached is unverified, never granted',
      () async {
        expect(
          await check(_FakeServer(probeThrows: true, groupThrows: true)),
          SalesAccessStatus.unverified,
        );
      },
    );

    test('has_group failing in both shapes is unverified', () async {
      expect(
        await check(
          _FakeServer(acceptsRecordShape: false, acceptsModelShape: false),
        ),
        SalesAccessStatus.unverified,
      );
    });

    test('an answer that is not a yes or no is unverified', () async {
      expect(
        await check(_FakeServer(groupAnswer: 'maybe')),
        SalesAccessStatus.unverified,
      );
      expect(
        await check(_FakeServer(groupAnswer: null, inGroup: true)),
        SalesAccessStatus.granted,
      );
    });

    test(
      'a probe that fails for another reason does not mean "missing"',
      () async {
        // The group answer decides when the probe cannot tell.
        expect(
          await check(_FakeServer(probeThrows: true)),
          SalesAccessStatus.granted,
        );
        expect(
          await check(_FakeServer(probeThrows: true, inGroup: false)),
          SalesAccessStatus.denied,
        );
      },
    );
  });

  group('portal users', () {
    test('a portal user is told so, not just "no access"', () async {
      expect(
        await check(_FakeServer(internal: false, inGroup: false)),
        SalesAccessStatus.portalUser,
      );
    });

    test(
      'a portal user is never granted, whatever the Sales group says',
      () async {
        expect(
          await check(_FakeServer(internal: false, inGroup: true)),
          SalesAccessStatus.portalUser,
        );
      },
    );

    test('no Sales module still comes first for a portal user', () async {
      expect(
        await check(_FakeServer(internal: false, moduleInstalled: false)),
        SalesAccessStatus.moduleMissing,
      );
    });

    test('an internal user without Sales is "denied", not "portal"', () async {
      expect(
        await check(_FakeServer(internal: true, inGroup: false)),
        SalesAccessStatus.denied,
      );
    });

    test('asks for the internal group by the one id all versions share', () {
      expect(SalesAccess.internalGroupXmlId, 'base.group_user');
    });
  });

  group('the has_group signature of each Odoo', () {
    test('18 and later: on the record first', () async {
      final server = _FakeServer();
      await check(server, major: 18);
      expect(server.groupArgs.first, [
        [7],
        SalesAccess.groupXmlId,
      ]);
      final v20 = _FakeServer();
      await check(v20, major: 20);
      expect(v20.groupArgs.first, [
        [7],
        SalesAccess.groupXmlId,
      ]);
    });

    test('17: the group alone first', () async {
      final server = _FakeServer(acceptsRecordShape: false);
      expect(await check(server, major: 17), SalesAccessStatus.granted);
      expect(
        server.groupArgs,
        [
          [SalesAccess.groupXmlId],
        ],
        reason: 'the first shape is the right one, so no second call',
      );
    });

    test('falls back to the other shape when the first is refused', () async {
      final on17 = _FakeServer(acceptsModelShape: false);
      expect(await check(on17, major: 17), SalesAccessStatus.granted);
      expect(on17.groupArgs.length, 2);

      final on18 = _FakeServer(acceptsRecordShape: false);
      expect(await check(on18, major: 18), SalesAccessStatus.granted);
      expect(on18.groupArgs.length, 2);
    });

    test('an unknown version (0) still gets an answer', () async {
      expect(
        await check(_FakeServer(inGroup: false), major: 0),
        SalesAccessStatus.denied,
      );
    });

    test('asks for the Sales group and the sale module, nothing else', () {
      expect(SalesAccess.groupXmlId, 'sales_team.group_sale_salesman');
      expect(SalesAccess.moduleProbe, ['sale', 'sale_menu_root']);
    });
  });

  group('recognising "module not installed"', () {
    test('by the server error text, wherever it is carried', () {
      expect(
        SalesAccess.isMissingExternalId({
          'error': {
            'message': 'Odoo Server Error',
            'data': {'message': 'External ID not found in the system: sale.x'},
          },
        }),
        isTrue,
      );
      expect(
        SalesAccess.isMissingExternalId({
          'error': {'message': 'external id not found in the system: sale.x'},
        }),
        isTrue,
      );
    });

    test('and by nothing else', () {
      expect(SalesAccess.isMissingExternalId({'result': <dynamic>[]}), isFalse);
      expect(
        SalesAccess.isMissingExternalId({
          'error': {
            'message': 'Odoo Session Expired',
            'data': {'message': 'Session expired'},
          },
        }),
        isFalse,
      );
      expect(SalesAccess.isMissingExternalId({}), isFalse);
    });
  });

  group('SalesAccessException', () {
    test('is made for every status but granted', () {
      expect(SalesAccessException.from(SalesAccessStatus.granted), isNull);
      for (final status in [
        SalesAccessStatus.denied,
        SalesAccessStatus.portalUser,
        SalesAccessStatus.moduleMissing,
        SalesAccessStatus.unverified,
      ]) {
        expect(SalesAccessException.from(status)?.status, status);
      }
    });

    test('never reads as a wrong password to the account-switch code', () {
      for (final e in [
        const SalesAccessException.denied(),
        const SalesAccessException.portalUser(),
        const SalesAccessException.moduleMissing(),
        const SalesAccessException.unverified(),
      ]) {
        final text = e.toString().toLowerCase();
        expect(text, isNot(contains('access denied')));
        expect(text, isNot(contains('password')));
        expect(text, isNot(contains('credentials')));
        expect(text, isNot(contains('authentication')));
      }
    });
  });
}
