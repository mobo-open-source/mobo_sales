import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';

void main() {
  // odoo/http/session.py (Odoo 20):
  //   SESSION_ROTATION_INTERVAL = 60 * 60 * 3
  //   SESSION_DELETION_TIMER = 120
  //   SESSION_ROTATION_INTERVAL_HEADER_SKIP =
  //       "X-Odoo-Skip-Session-Rotation-Interval"
  // save_session() rotates a logged-in session older than three hours unless
  // that header is set; the old id is deleted two minutes later. Odoo 19 rotates
  // the same way but has no header; 17 and 18 do not rotate by age.
  group('skipping Odoo 20 session rotation', () {
    test('uses the header name Odoo 20 reads', () {
      expect(
        OdooSessionManager.skipSessionRotationHeader,
        'X-Odoo-Skip-Session-Rotation-Interval',
      );
    });

    test(
      'is asked of Odoo 20 and later, and of a server not yet identified',
      () {
        expect(OdooSessionManager.shouldSkipSessionRotation(20), isTrue);
        expect(OdooSessionManager.shouldSkipSessionRotation(21), isTrue);
        expect(OdooSessionManager.shouldSkipSessionRotation(0), isTrue);
      },
    );

    test('is not sent to servers that have no such header', () {
      for (final generation in [17, 18, 19]) {
        expect(
          OdooSessionManager.shouldSkipSessionRotation(generation),
          isFalse,
          reason: 'Odoo $generation',
        );
      }
    });
  });
}
