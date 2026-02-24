import 'package:flutter/material.dart';

import 'package:hugeicons/hugeicons.dart';
import '../models/product.dart';
import '../utils/app_theme.dart';

class ProductSelector extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final bool isDark;
  final bool showBorder;
  final bool isSearching;
  final bool showDropdown;
  final List<Product> products;
  final VoidCallback? onToggleDropdown;
  final ValueChanged<String>? onChanged;
  final ValueChanged<Product>? onProductSelected;
  final String? Function(String?)? validator;
  final VoidCallback? onAddProduct;

  const ProductSelector({
    required this.controller,
    required this.labelText,
    required this.isDark,
    required this.isSearching,
    required this.showDropdown,
    required this.products,
    this.hintText,
    this.showBorder = false,
    this.onToggleDropdown,
    this.onChanged,
    this.onProductSelected,
    this.validator,
    this.onAddProduct,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: TextStyle(
            fontWeight: FontWeight.w400,
            color: isDark ? Colors.white70 : const Color(0xff7F7F7F),
          ),
        ),
        const SizedBox(height: 8),
        Column(
          children: [
            TextFormField(
              controller: controller,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : const Color(0xff000000),
              ),
              decoration: InputDecoration(
                hintText: hintText ?? 'Type to search products...',
                hintStyle: TextStyle(
                  fontWeight: FontWeight.w400,
                  color: isDark ? Colors.white54 : Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: showBorder ? _getBorderColor() : Colors.transparent,
                    width: showBorder ? 2 : 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: showBorder ? _getBorderColor() : Colors.transparent,
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppTheme.primaryColor,
                    width: 1,
                  ),
                ),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF2A2A2A)
                    : const Color(0xffF8FAFB),
                prefixIcon: Icon(
                  HugeIcons.strokeRoundedShoppingBasket01,
                  color: isDark ? Colors.white70 : const Color(0xff7F7F7F),
                ),
                suffixIcon: _buildSuffixIcon(),
              ),
              onChanged: onChanged,
              validator: validator,
            ),
            if (showDropdown && products.isNotEmpty) _buildDropdown(),
          ],
        ),
      ],
    );
  }

  Widget? _buildSuffixIcon() {
    if (isSearching) {
      return Padding(
        padding: const EdgeInsets.all(12.0),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onAddProduct != null)
          IconButton(
            icon: Icon(
              HugeIcons.strokeRoundedAdd01,
              color: AppTheme.primaryColor,
            ),
            onPressed: onAddProduct,
            tooltip: 'Add Product',
          ),
        IconButton(
          icon: Icon(
            showDropdown
                ? HugeIcons.strokeRoundedArrowUp01
                : HugeIcons.strokeRoundedArrowDown01,
            color: isDark ? Colors.white70 : const Color(0xff7F7F7F),
          ),
          onPressed: onToggleDropdown,
        ),
      ],
    );
  }

  Widget _buildDropdown() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return _buildProductItem(product);
        },
      ),
    );
  }

  Widget _buildProductItem(Product product) {
    return InkWell(
      onTap: () => onProductSelected?.call(product),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                HugeIcons.strokeRoundedShoppingBasket01,
                color: AppTheme.primaryColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                  if (product.description?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(
                      product.description!,
                      style: TextStyle(
                        fontWeight: FontWeight.w400,
                        color: isDark ? Colors.white60 : Colors.grey[600],
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              product.listPrice.toStringAsFixed(2),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBorderColor() {
    return isDark ? Colors.grey[600]! : Colors.grey[400]!;
  }
}
