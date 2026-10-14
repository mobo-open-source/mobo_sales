/// Odoo keeps notes and terms in `Html` fields (`account.move.narration` is one
/// in Odoo 17, 18, 19 and 20), so a note typed as "Pay in 30 days" comes back as
/// `<p>Pay in 30 days</p>`. A text box shows and edits plain text; these two
/// functions go between the two.

/// The text of [html], as a person would read it: paragraphs and `<br>` become
/// line breaks, list items get a dash, tags are dropped and entities
/// (`&amp;`, `&nbsp;`, `&#39;`) become the characters they stand for. Odoo's
/// "no value" (`false`, null) is an empty string.
String htmlToPlainText(Object? html) {
  if (html == null || html == false) return '';
  var text = html.toString();
  if (text.trim().toLowerCase() == 'false') return '';

  text = text
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
      .replaceAll(
        RegExp(
          r'<(script|style)[^>]*>.*?</\1>',
          caseSensitive: false,
          dotAll: true,
        ),
        '',
      )
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</(p|div|h[1-6]|tr|table|ul|ol)>', caseSensitive: false),
        '\n\n',
      )
      .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '- ')
      .replaceAll(RegExp(r'</t[dh]>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]*>'), '');

  text = _decodeEntities(text)
      .replaceAll('\r\n', '\n')
      .replaceAll(' ', ' ')
      .split('\n')
      .map((line) => line.trimRight())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

/// [text] as the HTML Odoo expects for an `Html` field: each blank-line
/// separated paragraph in `<p>`, single line breaks as `<br>`, and `&`, `<`
/// and `>` escaped so what was typed is shown as typed. Null when [text] is
/// blank — the caller then writes Odoo's "no value" (`false`) or leaves the
/// field out.
String? plainTextToHtml(String text) {
  final trimmed = text.replaceAll('\r\n', '\n').trim();
  if (trimmed.isEmpty) return null;

  String escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  return trimmed
      .split(RegExp(r'\n\s*\n'))
      .map((paragraph) => paragraph.trim())
      .where((paragraph) => paragraph.isNotEmpty)
      .map(
        (paragraph) => '<p>${escape(paragraph).replaceAll('\n', '<br>')}</p>',
      )
      .join();
}

String _decodeEntities(String text) {
  const named = {
    '&nbsp;': ' ',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&apos;': "'",
    '&#39;': "'",
  };
  var out = text;
  named.forEach((entity, value) => out = out.replaceAll(entity, value));
  out = out.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
    final code = int.tryParse(m.group(1)!, radix: 16);
    return code == null ? m.group(0)! : String.fromCharCode(code);
  });
  out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    return code == null ? m.group(0)! : String.fromCharCode(code);
  });
  // The ampersand last, so "&amp;lt;" reads as "&lt;" and not "<".
  return out.replaceAll('&amp;', '&');
}
