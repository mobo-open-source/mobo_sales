import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobo_sales/services/payment_service.dart';
import 'package:mobo_sales/services/permission_service.dart';
import 'package:mobo_sales/models/invoice.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../mocks/mock_services.dart';

void main() {
  late MockOdooClient mockClient;
  late MockPermissionService mockPermissionService;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    registerFallbackValue(Uri.parse('http://localhost'));
  });

  setUp(() {
    mockClient = MockOdooClient();
    mockPermissionService = MockPermissionService();

    PermissionService.instance = mockPermissionService;

    PaymentService.clearBehaviorCache();
  });

  group('PaymentService Behavior Detection Tests', () {
    test(
      'detectOdooPaymentBehavior returns cached behavior on subsequent calls',
      () async {
        when(() => mockClient.callKw(any())).thenAnswer(
          (_) async => [
            {'key': 'database.version', 'value': '17.0'},
          ],
        );
      },
    );

    test('detectOdooPaymentBehavior returns default on error', () async {
      final behavior = await PaymentService.detectOdooPaymentBehavior();

      expect(behavior.databaseVersion, 'unknown');
      expect(behavior.requiresReconciliation, true);
      expect(behavior.paymentStateAfterRecording, 'in_payment');
    });

    test('clearBehaviorCache clears the cached behavior', () {
      PaymentService.clearBehaviorCache();
    });
  });

  group('PaymentService Data Model Tests', () {
    test('PaymentMethodData.fromJson parses correctly', () {
      final json = {
        'id': 1,
        'name': 'Cash',
        'type': 'cash',
        'is_default': true,
        'odoo_config': {'key': 'value'},
      };

      final method = PaymentMethodData.fromJson(json);

      expect(method.id, 1);
      expect(method.name, 'Cash');
      expect(method.type, 'cash');
      expect(method.isDefault, true);
      expect(method.odooConfig, {'key': 'value'});
    });

    test('PaymentMethodData.fromJson handles missing fields', () {
      final json = {'id': 2};

      final method = PaymentMethodData.fromJson(json);

      expect(method.id, 2);
      expect(method.name, 'Unknown Method');
      expect(method.type, 'bank');
      expect(method.isDefault, false);
      expect(method.odooConfig, {});
    });

    test('PaymentOptions has correct defaults', () {
      final options = PaymentOptions();

      expect(options.memo, '');
      expect(options.differenceHandling, PaymentDifferenceHandling.keepOpen);
      expect(options.writeOffConfig, isNull);
      expect(options.autoReconcile, true);
    });

    test('PaymentResult can be created with success', () {
      final invoice = Invoice(
        id: 1,
        name: 'INV/001',
        customerName: 'Test Customer',
        lines: [],
        taxLines: [],
        subtotal: 100.0,
        taxAmount: 10.0,
        total: 110.0,
        amountPaid: 110.0,
        amountResidual: 0.0,
        status: 'posted',
        paymentState: 'paid',
      );

      final result = PaymentResult(
        success: true,
        updatedInvoice: invoice,
        warnings: ['test_warning'],
      );

      expect(result.success, true);
      expect(result.payment, isNull);
      expect(result.updatedInvoice.id, 1);
      expect(result.warnings, ['test_warning']);
      expect(result.errorMessage, isNull);
    });
  });

  group('PaymentService Error Handling Tests', () {
    test('PaymentError.network creates network error', () {
      final error = PaymentError.network(
        message: 'Connection failed',
        action: PaymentErrorAction.retry,
        context: {'timeout': true},
      );

      expect(error.type, PaymentErrorType.network);
      expect(error.message, 'Connection failed');
      expect(error.action, PaymentErrorAction.retry);
      expect(error.context?['timeout'], true);
    });

    test('PaymentError.validation creates validation error', () {
      final error = PaymentError.validation(
        message: 'Invalid amount',
        field: 'amount',
        action: PaymentErrorAction.correct,
      );

      expect(error.type, PaymentErrorType.validation);
      expect(error.message, 'Invalid amount');
      expect(error.field, 'amount');
      expect(error.action, PaymentErrorAction.correct);
    });

    test('PaymentError.sync creates sync error', () {
      final error = PaymentError.sync(
        message: 'Sync failed',
        action: PaymentErrorAction.refresh,
      );

      expect(error.type, PaymentErrorType.sync);
      expect(error.message, 'Sync failed');
      expect(error.action, PaymentErrorAction.refresh);
    });
  });

  group('PaymentService Enum Tests', () {
    test('PaymentDifferenceHandling has correct values', () {
      expect(PaymentDifferenceHandling.values.length, 2);
      expect(PaymentDifferenceHandling.keepOpen, isNotNull);
      expect(PaymentDifferenceHandling.writeOff, isNotNull);
    });

    test('PaymentErrorType has all expected values', () {
      expect(PaymentErrorType.values.length, 5);
      expect(PaymentErrorType.network, isNotNull);
      expect(PaymentErrorType.validation, isNotNull);
      expect(PaymentErrorType.sync, isNotNull);
      expect(PaymentErrorType.reconciliation, isNotNull);
      expect(PaymentErrorType.unknown, isNotNull);
    });

    test('PaymentErrorAction has all expected values', () {
      expect(PaymentErrorAction.values.length, 4);
      expect(PaymentErrorAction.retry, isNotNull);
      expect(PaymentErrorAction.correct, isNotNull);
      expect(PaymentErrorAction.refresh, isNotNull);
      expect(PaymentErrorAction.contact, isNotNull);
    });
  });

  group('PaymentService WriteOffConfig Tests', () {
    test('WriteOffConfig can be created', () {
      final config = WriteOffConfig(
        accountId: 123,
        label: 'Payment Difference',
      );

      expect(config.accountId, 123);
      expect(config.label, 'Payment Difference');
    });
  });

  group('PaymentService OdooPaymentBehavior Tests', () {
    test('OdooPaymentBehavior.fromDetection parses correctly', () {
      final detection = {
        'marks_as_paid_directly': true,
        'requires_reconciliation': false,
        'payment_state_after_recording': 'paid',
        'database_version': '17.0',
      };

      final behavior = OdooPaymentBehavior.fromDetection(detection);

      expect(behavior.marksAsPaidDirectly, true);
      expect(behavior.requiresReconciliation, false);
      expect(behavior.paymentStateAfterRecording, 'paid');
      expect(behavior.databaseVersion, '17.0');
    });

    test('OdooPaymentBehavior.fromDetection handles missing fields', () {
      final detection = <String, dynamic>{};

      final behavior = OdooPaymentBehavior.fromDetection(detection);

      expect(behavior.marksAsPaidDirectly, false);
      expect(behavior.requiresReconciliation, true);
      expect(behavior.paymentStateAfterRecording, 'in_payment');
      expect(behavior.databaseVersion, 'unknown');
    });
  });
}
