import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/invoice_filter_domain.dart';

import '../helpers/odoo_domain.dart';

Map<String, dynamic> _inv(
  int id,
  String state,
  String payment, {
  String type = 'out_invoice',
  String date = '2026-10-01',
  String due = '2099-01-01',
  int partner = 7,
  String origin = '',
}) => {
  'id': id,
  'name': 'INV/$id',
  'move_type': type,
  'state': state,
  'payment_state': payment,
  'invoice_date': date,
  'invoice_date_due': due,
  'partner_id': [partner, partner == 7 ? 'Azure' : 'Deco'],
  'partner_id.name': partner == 7 ? 'Azure' : 'Deco',
  'invoice_origin': origin,
};

void main() {
  final odoo = OdooDomain([
    _inv(1, 'draft', 'not_paid', date: '2026-10-01'),
    _inv(2, 'posted', 'not_paid', date: '2026-10-05', due: '2020-01-01'),
    _inv(3, 'posted', 'paid', date: '2026-10-10'),
    _inv(4, 'posted', 'partial', date: '2026-10-15', due: '2020-01-01'),
    _inv(5, 'posted', 'in_payment', date: '2026-10-20'),
    _inv(6, 'posted', 'reversed', date: '2026-10-25', partner: 8),
    _inv(7, 'posted', 'blocked', date: '2026-10-28'),
    _inv(8, 'cancel', 'not_paid', date: '2026-10-02'),
    _inv(9, 'posted', 'not_paid', type: 'in_invoice'),
    _inv(10, 'posted', 'paid', partner: 8, origin: 'S00042'),
  ]);

  List<int> shown({
    Set<String> status = const {},
    DateTime? start,
    DateTime? end,
    String search = '',
    int? customer,
    String? origin,
    bool overdue = false,
    bool unpaid = false,
  }) {
    final domain = invoiceListDomain(
      statusFilters: status,
      startDate: start,
      endDate: end,
      searchQuery: search,
      customerId: customer,
      saleOrderName: origin,
      overdueOnly: overdue,
      unpaidOnly: unpaid,
      today: DateTime(2026, 10, 30),
    );
    return odoo.search(domain).map((r) => r['id'] as int).toList()..sort();
  }

  group('each status filter', () {
    test('no filter lists customer invoices and refunds only', () {
      expect(shown(), [1, 2, 3, 4, 5, 6, 7, 8, 10]);
    });
    test('Draft', () => expect(shown(status: {'draft'}), [1]));
    test('Posted: every posted one, however paid', () {
      expect(shown(status: {'posted'}), [2, 3, 4, 5, 6, 7, 10]);
    });
    test('Paid', () => expect(shown(status: {'paid'}), [3, 10]));
    test('Partially Paid', () => expect(shown(status: {'partial'}), [4]));
    test('Not Paid: posted and unpaid', () {
      expect(shown(status: {'not_paid'}), [2]);
    });
    test('In Payment', () => expect(shown(status: {'in_payment'}), [5]));
    test('Reversed', () => expect(shown(status: {'reversed'}), [6]));
    test('Blocked', () => expect(shown(status: {'blocked'}), [7]));
    test('Cancelled', () => expect(shown(status: {'cancelled'}), [8]));
  });

  group('status filters together show any of them', () {
    test('two with a one-leaf domain each', () {
      expect(shown(status: {'draft', 'cancelled'}), [1, 8]);
    });
    test('one with a two-leaf domain beside a one-leaf one', () {
      // Not Paid is `& state payment_state`: three tokens, which counting
      // tokens for the `|` operators turned into an invalid domain.
      expect(shown(status: {'not_paid', 'paid'}), [2, 3, 10]);
      expect(shown(status: {'paid', 'not_paid'}), [2, 3, 10]);
    });
    test('three, two of them compound', () {
      expect(shown(status: {'not_paid', 'draft', 'partial'}), [1, 2, 4]);
    });
    test('every status at once is every invoice', () {
      expect(
        shown(
          status: {
            'draft',
            'posted',
            'paid',
            'partial',
            'not_paid',
            'in_payment',
            'reversed',
            'blocked',
            'cancelled',
          },
        ),
        [1, 2, 3, 4, 5, 6, 7, 8, 10],
      );
    });
    test('the domain has exactly one operator fewer than alternatives', () {
      final domain = invoiceListDomain(statusFilters: {'not_paid', 'paid'});
      expect(domain.where((t) => t == '|'), hasLength(1));
    });
  });

  group('status with the other filters', () {
    test('a status and a date range', () {
      expect(
        shown(
          status: {'paid', 'partial'},
          start: DateTime(2026, 10, 12),
          end: DateTime(2026, 10, 31),
        ),
        [4],
      );
    });
    test('a date range alone', () {
      expect(
        shown(start: DateTime(2026, 10, 20), end: DateTime(2026, 10, 28)),
        [5, 6, 7],
      );
    });
    test('only a start, only an end', () {
      expect(shown(start: DateTime(2026, 10, 25)), [6, 7]);
      expect(shown(end: DateTime(2026, 10, 2)), [1, 8, 10]);
    });
    test('a status and a search', () {
      expect(shown(status: {'paid', 'reversed'}, search: 'deco'), [6, 10]);
      expect(shown(status: {'paid'}, search: 'INV/3'), [3]);
    });
    test('status, date range and search together', () {
      expect(
        shown(
          status: {'paid', 'posted'},
          start: DateTime(2026, 10, 9),
          end: DateTime(2026, 10, 31),
          search: 'azure',
        ),
        [3, 4, 5, 7],
      );
    });
  });

  group('the scope a list is opened for', () {
    test('a customer', () => expect(shown(customer: 8), [6, 10]));
    test('a customer with a status', () {
      expect(shown(customer: 8, status: {'paid', 'draft'}), [10]);
    });
    test('a sale order', () => expect(shown(origin: 'S00042'), [10]));
    test('overdue: posted, unpaid or partial, past due', () {
      expect(shown(overdue: true), [2, 4]);
    });
    test('overdue with a status', () {
      expect(shown(overdue: true, status: {'partial', 'paid'}), [4]);
    });
    test('unpaid', () => expect(shown(unpaid: true), [2, 4]));
  });
}
