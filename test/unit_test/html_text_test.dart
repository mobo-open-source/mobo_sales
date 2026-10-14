import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/html_text.dart';

/// Odoo keeps notes in HTML fields (account.move.narration in 17 to 20): the
/// text box shows and edits plain text.
void main() {
  group('htmlToPlainText', () {
    test('drops the paragraph tags Odoo wraps a note in', () {
      expect(htmlToPlainText('<p>xcds</p>'), 'xcds');
    });

    test('keeps paragraphs and line breaks as line breaks', () {
      expect(htmlToPlainText('<p>One</p><p>Two</p>'), 'One\n\nTwo');
      expect(htmlToPlainText('<p>One<br>Two<br/>Three</p>'), 'One\nTwo\nThree');
    });

    test('shows list items as dashes, drops the rest of the markup', () {
      expect(
        htmlToPlainText(
          '<p>Terms:</p><ul><li>Net 30</li><li><b>No</b> returns</li></ul>'
          '<a href="https://x.test">link</a>',
        ),
        'Terms:\n\n- Net 30\n- No returns\n\nlink',
      );
    });

    test('turns entities into their characters, the ampersand last', () {
      expect(
        htmlToPlainText(
          '<p>Tom &amp; Jerry &lt;b&gt;&nbsp;&#39;hi&#39; &#x41;</p>',
        ),
        "Tom & Jerry <b> 'hi' A",
      );
      expect(htmlToPlainText('&amp;lt;'), '&lt;');
    });

    test('leaves out scripts, styles and comments', () {
      expect(
        htmlToPlainText(
          '<style>p{color:red}</style><!-- note --><p>Hi</p><script>x()</script>',
        ),
        'Hi',
      );
    });

    test('Odoo\'s "no value" is empty', () {
      for (final none in [false, null, '', 'false', '<p><br></p>', '   ']) {
        expect(htmlToPlainText(none), '', reason: '$none');
      }
    });

    test('plain text passes through', () {
      expect(htmlToPlainText('Just text\nand more'), 'Just text\nand more');
    });
  });

  group('plainTextToHtml', () {
    test('wraps a paragraph', () {
      expect(plainTextToHtml('Pay in 30 days'), '<p>Pay in 30 days</p>');
    });

    test('blank lines separate paragraphs, single ones are line breaks', () {
      expect(
        plainTextToHtml('One\nTwo\n\nThree'),
        '<p>One<br>Two</p><p>Three</p>',
      );
      expect(plainTextToHtml('A\r\nB'), '<p>A<br>B</p>');
    });

    test('escapes what would be read as markup', () {
      expect(
        plainTextToHtml('1 < 2 & 3 > 2 <b>'),
        '<p>1 &lt; 2 &amp; 3 &gt; 2 &lt;b&gt;</p>',
      );
    });

    test('is null for nothing', () {
      expect(plainTextToHtml(''), isNull);
      expect(plainTextToHtml('  \n '), isNull);
    });

    test('what is typed comes back as typed', () {
      for (final typed in [
        'Pay in 30 days',
        'One\nTwo',
        'One\n\nTwo & <three>',
        "It's a test",
      ]) {
        expect(htmlToPlainText(plainTextToHtml(typed)), typed);
      }
    });
  });
}
