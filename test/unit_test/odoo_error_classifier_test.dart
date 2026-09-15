import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/odoo_error_classifier.dart';

void main() {
  group('OdooErrorClassifier', () {
    test('detects genuine transport failures', () {
      const unreachable = [
        'SocketException: Connection refused (OS Error: Connection refused)',
        'ClientException with SocketException: Failed host lookup',
        'Exception: Server returned HTML instead of JSON',
        'HttpException: 502 Bad Gateway',
        'Request failed, statusCode: 503',
        'Exception: database not found',
        'Connection timeout after 30s',
      ];
      for (final error in unreachable) {
        expect(
          OdooErrorClassifier.isServerUnreachable(error),
          true,
          reason: error,
        );
      }
    });

    test('does not report application errors as an unreachable server', () {
      const reachable = [
        'Odoo Server Error: AccessError - You do not have enough rights to '
            'access the fields "credit,credit_limit" on Contact (res.partner).',
        'Odoo Server Error: ValueError - Invalid field '
            'res.partner.customer_rank in leaf',
        'Odoo Server Error: UserError - Quotation 2504 cannot be confirmed',
      ];
      for (final error in reachable) {
        expect(
          OdooErrorClassifier.isServerUnreachable(error),
          false,
          reason: error,
        );
      }
    });

    test('a status code inside an amount or id is not a transport failure', () {
      expect(
        OdooErrorClassifier.isServerUnreachable(
          'ValidationError - Total must not exceed 1500.00',
        ),
        false,
      );
      expect(
        OdooErrorClassifier.isServerUnreachable(
          'Record does not exist or has been deleted (id 504123)',
        ),
        false,
      );
    });

    test('an empty or null error is not a transport failure', () {
      expect(OdooErrorClassifier.isServerUnreachable(null), false);
      expect(OdooErrorClassifier.isServerUnreachable(''), false);
    });
  });
}
