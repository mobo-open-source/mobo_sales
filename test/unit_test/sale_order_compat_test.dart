import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/models/sale_order_compat.dart';

void main() {
  group('sale.order.line field names', () {
    test('Odoo 17 and 18 use product_uom and tax_id', () {
      for (final generation in [17, 18]) {
        final spellings = SaleLineFields.candidates(generation);
        expect(spellings, hasLength(1), reason: 'generation $generation');
        expect(spellings.single.uom, 'product_uom');
        expect(spellings.single.tax, 'tax_id');
      }
    });

    test('Odoo 19 and 20 use product_uom_id and tax_ids', () {
      for (final generation in [19, 20, 21]) {
        final spellings = SaleLineFields.candidates(generation);
        expect(spellings, hasLength(1), reason: 'generation $generation');
        expect(spellings.single.uom, 'product_uom_id');
        expect(spellings.single.tax, 'tax_ids');
      }
    });

    test('the two names always move together, never mixed', () {
      expect(SaleLineFields.legacy.uom, 'product_uom');
      expect(SaleLineFields.legacy.tax, 'tax_id');
      expect(SaleLineFields.current.uom, 'product_uom_id');
      expect(SaleLineFields.current.tax, 'tax_ids');
    });

    test(
      'an unknown generation tries the 17/18 names, then the 19/20 ones',
      () {
        final spellings = SaleLineFields.candidates(0);
        expect(spellings, hasLength(2));
        expect(spellings.first.uom, 'product_uom');
        expect(spellings.last.uom, 'product_uom_id');
        expect(spellings.last.tax, 'tax_ids');
      },
    );
  });

  group('order line create commands', () {
    // The form keeps ids loosely: an int, a string, or Odoo's [id, name].
    int? toId(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is String) return int.tryParse(v);
      if (v is List && v.isNotEmpty) return toId(v.first);
      return null;
    }

    final lines = <Map<String, dynamic>>[
      {
        'product_id': 5,
        'product_name': 'Desk',
        'quantity': 2.0,
        'unit_price': 99.5,
        'uom_id': [3, 'Dozen'],
      },
      {
        'product_id': null,
        'product_name': 'Ghost',
        'quantity': 1.0,
        'unit_price': 1.0,
        'uom_id': 1,
      },
      {
        'product_id': '7',
        'product_name': 'Chair',
        'quantity': 1.0,
        'unit_price': 10.0,
        'uom_id': null,
      },
    ];

    test('Odoo 17 and 18 put the unit under product_uom', () {
      final uomField = SaleLineFields.candidates(18).first.uom;
      final commands = saleOrderLineCommands(lines, uomField, toId);

      expect(commands, hasLength(2));
      expect(commands.first, [
        0,
        0,
        {
          'product_id': 5,
          'name': 'Desk',
          'product_uom_qty': 2.0,
          'price_unit': 99.5,
          'product_uom': 3,
        },
      ]);
    });

    test('Odoo 19 and 20 put the unit under product_uom_id', () {
      for (final generation in [19, 20]) {
        final uomField = SaleLineFields.candidates(generation).first.uom;
        final values =
            saleOrderLineCommands(lines, uomField, toId).first[2] as Map;

        expect(values['product_uom_id'], 3, reason: 'generation $generation');
        expect(values.containsKey('product_uom'), isFalse);
      }
    });

    test('a line without a product is skipped', () {
      final commands = saleOrderLineCommands(lines, 'product_uom_id', toId);
      final names = [for (final c in commands) (c[2] as Map)['name']];
      expect(names, ['Desk', 'Chair']);
    });

    test('a missing unit falls back to id 1 and a string id is read', () {
      final commands = saleOrderLineCommands(lines, 'product_uom_id', toId);
      final chair = commands.last[2] as Map;
      expect(chair['product_id'], 7);
      expect(chair['product_uom_id'], 1);
    });

    test('each command creates a record: [0, 0, values]', () {
      for (final command in saleOrderLineCommands(lines, 'product_uom', toId)) {
        expect(command.take(2), [0, 0]);
        expect(command[2], isA<Map>());
      }
    });

    test('no lines, no commands', () {
      expect(saleOrderLineCommands(const [], 'product_uom', toId), isEmpty);
    });
  });

  group('fiscal position tax model', () {
    test('exists up to 18 and for an unknown server, gone from 19', () {
      expect(saleUsesFiscalPositionTaxModel(17), isTrue);
      expect(saleUsesFiscalPositionTaxModel(18), isTrue);
      expect(saleUsesFiscalPositionTaxModel(0), isTrue);
      expect(saleUsesFiscalPositionTaxModel(19), isFalse);
      expect(saleUsesFiscalPositionTaxModel(20), isFalse);
    });
  });

  group('online payment', () {
    test('Odoo 17 to 19 ask for require_payment', () {
      for (final generation in [17, 18, 19]) {
        expect(saleOrderPaymentFields(generation), ['require_payment']);
      }
    });

    test('Odoo 20 asks for prepayment_percent, which replaced it', () {
      expect(saleOrderPaymentFields(20), ['prepayment_percent']);
    });

    test('an unknown server is asked for both', () {
      expect(saleOrderPaymentFields(0), [
        'require_payment',
        'prepayment_percent',
      ]);
    });

    test('require_payment is derived from a positive prepayment', () {
      expect(
        withRequirePayment({'prepayment_percent': 0.5})['require_payment'],
        isTrue,
      );
      expect(
        withRequirePayment({'prepayment_percent': 1.0})['require_payment'],
        isTrue,
      );
      expect(
        withRequirePayment({'prepayment_percent': 0.0})['require_payment'],
        isFalse,
      );
    });

    test('a server that sends require_payment is believed', () {
      final row = withRequirePayment({
        'require_payment': false,
        'prepayment_percent': 0.5,
      });
      expect(row['require_payment'], isFalse);
    });

    test('nothing is invented when neither field was read', () {
      expect(
        withRequirePayment({'name': 'S001'}).containsKey('require_payment'),
        isFalse,
      );
    });
  });

  group('delivery status filters', () {
    test('Delivered matches fully delivered orders', () {
      expect(deliveryStatusLeaf('delivered'), ['delivery_status', '=', 'full']);
    });

    test('To Deliver matches every status short of fully delivered', () {
      expect(deliveryStatusLeaf('to_deliver'), [
        'delivery_status',
        'in',
        ['pending', 'started', 'partial'],
      ]);
    });

    test('only uses values that sale.order.delivery_status really has', () {
      // pending, started, partial, full in Odoo 17, 18, 19 and 20. A value
      // outside this set matches nothing, silently.
      const real = {'pending', 'started', 'partial', 'full'};
      for (final filter in ['delivered', 'to_deliver']) {
        final leaf = deliveryStatusLeaf(filter)!;
        final values = leaf[2] is List ? leaf[2] as List : [leaf[2]];
        expect(real.containsAll(values.cast<String>()), isTrue);
      }
    });

    test('other filters are not delivery filters', () {
      expect(deliveryStatusLeaf('invoiced'), isNull);
      expect(deliveryStatusLeaf('sale'), isNull);
    });

    test('each call returns a fresh leaf that is safe to modify', () {
      final first = deliveryStatusLeaf('delivered')!;
      first.add('x');
      expect(deliveryStatusLeaf('delivered'), hasLength(3));
    });
  });

  group('attachments', () {
    test('the file goes in datas up to Odoo 19 and in raw from 20', () {
      expect(attachmentContentField(17), 'datas');
      expect(attachmentContentField(18), 'datas');
      expect(attachmentContentField(19), 'datas');
      expect(attachmentContentField(0), 'datas');
      expect(attachmentContentField(20), 'raw');
      expect(attachmentContentField(21), 'raw');
    });

    Map<String, dynamic> create(int generation, {String? description}) =>
        attachmentCreateValues(
          generation: generation,
          orderId: 42,
          name: 'terms.pdf',
          base64Data: 'QUJD',
          mimetype: 'application/pdf',
          description: description,
        );

    test('Odoo 20 sends raw and never datas', () {
      final values = create(20);
      expect(values['raw'], 'QUJD');
      expect(values.containsKey('datas'), isFalse);
    });

    test('Odoo 19 and older send datas and never raw', () {
      for (final generation in [17, 18, 19, 0]) {
        final values = create(generation);
        expect(values['datas'], 'QUJD', reason: 'generation $generation');
        expect(values.containsKey('raw'), isFalse);
      }
    });

    test('links the file to the order whatever the server', () {
      final values = create(20);
      expect(values['name'], 'terms.pdf');
      expect(values['type'], 'binary');
      expect(values['res_model'], 'sale.order');
      expect(values['res_id'], 42);
      expect(values['mimetype'], 'application/pdf');
    });

    test('the description is only sent when there is one', () {
      expect(create(20).containsKey('description'), isFalse);
      expect(
        create(20, description: 'Signed copy')['description'],
        'Signed copy',
      );
    });
  });

  group('PDF quote builder', () {
    test('only Odoo 18 has save_included_pdf', () {
      expect(quoteBuilderSavesViaMethod(18), isTrue);
      expect(quoteBuilderSavesViaMethod(19), isFalse);
      expect(quoteBuilderSavesViaMethod(20), isFalse);
      expect(quoteBuilderSavesViaMethod(17), isFalse);
      expect(quoteBuilderSavesViaMethod(0), isFalse);
    });

    test('recognises the server saying the method does not exist', () {
      expect(
        quoteBuilderMethodMissing(
          Exception(
            "Odoo Server Error: The method 'sale.order.save_included_pdf' does not exist",
          ),
        ),
        isTrue,
      );
      expect(
        quoteBuilderMethodMissing(
          Exception("'sale.order' object has no attribute 'save_included_pdf'"),
        ),
        isTrue,
      );
    });

    test('does not mistake another failure for a missing method', () {
      expect(quoteBuilderMethodMissing(Exception('Session expired')), isFalse);
      expect(
        quoteBuilderMethodMissing(
          Exception('save_included_pdf: Access Denied'),
        ),
        isFalse,
      );
    });

    test(
      'writes the headers, footers and every line that offers documents',
      () {
        final writes = buildQuoteBuilderWrites(
          headerIds: [3, 1],
          footerIds: [2],
          productDocsByLine: {
            11: {7, 5},
          },
          lineIds: [11, 12],
        );

        expect(writes.orderValues, {
          'quotation_document_ids': [
            [
              6,
              0,
              [1, 2, 3],
            ],
          ],
        });
        expect(writes.lineValues.keys.toList(), [11, 12]);
        expect(writes.lineValues[11], {
          'product_document_ids': [
            [
              6,
              0,
              [5, 7],
            ],
          ],
        });
      },
    );

    test('a line with every document deselected is written empty', () {
      final writes = buildQuoteBuilderWrites(
        headerIds: const [],
        footerIds: const [],
        productDocsByLine: const {},
        lineIds: [12],
      );

      expect(writes.lineValues[12], {
        'product_document_ids': [
          [6, 0, <int>[]],
        ],
      });
      expect(writes.orderValues['quotation_document_ids'], [
        [6, 0, <int>[]],
      ]);
    });

    test('a line with a selection is written even when it was not listed', () {
      final writes = buildQuoteBuilderWrites(
        headerIds: const [],
        footerIds: const [],
        productDocsByLine: {
          20: {1},
        },
        lineIds: const [],
      );
      expect(writes.lineValues.keys, [20]);
    });

    test('a document on both lists is only written once', () {
      final writes = buildQuoteBuilderWrites(
        headerIds: [4, 4],
        footerIds: [4],
        productDocsByLine: const {},
        lineIds: const [],
      );
      expect(writes.orderValues['quotation_document_ids'], [
        [
          6,
          0,
          [4],
        ],
      ]);
    });
  });

  group('customer read on the quote form', () {
    test('Odoo 20 does not ask for company_name, which it removed', () {
      final fields = quoteCustomerFields(20);
      expect(fields, isNot(contains('company_name')));
      expect(fields, contains('parent_id'));
    });

    test('Odoo 19 and older ask for company_name as before', () {
      for (final generation in [17, 18, 19, 0]) {
        final fields = quoteCustomerFields(generation);
        expect(
          fields,
          contains('company_name'),
          reason: 'generation $generation',
        );
        expect(fields, isNot(contains('parent_id')));
      }
    });

    test('keeps the fields that exist on every version', () {
      for (final generation in [17, 19, 20]) {
        expect(
          quoteCustomerFields(generation),
          containsAll(['name', 'email', 'phone', 'vat', 'image_1920']),
        );
      }
    });
  });

  group('the signature tab', () {
    // The same four fields on Odoo 17, 18, 19 and 20 (sale/models/sale_order.py
    // in each tree), so the rule has no generation in it.
    // A quotation that is still open, so "asks for a signature" is also
    // "can still be given one". The tab needs one or the other.
    Map<String, dynamic> row({
      Object? require = false,
      Object? by = false,
      Object? on = false,
      Object? image = false,
      String state = 'draft',
    }) => {
      'require_signature': require,
      'signed_by': by,
      'signed_on': on,
      'signature': image,
      'state': state,
      'is_expired': false,
    };

    test('is there when the order asks for an online signature', () {
      expect(saleOrderShowsSignature(row(require: true)), isTrue);
    });

    test('is there once anything of a signature is on file', () {
      expect(saleOrderShowsSignature(row(by: 'Ada')), isTrue);
      expect(saleOrderShowsSignature(row(on: '2026-10-01 10:00:00')), isTrue);
      expect(saleOrderShowsSignature(row(image: 'iVBORw0KGgo=')), isTrue);
      // Odoo 20 sends an image as an object when nothing flattened it.
      expect(
        saleOrderShowsSignature(row(image: {'content': 'iVBOR', 'size': 5})),
        isTrue,
      );
    });

    test('is not there for an order that neither needs nor has one', () {
      expect(saleOrderShowsSignature(row()), isFalse);
      expect(
        saleOrderShowsSignature(row(by: '', on: null, image: false)),
        isFalse,
        reason: 'empty values are how Odoo says "not set"',
      );
    });

    test('is not there on a server that has none of the fields, or before '
        'anything was read', () {
      expect(saleOrderShowsSignature(const {}), isFalse);
      expect(
        saleOrderShowsSignature(const {'prepayment_percent': 0.0}),
        isFalse,
      );
    });

    test('is there when only some of the fields exist and one is set', () {
      // A server that lacks `signature` still answers for the others.
      expect(
        saleOrderShowsSignature({
          'require_signature': true,
          'state': 'draft',
        }),
        isTrue,
      );
      expect(saleOrderShowsSignature({'require_signature': false}), isFalse);
    });

    test('is not there once the order can no longer be signed', () {
      // What a tester hit on a confirmed order: a tab holding "Not signed
      // yet" and nothing that could be pressed.
      expect(saleOrderShowsSignature(row(require: true, state: 'sale')), isFalse);
    });

    test('is still there for a confirmed order that was signed', () {
      expect(
        saleOrderShowsSignature(row(require: true, state: 'sale', by: 'Ada')),
        isTrue,
        reason: 'the signature is worth showing even when it is settled',
      );
    });
  });

  group('whether Odoo would take a signature', () {
    // `_has_to_be_signed()` reads the same in sale/models/sale_order.py on
    // Odoo 17, 18, 19 and 20, so there is no generation in this either.
    Map<String, dynamic> order({
      String state = 'draft',
      bool expired = false,
      Object? require = true,
      Object? signature = false,
    }) => {
      'state': state,
      'is_expired': expired,
      'require_signature': require,
      'signature': signature,
    };

    test('yes for a draft or sent order that asks and is unsigned', () {
      expect(saleOrderHasToBeSigned(order(state: 'draft')), isTrue);
      expect(saleOrderHasToBeSigned(order(state: 'sent')), isTrue);
    });

    test('no once the order is confirmed', () {
      // What a tester hit: a capture pad on a Sales Order, which Odoo would
      // refuse — the portal only signs a quotation.
      for (final state in ['sale', 'done', 'cancel']) {
        expect(
          saleOrderHasToBeSigned(order(state: state)),
          isFalse,
          reason: state,
        );
      }
    });

    test('no once it has expired', () {
      expect(saleOrderHasToBeSigned(order(expired: true)), isFalse);
    });

    test('no when the order does not ask for one', () {
      expect(saleOrderHasToBeSigned(order(require: false)), isFalse);
      expect(saleOrderHasToBeSigned(order(require: null)), isFalse);
    });

    test('no once it is already signed', () {
      expect(
        saleOrderHasToBeSigned(order(signature: 'iVBORw0KGgo=')),
        isFalse,
      );
      expect(
        saleOrderHasToBeSigned(order(signature: {'content': 'iVBOR'})),
        isFalse,
      );
    });

    test('an empty signature is not a signature', () {
      expect(saleOrderHasToBeSigned(order(signature: '  ')), isTrue);
      expect(saleOrderHasToBeSigned(order(signature: false)), isTrue);
    });

    test('a server that would not give is_expired is treated as not', () {
      final row = order()..remove('is_expired');
      expect(saleOrderHasToBeSigned(row), isTrue);
    });

    test('nothing read yet is not an invitation to sign', () {
      expect(saleOrderHasToBeSigned(const {}), isFalse);
    });
  });
}
