import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobo_sales/utils/odoo_binary.dart';

void main() {
  // Odoo 20: Binary.convert_to_read (odoo/orm/fields_binary.py) returns
  // {'filename'?: ..., 'content': <base64>, 'size': N}; the JSON dispatcher
  // serialises it with json.dumps defaults, i.e. ", " and ": ".
  group('flattenOdooBinaryValues', () {
    test('turns a read() image object back into the base64 string', () {
      const raw =
          '{"jsonrpc": "2.0", "id": 1, "result": [{"id": 2, "name": "Admin", '
          '"image_1920": {"content": "iVBORw0KGgo=", "size": 8}, '
          '"phone": false}]}';

      final decoded = jsonDecode(flattenOdooBinaryValues(raw));

      final row = decoded['result'][0] as Map;
      expect(row['image_1920'], 'iVBORw0KGgo=');
      expect(row['name'], 'Admin');
      expect(row['phone'], false);
    });

    test('also flattens an object that carries a filename', () {
      const raw =
          '{"result": [{"signature": {"filename": "sig.png", '
          '"content": "QUJD", "size": 3}}]}';

      final row = jsonDecode(flattenOdooBinaryValues(raw))['result'][0] as Map;

      expect(row['signature'], 'QUJD');
    });

    test('copes with escapes and braces inside the filename', () {
      const raw =
          r'{"v": {"filename": "we\"ird {name}\\.png", "content": "QUJD", '
          r'"size": 3}, "w": 1}';

      final decoded = jsonDecode(flattenOdooBinaryValues(raw)) as Map;

      expect(decoded['v'], 'QUJD');
      expect(decoded['w'], 1);
    });

    test('reads compact JSON as well as the default spacing', () {
      const raw =
          '[{"a":{"content":"QUJD","size":3},"b":{"size":1,"content":"WA=="}}]';

      final row =
          (jsonDecode(flattenOdooBinaryValues(raw)) as List).first as Map;

      expect(row['a'], 'QUJD');
      expect(row['b'], 'WA==');
    });

    test('flattens every record of a list, and leaves empty fields alone', () {
      final raw = jsonEncode({
        'result': [
          {
            'id': 1,
            'image_128': {'content': 'AAA=', 'size': 2},
          },
          {'id': 2, 'image_128': false},
          {
            'id': 3,
            'image_128': {'content': 'BBB=', 'size': 2},
          },
        ],
      });

      final rows = jsonDecode(flattenOdooBinaryValues(raw))['result'] as List;

      expect(rows.map((r) => r['image_128']), ['AAA=', false, 'BBB=']);
    });

    test('leaves objects that are not binary values untouched', () {
      const cases = [
        '{"a": {"content": "x"}}',
        '{"a": {"content": 5, "size": 1}}',
        '{"a": {"content": "x", "size": 1, "extra": 2}}',
        '{"a": {"content": "x", "content": "y", "size": 1}}',
        '{"a": {"size": 1, "checksum": "abc"}}',
        '{"a": {"id": 1, "content": "<p>hello</p>"}}',
        '{"a": {"content": "x", "size": "big"}}',
      ];
      for (final raw in cases) {
        expect(flattenOdooBinaryValues(raw), raw, reason: raw);
      }
    });

    test('does not mistake JSON quoted inside a string for an object', () {
      final raw = jsonEncode({
        'note': '{"content": "QUJD", "size": 3}',
        'html': '<style>{"content": "x", "size": 1}</style>',
      });

      expect(flattenOdooBinaryValues(raw), raw);
    });

    test('returns the very same text when there is nothing to flatten', () {
      const raw = '{"result": [{"id": 1, "name": "Azure Interior"}]}';

      expect(identical(flattenOdooBinaryValues(raw), raw), isTrue);
    });

    test('survives truncated or malformed input', () {
      const cases = [
        '{"a": {"content": "QUJD',
        '{"a": {"content": "QUJD", "size": ',
        '{"a": {"content": "QUJD", "size": 3',
        '{"a": {"content": "QUJD", "size": 3,',
        '{{{{"content"',
        '',
      ];
      for (final raw in cases) {
        expect(flattenOdooBinaryValues(raw), raw, reason: raw);
      }
    });

    test('handles a multi-megabyte image', () {
      final image = base64Encode(
        List<int>.generate(3 * 1024 * 1024, (i) => i & 0xFF),
      );
      final raw =
          '{"result": [{"image_1920": {"content": "$image", "size": 3145728}}]}';

      final flat = flattenOdooBinaryValues(raw);

      expect(flat.length, lessThan(raw.length));
      expect(jsonDecode(flat)['result'][0]['image_1920'], image);
    });
  });

  group('odooReadsBinaryAsObject', () {
    test('is true from Odoo 20 and for an unknown version', () {
      expect(odooReadsBinaryAsObject(17), isFalse);
      expect(odooReadsBinaryAsObject(18), isFalse);
      expect(odooReadsBinaryAsObject(19), isFalse);
      expect(odooReadsBinaryAsObject(20), isTrue);
      expect(odooReadsBinaryAsObject(21), isTrue);
      expect(odooReadsBinaryAsObject(0), isTrue);
    });
  });

  group('odooResponseMayCarryBinaryObjects', () {
    bool decide({
      String method = 'POST',
      String url = 'https://erp.example.com/web/dataset/call_kw',
      int status = 200,
      int generation = 20,
    }) => odooResponseMayCarryBinaryObjects(
      method: method,
      url: Uri.parse(url),
      statusCode: status,
      generation: generation,
    );

    test('is true for a successful call_kw on Odoo 20', () {
      expect(decide(), isTrue);
      expect(
        decide(url: 'https://erp.example.com/odoo/web/dataset/call_kw'),
        isTrue,
      );
      expect(decide(generation: 0), isTrue);
    });

    test('leaves older servers alone', () {
      for (final generation in [17, 18, 19]) {
        expect(decide(generation: generation), isFalse, reason: '$generation');
      }
    });

    test('leaves everything that is not a successful call_kw alone', () {
      expect(decide(method: 'GET'), isFalse);
      expect(decide(status: 500), isFalse);
      expect(decide(status: 404), isFalse);
      expect(
        decide(url: 'https://erp.example.com/web/session/get_session_info'),
        isFalse,
      );
      expect(
        decide(url: 'https://erp.example.com/web/content/7/file.pdf'),
        isFalse,
      );
      expect(
        decide(url: 'https://erp.example.com/web/session/authenticate'),
        isFalse,
      );
    });
  });

  group('odooBinaryToBase64', () {
    test('reads the string of Odoo 17-19 and the object of Odoo 20', () {
      expect(odooBinaryToBase64('QUJD'), 'QUJD');
      expect(odooBinaryToBase64({'content': 'QUJD', 'size': 3}), 'QUJD');
      expect(
        odooBinaryToBase64({'filename': 'a.png', 'content': 'QUJD', 'size': 3}),
        'QUJD',
      );
    });

    test('maps every flavour of empty to null', () {
      expect(odooBinaryToBase64(false), isNull);
      expect(odooBinaryToBase64(null), isNull);
      expect(odooBinaryToBase64(''), isNull);
      expect(odooBinaryToBase64({'size': 0}), isNull);
      expect(odooBinaryToBase64({'content': '', 'size': 0}), isNull);
      expect(odooBinaryToBase64(42), isNull);
    });
  });

  group('flattenOdooBinaryResponse', () {
    http.StreamedResponse responseWith(String body, {int status = 200}) {
      final bytes = utf8.encode(body);
      return http.StreamedResponse(
        http.ByteStream.fromBytes(bytes),
        status,
        contentLength: bytes.length,
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'content-length': '${bytes.length}',
          'set-cookie': 'session_id=abc; Path=/',
        },
        reasonPhrase: 'OK',
      );
    }

    test('rewrites the body and keeps status and headers', () async {
      final response = await flattenOdooBinaryResponse(
        responseWith(
          '{"result": [{"name": "Café Ünïcode", '
          '"image_1920": {"content": "QUJD", "size": 3}}]}',
        ),
      );

      final body = await http.Response.fromStream(response);
      final row = jsonDecode(body.body)['result'][0] as Map;

      expect(row['image_1920'], 'QUJD');
      expect(row['name'], 'Café Ünïcode');
      expect(response.statusCode, 200);
      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
      expect(response.headers['set-cookie'], 'session_id=abc; Path=/');
      expect(response.headers.containsKey('content-length'), isFalse);
      expect(response.contentLength, utf8.encode(body.body).length);
    });

    test(
      'passes a body without binary objects through byte for byte',
      () async {
        const original = '{"result": [{"name": "Café"}]}';

        final response = await flattenOdooBinaryResponse(
          responseWith(original),
        );
        final body = await http.Response.fromStream(response);

        expect(body.bodyBytes, utf8.encode(original));
      },
    );
  });
}
