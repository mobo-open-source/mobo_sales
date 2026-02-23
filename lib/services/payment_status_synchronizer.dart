import 'dart:async';
import '../models/payment.dart';
import 'odoo_session_manager.dart';

class PaymentStatusUpdate {
  final int invoiceId;
  final String previousPaymentState;
  final String currentPaymentState;
  final List<Payment> payments;
  final DateTime timestamp;
  final bool requiresReconciliation;

  PaymentStatusUpdate({
    required this.invoiceId,
    required this.previousPaymentState,
    required this.currentPaymentState,
    required this.payments,
    required this.timestamp,
    required this.requiresReconciliation,
  });
}

class PaymentStatusSynchronizer {
  static const Duration _defaultTimeout = Duration(seconds: 45);
  static const Duration _extendedTimeout = Duration(seconds: 60);
  static const Duration _watchInterval = Duration(seconds: 15);
  static const Duration _debounceDelay = Duration(milliseconds: 500);

  static final Map<int, StreamController<PaymentStatusUpdate>>
  _statusControllers = {};
  static final Map<int, Timer> _watchTimers = {};
  static final Map<int, String> _lastKnownStates = {};

  static final Map<int, Future<PaymentStatusUpdate>?> _activeSyncs = {};
  static final Map<int, Timer> _debounceTimers = {};
  static final Map<int, PaymentStatusUpdate> _cachedUpdates = {};
  static const Duration _cacheValidDuration = Duration(seconds: 5);

  static void clearAllCaches() {
    _activeSyncs.clear();
    _debounceTimers.forEach((key, timer) => timer.cancel());
    _debounceTimers.clear();
    _cachedUpdates.clear();
  }

  static Future<PaymentStatusUpdate> syncInvoicePaymentStatus(
    int invoiceId,
  ) async {
    if (_activeSyncs[invoiceId] != null) {
      return await _activeSyncs[invoiceId]!;
    }

    final cachedUpdate = _cachedUpdates[invoiceId];
    if (cachedUpdate != null &&
        DateTime.now().difference(cachedUpdate.timestamp) <
            _cacheValidDuration) {
      return cachedUpdate;
    }

    final syncFuture = _performPaymentStatusSync(invoiceId);
    _activeSyncs[invoiceId] = syncFuture;

    try {
      final result = await syncFuture;

      _cachedUpdates[invoiceId] = result;

      return result;
    } finally {
      _activeSyncs[invoiceId] = null;
    }
  }

  static Future<PaymentStatusUpdate> _performPaymentStatusSync(
    int invoiceId,
  ) async {
    final client = await OdooSessionManager.getClient();
    if (client == null) {
      throw Exception('No active Odoo session');
    }

    try {
      final invoiceResult = await client
          .callKw({
            'model': 'account.move',
            'method': 'search_read',
            'args': [
              [
                ['id', '=', invoiceId],
              ],
              ['payment_state', 'amount_residual', 'amount_total', 'state'],
            ],
            'kwargs': {},
          })
          .timeout(_defaultTimeout);

      if (invoiceResult.isEmpty) {
        throw Exception('Invoice $invoiceId not found');
      }

      final invoiceData = invoiceResult[0] as Map<String, dynamic>;
      final currentPaymentState = invoiceData['payment_state'] ?? 'not_paid';
      final previousPaymentState = _lastKnownStates[invoiceId] ?? 'unknown';

      final payments = await _getInvoicePaymentsWithReconciliationSafe(
        client,
        invoiceId,
      );

      final requiresReconciliation = payments.any(
        (p) => p.requiresReconciliation,
      );

      _lastKnownStates[invoiceId] = currentPaymentState;

      final update = PaymentStatusUpdate(
        invoiceId: invoiceId,
        previousPaymentState: previousPaymentState,
        currentPaymentState: currentPaymentState,
        payments: payments,
        timestamp: DateTime.now(),
        requiresReconciliation: requiresReconciliation,
      );

      _notifyWatchers(invoiceId, update);

      return update;
    } catch (e) {
      rethrow;
    }
  }

  static Stream<PaymentStatusUpdate> watchPaymentStatus(int invoiceId) {
    if (!_statusControllers.containsKey(invoiceId)) {
      _statusControllers[invoiceId] =
          StreamController<PaymentStatusUpdate>.broadcast();

      _startWatching(invoiceId);
    }

    return _statusControllers[invoiceId]!.stream;
  }

  static void stopWatchingPaymentStatus(int invoiceId) {
    _watchTimers[invoiceId]?.cancel();
    _watchTimers.remove(invoiceId);

    _debounceTimers[invoiceId]?.cancel();
    _debounceTimers.remove(invoiceId);

    _statusControllers[invoiceId]?.close();
    _statusControllers.remove(invoiceId);

    _lastKnownStates.remove(invoiceId);
    _activeSyncs.remove(invoiceId);
    _cachedUpdates.remove(invoiceId);
  }

  static Future<List<PaymentStatusUpdate>> syncMultipleInvoiceStatuses(
    List<int> invoiceIds,
  ) async {
    if (invoiceIds.isEmpty) return [];

    final client = await OdooSessionManager.getClient();
    if (client == null) {
      throw Exception('No active Odoo session');
    }

    try {
      final invoiceResults = await client
          .callKw({
            'model': 'account.move',
            'method': 'search_read',
            'args': [
              [
                ['id', 'in', invoiceIds],
              ],
              [
                'id',
                'payment_state',
                'amount_residual',
                'amount_total',
                'state',
              ],
            ],
            'kwargs': {},
          })
          .timeout(_defaultTimeout);

      List<PaymentStatusUpdate> updates = [];

      for (var invoiceData in invoiceResults) {
        final invoiceId = invoiceData['id'] as int;
        final currentPaymentState = invoiceData['payment_state'] ?? 'not_paid';
        final previousPaymentState = _lastKnownStates[invoiceId] ?? 'unknown';

        try {
          final payments = await _getInvoicePaymentsWithReconciliation(
            client,
            invoiceId,
          );
          final requiresReconciliation = payments.any(
            (p) => p.requiresReconciliation,
          );

          _lastKnownStates[invoiceId] = currentPaymentState;

          final update = PaymentStatusUpdate(
            invoiceId: invoiceId,
            previousPaymentState: previousPaymentState,
            currentPaymentState: currentPaymentState,
            payments: payments,
            timestamp: DateTime.now(),
            requiresReconciliation: requiresReconciliation,
          );

          updates.add(update);

          _notifyWatchers(invoiceId, update);
        } catch (e) {}
      }

      return updates;
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> resolveStatusConflict(
    int invoiceId,
    String localPaymentState,
    String remotePaymentState,
  ) async {
    try {
      final update = await syncInvoicePaymentStatus(invoiceId);

      _notifyWatchers(invoiceId, update);
    } catch (e) {
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getDetailedPaymentStatus(
    int invoiceId,
  ) async {
    final client = await OdooSessionManager.getClient();
    if (client == null) {
      throw Exception('No active Odoo session');
    }

    try {
      final invoiceResult = await client
          .callKw({
            'model': 'account.move',
            'method': 'search_read',
            'args': [
              [
                ['id', '=', invoiceId],
              ],
              [
                'payment_state',
                'amount_residual',
                'amount_total',
                'amount_paid',
                'state',
                'invoice_date',
                'invoice_date_due',
                'name',
              ],
            ],
            'kwargs': {},
          })
          .timeout(_defaultTimeout);

      if (invoiceResult.isEmpty) {
        throw Exception('Invoice $invoiceId not found');
      }

      final invoiceData = invoiceResult[0] as Map<String, dynamic>;

      final payments = await _getInvoicePaymentsWithReconciliation(
        client,
        invoiceId,
      );

      final totalPaid = payments
          .where((p) => p.isFullyReconciled)
          .fold(0.0, (sum, p) => sum + p.amount);

      final totalPending = payments
          .where((p) => p.isInPayment)
          .fold(0.0, (sum, p) => sum + p.amount);

      final totalAmount = (invoiceData['amount_total'] ?? 0.0).toDouble();
      final remainingAmount = (invoiceData['amount_residual'] ?? 0.0)
          .toDouble();

      return {
        'invoice_id': invoiceId,
        'payment_state': invoiceData['payment_state'],
        'invoice_state': invoiceData['state'],
        'total_amount': totalAmount,
        'amount_paid': totalPaid,
        'amount_pending': totalPending,
        'amount_remaining': remainingAmount,
        'payments': payments.map((p) => p.toJson()).toList(),
        'requires_reconciliation': payments.any(
          (p) => p.requiresReconciliation,
        ),
        'reconciliation_count': payments
            .where((p) => p.requiresReconciliation)
            .length,
        'last_sync': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      rethrow;
    }
  }

  static void dispose() {
    for (var timer in _watchTimers.values) {
      timer.cancel();
    }
    _watchTimers.clear();

    for (var timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();

    for (var controller in _statusControllers.values) {
      controller.close();
    }
    _statusControllers.clear();

    _lastKnownStates.clear();
    _activeSyncs.clear();
    _cachedUpdates.clear();
  }

  static void clearCache(int invoiceId) {
    _cachedUpdates.remove(invoiceId);
    _activeSyncs.remove(invoiceId);
  }

  static void _startWatching(int invoiceId) {
    _watchTimers[invoiceId] = Timer.periodic(_watchInterval, (timer) async {
      try {
        _debouncedSync(invoiceId);
      } catch (e) {}
    });
  }

  static void _debouncedSync(int invoiceId) {
    _debounceTimers[invoiceId]?.cancel();

    _debounceTimers[invoiceId] = Timer(_debounceDelay, () async {
      try {
        await syncInvoicePaymentStatus(invoiceId);
      } catch (e) {}
    });
  }

  static void _notifyWatchers(int invoiceId, PaymentStatusUpdate update) {
    final controller = _statusControllers[invoiceId];
    if (controller != null && !controller.isClosed) {
      controller.add(update);
    }
  }

  static Future<List<Payment>> _getInvoicePaymentsWithReconciliation(
    dynamic client,
    int invoiceId,
  ) async {
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
              ['debit_move_id', 'credit_move_id', 'amount', 'create_date'],
            ],
            'kwargs': {},
          })
          .timeout(_extendedTimeout);

      Set<int> paymentIds = {};
      Map<int, List<ReconciliationLine>> reconciliationLines = {};

      for (var reconcile in reconciliationResult) {
        final reconcileAmount = (reconcile['amount'] ?? 0.0).toDouble();
        final reconcileDate = reconcile['create_date'] != null
            ? DateTime.parse(reconcile['create_date'])
            : null;

        int? debitMoveId;
        int? creditMoveId;

        if (reconcile['debit_move_id'] is List &&
            reconcile['debit_move_id'].isNotEmpty) {
          debitMoveId = reconcile['debit_move_id'][0] is int
              ? reconcile['debit_move_id'][0]
              : null;
        } else if (reconcile['debit_move_id'] is int) {
          debitMoveId = reconcile['debit_move_id'];
        } else {}

        if (reconcile['credit_move_id'] is List &&
            reconcile['credit_move_id'].isNotEmpty) {
          creditMoveId = reconcile['credit_move_id'][0] is int
              ? reconcile['credit_move_id'][0]
              : null;
        } else if (reconcile['credit_move_id'] is int) {
          creditMoveId = reconcile['credit_move_id'];
        } else {}

        if (debitMoveId == null && creditMoveId == null) {
          continue;
        }

        final moveLineResult = await client
            .callKw({
              'model': 'account.move.line',
              'method': 'search_read',
              'args': [
                [
                  [
                    'id',
                    'in',
                    [
                      debitMoveId,
                      creditMoveId,
                    ].where((id) => id != null).toList(),
                  ],
                ],
                ['move_id', 'payment_id'],
              ],
              'kwargs': {},
            })
            .timeout(_extendedTimeout);

        for (var moveLine in moveLineResult) {
          int? moveId;
          if (moveLine['move_id'] is List && moveLine['move_id'].isNotEmpty) {
            moveId = moveLine['move_id'][0] is int
                ? moveLine['move_id'][0]
                : null;
          } else if (moveLine['move_id'] is int) {
            moveId = moveLine['move_id'];
          } else {}

          if (moveId != null) {
            int? paymentId;
            if (moveLine['payment_id'] is List &&
                moveLine['payment_id'].isNotEmpty) {
              paymentId = moveLine['payment_id'][0] is int
                  ? moveLine['payment_id'][0]
                  : null;
            } else if (moveLine['payment_id'] is int) {
              paymentId = moveLine['payment_id'];
            } else if (moveLine['payment_id'] == false ||
                moveLine['payment_id'] == null) {
              continue;
            } else {
              continue;
            }

            if (paymentId != null) {
              paymentIds.add(paymentId);
              reconciliationLines.putIfAbsent(paymentId, () => []);
              reconciliationLines[paymentId]!.add(
                ReconciliationLine(
                  paymentId: paymentId,
                  invoiceId: invoiceId,
                  amount: reconcileAmount,
                  reconcileDate: reconcileDate,
                  isFullReconciliation: true,
                ),
              );
            } else {
              try {
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

                if (paymentResult.isNotEmpty && paymentResult[0] is int) {
                  final foundPaymentId = paymentResult[0];
                  paymentIds.add(foundPaymentId);
                  reconciliationLines.putIfAbsent(foundPaymentId, () => []);
                  reconciliationLines[foundPaymentId]!.add(
                    ReconciliationLine(
                      paymentId: foundPaymentId,
                      invoiceId: invoiceId,
                      amount: reconcileAmount,
                      reconcileDate: reconcileDate,
                      isFullReconciliation: true,
                    ),
                  );
                }
              } catch (e) {}
            }
          }
        }
      }

      List<Payment> payments = [];

      if (paymentIds.isNotEmpty) {
        final paymentResults = await client
            .callKw({
              'model': 'account.payment',
              'method': 'search_read',
              'args': [
                [
                  ['id', 'in', paymentIds.toList()],
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

        for (var paymentData in paymentResults) {
          if (paymentData['id'] is! int) {
            continue;
          }

          final paymentId = paymentData['id'] as int;
          final isReconciled = paymentData['is_reconciled'] ?? false;
          final paymentState = paymentData['state'] ?? 'draft';

          paymentData['reconciliation_lines'] =
              reconciliationLines[paymentId]
                  ?.map((line) => line.toJson())
                  .toList() ??
              [];

          paymentData['reconciliation_status'] = isReconciled
              ? 'complete'
              : paymentState == 'posted'
              ? 'pending'
              : 'not_required';
          paymentData['requires_manual_reconciliation'] =
              paymentState == 'posted' && !isReconciled;

          final reconciledAmount =
              reconciliationLines[paymentId]?.fold(
                0.0,
                (sum, line) => sum + line.amount,
              ) ??
              0.0;
          paymentData['reconciled_amount'] = reconciledAmount;

          payments.add(Payment.fromJson(paymentData));
        }
      }

      return payments;
    } catch (e) {
      return [];
    }
  }

  static Future<List<Payment>> _getInvoicePaymentsWithReconciliationSafe(
    dynamic client,
    int invoiceId,
  ) async {
    try {
      return await _getInvoicePaymentsWithReconciliation(client, invoiceId);
    } catch (e) {
      final errorString = e.toString().toLowerCase();

      if (errorString.contains('invalid field') ||
          errorString.contains('keyerror') ||
          errorString.contains('payment_id') ||
          errorString.contains('field does not exist')) {
        return await _getInvoicePaymentsFallback(client, invoiceId);
      }

      rethrow;
    }
  }

  static Future<List<Payment>> _getInvoicePaymentsFallback(
    dynamic client,
    int invoiceId,
  ) async {
    try {
      final invoiceResult = await client
          .callKw({
            'model': 'account.move',
            'method': 'search_read',
            'args': [
              [
                ['id', '=', invoiceId],
              ],
              ['name', 'partner_id'],
            ],
            'kwargs': {},
          })
          .timeout(_extendedTimeout);

      if (invoiceResult.isEmpty) {
        return [];
      }

      final invoiceData = invoiceResult[0];
      final invoiceName = invoiceData['name'] ?? '';
      final partnerId = invoiceData['partner_id'] is List
          ? invoiceData['partner_id'][0]
          : invoiceData['partner_id'];

      final paymentResults = await client
          .callKw({
            'model': 'account.payment',
            'method': 'search_read',
            'args': [
              [
                ['state', '!=', 'draft'],
                ['partner_type', '=', 'customer'],
                ['partner_id', '=', partnerId],
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
            'kwargs': {'limit': 50},
          })
          .timeout(_extendedTimeout);

      List<Payment> relevantPayments = [];

      for (var paymentData in paymentResults) {
        try {
          final communication = paymentData['communication']?.toString() ?? '';
          final reference = paymentData['ref']?.toString() ?? '';

          if ((communication.isNotEmpty &&
                  (communication.contains(invoiceId.toString()) ||
                      communication.contains(invoiceName))) ||
              (reference.isNotEmpty &&
                  (reference.contains(invoiceId.toString()) ||
                      reference.contains(invoiceName)))) {
            paymentData['reconciliation_lines'] = [];
            paymentData['reconciliation_status'] = 'unknown';
            paymentData['requires_manual_reconciliation'] = false;
            paymentData['reconciled_amount'] = 0.0;

            final payment = Payment.fromJson(paymentData);
            relevantPayments.add(payment);
          }
        } catch (e) {}
      }

      return relevantPayments;
    } catch (e) {
      return [];
    }
  }
}
