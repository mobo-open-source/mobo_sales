import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/payment.dart';
import '../../providers/currency_provider.dart';
import '../../services/invoice_payments_service.dart';
import '../../utils/odoo_date.dart';
import '../../widgets/section_error_state.dart';

/// Shows the payments of the invoice with [invoiceId]: what Odoo's Payments
/// button on an invoice opens. With [inProgressOnly] it lists the payments
/// still in progress, which is what the "Check them" link of Odoo's Pay
/// wizard warning opens.
Future<void> showInvoicePaymentsSheet(
  BuildContext context, {
  required int invoiceId,
  bool inProgressOnly = false,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: isDark ? Colors.grey[900] : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => _InvoicePaymentsSheet(
        invoiceId: invoiceId,
        inProgressOnly: inProgressOnly,
        scrollController: scrollController,
      ),
    ),
  );
}

class _InvoicePaymentsSheet extends StatefulWidget {
  final int invoiceId;
  final bool inProgressOnly;
  final ScrollController scrollController;

  const _InvoicePaymentsSheet({
    required this.invoiceId,
    required this.inProgressOnly,
    required this.scrollController,
  });

  @override
  State<_InvoicePaymentsSheet> createState() => _InvoicePaymentsSheetState();
}

class _InvoicePaymentsSheetState extends State<_InvoicePaymentsSheet> {
  List<InvoicePaymentRow>? _payments;
  String? _error;
  bool _loading = true;

  /// The Odoo generation the rows were read from. A payment state only means
  /// something alongside it — see [Payment.unmatchedState].
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await InvoicePaymentsService.fetch(widget.invoiceId);
      if (!mounted) return;
      setState(() {
        _payments = widget.inProgressOnly ? info.inProgress : info.payments;
        _generation = info.generation;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[700] : Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Payments',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(isDark)),
      ],
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return SectionErrorState(error: _error, onRetry: _load);
    }
    final payments = _payments ?? const <InvoicePaymentRow>[];
    if (payments.isEmpty) {
      return Center(
        child: Text(
          widget.inProgressOnly
              ? 'No payments in progress.'
              : 'No payments for this invoice.',
          style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
        ),
      );
    }
    return ListView.separated(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: payments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _buildRow(payments[i], isDark),
    );
  }

  Widget _buildRow(InvoicePaymentRow payment, bool isDark) {
    final currency = context.read<CurrencyProvider>();
    final details = [
      if (payment.date != null)
        OdooDate.formatDateForDisplay(OdooDate.formatDate(payment.date!)),
      payment.journalName,
      payment.methodName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    details,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                currency.formatAmount(
                  payment.amount,
                  currency: payment.currencyCode,
                ),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              _buildStateBadge(payment.state, _generation, isDark),
            ],
          ),
        ],
      ),
    );
  }

  /// Colours follow Odoo's list decorations: not matched with the bank yet
  /// is a warning, settled is done, cancelled and rejected are muted.
  ///
  /// The state is read against the server's generation, not matched to a
  /// literal: `paid` is the settled end of the pair on Odoo 18 and 19 and
  /// the unsettled end on 20, so one colour table keyed on the word alone
  /// gets one of the two releases backwards.
  Widget _buildStateBadge(String state, int generation, bool isDark) {
    final Color color;
    if (state == 'rejected') {
      color = Colors.red;
    } else if (state == Payment.unmatchedState(generation)) {
      color = Colors.orange;
    } else if (Payment.isSettledState(state, generation)) {
      color = Colors.green;
    } else {
      color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.25 : 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        InvoicePaymentsService.stateLabel(state),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? color.shade200OrSelf : color,
        ),
      ),
    );
  }
}

extension on Color {
  /// A lighter tone for dark mode when the colour is a Material swatch.
  Color get shade200OrSelf {
    final self = this;
    return self is MaterialColor ? self.shade200 : self;
  }
}
