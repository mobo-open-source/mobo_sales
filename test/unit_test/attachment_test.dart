import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/models/attachment.dart';

void main() {
  // Odoo 20 dropped ir.attachment.datas (odoo/addons/base/models/
  // ir_attachment.py keeps only `raw` and `db_datas`), so
  // /web/content/ir.attachment/<id>/datas/<name> now answers 404
  // (ir.binary._get_stream_from: "Record has no field 'datas'"). The route
  // /web/content/<int:id>/<string:filename> exists, with `raw` as its default
  // field, in Odoo 17, 18, 19 and 20.
  group('Attachment download URL', () {
    test('a binary attachment is served from /web/content/<id>/<name>', () {
      final attachment = Attachment.fromJson({
        'id': 7,
        'name': 'Terms & Conditions.pdf',
        'type': 'binary',
        'url': false,
        'mimetype': 'application/pdf',
      });

      expect(attachment.url, '/web/content/7/Terms%20%26%20Conditions.pdf');
      expect(attachment.getDownloadUrl(), attachment.url);
      expect(attachment.url, isNot(contains('datas')));
      expect(attachment.url, isNot(contains('ir.attachment')));
    });

    test('the url Odoo stores on the record wins', () {
      final attachment = Attachment.fromJson({
        'id': 8,
        'name': 'Brochure',
        'type': 'url',
        'url': 'https://example.com/brochure.pdf',
      });

      expect(attachment.url, 'https://example.com/brochure.pdf');
      expect(attachment.getDownloadUrl(), 'https://example.com/brochure.pdf');
    });

    test('an attachment rebuilt without a url still resolves one', () {
      final attachment = Attachment(id: 9, name: 'photo.png', type: 'binary');

      expect(attachment.getDownloadUrl(), '/web/content/9/photo.png');
      expect(attachment.isViewable, isTrue);
    });

    test('a url-type attachment with no url has nothing to download', () {
      final attachment = Attachment(id: 10, name: 'link', type: 'url');

      expect(attachment.getDownloadUrl(), isNull);
      expect(attachment.isViewable, isFalse);
    });
  });
}
