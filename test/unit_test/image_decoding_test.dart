import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List?> decodeBase64Image(String imageUrl) async {
  try {
    final base64String = imageUrl.contains(',')
        ? imageUrl.split(',')[1]
        : imageUrl;

    final cleanBase64 = base64String.replaceAll(RegExp(r'\s+'), '');

    await Future.delayed(const Duration(milliseconds: 10));

    final bytes = base64Decode(cleanBase64);

    if (bytes.isNotEmpty) {
      if (bytes[0] == 0x3c) {
        return null;
      }
    }

    return bytes;
  } catch (e) {
    print('Error decoding: $e');
    return null;
  }
}

void main() {
  group('Image Decoding Tests', () {
    test('Decodes valid clean base64 string', () async {
      const validBase64 = 'SGVsbG8gV29ybGQ=';
      final result = await decodeBase64Image(validBase64);
      expect(result, isNotNull);
      expect(utf8.decode(result!), equals('Hello World'));
    });

    test('Decodes base64 string with newlines (MIME style)', () async {
      const base64WithNewlines = 'SGVsbG8g\nV29ybGQ=';
      final result = await decodeBase64Image(base64WithNewlines);
      expect(result, isNotNull);
      expect(utf8.decode(result!), equals('Hello World'));
    });

    test('Decodes data URI', () async {
      const dataUri = 'data:image/png;base64,SGVsbG8gV29ybGQ=';
      final result = await decodeBase64Image(dataUri);
      expect(result, isNotNull);
      expect(utf8.decode(result!), equals('Hello World'));
    });

    test('Returns null for invalid base64', () async {
      const invalidBase64 = 'Not a base64 string!!!';
      final result = await decodeBase64Image(invalidBase64);

      expect(result, isNull);
    });

    test('Returns null for SVG/XML content (starts with <)', () async {
      const svgBase64 = 'PHN2Zw==';
      final result = await decodeBase64Image(svgBase64);
      expect(result, isNull);
    });
  });
}
