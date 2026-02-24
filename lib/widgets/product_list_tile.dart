import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import '../providers/currency_provider.dart';

class ProductListTile extends StatelessWidget {
  final String id;
  final String name;
  final String? defaultCode;
  final double listPrice;
  final List? currencyId;
  final String? category;
  final double qtyAvailable;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final int? variantCount;
  final bool isDark;
  final VoidCallback? onTap;
  final Widget? popupMenu;
  final List<Widget>? actionButtons;
  final Map<String, Uint8List>? imageCache;
  final List<Map<String, String>>? attributes;

  const ProductListTile({
    super.key,
    required this.id,
    required this.name,
    this.defaultCode,
    required this.listPrice,
    this.currencyId,
    this.category,
    required this.qtyAvailable,
    this.imageUrl,
    this.imageBytes,
    this.variantCount,
    required this.isDark,
    this.onTap,
    this.popupMenu,
    this.actionButtons,
    this.imageCache,
    this.attributes,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProductImage(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  name,
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
                              ),
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Consumer<CurrencyProvider>(
                                  builder: (context, currencyProvider, _) {
                                    String? currencyCode =
                                        (currencyId != null &&
                                            currencyId!.length > 1)
                                        ? currencyId![1].toString()
                                        : null;
                                    final formattedPrice = currencyProvider
                                        .formatAmount(
                                          listPrice,
                                          currency: currencyCode,
                                        );
                                    return Text(
                                      formattedPrice,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.grey[800],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 0),
                      child: Text(
                        "SKU: ${_getDisplaySku()}",
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[300] : Colors.grey[600],
                          fontWeight: FontWeight.w400,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (category != null && category!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            Text(
                              "Category:",
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[800],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                category!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey[300]
                                      : Colors.grey[900],
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              "${qtyAvailable.toStringAsFixed(0)} in stock",
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white
                                    : (qtyAvailable > 0
                                          ? Colors.green[700]
                                          : Colors.red[700]),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (variantCount != null && variantCount! > 1) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.grey[800]!
                                    : Colors.blue[50]!,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "$variantCount variants",
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : Colors.blue[700],
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (popupMenu != null &&
                        attributes != null &&
                        attributes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: attributes!.take(2).map((attr) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.grey[800]
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '${attr['attribute_name']}: ${attr['value_name']}',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: isDark
                                      ? Colors.grey[300]
                                      : Colors.black87,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    if (actionButtons != null && actionButtons!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        height: 1,
                        width: double.infinity,
                        color: theme.colorScheme.onSurface.withOpacity(0.07),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: actionButtons!,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductImage() {
    Widget? imageWidget;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      if (imageUrl!.startsWith('http')) {
        imageWidget = CachedNetworkImage(
          imageUrl: imageUrl!,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: isDark ? Colors.grey[800] : Colors.grey[100],
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
            ),
          ),
          errorWidget: (context, url, error) => _buildAvatarFallback(),
        );
      } else if (imageCache != null && imageCache!.containsKey(imageUrl)) {
        imageWidget = Image.memory(
          imageCache![imageUrl]!,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildAvatarFallback(),
        );
      } else if (imageBytes != null) {
        imageWidget = Image.memory(
          imageBytes!,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildAvatarFallback(),
        );
      }
    }
    imageWidget ??= _buildAvatarFallback();
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : Colors.black.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          color: isDark ? Colors.grey[800] : Colors.grey[100],
          child: imageWidget,
        ),
      ),
    );
  }

  Widget _buildAvatarFallback() {
    final initials = _initialsFromName(name);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.grey[300]!, Colors.grey[400]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  String _getDisplaySku() {
    if (defaultCode != null &&
        defaultCode!.trim().isNotEmpty &&
        defaultCode!.toLowerCase() != 'false' &&
        defaultCode!.toLowerCase() != 'null') {
      return defaultCode!;
    }
    return '—';
  }

  String _initialsFromName(String fullName) {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return '?';

    final clean = trimmed.replaceAll(RegExp(r"\s+"), ' ');
    return clean.length >= 2
        ? clean.substring(0, 2).toUpperCase()
        : clean[0].toUpperCase();
  }
}
