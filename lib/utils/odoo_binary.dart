import 'dart:convert';

import 'package:http/http.dart' as http;

/// Whether `read`/`search_read` hand a binary or image field back as an object.
///
/// Odoo 17 to 19 return the base64 text itself (`"image_1920": "iVBOR..."`).
/// Odoo 20 returns `{"content": "iVBOR...", "size": 1234}`, with a `filename`
/// key too when the file has a name of its own. Everything in the app that
/// reads an avatar, a product photo, a logo or a signature expects the text, so
/// from 20 the transport flattens the objects back (see
/// [flattenOdooBinaryValues]). An unknown generation (0) is flattened as well:
/// the objects exist only on servers that send them, so there is nothing to
/// lose.
bool odooReadsBinaryAsObject(int generation) =>
    generation == 0 || generation >= 20;

/// Whether a response should go through [flattenOdooBinaryResponse]: it
/// answers a `call_kw` RPC (`POST .../dataset/call_kw`) successfully, on a
/// server that returns binary fields as objects (see [odooReadsBinaryAsObject]).
///
/// Nothing else is rewritten: downloads, session calls, errors and every older
/// server are passed through untouched.
bool odooResponseMayCarryBinaryObjects({
  required String method,
  required Uri url,
  required int statusCode,
  required int generation,
}) {
  if (method != 'POST' || statusCode != 200) return false;
  if (!url.path.endsWith('/dataset/call_kw')) return false;
  return odooReadsBinaryAsObject(generation);
}

/// The base64 text of a binary/image value as the server sent it, or `null`
/// when the field is empty.
///
/// Understands both shapes: the plain string of Odoo 17 to 19 and the
/// `{content, size}` object of Odoo 20. `false` is how Odoo says "no value".
String? odooBinaryToBase64(dynamic value) {
  if (value is String) return value.isEmpty ? null : value;
  if (value is Map) {
    final content = value['content'];
    if (content is String && content.isNotEmpty) return content;
  }
  return null;
}

/// Replaces every Odoo 20 binary object in [json] by its base64 string.
///
/// `{"content": "<base64>", "size": 12}` becomes `"<base64>"`, wherever it
/// sits in the document. Only an object whose keys are drawn from `filename`,
/// `content`, `size` and `checksum`, and that has a string `content` and a
/// `size`, is touched; any other object, however much it resembles one, is left
/// as it is. [json] comes back unchanged (the very same instance) when there is
/// nothing to flatten.
///
/// This works on the text rather than on decoded JSON so that a response full
/// of images is not parsed and serialised a second time: it jumps from `{` to
/// `{` with `indexOf` and reads a candidate only as far as it keeps looking like
/// a binary object.
String flattenOdooBinaryValues(String json) {
  if (!json.contains('"content"')) return json;

  StringBuffer? out;
  var copied = 0;
  var from = 0;
  while (true) {
    final open = json.indexOf('{', from);
    if (open < 0) break;
    final match = _matchBinaryObject(json, open);
    if (match == null) {
      from = open + 1;
      continue;
    }
    (out ??= StringBuffer())
      ..write(json.substring(copied, open))
      ..write(json.substring(match.contentStart, match.contentEnd));
    copied = match.end;
    from = match.end;
  }
  if (out == null) return json;
  return (out..write(json.substring(copied))).toString();
}

/// [response] with [flattenOdooBinaryValues] applied to its JSON body.
///
/// The body is read whole, which is what every RPC caller does anyway. When
/// nothing was flattened the original bytes are passed on untouched.
Future<http.StreamedResponse> flattenOdooBinaryResponse(
  http.StreamedResponse response,
) async {
  final bytes = await response.stream.toBytes();

  var body = bytes;
  try {
    final text = utf8.decode(bytes, allowMalformed: true);
    final flat = flattenOdooBinaryValues(text);
    if (!identical(flat, text)) body = utf8.encode(flat);
  } catch (_) {
    body = bytes;
  }

  return http.StreamedResponse(
    http.ByteStream.fromBytes(body),
    response.statusCode,
    contentLength: body.length,
    request: response.request,
    headers: {
      for (final entry in response.headers.entries)
        if (entry.key.toLowerCase() != 'content-length') entry.key: entry.value,
    },
    isRedirect: response.isRedirect,
    persistentConnection: response.persistentConnection,
    reasonPhrase: response.reasonPhrase,
  );
}

class _BinaryObject {
  const _BinaryObject(this.contentStart, this.contentEnd, this.end);

  /// The quoted `content` string, quotes included.
  final int contentStart;
  final int contentEnd;

  /// One past the closing `}`.
  final int end;
}

const int _quote = 0x22;
const int _backslash = 0x5C;
const int _comma = 0x2C;
const int _colon = 0x3A;
const int _closeBrace = 0x7D;

/// Reads the object opening at [open] if, and only as long as, it is a binary
/// object; `null` as soon as it is anything else.
_BinaryObject? _matchBinaryObject(String s, int open) {
  var i = open + 1;
  int? contentStart;
  int? contentEnd;
  var hasSize = false;
  var seen = 0;

  while (true) {
    i = _skipSpace(s, i);
    if (i >= s.length || s.codeUnitAt(i) != _quote) return null;

    int bit;
    var isString = true;
    if (s.startsWith('"content"', i)) {
      bit = 1;
      i += 9;
    } else if (s.startsWith('"size"', i)) {
      bit = 2;
      isString = false;
      i += 6;
    } else if (s.startsWith('"filename"', i)) {
      bit = 4;
      i += 10;
    } else if (s.startsWith('"checksum"', i)) {
      bit = 8;
      i += 10;
    } else {
      return null;
    }
    if (seen & bit != 0) return null;
    seen |= bit;

    i = _skipSpace(s, i);
    if (i >= s.length || s.codeUnitAt(i) != _colon) return null;
    i = _skipSpace(s, i + 1);
    if (i >= s.length) return null;

    if (isString) {
      if (s.codeUnitAt(i) != _quote) return null;
      final end = _endOfString(s, i);
      if (end < 0) return null;
      if (bit == 1) {
        contentStart = i;
        contentEnd = end;
      }
      i = end;
    } else {
      final end = _endOfNumber(s, i);
      if (end < 0) return null;
      hasSize = true;
      i = end;
    }

    i = _skipSpace(s, i);
    if (i >= s.length) return null;
    final next = s.codeUnitAt(i);
    if (next == _comma) {
      i++;
      continue;
    }
    if (next == _closeBrace) {
      i++;
      break;
    }
    return null;
  }

  if (contentStart == null || contentEnd == null || !hasSize) return null;
  return _BinaryObject(contentStart, contentEnd, i);
}

int _skipSpace(String s, int i) {
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (c != 0x20 && c != 0x0A && c != 0x0D && c != 0x09) break;
    i++;
  }
  return i;
}

/// One past the closing quote of the string opening at [start], or -1.
///
/// Uses `indexOf` to cross the string, so a multi-megabyte image is not walked
/// character by character; a quote preceded by an odd number of backslashes is
/// escaped and skipped.
int _endOfString(String s, int start) {
  var from = start + 1;
  while (true) {
    final quote = s.indexOf('"', from);
    if (quote < 0) return -1;
    var slashes = 0;
    var back = quote - 1;
    while (back > start && s.codeUnitAt(back) == _backslash) {
      slashes++;
      back--;
    }
    if (slashes.isEven) return quote + 1;
    from = quote + 1;
  }
}

/// One past the JSON number starting at [start], or -1 when there is none.
int _endOfNumber(String s, int start) {
  var i = start;
  var digits = 0;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    final isDigit = c >= 0x30 && c <= 0x39;
    final isNumberChar =
        isDigit ||
        c == 0x2D ||
        c == 0x2B ||
        c == 0x2E ||
        c == 0x65 ||
        c == 0x45;
    if (!isNumberChar) break;
    if (isDigit) digits++;
    i++;
  }
  return digits == 0 ? -1 : i;
}
