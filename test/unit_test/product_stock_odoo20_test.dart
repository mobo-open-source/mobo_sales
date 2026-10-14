import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobo_sales/models/delivery.dart';
import 'package:mobo_sales/models/product.dart';
import 'package:mobo_sales/providers/product_provider.dart';
import 'package:mobo_sales/services/product_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks/mock_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('productTypeFilterDomain', () {
    // Odoo 17 has type = consu | service | product. Odoo 18 folded consu and
    // product into one value, `consu`, plus the boolean `is_storable`.
    List<List<dynamic>> chips(
      int generation, {
      bool services = false,
      bool consumables = false,
      bool storable = false,
      bool hasIsStorable = false,
    }) => productTypeFilterDomain(
      generation: generation,
      services: services,
      consumables: consumables,
      storable: storable,
      hasIsStorable: hasIsStorable,
    );

    test('no chip selected adds nothing, on every version', () {
      for (final generation in [0, 17, 18, 19, 20]) {
        expect(chips(generation), isEmpty);
        expect(chips(generation, hasIsStorable: true), isEmpty);
      }
    });

    test('Services is type = service on every version', () {
      for (final generation in [0, 17, 18, 19, 20]) {
        expect(chips(generation, services: true, hasIsStorable: true), [
          ['type', '=', 'service'],
        ]);
      }
    });

    test('Odoo 17 and an unknown version keep type = consu / product', () {
      for (final generation in [0, 17]) {
        expect(chips(generation, consumables: true), [
          ['type', '=', 'consu'],
        ]);
        expect(chips(generation, storable: true), [
          ['type', '=', 'product'],
        ]);
        // 17 has no is_storable, so the flag is never consulted.
        expect(chips(generation, storable: true, hasIsStorable: true), [
          ['type', '=', 'product'],
        ]);
      }
    });

    test('Odoo 18 and 19 with stock: Storable is Goods that track stock', () {
      for (final generation in [18, 19]) {
        expect(chips(generation, storable: true, hasIsStorable: true), [
          ['type', '=', 'consu'],
          ['is_storable', '=', true],
        ]);
      }
    });

    test('Odoo 18 and 19 with stock: Consumable is Goods that do not', () {
      for (final generation in [18, 19]) {
        expect(chips(generation, consumables: true, hasIsStorable: true), [
          ['type', '=', 'consu'],
          ['is_storable', '=', false],
        ]);
      }
    });

    test('Odoo 18 and 19 without is_storable never name a missing field', () {
      // No stock module, no is_storable: asking for it would fail the whole
      // product list. `type = product` matches nothing there, as it always did.
      for (final generation in [18, 19]) {
        final domain = chips(
          generation,
          consumables: true,
          storable: true,
          hasIsStorable: false,
        );
        expect(domain.where((leaf) => leaf[0] == 'is_storable'), isEmpty);
        expect(domain, [
          ['type', '=', 'consu'],
          ['type', '=', 'product'],
        ]);
      }
    });

    test('Odoo 20 always has is_storable, known or not', () {
      for (final hasIsStorable in [true, false]) {
        expect(chips(20, storable: true, hasIsStorable: hasIsStorable), [
          ['type', '=', 'consu'],
          ['is_storable', '=', true],
        ]);
        expect(chips(20, consumables: true, hasIsStorable: hasIsStorable), [
          ['type', '=', 'consu'],
          ['is_storable', '=', false],
        ]);
      }
    });

    test('type = product is never sent where it is not a value', () {
      for (final generation in [18, 19, 20]) {
        final domain = chips(
          generation,
          services: true,
          consumables: true,
          storable: true,
          hasIsStorable: true,
        );
        expect(
          domain.any((leaf) => leaf[0] == 'type' && leaf[2] == 'product'),
          isFalse,
          reason: 'generation $generation',
        );
      }
    });
  });

  group('productSearchDomain', () {
    // The domain is a flat prefix expression of `|` operators then leaves.
    int operators(List<dynamic> domain) => domain.where((t) => t == '|').length;
    List<List<dynamic>> leaves(List<dynamic> domain) => [
      for (final t in domain)
        if (t is List) t.cast<dynamic>(),
    ];

    test('matches name, internal reference and barcode with an OR', () {
      for (final generation in [0, 17, 18, 19]) {
        final domain = productSearchDomain('abc', generation: generation);

        expect(leaves(domain), [
          ['name', 'ilike', 'abc'],
          ['default_code', 'ilike', 'abc'],
          ['barcode', 'ilike', 'abc'],
        ]);
        // 3 leaves need 2 operators, all in front: a complete expression.
        expect(operators(domain), 2);
        expect(domain.take(2), ['|', '|']);
      }
    });

    test('Odoo 20 also searches the variants barcodes', () {
      // 20 keeps a template barcode only for a single-variant template; the
      // variants of a multi-variant one are found through the one2many.
      final domain = productSearchDomain('abc', generation: 20);

      expect(leaves(domain), [
        ['name', 'ilike', 'abc'],
        ['default_code', 'ilike', 'abc'],
        ['barcode', 'ilike', 'abc'],
        ['product_variant_ids.barcode', 'ilike', 'abc'],
      ]);
      expect(operators(domain), 3);
    });

    test(
      'Odoo 17 to 19 never name the variants path, which 17 to 19 cover',
      () {
        for (final generation in [0, 17, 18, 19]) {
          final domain = productSearchDomain('abc', generation: generation);
          expect(
            leaves(domain).any((l) => l[0] == 'product_variant_ids.barcode'),
            isFalse,
          );
        }
      },
    );

    test('the stock check search adds the category name, in its old order', () {
      final domain = productSearchDomain(
        'abc',
        generation: 19,
        includeCategory: true,
      );

      expect(leaves(domain).map((l) => l[0]), [
        'name',
        'default_code',
        'categ_id.name',
        'barcode',
      ]);
      expect(operators(domain), 3);
    });

    test('every operator comes before every leaf', () {
      for (final generation in [0, 17, 18, 19, 20]) {
        for (final includeCategory in [false, true]) {
          final domain = productSearchDomain(
            'abc',
            generation: generation,
            includeCategory: includeCategory,
          );
          final firstLeaf = domain.indexWhere((t) => t is List);
          expect(domain.skip(firstLeaf).any((t) => t == '|'), isFalse);
          expect(operators(domain), leaves(domain).length - 1);
        }
      }
    });
  });

  group('uomOptionFields', () {
    test('asks for category_id only where uom.uom still has it', () {
      expect(uomOptionFields(0), contains('category_id'));
      expect(uomOptionFields(17), contains('category_id'));
      expect(uomOptionFields(18), contains('category_id'));
      expect(uomOptionFields(19), isNot(contains('category_id')));
      expect(uomOptionFields(20), isNot(contains('category_id')));
    });

    test('always asks for id and name, which the picker shows', () {
      for (final generation in [0, 17, 18, 19, 20]) {
        expect(uomOptionFields(generation), containsAll(['id', 'name']));
      }
    });
  });

  group('supplierVendorName', () {
    test('reads the vendor from the partner_id many2one', () {
      expect(
        supplierVendorName({
          'partner_id': [7, 'Azure Interior'],
          'price': 12.5,
        }),
        'Azure Interior',
      );
    });

    test('trims the name', () {
      expect(
        supplierVendorName({
          'partner_id': [7, '  Azure Interior '],
        }),
        'Azure Interior',
      );
    });

    test('falls back to a plain name for a row that carries one', () {
      expect(supplierVendorName({'name': 'Legacy Vendor'}), 'Legacy Vendor');
      expect(
        supplierVendorName({
          'name': [3, 'Legacy Vendor'],
        }),
        'Legacy Vendor',
      );
    });

    test('a row without a real vendor gives null', () {
      expect(supplierVendorName({'price': 3.0}), isNull);
      expect(supplierVendorName({'partner_id': false}), isNull);
      expect(supplierVendorName({'partner_id': <dynamic>[]}), isNull);
      expect(
        supplierVendorName({
          'partner_id': [1, ''],
        }),
        isNull,
      );
      expect(
        supplierVendorName({
          'partner_id': [1, 'false'],
        }),
        isNull,
      );
      expect(
        supplierVendorName({
          'partner_id': [1, 'Unknown Vendor'],
        }),
        isNull,
      );
    });
  });

  group('delivery field names', () {
    test(
      'picking moves: move_ids_without_package until 18, move_ids from 19',
      () {
        expect(pickingMovesField(17), 'move_ids_without_package');
        expect(pickingMovesField(18), 'move_ids_without_package');
        expect(pickingMovesField(19), 'move_ids');
        expect(pickingMovesField(20), 'move_ids');
      },
    );

    test('an unknown version asks for the older picking moves field', () {
      expect(pickingMovesField(0), 'move_ids_without_package');
    });

    test('move unit: product_uom until 19, uom_id from 20', () {
      expect(stockMoveUomFields(17), ['product_uom']);
      expect(stockMoveUomFields(18), ['product_uom']);
      expect(stockMoveUomFields(19), ['product_uom']);
      expect(stockMoveUomFields(20), ['uom_id']);
    });

    test('an unknown version tries both move unit fields, older first', () {
      expect(stockMoveUomFields(0), ['product_uom', 'uom_id']);
    });
  });

  group('ProductService', () {
    final service = ProductService.instance;

    group('canCreateProduct', () {
      test(
        'Odoo 20 asks has_access, the check that replaced the old one',
        () async {
          Map<String, dynamic>? sent;
          final allowed = await service.canCreateProduct(
            generation: 20,
            callKw: (payload) async {
              sent = payload;
              return true;
            },
          );

          expect(allowed, isTrue);
          expect(sent!['model'], 'product.template');
          expect(sent!['method'], 'has_access');
          expect(sent!['args'], [<int>[], 'create']);
        },
      );

      test('Odoo 17 keeps check_access_rights without raising', () async {
        Map<String, dynamic>? sent;
        final allowed = await service.canCreateProduct(
          generation: 17,
          callKw: (payload) async {
            sent = payload;
            return true;
          },
        );

        expect(allowed, isTrue);
        expect(sent!['method'], 'check_access_rights');
        expect(sent!['args'], ['create']);
        expect((sent!['kwargs'] as Map)['raise_exception'], false);
      });

      test('a refusal is false', () async {
        for (final generation in [17, 18, 19, 20]) {
          expect(
            await service.canCreateProduct(
              generation: generation,
              callKw: (_) async => false,
            ),
            isFalse,
            reason: 'generation $generation',
          );
        }
      });

      test('a failure to ask is false, not an exception', () async {
        expect(
          await service.canCreateProduct(
            generation: 20,
            callKw: (_) async => throw Exception('network down'),
          ),
          isFalse,
        );
      });

      test('an answer that is not a boolean is false', () async {
        expect(
          await service.canCreateProduct(
            generation: 20,
            callKw: (_) async => null,
          ),
          isFalse,
        );
      });
    });

    group('fetchGroupSummary', () {
      final domain = [
        ['sale_ok', '=', true],
      ];

      test(
        'Odoo 20 groups with formatted_read_group and keeps the old rows',
        () async {
          Map<String, dynamic>? sent;
          final rows = await service.fetchGroupSummary(
            domain: domain,
            groupBy: 'categ_id',
            generation: 20,
            callKw: (payload) async {
              sent = payload;
              return [
                {
                  'categ_id': [1, 'All / Saleable'],
                  '__count': 3,
                  '__extra_domain': [
                    ['categ_id', '=', 1],
                  ],
                },
                {
                  'categ_id': false,
                  '__count': 2,
                  '__extra_domain': [
                    ['categ_id', '=', false],
                  ],
                },
              ];
            },
          );

          expect(sent!['model'], 'product.template');
          expect(sent!['method'], 'formatted_read_group');
          expect(sent!['args'], [domain]);
          final kwargs = sent!['kwargs'] as Map;
          expect(kwargs['groupby'], ['categ_id']);
          expect(kwargs['aggregates'], ['__count']);
          expect(kwargs.containsKey('lazy'), isFalse);

          // The provider reads `__count` and the many2one pair, as it did from
          // the old read_group.
          expect(rows, hasLength(2));
          expect(rows[0]['categ_id'], [1, 'All / Saleable']);
          expect(rows[0]['__count'], 3);
          expect(rows[1]['categ_id'], false);
          expect(rows[1]['__count'], 2);
        },
      );

      test('a selection group keeps its raw value', () async {
        final rows = await service.fetchGroupSummary(
          domain: domain,
          groupBy: 'type',
          generation: 20,
          callKw: (_) async => [
            {'type': 'consu', '__count': 4, '__extra_domain': []},
            {'type': 'service', '__count': 1, '__extra_domain': []},
          ],
        );

        expect(rows.map((r) => r['type']), ['consu', 'service']);
        expect(rows.map((r) => r['__count']), [4, 1]);
      });

      test('Odoo 18 still calls the classic read_group', () async {
        Map<String, dynamic>? sent;
        final rows = await service.fetchGroupSummary(
          domain: domain,
          groupBy: 'categ_id',
          generation: 18,
          callKw: (payload) async {
            sent = payload;
            return [
              {
                'categ_id': [1, 'All'],
                '__count': 5,
              },
            ];
          },
        );

        expect(sent!['method'], 'read_group');
        expect(sent!['args'], [domain]);
        final kwargs = sent!['kwargs'] as Map;
        expect(kwargs['fields'], ['categ_id']);
        expect(kwargs['groupby'], ['categ_id']);
        expect(kwargs['lazy'], false);
        expect(rows.single['__count'], 5);
      });

      test('a server error reaches the caller', () async {
        expect(
          service.fetchGroupSummary(
            domain: domain,
            groupBy: 'categ_id',
            generation: 20,
            callKw: (_) async => throw Exception('boom'),
          ),
          throwsA(isA<Exception>()),
        );
      });
    });
  });

  group('ProductProvider domains', () {
    late MockProductService productService;
    late MockConnectivityService connectivity;
    late MockSessionService session;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      productService = MockProductService();
      connectivity = MockConnectivityService();
      session = MockSessionService();
      when(() => connectivity.isConnected).thenReturn(true);
      when(() => session.hasValidSession).thenReturn(true);
      when(
        () => productService.getProductCount(any()),
      ).thenAnswer((_) async => 0);
    });

    /// The domain `fetchProducts` sends for [filters] on a server of
    /// [generation].
    Future<List<dynamic>> domainSent(
      int generation,
      Map<String, dynamic> filters,
    ) async {
      List<dynamic>? seen;
      when(
        () => productService.fetchProducts(
          domain: any(named: 'domain'),
          fields: any(named: 'fields'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((invocation) async {
        seen = invocation.namedArguments[#domain] as List<dynamic>;
        return <Map<String, dynamic>>[];
      });

      final provider = ProductProvider(
        productService: productService,
        connectivityService: connectivity,
        sessionService: session,
        generationLoader: () async => generation,
      );
      await provider.fetchProducts(filters: filters);
      return seen!;
    }

    /// The domain `fetchProducts` sends for the search text [query].
    Future<List<dynamic>> searchDomainSent(int generation, String query) async {
      List<dynamic>? seen;
      when(
        () => productService.fetchProducts(
          domain: any(named: 'domain'),
          fields: any(named: 'fields'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((invocation) async {
        seen = invocation.namedArguments[#domain] as List<dynamic>;
        return <Map<String, dynamic>>[];
      });

      final provider = ProductProvider(
        productService: productService,
        connectivityService: connectivity,
        sessionService: session,
        generationLoader: () async => generation,
      );
      await provider.fetchProducts(searchQuery: query);
      return seen!;
    }

    test('Storable on Odoo 20 filters on is_storable', () async {
      final domain = await domainSent(20, {'showStorableOnly': true});

      expect(domain, contains(equals(['is_storable', '=', true])));
      expect(domain, contains(equals(['type', '=', 'consu'])));
      expect(domain, isNot(contains(equals(['type', '=', 'product']))));
      expect(domain, contains(equals(['sale_ok', '=', true])));
    });

    test('Consumables on Odoo 20 are Goods that do not track stock', () async {
      final domain = await domainSent(20, {'showConsumablesOnly': true});

      expect(domain, contains(equals(['type', '=', 'consu'])));
      expect(domain, contains(equals(['is_storable', '=', false])));
    });

    test('Storable on Odoo 17 is still type = product', () async {
      final domain = await domainSent(17, {'showStorableOnly': true});

      expect(domain, contains(equals(['type', '=', 'product'])));
      expect(domain.any((d) => d is List && d[0] == 'is_storable'), isFalse);
    });

    test('an unknown version asks what Odoo 17 understands', () async {
      final domain = await domainSent(0, {
        'showStorableOnly': true,
        'showServicesOnly': true,
      });

      expect(domain, contains(equals(['type', '=', 'product'])));
      expect(domain, contains(equals(['type', '=', 'service'])));
    });

    test('a generation that cannot be read falls back to Odoo 17', () async {
      when(
        () => productService.fetchProducts(
          domain: any(named: 'domain'),
          fields: any(named: 'fields'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => <Map<String, dynamic>>[]);

      final provider = ProductProvider(
        productService: productService,
        connectivityService: connectivity,
        sessionService: session,
        generationLoader: () async => throw Exception('no session'),
      );
      await provider.fetchProducts(filters: {'showStorableOnly': true});

      expect(provider.error, isNull);
    });

    test('a search on Odoo 20 looks through the variants barcodes', () async {
      final domain = await domainSent(20, {});
      expect(
        domain.any((t) => t is List && t[0] == 'product_variant_ids.barcode'),
        isFalse,
        reason: 'no search text, no search leaves',
      );

      final searched = await searchDomainSent(20, 'abc');
      expect(
        searched,
        contains(equals(['product_variant_ids.barcode', 'ilike', 'abc'])),
      );
      expect(searched, contains(equals(['barcode', 'ilike', 'abc'])));
    });

    test('a search on Odoo 18 keeps the plain barcode leaf', () async {
      final searched = await searchDomainSent(18, 'abc');

      expect(searched, contains(equals(['barcode', 'ilike', 'abc'])));
      expect(
        searched.any((t) => t is List && t[0] == 'product_variant_ids.barcode'),
        isFalse,
      );
    });

    test('the Available chip is unchanged: qty_available > 0', () async {
      final domain = await domainSent(20, {'showAvailableOnly': true});

      expect(domain, contains(equals(['qty_available', '>', 0])));
    });

    test('typeFilterLeaves answers for the generation it is given', () {
      final provider = ProductProvider(
        productService: productService,
        connectivityService: connectivity,
        sessionService: session,
        generationLoader: () async => 20,
      );

      expect(provider.typeFilterLeaves(storable: true, generation: 20), [
        ['type', '=', 'consu'],
        ['is_storable', '=', true],
      ]);
      expect(provider.typeFilterLeaves(storable: true, generation: 17), [
        ['type', '=', 'product'],
      ]);
    });
  });
}
