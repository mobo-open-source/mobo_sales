import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// An Odoo that evaluates the domain it is sent against a handful of orders,
/// so each filter of the quotations list is checked by what it returns, not by
/// the shape of the domain.
class FakeSaleOrderOdoo {
  FakeSaleOrderOdoo({this.withDeliveryStatus = true});

  final bool withDeliveryStatus;
  late HttpServer _http;

  /// Held back, to make a read slow.
  Completer<void>? gate;
  final searchReads = <List>[];
  final readGroups = <List>[];

  static Map<String, dynamic> _o(
    int id,
    String state, {
    String invoice = 'no',
    String? delivery,
    int user = 2,
    String validity = '2099-01-01',
    String created = '2026-10-01 10:00:00',
  }) => {
    'id': id,
    'name': 'S0000$id',
    'partner_id': [7, 'Azure Interior'],
    'date_order': created,
    'create_date': created,
    'state': state,
    'amount_total': 10.0 * id,
    'amount_untaxed': 10.0 * id,
    'amount_tax': 0.0,
    'currency_id': [1, 'USD'],
    'order_line': <int>[],
    'invoice_status': invoice,
    'delivery_status': delivery ?? false,
    'user_id': [user, 'U$user'],
    'validity_date': validity,
  };

  final orders = <Map<String, dynamic>>[
    _o(1, 'draft', validity: '2020-01-01'),
    _o(2, 'sent', user: 3, created: '2026-10-02 10:00:00'),
    _o(
      3,
      'sale',
      invoice: 'to invoice',
      delivery: 'pending',
      created: '2026-10-10 10:00:00',
    ),
    _o(
      4,
      'done',
      invoice: 'invoiced',
      delivery: 'full',
      user: 3,
      created: '2026-09-01 10:00:00',
    ),
    _o(
      5,
      'sale',
      invoice: 'invoiced',
      delivery: 'full',
      created: '2026-10-20 10:00:00',
    ),
    _o(6, 'cancel', created: '2026-10-03 10:00:00'),
  ];

  dynamic _value(Map<String, dynamic> o, String field) {
    if (field == 'user_id') return (o['user_id'] as List).first;
    if (field == 'partner_id.name') return (o['partner_id'] as List)[1];
    return o[field];
  }

  bool _leaf(Map<String, dynamic> o, List leaf) {
    final field = leaf[0] as String;
    if (field == 'delivery_status' && !withDeliveryStatus) {
      throw Exception('Invalid field delivery_status on model sale.order');
    }
    final op = leaf[1] as String;
    final want = leaf[2];
    final have = _value(o, field);
    switch (op) {
      case '=':
        return have == want;
      case 'in':
        return (want as List).contains(have);
      case '<':
        return have is String && have.compareTo(want as String) < 0;
      case '>=':
        return have is String && have.compareTo(want as String) >= 0;
      case '<=':
        return have is String && have.compareTo(want as String) <= 0;
      case 'ilike':
        return have.toString().toLowerCase().contains(
          (want as String).toLowerCase(),
        );
    }
    throw Exception('operator $op not handled by the fake');
  }

  /// Prefix-notation domain, as Odoo reads it: leaves are ANDed unless an
  /// operator says otherwise.
  bool _matches(Map<String, dynamic> o, List domain) {
    var i = 0;
    bool next() {
      final item = domain[i++];
      if (item == '|') return next() | next();
      if (item == '&') return next() & next();
      if (item == '!') return !next();
      return _leaf(o, item as List);
    }

    var ok = true;
    while (i < domain.length) {
      ok = next() && ok;
    }
    return ok;
  }

  List<Map<String, dynamic>> matching(List domain) => [
    for (final o in orders)
      if (_matches(o, domain)) o,
  ];

  String get url => 'http://127.0.0.1:${_http.port}';

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      _http.forEach((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final params = (body['params'] as Map?) ?? {};
        final model = params['model'];
        final method = params['method'];
        dynamic result = [];
        Object? error;
        if (method == 'check_access_rights' || method == 'has_access') {
          result = true;
        } else if (model == 'sale.order') {
          try {
            switch (method) {
              case 'fields_get':
                result = {
                  'name': {},
                  'state': {},
                  'invoice_status': {},
                  if (withDeliveryStatus) 'delivery_status': {},
                };
              case 'read_group':
                readGroups.add(params['args'][0] as List);
                final by = <String, int>{};
                for (final o in matching(params['args'][0] as List)) {
                  by.update('${o['state']}', (n) => n + 1, ifAbsent: () => 1);
                }
                result = [
                  for (final e in by.entries)
                    {'state': e.key, '__count': e.value, '__domain': []},
                ];
              case 'search_count':
                result = matching(params['args'][0] as List).length;
              case 'search_read':
                searchReads.add(params['args'][0] as List);
                if (gate != null) await gate!.future;
                result = matching(params['args'][0] as List);
            }
          } catch (e) {
            error = e;
          }
        }
        request.response
          ..persistentConnection = false
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              error == null
                  ? {'jsonrpc': '2.0', 'id': body['id'], 'result': result}
                  : {
                      'jsonrpc': '2.0',
                      'id': body['id'],
                      'error': {
                        'code': 200,
                        'message': 'Odoo Server Error',
                        'data': {
                          'name': 'odoo.exceptions.ValidationError',
                          'message': '$error',
                          'debug': '$error',
                        },
                      },
                    },
            ),
          );
        await request.response.close();
      }),
    );
  }

  Future<void> stop() => _http.close(force: true);
}
