import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/main.dart' show navigatorKey;
import 'package:mobo_sales/screens/stock_check/inventory_details_screen.dart';
import 'package:mobo_sales/widgets/custom_snackbar.dart';
import 'package:shimmer/shimmer.dart';

Map<String, dynamic> _stock({
  List<Map<String, dynamic>> incoming = const [],
  List<Map<String, dynamic>> outgoing = const [],
  List<Map<String, dynamic>>? locations,
}) => {
  'stock_details':
      locations ??
      [
        // The reference-only location comes first on purpose: the page must
        // put what counts towards the totals above it.
        {
          'warehouse': 'Customers',
          'quantity': -3.0,
          'reserved_quantity': 0.0,
          'available': -3.0,
          'is_external': true,
          'location_type': 'customer',
          'is_counted_in_totals': false,
        },
        // Its name does not say what kind of location it is.
        {
          'warehouse': 'Acme Storage',
          'quantity': 0.0,
          'reserved_quantity': 0.0,
          'available': 0.0,
          'is_external': true,
          'location_type': 'supplier',
          'is_counted_in_totals': false,
        },
        {
          'warehouse': 'WH/Stock',
          'quantity': 14.0,
          'reserved_quantity': 2.0,
          'available': 12.0,
          'is_external': false,
          'location_type': 'internal',
          'is_counted_in_totals': true,
        },
      ],
  'incoming_stock': incoming,
  'outgoing_stock': outgoing,
  'totalInStock': 14.0,
  'totalReserved': 2.0,
  'totalIncoming': incoming.isEmpty ? 0.0 : 5.0,
  'totalOutgoing': outgoing.isEmpty ? 0.0 : 1.0,
  'forecastedStock': 19.5,
};

const _variant = {
  'id': 7,
  'name': 'Acoustic Bloc Screens',
  'default_code': 'FURN_6666',
  'barcode': 'N/A',
  'image_url': null,
};

const _template = {'category': 'Furniture / Office'};

void main() {
  Widget screen({
    required Future<Map<String, dynamic>> Function() load,
    Future<List<Map<String, String>>> Function()? attributes,
    ThemeData? theme,
  }) => MaterialApp(
    navigatorKey: navigatorKey,
    theme: theme,
    home: InventoryDetailsScreen(
      variant: _variant,
      template: _template,
      loadInventory: load,
      loadAttributes: attributes,
    ),
  );

  testWidgets(
    'shows the product at once and a skeleton until the stock is in',
    (tester) async {
      final stock = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(screen(load: () => stock.future));

      // The header is known from the list, so it is not waiting on the server.
      expect(find.text('Inventory Details'), findsOneWidget);
      expect(find.text('Acoustic Bloc Screens'), findsOneWidget);
      expect(find.text('FURN_6666'), findsOneWidget);
      expect(find.text('Furniture / Office'), findsOneWidget);
      // "N/A" is the list's placeholder for no barcode, not a barcode.
      expect(find.text('N/A'), findsNothing);

      // The figures and the cards below it are placeholders.
      expect(find.byType(Shimmer), findsWidgets);
      expect(find.text('Stock Locations'), findsNothing);

      stock.complete(_stock());
      await tester.pump();

      expect(find.byType(Shimmer), findsNothing);
      expect(find.text('Stock Locations'), findsOneWidget);
    },
  );

  testWidgets('lists the locations that count first and marks the others', (
    tester,
  ) async {
    await tester.pumpWidget(screen(load: () async => _stock()));
    await tester.pump();

    expect(find.text('Internal · 2 reserved'), findsOneWidget);
    // "Customers" already says it is a customer location; "Acme Storage"
    // does not say it is a vendor's.
    expect(find.text('Not counted'), findsOneWidget);
    expect(find.text('Vendor · Not counted'), findsOneWidget);
    expect(find.text('Customer · Not counted'), findsNothing);
    expect(
      tester.getTopLeft(find.text('WH/Stock')).dy,
      lessThan(tester.getTopLeft(find.text('Customers')).dy),
    );

    // The header carries the totals, without trailing zeros.
    expect(find.text('On Hand'), findsOneWidget);
    expect(find.text('Reserved'), findsOneWidget);
    expect(find.text('Forecasted'), findsOneWidget);
    expect(find.text('19.5'), findsOneWidget);
    expect(find.text('-3'), findsOneWidget);
    expect(find.text('14.0'), findsNothing);

    expect(find.textContaining('Totals count internal'), findsOneWidget);

    // Nothing is on its way, so there are no shipment cards or pills.
    expect(find.text('Incoming Shipments'), findsNothing);
    expect(find.text('Outgoing Shipments'), findsNothing);
    expect(find.textContaining('incoming'), findsNothing);
  });

  testWidgets('lists the incoming shipments with their route and date', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(
        load: () async => _stock(
          incoming: [
            {
              'quantity': 5.0,
              'expected_date': '2026-10-12 12:00:00',
              'from_location': 'Vendors',
              'to_location': 'WH/Stock',
            },
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Incoming Shipments'), findsOneWidget);
    expect(find.text('Outgoing Shipments'), findsNothing);
    expect(find.text('5 incoming'), findsOneWidget);
    expect(find.text('5 items'), findsOneWidget);
    expect(find.text('Vendors'), findsOneWidget);
    expect(find.text('12 Oct 2026'), findsOneWidget);
  });

  testWidgets('says so when no stock is recorded anywhere', (tester) async {
    await tester.pumpWidget(
      screen(load: () async => _stock(locations: const [])),
    );
    await tester.pump();

    expect(find.text('Stock Locations'), findsOneWidget);
    expect(find.text('No stock is recorded in any location.'), findsOneWidget);
  });

  testWidgets('shows the variant attributes once they are read', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(
        load: () async => _stock(),
        attributes: () async => [
          {'attribute_name': 'Color', 'value_name': 'White'},
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Color: White'), findsOneWidget);
  });

  testWidgets('a failed read shows the reason and Try again reads again', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      screen(
        load: () async {
          calls++;
          if (calls == 1) throw Exception('Connection error');
          return _stock();
        },
      ),
    );
    await tester.pump();

    expect(find.text('Unable to load inventory'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // Never a made-up zero: the figures are dashes, not 0.
    expect(find.text('–'), findsNWidgets(3));
    expect(find.text('Stock Locations'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();

    expect(calls, 2);
    expect(find.text('Unable to load inventory'), findsNothing);
    expect(find.text('Stock Locations'), findsOneWidget);
    expect(find.text('–'), findsNothing);
  });

  testWidgets('a refresh that fails keeps what is on the page', (tester) async {
    var calls = 0;
    try {
      await tester.pumpWidget(
        screen(
          load: () async {
            calls++;
            if (calls > 1) throw Exception('Connection error');
            return _stock();
          },
        ),
      );
      await tester.pump();
      expect(find.text('WH/Stock'), findsOneWidget);

      await tester.fling(
        find.byType(SingleChildScrollView),
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(calls, 2);
      expect(find.text('WH/Stock'), findsOneWidget);
      expect(find.text('Unable to load inventory'), findsNothing);
    } finally {
      CustomSnackbar.dismiss();
      await tester.pump();
    }
  });

  testWidgets('renders in the dark theme too', (tester) async {
    await tester.pumpWidget(
      screen(
        load: () async => _stock(
          incoming: [
            {
              'quantity': 1.0,
              'expected_date': 'N/A',
              'from_location': 'Vendors',
              'to_location': 'WH/Stock',
            },
          ],
        ),
        theme: ThemeData.dark(),
      ),
    );
    await tester.pump();

    expect(find.text('Stock Locations'), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
    expect(find.text('Not specified'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
