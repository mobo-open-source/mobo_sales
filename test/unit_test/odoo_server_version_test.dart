import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/utils/odoo_version.dart';

void main() {
  // odoo_rpc turns `server_version_info[0]` into OdooSession.serverVersion
  // (odoo_rpc-0.7.1/lib/src/odoo_session.dart: `versionInfo[0].toString()`).
  // The Odoo 20 development tree has server_version '19.5a1' and
  // server_version_info [19, 5, 0, 'alpha', 1, ''] (odoo/release.py), so what
  // odoo_rpc hands over for it is just '19'.
  group('serverVersionNeedsRefinement', () {
    test(
      'is true for a bare 19, which could be Odoo 19 or a 20 pre-release',
      () {
        expect(OdooSessionManager.serverVersionNeedsRefinement('19'), isTrue);
        expect(
          OdooSessionManager.serverVersionNeedsRefinement('saas~19'),
          isTrue,
        );
      },
    );

    test('is false once a minor part is present', () {
      expect(
        OdooSessionManager.serverVersionNeedsRefinement('19.5a1'),
        isFalse,
      );
      expect(OdooSessionManager.serverVersionNeedsRefinement('19.0'), isFalse);
      expect(
        OdooSessionManager.serverVersionNeedsRefinement('saas~19.2'),
        isFalse,
      );
    });

    test('leaves 17, 18, 20 and unreadable versions alone', () {
      for (final v in ['17', '18', '20', 'saas~18', '17.0', '', 'unknown']) {
        expect(
          OdooSessionManager.serverVersionNeedsRefinement(v),
          isFalse,
          reason: v,
        );
      }
    });

    test('a bare 19 reads as generation 19, the refined string as 20', () {
      expect(odooGeneration('19'), 19);
      expect(odooGeneration('19.5a1'), 20);
    });
  });

  group('parseVersionInfoReply', () {
    test('reads the Odoo 20 development tree reply', () {
      final reply = {
        'jsonrpc': '2.0',
        'id': 1,
        'result': {
          'server_version': '19.5a1',
          'server_version_info': [19, 5, 0, 'alpha', 1, ''],
          'server_serie': '19.5',
        },
      };

      final version = OdooSessionManager.parseVersionInfoReply(reply);

      expect(version, '19.5a1');
      expect(odooGeneration(version), 20);
    });

    test(
      'reads the Odoo 17 to 19 reply, which also carries protocol_version',
      () {
        final reply = {
          'jsonrpc': '2.0',
          'id': 1,
          'result': {
            'server_version': '19.0',
            'server_version_info': [19, 0, 0, 'final', 0, ''],
            'server_serie': '19.0',
            'protocol_version': 1,
          },
        };

        final version = OdooSessionManager.parseVersionInfoReply(reply);

        expect(version, '19.0');
        expect(odooGeneration(version), 19);
      },
    );

    test(
      'falls back to the release series when the version string is absent',
      () {
        final reply = {
          'result': {'server_serie': '19.5'},
        };

        expect(OdooSessionManager.parseVersionInfoReply(reply), '19.5');
        expect(odooGeneration('19.5'), 20);
      },
    );

    test('returns null for an error, an empty reply or something else', () {
      expect(
        OdooSessionManager.parseVersionInfoReply({
          'error': {'code': 100, 'message': 'Odoo Session Expired'},
        }),
        isNull,
      );
      expect(
        OdooSessionManager.parseVersionInfoReply({
          'result': {'server_version': '  '},
        }),
        isNull,
      );
      expect(
        OdooSessionManager.parseVersionInfoReply({'result': null}),
        isNull,
      );
      expect(OdooSessionManager.parseVersionInfoReply('<html></html>'), isNull);
      expect(OdooSessionManager.parseVersionInfoReply(null), isNull);
    });
  });
}
