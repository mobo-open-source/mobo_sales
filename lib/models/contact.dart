/// Represents a customer or partner record from Odoo's `res.partner` model.
class Contact {
  final int id;
  final String name;
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

      imageUrl: (json['image_128'] ?? json['image_1920'])?.toString(),
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
          : json['company_name']?.toString(),
      companyId:
          (json['company_id'] is List &&
              (json['company_id'] as List).isNotEmpty)
          ? json['company_id'][0] as int?
          : null,
      vat: json['vat']?.toString(),
      companyType: json['company_type']?.toString(),
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
