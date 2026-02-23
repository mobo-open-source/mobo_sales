import 'package:flutter/material.dart';
import '../models/invoice.dart';
import '../models/payment.dart';

class ReconciliationIndicator extends StatelessWidget {
  final Invoice invoice;
  final bool showDetails;
  final VoidCallback? onReconcileHelp;
  final EdgeInsetsGeometry? padding;
  final bool compact;

  const ReconciliationIndicator({
    super.key,
    required this.invoice,
    this.showDetails = true,
    this.onReconcileHelp,
    this.padding,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!invoice.requiresReconciliation) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final pendingPayments = invoice.reconciliationRequirement.pendingPayments;

    if (compact) {
      return _buildCompactIndicator(context, theme, pendingPayments);
    }

    return _buildFullIndicator(context, theme, pendingPayments);
  }

  Widget _buildCompactIndicator(
    BuildContext context,
    ThemeData theme,
    List<Payment> pendingPayments,
  ) {
    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sync_problem, size: 16, color: Colors.orange.shade700),
          const SizedBox(width: 4),
          Text(
            'Reconciliation Required',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.orange.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (onReconcileHelp != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onReconcileHelp,
              child: Icon(
                Icons.help_outline,
                size: 14,
                color: Colors.orange.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFullIndicator(
    BuildContext context,
    ThemeData theme,
    List<Payment> pendingPayments,
  ) {
    return Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.sync_problem, color: Colors.orange.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Reconciliation Required in Odoo',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onReconcileHelp != null)
                IconButton(
                  onPressed: onReconcileHelp,
                  icon: Icon(Icons.help_outline, color: Colors.orange.shade600),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          if (showDetails) ...[
            const SizedBox(height: 8),
            Text(
              invoice.reconciliationRequirement.reason,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.orange.shade800,
              ),
            ),
            const SizedBox(height: 8),
            _buildPaymentsList(context, theme, pendingPayments),
            const SizedBox(height: 8),
            _buildGuidanceText(context, theme),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentsList(
    BuildContext context,
    ThemeData theme,
    List<Payment> pendingPayments,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pending Payments:',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: Colors.orange.shade800,
          ),
        ),
        const SizedBox(height: 4),
        ...pendingPayments.map(
          (payment) => Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 2),
            child: Row(
              children: [
                Icon(Icons.payment, size: 14, color: Colors.orange.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${payment.name} - \$${payment.amount.toStringAsFixed(2)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    payment.statusDisplayText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGuidanceText(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'These payments are posted but need to be reconciled in Odoo to complete the payment process. '
              'Please access your Odoo backend to reconcile these transactions.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.orange.shade800,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
