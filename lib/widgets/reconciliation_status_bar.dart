import 'package:flutter/material.dart';
import '../models/payment.dart';
import '../models/invoice.dart';

class ReconciliationStatusBar extends StatelessWidget {
  final List<Payment> payments;
  final Invoice? invoice;
  final VoidCallback? onViewDetails;
  final bool showProgress;
  final EdgeInsetsGeometry? padding;

  const ReconciliationStatusBar({
    super.key,
    required this.payments,
    this.invoice,
    this.onViewDetails,
    this.showProgress = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final reconciliationData = _calculateReconciliationData();

    if (reconciliationData.totalPayments == 0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _getBackgroundColor(reconciliationData),
        border: Border.all(color: _getBorderColor(reconciliationData)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context, theme, reconciliationData),
          if (showProgress && reconciliationData.totalPayments > 0) ...[
            const SizedBox(height: 8),
            _buildProgressBar(context, theme, reconciliationData),
          ],
          if (reconciliationData.pendingCount > 0) ...[
            const SizedBox(height: 8),
            _buildPendingInfo(context, theme, reconciliationData),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    ReconciliationData data,
  ) {
    return Row(
      children: [
        Icon(_getStatusIcon(data), color: _getStatusColor(data), size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _getStatusText(data),
            style: theme.textTheme.titleSmall?.copyWith(
              color: _getStatusColor(data),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (onViewDetails != null)
          TextButton(
            onPressed: onViewDetails,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'View Details',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _getStatusColor(data),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProgressBar(
    BuildContext context,
    ThemeData theme,
    ReconciliationData data,
  ) {
    final progress = data.totalPayments > 0
        ? data.reconciledCount / data.totalPayments
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Reconciliation Progress',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: _getStatusColor(data),
              ),
            ),
            Text(
              '${data.reconciledCount}/${data.totalPayments} payments',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _getStatusColor(data),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: _getStatusColor(data).withOpacity(0.2),
          valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(data)),
          minHeight: 6,
        ),
      ],
    );
  }

  Widget _buildPendingInfo(
    BuildContext context,
    ThemeData theme,
    ReconciliationData data,
  ) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _getStatusColor(data).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule, size: 16, color: _getStatusColor(data)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${data.pendingCount} payment${data.pendingCount == 1 ? '' : 's'} pending reconciliation',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _getStatusColor(data),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Total pending amount: \$${data.pendingAmount.toStringAsFixed(2)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _getStatusColor(data),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ReconciliationData _calculateReconciliationData() {
    final totalPayments = payments.length;
    final reconciledPayments = payments
        .where((p) => p.isFullyReconciled)
        .toList();
    final pendingPayments = payments
        .where((p) => p.requiresReconciliation)
        .toList();
    final inPaymentPayments = payments.where((p) => p.isInPayment).toList();
    final failedPayments = payments
        .where((p) => p.reconciliationStatus == ReconciliationStatus.failed)
        .toList();

    final reconciledCount = reconciledPayments.length;
    final pendingCount = pendingPayments.length;
    final inPaymentCount = inPaymentPayments.length;
    final failedCount = failedPayments.length;

    final reconciledAmount = reconciledPayments.fold(
      0.0,
      (sum, p) => sum + p.amount,
    );
    final pendingAmount = pendingPayments.fold(0.0, (sum, p) => sum + p.amount);
    final inPaymentAmount = inPaymentPayments.fold(
      0.0,
      (sum, p) => sum + p.amount,
    );

    ReconciliationStatus status;
    if (failedCount > 0) {
      status = ReconciliationStatus.failed;
    } else if (pendingCount == 0 && inPaymentCount == 0 && totalPayments > 0) {
      status = ReconciliationStatus.complete;
    } else if (reconciledCount > 0 &&
        (pendingCount > 0 || inPaymentCount > 0)) {
      status = ReconciliationStatus.partial;
    } else if (pendingCount > 0 || inPaymentCount > 0) {
      status = ReconciliationStatus.pending;
    } else {
      status = ReconciliationStatus.notRequired;
    }

    return ReconciliationData(
      totalPayments: totalPayments,
      reconciledCount: reconciledCount,
      pendingCount: pendingCount,
      inPaymentCount: inPaymentCount,
      reconciledAmount: reconciledAmount,
      pendingAmount: pendingAmount,
      inPaymentAmount: inPaymentAmount,
      status: status,
    );
  }

  Color _getBackgroundColor(ReconciliationData data) {
    switch (data.status) {
      case ReconciliationStatus.complete:
        return Colors.green.shade50;
      case ReconciliationStatus.partial:
        return Colors.orange.shade50;
      case ReconciliationStatus.pending:
        return Colors.orange.shade50;
      case ReconciliationStatus.failed:
        return Colors.red.shade50;
      case ReconciliationStatus.notRequired:
        return Colors.grey.shade50;
    }
  }

  Color _getBorderColor(ReconciliationData data) {
    switch (data.status) {
      case ReconciliationStatus.complete:
        return Colors.green.shade300;
      case ReconciliationStatus.partial:
        return Colors.orange.shade300;
      case ReconciliationStatus.pending:
        return Colors.orange.shade300;
      case ReconciliationStatus.failed:
        return Colors.red.shade300;
      case ReconciliationStatus.notRequired:
        return Colors.grey.shade300;
    }
  }

  Color _getStatusColor(ReconciliationData data) {
    switch (data.status) {
      case ReconciliationStatus.complete:
        return Colors.green.shade700;
      case ReconciliationStatus.partial:
        return Colors.orange.shade700;
      case ReconciliationStatus.pending:
        return Colors.orange.shade700;
      case ReconciliationStatus.failed:
        return Colors.red.shade700;
      case ReconciliationStatus.notRequired:
        return Colors.grey.shade700;
    }
  }

  IconData _getStatusIcon(ReconciliationData data) {
    switch (data.status) {
      case ReconciliationStatus.complete:
        return Icons.check_circle;
      case ReconciliationStatus.partial:
        return Icons.sync_problem;
      case ReconciliationStatus.pending:
        return Icons.schedule;
      case ReconciliationStatus.failed:
        return Icons.error;
      case ReconciliationStatus.notRequired:
        return Icons.info;
    }
  }

  String _getStatusText(ReconciliationData data) {
    switch (data.status) {
      case ReconciliationStatus.complete:
        return 'All Payments Reconciled';
      case ReconciliationStatus.partial:
        return 'Partial Reconciliation Required';
      case ReconciliationStatus.pending:
        return 'Reconciliation Required';
      case ReconciliationStatus.failed:
        return 'Reconciliation Failed';
      case ReconciliationStatus.notRequired:
        return 'No Reconciliation Required';
    }
  }
}

class ReconciliationData {
  final int totalPayments;
  final int reconciledCount;
  final int pendingCount;
  final int inPaymentCount;
  final double reconciledAmount;
  final double pendingAmount;
  final double inPaymentAmount;
  final ReconciliationStatus status;

  ReconciliationData({
    required this.totalPayments,
    required this.reconciledCount,
    required this.pendingCount,
    required this.inPaymentCount,
    required this.reconciledAmount,
    required this.pendingAmount,
    required this.inPaymentAmount,
    required this.status,
  });
}
