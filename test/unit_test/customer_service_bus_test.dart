import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobo_sales/services/customer_service.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/services/permission_service.dart';

import '../mocks/mock_services.dart';

/// Every customer write that reaches the server is announced on the data bus,
/// by the service, so the screens that made it and the screens that did not
/// (the list, a customer's page, the dashboard) all hear of it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DataChangeBus bus;
  late List<DataChange> heard;
  late DataChangeSubscription subscription;
  late List<Map<String, dynamic>> calls;
  late PermissionService savedPermissions;
  late MockPermissionService permissions;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    savedPermissions = PermissionService.instance;
    permissions = MockPermissionService();
    when(
      () => permissions.canCreate('res.partner'),
    ).thenAnswer((_) async => true);
    when(
      () => permissions.canWrite('res.partner'),
    ).thenAnswer((_) async => true);
    PermissionService.instance = permissions;

    bus = DataChangeBus.forTesting();
    heard = [];
    calls = [];
    subscription = bus.listen(
      debounce: Duration.zero,
      onChange: (burst) => heard.addAll(burst),
    );
  });

  tearDown(() {
    subscription.cancel();
    PermissionService.instance = savedPermissions;
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  /// A server that answers `fields_get` with a schema that accepts the values
  /// the tests send, and everything else with [answer].
  CustomerService serviceAnswering(
    dynamic Function(Map<String, dynamic> payload) answer,
  ) {
    return CustomerService.forTesting(
      bus: bus,
      callKw: (payload) async {
        calls.add(payload);
        if (payload['method'] == 'fields_get') {
          return {
            'name': {'type': 'char', 'readonly': false},
            'phone': {'type': 'char', 'readonly': false},
            'active': {'type': 'boolean', 'readonly': false},
            'id': {'type': 'integer', 'readonly': true},
          };
        }
        return answer(payload);
      },
    );
  }

  test('creating a customer announces it, with the new id', () async {
    final service = serviceAnswering((payload) {
      if (payload['method'] == 'create') return 42;
      if (payload['method'] == 'read') {
        return [
          {'id': 42, 'name': 'Ada'},
        ];
      }
    });

    final created = await service.createCustomer({'name': 'Ada'});
    await settle();

    expect(created?.id, 42);
    expect(heard, hasLength(1));
    expect(heard.single.entity, DataEntity.customer);
    expect(heard.single.kind, DataChangeKind.created);
    expect(heard.single.id, 42);
  });

  test('the customer is announced even when reading it back fails', () async {
    final service = serviceAnswering((payload) {
      if (payload['method'] == 'create') return 7;
      throw Exception('AccessError: not allowed to read property_payment_term');
    });

    await expectLater(service.createCustomer({'name': 'Ada'}), throwsException);
    await settle();

    expect(heard.map((c) => c.kind), [DataChangeKind.created]);
    expect(heard.single.id, 7);
  });

  test('a create the server rejects announces nothing', () async {
    final service = serviceAnswering((payload) {
      throw Exception('ValidationError');
    });

    await expectLater(service.createCustomer({'name': 'Ada'}), throwsException);
    await settle();

    expect(heard, isEmpty);
  });

  test('updating a customer announces it once the server says true', () async {
    final service = serviceAnswering((payload) => true);

    final ok = await service.updateCustomer(9, {'phone': '123'});
    await settle();

    expect(ok, isTrue);
    expect(heard, hasLength(1));
    expect(heard.single.entity, DataEntity.customer);
    expect(heard.single.kind, DataChangeKind.updated);
    expect(heard.single.id, 9);
  });

  test('an update the server answers false to announces nothing', () async {
    final service = serviceAnswering((payload) => false);

    final ok = await service.updateCustomer(9, {'phone': '123'});
    await settle();

    expect(ok, isFalse);
    expect(heard, isEmpty);
  });

  test('an update that throws announces nothing', () async {
    final service = serviceAnswering((payload) {
      throw Exception('UserError');
    });

    await expectLater(
      service.updateCustomer(9, {'phone': '1'}),
      throwsException,
    );
    await settle();

    expect(heard, isEmpty);
  });

  test('an update the user may not make never reaches the server', () async {
    when(
      () => permissions.canWrite('res.partner'),
    ).thenAnswer((_) async => false);
    final service = serviceAnswering((payload) => true);

    await expectLater(
      service.updateCustomer(9, {'phone': '1'}),
      throwsException,
    );
    await settle();

    expect(calls, isEmpty);
    expect(heard, isEmpty);
  });

  test('archiving a customer announces it as gone from the lists', () async {
    final service = serviceAnswering((payload) => true);

    final ok = await service.deleteCustomer(5);
    await settle();

    expect(ok, isTrue);
    expect(calls.last['args'], [
      [5],
      {'active': false},
    ]);
    expect(heard, hasLength(1));
    expect(heard.single.kind, DataChangeKind.deleted);
    expect(heard.single.id, 5);
  });

  test('with no session nothing is sent or announced', () async {
    final service = CustomerService.forTesting(
      bus: bus,
      hasSession: () async => false,
      callKw: (payload) async {
        calls.add(payload);
        return true;
      },
    );

    await expectLater(
      service.updateCustomer(9, {'phone': '1'}),
      throwsException,
    );
    await settle();

    expect(calls, isEmpty);
    expect(heard, isEmpty);
  });
}
