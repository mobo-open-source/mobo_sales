import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/group_labels.dart';

void main() {
  const known = {'date_order': 'Order Date', 'user_id': 'Salesperson'};
  test('date granularities read as words', () {
    expect(groupByDisplayLabel('date_order:year', known), 'Order Date: Year');
    expect(groupByDisplayLabel('date_order:quarter', known), 'Order Date: Quarter');
    expect(groupByDisplayLabel('date_order:day', known), 'Order Date: Day');
  });
  test('known and unknown fields', () {
    expect(groupByDisplayLabel('user_id', known), 'Salesperson');
    expect(groupByDisplayLabel('x_some_field_id'), 'X Some Field');
    expect(groupByDisplayLabel('create_date:month'), 'Create Date: Month');
    expect(groupByDisplayLabel(null), '');
  });
}
