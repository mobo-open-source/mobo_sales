/// Prunes invalid Odoo fields from API requests to handle version differences.
class FieldValidationService {
  static final Map<String, Set<String>> _invalidFields = {};
  static final Map<String, List<String>> _safeFieldSets = {
    'product.template': [
      'id',
      'name',
      'list_price',
      'product_variant_count',
      'default_code',
      'image_128',
      'image_1920',
      'barcode',
      'categ_id',
      'create_date',
      'description_sale',
      'weight',
      'volume',
      'standard_price',
      'active',
      'write_date',
    ],
    'product.product': [
      'id',
      'name',
      'list_price',
      'default_code',
      'categ_id',
      'product_variant_count',
      'type',
      'image_128',
      'image_1920',
      'product_template_attribute_value_ids',
      'product_tmpl_id',
      'create_date',
      'write_date',
      'active',
      'qty_available',
    ],
    'sale.order': [
      'id',
      'name',
      'partner_id',
      'date_order',
      'state',
      'amount_total',
      'currency_id',
      'user_id',
      'company_id',
    ],
  };

  /// Returns validated fields for [model], filtering out known invalid ones.
  static List<String> getValidatedFields(
    String model, {
    List<String>? requestedFields,
  }) {
    final safeFields = _safeFieldSets[model] ?? ['id', 'name'];
    final invalidFieldsForModel = _invalidFields[model] ?? <String>{};

    if (requestedFields != null) {
      return requestedFields
          .where((field) => !invalidFieldsForModel.contains(field))
          .toList();
    }

    return safeFields
        .where((field) => !invalidFieldsForModel.contains(field))
        .toList();
  }

  /// Marks [field] as invalid for [model] so it is excluded from future requests.
  static void markFieldAsInvalid(String model, String field) {
    _invalidFields.putIfAbsent(model, () => <String>{});
    _invalidFields[model]!.add(field);
  }

  /// Extracts the offending field name from an Odoo [errorMessage], if possible.
  static String? extractInvalidField(String errorMessage) {
    final patterns = [
      RegExp(r"Invalid field '([^']+)'"),
      RegExp(r'Field "([^"]+)" does not exist'),
      RegExp(r'Unknown field: ([^\s,]+)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(errorMessage);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  /// Returns `true` if [errorMessage] indicates an Odoo field validation failure.
  static bool isFieldValidationError(String errorMessage) {
    return errorMessage.contains('builtins.ValueError') ||
        errorMessage.contains('Invalid field') ||
        errorMessage.contains('Field') &&
            errorMessage.contains('does not exist') ||
        errorMessage.contains('Unknown field') ||
        errorMessage.contains('Odoo Server Error');
  }

  /// Handles a field error by removing the problematic field and returning the updated list.
  static List<String> handleFieldError(
    String model,
    String errorMessage,
    List<String> currentFields,
  ) {
    final invalidField = extractInvalidField(errorMessage);

    if (invalidField != null) {
      markFieldAsInvalid(model, invalidField);
      return currentFields.where((field) => field != invalidField).toList();
    }

    final problematicFields = _getProblematicFieldsForModel(model);
    String? removedField;

    for (final field in problematicFields) {
      if (currentFields.contains(field) &&
          !(_invalidFields[model]?.contains(field) ?? false)) {
        markFieldAsInvalid(model, field);
        removedField = field;
        break;
      }
    }

    if (removedField != null) {
      return currentFields.where((field) => field != removedField).toList();
    }

    return _getMinimalFields(model);
  }

  static List<String> _getProblematicFieldsForModel(String model) {
    switch (model) {
      case 'product.template':
        return [
          'qty_available',
          'property_stock_inventory',
          'property_stock_production',
          'cost_method',
          'taxes_id',
          'currency_id',
          'uom_id',
          'seller_ids',
          'procurement_route',
          'lead_time',
          'dimensions',
          'property_account_income',
          'property_account_expense',
        ];
      case 'product.product':
        return [
          'property_stock_inventory',
          'property_stock_production',
          'cost_method',
          'procurement_route',
          'lead_time',
          'dimensions',
        ];
      case 'sale.order':
        return ['invoice_status', 'delivery_status', 'validity_date'];
      case 'res.partner':
        return [
          'partner_latitude',
          'partner_longitude',
          'website',
          'function',
          'title',
        ];
      case 'account.move':
        return [
          'invoice_payment_state',
          'activity_ids',
          'narration',
          'reversed_entry_id',
        ];
      default:
        return ['currency_id', 'company_id', 'user_id'];
    }
  }

  static List<String> _getMinimalFields(String model) {
    switch (model) {
      case 'product.template':
      case 'product.product':
        return ['id', 'name', 'list_price'];
      case 'sale.order':
        return ['id', 'name', 'partner_id', 'state'];
      case 'res.partner':
        return ['id', 'name'];
      case 'account.move':
        return ['id', 'name', 'state', 'payment_state', 'amount_total'];
      default:
        return ['id', 'name'];
    }
  }

  /// Executes [apiCall] for [model], retrying with pruned fields on validation errors.
  static Future<T> executeWithFieldValidation<T>({
    required String model,
    required Future<T> Function(List<String> fields) apiCall,
    List<String>? initialFields,
    int maxRetries = 3,
  }) async {
    int retryCount = 0;
    List<String> fields = initialFields ?? getValidatedFields(model);

    while (retryCount < maxRetries) {
      try {
        return await apiCall(fields);
      } catch (e) {
        if (isFieldValidationError(e.toString())) {
          final bool isGeneric =
              e.toString().contains('Odoo Server Error') &&
              !e.toString().contains('Invalid field') &&
              !e.toString().contains('Unknown field');

          if (isGeneric) {
            try {
              await apiCall(_getMinimalFields(model));
            } catch (minimalError) {
              rethrow;
            }
          }

          fields = await _handleFieldDiscoveryDetailed(
            model,
            e.toString(),
            fields,
          );

          if (fields.isEmpty || !fields.contains('id')) {
            fields = _getMinimalFields(model);
          }

          retryCount++;
          continue;
        }

        rethrow;
      }
    }

    throw Exception(
      'Failed to execute API call for model "$model" after $maxRetries attempts',
    );
  }

  static Future<List<String>> _handleFieldDiscoveryDetailed(
    String model,
    String errorMessage,
    List<String> currentFields,
  ) async {
    final invalidField = extractInvalidField(errorMessage);
    if (invalidField != null) {
      markFieldAsInvalid(model, invalidField);
      return currentFields.where((field) => field != invalidField).toList();
    }

    final problematicFields = _getProblematicFieldsForModel(model);
    List<String> updatedFields = List<String>.from(currentFields);
    bool changed = false;

    for (final field in problematicFields) {
      if (updatedFields.contains(field)) {
        markFieldAsInvalid(model, field);
        updatedFields.remove(field);
        changed = true;

        break;
      }
    }

    if (!changed) {
      return _getMinimalFields(model);
    }

    return updatedFields;
  }

  /// Clears the invalid fields cache, optionally scoped to a single [model].
  static void clearInvalidFieldsCache([String? model]) {
    if (model != null) {
      _invalidFields.remove(model);
    } else {
      _invalidFields.clear();
    }
  }

  /// Returns an unmodifiable copy of the current invalid fields cache.
  static Map<String, Set<String>> getInvalidFieldsCache() {
    return Map.unmodifiable(_invalidFields);
  }
}
