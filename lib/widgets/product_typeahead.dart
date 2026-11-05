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

  /// Products per request. The list loads the next page as it is scrolled to
  /// the end; it used to read a fixed hundred and stop, so a larger catalogue
  /// could not be scrolled through at all.
  static const _pageSize = 30;

  /// The fields the row asks for. Not every one exists on every database:
  /// `qty_available` comes from the Inventory app, so a database with Sales
  /// but no Inventory has no such field, and asking for it makes the whole
  /// search fail ("Invalid field"). The server is asked which exist, once.
  static const _wantedFields = [
    'id',
    'name',
    'list_price',
    'qty_available',
    'default_code',
    'barcode',
    // The row draws a 36pt thumbnail, and `image_128` is a stored
    // resize of `image_1920`, so it is set whenever the full image
    // is. Asking for `image_1920` as well would pull a full-size
    // base64 image for every product in the page.
    'image_128',
    'product_variant_count',
    'uom_id',
    'taxes_id',
    'categ_id',
    'description_sale',
  ];

  /// Fields every database has: never dropped, even if the lookup fails.
  static const _coreFields = {'id', 'name', 'list_price', 'default_code'};

  List<String>? _knownFields;

  /// Whether the last search failed, as opposed to finding nothing.
  bool _failed = false;

  List<Product> _results = const [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String _query = '';
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

  /// The first page of [pattern], replacing what is shown.
  Future<void> _fetch(String pattern) async {
    final seq = ++_requestSeq;
    _query = pattern;
    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
    });

    final results = await _searchProducts(pattern, offset: 0);
    if (!mounted || seq != _requestSeq) return;
    setState(() {
      _results = results ?? const [];
      _failed = results == null;
      _hasMore = results != null && results.length == _pageSize;
      _isLoading = false;
    });
  }

  /// The next page of the search on screen, appended to it.
  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    final seq = _requestSeq;
    setState(() => _isLoadingMore = true);

    final page = await _searchProducts(_query, offset: _results.length);
    // A new search started meanwhile; this page belongs to the old one.
    if (!mounted || seq != _requestSeq) return;
    final known = {for (final p in _results) p.id};
    setState(() {
      _results = [
        ..._results,
        for (final p in page ?? const <Product>[])
          if (!known.contains(p.id)) p,
      ];
      _hasMore = page != null && page.length == _pageSize;
      _isLoadingMore = false;
    });
  }

  /// The wanted fields this database has.
  Future<List<String>> _fieldsToRead() async {
    final known = _knownFields;
    if (known != null) return known;
    try {
      final defs = await OdooSessionManager.safeCallKw({
        'model': 'product.product',
        'method': 'fields_get',
        'args': [],
        'kwargs': {
          'attributes': ['type'],
        },
      });
      if (defs is Map && defs.isNotEmpty) {
        return _knownFields = [
          for (final f in _wantedFields)
            if (_coreFields.contains(f) || defs.containsKey(f)) f,
        ];
      }
    } catch (_) {}
    // Not cached: the next search asks again. Meanwhile read what every
    // database has.
    return [..._coreFields, 'barcode', 'image_128', 'uom_id', 'categ_id'];
  }

  /// One page of products, or null when the search itself failed (which is
  /// not the same as finding nothing).
  Future<List<Product>?> _searchProducts(
    String pattern, {
    required int offset,
  }) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return null;
      final fields = await _fieldsToRead();

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
          'fields': fields,
          'limit': _pageSize,
          'offset': offset,
          // A stable order, or a page boundary can repeat or skip a product.
          'order': 'name asc, id asc',
        },
      });

      if (results is List) {
        return results.map((data) => Product.fromJson(data)).toList();
      }
      return null;
    } catch (e) {
      return null;
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
      emptyText: _failed
          ? "Couldn't load products. Check your connection and try again."
          : 'No products found',
      onSearchChanged: _onSearchChanged,
      onLoadMore: _loadMore,
      hasMore: _hasMore,
      isLoadingMore: _isLoadingMore,
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
      // Without the Inventory app there is no stock to show, and "Stock: 0"
      // in red would say the product has none.
      trailing: _knownFields?.contains('qty_available') == false
          ? null
          : Text(
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
