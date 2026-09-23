import 'odoo_session_manager.dart';
import 'field_validation_service.dart';

/// Fetches detailed invoice data from Odoo's `account.move` model.
class InvoiceDetailsService {
  /// Fetches full details for the invoice with [invoiceId].
  Future<Map<String, dynamic>> fetchInvoiceDetails(int invoiceId) async {
    final invoiceResult =
        await FieldValidationService.executeWithFieldValidation<List<dynamic>>(
          model: 'account.move',
          initialFields: [
            'name',
            'state',
            'partner_id',
            'ref',
            'invoice_origin',
            'user_id',
            'invoice_payment_term_id',
            'company_id',
            'invoice_date',
            'invoice_date_due',
            'amount_total',
            'amount_untaxed',
            'amount_tax',
            'amount_residual',
            'currency_id',
            'invoice_line_ids',
            'create_date',
            'write_date',
            'payment_state',
            'move_type',
          ],
          apiCall: (currentFields) async {
            final res = await OdooSessionManager.safeCallKw({
              'model': 'account.move',
              'method': 'search_read',
              'args': [
                [
                  ['id', '=', invoiceId],
                ],
                currentFields,
              ],
              'kwargs': {},
            });
            return (res as List).cast<dynamic>();
          },
        );

    if (invoiceResult.isNotEmpty) {
      final invoiceData = Map<String, dynamic>.from(invoiceResult[0]);
      return invoiceData;
    }
    return {};
  }

  /// Fetches contact details for the partner with [partnerId].
  Future<Map<String, dynamic>> fetchPartnerDetails(int partnerId) async {
    final partnerResult = await OdooSessionManager.safeCallKw({
      'model': 'res.partner',
      'method': 'search_read',
      'args': [
        [
          ['id', '=', partnerId],
        ],
        ['email', 'phone', 'street', 'city', 'zip', 'country_id'],
      ],
      'kwargs': {},
    });

    if (partnerResult.isNotEmpty) {
      return Map<String, dynamic>.from(partnerResult[0]);
    }
    return {};
  }

  /// Fetches the `account.move.line` records for the given [lineIds].
  Future<List<Map<String, dynamic>>> fetchInvoiceLines(
    List<int> lineIds,
  ) async {
    final lines = await OdooSessionManager.safeCallKw({
      'model': 'account.move.line',
      'method': 'search_read',
      'args': [
        [
          ['id', 'in', lineIds],
        ],
        [
          'name',
          'quantity',
          'price_unit',
          'price_subtotal',
          'price_total',
          'discount',
          'tax_ids',
          'product_id',
          'currency_id',
          'product_uom_id',
        ],
      ],
      'kwargs': {},
    });

    return (lines as List).map((l) => Map<String, dynamic>.from(l)).toList();
  }

  /// Fetches the product name for the given [productId].
  Future<Map<String, dynamic>> fetchProductDetails(int productId) async {
    final productResult = await OdooSessionManager.safeCallKw({
      'model': 'product.product',
      'method': 'search_read',
      'args': [
        [
          ['id', '=', productId],
        ],
        ['name'],
      ],
      'kwargs': {},
    });

    if (productResult.isNotEmpty) {
      return Map<String, dynamic>.from(productResult[0]);
    }
    return {};
  }

  /// Fetches tax records for the given [taxIds].
  Future<List<Map<String, dynamic>>> fetchTaxDetails(List<int> taxIds) async {
    final taxResult = await OdooSessionManager.safeCallKw({
      'model': 'account.tax',
      'method': 'search_read',
      'args': [
        [
          ['id', 'in', taxIds],
        ],
        ['name', 'amount', 'amount_type', 'type_tax_use'],
      ],
      'kwargs': {},
    });

    return (taxResult as List)
        .map((t) => Map<String, dynamic>.from(t))
        .toList();
  }

  /// Posts (confirms) the invoice with [invoiceId] in Odoo.
  Future<void> postInvoice(int invoiceId) async {
    await OdooSessionManager.safeCallKw({
      'model': 'account.move',
      'method': 'action_post',
      'args': [
        [invoiceId],
      ],
      'kwargs': {},
    });
  }

  /// Resets the invoice with [invoiceId] back to draft state.
  ///
  /// `button_draft` is the method on every supported release. The
  /// `action_draft` retry exists only for a server that does not define it,
  /// so any other failure is rethrown rather than retried: Odoo refuses this
  /// for real reasons — a reconciled payment, a posted entry lock date,
  /// missing rights — and swallowing that to call a second method replaced
  /// the actual explanation with an unrelated one, leaving the user with an
  /// error that named a method they had never heard of.
  Future<void> resetToDraft(int invoiceId) async {
    try {
      await OdooSessionManager.safeCallKw({
        'model': 'account.move',
        'method': 'button_draft',
        'args': [
          [invoiceId],
        ],
        'kwargs': {},
      });
    } catch (e) {
      if (!_isMissingMethodError(e)) rethrow;
      await OdooSessionManager.safeCallKw({
        'model': 'account.move',
        'method': 'action_draft',
        'args': [
          [invoiceId],
        ],
        'kwargs': {},
      });
    }
  }

  /// Whether [error] means the server does not define the method at all.
  static bool _isMissingMethodError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('has no attribute') ||
        message.contains('object has no method') ||
        message.contains('is not a valid action') ||
        message.contains('attributeerror');
  }

  /// Cancels the invoice with [invoiceId].
  Future<void> cancelInvoice(int invoiceId) async {
    try {
      await OdooSessionManager.safeCallKw({
        'model': 'account.move',
        'method': 'action_cancel',
        'args': [
          [invoiceId],
        ],
        'kwargs': {},
      });
    } catch (e) {
      await OdooSessionManager.safeCallKw({
        'model': 'account.move',
        'method': 'button_cancel',
        'args': [
          [invoiceId],
        ],
        'kwargs': {},
      });
    }
  }

  /// Permanently deletes the invoice with [invoiceId].
  Future<void> deleteInvoice(int invoiceId) async {
    await OdooSessionManager.safeCallKw({
      'model': 'account.move',
      'method': 'unlink',
      'args': [
        [invoiceId],
      ],
      'kwargs': {},
    });
  }
}
