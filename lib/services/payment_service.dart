import 'dart:async' show TimeoutException;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:intl/intl.dart';
import '../models/payment.dart';
import '../models/invoice.dart';
import 'data_change_bus.dart';
import 'odoo_error_classifier.dart';
import 'odoo_error_handler.dart';
import 'odoo_session_manager.dart';
import 'permission_service.dart';

class PaymentMethodData {
  final int id;
  final String name;
  final String type;
  final bool isDefault;
  final Map<String, dynamic> odooConfig;

  PaymentMethodData({
    required this.id,
    required this.name,
    required this.type,
    this.isDefault = false,
    this.odooConfig = const {},
  });

  factory PaymentMethodData.fromJson(Map<String, dynamic> json) {
    return PaymentMethodData(
      id: json['id'],
      name: json['name'] ?? 'Unknown Method',
      type: json['type'] ?? 'bank',
      isDefault: json['is_default'] ?? false,
      odooConfig: json['odoo_config'] ?? {},
    );
  }
}

class PaymentOptions {
  final String memo;
  final PaymentDifferenceHandling differenceHandling;
  final WriteOffConfig? writeOffConfig;
  final bool autoReconcile;

  PaymentOptions({
    this.memo = '',
    this.differenceHandling = PaymentDifferenceHandling.keepOpen,
    this.writeOffConfig,
    this.autoReconcile = true,
  });
}

enum PaymentDifferenceHandling { keepOpen, writeOff }

class WriteOffConfig {
  final int accountId;
  final String label;

  WriteOffConfig({required this.accountId, required this.label});
}

class PaymentResult {
  final bool success;
  final Payment? payment;
  final Invoice updatedInvoice;
  final List<String> warnings;
  final String? errorMessage;

  PaymentResult({
    required this.success,
    this.payment,
    required this.updatedInvoice,
    this.warnings = const [],
    this.errorMessage,
  });
}

enum PaymentErrorType { network, validation, sync, reconciliation, unknown }

enum PaymentErrorAction { retry, correct, refresh, contact }

class OdooPaymentBehavior {
  final bool marksAsPaidDirectly;
  final bool requiresReconciliation;
  final String paymentStateAfterRecording;
  final String databaseVersion;

  OdooPaymentBehavior({
    required this.marksAsPaidDirectly,
    required this.requiresReconciliation,
    required this.paymentStateAfterRecording,
    required this.databaseVersion,
  });

  factory OdooPaymentBehavior.fromDetection(Map<String, dynamic> detection) {
    return OdooPaymentBehavior(
      marksAsPaidDirectly: detection['marks_as_paid_directly'] ?? false,
      requiresReconciliation: detection['requires_reconciliation'] ?? true,
      paymentStateAfterRecording:
          detection['payment_state_after_recording'] ?? 'in_payment',
      databaseVersion: detection['database_version'] ?? 'unknown',
    );
  }
}

class PaymentError extends Error {
  final PaymentErrorType type;
  final String message;
  final String? field;
  final PaymentErrorAction action;
  final Map<String, dynamic>? context;

  PaymentError({
    required this.type,
    required this.message,
    this.field,
    required this.action,
    this.context,
  });

  factory PaymentError.network({
    required String message,
    required PaymentErrorAction action,
    Map<String, dynamic>? context,
  }) {
    return PaymentError(
      type: PaymentErrorType.network,
      message: message,
      action: action,
      context: context,
    );
  }

  factory PaymentError.validation({
    required String message,
    String? field,
    required PaymentErrorAction action,
    Map<String, dynamic>? context,
  }) {
    return PaymentError(
      type: PaymentErrorType.validation,
      message: message,
      field: field,
      action: action,
      context: context,
    );
  }

  factory PaymentError.sync({
    required String message,
    required PaymentErrorAction action,
    Map<String, dynamic>? context,
  }) {
    return PaymentError(
      type: PaymentErrorType.sync,
      message: message,
      action: action,
      context: context,
    );
  }

  factory PaymentError.unknown({
    required String message,
    required PaymentErrorAction action,
    Map<String, dynamic>? context,
  }) {
    return PaymentError(
      type: PaymentErrorType.unknown,
      message: message,
      action: action,
      context: context,
    );
  }
}

/// How far registering a payment got, so a failure can tell "never sent" from
/// "sent, and the answer was lost".
class _PaymentProgress {
  /// True once the request that creates the payment was sent.
  bool sent = false;

  /// What the invoice still owed before the payment.
  double? residualBefore;

  /// The customer, and the newest payment they had before this one, so a
  /// payment that appears afterwards can be told from older ones. (Odoo 19 keeps
  /// the residual of an invoice whose payment is only "in process", so the
  /// residual alone does not show that a payment was made.)
  int? partnerId;
  int? newestPaymentBefore;
}

class PaymentService {
  static const Duration _defaultTimeout = Duration(seconds: 45);
  static const Duration _extendedTimeout = Duration(seconds: 60);

  static Map<String, OdooPaymentBehavior>? _odooBehaviorCache;

  /// The bus a registered payment is announced on. Tests swap in their own.
  @visibleForTesting
  static DataChangeBus bus = DataChangeBus.instance;

  /// Where the Odoo client comes from; a test swaps in a fake.
  @visibleForTesting
  static Future<dynamic> Function() clientProvider =
      OdooSessionManager.getClient;

  /// Announces that a payment was registered against [invoiceId], once the
  /// server has accepted it: the payment itself is new, and the invoice's
  /// payment state, residual amount and status chip have changed with it, so
  /// every list and detail page that shows either brings itself up to date.
  static void _announcePaymentRegistered(int invoiceId, int? paymentId) {
    bus.paymentChanged(paymentId, kind: DataChangeKind.created);
    bus.invoiceChanged(invoiceId);
  }

  static Future<OdooPaymentBehavior> detectOdooPaymentBehavior() async {
    if (_odooBehaviorCache != null && _odooBehaviorCache!.isNotEmpty) {
      final cached = _odooBehaviorCache!.values.first;
      return cached;
    }

    final client = await clientProvider();
    if (client == null) {
      return _getDefaultPaymentBehavior();
    }

    try {
      const shortTimeout = Duration(seconds: 10);

      final dbInfo = await client
          .callKw({
            'model': 'ir.config_parameter',
            'method': 'search_read',
            'args': [
              [
                [
                  'key',
                  'in',
                  ['database.version', 'web.base.url'],
                ],
              ],
              ['key', 'value'],
            ],
            'kwargs': {},
          })
          .timeout(shortTimeout);

      String databaseVersion = 'unknown';
      for (var param in dbInfo) {
        if (param['key'] == 'database.version') {
          databaseVersion = param['value'] ?? 'unknown';
          break;
        }
      }

      final behavior = await _detectPaymentBehaviorFromConfiguration(
        client,
      ).timeout(shortTimeout);

      final odooBehavior = OdooPaymentBehavior(
        marksAsPaidDirectly: behavior['marks_as_paid_directly'],
        requiresReconciliation: behavior['requires_reconciliation'],
        paymentStateAfterRecording: behavior['payment_state_after_recording'],
        databaseVersion: databaseVersion,
      );

      _odooBehaviorCache = {'default': odooBehavior};

      return odooBehavior;
    } catch (e) {
      final defaultBehavior = _getDefaultPaymentBehavior();
      _odooBehaviorCache = {'default': defaultBehavior};
      return defaultBehavior;
    }
  }

  static OdooPaymentBehavior _getDefaultPaymentBehavior() {
    return OdooPaymentBehavior(
      marksAsPaidDirectly: false,
      requiresReconciliation: true,
      paymentStateAfterRecording: 'in_payment',
      databaseVersion: 'unknown',
    );
  }

  static void clearBehaviorCache() {
    _odooBehaviorCache = null;
  }

  /// The domain for the accounts offered as the write-off of a payment
  /// difference (`account.payment.register.writeoff_account_id`).
  ///
  /// `account.account` changed shape twice. Odoo 18 replaced the single
  /// `company_id` by the many2many `company_ids` (an account can belong to
  /// several companies, and a branch uses its parent's), and Odoo 19 replaced
  /// the `deprecated` flag by the standard `active`. Searching a field the
  /// release does not have fails the whole call, so the company and the
  /// "not deprecated" conditions are built per [generation]. From 19 an
  /// inactive account is already left out of every search.
  ///
  /// An unknown generation (0) gets the Odoo 17 domain the app always sent.
  static List<dynamic> writeoffAccountDomain({
    required int generation,
    required int companyId,
  }) {
    final hasCompanyIds = generation >= 18;
    final hasDeprecated = generation < 19;
    return [
      hasCompanyIds
          ? ['company_ids', 'parent_of', companyId]
          : ['company_id', '=', companyId],
      [
        'account_type',
        'in',
        ['expense', 'asset_current', 'income_other'],
      ],
      if (hasDeprecated) ['deprecated', '=', false],
    ];
  }

  static Future<PaymentResult> createPaymentWithOdooFlow({
    required int invoiceId,
    required double amount,
    required PaymentMethodData paymentMethod,
    required DateTime paymentDate,
    PaymentOptions? options,
  }) async {
    return await _createPaymentWithTimeout(
      invoiceId: invoiceId,
      amount: amount,
      paymentMethod: paymentMethod,
      paymentDate: paymentDate,
      options: options,
    ).timeout(
      const Duration(seconds: 60),
      onTimeout: () => _processingResult(invoiceId, amount),
    );
  }

  /// What [createPaymentWithOdooFlow] answers when the server's answer to the
  /// payment request did not arrive, or could not be told apart from "done":
  /// not a failure and not a success, so the screen reloads the invoice and
  /// reports what it finds. The payment is never sent again.
  static PaymentResult _processingResult(int invoiceId, double amount) {
    return PaymentResult(
      success: false,
      updatedInvoice: Invoice(
        id: invoiceId,
        name: 'Unknown',
        customerName: 'Unknown',
        lines: [],
        taxLines: [],
        subtotal: 0,
        taxAmount: 0,
        total: amount,
        amountPaid: 0,
        amountResidual: amount,
        status: 'draft',
        paymentState: 'not_paid',
      ),
      errorMessage:
          'Payment is being processed. Please refresh to see the updated status.',
      warnings: ['timeout_but_processing'],
    );
  }

  /// Registers the payment once, and settles what happened when it does not
  /// answer cleanly.
  ///
  /// The wizard is run at most once. A request that failed or timed out may
  /// still have created the payment on the server; running it again then paid
  /// the invoice twice (a partial payment of 300 on 1000 leaves 700, so the
  /// repeat of 300 looks fine). So after a failure the invoice is read back:
  /// if it owes less than before the payment went through, and if it cannot be
  /// told the answer is "being processed".
  static Future<PaymentResult> _createPaymentWithTimeout({
    required int invoiceId,
    required double amount,
    required PaymentMethodData paymentMethod,
    required DateTime paymentDate,
    PaymentOptions? options,
  }) async {
    final client = await clientProvider();
    if (client == null) {
      throw PaymentError.network(
        message: 'No active Odoo session. Please log in again.',
        action: PaymentErrorAction.retry,
      );
    }

    final progress = _PaymentProgress();
    try {
      await _registerPayment(
        client,
        invoiceId: invoiceId,
        amount: amount,
        paymentDate: paymentDate,
        journalType: paymentMethod.type,
        memo: options?.memo,
        differenceHandling:
            options?.differenceHandling == PaymentDifferenceHandling.writeOff
            ? 'reconcile'
            : 'open',
        writeoffAccountId: options?.writeOffConfig?.accountId,
        writeoffLabel: options?.writeOffConfig?.label,
        progress: progress,
      );

      return PaymentResult(
        success: true,
        payment: null,
        updatedInvoice: await _getSafeInvoiceData(invoiceId),
        warnings: [],
      );
    } on PaymentError {
      // Refused before anything was sent (a bad amount, an unposted invoice,
      // no such journal): the user corrects it and tries again.
      rethrow;
    } catch (e) {
      return await _resultAfterFailure(
        client,
        invoiceId: invoiceId,
        amount: amount,
        error: e,
        progress: progress,
      );
    }
  }

  static Future<PaymentResult> _resultAfterFailure(
    dynamic client, {
    required int invoiceId,
    required double amount,
    required Object error,
    required _PaymentProgress progress,
  }) async {
    // Nothing was sent to create the payment: it is a plain failure.
    if (!progress.sent) {
      return PaymentResult(
        success: false,
        updatedInvoice: await _getSafeInvoiceData(invoiceId),
        errorMessage: OdooErrorHandler.toSnackbarMessage(error),
      );
    }

    // The request went out. Ask the server what became of it.
    double? after;
    try {
      after = await _residualOf(client, invoiceId);
    } catch (_) {}

    final before = progress.residualBefore;
    final owesLess = before != null && after != null && after < before - 1e-9;
    var paymentAppeared = false;
    try {
      paymentAppeared = await _paymentAppeared(client, progress, amount);
    } catch (_) {}
    if (owesLess || paymentAppeared) {
      // The invoice owes less than before, or a payment of this amount has
      // appeared for the customer: the payment was recorded and only the
      // answer got lost.
      return PaymentResult(
        success: true,
        payment: null,
        updatedInvoice: await _getSafeInvoiceData(invoiceId),
        warnings: [],
      );
    }

    // Nothing changed, and the server did answer with a refusal (it is not a
    // lost connection): the payment was not made.
    if (after != null && !_looksLikeLostAnswer(error)) {
      return PaymentResult(
        success: false,
        updatedInvoice: await _getSafeInvoiceData(invoiceId),
        errorMessage: OdooErrorHandler.toSnackbarMessage(error),
      );
    }

    // The answer was lost and the invoice does not show it yet (or could not
    // be read): the server may still be working on it.
    return _processingResult(invoiceId, amount);
  }

  /// Whether [error] is the answer going missing (a timeout, a dropped
  /// connection) rather than the server saying no.
  static bool _looksLikeLostAnswer(Object error) {
    if (error is TimeoutException) return true;
    if (OdooErrorClassifier.isServerUnreachable(error)) return true;
    final text = error.toString().toLowerCase();
    return text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('connection') ||
        text.contains('socket');
  }

  /// The id of the newest payment of [partnerId], or null when it cannot be
  /// read (then only the invoice's residual tells whether a payment was made).
  static Future<int?> _newestPaymentId(dynamic client, int? partnerId) async {
    if (partnerId == null) return null;
    try {
      final rows = await client
          .callKw({
            'model': 'account.payment',
            'method': 'search_read',
            'args': [
              [
                ['partner_id', '=', partnerId],
              ],
              ['id'],
            ],
            'kwargs': {'order': 'id desc', 'limit': 1},
          })
          .timeout(_defaultTimeout);
      if (rows is List) {
        return rows.isEmpty ? 0 : rows.first['id'] as int?;
      }
    } catch (_) {}
    return null;
  }

  /// Whether the customer has a payment of [amount] newer than the one seen
  /// before the request went out.
  static Future<bool> _paymentAppeared(
    dynamic client,
    _PaymentProgress progress,
    double amount,
  ) async {
    final partnerId = progress.partnerId;
    final newest = progress.newestPaymentBefore;
    if (partnerId == null || newest == null) return false;
    final rows = await client
        .callKw({
          'model': 'account.payment',
          'method': 'search_read',
          'args': [
            [
              ['partner_id', '=', partnerId],
              ['id', '>', newest],
              ['amount', '>=', amount - 0.0001],
              ['amount', '<=', amount + 0.0001],
            ],
            ['id'],
          ],
          'kwargs': {'limit': 1},
        })
        .timeout(_defaultTimeout);
    return rows is List && rows.isNotEmpty;
  }

  static Future<double> _residualOf(dynamic client, int invoiceId) async {
    final rows = await client
        .callKw({
          'model': 'account.move',
          'method': 'search_read',
          'args': [
            [
              ['id', '=', invoiceId],
            ],
            ['amount_residual'],
          ],
          'kwargs': {},
        })
        .timeout(_defaultTimeout);
    if (rows is! List || rows.isEmpty) {
      throw Exception('Invoice not found');
    }
    return ((rows.first['amount_residual'] as num?) ?? 0).toDouble();
  }

  /// Registers a payment on an invoice through Odoo's own wizard.
  ///
  /// The wizard is left to work out what it knows: the direction of the payment
  /// (a credit note is refunded, an invoice is collected), the partner, the
  /// company and, first, the journal and method line the invoice prefers. Only
  /// what the user chose is sent: the amount, the date, the memo, how a
  /// difference is handled, and the journal type (bank or cash) if the
  /// wizard's own journal is of another kind.
  static Future<({int? paymentId, int companyId})> _registerPayment(
    dynamic client, {
    required int invoiceId,
    required double amount,
    required DateTime paymentDate,
    required String journalType,
    String? memo,
    String differenceHandling = 'open',
    int? writeoffAccountId,
    String? writeoffLabel,
    required _PaymentProgress progress,
  }) async {
    if (amount <= 0) {
      throw PaymentError.validation(
        message: 'Payment amount must be greater than zero',
        field: 'amount',
        action: PaymentErrorAction.correct,
      );
    }

    final invoice = await _getInvoiceDetails(client, invoiceId);
    if (invoice['state'] != 'posted') {
      throw PaymentError.validation(
        message: 'Invoice must be posted before payment can be made',
        action: PaymentErrorAction.correct,
      );
    }
    progress.residualBefore = (invoice['amount_residual'] as num?)?.toDouble();
    final companyId = _idOf(invoice['company_id']) ?? 1;
    progress.partnerId = _idOf(invoice['partner_id']);
    progress.newestPaymentBefore = await _newestPaymentId(
      client,
      progress.partnerId,
    );

    final canCreatePaymentRegister = await PermissionService.instance.canCreate(
      'account.payment.register',
    );
    if (!canCreatePaymentRegister) {
      throw Exception('You do not have permission to register payments.');
    }

    final context = {
      'active_model': 'account.move',
      'active_ids': [invoiceId],
      'allowed_company_ids': [companyId],
    };

    final wizardData = <String, dynamic>{
      'amount': amount,
      'payment_date': DateFormat('yyyy-MM-dd').format(paymentDate),
      // Odoo's field for the memo. Left out when the user typed none, so Odoo
      // fills in its own (the invoice number).
      if (memo != null && memo.trim().isNotEmpty) 'communication': memo.trim(),
    };
    if (differenceHandling == 'reconcile' && writeoffAccountId != null) {
      wizardData['payment_difference_handling'] = 'reconcile';
      wizardData['writeoff_account_id'] = writeoffAccountId;
      wizardData['writeoff_label'] = writeoffLabel ?? 'Payment Difference';
    }

    final wizardId = await client
        .callKw({
          'model': 'account.payment.register',
          'method': 'create',
          'args': [wizardData],
          'kwargs': {'context': context},
        })
        .timeout(_defaultTimeout);

    await _chooseJournal(client, wizardId, journalType, context);

    // From here on the payment may exist on the server.
    progress.sent = true;
    final result = await client
        .callKw({
          'model': 'account.payment.register',
          'method': 'action_create_payments',
          'args': [
            [wizardId],
          ],
          'kwargs': {'context': context},
        })
        .timeout(_defaultTimeout);

    int? paymentId;
    if (result is Map && result['res_id'] is int) {
      paymentId = result['res_id'] as int;
    }

    _announcePaymentRegistered(invoiceId, paymentId);
    return (paymentId: paymentId, companyId: companyId);
  }

  /// Makes sure the wizard pays from a journal of the kind the user chose.
  ///
  /// The wizard has already picked one by Odoo's rules, the invoice's preferred
  /// payment method line first; that stays when it is of the right type. Only
  /// when it is not (the user chose cash, say) the first journal of the chosen
  /// type that the wizard offers is used, in Odoo's own journal order.
  static Future<void> _chooseJournal(
    dynamic client,
    dynamic wizardId,
    String journalType,
    Map<String, dynamic> context,
  ) async {
    final wanted = journalType.toLowerCase() == 'cash' ? 'cash' : 'bank';

    Future<Map<String, dynamic>?> readWizard() async {
      final rows = await client
          .callKw({
            'model': 'account.payment.register',
            'method': 'read',
            'args': [
              [wizardId],
              [
                'journal_id',
                'payment_method_line_id',
                'available_journal_ids',
                'available_payment_method_line_ids',
              ],
            ],
            'kwargs': {'context': context},
          })
          .timeout(_defaultTimeout);
      if (rows is List && rows.isNotEmpty && rows.first is Map) {
        return Map<String, dynamic>.from(rows.first as Map);
      }
      return null;
    }

    final wizard = await readWizard();
    if (wizard == null) return; // Cannot look: leave Odoo's own choice.

    final available = _idsOf(wizard['available_journal_ids']);
    if (available.isEmpty) return;

    final journals = await client
        .callKw({
          'model': 'account.journal',
          'method': 'search_read',
          'args': [
            [
              ['id', 'in', available],
            ],
            ['id', 'name', 'type'],
          ],
          'kwargs': {'context': context},
        })
        .timeout(_defaultTimeout);
    if (journals is! List) return;

    final currentId = _idOf(wizard['journal_id']);
    for (final j in journals) {
      if (j is Map && j['id'] == currentId && j['type'] == wanted) return;
    }

    Map? match;
    for (final j in journals) {
      if (j is Map && j['type'] == wanted) {
        match = j;
        break;
      }
    }
    if (match == null) {
      throw PaymentError.validation(
        message: 'No $wanted journal is available for this payment.',
        action: PaymentErrorAction.correct,
      );
    }

    await client
        .callKw({
          'model': 'account.payment.register',
          'method': 'write',
          'args': [
            [wizardId],
            {'journal_id': match['id']},
          ],
          'kwargs': {'context': context},
        })
        .timeout(_defaultTimeout);

    // Odoo picks the method line again for the new journal; if it found none,
    // take the first it offers.
    final after = await readWizard();
    if (after != null && _idOf(after['payment_method_line_id']) == null) {
      final lines = _idsOf(after['available_payment_method_line_ids']);
      if (lines.isNotEmpty) {
        await client
            .callKw({
              'model': 'account.payment.register',
              'method': 'write',
              'args': [
                [wizardId],
                {'payment_method_line_id': lines.first},
              ],
              'kwargs': {'context': context},
            })
            .timeout(_defaultTimeout);
      }
    }
  }

  static final Map<int, int> _decimalsCache = {};

  /// Decimal places of the currency [currencyId] (`res.currency`
  /// `decimal_places`): 2 for most, 3 for KWD or BHD, 0 for JPY. Two when it
  /// cannot be read, which is what most currencies use.
  static Future<int> currencyDecimals(int? currencyId) async {
    if (currencyId == null) return 2;
    final cached = _decimalsCache[currencyId];
    if (cached != null) return cached;
    try {
      final client = await clientProvider();
      if (client == null) return 2;
      final rows = await client
          .callKw({
            'model': 'res.currency',
            'method': 'read',
            'args': [
              [currencyId],
              ['decimal_places'],
            ],
            'kwargs': {},
          })
          .timeout(_defaultTimeout);
      if (rows is List && rows.isNotEmpty) {
        final places = rows.first['decimal_places'];
        if (places is int && places >= 0 && places <= 6) {
          return _decimalsCache[currencyId] = places;
        }
      }
    } catch (_) {}
    return 2;
  }

  static int? _idOf(dynamic value) {
    if (value is int) return value;
    if (value is List && value.isNotEmpty && value.first is int) {
      return value.first as int;
    }
    return null;
  }

  static List<int> _idsOf(dynamic value) => value is List
      ? [
          for (final v in value)
            if (v is int) v,
        ]
      : <int>[];

  /// Registers a payment and answers with what the server says. Throws when
  /// the server refuses it; nothing is announced then.
  static Future<Map<String, dynamic>> createPayment({
    required int invoiceId,
    required double amount,
    required String paymentMethod,
    required DateTime paymentDate,
    String? memo,
    String paymentDifferenceHandling = 'open',
    int? writeoffAccountId,
    String? writeoffLabel,
  }) async {
    final client = await clientProvider();
    if (client == null) {
      throw Exception('No active Odoo session');
    }

    final done = await _registerPayment(
      client,
      invoiceId: invoiceId,
      amount: amount,
      paymentDate: paymentDate,
      journalType: paymentMethod,
      memo: memo,
      differenceHandling: paymentDifferenceHandling,
      writeoffAccountId: writeoffAccountId,
      writeoffLabel: writeoffLabel,
      progress: _PaymentProgress(),
    );

    // The payment exists on the server from here on. Reading the invoice back
    // is only a courtesy to the caller, so a failure of that read must not turn
    // a recorded payment into a failed one.
    Map<String, dynamic> updatedInvoice = {};
    try {
      updatedInvoice = await _getUpdatedInvoiceStatus(client, invoiceId, done);
    } catch (_) {}

    return {
      'success': true,
      'payment_id': done.paymentId,
      'payment_state': updatedInvoice['payment_state'],
      'updated_invoice': updatedInvoice,
    };
  }

  static Future<Map<String, dynamic>> _getUpdatedInvoiceStatus(
    dynamic client,
    int invoiceId,
    ({int? paymentId, int companyId}) done,
  ) async {
    final result = await client
        .callKw({
          'model': 'account.move',
          'method': 'search_read',
          'args': [
            [
              ['id', '=', invoiceId],
            ],
            ['amount_residual', 'amount_total', 'state', 'payment_state'],
          ],
          'kwargs': {
            'context': {
              'allowed_company_ids': [done.companyId],
            },
          },
        })
        .timeout(_defaultTimeout);

    if (result.isEmpty) {
      throw Exception('Failed to fetch updated invoice data');
    }

    final invoice = result[0];
    final amountResidual = (invoice['amount_residual'] as num? ?? 0).toDouble();
    invoice['is_fully_paid'] = amountResidual < 1e-6;

    return invoice;
  }

  static Future<Payment> getPaymentDetails(int paymentId) async {
    final client = await clientProvider();
    if (client == null) {
      throw Exception('No active Odoo session');
    }

    try {
      final result = await client
          .callKw({
            'model': 'account.payment',
            'method': 'search_read',
            'args': [
              [
                ['id', '=', paymentId],
              ],
              [
                'id',
                'name',
                'amount',
                'state',
                'payment_type',
                'partner_type',
                'partner_id',
                'journal_id',
                'payment_method_line_id',
                'date',
                'company_id',
                'currency_id',
                'create_date',
                'write_date',
                'is_reconciled',
              ],
            ],
            'kwargs': {},
          })
          .timeout(_extendedTimeout);

      if (result.isEmpty) {
        throw Exception('Payment not found');
      }

      final paymentData = result[0] as Map<String, dynamic>;

      final reconciliationData = await _getPaymentReconciliationDetails(
        client,
        paymentId,
      );
      paymentData['reconciled_invoice_ids'] = reconciliationData['invoice_ids'];
      paymentData['reconciled_amount'] =
          reconciliationData['reconciled_amount'];

      return Payment.fromJson(paymentData);
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<Payment>> getInvoicePayments(int invoiceId) async {
    final client = await clientProvider();
    if (client == null) {
      throw Exception('No active Odoo session');
    }

    try {
      final reconciliationResult = await client
          .callKw({
            'model': 'account.partial.reconcile',
            'method': 'search_read',
            'args': [
              [
                '|',
                ['debit_move_id.move_id', '=', invoiceId],
                ['credit_move_id.move_id', '=', invoiceId],
              ],
              ['debit_move_id', 'credit_move_id', 'amount'],
            ],
            'kwargs': {},
          })
          .timeout(_extendedTimeout);

      Set<int> paymentIds = {};
      for (var reconcile in reconciliationResult) {
        final debitMoveId = reconcile['debit_move_id'] is List
            ? reconcile['debit_move_id'][0]
            : reconcile['debit_move_id'];
        final creditMoveId = reconcile['credit_move_id'] is List
            ? reconcile['credit_move_id'][0]
            : reconcile['credit_move_id'];

        final moveLineResult = await client
            .callKw({
              'model': 'account.move.line',
              'method': 'search_read',
              'args': [
                [
                  [
                    'id',
                    'in',
                    [debitMoveId, creditMoveId],
                  ],
                  ['move_id.move_type', '=', 'entry'],
                ],
                ['move_id'],
              ],
              'kwargs': {},
            })
            .timeout(_defaultTimeout);

        for (var moveLine in moveLineResult) {
          final moveId = moveLine['move_id'] is List
              ? moveLine['move_id'][0]
              : moveLine['move_id'];

          final paymentResult = await client
              .callKw({
                'model': 'account.payment',
                'method': 'search',
                'args': [
                  [
                    ['move_id', '=', moveId],
                  ],
                ],
                'kwargs': {'limit': 1},
              })
              .timeout(_extendedTimeout);

          if (paymentResult.isNotEmpty) {
            paymentIds.add(paymentResult[0]);
          }
        }
      }

      List<Payment> payments = [];
      for (int paymentId in paymentIds) {
        try {
          final payment = await getPaymentDetails(paymentId);
          payments.add(payment);
        } catch (e) {}
      }

      return payments;
    } catch (e) {
      return [];
    }
  }

  static Future<bool> reconcilePayment(int paymentId, int invoiceId) async {
    final client = await clientProvider();
    if (client == null) {
      throw Exception('No active Odoo session');
    }

    try {
      final paymentMoveLines = await client
          .callKw({
            'model': 'account.move.line',
            'method': 'search_read',
            'args': [
              [
                ['payment_id', '=', paymentId],
                ['account_id.account_type', '=', 'asset_receivable'],
                ['reconciled', '=', false],
              ],
              ['id', 'debit', 'credit', 'amount_residual'],
            ],
            'kwargs': {},
          })
          .timeout(_defaultTimeout);

      final invoiceMoveLines = await client
          .callKw({
            'model': 'account.move.line',
            'method': 'search_read',
            'args': [
              [
                ['move_id', '=', invoiceId],
                ['account_id.account_type', '=', 'asset_receivable'],
                ['reconciled', '=', false],
              ],
              ['id', 'debit', 'credit', 'amount_residual'],
            ],
            'kwargs': {},
          })
          .timeout(_defaultTimeout);

      if (paymentMoveLines.isEmpty || invoiceMoveLines.isEmpty) {
        throw Exception('No reconcilable move lines found');
      }

      final lineIds = [
        ...paymentMoveLines.map((line) => line['id']),
        ...invoiceMoveLines.map((line) => line['id']),
      ];

      await client
          .callKw({
            'model': 'account.move.line',
            'method': 'reconcile',
            'args': [lineIds],
            'kwargs': {},
          })
          .timeout(_extendedTimeout);

      // Reconciling moves the invoice from "in payment" to "paid".
      bus.paymentChanged(paymentId, kind: DataChangeKind.updated);
      bus.invoiceChanged(invoiceId);

      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<List<Payment>> getPaymentsWithReconciliation(
    int invoiceId,
  ) async {
    try {
      final client = await clientProvider();
      if (client == null) {
        throw PaymentError.network(
          message: 'No active Odoo session',
          action: PaymentErrorAction.retry,
        );
      }

      final payments = await getInvoicePayments(invoiceId);

      List<Payment> enhancedPayments = [];
      for (Payment payment in payments) {
        if (payment.id != null) {
          final reconciliationData = await _getDetailedReconciliationData(
            client,
            payment.id!,
          );
          final enhancedPayment = _enhancePaymentWithReconciliation(
            payment,
            reconciliationData,
          );
          enhancedPayments.add(enhancedPayment);
        }
      }

      return enhancedPayments;
    } catch (e) {
      if (e is PaymentError) rethrow;
      throw _handlePaymentError(e);
    }
  }

  static Future<ReconciliationStatus> checkReconciliationStatus(
    int paymentId,
  ) async {
    try {
      final client = await clientProvider();
      if (client == null) {
        throw PaymentError.network(
          message: 'No active Odoo session',
          action: PaymentErrorAction.retry,
        );
      }

      final paymentResult = await client
          .callKw({
            'model': 'account.payment',
            'method': 'search_read',
            'args': [
              [
                ['id', '=', paymentId],
              ],
              ['state', 'is_reconciled', 'reconciled_invoice_ids'],
            ],
            'kwargs': {},
          })
          .timeout(_defaultTimeout);

      if (paymentResult.isEmpty) {
        throw PaymentError.validation(
          message: 'Payment not found',
          action: PaymentErrorAction.refresh,
        );
      }

      final paymentData = paymentResult[0];
      final state = Payment.parseOdooState(
        paymentData['state'] is String ? paymentData['state'] : 'draft',
      );
      final isReconciled = paymentData['is_reconciled'] ?? false;

      ReconciliationStatus status;
      if (state == OdooPaymentState.draft ||
          state == OdooPaymentState.cancelled) {
        status = ReconciliationStatus.notRequired;
      } else if (state == OdooPaymentState.posted && !isReconciled) {
        final partialReconciliations = await _getPartialReconciliations(
          client,
          paymentId,
        );
        if (partialReconciliations.isNotEmpty) {
          status = ReconciliationStatus.partial;
        } else {
          status = ReconciliationStatus.pending;
        }
      } else if (isReconciled || state == OdooPaymentState.reconciled) {
        status = ReconciliationStatus.complete;
      } else {
        status = ReconciliationStatus.failed;
      }

      return status;
    } catch (e) {
      if (e is PaymentError) rethrow;
      throw _handlePaymentError(e);
    }
  }

  static Future<bool> requiresReconciliation(int invoiceId) async {
    try {
      final client = await clientProvider();
      if (client == null) {
        throw PaymentError.network(
          message: 'No active Odoo session',
          action: PaymentErrorAction.retry,
        );
      }

      final invoiceResult = await client
          .callKw({
            'model': 'account.move',
            'method': 'search_read',
            'args': [
              [
                ['id', '=', invoiceId],
              ],
              ['payment_state', 'amount_residual'],
            ],
            'kwargs': {},
          })
          .timeout(_defaultTimeout);

      if (invoiceResult.isEmpty) {
        throw PaymentError.validation(
          message: 'Invoice not found',
          action: PaymentErrorAction.refresh,
        );
      }

      final invoiceData = invoiceResult[0];
      final paymentState = invoiceData['payment_state'];

      if (paymentState == 'in_payment') {
        return true;
      }

      final payments = await getInvoicePayments(invoiceId);
      for (Payment payment in payments) {
        if (payment.id != null) {
          final reconciliationStatus = await checkReconciliationStatus(
            payment.id!,
          );
          if (reconciliationStatus == ReconciliationStatus.pending ||
              reconciliationStatus == ReconciliationStatus.partial) {
            return true;
          }
        }
      }

      return false;
    } catch (e) {
      if (e is PaymentError) rethrow;
      throw _handlePaymentError(e);
    }
  }

  static Future<Map<String, dynamic>> _detectPaymentBehaviorFromConfiguration(
    dynamic client,
  ) async {
    try {
      final autoReconcileConfig = await client
          .callKw({
            'model': 'ir.config_parameter',
            'method': 'search_read',
            'args': [
              [
                ['key', '=', 'account.auto.reconcile'],
              ],
              ['value'],
            ],
            'kwargs': {},
          })
          .timeout(_defaultTimeout);

      bool autoReconcile = false;
      if (autoReconcileConfig.isNotEmpty) {
        autoReconcile =
            autoReconcileConfig[0]['value']?.toString().toLowerCase() == 'true';
      }

      final paymentMethods = await client
          .callKw({
            'model': 'account.payment.method',
            'method': 'search_read',
            'args': [
              [],
              ['name', 'code', 'payment_type'],
            ],
            'kwargs': {'limit': 10},
          })
          .timeout(_defaultTimeout);

      bool hasDirectPaymentMethods = false;
      bool hasReconciliationRequiredMethods = false;

      for (var method in paymentMethods) {
        final code = method['code']?.toString() ?? '';
        final paymentType = method['payment_type']?.toString() ?? '';

        if (code.contains('check') ||
            code.contains('bank') ||
            paymentType == 'inbound') {
          hasReconciliationRequiredMethods = true;
        }

        if (code.contains('cash') || code.contains('manual')) {
          hasDirectPaymentMethods = true;
        }
      }

      if (autoReconcile && hasDirectPaymentMethods) {
        return {
          'marks_as_paid_directly': true,
          'requires_reconciliation': false,
          'payment_state_after_recording': 'paid',
        };
      } else if (hasReconciliationRequiredMethods) {
        return {
          'marks_as_paid_directly': false,
          'requires_reconciliation': true,
          'payment_state_after_recording': 'in_payment',
        };
      } else {
        return {
          'marks_as_paid_directly': false,
          'requires_reconciliation': true,
          'payment_state_after_recording': 'in_payment',
        };
      }
    } catch (e) {
      return {
        'marks_as_paid_directly': false,
        'requires_reconciliation': true,
        'payment_state_after_recording': 'in_payment',
      };
    }
  }

  static Future<Map<String, dynamic>> _getInvoiceDetails(
    dynamic client,
    int invoiceId,
  ) async {
    final result = await client
        .callKw({
          'model': 'account.move',
          'method': 'search_read',
          'args': [
            [
              ['id', '=', invoiceId],
            ],
            [
              'partner_id',
              'company_id',
              'amount_residual',
              'currency_id',
              'name',
              'payment_state',
              'state',
              'move_type',
            ],
          ],
          'kwargs': {},
        })
        .timeout(_defaultTimeout);

    if (result.isEmpty) {
      throw Exception('Invoice not found');
    }

    return result[0];
  }

  static Future<Map<String, dynamic>> _getPaymentReconciliationDetails(
    dynamic client,
    int paymentId,
  ) async {
    try {
      final result = await client
          .callKw({
            'model': 'account.partial.reconcile',
            'method': 'search_read',
            'args': [
              [
                '|',
                ['debit_move_id.payment_id', '=', paymentId],
                ['credit_move_id.payment_id', '=', paymentId],
              ],
              ['debit_move_id', 'credit_move_id', 'amount'],
            ],
            'kwargs': {},
          })
          .timeout(_defaultTimeout);

      Set<int> invoiceIds = {};
      double reconciledAmount = 0.0;

      for (var reconcile in result) {
        reconciledAmount += (reconcile['amount'] as double? ?? 0.0);

        final debitMoveId = reconcile['debit_move_id'] is List
            ? reconcile['debit_move_id'][0]
            : reconcile['debit_move_id'];
        final creditMoveId = reconcile['credit_move_id'] is List
            ? reconcile['credit_move_id'][0]
            : reconcile['credit_move_id'];

        final moveLineResult = await client
            .callKw({
              'model': 'account.move.line',
              'method': 'search_read',
              'args': [
                [
                  [
                    'id',
                    'in',
                    [debitMoveId, creditMoveId],
                  ],
                  ['move_id.move_type', '=', 'out_invoice'],
                ],
                ['move_id'],
              ],
              'kwargs': {},
            })
            .timeout(_defaultTimeout);

        for (var moveLine in moveLineResult) {
          final moveId = moveLine['move_id'] is List
              ? moveLine['move_id'][0]
              : moveLine['move_id'];
          invoiceIds.add(moveId);
        }
      }

      return {
        'invoice_ids': invoiceIds.toList(),
        'reconciled_amount': reconciledAmount,
      };
    } catch (e) {
      return {'invoice_ids': <int>[], 'reconciled_amount': 0.0};
    }
  }

  static Future<Map<String, dynamic>> _getDetailedReconciliationData(
    dynamic client,
    int paymentId,
  ) async {
    try {
      final reconcileResult = await client
          .callKw({
            'model': 'account.partial.reconcile',
            'method': 'search_read',
            'args': [
              [
                '|',
                ['debit_move_id.payment_id', '=', paymentId],
                ['credit_move_id.payment_id', '=', paymentId],
              ],
              ['debit_move_id', 'credit_move_id', 'amount', 'create_date'],
            ],
            'kwargs': {},
          })
          .timeout(_defaultTimeout);

      List<ReconciliationLine> reconciliationLines = [];
      Set<int> invoiceIds = {};
      double totalReconciled = 0.0;

      for (var reconcile in reconcileResult) {
        final amount = (reconcile['amount'] ?? 0.0).toDouble();
        totalReconciled += amount;

        final debitMoveId = reconcile['debit_move_id'] is List
            ? reconcile['debit_move_id'][0]
            : reconcile['debit_move_id'];
        final creditMoveId = reconcile['credit_move_id'] is List
            ? reconcile['credit_move_id'][0]
            : reconcile['credit_move_id'];

        final moveLineResult = await client
            .callKw({
              'model': 'account.move.line',
              'method': 'search_read',
              'args': [
                [
                  [
                    'id',
                    'in',
                    [debitMoveId, creditMoveId],
                  ],
                  ['move_id.move_type', '=', 'out_invoice'],
                ],
                ['move_id'],
              ],
              'kwargs': {},
            })
            .timeout(_defaultTimeout);

        for (var moveLine in moveLineResult) {
          final invoiceId = moveLine['move_id'] is List
              ? moveLine['move_id'][0]
              : moveLine['move_id'];
          invoiceIds.add(invoiceId);

          reconciliationLines.add(
            ReconciliationLine(
              paymentId: paymentId,
              invoiceId: invoiceId,
              amount: amount,
              reconcileDate: reconcile['create_date'] != null
                  ? DateTime.parse(reconcile['create_date'])
                  : null,
              isFullReconciliation: true,
            ),
          );
        }
      }

      return {
        'reconciliation_lines': reconciliationLines,
        'invoice_ids': invoiceIds.toList(),
        'total_reconciled': totalReconciled,
        'reconciliation_status': reconciliationLines.isNotEmpty
            ? ReconciliationStatus.complete.name
            : ReconciliationStatus.pending.name,
      };
    } catch (e) {
      return {
        'reconciliation_lines': <ReconciliationLine>[],
        'invoice_ids': <int>[],
        'total_reconciled': 0.0,
        'reconciliation_status': ReconciliationStatus.notRequired.name,
      };
    }
  }

  static Payment _enhancePaymentWithReconciliation(
    Payment payment,
    Map<String, dynamic> reconciliationData,
  ) {
    final reconciliationLines =
        reconciliationData['reconciliation_lines'] as List<ReconciliationLine>;
    final reconciliationStatus = Payment.parseReconciliationStatus(
      reconciliationData['reconciliation_status'],
    );

    return Payment(
      id: payment.id,
      name: payment.name,
      amount: payment.amount,
      state: payment.state,
      paymentType: payment.paymentType,
      partnerType: payment.partnerType,
      partnerId: payment.partnerId,
      partnerName: payment.partnerName,
      journalId: payment.journalId,
      journalName: payment.journalName,
      paymentMethodLineId: payment.paymentMethodLineId,
      paymentMethodName: payment.paymentMethodName,
      paymentDate: payment.paymentDate,
      communication: payment.communication,
      reference: payment.reference,
      companyId: payment.companyId,
      currencyId: payment.currencyId,
      createdAt: payment.createdAt,
      updatedAt: payment.updatedAt,
      isReconciled: payment.isReconciled,
      reconciledInvoiceIds:
          reconciliationData['invoice_ids'] ?? payment.reconciledInvoiceIds,
      reconciledAmount:
          reconciliationData['total_reconciled'] ?? payment.reconciledAmount,
      reconciliationStatus: reconciliationStatus,
      reconciliationLines: reconciliationLines,
      reconciliationDate: reconciliationLines.isNotEmpty
          ? reconciliationLines.first.reconcileDate
          : null,
      requiresManualReconciliation:
          reconciliationStatus == ReconciliationStatus.pending ||
          reconciliationStatus == ReconciliationStatus.partial,
      odooState: payment.odooState,
      odooReference: payment.odooReference,
      odooMetadata: payment.odooMetadata,
    );
  }

  static Future<List<Map<String, dynamic>>> _getPartialReconciliations(
    dynamic client,
    int paymentId,
  ) async {
    try {
      final result = await client
          .callKw({
            'model': 'account.partial.reconcile',
            'method': 'search_read',
            'args': [
              [
                '|',
                ['debit_move_id.payment_id', '=', paymentId],
                ['credit_move_id.payment_id', '=', paymentId],
              ],
              ['amount', 'create_date'],
            ],
            'kwargs': {},
          })
          .timeout(_defaultTimeout);

      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      return [];
    }
  }

  static Future<Invoice> _getSafeInvoiceData(int invoiceId) async {
    try {
      final client = await clientProvider();
      if (client != null) {
        final result = await client
            .callKw({
              'model': 'account.move',
              'method': 'search_read',
              'args': [
                [
                  ['id', '=', invoiceId],
                ],
                ['id', 'name', 'partner_id', 'amount_total', 'state'],
              ],
              'kwargs': {},
            })
            .timeout(_defaultTimeout);

        if (result.isNotEmpty) {
          return Invoice.fromJson(result[0]);
        }
      }
    } catch (e) {}

    return Invoice(
      id: invoiceId,
      name: 'Unknown Invoice',
      customerName: 'Unknown Customer',
      lines: [],
      taxLines: [],
      subtotal: 0.0,
      taxAmount: 0.0,
      total: 0.0,
      amountPaid: 0.0,
      amountResidual: 0.0,
      status: 'unknown',
      paymentState: 'unknown',
    );
  }

  static PaymentError _handlePaymentError(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('timeout') ||
        errorString.contains('timeoutexception') ||
        errorString.contains('future not completed') ||
        errorString.contains('connection') ||
        errorString.contains('network') ||
        errorString.contains('socket')) {
      return PaymentError.network(
        message:
            'Connection timeout. Please check your internet connection and try again.',
        action: PaymentErrorAction.retry,
        context: {'original_error': error.toString(), 'timeout': true},
      );
    }

    if (errorString.contains('session') ||
        errorString.contains('authentication') ||
        errorString.contains('login') ||
        errorString.contains('unauthorized')) {
      return PaymentError.network(
        message: 'Session expired. Please log in again.',
        action: PaymentErrorAction.retry,
        context: {'requires_login': true},
      );
    }

    if (errorString.contains('invalid field') ||
        errorString.contains('keyerror') ||
        errorString.contains('payment_id') ||
        errorString.contains('field does not exist')) {
      return PaymentError.sync(
        message:
            'Data synchronization issue detected. The app will attempt to use an alternative method.',
        action: PaymentErrorAction.refresh,
        context: {'field_error': true, 'original_error': error.toString()},
      );
    }

    if (errorString.contains('validation') ||
        errorString.contains('invalid') ||
        errorString.contains('constraint') ||
        errorString.contains('required')) {
      return PaymentError.validation(
        message: 'Invalid payment data. Please check your input and try again.',
        action: PaymentErrorAction.correct,
        context: {'validation_error': true},
      );
    }

    if (errorString.contains('reconcile') ||
        errorString.contains('reconciliation') ||
        errorString.contains('move line')) {
      return PaymentError.sync(
        message:
            'Payment reconciliation failed. The payment may still be created but requires manual reconciliation in Odoo.',
        action: PaymentErrorAction.refresh,
        context: {'reconciliation_error': true},
      );
    }

    if (errorString.contains('access') ||
        errorString.contains('permission') ||
        errorString.contains('forbidden')) {
      return PaymentError.validation(
        message:
            'Insufficient permissions to perform this action. Please contact your administrator.',
        action: PaymentErrorAction.contact,
        context: {'permission_error': true},
      );
    }

    if (errorString.contains('odoo server error') ||
        errorString.contains('internal server error')) {
      return PaymentError.network(
        message: 'Server error occurred. Please try again in a few moments.',
        action: PaymentErrorAction.retry,
        context: {'server_error': true},
      );
    }

    return PaymentError.unknown(
      message:
          'An unexpected error occurred. Please try again or contact support if the problem persists.',
      action: PaymentErrorAction.contact,
      context: {'original_error': error.toString()},
    );
  }
}
