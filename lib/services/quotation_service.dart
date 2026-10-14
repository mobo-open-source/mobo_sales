import 'package:flutter/material.dart';
import 'package:mobo_sales/widgets/confetti_dialogs.dart';
import 'package:mobo_sales/widgets/custom_snackbar.dart';
import 'odoo_error_handler.dart';
import 'odoo_session_manager.dart';
import 'data_change_bus.dart';

/// Handles send, email, and delete operations on Odoo `sale.order` records.
class QuotationService {
  /// Sends the quotation email for [orderId] (instance method wrapper).
  Future<void> sendQuotationInstance(
    BuildContext context,
    int orderId, {
    required VoidCallback closeLoadingDialog,
  }) {
    return sendQuotation(
      context,
      orderId,
      closeLoadingDialog: closeLoadingDialog,
    );
  }

  /// Returns `true` if the quotation with [orderId] can be sent (not cancelled).
  Future<bool> canSendQuotationInstance(int orderId) {
    return canSendQuotation(orderId);
  }

  /// Deletes the quotation with [orderId] (instance method wrapper).
  Future<void> deleteQuotationInstance(int orderId) {
    return deleteQuotation(orderId);
  }

  /// Triggers the Odoo send-by-email wizard for [orderId] and shows a confirmation dialog.
  static Future<void> sendQuotation(
    BuildContext context,
    int orderId, {
    required VoidCallback closeLoadingDialog,
  }) async {
    try {
      final session = await OdooSessionManager.getCurrentSession();
      if (session == null) {
        throw Exception('No session found');
      }

      final contextParams = {
        'lang': 'en_US',
        'tz': 'UTC',
        'uid': session.userId ?? 0,
        'allowed_company_ids': session.allowedCompanyIds.isNotEmpty
            ? session.allowedCompanyIds
            : (session.selectedCompanyId != null
                  ? [session.selectedCompanyId!]
                  : []),
        'active_model': 'sale.order',
        'active_id': orderId,
        'active_ids': [orderId],
        'default_model': 'sale.order',
        'default_res_ids': [orderId],
        'default_composition_mode': 'comment',
        'default_email_layout_xmlid':
            'mail.mail_notification_layout_with_responsible_signature',
        'email_notification_allow_footer': true,
        'proforma': false,
        'force_email': true,
        'model_description': 'Sales Order',
        'mark_so_as_sent': true,
        'validate_analytic': true,
        'check_document_layout': true,
      };

      ('Sending quotation with order ID: $orderId', name: 'QuotationService');

      final quotationCheck = await OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', orderId],
          ],
        ],
        'kwargs': {
          'fields': ['id', 'name', 'state'],
          'context': contextParams,
        },
      });

      if (quotationCheck is! List || quotationCheck.isEmpty) {
        throw Exception(
          'Quotation with ID $orderId not found or has been deleted',
        );
      }

      final quotation = quotationCheck.first;
      final quotationState = quotation['state'];
      final quotationName = quotation['name'];

      (
        'Quotation found: $quotationName, State: $quotationState',
        name: 'QuotationService',
      );

      if (quotationState == 'cancel') {
        throw Exception('Cannot send cancelled quotation $quotationName');
      }

      final wizardAction = await OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'action_quotation_send',
        'args': [orderId],
        'kwargs': {'context': contextParams},
      });

      if (wizardAction is Map && wizardAction.containsKey('res_model')) {
        final wizardModel = wizardAction['res_model'];

        if (wizardModel == 'base.document.layout') {
          final wizardContext = wizardAction['context'];
          if (wizardContext is Map &&
              wizardContext.containsKey('report_action')) {
            final reportAction = wizardContext['report_action'];
            if (reportAction is Map &&
                reportAction['res_model'] == 'mail.compose.message') {
              final nestedContext = Map<String, dynamic>.from(contextParams);
              if (reportAction['context'] != null) {
                nestedContext.addAll(
                  Map<String, dynamic>.from(reportAction['context']),
                );
              }

              final wizardCreateResult = await OdooSessionManager.safeCallKw({
                'model': 'mail.compose.message',
                'method': 'create',
                'args': [{}],
                'kwargs': {'context': nestedContext},
              });

              if (wizardCreateResult is int) {
                final sendResult = await OdooSessionManager.safeCallKw({
                  'model': 'mail.compose.message',
                  'method': 'action_send_mail',
                  'args': [wizardCreateResult],
                  'kwargs': {'context': nestedContext},
                });

                final verifyResult = await OdooSessionManager.safeCallKw({
                  'model': 'sale.order',
                  'method': 'read',
                  'args': [orderId],
                  'kwargs': {
                    'fields': ['state'],
                    'context': contextParams,
                  },
                });

                final currentState =
                    verifyResult is List && verifyResult.isNotEmpty
                    ? verifyResult.first['state']
                    : quotationState;

                final sendSuccess = true;

                if (context.mounted) {
                  if (sendSuccess) {
                    closeLoadingDialog();

                    await Future.delayed(const Duration(milliseconds: 300));
                    if (context.mounted) {
                      showQuotationSentConfettiDialog(context, quotationName);
                    }
                  }
                }
              } else {
                throw Exception('Failed to create send wizard');
              }
            } else {
              throw Exception(
                'No valid mail compose wizard found in document layout action',
              );
            }
          } else {
            throw Exception(
              'Document layout wizard missing report_action context',
            );
          }
        } else if (wizardModel == 'mail.compose.message') {
          final wizardContext = Map<String, dynamic>.from(contextParams);
          if (wizardAction['context'] != null) {
            wizardContext.addAll(
              Map<String, dynamic>.from(wizardAction['context']),
            );
          }

          final wizardCreateResult = await OdooSessionManager.safeCallKw({
            'model': 'mail.compose.message',
            'method': 'create',
            'args': [{}],
            'kwargs': {'context': wizardContext},
          });

          if (wizardCreateResult is int) {
            final sendResult = await OdooSessionManager.safeCallKw({
              'model': 'mail.compose.message',
              'method': 'action_send_mail',
              'args': [wizardCreateResult],
              'kwargs': {'context': wizardContext},
            });

            final verifyResult = await OdooSessionManager.safeCallKw({
              'model': 'sale.order',
              'method': 'read',
              'args': [orderId],
              'kwargs': {
                'fields': ['state'],
                'context': contextParams,
              },
            });

            final currentState = verifyResult is List && verifyResult.isNotEmpty
                ? verifyResult.first['state']
                : quotationState;

            final sendSuccess = true;

            // Sending marks a draft as sent: the list, the details behind this
            // dialog and the dashboard show the new state.
            DataChangeBus.instance.quotationChanged(orderId);

            if (context.mounted) {
              if (sendSuccess) {
                closeLoadingDialog();

                await Future.delayed(const Duration(milliseconds: 300));
                if (context.mounted) {
                  showQuotationSentConfettiDialog(context, quotationName);
                }
              }
            }
          } else {
            throw Exception('Failed to create send wizard');
          }
        } else {
          throw Exception('Unexpected wizard model: $wizardModel');
        }
      } else {
        DataChangeBus.instance.quotationChanged(orderId);
        if (context.mounted) {
          closeLoadingDialog();

          await Future.delayed(const Duration(milliseconds: 300));
          if (context.mounted) {
            showQuotationSentConfettiDialog(context, quotationName);
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        closeLoadingDialog();

        await Future.delayed(const Duration(milliseconds: 300));
        if (context.mounted) {
          CustomSnackbar.showError(context, _getErrorMessage(e));
        }
      }
    }
  }

  /// Checks whether the quotation with [orderId] is in a sendable state.
  static Future<bool> canSendQuotation(int orderId) async {
    try {
      final result = await OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', orderId],
          ],
        ],
        'kwargs': {
          'fields': ['state'],
          'limit': 1,
        },
      });

      if (result is List && result.isNotEmpty) {
        final quotation = result.first;
        final state = quotation['state'];
        return state != 'cancel';
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Returns all field names available on the `sale.order` model.
  static Future<List<String>> getAvailableFields() async {
    try {
      final result = await OdooSessionManager.safeCallKw({
        'model': 'sale.order',
        'method': 'fields_get',
        'args': [],
        'kwargs': {},
      });

      if (result is Map) {
        return result.keys.cast<String>().toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Permanently deletes the draft or cancelled quotation with [orderId].
  static Future<void> deleteQuotation(int orderId) async {
    final result = await OdooSessionManager.safeCallKw({
      'model': 'sale.order',
      'method': 'search_read',
      'args': [
        [
          ['id', '=', orderId],
        ],
      ],
      'kwargs': {
        'fields': ['state', 'name'],
        'limit': 1,
      },
    });

    if (result is! List || result.isEmpty) {
      throw Exception('Sale Order not found');
    }

    final so = result.first as Map<String, dynamic>;
    final state = so['state']?.toString();
    final name = so['name']?.toString() ?? '#$orderId';

    if (state != 'draft' && state != 'cancel') {
      throw Exception(
        'Only draft or cancelled documents can be deleted ($name)',
      );
    }

    await OdooSessionManager.safeCallKw({
      'model': 'sale.order',
      'method': 'unlink',
      'args': [
        [orderId],
      ],
      'kwargs': {},
    });
  }

  /// Why sending failed, in one sentence for the snackbar.
  static String _getErrorMessage(dynamic error) {
    final errorString = error.toString();

    if (errorString.contains('Cannot send cancelled quotation')) {
      return 'Cannot send a cancelled quotation. Please check the quotation status.';
    }

    if (errorString.contains('not found or has been deleted')) {
      return 'Quotation not found. It may have been deleted by another user.';
    }

    return OdooErrorHandler.toSnackbarMessage(
      error,
      fallback: 'Could not send the quotation. Please try again.',
    );
  }
}
