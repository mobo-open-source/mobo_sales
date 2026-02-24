/// Represents a product template from Odoo's `product.template` model.
class Product {
  final String id;
  final String name;
  final double listPrice;
  final double qtyAvailable;
  final String? imageUrl;
  final String defaultCode;
  final String? barcode;
  final dynamic categId;
  final String? category;
  final int? templateId;
  final DateTime? creationDate;
  final String? description;
  final double? weight;
  final double? volume;
  final String? dimensions;
  final double? cost;
  final int variantCount;
  final List<ProductAttribute>? attributes;
  late final List<dynamic>? taxesIds;
  final List<dynamic>? sellerIds;
  final int? leadTime;
  final dynamic propertyStockInventory;
  final dynamic propertyStockProduction;
  final String? procurementRoute;
  final String? costMethod;
  final double? standardPrice;
  final String? propertyAccountIncome;
  final String? propertyAccountExpense;
  final Map<String, String>? selectedVariants;
  final double? quantity;
  final List<int> productTemplateAttributeValueIds;
  Tax? selectedTax;
  final int? taxId;
  final List<dynamic>? currencyId;
  final dynamic uomId;
  Map<String, dynamic>? extraData;
  final bool? active;
  final DateTime? writeDate;
  final bool? saleOk;
  final bool? purchaseOk;
  final List<int>? productVariantIds;

  Product({
    required this.id,
    required this.name,
    required this.listPrice,
    required this.qtyAvailable,
    required this.variantCount,
    required this.defaultCode,
    this.imageUrl,
    this.barcode,
    this.categId,
    this.category,
    this.templateId,
    this.creationDate,
    this.description,
    this.weight,
    this.volume,
    this.dimensions,
    this.cost,
    this.attributes,
    this.taxesIds,
    this.sellerIds,
    this.leadTime,
    this.propertyStockInventory,
    this.propertyStockProduction,
    this.procurementRoute,
    this.costMethod,
    this.standardPrice,
    this.propertyAccountIncome,
    this.propertyAccountExpense,
    this.selectedVariants,
    this.quantity,
    this.productTemplateAttributeValueIds = const [],
    this.selectedTax,
    this.taxId,
    this.currencyId,
    this.uomId,
    this.extraData,
    this.active,
    this.writeDate,
    this.saleOk,
    this.purchaseOk,
    this.productVariantIds,
  });

  /// Constructs a [Product] from a raw Odoo JSON map, handling image and variant data.
  factory Product.fromJson(Map<String, dynamic> json) {
    String? imageUrl;
    if (json['image_128'] is String &&
        (json['image_128'] as String).isNotEmpty) {
      imageUrl = 'data:image/png;base64,${json['image_128']}';
    } else if (json['image_1920'] is String &&
        (json['image_1920'] as String).isNotEmpty) {
      imageUrl = 'data:image/png;base64,${json['image_1920']}';
    } else {
      imageUrl = null;
    }
    return Product(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? 'Unknown',
      listPrice: (json['list_price'] as num?)?.toDouble() ?? 0.0,
      qtyAvailable: (json['qty_available'] as num?)?.toDouble() ?? 0.0,
      variantCount: json['product_variant_count'] as int? ?? 0,
      defaultCode:
          json['default_code'] is String &&
              json['default_code'].toString().toLowerCase() != 'false'
          ? json['default_code']
          : '',
      imageUrl: imageUrl,
      barcode: json['barcode'] is String ? json['barcode'] : null,
      categId: json['categ_id'],
      category:
          json['categ_id'] is List &&
              json['categ_id'].length == 2 &&
              json['categ_id'][1] is String
          ? json['categ_id'][1]
          : null,
      templateId:
          json['product_tmpl_id'] is List &&
              (json['product_tmpl_id'] as List).isNotEmpty &&
              (json['product_tmpl_id'][0] is int)
          ? json['product_tmpl_id'][0] as int
          : int.tryParse(json['id'].toString()),
      creationDate: json['create_date'] is String
          ? DateTime.tryParse(json['create_date'])
          : null,
      description: json['description_sale'] is String
          ? json['description_sale']
          : null,
      weight: (json['weight'] as num?)?.toDouble(),
      volume: (json['volume'] as num?)?.toDouble(),
      dimensions: json['dimensions']?.toString(),
      cost: (json['standard_price'] as num?)?.toDouble(),
      attributes: json['attributes'] != null
          ? (json['attributes'] as List)
                .map((attr) => ProductAttribute.fromJson(attr))
                .toList()
          : null,
      taxesIds: json['taxes_id'] as List<dynamic>?,
      sellerIds: json['seller_ids'] as List<dynamic>?,
      leadTime: json['lead_time'] as int?,
      propertyStockInventory: json['property_stock_inventory'],
      propertyStockProduction: json['property_stock_production'],
      procurementRoute: json['procurement_route']?.toString(),
      costMethod: json['cost_method']?.toString(),
      standardPrice: (json['standard_price'] as num?)?.toDouble(),
      propertyAccountIncome: json['property_account_income']?.toString(),
      propertyAccountExpense: json['property_account_expense']?.toString(),
      selectedVariants: json['selected_variants'] != null
          ? Map<String, String>.from(json['selected_variants'])
          : null,
      quantity: (json['quantity'] as num?)?.toDouble(),
      productTemplateAttributeValueIds: List<int>.from(
        json['product_template_attribute_value_ids'] ?? [],
      ),
      selectedTax: json['selected_tax'] != null
          ? Tax(
              id: json['selected_tax']['id'] as int,
              name: json['selected_tax']['name']?.toString() ?? 'Unknown Tax',
              amount:
                  (json['selected_tax']['amount'] as num?)?.toDouble() ?? 0.0,
              amountType:
                  json['selected_tax']['amount_type']?.toString() ?? 'percent',
            )
          : null,
      taxId: json['tax_id'] as int?,
      currencyId: json['currency_id'] as List<dynamic>?,
      uomId: json['uom_id'],
      extraData: {},
      active: json['active'] is bool ? json['active'] : null,
      writeDate: json['write_date'] is String
          ? DateTime.tryParse(json['write_date'])
          : null,
      saleOk: json['sale_ok'] is bool ? json['sale_ok'] : null,
      purchaseOk: json['purchase_ok'] is bool ? json['purchase_ok'] : null,
      productVariantIds: json['product_variant_ids'] is List
          ? (json['product_variant_ids'] as List).cast<int>().toList()
          : null,
    );
  }

  /// Serialises this product to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'list_price': listPrice,
      'qty_available': qtyAvailable,
      'product_variant_count': variantCount,
      'default_code': defaultCode,
      'image_128': imageUrl,
      'barcode': barcode,
      'categ_id': categId,
      'category': category,
      'product_tmpl_id': templateId,
      'create_date': creationDate?.toIso8601String(),
      'description_sale': description,
      'weight': weight,
      'volume': volume,
      'dimensions': dimensions,
      'standard_price': cost,
      'attributes': attributes?.map((attr) => attr.toJson()).toList(),
      'taxes_id': taxesIds,
      'seller_ids': sellerIds,
      'lead_time': leadTime,
      'property_stock_inventory': propertyStockInventory,
      'property_stock_production': propertyStockProduction,
      'procurement_route': procurementRoute,
      'cost_method': costMethod,
      'standard_price': standardPrice,
      'property_account_income': propertyAccountIncome,
      'property_account_expense': propertyAccountExpense,
      'selected_variants': selectedVariants,
      'quantity': quantity,
      'product_template_attribute_value_ids': productTemplateAttributeValueIds,
      'selected_tax': selectedTax != null
          ? {
              'id': selectedTax!.id,
              'name': selectedTax!.name,
              'amount': selectedTax!.amount,
              'amount_type': selectedTax!.amountType,
            }
          : null,
      'tax_id': taxId,
      'currency_id': currencyId,
      'uom_id': uomId,
      'extraData': extraData,
      'active': active,
      'write_date': writeDate?.toIso8601String(),
      'sale_ok': saleOk,
      'purchase_ok': purchaseOk,
      'product_variant_ids': productVariantIds,
    };
  }

  /// Returns the resolved category name string.
  String get categoryValue {
    if (category != null) {
      return category!;
    }
    if (categId is List && categId.length == 2 && categId[1] is String) {
      return categId[1];
    }
    return 'Uncategorized';
  }

  /// Returns `true` if this product's name or internal reference matches [query].
  bool filter(String query) {
    final lowercaseQuery = query.toLowerCase();
    return name.toLowerCase().contains(lowercaseQuery) ||
        (defaultCode.isNotEmpty &&
            defaultCode.toLowerCase().contains(lowercaseQuery));
  }

  @override
  String toString() => name;

  bool get isActive => true;

  /// Whether this product has stock available.
  bool get isInStock => qtyAvailable > 0;

  /// Whether this product's stock is low (1–10 units).
  bool get isLowStock => qtyAvailable > 0 && qtyAvailable <= 10;

  /// Returns a human-readable stock status string.
  String get stockStatus {
    if (qtyAvailable <= 0) return 'Out of Stock';
    if (qtyAvailable <= 10) return 'Low Stock';
    return 'In Stock';
  }

  /// Returns the SKU (internal reference), or `null` if not set.
  String? get sku => defaultCode.isNotEmpty ? defaultCode : null;

  /// Returns a copy of this product with the specified fields overridden.
  Product copyWith({
    String? id,
    String? name,
    double? listPrice,
    double? qtyAvailable,
    int? variantCount,
    String? defaultCode,
    String? imageUrl,
    String? barcode,
    dynamic categId,
    String? category,
    int? templateId,
    DateTime? creationDate,
    String? description,
    double? weight,
    double? volume,
    String? dimensions,
    double? cost,
    List<ProductAttribute>? attributes,
    List<dynamic>? taxesIds,
    List<dynamic>? sellerIds,
    int? leadTime,
    dynamic propertyStockInventory,
    dynamic propertyStockProduction,
    String? procurementRoute,
    String? costMethod,
    double? standardPrice,
    String? propertyAccountIncome,
    String? propertyAccountExpense,
    Map<String, String>? selectedVariants,
    double? quantity,
    List<int>? productTemplateAttributeValueIds,
    Tax? selectedTax,
    int? taxId,
    List<dynamic>? currencyId,
    dynamic uomId,
    Map<String, dynamic>? extraData,
    bool? active,
    DateTime? writeDate,
    bool? saleOk,
    bool? purchaseOk,
    List<int>? productVariantIds,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      listPrice: listPrice ?? this.listPrice,
      qtyAvailable: qtyAvailable ?? this.qtyAvailable,
      variantCount: variantCount ?? this.variantCount,
      defaultCode: defaultCode ?? this.defaultCode,
      imageUrl: imageUrl ?? this.imageUrl,
      barcode: barcode ?? this.barcode,
      categId: categId ?? this.categId,
      category: category ?? this.category,
      templateId: templateId ?? this.templateId,
      creationDate: creationDate ?? this.creationDate,
      description: description ?? this.description,
      weight: weight ?? this.weight,
      volume: volume ?? this.volume,
      dimensions: dimensions ?? this.dimensions,
      cost: cost ?? this.cost,
      attributes: attributes ?? this.attributes,
      taxesIds: taxesIds ?? this.taxesIds,
      sellerIds: sellerIds ?? this.sellerIds,
      leadTime: leadTime ?? this.leadTime,
      propertyStockInventory:
          propertyStockInventory ?? this.propertyStockInventory,
      propertyStockProduction:
          propertyStockProduction ?? this.propertyStockProduction,
      procurementRoute: procurementRoute ?? this.procurementRoute,
      costMethod: costMethod ?? this.costMethod,
      standardPrice: standardPrice ?? this.standardPrice,
      propertyAccountIncome:
          propertyAccountIncome ?? this.propertyAccountIncome,
      propertyAccountExpense:
          propertyAccountExpense ?? this.propertyAccountExpense,
      selectedVariants: selectedVariants ?? this.selectedVariants,
      quantity: quantity ?? this.quantity,
      productTemplateAttributeValueIds:
          productTemplateAttributeValueIds ??
          this.productTemplateAttributeValueIds,
      selectedTax: selectedTax ?? this.selectedTax,
      taxId: taxId ?? this.taxId,
      currencyId: currencyId ?? this.currencyId,
      uomId: uomId ?? this.uomId,
      extraData: extraData ?? this.extraData,
      active: active ?? this.active,
      writeDate: writeDate ?? this.writeDate,
      saleOk: saleOk ?? this.saleOk,
      purchaseOk: purchaseOk ?? this.purchaseOk,
      productVariantIds: productVariantIds ?? this.productVariantIds,
    );
  }
}

/// Represents a product attribute (e.g. Color, Size) with its possible values.
class ProductAttribute {
  final String name;
  final List<String> values;
  final Map<String, double>? extraCost;

  ProductAttribute({required this.name, required this.values, this.extraCost});

  /// Constructs a [ProductAttribute] from a raw Odoo JSON map.
  factory ProductAttribute.fromJson(Map<String, dynamic> json) {
    return ProductAttribute(
      name: json['name']?.toString() ?? 'Unknown',
      values: (json['values'] as List<dynamic>?)?.cast<String>() ?? [],
      extraCost: json['extra_cost'] != null
          ? Map<String, double>.from(json['extra_cost'])
          : null,
    );
  }

  /// Serialises this attribute to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {'name': name, 'values': values, 'extra_cost': extraCost};
  }
}

/// Represents a tax record associated with a product.
class Tax {
  final int id;
  final String name;
  final double amount;
  final String amountType;

  Tax({
    required this.id,
    required this.name,
    required this.amount,
    required this.amountType,
  });

  @override
  String toString() {
    if (amountType == 'percent') {
      return name.contains('%')
          ? name
          : (name.isNotEmpty
                ? '$name ${amount.toStringAsFixed(0)}%'
                : '${amount.toStringAsFixed(0)}%');
    } else {
      return name.isNotEmpty
          ? '$name ${amount.toStringAsFixed(2)}'
          : amount.toStringAsFixed(2);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tax && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
