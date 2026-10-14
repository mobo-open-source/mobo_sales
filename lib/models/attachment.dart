/// Represents a file attachment linked to an Odoo record.
class Attachment {
  final int id;
  final String name;
  final String type;
  final String? url;
  final String? mimetype;
  final DateTime? createDate;
  final String? description;

  Attachment({
    required this.id,
    required this.name,
    required this.type,
    this.url,
    this.mimetype,
    this.createDate,
    this.description,
  });

  /// The path Odoo serves an attachment's file from, relative to the server.
  ///
  /// `/web/content/<id>/<name>` streams the attachment's `raw` content and is
  /// the same route on Odoo 17 to 20. The longer
  /// `/web/content/ir.attachment/<id>/datas/<name>` this used to build names
  /// the `datas` field, which Odoo 20 removed from `ir.attachment` (only `raw`
  /// remains): there it answers 404.
  static String contentUrl(Object? id, String name) =>
      '/web/content/$id/${Uri.encodeComponent(name)}';

  /// Constructs an [Attachment] from a raw Odoo JSON map, resolving the download URL.
  factory Attachment.fromJson(Map<String, dynamic> json) {
    String? attachmentUrl = json['url']?.toString();

    if (json['type'] == 'binary' &&
        (attachmentUrl == null ||
            attachmentUrl == 'false' ||
            attachmentUrl.isEmpty)) {
      final attachmentId = json['id'];
      final fileName = json['name'] ?? 'attachment';
      attachmentUrl = contentUrl(attachmentId, fileName.toString());
    }

    DateTime? parsedCreateDate;
    final createDateRaw = json['create_date'];
    if (createDateRaw != null) {
      if (createDateRaw is DateTime) {
        parsedCreateDate = createDateRaw;
      } else if (createDateRaw is String) {
        try {
          parsedCreateDate = DateTime.parse(createDateRaw);
        } catch (e) {
          parsedCreateDate = null;
        }
      }
    }

    String? normalizedDescription;
    final rawDesc = json['description'];
    if (rawDesc == null || rawDesc == false) {
      normalizedDescription = null;
    } else {
      final s = rawDesc.toString().trim();
      normalizedDescription = (s.isEmpty || s.toLowerCase() == 'false')
          ? null
          : s;
    }

    return Attachment(
      id: json['id'] as int,
      name: json['name']?.toString() ?? 'Unknown',
      type: json['type']?.toString() ?? 'binary',
      url: attachmentUrl,
      mimetype: json['mimetype']?.toString(),
      createDate: parsedCreateDate,
      description: normalizedDescription,
    );
  }

  /// Serialises this attachment to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'url': url,
      'mimetype': mimetype,
      'create_date': createDate?.toIso8601String(),
      'description': description,
    };
  }

  /// Returns the resolved download URL for this attachment, or `null` if unavailable.
  String? getDownloadUrl() {
    if (url != null && url!.isNotEmpty && url != 'false') {
      return url;
    }

    if (type == 'binary') {
      return contentUrl(id, name);
    }

    return null;
  }

  /// Whether this attachment has a resolvable download URL.
  bool get isViewable {
    final downloadUrl = getDownloadUrl();
    return downloadUrl != null && downloadUrl.isNotEmpty;
  }

  /// Whether this attachment's MIME type or file name indicates an image.
  bool get isImage {
    return mimetype?.startsWith('image/') == true ||
        name.toLowerCase().endsWith('.png') ||
        name.toLowerCase().endsWith('.jpg') ||
        name.toLowerCase().endsWith('.jpeg') ||
        name.toLowerCase().endsWith('.gif') ||
        name.toLowerCase().endsWith('.webp');
  }

  /// Whether this attachment's MIME type or file name indicates a PDF.
  bool get isPdf {
    return mimetype?.contains('pdf') == true ||
        name.toLowerCase().endsWith('.pdf');
  }

  @override
  String toString() {
    return 'Attachment(id: $id, name: $name, type: $type, url: $url, mimetype: $mimetype)';
  }
}
