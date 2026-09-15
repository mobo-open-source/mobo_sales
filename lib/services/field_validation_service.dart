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
  ///
  /// Handles both shapes Odoo emits: the quoted form used when reading a field
  /// list (`Invalid field 'foo' on model 'res.partner'`) and the dotted form
  /// used for domain leaves (`Invalid field res.partner.foo in leaf ...`).
  static String? extractInvalidField(String errorMessage) {
    final patterns = [
      RegExp(r"Invalid field '([^']+)'"),
      RegExp(r'Invalid field "([^"]+)"'),
      RegExp(r'Invalid field\s+[\w.]+\.(\w+)'),
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

  /// Extracts the fields named by an Odoo field-level access error.
  ///
  /// Odoo 17/18 emit a comma-separated list (`access the fields "a,b"`) while
  /// Odoo 19 names a single field (`access the field "a"`). These fields exist
  /// but are restricted to a group the user is not in, so they are pruned and
  /// remembered rather than being allowed to fail the whole request.
  static List<String> extractInaccessibleFields(String errorMessage) {
    final match = RegExp(
      r'rights to access the fields?\s+"([^"]+)"',
    ).firstMatch(errorMessage);
    if (match == null) return const [];
    return match
        .group(1)!
        .split(',')
        .map((field) => field.trim())
        .where((field) => field.isNotEmpty)
        .toList();
  }

  /// Returns `true` if [errorMessage] names a field the server rejected.
  ///
  /// Deliberately narrow: a generic `Odoo Server Error` is not treated as a
  /// field problem, because retrying it with a pruned field list cannot fix it
  /// and only replaces the real cause with a misleading message.
  static bool isFieldValidationError(String errorMessage) {
    return errorMessage.contains('Invalid field') ||
        errorMessage.contains('Unknown field') ||
        (errorMessage.contains('Field') &&
            errorMessage.contains('does not exist'));
  }

  /// Returns `true` if [errorMessage] is about a field used in a *domain*
  /// rather than in the requested field list.
  ///
  /// Pruning the field list cannot resolve these, so they must surface to the
  /// caller instead of being retried.
  static bool isDomainFieldError(String errorMessage) {
    return errorMessage.contains('in leaf') ||
        errorMessage.contains('in domain term') ||
        RegExp(r'Invalid field\s+[\w.]+\.\w+').hasMatch(errorMessage);
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
        return ['partner_latitude', 'partner_longitude'];
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
    Object lastError = Exception('No attempt was made for model "$model"');
    bool triedMinimalFields = false;

    while (retryCount < maxRetries) {
      try {
        return await apiCall(fields);
      } catch (e) {
        lastError = e;
        final message = e.toString();

        if (isDomainFieldError(message)) {
          rethrow;
        }

        final inaccessible = extractInaccessibleFields(message);
        if (inaccessible.isNotEmpty) {
          final remaining = fields
              .where((field) => !inaccessible.contains(field))
              .toList();
          if (_sameFields(fields, remaining) || remaining.isEmpty) {
            rethrow;
          }
          for (final field in inaccessible) {
            markFieldAsInvalid(model, field);
          }
          fields = remaining;
          retryCount++;
          continue;
        }

        if (!isFieldValidationError(message)) {
          if (!_isGenericServerError(message) || triedMinimalFields) {
            rethrow;
          }
          triedMinimalFields = true;
          fields = _getMinimalFields(model);
          retryCount++;
          continue;
        }

        final nextFields = await _handleFieldDiscoveryDetailed(
          model,
          message,
          fields,
        );

        if (_sameFields(fields, nextFields)) {
          rethrow;
        }

        fields = nextFields;
        if (fields.isEmpty || !fields.contains('id')) {
          fields = _getMinimalFields(model);
        }

        retryCount++;
      }
    }

    throw lastError;
  }

  /// Returns `true` for a server error Odoo did not attribute to a field.
  ///
  /// These get one retry with the minimal field set, in case an unrecognised
  /// field in the request is at fault; the original error is preserved if that
  /// retry also fails.
  static bool _isGenericServerError(String errorMessage) {
    return errorMessage.contains('Odoo Server Error') ||
        errorMessage.contains('builtins.ValueError');
  }

  static bool _sameFields(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
