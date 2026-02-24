import 'package:intl/intl.dart';
import '../models/payment.dart';
import '../models/invoice.dart';
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

class PaymentService {
  static const Duration _defaultTimeout = Duration(seconds: 45);
  static const Duration _extendedTimeout = Duration(seconds: 60);

  static Map<String, OdooPaymentBehavior>? _odooBehaviorCache;

  static Future<OdooPaymentBehavior> detectOdooPaymentBehavior() async {
    if (_odooBehaviorCache != null && _odooBehaviorCache!.isNotEmpty) {
      final cached = _odooBehaviorCache!.values.first;
      return cached;
    }

    final client = await OdooSessionManager.getClient();
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

  static Future<PaymentResult> _executeEnhancedWorkflow(
    dynamic client,
    int invoiceId,
    double amount,
    PaymentMethodData paymentMethod,
    DateTime paymentDate,
    PaymentOptions options,
  ) async {
    try {
      final odooBehavior = await detectOdooPaymentBehavior();

      await _validatePaymentData(client, invoiceId, amount, paymentMethod);

      final invoiceData = await _getInvoiceDetails(client, invoiceId);
      final paymentContext = await _buildPaymentContext(
        client,
        invoiceData,
        paymentMethod,
      );

      final paymentResult = await _executeOdooPaymentWizardWithBehavior(
        client,
        invoiceId: invoiceId,
        amount: amount,
        paymentDate: paymentDate,
        paymentMethod: paymentMethod,
        context: paymentContext,
        options: options,
        odooBehavior: odooBehavior,
      );

      final updatedInvoice = await _getUpdatedInvoiceWithPayments(
        client,
        invoiceId,
      );

      Payment? payment;
      if (paymentResult['payment_id'] != null) {
        payment = await getPaymentDetails(paymentResult['payment_id']);
      }

      return PaymentResult(
        success: true,
        payment: payment,
        updatedInvoice: updatedInvoice,
        warnings: paymentResult['warnings'] ?? [],
      );
    } catch (e) {
      rethrow;
    }
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
      onTimeout: () {
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
      },
    );
  }

  static Future<PaymentResult> _createPaymentWithTimeout({
    required int invoiceId,
    required double amount,
    required PaymentMethodData paymentMethod,
    required DateTime paymentDate,
    PaymentOptions? options,
  }) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw PaymentError.network(
          message: 'No active Odoo session. Please log in again.',
          action: PaymentErrorAction.retry,
        );
      }

      try {
        final paymentResult = await createPayment(
          invoiceId: invoiceId,
          amount: amount,
          paymentMethod: paymentMethod.type,
          paymentDate: paymentDate,
          memo: options?.memo,
          paymentDifferenceHandling:
              options?.differenceHandling == PaymentDifferenceHandling.writeOff
              ? 'reconcile'
              : 'open',
          writeoffAccountId: options?.writeOffConfig?.accountId,
          writeoffLabel: options?.writeOffConfig?.label,
        );

        if (paymentResult['success'] == true) {
          final updatedInvoice = await _getSafeInvoiceData(invoiceId);

          return PaymentResult(
            success: true,
            payment: null,
            updatedInvoice: updatedInvoice,
            warnings: [],
          );
        } else {
          throw Exception(paymentResult['error'] ?? 'Payment creation failed');
        }
      } catch (e) {
        return await _executeEnhancedWorkflow(
          client,
          invoiceId,
          amount,
          paymentMethod,
          paymentDate,
          options ?? PaymentOptions(),
        );
      }
    } catch (e) {
      if (e is PaymentError) {
        rethrow;
      }

      return PaymentResult(
        success: false,
        updatedInvoice: await _getSafeInvoiceData(invoiceId),
        errorMessage: _handlePaymentError(e).message,
      );
    }
  }

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
    final client = await OdooSessionManager.getClient();
    if (client == null) {
      throw Exception('No active Odoo session');
    }

    try {
      final invoiceData = await _getInvoiceDetails(client, invoiceId);
      final partnerId = invoiceData['partner_id'] is List
          ? invoiceData['partner_id'][0]
          : invoiceData['partner_id'];
      final companyId = invoiceData['company_id'] is List
          ? invoiceData['company_id'][0]
          : invoiceData['company_id'] ?? 1;

      final journalData = await _findPaymentJournal(
        client,
        companyId,
        paymentMethod,
      );
      final paymentMethodLineData = await _findPaymentMethodLine(
        client,
        journalData['id'],
        companyId,
      );

      final paymentResult = await _createPaymentViaWizard(
        client,
        invoiceId: invoiceId,
        amount: amount,
        paymentDate: paymentDate,
        journalId: journalData['id'],
        paymentMethodLineId: paymentMethodLineData['id'],
        partnerId: partnerId,
        companyId: companyId,
        memo: memo ?? invoiceData['name']?.toString() ?? '',
        paymentDifferenceHandling: paymentDifferenceHandling,
        writeoffAccountId: writeoffAccountId,
        writeoffLabel: writeoffLabel,
      );

      final updatedInvoice = await _getUpdatedInvoiceStatus(
        client,
        invoiceId,
        companyId,
      );

      return {
        'success': true,
        'payment_id': paymentResult['payment_id'],
        'payment_state': paymentResult['payment_state'],
        'updated_invoice': updatedInvoice,
      };
    } catch (e) {
      rethrow;
    }
  }

  static Future<Payment> getPaymentDetails(int paymentId) async {
    final client = await OdooSessionManager.getClient();
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
    final client = await OdooSessionManager.getClient();
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
    final client = await OdooSessionManager.getClient();
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

      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<List<Payment>> getPaymentsWithReconciliation(
    int invoiceId,
  ) async {
    try {
      final client = await OdooSessionManager.getClient();
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
      final client = await OdooSessionManager.getClient();
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
      final state = paymentData['state'];
      final isReconciled = paymentData['is_reconciled'] ?? false;

      ReconciliationStatus status;
      if (state == 'draft' || state == 'cancelled') {
        status = ReconciliationStatus.notRequired;
      } else if (state == 'posted' && !isReconciled) {
        final partialReconciliations = await _getPartialReconciliations(
          client,
          paymentId,
        );
        if (partialReconciliations.isNotEmpty) {
          status = ReconciliationStatus.partial;
        } else {
          status = ReconciliationStatus.pending;
        }
      } else if (isReconciled) {
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
      final client = await OdooSessionManager.getClient();
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

  static Future<Map<String, dynamic>> _findPaymentJournal(
    dynamic client,
    int companyId,
    String paymentMethod,
  ) async {
    final journalType = paymentMethod.toLowerCase() == 'cash' ? 'cash' : 'bank';

    final result = await client
        .callKw({
          'model': 'account.journal',
          'method': 'search_read',
          'args': [
            [
              ['type', '=', journalType],
              ['active', '=', true],
              ['company_id', '=', companyId],
            ],
            ['id', 'name', 'type', 'company_id'],
          ],
          'kwargs': {'limit': 1},
        })
        .timeout(_defaultTimeout);

    if (result.isEmpty) {
      throw Exception('No $journalType journal found for company $companyId');
    }

    return result[0];
  }

  static Future<Map<String, dynamic>> _findPaymentMethodLine(
    dynamic client,
    int journalId,
    int companyId,
  ) async {
    final result = await client
        .callKw({
          'model': 'account.payment.method.line',
          'method': 'search_read',
          'args': [
            [
              ['journal_id', '=', journalId],
              ['payment_type', '=', 'inbound'],
            ],
            ['id', 'name', 'payment_method_id'],
          ],
          'kwargs': {'limit': 1},
        })
        .timeout(_defaultTimeout);

    if (result.isEmpty) {
      throw Exception('No payment method line found for journal $journalId');
    }

    return result[0];
  }

  static Future<Map<String, dynamic>> _createPaymentViaWizard(
    dynamic client, {
    required int invoiceId,
    required double amount,
    required DateTime paymentDate,
    required int journalId,
    required int paymentMethodLineId,
    required int partnerId,
    required int companyId,
    required String memo,
    String paymentDifferenceHandling = 'open',
    int? writeoffAccountId,
    String? writeoffLabel,
  }) async {
    final wizardData = {
      'amount': amount,
      'payment_date': DateFormat('yyyy-MM-dd').format(paymentDate),
      'journal_id': journalId,
      'payment_method_line_id': paymentMethodLineId,

      'partner_id': partnerId,
      'partner_type': 'customer',
      'payment_type': 'inbound',
      'company_id': companyId,
      'group_payment': false,
      'payment_difference_handling': paymentDifferenceHandling,
    };

    if (paymentDifferenceHandling == 'reconcile' && writeoffAccountId != null) {
      wizardData['writeoff_account_id'] = writeoffAccountId;
      wizardData['writeoff_label'] = writeoffLabel ?? 'Payment Difference';
    }

    final canCreatePaymentRegister = await PermissionService.instance.canCreate(
      'account.payment.register',
    );
    if (!canCreatePaymentRegister) {
      throw Exception('You do not have permission to register payments.');
    }
    final wizardId = await client
        .callKw({
          'model': 'account.payment.register',
          'method': 'create',
          'args': [wizardData],
          'kwargs': {
            'context': {
              'active_model': 'account.move',
              'active_ids': [invoiceId],
              'default_payment_type': 'inbound',
              'default_partner_type': 'customer',
              'company_id': companyId,
              'allowed_company_ids': [companyId],
            },
          },
        })
        .timeout(_defaultTimeout);

    final result = await client
        .callKw({
          'model': 'account.payment.register',
          'method': 'action_create_payments',
          'args': [
            [wizardId],
          ],
          'kwargs': {
            'context': {
              'active_model': 'account.move',
              'active_ids': [invoiceId],
              'company_id': companyId,
              'allowed_company_ids': [companyId],
            },
          },
        })
        .timeout(_defaultTimeout);

    int? paymentId;
    if (result is Map && result['res_id'] != null) {
      paymentId = result['res_id'];
    }

    await Future.delayed(const Duration(milliseconds: 500));

    return {
      'payment_id': paymentId,
      'payment_state': 'posted',
      'wizard_result': result,
    };
  }

  static Future<Map<String, dynamic>> _getUpdatedInvoiceStatus(
    dynamic client,
    int invoiceId,
    int companyId,
  ) async {
    await Future.delayed(const Duration(milliseconds: 1000));

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
              'company_id': companyId,
              'allowed_company_ids': [companyId],
            },
          },
        })
        .timeout(_defaultTimeout);

    if (result.isEmpty) {
      throw Exception('Failed to fetch updated invoice data');
    }

    final invoice = result[0];
    final amountResidual = invoice['amount_residual'] as double? ?? 0.0;
    invoice['is_fully_paid'] = amountResidual <= 0.01;

    return invoice;
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

  static Future<void> _validatePaymentData(
    dynamic client,
    int invoiceId,
    double amount,
    PaymentMethodData paymentMethod,
  ) async {
    if (amount <= 0) {
      throw PaymentError.validation(
        message: 'Payment amount must be greater than zero',
        field: 'amount',
        action: PaymentErrorAction.correct,
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
            ['state', 'amount_residual', 'move_type'],
          ],
          'kwargs': {},
        })
        .timeout(_defaultTimeout);

    if (invoiceResult.isEmpty) {
      throw PaymentError.validation(
        message: 'Invoice not found',
        field: 'invoiceId',
        action: PaymentErrorAction.refresh,
      );
    }

    final invoice = invoiceResult[0];
    if (invoice['state'] != 'posted') {
      throw PaymentError.validation(
        message: 'Invoice must be posted before payment can be made',
        action: PaymentErrorAction.correct,
      );
    }

    final amountResidual = (invoice['amount_residual'] ?? 0.0).toDouble();
    if (amount > amountResidual) {
      throw PaymentError.validation(
        message:
            'Payment amount cannot exceed remaining balance of \$${amountResidual.toStringAsFixed(2)}',
        field: 'amount',
        action: PaymentErrorAction.correct,
      );
    }
  }

  static Future<Map<String, dynamic>> _buildPaymentContext(
    dynamic client,
    Map<String, dynamic> invoiceData,
    PaymentMethodData paymentMethod,
  ) async {
    final partnerId = invoiceData['partner_id'] is List
        ? invoiceData['partner_id'][0]
        : invoiceData['partner_id'];
    final companyId = invoiceData['company_id'] is List
        ? invoiceData['company_id'][0]
        : invoiceData['company_id'] ?? 1;

    return {
      'partner_id': partnerId,
      'company_id': companyId,
      'active_model': 'account.move',
      'active_ids': [invoiceData['id']],
      'default_payment_type': 'inbound',
      'default_partner_type': 'customer',
      'allowed_company_ids': [companyId],
    };
  }

  static Future<Map<String, dynamic>> _executeOdooPaymentWizardWithBehavior(
    dynamic client, {
    required int invoiceId,
    required double amount,
    required DateTime paymentDate,
    required PaymentMethodData paymentMethod,
    required Map<String, dynamic> context,
    required PaymentOptions options,
    required OdooPaymentBehavior odooBehavior,
  }) async {
    final journalData = await _findPaymentJournal(
      client,
      context['company_id'],
      paymentMethod.type,
    );
    final paymentMethodLineData = await _findPaymentMethodLine(
      client,
      journalData['id'],
      context['company_id'],
    );

    final wizardData = {
      'amount': amount,
      'payment_date': DateFormat('yyyy-MM-dd').format(paymentDate),
      'journal_id': journalData['id'],
      'payment_method_line_id': paymentMethodLineData['id'],
      'partner_id': context['partner_id'],
      'partner_type': 'customer',
      'payment_type': 'inbound',
      'company_id': context['company_id'],
      'group_payment': false,
      'payment_difference_handling':
          options.differenceHandling == PaymentDifferenceHandling.writeOff
          ? 'reconcile'
          : 'open',
    };

    if (odooBehavior.requiresReconciliation &&
        options.differenceHandling == PaymentDifferenceHandling.keepOpen) {}

    if (options.differenceHandling == PaymentDifferenceHandling.writeOff &&
        options.writeOffConfig != null) {
      wizardData['writeoff_account_id'] = options.writeOffConfig!.accountId;
      wizardData['writeoff_label'] = options.writeOffConfig!.label;
    }

    final canCreatePaymentRegister = await PermissionService.instance.canCreate(
      'account.payment.register',
    );
    if (!canCreatePaymentRegister) {
      throw Exception('You do not have permission to register payments.');
    }
    final wizardId = await client
        .callKw({
          'model': 'account.payment.register',
          'method': 'create',
          'args': [wizardData],
          'kwargs': {'context': context},
        })
        .timeout(_defaultTimeout);

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
    List<String> warnings = [];

    if (result is Map) {
      paymentId = result['res_id'];
      if (result['warning'] != null) {
        warnings.add(result['warning'].toString());
      }
    }

    await Future.delayed(const Duration(milliseconds: 500));

    if (odooBehavior.marksAsPaidDirectly) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    return {
      'payment_id': paymentId,
      'payment_state': odooBehavior.paymentStateAfterRecording,
      'wizard_result': result,
      'warnings': warnings,
      'odoo_behavior': {
        'marks_as_paid_directly': odooBehavior.marksAsPaidDirectly,
        'requires_reconciliation': odooBehavior.requiresReconciliation,
      },
    };
  }

  static Future<Invoice> _getUpdatedInvoiceWithPayments(
    dynamic client,
    int invoiceId,
  ) async {
    await Future.delayed(const Duration(milliseconds: 1000));

    final result = await client
        .callKw({
          'model': 'account.move',
          'method': 'search_read',
          'args': [
            [
              ['id', '=', invoiceId],
            ],
            [
              'id',
              'name',
              'partner_id',
              'amount_total',
              'amount_residual',
              'amount_tax',
              'amount_untaxed',
              'state',
              'payment_state',
              'invoice_date',
              'invoice_date_due',
              'invoice_origin',
              'is_move_sent',
              'create_date',
              'write_date',
              'currency_id',
            ],
          ],
          'kwargs': {},
        })
        .timeout(_defaultTimeout);

    if (result.isEmpty) {
      throw PaymentError.sync(
        message: 'Failed to fetch updated invoice data',
        action: PaymentErrorAction.refresh,
      );
    }

    final invoiceData = result[0];

    final payments = await getPaymentsWithReconciliation(invoiceId);
    invoiceData['payments'] = payments.map((p) => p.toJson()).toList();

    return Invoice.fromJson(invoiceData);
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
      final client = await OdooSessionManager.getClient();
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
        errorString.contains('internal server error') ||
        errorString.contains('500')) {
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
