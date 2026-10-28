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
            // The badge reads "Sent" once the invoice was emailed; a server
            // without the field has it dropped and read again.
            'is_move_sent',
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
  ///
  /// Returns null when the invoice is posted, or the name of the step Odoo
  /// stopped at when it is not.
  ///
  /// `action_post` does not always post. It returns a window action instead
  /// when Odoo wants something confirmed first — the abnormal-amount wizard,
  /// and from Odoo 20 a future-dated or hash-restricted entry — and some of
  /// the actions it returns (an autoprint job, a report) come *after* a
  /// successful post. The shape of the action cannot tell those apart, so the
  /// invoice's own state decides.
  Future<String?> postInvoice(int invoiceId) async {
    final result = await OdooSessionManager.safeCallKw({
      'model': 'account.move',
      'method': 'action_post',
      'args': [
        [invoiceId],
      ],
      'kwargs': {},
    });

    if (result == true || result == null || result == false) return null;

    final state = await readInvoiceState(invoiceId);
    if (state == 'posted') return null;

    final name = result is Map ? result['name']?.toString() : null;
    return (name != null && name.isNotEmpty) ? name : 'another confirmation';
  }

  /// The `state` of the invoice with [invoiceId], or null when it cannot be
  /// read.
  Future<String?> readInvoiceState(int invoiceId) async {
    try {
      final rows = await OdooSessionManager.safeCallKw({
        'model': 'account.move',
        'method': 'read',
        'args': [
          [invoiceId],
          ['state'],
        ],
        'kwargs': {},
      });
      if (rows is List && rows.isNotEmpty) {
        return rows.first['state']?.toString();
      }
    } catch (_) {
      // The post is what matters; an unreadable state falls back to the
      // caller's own refresh.
    }
    return null;
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
      if (!isMissingMethodError(e)) rethrow;
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
  ///
  /// Odoo words it differently by release: 17 and 18 say "The method 'x' does
  /// not exist on the model 'm'", 19 and 20 "The method 'm.x' does not exist".
  static bool isMissingMethodError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('has no attribute') ||
        message.contains('object has no method') ||
        message.contains('is not a valid action') ||
        message.contains('attributeerror') ||
        (message.contains('the method') && message.contains('does not exist'));
  }

  /// Cancels the invoice with [invoiceId].
  ///
  /// `button_cancel` is the method on every supported release, 17 to 20, and
  /// from the posted state it first resets the invoice to draft itself. The
  /// `action_cancel` retry exists only for a server that does not define
  /// `button_cancel`; no release does define `action_cancel`, so trying it first
  /// cost a failed call (and a server-side error) on every cancel. As with
  /// [resetToDraft], any other failure is rethrown: it is Odoo's real reason.
  Future<void> cancelInvoice(int invoiceId) async {
    try {
      await OdooSessionManager.safeCallKw({
        'model': 'account.move',
        'method': 'button_cancel',
        'args': [
          [invoiceId],
        ],
        'kwargs': {},
      });
    } catch (e) {
      if (!isMissingMethodError(e)) rethrow;
      await OdooSessionManager.safeCallKw({
        'model': 'account.move',
        'method': 'action_cancel',
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

/// Odoo's Invoicing group — "Billing" on Odoo 17, "Invoicing" from 18.
///
/// `account.move._post` requires it on every release the app supports, over
/// and above write access to the model, and raises an `AccessError` without
/// it. The external id is unchanged across 17 to 20.
const String kInvoicingGroup = 'account.group_account_invoice';

/// What to tell a user who has write access but not [kInvoicingGroup].
///
/// Names the right by the label Odoo shows, so the administrator being asked
/// can find it: Settings → Users → the user → Accounting.
const String kInvoicingGroupMissingMessage =
    'You do not have permission to confirm invoices. Ask your administrator '
    'to give you the Invoicing access right in Odoo (called Billing on Odoo '
    '17), under Settings → Users → Accounting.';
