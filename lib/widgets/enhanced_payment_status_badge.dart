import 'package:flutter/material.dart';

import 'package:hugeicons/hugeicons.dart';
import '../models/invoice.dart';

class EnhancedPaymentStatusBadge extends StatelessWidget {
  final Invoice invoice;
  final bool showIcon;
  final bool showReconciliationIndicator;
  final double? fontSize;
  final EdgeInsetsGeometry? padding;

  const EnhancedPaymentStatusBadge({
    super.key,
    required this.invoice,
    this.showIcon = true,
    this.showReconciliationIndicator = true,
    this.fontSize,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _getOdooBackgroundColor(isDark),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            _getOdooStatusText(),
            style: TextStyle(
              fontSize: fontSize ?? 12,
              fontWeight: FontWeight.w600,
              color: _getOdooTextColor(isDark),
            ),
          ),
          if (showReconciliationIndicator &&
              _shouldShowReconciliationIndicator()) ...[
            const SizedBox(width: 4),
            Icon(
              HugeIcons.strokeRoundedRefresh,
              size: (fontSize ?? 12) + 1,
              color: _getReconciliationIndicatorColor(isDark),
            ),
          ],
        ],
      ),
    );
  }

  Color _getOdooBackgroundColor(bool isDark) {
    final baseColor = _getOdooStatusColor();
    return isDark ? baseColor.withOpacity(0.2) : baseColor.withOpacity(0.1);
  }

  Color _getOdooBorderColor(bool isDark) {
    final baseColor = _getOdooStatusColor();
    return isDark ? baseColor.withOpacity(0.4) : baseColor.withOpacity(0.3);
  }

  Color _getOdooTextColor(bool isDark) {
    final baseColor = _getOdooStatusColor();
    return isDark ? baseColor.withOpacity(0.9) : baseColor;
  }

  Color _getReconciliationIndicatorColor(bool isDark) {
    return isDark
        ? const Color(0xFFFF9800).withOpacity(0.8)
        : const Color(0xFFFF9800);
  }

  IconData _getOdooStatusIcon() {
    switch (invoice.status.toLowerCase()) {
      case 'draft':
        return HugeIcons.strokeRoundedEdit02;
      case 'cancel':
        return HugeIcons.strokeRoundedCancel01;
      case 'sent':
        return HugeIcons.strokeRoundedSent;
      case 'posted':
        switch (invoice.paymentState.toLowerCase()) {
          case 'paid':
            return HugeIcons.strokeRoundedCheckmarkCircle02;
          case 'partial':
            return HugeIcons.strokeRoundedCircleArrowRight02;
          case 'reversed':
            return HugeIcons.strokeRoundedReverseWithdrawal01;
          case 'in_payment':
            return HugeIcons.strokeRoundedLoading03;
          case 'blocked':
            return HugeIcons.strokeRoundedBlocked;
          case 'invoicing_legacy':
            return HugeIcons.strokeRoundedInformationCircle;
          default:
            if (invoice.isMoveSent == true) {
              return HugeIcons.strokeRoundedSent;
            }

            return HugeIcons.strokeRoundedTick03;
        }
      default:
        return HugeIcons.strokeRoundedInformationCircle;
    }
  }

  String _getOdooStatusText() {
    switch (invoice.status.toLowerCase()) {
      case 'draft':
        return 'Draft';
      case 'cancel':
        return 'Cancelled';
      case 'sent':
        return 'Sent';
      case 'posted':
        switch (invoice.paymentState.toLowerCase()) {
          case 'paid':
            return 'Paid';
          case 'partial':
            return 'Partially Paid';
          case 'reversed':
            return 'Reversed';
          case 'in_payment':
            return 'In Payment';
          case 'blocked':
            return 'Blocked';
          case 'invoicing_legacy':
            return 'Invoicing App Legacy';
          default:
            if (invoice.isMoveSent == true) {
              return 'Sent';
            }

            return 'Posted';
        }
      default:
        return invoice.status.isNotEmpty ? invoice.status : 'Unknown';
    }
  }

  Color _getOdooStatusColor() {
    switch (invoice.status.toLowerCase()) {
      case 'draft':
        return Colors.grey;
      case 'cancel':
        return Colors.red;
      case 'sent':
        return Colors.grey;
      case 'posted':
        switch (invoice.paymentState.toLowerCase()) {
          case 'paid':
            return Colors.green;
          case 'partial':
            return Colors.orange;
          case 'reversed':
            return Colors.purple;
          case 'in_payment':
            return Colors.green;
          case 'blocked':
            return Colors.grey;
          case 'invoicing_legacy':
            return Colors.amber;
          default:
            return Colors.grey;
        }
      default:
        return Colors.grey;
    }
  }

  bool _shouldShowReconciliationIndicator() {
    if (invoice.status.toLowerCase() != 'posted') {
      return false;
    }

    try {
      return invoice.paymentState.toLowerCase() == 'in_payment' ||
          invoice.requiresReconciliation ||
          invoice.hasInPaymentTransactions;
    } catch (e) {
      return invoice.paymentState.toLowerCase() == 'in_payment' ||
          invoice.hasInPaymentTransactions;
    }
  }
}

class PaymentProgressIndicator extends StatelessWidget {
  final Invoice invoice;
  final double height;
  final bool showLabels;

  const PaymentProgressIndicator({
    super.key,
    required this.invoice,
    this.height = 6,
    this.showLabels = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = _calculateProgress();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabels) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Payment Progress',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 0),
        ],
        Container(
          height: height,
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[800] : Colors.grey[200],
            borderRadius: BorderRadius.circular(height / 2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                color: _getProgressColor(),
                borderRadius: BorderRadius.circular(height / 2),
              ),
            ),
          ),
        ),
        if (showLabels) ...[
          const SizedBox(height: 0),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Paid: ${(invoice.total - invoice.amountResidual).toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              Text(
                'Remaining: ${invoice.amountResidual.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  double _calculateProgress() {
    if (invoice.total <= 0) return 0.0;
    final paidAmount = invoice.total - invoice.amountResidual;
    return (paidAmount / invoice.total).clamp(0.0, 1.0);
  }

  Color _getProgressColor() {
    switch (invoice.paymentState.toLowerCase()) {
      case 'paid':
        return const Color(0xFF4CAF50);
      case 'in_payment':
        return const Color(0xFF2196F3);
      case 'partial':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF9E9E9E);
    }
  }
}

class PaymentStatusCard extends StatelessWidget {
  final Invoice invoice;
  final VoidCallback? onPaymentTap;
  final VoidCallback? onReconcileTap;

  const PaymentStatusCard({
    super.key,
    required this.invoice,
    this.onPaymentTap,
    this.onReconcileTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [const SizedBox(height: 4), _buildPaymentDetails(isDark)],
      ),
    );
  }

  Widget _buildPaymentDetails(bool isDark) {
    return Column(
      children: [
        _buildDetailRow(
          'Total Amount',
          invoice.total.toStringAsFixed(2),
          isDark,
        ),
        _buildDetailRow(
          'Amount Paid',
          (invoice.total - invoice.amountResidual).toStringAsFixed(2),
          isDark,
        ),
        _buildDetailRow(
          'Amount Due',
          invoice.amountResidual.toStringAsFixed(2),
          isDark,
          isHighlighted: invoice.amountResidual > 0,
        ),
        if (invoice.dueDate != null)
          _buildDetailRow(
            'Due Date',
            '${invoice.dueDate!.day}/${invoice.dueDate!.month}/${invoice.dueDate!.year}',
            isDark,
            isOverdue: invoice.isOverdue,
          ),
      ],
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    bool isDark, {
    bool isHighlighted = false,
    bool isOverdue = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w400,
              color: isDark ? Colors.white70 : Color(0xff7F7F7F),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isHighlighted || isOverdue
                  ? FontWeight.w600
                  : FontWeight.normal,
              color: isOverdue
                  ? Colors.red
                  : isHighlighted
                  ? (isDark ? Colors.white : Color(0xff000000))
                  : (isDark ? Colors.grey[300] : Color(0xff000000)),
            ),
          ),
        ],
      ),
    );
  }

  bool _shouldShowActions() {
    return invoice.paymentState != 'paid' && invoice.status == 'posted';
  }
}
