import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/providers/product_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/odoo_domain.dart';
import '../mocks/mock_services.dart';

/// The products list filters, by what they return: each one, and every
/// combination the filter sheet allows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProductProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = ProductProvider(
      productService: MockProductService(),
      connectivityService: MockConnectivityService(),
      sessionService: MockSessionService(),
    );
  });

  Map<String, dynamic> p(
    int id,
    String name, {
    required String type,
    bool? storable,
    double qty = 0,
    bool active = true,
    bool saleOk = true,
    String code = '',
  }) => {
    'id': id,
    'name': name,
    'type': type,
    if (storable != null) 'is_storable': storable,
    'qty_available': qty,
    'active': active,
    'sale_ok': saleOk,
    'default_code': code,
    'barcode': '',
  };

  // Odoo 17: service / consu / product (storable).
  final v17 = OdooDomain([
    p(1, 'Consulting', type: 'service'),
    p(2, 'Paper', type: 'consu', qty: 5, code: 'PAP'),
    p(3, 'Desk', type: 'product', qty: 8, code: 'DSK'),
    p(4, 'Chair', type: 'product', qty: 0, code: 'CHR'),
    p(5, 'Old desk', type: 'product', qty: 3, active: false),
    p(6, 'Old service', type: 'service', active: false),
    p(7, 'Internal', type: 'product', qty: 9, saleOk: false),
  ]);

  // Odoo 20: service / consu, with `is_storable` on goods.
  final v20 = OdooDomain([
    p(1, 'Consulting', type: 'service'),
    p(2, 'Paper', type: 'consu', storable: false, qty: 5, code: 'PAP'),
    p(3, 'Desk', type: 'consu', storable: true, qty: 8, code: 'DSK'),
    p(4, 'Chair', type: 'consu', storable: true, qty: 0, code: 'CHR'),
    p(5, 'Old desk', type: 'consu', storable: true, qty: 3, active: false),
    p(6, 'Old service', type: 'service', active: false),
    p(7, 'Internal', type: 'consu', storable: true, qty: 9, saleOk: false),
  ]);

  List<int> shown(
    OdooDomain odoo,
    int generation, {
    bool services = false,
    bool consumables = false,
    bool storable = false,
    bool available = false,
    bool archived = false,
    String search = '',
  }) {
    final domain = provider.domainFor(search, 'All Products', {
      'showServicesOnly': services,
      'showConsumablesOnly': consumables,
      'showStorableOnly': storable,
      'showAvailableOnly': available,
      'showArchivedOnly': archived,
    }, generation: generation);
    return odoo.search(domain).map((r) => r['id'] as int).toList()..sort();
  }

  for (final (label, odoo, gen) in [
    ('Odoo 17', v17, 17),
    ('Odoo 20', v20, 20),
  ]) {
    group('$label products', () {
      test('no filter: sellable, active products', () {
        expect(shown(odoo, gen), [1, 2, 3, 4]);
      });
      test('Services', () => expect(shown(odoo, gen, services: true), [1]));
      test('Consumables', () {
        expect(shown(odoo, gen, consumables: true), [2]);
      });
      test('Storable', () {
        expect(shown(odoo, gen, storable: true), [3, 4]);
      });
      test('Available: in stock', () {
        expect(shown(odoo, gen, available: true), [2, 3]);
      });
      test('Archived: only what was archived', () {
        expect(shown(odoo, gen, archived: true), [5, 6]);
      });

      test('type chips are alternatives', () {
        expect(shown(odoo, gen, services: true, consumables: true), [1, 2]);
        expect(shown(odoo, gen, services: true, storable: true), [1, 3, 4]);
        expect(shown(odoo, gen, consumables: true, storable: true), [2, 3, 4]);
        expect(
          shown(odoo, gen, services: true, consumables: true, storable: true),
          [1, 2, 3, 4],
        );
      });

      test('a type with Available', () {
        expect(shown(odoo, gen, storable: true, available: true), [3]);
        expect(shown(odoo, gen, consumables: true, available: true), [2]);
        expect(shown(odoo, gen, services: true, available: true), isEmpty);
        expect(
          shown(odoo, gen, services: true, storable: true, available: true),
          [3],
        );
      });

      test('a type with Archived', () {
        expect(shown(odoo, gen, services: true, archived: true), [6]);
        expect(shown(odoo, gen, storable: true, archived: true), [5]);
        expect(
          shown(odoo, gen, services: true, storable: true, archived: true),
          [5, 6],
        );
      });

      test('Archived with Available', () {
        expect(shown(odoo, gen, archived: true, available: true), [5]);
      });

      test('every filter at once', () {
        expect(
          shown(
            odoo,
            gen,
            services: true,
            consumables: true,
            storable: true,
            available: true,
            archived: true,
          ),
          [5],
        );
      });

      test('a search narrows each filter', () {
        expect(shown(odoo, gen, search: 'desk'), [3]);
        expect(shown(odoo, gen, search: 'desk', archived: true), [5]);
        expect(shown(odoo, gen, search: 'DSK', storable: true), [3]);
        expect(shown(odoo, gen, search: 'e', storable: true, available: true), [
          3,
        ]);
        expect(shown(odoo, gen, search: 'chair', available: true), isEmpty);
      });
    });
  }
}
