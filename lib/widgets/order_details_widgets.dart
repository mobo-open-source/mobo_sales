import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import '../models/contact.dart';

class OrderDetailsTopSection extends StatelessWidget {
  final Map<String, dynamic> orderData;
  final Contact? customerDetails;
  final bool isDark;
  final Color primaryColor;
  final String documentType;
  final int? daysUntilExpiry;

  const OrderDetailsTopSection({
    super.key,
    required this.orderData,
    required this.customerDetails,
    required this.isDark,
    required this.primaryColor,
    required this.documentType,
    this.daysUntilExpiry,
  });

  String _safeString(dynamic value) {
    if (value == null) return '';
    if (value is List && value.isNotEmpty) {
      return value[1]?.toString() ?? '';
    }
    return value.toString();
  }

  String _getDisplayName() {
    final c = customerDetails;
    bool isReal(String? v) =>
        v != null && v.trim().isNotEmpty && v.trim().toLowerCase() != 'false';

    final companyName =
        (c != null && c.isCompany == true && isReal(c.companyName))
        ? c.companyName
        : null;

    return companyName ??
        (c != null && isReal(c.name)
            ? c.name
            : _getCustomerName(orderData['partner_id']));
  }

  String _getCustomerName(dynamic partnerId) {
    if (partnerId is List && partnerId.length > 1) {
      return partnerId[1].toString();
    }
    return 'Unknown Customer';
  }

  String _getAddress() {
    final c = customerDetails;
    bool isReal(String? v) =>
        v != null && v.trim().isNotEmpty && v.trim().toLowerCase() != 'false';

    if (c == null) return '';

    final addressParts = [
      c.street,
      c.street2,
      c.city,
      c.state,
      c.zip,
      c.country,
    ].where((part) => isReal(part)).toList();

    return addressParts.isNotEmpty ? addressParts.join(', ') : '';
  }

  String? _getPhone() {
    final c = customerDetails;
    bool isReal(String? v) =>
        v != null && v.trim().isNotEmpty && v.trim().toLowerCase() != 'false';

    if (c == null) return null;

    return isReal(c.phone) ? c.phone : (isReal(c.mobile) ? c.mobile : null);
  }

  String? _getEmail() {
    final c = customerDetails;
    bool isReal(String? v) =>
        v != null && v.trim().isNotEmpty && v.trim().toLowerCase() != 'false';

    return c != null && isReal(c.email) ? c.email : null;
  }

  String _getStatusLabel() {
    final state = orderData['state'];
    switch (documentType) {
      case 'quotation':
        return state == 'sale' ? 'Sale Order' : 'Quotation';
      case 'invoice':
        return 'Invoice';
      default:
        return documentType.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _getDisplayName();
    final address = _getAddress();
    final phone = _getPhone();
    final email = _getEmail();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _safeString(orderData['name']),
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF28A745).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _getStatusLabel(),
                  style: GoogleFonts.inter(
                    color: const Color(0xFF28A745),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          Text(
            displayName,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),

          if (address.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  HugeIcons.strokeRoundedLocation01,
                  size: 16,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    address,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: isDark ? Colors.grey[300] : Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),

          if (address.isNotEmpty) const SizedBox(height: 8),

          Row(
            children: [
              if (phone != null) ...[
                Icon(
                  HugeIcons.strokeRoundedCall,
                  size: 16,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                const SizedBox(width: 6),
                Text(
                  phone,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: isDark ? Colors.grey[300] : Colors.grey[600],
                  ),
                ),
              ],
              if (phone != null && email != null) ...[
                const SizedBox(width: 16),
                Container(
                  width: 1,
                  height: 12,
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                ),
                const SizedBox(width: 16),
              ],
              if (email != null) ...[
                Icon(
                  HugeIcons.strokeRoundedMail01,
                  size: 16,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    email,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: isDark ? Colors.grey[300] : Colors.grey[600],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order Date',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      orderData['date_order'] != null
                          ? DateFormat(
                              'MMM dd, yyyy',
                            ).format(DateTime.parse(orderData['date_order']))
                          : 'N/A',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              if (orderData['validity_date'] != null) ...[
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Valid Until',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            DateFormat('MMM dd, yyyy').format(
                              DateTime.parse(orderData['validity_date']),
                            ),
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          if (daysUntilExpiry != null &&
                              daysUntilExpiry! <= 7) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: daysUntilExpiry! < 0
                                    ? Colors.red.withOpacity(0.15)
                                    : Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                daysUntilExpiry! < 0
                                    ? 'Expired'
                                    : '${daysUntilExpiry}d left',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: daysUntilExpiry! < 0
                                      ? Colors.red[600]
                                      : Colors.orange[600],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class OrderDetailsTabsSection extends StatelessWidget {
  final TabController tabController;
  final bool isDark;
  final List<String> tabLabels;

  const OrderDetailsTabsSection({
    super.key,
    required this.tabController,
    required this.isDark,
    required this.tabLabels,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: tabLabels.asMap().entries.map((entry) {
          final index = entry.key;
          final label = entry.value;

          return Padding(
            padding: EdgeInsets.only(
              right: index < tabLabels.length - 1 ? 12 : 0,
            ),
            child: _buildTabItem(label, index, isDark),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTabItem(String text, int index, bool isDark) {
    return AnimatedBuilder(
      animation: tabController,
      builder: (context, child) {
        final isCurrentlySelected = tabController.index == index;
        return GestureDetector(
          onTap: () {
            tabController.animateTo(index);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: isCurrentlySelected ? Colors.black : Colors.white,
              border: Border.all(
                color: isCurrentlySelected
                    ? Colors.black
                    : (isDark ? Colors.grey[600]! : Colors.grey[300]!),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              text,
              style: GoogleFonts.inter(
                color: isCurrentlySelected
                    ? Colors.white
                    : (isDark ? Colors.grey[400] : Colors.grey[700]),
                fontSize: 15,
                fontWeight: isCurrentlySelected
                    ? FontWeight.bold
                    : FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }
}

class OrderLinesTable extends StatelessWidget {
  final List<Map<String, dynamic>> orderLines;
  final bool isDark;
  final String currencySymbol;

  const OrderLinesTable({
    super.key,
    required this.orderLines,
    required this.isDark,
    required this.currencySymbol,
  });

  String _safeString(dynamic value) {
    if (value == null) return '';
    if (value is List && value.isNotEmpty) {
      return value[1]?.toString() ?? '';
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey[50],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Product',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Qty',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Price',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Total',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),

          ...orderLines.asMap().entries.map((entry) {
            final index = entry.key;
            final line = entry.value;
            final isLast = index == orderLines.length - 1;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                        bottom: BorderSide(
                          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                          width: 1,
                        ),
                      ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _safeString(line['product_id']),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        if (line['name'] != null &&
                            line['name'].toString().isNotEmpty &&
                            line['name'] !=
                                _safeString(line['product_id'])) ...[
                          const SizedBox(height: 4),
                          Text(
                            line['name'].toString(),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      (line['product_uom_qty'] ?? 0).toString(),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      '$currencySymbol${(line['price_unit'] ?? 0).toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      '$currencySymbol${(line['price_subtotal'] ?? 0).toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class OrderTotalsSection extends StatelessWidget {
  final Map<String, dynamic> orderData;
  final bool isDark;
  final String currencySymbol;

  const OrderTotalsSection({
    super.key,
    required this.orderData,
    required this.isDark,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    final subtotal = orderData['amount_untaxed'] ?? 0.0;
    final tax = orderData['amount_tax'] ?? 0.0;
    final total = orderData['amount_total'] ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Subtotal',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
              Text(
                '$currencySymbol${subtotal.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tax',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
              Text(
                '$currencySymbol${tax.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Divider(
            color: isDark ? Colors.grey[700] : Colors.grey[300],
            thickness: 1,
          ),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Text(
                '$currencySymbol${total.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
