import 'package:flutter/material.dart';
import '../utils/invoice_name.dart';
import '../utils/odoo_version.dart';
import '../widgets/confetti_dialogs.dart';
import 'data_change_bus.dart';
import 'odoo_session_manager.dart';

/// Manages invoice sending, sale order fetching, and invoice creation against Odoo.
class InvoiceService {
  static final InvoiceService instance = InvoiceService._internal();
  InvoiceService._internal()
    : _callKw = OdooSessionManager.safeCallKw,
      _bus = DataChangeBus.instance;

  /// A service that talks to [callKw] instead of the Odoo session and
  /// announces on [bus]; for tests.
  @visibleForTesting
  InvoiceService.forTesting({
    required Future<dynamic> Function(Map<String, dynamic> payload) callKw,
    required DataChangeBus bus,
  }) : _callKw = callKw,
       _bus = bus;

  final Future<dynamic> Function(Map<String, dynamic> payload) _callKw;
  final DataChangeBus _bus;

  /// The `res.partner` fields read to fill in the customer when an invoice is
  /// opened for editing.
  ///
  /// `mobile` was removed in Odoo 19 and `company_name` in Odoo 20. Asking for
  /// a field the server no longer has fails the whole read, and the edit form
  /// would then show the customer with no contact details at all.
  static List<String> customerPrefillFields(int generation) => [
    'id',
    'name',
    'email',
    'phone',
    if (odooHasPartnerMobile(generation)) 'mobile',
    'street',
    'street2',
    'city',
    'state_id',
    'zip',
    'country_id',
    'image_1920',
    if (odooHasPartnerCompanyName(generation)) 'company_name',
    'vat',
  ];

  /// Sends the invoice email for [moveId] and shows a confirmation dialog on success.
  ///
  /// [closeLoadingDialog] is called exactly once on every path that ends
  /// here — sent, not sent, unsupported or failed — so the caller's loading
  /// dialog can never be left on screen. It is called before the confirmation
  /// dialog or the error is shown, never after.
  Future<void> sendInvoice(
    BuildContext context,
    int moveId, {
    required VoidCallback closeLoadingDialog,
  }) async {
    var dialogClosed = false;
    void closeDialogOnce() {
      if (dialogClosed) return;
      dialogClosed = true;
      closeLoadingDialog();
    }

    try {
      final session = await OdooSessionManager.getCurrentSession();
      final contextParams = {
        'lang': 'en_US',
        'tz': 'UTC',
        'allowed_company_ids':
            session != null && session.allowedCompanyIds.isNotEmpty
            ? session.allowedCompanyIds
            : (session?.selectedCompanyId != null
                  ? [session!.selectedCompanyId!]
                  : []),
        'active_model': 'account.move',
        'active_id': moveId,
        'active_ids': [moveId],
      };

      final wizardAction = await _callKw({
        'model': 'account.move',
        'method': 'action_invoice_sent',
        'args': [moveId],
        'kwargs': {'context': contextParams},
      });

      final wizardModel = wizardAction is Map
          ? wizardAction['res_model']
          : null;
      if (wizardModel != 'account.move.send.wizard') {
        // Another release asks for a different wizard (Odoo 17's is
        // `account.move.send`), which this flow does not drive. Saying so is
        // better than leaving the loading dialog up with nothing happening.
        throw Exception(
          'Sending invoices by email from the app is not supported by this '
          'Odoo version. Send it from Odoo instead.',
        );
      }

      final wizardCreateResult = await _callKw({
        'model': 'account.move.send.wizard',
        'method': 'create',
        'args': [
          {'move_id': moveId},
        ],
        'kwargs': {'context': contextParams},
      });

      if (wizardCreateResult is! int) {
        throw Exception('Odoo did not open the send wizard for this invoice.');
      }

      await _callKw({
        'model': 'account.move.send.wizard',
        'method': 'action_send_and_print',
        'args': [wizardCreateResult],
        'kwargs': {'context': contextParams},
      });

      // The invoice is sent (and its "sent" flag set) on the server from here.
      _bus.invoiceChanged(moveId);

      final verifyResult = await _callKw({
        'model': 'account.move',
        'method': 'read',
        'args': [moveId],
        'kwargs': {
          'fields': ['is_move_sent', 'name'],
          'context': contextParams,
        },
      });

      final isSent = verifyResult is List && verifyResult.isNotEmpty
          ? verifyResult.first['is_move_sent'] ?? false
          : false;
      final invoiceName = verifyResult is List && verifyResult.isNotEmpty
          ? verifyResult.first['name']?.toString() ?? 'Invoice'
          : 'Invoice';

      if (context.mounted) {
        closeDialogOnce();
        if (isSent) {
          showInvoiceSentConfettiDialog(context, invoiceName);
        }
      }
    } catch (e) {
      if (context.mounted) {
        closeDialogOnce();
      }
      rethrow;
    }
  }

  /// Fetches a paginated list of sale orders matching [domain].
  Future<List<Map<String, dynamic>>> fetchSaleOrders({
    required List<dynamic> domain,
    int limit = 40,
    int offset = 0,
    String order = 'name desc',
  }) async {
    try {
      final result = await _callKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [domain],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'partner_id',
            'amount_total',
            'date_order',
            'state',
            'invoice_status',
            'currency_id',
          ],
          'order': order,
          'limit': limit,
          'offset': offset,
        },
      });

      if (result is List) {
        return result.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  /// Fetches full details for the sale order with [saleOrderId].
  Future<Map<String, dynamic>> fetchSaleOrderDetails(int saleOrderId) async {
    try {
      final result = await _callKw({
        'model': 'sale.order',
        'method': 'read',
        'args': [
          [saleOrderId],
        ],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'partner_id',
            'amount_total',
            'amount_untaxed',
            'amount_tax',
            'currency_id',
            'date_order',
            'state',
            'invoice_status',
            'invoice_count',
            'invoice_ids',
            'payment_term_id',
            'order_line',
          ],
        },
      });

      return result.isNotEmpty ? result[0] : {};
    } catch (e) {
      rethrow;
    }
  }

  /// The fields that read across Odoo 17 to 20 without renaming.
  static const _saleOrderLineBaseFields = [
    'id',
    'product_id',
    'name',
    'product_uom_qty',
    'qty_delivered',
    'qty_invoiced',
    'qty_to_invoice',
    'price_unit',
    'price_subtotal',
    'price_total',
    'discount',
  ];

  /// sale.order.line's tax and unit-of-measure fields were renamed in Odoo 19
  /// (`tax_id` -> `tax_ids`, `product_uom` -> `product_uom_id`). Each list holds
  /// every known alias, tried in order, so the read call below self-heals
  /// instead of failing outright when the server rejects one.
  static const _saleOrderLineTaxFieldAliases = ['tax_id', 'tax_ids'];
  static const _saleOrderLineUomFieldAliases = [
    'product_uom',
    'product_uom_id',
  ];

  /// The tax field names to try for `sale.order.line` on [generation], the
  /// name the server has first. Odoo 19 and 20 only know `tax_ids`; asking for
  /// `tax_id` first made them refuse it (and log an error) before every read.
  /// An unknown generation (0) keeps the original order.
  static List<String> saleOrderLineTaxFieldAliases(int generation) =>
      generation >= 19
      ? _saleOrderLineTaxFieldAliases.reversed.toList()
      : _saleOrderLineTaxFieldAliases.toList();

  /// The unit-of-measure field names to try for `sale.order.line`; see
  /// [saleOrderLineTaxFieldAliases].
  static List<String> saleOrderLineUomFieldAliases(int generation) =>
      generation >= 19
      ? _saleOrderLineUomFieldAliases.reversed.toList()
      : _saleOrderLineUomFieldAliases.toList();

  /// Extracts the offending field name from an "Invalid field 'x' on
  /// 'model'" Odoo server error, or null if the error doesn't match.
  String? _invalidFieldFrom(Object error) {
    final match = RegExp(
      r"Invalid field '([^']+)'",
    ).firstMatch(error.toString());
    return match?.group(1);
  }

  /// Fetches the `sale.order.line` records for the given [lineIds].
  Future<List<Map<String, dynamic>>> fetchSaleOrderLines(
    List<int> lineIds,
  ) async {
    Future<dynamic> attemptRead(String taxField, String uomField) {
      return _callKw({
        'model': 'sale.order.line',
        'method': 'read',
        'args': [lineIds],
        'kwargs': {
          'fields': [..._saleOrderLineBaseFields, taxField, uomField],
        },
      });
    }

    try {
      final generation = await OdooSessionManager.serverGeneration();
      final taxAliases = saleOrderLineTaxFieldAliases(generation);
      final uomAliases = saleOrderLineUomFieldAliases(generation);

      var taxField = taxAliases.first;
      var uomField = uomAliases.first;

      dynamic result;
      final maxAttempts = taxAliases.length + uomAliases.length;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        try {
          result = await attemptRead(taxField, uomField);
          break;
        } catch (e) {
          final invalidField = _invalidFieldFrom(e);
          final taxIndex = taxAliases.indexOf(taxField);
          final uomIndex = uomAliases.indexOf(uomField);

          if (invalidField == taxField && taxIndex < taxAliases.length - 1) {
            taxField = taxAliases[taxIndex + 1];
          } else if (invalidField == uomField &&
              uomIndex < uomAliases.length - 1) {
            uomField = uomAliases[uomIndex + 1];
          } else {
            rethrow;
          }
        }
      }

      if (result is List) {
        return result.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  /// Returns all available payment terms from `account.payment.term`.
  Future<List<Map<String, dynamic>>> fetchPaymentTerms() async {
    try {
      final result = await _callKw({
        'model': 'account.payment.term',
        'method': 'search_read',
        'args': [[]],
        'kwargs': {
          'fields': ['id', 'name'],
          'order': 'name ASC',
        },
      });

      if (result is List) {
        return result.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  /// Creates a new `account.move` record from [invoiceData] and returns its ID.
  ///
  /// This is only the write and it announces nothing: the tax estimate below
  /// creates and deletes a throwaway invoice through it, which no list should
  /// hear about. The caller that creates a real invoice announces it (see
  /// `CreateInvoiceProvider`), since it also knows the sale order it is for.
  Future<int> createInvoice(Map<String, dynamic> invoiceData) async {
    try {
      final result = await _callKw({
        'model': 'account.move',
        'method': 'create',
        'args': [invoiceData],
        'kwargs': {},
      });

      if (result is int) return result;
      throw Exception('Failed to create invoice: Unexpected result $result');
    } catch (e) {
      rethrow;
    }
  }

  /// Writes [values] to the invoice [invoiceId] and announces the change.
  Future<void> updateInvoice(int invoiceId, Map<String, dynamic> values) async {
    await _callKw({
      'model': 'account.move',
      'method': 'write',
      'args': [
        [invoiceId],
        values,
      ],
      'kwargs': {},
    });
    _bus.invoiceChanged(invoiceId);
  }

  /// Creates a temporary invoice to calculate tax totals, then deletes it.
  Future<Map<String, dynamic>> calculateTax(
    Map<String, dynamic> tempInvoiceData,
  ) async {
    int? tempMoveId;
    try {
      tempMoveId = await createInvoice(tempInvoiceData);

      final result = await _callKw({
        'model': 'account.move',
        'method': 'read',
        'args': [
          [tempMoveId],
        ],
        'kwargs': {
          'fields': ['amount_untaxed', 'amount_tax', 'amount_total'],
        },
      });

      if (result is List && result.isNotEmpty) {
        return result.first as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      rethrow;
    } finally {
      if (tempMoveId != null) {
        try {
          await _callKw({
            'model': 'account.move',
            'method': 'unlink',
            'args': [
              [tempMoveId],
            ],
            'kwargs': {},
          });
        } catch (unlinkError) {}
      }
    }
  }

  /// Returns the Odoo database ID for the currency with ISO [code].
  Future<int?> getCurrencyId(String code) async {
    try {
      final result = await _callKw({
        'model': 'res.currency',
        'method': 'search_read',
        'args': [
          [
            ['name', '=', code],
          ],
        ],
        'kwargs': {
          'fields': ['id'],
          'limit': 1,
        },
      });

      if (result is List && result.isNotEmpty) {
        return result.first['id'] as int?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Creates a `sale.advance.payment.inv` wizard record with [data] and returns its ID.
  Future<int> createAdvancePaymentWizard(Map<String, dynamic> data) async {
    try {
      final result = await _callKw({
        'model': 'sale.advance.payment.inv',
        'method': 'create',
        'args': [data],
        'kwargs': {},
      });

      if (result is int) return result;
      throw Exception('Failed to create advance payment wizard');
    } catch (e) {
      rethrow;
    }
  }

  /// Executes the advance payment wizard to generate invoices from a sale order.
  Future<dynamic> executeAdvancePaymentWizard(
    int wizardId, {
    Map<String, dynamic>? context,
  }) async {
    try {
      return await _callKw({
        'model': 'sale.advance.payment.inv',
        'method': 'create_invoices',
        'args': [
          [wizardId],
        ],
        'kwargs': {if (context != null) 'context': context},
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Filters [productTaxIds] to only those belonging to the current user's company.
  Future<List<int>> filterTaxesByCompany(List<int> productTaxIds) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return productTaxIds;

      final session = await OdooSessionManager.getCurrentSession();
      int userCompanyId = 0;

      if (session?.userId != null) {
        final userResult = await _callKw({
          'model': 'res.users',
          'method': 'read',
          'args': [
            [session!.userId],
          ],
          'kwargs': {
            'fields': ['company_id'],
          },
        });
        if (userResult is List && userResult.isNotEmpty) {
          final companyField = userResult[0]['company_id'];
          if (companyField is List && companyField.isNotEmpty) {
            userCompanyId = companyField[0] as int;
          }
        }
      }

      final result = await _callKw({
        'model': 'account.tax',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', productTaxIds],
            ['company_id', '=', userCompanyId],
          ],
        ],
        'kwargs': {
          'fields': ['id'],
        },
      });

      if (result is List) {
        return result.map((t) => t['id'] as int).toList();
      }
      return productTaxIds;
    } catch (e) {
      return productTaxIds;
    }
  }

  /// Associates [invoiceId] with [saleOrderId] in Odoo.
  Future<void> linkInvoiceToSaleOrder(int saleOrderId, int invoiceId) async {
    try {
      await _callKw({
        'model': 'sale.order',
        'method': 'write',
        'args': [
          [saleOrderId],
          {
            'invoice_ids': [
              [4, invoiceId],
            ],
          },
        ],
        'kwargs': {},
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Returns the display name (sequence number) for the invoice with [invoiceId].
  Future<String?> getInvoiceName(int invoiceId) async {
    try {
      final result = await _callKw({
        'model': 'account.move',
        'method': 'read',
        'args': [
          [invoiceId],
        ],
        'kwargs': {
          'fields': ['name', 'state'],
        },
      });

      if (result is List && result.isNotEmpty) {
        // A draft has no number: it is called "Draft", not "false".
        return invoiceDisplayName(result[0]['name'], result[0]['state']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
