import 'package:flutter/material.dart';
import '../widgets/confetti_dialogs.dart';
import 'odoo_session_manager.dart';

/// Manages invoice sending, sale order fetching, and invoice creation against Odoo.
class InvoiceService {
  static final InvoiceService instance = InvoiceService._internal();
  InvoiceService._internal();

  /// Sends the invoice email for [moveId] and shows a confirmation dialog on success.
  Future<void> sendInvoice(
    BuildContext context,
    int moveId, {
    required VoidCallback closeLoadingDialog,
  }) async {
    try {
      final contextParams = {
        'lang': 'en_US',
        'tz': 'UTC',
        'allowed_company_ids': [1],
        'active_model': 'account.move',
        'active_id': moveId,
        'active_ids': [moveId],
      };

      final wizardAction = await OdooSessionManager.safeCallKw({
        'model': 'account.move',
        'method': 'action_invoice_sent',
        'args': [moveId],
        'kwargs': {'context': contextParams},
      });

      if (wizardAction is Map && wizardAction.containsKey('res_model')) {
        final wizardModel = wizardAction['res_model'];

        if (wizardModel == 'account.move.send.wizard') {
          final wizardCreateResult = await OdooSessionManager.safeCallKw({
            'model': 'account.move.send.wizard',
            'method': 'create',
            'args': [
              {'move_id': moveId},
            ],
            'kwargs': {'context': contextParams},
          });

          if (wizardCreateResult is int) {
            await OdooSessionManager.safeCallKw({
              'model': 'account.move.send.wizard',
              'method': 'action_send_and_print',
              'args': [wizardCreateResult],
              'kwargs': {'context': contextParams},
            });

            final verifyResult = await OdooSessionManager.safeCallKw({
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
              closeLoadingDialog();
              if (isSent) {
                showInvoiceSentConfettiDialog(context, invoiceName);
              }
            }
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        closeLoadingDialog();
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
      final result = await OdooSessionManager.safeCallKw({
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
      final result = await OdooSessionManager.safeCallKw({
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

  /// Fetches the `sale.order.line` records for the given [lineIds].
  Future<List<Map<String, dynamic>>> fetchSaleOrderLines(
    List<int> lineIds,
  ) async {
    try {
      final result = await OdooSessionManager.safeCallKw({
        'model': 'sale.order.line',
        'method': 'read',
        'args': [lineIds],
        'kwargs': {
          'fields': [
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
            'tax_id',
            'uom_id',
            'product_uom_id',
          ],
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

  /// Returns all available payment terms from `account.payment.term`.
  Future<List<Map<String, dynamic>>> fetchPaymentTerms() async {
    try {
      final result = await OdooSessionManager.safeCallKw({
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
  Future<int> createInvoice(Map<String, dynamic> invoiceData) async {
    try {
      final result = await OdooSessionManager.safeCallKw({
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

  /// Creates a temporary invoice to calculate tax totals, then deletes it.
  Future<Map<String, dynamic>> calculateTax(
    Map<String, dynamic> tempInvoiceData,
  ) async {
    int? tempMoveId;
    try {
      tempMoveId = await createInvoice(tempInvoiceData);

      final result = await OdooSessionManager.safeCallKw({
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
          await OdooSessionManager.safeCallKw({
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
      final result = await OdooSessionManager.safeCallKw({
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
      final result = await OdooSessionManager.safeCallKw({
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
      return await OdooSessionManager.safeCallKw({
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
      int userCompanyId = 1;

      if (session?.userId != null) {
        final userResult = await OdooSessionManager.safeCallKw({
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

      final result = await OdooSessionManager.safeCallKw({
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
      await OdooSessionManager.safeCallKw({
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
      final result = await OdooSessionManager.safeCallKw({
        'model': 'account.move',
        'method': 'read',
        'args': [
          [invoiceId],
        ],
        'kwargs': {
          'fields': ['name'],
        },
      });

      if (result is List && result.isNotEmpty) {
        return result[0]['name']?.toString();
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
