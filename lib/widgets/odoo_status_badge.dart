import 'package:flutter/material.dart';

class OdooStatusBadge extends StatelessWidget {
  final String paymentState;
  final String state;
  final bool isDark;
  final bool? isMoveSent;

  const OdooStatusBadge({
    super.key,
    required this.paymentState,
    required this.state,
    required this.isDark,
    this.isMoveSent,
  });

  @override
  Widget build(BuildContext context) {
    final statusInfo = _getStatusInfo();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: statusInfo.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusInfo.borderColor, width: 1),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: statusInfo.color.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Text(
        statusInfo.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: statusInfo.textColor,
        ),
      ),
    );
  }

  _StatusInfo _getStatusInfo() {
    switch (state.toLowerCase()) {
      case 'draft':
        return _StatusInfo(label: 'Draft', color: Colors.grey, isDark: isDark);
      case 'cancel':
        return _StatusInfo(
          label: 'Cancelled',
          color: Colors.red,
          isDark: isDark,
        );
      case 'sent':
        return _StatusInfo(label: 'Sent', color: Colors.grey, isDark: isDark);
      case 'posted':
        switch (paymentState.toLowerCase()) {
          case 'paid':
            return _StatusInfo(
              label: 'Paid',
              color: Colors.green,
              isDark: isDark,
            );
          case 'partial':
            return _StatusInfo(
              label: 'Partially Paid',
              color: Colors.orange,
              isDark: isDark,
            );
          case 'reversed':
            return _StatusInfo(
              label: 'Reversed',
              color: Colors.purple,
              isDark: isDark,
            );
          case 'in_payment':
            return _StatusInfo(
              label: 'In Payment',
              color: Colors.green,
              isDark: isDark,
            );
          case 'blocked':
            return _StatusInfo(
              label: 'Blocked',
              color: Colors.grey,
              isDark: isDark,
            );
          case 'invoicing_legacy':
            return _StatusInfo(
              label: 'Invoicing App Legacy',
              color: Colors.amber,
              isDark: isDark,
            );
          default:
            if (isMoveSent == true) {
              return _StatusInfo(
                label: 'Sent',
                color: Colors.grey,
                isDark: isDark,
              );
            }

            return _StatusInfo(
              label: 'Posted',
              color: Colors.grey,
              isDark: isDark,
            );
        }
      default:
        return _StatusInfo(
          label: state.isNotEmpty ? state : 'Unknown',
          color: Colors.grey,
          isDark: isDark,
        );
    }
  }
}

class _StatusInfo {
  final String label;
  final Color color;
  final Color textColor;
  final Color backgroundColor;
  final Color borderColor;

  _StatusInfo({required this.label, required Color color, required bool isDark})
    : color = color,
      textColor = isDark ? Colors.white : color,
      backgroundColor = isDark
          ? color.withOpacity(0.2)
          : color.withOpacity(0.1),
      borderColor = isDark ? color.withOpacity(0.5) : color;
}
