import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'dart:convert';
import '../models/product.dart';
import '../services/odoo_session_manager.dart';
import '../utils/app_theme.dart';

class ProductTypeAhead extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final bool isDark;
  final ValueChanged<Product> onProductSelected;
  final String? Function(String?)? validator;

  const ProductTypeAhead({
    required this.controller,
    required this.labelText,
    required this.isDark,
    required this.onProductSelected,
    this.hintText,
    this.validator,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: isDark ? Colors.white70 : const Color(0xff7F7F7F),
          ),
        ),
        const SizedBox(height: 8),
        TypeAheadField<Product>(
          controller: controller,
          builder: (context, controller, focusNode) {
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              validator: validator,
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: isDark ? Colors.white : const Color(0xff000000),
              ),
              decoration: InputDecoration(
                hintText: hintText ?? 'Search products...',
                hintStyle: GoogleFonts.manrope(
                  fontWeight: FontWeight.w400,
                  color: isDark ? Colors.white54 : Colors.grey[600],
                  fontSize: 15,
                ),
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedPackage,
                    color: isDark ? Colors.white70 : const Color(0xff7F7F7F),
                    size: 18,
                  ),
                ),
                suffixIcon: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowDown01,
                    color: isDark ? Colors.white70 : const Color(0xff7F7F7F),
                    size: 16,
                  ),
                ),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF1E1E1E)
                    : const Color(0xffF8FAFB),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? Colors.white10 : Colors.grey[200]!,
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppTheme.primaryColor,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
            );
          },
          suggestionsCallback: (pattern) async {
            try {
              final client = await OdooSessionManager.getClient();
              if (client == null) return [];

              final limit = pattern.isEmpty ? 6 : 100;
              final results = await client.callKw({
                'model': 'product.product',
                'method': 'search_read',
                'args': [
                  [
                    ['sale_ok', '=', true],
                    ['active', '=', true],
                    if (pattern.isNotEmpty) ...[
                      '|',
                      ['name', 'ilike', pattern],
                      ['default_code', 'ilike', pattern],
                    ],
                  ],
                ],
                'kwargs': {
                  'fields': [
                    'id',
                    'name',
                    'list_price',
                    'qty_available',
                    'default_code',
                    'barcode',
                    'image_128',
                    'image_1920',
                    'product_variant_count',
                    'uom_id',
                    'taxes_id',
                    'categ_id',
                    'description_sale',
                  ],
                  'limit': limit,
                },
              });

              if (results is List) {
                return results.map((data) => Product.fromJson(data)).toList();
              }
              return [];
            } catch (e) {
              return [];
            }
          },
          itemBuilder: (context, product) {
            return ListTile(
              leading: _buildProductImage(product),
              title: Text(
                product.name,
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (product.defaultCode.isNotEmpty)
                    Text(
                      'SKU: ${product.defaultCode}',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  Text(
                    'Price: ${product.listPrice.toStringAsFixed(2)}',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                ],
              ),
              trailing: Text(
                'Stock: ${product.qtyAvailable.toStringAsFixed(0)}',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: product.qtyAvailable > 0 ? Colors.green : Colors.red,
                ),
              ),
            );
          },
          onSelected: onProductSelected,
          loadingBuilder: (context) => const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          emptyBuilder: (context) => Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'No products found',
              style: GoogleFonts.manrope(
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
          ),
          decorationBuilder: (context, child) => Material(
            type: MaterialType.card,
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            child: child,
          ),
        ),
      ],
    );
  }

  Widget _buildProductImage(Product product) {
    if (product.imageUrl != null && product.imageUrl!.isNotEmpty) {
      try {
        final base64String = product.imageUrl!.contains(',')
            ? product.imageUrl!.split(',')[1]
            : product.imageUrl!;
        final bytes = base64Decode(base64String);
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            image: DecorationImage(
              image: MemoryImage(bytes),
              fit: BoxFit.cover,
            ),
          ),
        );
      } catch (e) {}
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const HugeIcon(
        icon: HugeIcons.strokeRoundedPackage,
        color: AppTheme.primaryColor,
        size: 18,
      ),
    );
  }
}
