import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/odoo_compat.dart';

/// The grouped reads of `DashboardScreen` (`_safeAggregateSumInCompanyCurrency`,
/// `_safeAggregateSum`, `_fetchDailyRevenue`, `_safeTopProducts`), made with the
/// same arguments, against a stand-in for each Odoo generation. They pin down
/// that the screen asks Odoo what it asked before and still finds, in the rows
/// it gets back, the keys it reads (`amount_total`, `__count`,
/// `currency_rate`, `date_order:day`, `product_id`, `currency_id`,
/// `product_uom_qty`, `price_total`).
///
/// `sale.order.currency_rate`, `sale.order.line.currency_id`, `price_total` and
/// `product_uom_qty` are stored in Odoo 17 to 20 (addons/sale/models/
/// sale_order.py and sale_order_line.py), so all of them can be grouped or
/// summed in SQL; `state` has no `done` value in any of them, which only means
/// the `('state', 'in', ['sale', 'done'])` filter matches the `sale` orders.
void main() {
  group('on Odoo 20 (formatted_read_group)', () {
    test('revenue by day and rate', () async {
      Map<String, dynamic>? sent;
      final rows = await OdooCompat.readGroup(
        model: 'sale.order',
        domain: [
          [
            'state',
            'in',
            ['sale', 'done'],
          ],
          ['date_order', '>=', '2026-10-03 00:00:00'],
          ['date_order', '<', '2026-10-10 00:00:00'],
        ],
        fields: const ['date_order', 'amount_total:sum'],
        groupby: const ['date_order:day', 'currency_rate'],
        orderby: 'date_order:day',
        generation: 20,
        callKw: (payload) async {
          sent = payload;
          return [
            {
              'date_order:day': ['2026-10-08', '08 Oct 2026'],
              'currency_rate': 0.5,
              'amount_total:sum': 80.0,
              '__count': 2,
              '__extra_domain': [],
            },
          ];
        },
      );

      expect(sent!['method'], 'formatted_read_group');
      final kwargs = sent!['kwargs'] as Map;
      expect(kwargs['groupby'], ['date_order:day', 'currency_rate']);
      expect(kwargs['aggregates'], ['amount_total:sum', '__count']);
      expect(kwargs['order'], 'date_order:day');

      // what _fetchDailyRevenue reads
      final group = rows.single;
      expect(group['date_order:day'], '08 Oct 2026');
      expect(group['amount_total'], 80.0);
      expect(group['currency_rate'], 0.5);
    });

    test('total by rate, for the company-currency conversion', () async {
      final rows = await OdooCompat.readGroup(
        model: 'sale.order',
        domain: const [],
        fields: const ['amount_total:sum'],
        groupby: const ['currency_rate'],
        generation: 20,
        callKw: (_) async => [
          {'currency_rate': 1.0, 'amount_total:sum': 100.0, '__count': 3},
          {'currency_rate': 0.5, 'amount_total:sum': 40.0, '__count': 1},
        ],
      );

      // what _safeAggregateSumInCompanyCurrency reads
      expect(rows.map((r) => r['amount_total']), [100.0, 40.0]);
      expect(rows.map((r) => r['__count']), [3, 1]);
      expect(rows.map((r) => r['currency_rate']), [1.0, 0.5]);
    });

    test('a total over everything is one row, with no group', () async {
      Map<String, dynamic>? sent;
      final rows = await OdooCompat.readGroup(
        model: 'account.move',
        domain: [
          ['move_type', '=', 'out_invoice'],
          ['state', '=', 'posted'],
        ],
        fields: const ['amount_residual_signed:sum'],
        groupby: const [],
        generation: 20,
        callKw: (payload) async {
          sent = payload;
          return [
            {'amount_residual_signed:sum': 1250.5, '__count': 4},
          ];
        },
      );

      expect((sent!['kwargs'] as Map)['groupby'], isEmpty);
      // what _safeAggregateSum reads
      expect(rows.first['amount_residual_signed'], 1250.5);
      expect(rows.first['__count'], 4);
    });

    test('top products, ordered by quantity with a limit', () async {
      Map<String, dynamic>? sent;
      final rows = await OdooCompat.readGroup(
        model: 'sale.order.line',
        domain: [
          [
            'order_id.state',
            'in',
            ['sale', 'done'],
          ],
          ['product_id', '!=', false],
        ],
        fields: const ['product_id', 'product_uom_qty:sum', 'price_total:sum'],
        groupby: const ['product_id', 'currency_id'],
        orderby: 'product_uom_qty:sum desc',
        limit: 200,
        generation: 20,
        callKw: (payload) async {
          sent = payload;
          return [
            {
              'product_id': [7, 'Desk'],
              'currency_id': [2, 'EUR'],
              'product_uom_qty:sum': 12.0,
              'price_total:sum': 1380.0,
              '__count': 5,
            },
          ];
        },
      );

      final kwargs = sent!['kwargs'] as Map;
      expect(kwargs['groupby'], ['product_id', 'currency_id']);
      expect(kwargs['aggregates'], [
        'product_uom_qty:sum',
        'price_total:sum',
        '__count',
      ]);
      expect(kwargs['order'], 'product_uom_qty:sum desc');
      expect(kwargs['limit'], 200);

      // what _safeTopProducts reads
      final group = rows.single;
      expect(group['product_id'], [7, 'Desk']);
      expect(group['currency_id'], [2, 'EUR']);
      expect(group['product_uom_qty'], 12.0);
      expect(group['price_total'], 1380.0);
    });

    test('orders per product count the groups', () async {
      Map<String, dynamic>? sent;
      final rows = await OdooCompat.readGroup(
        model: 'sale.order.line',
        domain: [
          ['product_id', '=', 7],
        ],
        fields: const ['order_id'],
        groupby: const ['order_id'],
        generation: 20,
        callKw: (payload) async {
          sent = payload;
          return [
            {
              'order_id': [11, 'S00011'],
              '__count': 2,
            },
            {
              'order_id': [12, 'S00012'],
              '__count': 1,
            },
          ];
        },
      );

      expect((sent!['kwargs'] as Map)['aggregates'], ['__count']);
      expect(rows, hasLength(2)); // _safeTopProducts uses .length
    });
  });

  group('on Odoo 17 and 18 (read_group)', () {
    test('keeps the call the dashboard always made', () async {
      for (final generation in [17, 18]) {
        Map<String, dynamic>? sent;
        await OdooCompat.readGroup(
          model: 'sale.order.line',
          domain: [
            ['product_id', '!=', false],
          ],
          fields: const [
            'product_id',
            'product_uom_qty:sum',
            'price_total:sum',
          ],
          groupby: const ['product_id', 'currency_id'],
          orderby: 'product_uom_qty:sum desc',
          limit: 200,
          generation: generation,
          callKw: (payload) async {
            sent = payload;
            return <Map<String, dynamic>>[];
          },
        );

        expect(sent!['method'], 'read_group', reason: 'Odoo $generation');
        expect(sent!['args'], [
          [
            ['product_id', '!=', false],
          ],
        ]);
        final kwargs = sent!['kwargs'] as Map;
        expect(kwargs['fields'], [
          'product_id',
          'product_uom_qty:sum',
          'price_total:sum',
        ]);
        expect(kwargs['groupby'], ['product_id', 'currency_id']);
        expect(kwargs['orderby'], 'product_uom_qty:sum desc');
        expect(kwargs['limit'], 200);
        expect(kwargs['lazy'], false);
      }
    });
  });
}
