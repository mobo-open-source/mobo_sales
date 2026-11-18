import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/odoo_form_defaults.dart';

/// The app asks Odoo what its own form would fill in on a new record, and adds
/// only what it does not send itself — never standing in the way of a save.
void main() {
  /// A `fields_get` answer shaped like Odoo 20's for `sale.order`.
  const saleOrderFields = {
    'partner_id': {'type': 'many2one', 'store': true, 'readonly': false},
    'company_id': {'type': 'many2one', 'store': true, 'readonly': false},
    'warehouse_id': {'type': 'many2one', 'store': true, 'readonly': false},
    'team_id': {'type': 'many2one', 'store': true, 'readonly': false},
    'journal_id': {'type': 'many2one', 'store': true, 'readonly': false},
    'currency_id': {'type': 'many2one', 'store': true, 'readonly': true},
    'tax_country_id': {'type': 'many2one', 'store': false, 'readonly': false},
    'name': {'type': 'char', 'store': true, 'readonly': false},
    'order_line': {'type': 'one2many', 'store': true, 'readonly': false},
  };

  late List<Map<String, dynamic>> calls;
  var key = 0;

  /// A fresh account each test, so no test reads another's cached schema.
  String nextAccount() => 'db|${++key}';

  Future<dynamic> Function(Map<String, dynamic>) server(
    Map<String, dynamic> onchangeValue,
  ) => (params) async {
    calls.add(params);
    switch (params['method']) {
      case 'fields_get':
        return saleOrderFields;
      case 'onchange':
        return {'value': onchangeValue};
    }
    return null;
  };

  setUp(() {
    calls = [];
    OdooFormDefaults.clearCache();
  });

  test('adds what the form fills and the app does not send', () async {
    final added = await OdooFormDefaults.missingMany2oneValues(
      callKw: server({'warehouse_id': 7, 'team_id': 1, 'journal_id': false}),
      model: 'sale.order',
      values: {'partner_id': 9, 'company_id': 14, 'state': 'draft'},
      accountKey: nextAccount(),
      context: const {
        'allowed_company_ids': [14],
        'company_id': 14,
      },
    );

    expect(added, {'warehouse_id': 7, 'team_id': 1});
  });

  test('asks the way the web form does, in the same company', () async {
    await OdooFormDefaults.missingMany2oneValues(
      callKw: server({'warehouse_id': 7}),
      model: 'sale.order',
      values: {'partner_id': 9, 'company_id': 14},
      accountKey: nextAccount(),
      context: const {
        'allowed_company_ids': [14],
        'company_id': 14,
      },
    );

    final onchange = calls.singleWhere((c) => c['method'] == 'onchange');
    final args = onchange['args'] as List;
    expect(args[0], isEmpty, reason: 'a new record');
    expect(args[1], {'partner_id': 9, 'company_id': 14});
    expect(args[2], isEmpty, reason: "the form's first call names no field");
    expect(
      (args[3] as Map).keys.toSet(),
      {'warehouse_id', 'team_id', 'journal_id'},
      reason: 'only the savable many2ones the app does not send',
    );
    expect(onchange['kwargs'], {
      'context': {
        'allowed_company_ids': [14],
        'company_id': 14,
      },
    });
  });

  test('never overrides a value the app sends', () async {
    final added = await OdooFormDefaults.missingMany2oneValues(
      callKw: server({'partner_id': 99, 'company_id': 1, 'warehouse_id': 7}),
      model: 'sale.order',
      values: {'partner_id': 9, 'company_id': 14},
      accountKey: nextAccount(),
    );

    expect(added, {'warehouse_id': 7});
  });

  test('asks for the schema once per account', () async {
    final account = nextAccount();
    for (var i = 0; i < 3; i++) {
      await OdooFormDefaults.missingMany2oneValues(
        callKw: server({'warehouse_id': 7}),
        model: 'sale.order',
        values: {'partner_id': 9},
        accountKey: account,
      );
    }
    expect(calls.where((c) => c['method'] == 'fields_get'), hasLength(1));
    expect(calls.where((c) => c['method'] == 'onchange'), hasLength(3));
  });

  test('adds nothing when the server refuses — the save goes on', () async {
    final added = await OdooFormDefaults.missingMany2oneValues(
      callKw: (params) async {
        if (params['method'] == 'onchange') throw Exception('Invalid field');
        return saleOrderFields;
      },
      model: 'sale.order',
      values: {'partner_id': 9},
      accountKey: nextAccount(),
    );
    expect(added, isEmpty);
  });

  test('adds nothing when the server does not answer in time', () async {
    final added = await OdooFormDefaults.missingMany2oneValues(
      callKw: (_) => Completer<dynamic>().future,
      model: 'sale.order',
      values: {'partner_id': 9},
      accountKey: nextAccount(),
      timeout: const Duration(milliseconds: 50),
    );
    expect(added, isEmpty);
  });

  group('reading the answer', () {
    test('a many2one comes back as its id, or false when empty', () {
      expect(
        OdooFormDefaults.many2oneIdsFrom(
          {'warehouse_id': 7, 'team_id': false},
          ['warehouse_id', 'team_id', 'user_id'],
        ),
        {'warehouse_id': 7},
      );
    });

    test('the [id, name] and {id, display_name} shapes are read too', () {
      expect(
        OdooFormDefaults.many2oneIdsFrom(
          {
            'warehouse_id': [7, 'WH'],
            'team_id': {'id': 3, 'display_name': 'Sales'},
          },
          ['warehouse_id', 'team_id'],
        ),
        {'warehouse_id': 7, 'team_id': 3},
      );
    });

    test('only stored, writable many2ones are asked for', () {
      expect(OdooFormDefaults.savableMany2oneFields(saleOrderFields), [
        'company_id',
        'journal_id',
        'partner_id',
        'team_id',
        'warehouse_id',
      ]);
    });
  });
}
