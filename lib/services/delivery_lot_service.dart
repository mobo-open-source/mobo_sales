import 'odoo_session_manager.dart';

/// A lot or serial number with stock at a delivery's source location.
class LotStock {
  const LotStock({
    required this.lotId,
    required this.name,
    required this.available,
  });

  final int lotId;
  final String name;

  /// What can still be taken from it: on hand, less what other transfers hold.
  final double available;
}

/// One lot or serial number reserved on a delivery line.
class MoveLot {
  const MoveLot({
    required this.lotId,
    required this.name,
    required this.quantity,
  });

  /// Null for a reserved line that carries no lot yet.
  final int? lotId;
  final String name;
  final double quantity;
}

/// `serial`, `lot` or `none` for the `tracking` value Odoo sent for a product.
///
/// Odoo 17 to 19 send the text `none` for an untracked product. Odoo 20 sends
/// `false`, because its `tracking` selection holds only `lot` and `serial`.
/// Reading `false` as text gave `"false"`, which is not `none`, so on Odoo 20
/// every product counted as tracked and no delivery could be confirmed.
String normalizeTracking(dynamic raw) {
  if (raw is String && (raw == 'lot' || raw == 'serial')) return raw;
  return 'none';
}

/// What the operation type of a delivery allows for lots and serial numbers
/// (`use_existing_lots` and `use_create_lots` on `stock.picking.type`).
///
/// A delivery normally only picks lots that already exist. Switching on
/// "Create New Lots/Serial Numbers" on its operation type also lets a delivery
/// make new ones, which is where Odoo shows its Generate button.
class LotOptions {
  const LotOptions({this.canCreate = false, this.canUseExisting = true});

  final bool canCreate;
  final bool canUseExisting;
}

/// The serial or lot numbers [count] starting at [first], the way Odoo counts:
/// the last run of digits is incremented and keeps its zero padding
/// (`SN-009` gives `SN-009`, `SN-010`, ...), and a name with no digits gets a
/// `0` added first.
///
/// This is `stock.lot.generate_lot_names` of Odoo 17 to 19. The app asks the
/// server for the real thing (Odoo 20 also takes the product's lot sequence
/// into account) and falls back to this only when that call fails.
List<String> generateLotNamesLocally(String first, int count) {
  if (count <= 0) return const [];
  final digits = RegExp(r'\d+').allMatches(first).map((m) => m.group(0)!);
  if (digits.isEmpty) return generateLotNamesLocally('${first}0', count);
  final initial = digits.last;
  final padding = initial.length;
  final parts = first.split(initial);
  final prefix = parts.sublist(0, parts.length - 1).join(initial);
  final suffix = parts.last;
  final start = int.parse(initial);
  return [
    for (var i = 0; i < count; i++)
      '$prefix${(start + i).toString().padLeft(padding, '0')}$suffix',
  ];
}

/// Lot and serial number handling for a delivery (`stock.picking`).
///
/// Odoo will not validate a transfer while a tracked product's line has no lot
/// or serial number (`button_validate` raises "You need to supply a Lot/Serial
/// Number"). On a delivery the lot must be one that already exists, so the user
/// picks it from the lots that have stock at the source location. The model
/// and field names used here are the same on Odoo 17 through 20.
class DeliveryLotService {
  DeliveryLotService._();

  static final DeliveryLotService instance = DeliveryLotService._();

  Future<dynamic> _call(
    String model,
    String method,
    List<dynamic> args, [
    Map<String, dynamic> kwargs = const {},
  ]) => OdooSessionManager.safeCallKw({
    'model': model,
    'method': method,
    'args': args,
    'kwargs': kwargs,
  });

  /// `serial`, `lot` or `none` for each of [productIds].
  Future<Map<int, String>> tracking(Iterable<int> productIds) async {
    final ids = productIds.toSet().toList();
    if (ids.isEmpty) return {};
    final rows = await _call('product.product', 'read', [
      ids,
      ['tracking'],
    ]);
    final result = <int, String>{};
    if (rows is List) {
      for (final row in rows) {
        result[row['id'] as int] = normalizeTracking(row['tracking']);
      }
    }
    return result;
  }

  /// The lots reserved on each move of [pickingId], by move id.
  Future<Map<int, List<MoveLot>>> moveLots(int pickingId) async {
    final rows = await _call(
      'stock.move.line',
      'search_read',
      [
        [
          ['picking_id', '=', pickingId],
        ],
      ],
      {
        'fields': ['move_id', 'lot_id', 'lot_name', 'quantity'],
      },
    );
    final result = <int, List<MoveLot>>{};
    if (rows is! List) return result;
    for (final row in rows) {
      final move = row['move_id'];
      if (move is! List || move.isEmpty) continue;
      final lot = row['lot_id'];
      final lotId = lot is List && lot.isNotEmpty ? lot[0] as int : null;
      final name = lot is List && lot.length > 1
          ? lot[1].toString()
          : (row['lot_name'] is String ? row['lot_name'] as String : '');
      result
          .putIfAbsent(move[0] as int, () => [])
          .add(
            MoveLot(
              lotId: lotId,
              name: name,
              quantity: ((row['quantity'] as num?) ?? 0).toDouble(),
            ),
          );
    }
    return result;
  }

  /// The names of the tracked products on [pickingId] that still have a
  /// reserved quantity with no lot or serial number.
  Future<List<String>> productsMissingLots(int pickingId) async {
    final rows = await _call(
      'stock.move.line',
      'search_read',
      [
        [
          ['picking_id', '=', pickingId],
          ['lot_id', '=', false],
          ['quantity', '>', 0],
        ],
      ],
      {
        'fields': ['product_id'],
      },
    );
    if (rows is! List || rows.isEmpty) return [];

    final products = <int, String>{};
    for (final row in rows) {
      final product = row['product_id'];
      if (product is List && product.length > 1) {
        products[product[0] as int] = product[1].toString();
      }
    }
    final tracking = await this.tracking(products.keys);
    return [
      for (final entry in products.entries)
        if ((tracking[entry.key] ?? 'none') != 'none') entry.value,
    ];
  }

  /// The lots of [productId] with stock at [locationId] (or inside it), with
  /// what is free to take. [ownReserved] is what the line being edited already
  /// holds by lot id, which counts as free for it.
  Future<List<LotStock>> availableLots({
    required int productId,
    required int locationId,
    Map<int, double> ownReserved = const {},
  }) async {
    final rows = await _call(
      'stock.quant',
      'search_read',
      [
        [
          ['product_id', '=', productId],
          ['location_id', 'child_of', locationId],
          ['lot_id', '!=', false],
          ['quantity', '>', 0],
        ],
      ],
      {
        'fields': ['lot_id', 'quantity', 'reserved_quantity'],
      },
    );
    final byLot = <int, LotStock>{};
    if (rows is List) {
      for (final row in rows) {
        final lot = row['lot_id'];
        if (lot is! List || lot.length < 2) continue;
        final lotId = lot[0] as int;
        final free =
            ((row['quantity'] as num?) ?? 0).toDouble() -
            ((row['reserved_quantity'] as num?) ?? 0).toDouble();
        final previous = byLot[lotId];
        byLot[lotId] = LotStock(
          lotId: lotId,
          name: lot[1].toString(),
          available: (previous?.available ?? 0) + free,
        );
      }
    }
    final lots = [
      for (final lot in byLot.values)
        LotStock(
          lotId: lot.lotId,
          name: lot.name,
          available: lot.available + (ownReserved[lot.lotId] ?? 0),
        ),
    ]..removeWhere((lot) => lot.available <= 0);
    lots.sort((a, b) => a.name.compareTo(b.name));
    return lots;
  }

  /// What the operation type [pickingTypeId] allows. A server that does not
  /// say gets the ordinary delivery default: existing lots only.
  Future<LotOptions> lotOptions(int pickingTypeId) async {
    try {
      final rows = await _call('stock.picking.type', 'read', [
        [pickingTypeId],
        ['use_create_lots', 'use_existing_lots'],
      ]);
      if (rows is List && rows.isNotEmpty) {
        final row = rows.first as Map;
        return LotOptions(
          canCreate: row['use_create_lots'] == true,
          canUseExisting: row['use_existing_lots'] != false,
        );
      }
    } catch (_) {}
    return const LotOptions();
  }

  /// [count] numbers starting at [first], as Odoo's Generate button makes them.
  Future<List<String>> generateNames(String first, int count) async {
    final name = first.trim();
    if (name.isEmpty || count <= 0) return const [];
    try {
      final rows = await _call('stock.lot', 'generate_lot_names', [
        name,
        count,
      ]);
      if (rows is List && rows.isNotEmpty) {
        final names = [
          for (final row in rows)
            if (row is Map && row['lot_name'] != null)
              row['lot_name'].toString(),
        ];
        if (names.length == count) return names;
      }
    } catch (_) {}
    return generateLotNamesLocally(name, count);
  }

  /// The number after the last one made for [productId], which Odoo puts in
  /// the "first serial number" box. Null when there is none yet.
  Future<String?> nextSerial(int productId, int? companyId) async {
    try {
      final rows = await _call(
        'stock.lot',
        'search_read',
        [
          [
            ['product_id', '=', productId],
            if (companyId != null) ...[
              '|',
              ['company_id', '=', companyId],
              ['company_id', '=', false],
            ],
          ],
        ],
        {
          'fields': ['name'],
          'order': 'id desc',
          'limit': 1,
        },
      );
      if (rows is List && rows.isNotEmpty) {
        final last = (rows.first as Map)['name']?.toString();
        if (last != null && last.isNotEmpty) {
          return (await generateNames(last, 2)).last;
        }
      }
    } catch (_) {}
    return null;
  }

  /// The id of the lot [name] of [productId], making it when it does not exist
  /// (what a delivery that may create lots does with a number nobody has used).
  Future<int> _lotIdFor(String name, int productId, int? companyId) async {
    final found = await _call(
      'stock.lot',
      'search',
      [
        [
          ['name', '=', name],
          ['product_id', '=', productId],
          if (companyId != null) ...[
            '|',
            ['company_id', '=', companyId],
            ['company_id', '=', false],
          ],
        ],
      ],
      {'limit': 1},
    );
    if (found is List && found.isNotEmpty) return found.first as int;
    final created = await _call('stock.lot', 'create', [
      {'name': name, 'product_id': productId, 'company_id': ?companyId},
    ]);
    return created is List ? created.first as int : created as int;
  }

  /// Replaces what [moveId] has reserved with [lots] (lot id to quantity) and
  /// [newLots] (lot or serial number to quantity, made first when they do not
  /// exist).
  ///
  /// The old reservation is released and the chosen lots are reserved and
  /// marked picked. If reserving the new lots fails, the stock is reserved
  /// again as it was before the error is rethrown, so a failed attempt never
  /// leaves the line with nothing.
  Future<void> saveLots({
    required int pickingId,
    required int moveId,
    required int productId,
    required int locationId,
    required int destinationId,
    required Map<int, double> lots,
    Map<String, double> newLots = const {},
    int? companyId,
  }) async {
    // The new numbers first: a lot that cannot be made must not leave the
    // line with its old reservation already gone.
    final wanted = Map<int, double>.of(lots);
    for (final entry in newLots.entries) {
      final id = await _lotIdFor(entry.key, productId, companyId);
      wanted[id] = (wanted[id] ?? 0) + entry.value;
    }

    final existing = await _call('stock.move.line', 'search', [
      [
        ['move_id', '=', moveId],
      ],
    ]);
    if (existing is List && existing.isNotEmpty) {
      await _call('stock.move.line', 'unlink', [existing]);
    }
    try {
      for (final entry in wanted.entries) {
        if (entry.value <= 0) continue;
        await _call('stock.move.line', 'create', [
          {
            'move_id': moveId,
            'picking_id': pickingId,
            'product_id': productId,
            'location_id': locationId,
            'location_dest_id': destinationId,
            'lot_id': entry.key,
            'quantity': entry.value,
            'picked': true,
          },
        ]);
      }
    } catch (_) {
      try {
        await _call('stock.picking', 'action_assign', [
          [pickingId],
        ]);
      } catch (_) {}
      rethrow;
    }
  }
}
