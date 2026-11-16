import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/data_change_bus.dart';
import 'package:mobo_sales/services/invoice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A context that is not mounted, so the service skips the confetti dialog and
/// the test can assert on the Odoo calls alone.
class _UnmountedContext extends Fake implements BuildContext {
  @override
  bool get mounted => false;
}

/// Records every `call_kw` payload and answers each model+method from [replies].
class _FakeOdoo {
  _FakeOdoo(this.replies);

  final Map<String, Object?> replies;
  final List<Map<String, dynamic>> calls = [];

  Future<dynamic> call(Map<String, dynamic> payload) async {
    calls.add(payload);
    return replies['${payload['model']}.${payload['method']}'];
  }

  Map<String, dynamic>? callTo(String model, String method) {
    for (final c in calls) {
      if (c['model'] == model && c['method'] == method) return c;
    }
    return null;
  }

  bool has(String model, String method) => callTo(model, method) != null;
}

/// The action `action_invoice_sent` returns on 18, 19 and 20 once the company
/// has a report layout.
Map<String, dynamic> _sendWizardAction() => {
  'type': 'ir.actions.act_window',
  'res_model': 'account.move.send.wizard',
  'context': {'active_id': 42},
};

/// What 18/19/20 return instead when the company has no report layout — the
/// real send action is parked under the configurator's context.
Map<String, dynamic> _layoutAction(Map<String, dynamic> inner) => {
  'type': 'ir.actions.act_window',
  'res_model': 'base.document.layout',
  'context': {'report_action': inner},
};

void main() {
  late DataChangeBus bus;

  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bus = DataChangeBus.forTesting();
  });

  /// Builds the service over [odoo] and returns how often the caller's loading
  /// dialog was closed.
  Future<int> send(_FakeOdoo odoo, {int moveId = 42}) async {
    var closed = 0;
    final service = InvoiceService.forTesting(callKw: odoo.call, bus: bus);
    try {
      await service.sendInvoice(
        _UnmountedContext(),
        moveId,
        closeLoadingDialog: () => closed++,
      );
    } catch (_) {
      // The caller surfaces the error; this test only cares that the dialog
      // was closed and which calls were made.
    }
    return closed;
  }

  group('Odoo 18, 19 and 20', () {
    test('drives account.move.send.wizard with move_id', () async {
      final odoo = _FakeOdoo({
        'account.move.action_invoice_sent': _sendWizardAction(),
        'account.move.send.wizard.create': 7,
        'account.move.send.wizard.action_send_and_print': true,
        'account.move.read': [
          {'is_move_sent': true, 'name': 'INV/2026/00010'},
        ],
      });

      await send(odoo);

      final create = odoo.callTo('account.move.send.wizard', 'create');
      expect(create, isNotNull);
      expect((create!['args'] as List).first, {'move_id': 42});
      expect(odoo.has('account.move.send.wizard', 'action_send_and_print'), isTrue);
    });

    test(
      'still sends when the company has no report layout configured',
      () async {
        // The regression this guards: `action_invoice_sent` answers with the
        // document-layout configurator, which the flow used to mistake for an
        // unsupported Odoo version.
        final odoo = _FakeOdoo({
          'account.move.action_invoice_sent': _layoutAction(
            _sendWizardAction(),
          ),
          'account.move.send.wizard.create': 7,
          'account.move.send.wizard.action_send_and_print': true,
          'account.move.read': [
            {'is_move_sent': true, 'name': 'INV/2026/00010'},
          ],
        });

        await send(odoo);

        expect(
          odoo.has('account.move.send.wizard', 'action_send_and_print'),
          isTrue,
          reason: 'the layout step must be stepped past, not treated as a '
              'version that cannot send',
        );
      },
    );

    test('carries the unwrapped action context into the wizard', () async {
      final odoo = _FakeOdoo({
        'account.move.action_invoice_sent': _layoutAction({
          'res_model': 'account.move.send.wizard',
          'context': {'default_from_invoice': true},
        }),
        'account.move.send.wizard.create': 7,
        'account.move.send.wizard.action_send_and_print': true,
        'account.move.read': [
          {'is_move_sent': true, 'name': 'INV/2026/00010'},
        ],
      });

      await send(odoo);

      final create = odoo.callTo('account.move.send.wizard', 'create')!;
      final context = (create['kwargs'] as Map)['context'] as Map;
      expect(context['default_from_invoice'], isTrue);
      expect(context['active_model'], 'account.move');
    });
  });

  group('Odoo 17', () {
    test('drives account.move.send with move_ids and the mail flag', () async {
      // 17 has no `account.move.send.wizard`; it links invoices through the
      // many2many `move_ids` and only emails when `checkbox_send_mail` is set.
      final odoo = _FakeOdoo({
        'account.move.action_invoice_sent': {
          'res_model': 'account.move.send',
          'context': {},
        },
        'account.move.send.create': 5,
        'account.move.send.action_send_and_print': true,
        'account.move.read': [
          {'is_move_sent': true, 'name': 'INV/2026/00010'},
        ],
      });

      await send(odoo);

      final create = odoo.callTo('account.move.send', 'create');
      expect(create, isNotNull, reason: 'Odoo 17 must not be refused outright');
      expect((create!['args'] as List).first, {
        'move_ids': [
          [6, 0, [42]],
        ],
        'checkbox_send_mail': true,
      });
      expect(odoo.has('account.move.send', 'action_send_and_print'), isTrue);
    });
  });

  group('failure paths', () {
    test('refuses a wizard it cannot drive, without blaming the version', () async {
      final odoo = _FakeOdoo({
        'account.move.action_invoice_sent': {'res_model': 'some.future.wizard'},
      });

      Object? raised;
      final service = InvoiceService.forTesting(callKw: odoo.call, bus: bus);
      try {
        await service.sendInvoice(
          _UnmountedContext(),
          42,
          closeLoadingDialog: () {},
        );
      } catch (e) {
        raised = e;
      }

      expect(raised, isNotNull);
      expect(
        raised.toString(),
        isNot(contains('Odoo version')),
        reason: 'an unrecognised wizard is not evidence about the version',
      );
      expect(odoo.has('some.future.wizard', 'create'), isFalse);
    });

    test('refuses a layout step that carries no send action', () async {
      final odoo = _FakeOdoo({
        'account.move.action_invoice_sent': {
          'res_model': 'base.document.layout',
          'context': <String, dynamic>{},
        },
      });

      expect(await send(odoo), 1);
    });

    test('closes the loading dialog exactly once on every path', () async {
      final sent = _FakeOdoo({
        'account.move.action_invoice_sent': _sendWizardAction(),
        'account.move.send.wizard.create': 7,
        'account.move.send.wizard.action_send_and_print': true,
        'account.move.read': [
          {'is_move_sent': true, 'name': 'INV/2026/00010'},
        ],
      });
      final refused = _FakeOdoo({
        'account.move.action_invoice_sent': {'res_model': 'some.future.wizard'},
      });
      final failed = _FakeOdoo({'account.move.action_invoice_sent': null});

      expect(await send(sent), 1);
      expect(await send(refused), 1);
      expect(await send(failed), 1);
    });
  });
}
