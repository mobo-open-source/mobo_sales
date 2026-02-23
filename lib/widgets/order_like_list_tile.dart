import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import '../providers/currency_provider.dart';

class OrderLikeListTile extends StatelessWidget {
  final String id;
  final String customer;
  final String? infoLine;
  final String? extraInfoLine;
  final double? amount;
  final List? currencyId;
  final String status;
  final Color statusColor;
  final VoidCallback? onTap;
  final Widget? popupMenu;
  final bool isDark;
  final String? amountLabel;
  final IconData? mainIcon;
  final IconData? extraIcon;
  final Widget? customStatusWidget;

  const OrderLikeListTile({
    super.key,
    required this.id,
    required this.customer,
    this.infoLine,
    this.extraInfoLine,
    this.amount,
    this.currencyId,
    required this.status,
    required this.statusColor,
    this.onTap,
    this.popupMenu,
    required this.isDark,
    this.amountLabel,
    this.mainIcon,
    this.extraIcon,
    this.customStatusWidget,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[850] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey[850]! : Colors.grey[200]!,
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withOpacity(0.05),
              offset: const Offset(0, 6),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.only(
            left: 14,
            top: 14,
            bottom: 14,
            right: 14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          id,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white
                                : AppTheme.primaryColor,
                            letterSpacing: -0.1,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (customer.isNotEmpty && customer != 'Unknown')
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              customer,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.grey[300]
                                    : Color(0xff6D717F),
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),

                  Row(
                    children: [
                      customStatusWidget ?? _buildStatusBadge(),
                      if (popupMenu != null) ...[popupMenu!],
                    ],
                  ),
                ],
              ),
              if (infoLine != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (mainIcon != null) ...[
                            Icon(
                              mainIcon,
                              size: 14,
                              color: isDark
                                  ? Colors.grey[100]
                                  : Color(0xffC5C5C5),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            infoLine!,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.grey[100]
                                  : Color(0xff6D717F),
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      if (extraInfoLine != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (extraIcon != null) ...[
                              Icon(
                                extraIcon,
                                size: 14,
                                color: isDark
                                    ? Colors.grey[100]
                                    : Color(0xffC5C5C5),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              extraInfoLine!,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.grey[100]
                                    : Color(0xff6D717F),
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

              const SizedBox(height: 8),
              if (amount != null && amountLabel != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        amountLabel!,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.grey[200] : Color(0xff5E5E5E),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Consumer<CurrencyProvider>(
                      builder: (context, currencyProvider, _) {
                        final String? currencyCode =
                            (currencyId != null && currencyId!.length > 1)
                            ? currencyId![1].toString()
                            : null;
                        final formattedAmount = currencyProvider.formatAmount(
                          amount!,
                          currency: currencyCode,
                        );
                        return Text(
                          formattedAmount,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Color(0xff101010),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              if (amount != null && amountLabel != null)
                const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    final textColor = isDark ? Colors.white : statusColor;
    final backgroundColor = isDark
        ? Colors.white.withOpacity(0.15)
        : statusColor.withOpacity(0.10);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isDark ? FontWeight.bold : FontWeight.w600,
          color: textColor,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
