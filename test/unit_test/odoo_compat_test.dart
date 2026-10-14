import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/odoo_compat.dart';

void main() {
  /// A `formatted_read_group` result as Odoo 19/20 return it: many2one groups
  /// as [id, name], date groups as [isoStart, label], aggregates under
  /// `field:agg`, and the group's domain under `__extra_domain`.
  final formatted = [
    {
      'date_order:day': ['2026-10-01', '01 Oct 2026'],
      'currency_rate': 1.0,
      'amount_total:sum': 150.5,
      '__count': 3,
      '__extra_domain': [
        '&',
        ['date_order', '>=', '2026-10-01'],
        ['date_order', '<', '2026-10-02'],
      ],
    },
    {
      'date_order:day': ['2026-10-02', '02 Oct 2026'],
      'currency_rate': 0.5,
      'amount_total:sum': 40.0,
      '__count': 1,
      '__extra_domain': [],
    },
  ];

  group('readGroup on Odoo 20', () {
    test(
      'asks formatted_read_group, not the removed read_group signature',
      () async {
        Map<String, dynamic>? sent;
        await OdooCompat.readGroup(
          model: 'sale.order',
          domain: [
            ['state', '=', 'sale'],
          ],
          fields: ['date_order', 'amount_total:sum'],
          groupby: ['date_order:day', 'currency_rate'],
          orderby: 'date_order:day',
          limit: 5,
          generation: 20,
          callKw: (p) async {
            sent = p;
            return formatted;
          },
        );

        expect(sent!['model'], 'sale.order');
        expect(sent!['method'], 'formatted_read_group');
        expect(sent!['args'], [
          [
            ['state', '=', 'sale'],
          ],
        ]);
        final kw = sent!['kwargs'] as Map;
        expect(kw['groupby'], ['date_order:day', 'currency_rate']);
        expect(kw['aggregates'], ['amount_total:sum', '__count']);
        expect(kw['order'], 'date_order:day');
        expect(kw['limit'], 5);
        expect(kw.containsKey('lazy'), isFalse);
        expect(kw.containsKey('fields'), isFalse);
        expect(kw.containsKey('orderby'), isFalse);
      },
    );

    test('returns rows in the old read_group shape', () async {
      final rows = await OdooCompat.readGroup(
        model: 'sale.order',
        domain: const [],
        fields: ['date_order', 'amount_total:sum'],
        groupby: ['date_order:day', 'currency_rate'],
        generation: 20,
        callKw: (_) async => formatted,
      );

      expect(rows, hasLength(2));
      expect(
        rows[0]['date_order:day'],
        '01 Oct 2026',
        reason: 'label, as before',
      );
      expect(rows[0]['amount_total'], 150.5, reason: 'under the field name');
      expect(rows[0]['amount_total:sum'], 150.5, reason: 'and the full spec');
      expect(rows[0]['__count'], 3);
      expect(rows[0]['currency_rate'], 1.0);
      expect(rows[0]['__domain'], isNotEmpty);
      expect(rows[1]['amount_total'], 40.0);
      expect(rows[1]['__domain'], isEmpty);
    });

    test(
      'many2one groups stay [id, name]; selection and false pass through',
      () async {
        final rows = await OdooCompat.readGroup(
          model: 'sale.order.line',
          domain: const [],
          fields: ['product_id', 'product_uom_qty:sum'],
          groupby: ['product_id', 'state'],
          generation: 20,
          callKw: (_) async => [
            {
              'product_id': [7, 'Desk'],
              'state': 'sale',
              'product_uom_qty:sum': 4.0,
              '__count': 2,
              '__extra_domain': [],
            },
            {
              'product_id': false,
              'state': false,
              'product_uom_qty:sum': 1.0,
              '__count': 1,
              '__extra_domain': [],
            },
          ],
        );

        expect(rows[0]['product_id'], [7, 'Desk']);
        expect(rows[0]['state'], 'sale');
        expect(rows[0]['product_uom_qty'], 4.0);
        expect(rows[1]['product_id'], false);
      },
    );

    test('a count-only grouping needs no aggregates', () async {
      Map<String, dynamic>? sent;
      final rows = await OdooCompat.readGroup(
        model: 'res.partner',
        domain: const [],
        fields: ['id'],
        groupby: ['country_id'],
        generation: 20,
        callKw: (p) async {
          sent = p;
          return [
            {
              'country_id': [104, 'India'],
              '__count': 12,
              '__extra_domain': [],
            },
          ];
        },
      );
      expect((sent!['kwargs'] as Map)['aggregates'], ['__count']);
      expect(rows.single['__count'], 12);
    });

    test('an Odoo 19 server takes the same path', () async {
      Map<String, dynamic>? sent;
      await OdooCompat.readGroup(
        model: 'account.move',
        domain: const [],
        fields: ['id'],
        groupby: ['partner_id'],
        generation: 19,
        callKw: (p) async {
          sent = p;
          return [];
        },
      );
      expect(sent!['method'], 'formatted_read_group');
    });

    test('a non-list result is an empty list, not a crash', () async {
      final rows = await OdooCompat.readGroup(
        model: 'x',
        domain: const [],
        fields: const [],
        groupby: ['a'],
        generation: 20,
        callKw: (_) async => false,
      );
      expect(rows, isEmpty);
    });
  });

  group('readGroup before Odoo 19', () {
    test('keeps the classic call and returns its rows untouched', () async {
      Map<String, dynamic>? sent;
      final rows = await OdooCompat.readGroup(
        model: 'sale.order',
        domain: const [],
        fields: ['amount_total:sum'],
        groupby: ['partner_id'],
        orderby: 'partner_id',
        generation: 18,
        callKw: (p) async {
          sent = p;
          return [
            {
              'partner_id': [1, 'Ann'],
              'amount_total': 9.0,
              '__count': 2,
            },
          ];
        },
      );
      expect(sent!['method'], 'read_group');
      final kw = sent!['kwargs'] as Map;
      expect(kw['fields'], ['amount_total:sum']);
      expect(kw['groupby'], ['partner_id']);
      expect(kw['lazy'], false);
      expect(kw['orderby'], 'partner_id');
      expect(rows.single['amount_total'], 9.0);
    });
  });

  group('readGroup on an unknown version', () {
    test('tries the classic call first', () async {
      final methods = <String>[];
      await OdooCompat.readGroup(
        model: 'sale.order',
        domain: const [],
        fields: ['id'],
        groupby: ['partner_id'],
        generation: 0,
        callKw: (p) async {
          methods.add(p['method'] as String);
          return [];
        },
      );
      expect(methods, ['read_group']);
    });

    test(
      'falls back to formatted_read_group when the server refuses the old arguments',
      () async {
        final methods = <String>[];
        final rows = await OdooCompat.readGroup(
          model: 'sale.order',
          domain: const [],
          fields: ['amount_total:sum'],
          groupby: ['currency_rate'],
          generation: 0,
          callKw: (p) async {
            methods.add(p['method'] as String);
            if (p['method'] == 'read_group') {
              throw Exception(
                "TypeError: read_group() got an unexpected keyword argument 'fields'",
              );
            }
            return [
              {
                'currency_rate': 1.0,
                'amount_total:sum': 5.0,
                '__count': 1,
                '__extra_domain': [],
              },
            ];
          },
        );
        expect(methods, ['read_group', 'formatted_read_group']);
        expect(rows.single['amount_total'], 5.0);
      },
    );

    test('an unrelated error is not swallowed', () async {
      expect(
        OdooCompat.readGroup(
          model: 'sale.order',
          domain: const [],
          fields: const [],
          groupby: ['a'],
          generation: 0,
          callKw: (_) async => throw Exception('Access Denied'),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('readGroupAggregates', () {
    test('keeps field:agg, drops plain names, rewrites aliases', () {
      expect(
        OdooCompat.readGroupAggregates([
          'date_order',
          'amount_total:sum',
          'total:sum(price_total)',
          'id',
        ]),
        ['amount_total:sum', 'price_total:sum'],
      );
    });
  });

  group('hasAccess', () {
    test('Odoo 20 asks has_access with an empty id list', () async {
      Map<String, dynamic>? sent;
      final ok = await OdooCompat.hasAccess(
        model: 'sale.order',
        operation: 'create',
        generation: 20,
        callKw: (p) async {
          sent = p;
          return true;
        },
      );
      expect(ok, isTrue);
      expect(sent!['method'], 'has_access');
      expect(sent!['args'], [<int>[], 'create']);
    });

    test('Odoo 17 keeps check_access_rights without raising', () async {
      Map<String, dynamic>? sent;
      final ok = await OdooCompat.hasAccess(
        model: 'sale.order',
        operation: 'write',
        generation: 17,
        callKw: (p) async {
          sent = p;
          return false;
        },
      );
      expect(ok, isFalse);
      expect(sent!['method'], 'check_access_rights');
      expect(sent!['args'], ['write']);
      expect((sent!['kwargs'] as Map)['raise_exception'], false);
    });

    test('Odoo 18 and 19 use has_access', () async {
      for (final g in [18, 19]) {
        String? method;
        await OdooCompat.hasAccess(
          model: 'm',
          operation: 'read',
          generation: g,
          callKw: (p) async {
            method = p['method'] as String;
            return true;
          },
        );
        expect(method, 'has_access', reason: 'generation $g');
      }
    });

    test(
      'unknown version falls back to has_access when the old check is gone',
      () async {
        final methods = <String>[];
        final ok = await OdooCompat.hasAccess(
          model: 'm',
          operation: 'read',
          generation: 0,
          callKw: (p) async {
            methods.add(p['method'] as String);
            if (p['method'] == 'check_access_rights') {
              throw Exception(
                "AttributeError: 'm' has no attribute 'check_access_rights'",
              );
            }
            return true;
          },
        );
        expect(ok, isTrue);
        expect(methods, ['check_access_rights', 'has_access']);
      },
    );

    test('a failed call throws instead of answering "no"', () async {
      expect(
        OdooCompat.hasAccess(
          model: 'm',
          operation: 'read',
          generation: 20,
          callKw: (_) async => throw Exception('Network down'),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
