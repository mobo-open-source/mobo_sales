import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

import '../models/product.dart';
import '../services/odoo_session_manager.dart';
import '../shared/widgets/mobo/mobo_select_form_field.dart';
import '../utils/app_theme.dart';

/// Server-searched "add a product" picker, built on [MoboSelectFormField].
///
/// This is a search-and-add box rather than a held value: the parent adds the
/// chosen [Product] to its lines and the field goes back to empty, which is why
/// its `value` is always null.
class ProductTypeAhead extends StatefulWidget {
  final String labelText;

  /// Draws a red ` *` after [labelText].
  final bool isRequired;
  final String? hintText;
  final ValueChanged<Product> onProductSelected;
  final String? Function(Product?)? validator;

  const ProductTypeAhead({
    required this.labelText,
    this.isRequired = false,
    required this.onProductSelected,
    this.hintText,
    this.validator,
    super.key,
  });

  @override
  State<ProductTypeAhead> createState() => _ProductTypeAheadState();
}

class _ProductTypeAheadState extends State<ProductTypeAhead> {
  static const _debounce = Duration(milliseconds: 300);

  List<Product> _results = const [];
  bool _isLoading = false;
  Timer? _debounceTimer;

  /// Responses can arrive out of order; only the latest request may write.
  int _requestSeq = 0;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    // The unfiltered first page needs no debounce — nothing was typed.
    if (query.isEmpty) {
      _fetch(query);
      return;
    }
    _debounceTimer = Timer(_debounce, () => _fetch(query));
  }

  Future<void> _fetch(String pattern) async {
    final seq = ++_requestSeq;
    setState(() => _isLoading = true);

    final results = await _searchProducts(pattern);
    if (!mounted || seq != _requestSeq) return;
    setState(() {
      _results = results;
      _isLoading = false;
    });
  }

  Future<List<Product>> _searchProducts(String pattern) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return [];

      final limit = pattern.isEmpty ? 6 : 100;
      // Use safeCallKw (not the raw client) so the request carries the
      // active company context and refreshes an expired session, instead
      // of silently returning an empty list when the session has expired.
      final results = await OdooSessionManager.safeCallKw({
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
  }

  void _onChanged(String? id) {
    // Null is the field clearing itself after a pick; nothing to report.
    if (id == null) return;
    for (final product in _results) {
      if (product.id == id) {
        widget.onProductSelected(product);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MoboSelectFormField<String>(
      label: widget.labelText,
      isRequired: widget.isRequired,
      hintText: widget.hintText ?? 'Search products...',
      prefixHugeIcon: HugeIcons.strokeRoundedPackage,
      allowClear: false,
      options: [for (final product in _results) _optionFor(product)],
      value: null,
      isLoading: _isLoading,
      emptyText: 'No products found',
      onSearchChanged: _onSearchChanged,
      onChanged: _onChanged,
      validator: widget.validator == null
          ? null
          : (_) => widget.validator!(null),
    );
  }

  MoboOption<String> _optionFor(Product product) {
    return MoboOption<String>(
      value: product.id,
      label: product.name,
      subtitle: [
        if (product.defaultCode.isNotEmpty) 'SKU: ${product.defaultCode}',
        'Price: ${product.listPrice.toStringAsFixed(2)}',
      ].join('  •  '),
      leading: _buildProductImage(product),
      trailing: Text(
        'Stock: ${product.qtyAvailable.toStringAsFixed(0)}',
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: product.qtyAvailable > 0 ? Colors.green : Colors.red,
        ),
      ),
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
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            image: DecorationImage(
              image: MemoryImage(bytes),
              fit: BoxFit.cover,
            ),
          ),
        );
      } catch (e) {
        // Fall through to the placeholder below.
      }
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.1),
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
