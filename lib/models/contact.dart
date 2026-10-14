/// Represents a customer or partner record from Odoo's `res.partner` model.
class Contact {
  final int id;
  final String name;

  /// Odoo's `complete_name`: the name as its own Customers list shows it,
  /// "Company, Contact" for a contact that belongs to a company. Only the
  /// lists read it; see [listName].
  final String? completeName;
  final String? email;
  final String? phone;
  final String? mobile;
  final String? website;
  final String? function;
  final String? street;
  final String? street2;
  final String? city;
  final String? state;
  final int? stateId;
  final String? zip;
  final String? country;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isLoading;

  final bool? isCompany;
  final String? companyName;
  final int? companyId;
  final String? vat;
  final String? companyType;
  final String? industry;
  final String? customerRank;
  final String? salesperson;
  final String? paymentTerms;
  final int? paymentTermId;
  final String? creditLimit;
  final String? currency;
  final double? totalReceivable;

  final String? title;
  final String? lang;
  final String? timezone;
  final String? comment;
  final bool? isActive;
  final String? customerType;

  final List<int>? categoryIds;

  Contact({
    required this.id,
    required this.name,
    this.completeName,
    this.email,
    this.phone,
    this.mobile,
    this.website,
    this.function,
    this.street,
    this.street2,
    this.city,
    this.state,
    this.stateId,
    this.zip,
    this.country,
    this.imageUrl,
    this.latitude,
    this.longitude,
    this.createdAt,
    this.updatedAt,
    this.isLoading = false,
    this.isCompany,
    this.companyName,
    this.companyId,
    this.vat,
    this.companyType,
    this.industry,
    this.customerRank,
    this.salesperson,
    this.paymentTerms,
    this.paymentTermId,
    this.creditLimit,
    this.currency,
    this.totalReceivable,
    this.title,
    this.lang,
    this.timezone,
    this.comment,
    this.isActive,
    this.customerType,
    this.categoryIds,
  });

  /// Creates a [Contact] from a raw Odoo JSON map, handling field type conversions and null safety.
  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] ?? 0,
      name: json['name']?.toString() ?? 'Unnamed Contact',
      completeName: json['complete_name']?.toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      mobile: json['mobile']?.toString(),
      website: json['website']?.toString(),
      function: json['function']?.toString(),
      street: json['street']?.toString(),
      street2: json['street2']?.toString(),
      city: json['city']?.toString(),
      state: json['state_id'] is List && json['state_id'].length > 1
          ? json['state_id'][1]?.toString()
          : null,
      stateId: json['state_id'] is List && json['state_id'].length > 0
          ? json['state_id'][0]
          : null,
      zip: json['zip']?.toString(),
      country: json['country_id'] is List
          ? json['country_id'][1]?.toString()
          : json['country_id']?.toString(),

      imageUrl: _imageFrom(json),
      latitude: json['partner_latitude']?.toDouble(),
      longitude: json['partner_longitude']?.toDouble(),
      createdAt: json['create_date'] != null
          ? DateTime.parse(json['create_date'])
          : null,
      updatedAt: json['write_date'] != null
          ? DateTime.parse(json['write_date'])
          : null,
      isCompany: json['is_company'] ?? false,
      companyName:
          (json['company_id'] is List &&
              (json['company_id'] as List).length > 1)
          ? json['company_id'][1]?.toString()
          : _companyNameFrom(json),
      companyId:
          (json['company_id'] is List &&
              (json['company_id'] as List).isNotEmpty)
          ? json['company_id'][0] as int?
          : null,
      vat: json['vat']?.toString(),
      companyType: _companyTypeFrom(json),
      industry: json['industry_id'] is List
          ? json['industry_id'][1]?.toString()
          : json['industry']?.toString(),
      customerRank: json['customer_rank']?.toString(),
      salesperson: json['user_id'] is List
          ? json['user_id'][1]?.toString()
          : json['salesperson']?.toString(),
      paymentTerms: json['property_payment_term_id'] is List
          ? json['property_payment_term_id'][1]?.toString()
          : json['payment_terms']?.toString(),
      paymentTermId:
          json['property_payment_term_id'] is List &&
              json['property_payment_term_id'].isNotEmpty
          ? json['property_payment_term_id'][0]
          : null,
      creditLimit: json['credit_limit']?.toString(),
      currency: json['currency_id'] is List
          ? json['currency_id'][1]?.toString()
          : json['currency']?.toString(),
      totalReceivable: (json['credit'] is num)
          ? (json['credit'] as num).toDouble()
          : (json['credit'] != null
                ? double.tryParse(json['credit'].toString())
                : (json['total_receivable'] is num)
                ? (json['total_receivable'] as num).toDouble()
                : (json['total_receivable'] != null
                      ? double.tryParse(json['total_receivable'].toString())
                      : null)),
      title: json['title'] is List && json['title'].length > 1
          ? json['title'][1]?.toString()
          : (json['title'] is String ? json['title'] : null),
      lang: json['lang']?.toString(),
      timezone: json['tz']?.toString(),
      comment: json['comment']?.toString(),
      isActive: json['active'] ?? true,
      customerType: json['type']?.toString(),
      categoryIds: (json['category_id'] is List)
          ? List<int>.from((json['category_id'] as List).whereType<int>())
          : null,
    );
  }

  /// The free-text company of a contact, from whichever field the server has.
  ///
  /// Up to Odoo 19 that is `company_name` and it is returned as written, so
  /// an unset value stays `'false'` for the callers that already test for it.
  /// Odoo 20 removed the field in favour of the `parent_id` relation (the
  /// "Company Employer"); `parent_name` is its name, and is what the customer
  /// reads ask for in place of `company_name` there. Only that key is used,
  /// not `parent_id` itself, so data that merely happens to carry the relation
  /// (other screens read it for their own reasons) is not reinterpreted.
  static String? _companyNameFrom(Map<String, dynamic> json) {
    if (json.containsKey('company_name')) {
      return json['company_name']?.toString();
    }
    final parentName = json['parent_name'];
    if (parentName is String && parentName.isNotEmpty) return parentName;
    return null;
  }

  /// The contact's picture as base64 text, whichever shape the data has.
  ///
  /// Up to Odoo 19 a binary field reads as its base64 text, or `false` when
  /// empty. Odoo 20 reads it as a dict with the base64 text under `content`
  /// (next to `size`, and `filename` when there is one). The transport already
  /// flattens those for every `call_kw` (see `odoo_binary.dart`); this stays
  /// tolerant of the dict anyway, so a contact built from data that did not go
  /// through it still gets its photo instead of the text of a map. A dict
  /// without content (the metadata-only form) is "no image"; anything else is
  /// passed on as the app always did.
  static String? _imageFrom(Map<String, dynamic> json) {
    final value = json['image_128'] ?? json['image_1920'];
    if (value is Map) {
      final content = value['content'];
      return content is String && content.isNotEmpty ? content : null;
    }
    return value?.toString();
  }

  /// `person` or `company`. Odoo 20 removed `company_type`; it was only ever
  /// `company` for a partner with `is_company` and `person` for the rest, so
  /// when the server does not send it, it is worked out from `is_company`.
  /// Unknown (null) when neither is in the data, never a guess.
  static String? _companyTypeFrom(Map<String, dynamic> json) {
    final type = json['company_type'];
    if (type is String && type.isNotEmpty) return type;
    final isCompany = json['is_company'];
    if (isCompany is bool) return isCompany ? 'company' : 'person';
    return null;
  }

  /// The name a customer list row shows: [completeName] when the server sent
  /// one ("Acme Corporation, Addison Olson"), otherwise [name]. Odoo sends
  /// `false` for an empty char, which reads here as the text `false`. Apart
  /// from [displayName], which the detail and edit screens use and which
  /// answers a different question.
  String get listName {
    final full = completeName?.trim();
    if (full == null || full.isEmpty || full.toLowerCase() == 'false') {
      return name;
    }
    return full;
  }

  /// Returns `true` if this contact has valid non-zero latitude and longitude.
  bool hasValidCoordinates() {
    return latitude != null &&
        longitude != null &&
        latitude != 0.0 &&
        longitude != 0.0;
  }

  /// Converts this contact to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'mobile': mobile,
      'website': website,
      'function': function,
      'street': street,
      'street2': street2,
      'city': city,
      'state': state,
      'state_id': stateId,
      'zip': zip,
      'country_id': country,
      'image_1920': imageUrl,
      'partner_latitude': latitude,
      'partner_longitude': longitude,
      'is_company': isCompany,
      'company_name': companyName,
      'company_id': companyId,
      'vat': vat,
      'company_type': companyType,
      'industry': industry,
      'customer_rank': customerRank,
      'salesperson': salesperson,
      'payment_terms': paymentTerms,
      'property_payment_term_id': paymentTermId,
      'credit_limit': creditLimit,
      'currency': currency,
      'total_receivable': totalReceivable,
      'title': title,
      'lang': lang,
      'tz': timezone,
      'comment': comment,
      'active': isActive,
      'type': customerType,
      'category_id': categoryIds,
    };
  }

  /// Returns a copy of this contact with the specified fields overridden.
  Contact copyWith({
    int? id,
    String? name,
    String? completeName,
    String? email,
    String? phone,
    String? mobile,
    String? website,
    String? function,
    String? street,
    String? street2,
    String? city,
    String? state,
    int? stateId,
    String? zip,
    String? country,
    String? imageUrl,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isLoading,
    bool? isCompany,
    String? companyName,
    int? companyId,
    String? vat,
    String? companyType,
    String? industry,
    String? customerRank,
    String? salesperson,
    String? paymentTerms,
    int? paymentTermId,
    String? creditLimit,
    String? currency,
    String? title,
    String? lang,
    String? timezone,
    String? comment,
    bool? isActive,
    String? customerType,
    List<int>? categoryIds,
  }) {
    return Contact(
      id: id ?? this.id,
      name: name ?? this.name,
      completeName: completeName ?? this.completeName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      mobile: mobile ?? this.mobile,
      website: website ?? this.website,
      function: function ?? this.function,
      street: street ?? this.street,
      street2: street2 ?? this.street2,
      city: city ?? this.city,
      state: state ?? this.state,
      stateId: stateId ?? this.stateId,
      zip: zip ?? this.zip,
      country: country ?? this.country,
      imageUrl: imageUrl ?? this.imageUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isLoading: isLoading ?? this.isLoading,
      isCompany: isCompany ?? this.isCompany,
      companyName: companyName ?? this.companyName,
      companyId: companyId ?? this.companyId,
      vat: vat ?? this.vat,
      companyType: companyType ?? this.companyType,
      industry: industry ?? this.industry,
      customerRank: customerRank ?? this.customerRank,
      salesperson: salesperson ?? this.salesperson,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      paymentTermId: paymentTermId ?? this.paymentTermId,
      creditLimit: creditLimit ?? this.creditLimit,
      currency: currency ?? this.currency,
      title: title ?? this.title,
      lang: lang ?? this.lang,
      timezone: timezone ?? this.timezone,
      comment: comment ?? this.comment,
      isActive: isActive ?? this.isActive,
      customerType: customerType ?? this.customerType,
      categoryIds: categoryIds ?? this.categoryIds,
    );
  }

  /// Returns a formatted multi-part address string.
  String get fullAddress {
    final parts = [
      street,
      street2,
      city,
      state,
      zip,
      country,
    ].where((part) => part != null && part.isNotEmpty).toList();
    return parts.join(', ');
  }

  /// Returns the most appropriate display name for this contact.
  String get displayName {
    if ((isCompany ?? false) &&
        companyName != null &&
        companyName!.isNotEmpty &&
        companyName != 'false') {
      return companyName!;
    }

    if (name.isNotEmpty && name != 'false') {
      return name;
    }

    return 'Unnamed Contact';
  }

  /// Returns a combined string of available phone, mobile, and email details.
  String get contactInfo {
    final parts = [
      if (phone != null && phone!.isNotEmpty) 'Phone: $phone',
      if (mobile != null && mobile!.isNotEmpty) 'Mobile: $mobile',
      if (email != null && email!.isNotEmpty) 'Email: $email',
    ];
    return parts.join(' • ');
  }

  /// Whether this contact has GPS coordinates.
  bool get hasLocation => latitude != null && longitude != null;

  /// Whether this contact has at least one phone, mobile, or email value.
  bool get hasContactInfo =>
      (phone != null && phone!.isNotEmpty) ||
      (mobile != null && mobile!.isNotEmpty) ||
      (email != null && email!.isNotEmpty);

  bool get hasRealAddress {
    bool isEmptyOrFalse(String? value) =>
        value == null ||
        value.trim().isEmpty ||
        value.trim().toLowerCase() == 'false';
    return !isEmptyOrFalse(street) ||
        !isEmptyOrFalse(city) ||
        !isEmptyOrFalse(zip);
  }
}
