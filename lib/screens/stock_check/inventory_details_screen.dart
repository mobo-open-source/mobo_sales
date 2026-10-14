import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../services/odoo_error_handler.dart';
import '../../utils/app_theme.dart';
import '../../widgets/custom_snackbar.dart';

/// The stock of one product variant: what is on hand, reserved and forecast,
/// where it sits, and what is on its way in or out.
///
/// Laid out like the Product Details page: a header card with the product and
/// its figures, then one card per topic. The screen only presents; the figures
/// come from [loadInventory], so the caller decides where they are read from.
class InventoryDetailsScreen extends StatefulWidget {
  const InventoryDetailsScreen({
    super.key,
    required this.variant,
    required this.loadInventory,
    this.template,
    this.loadAttributes,
  });

  /// The variant being looked at: `name`, `default_code`, `barcode`, `image_url`.
  final Map<String, dynamic> variant;

  /// The product the variant belongs to; gives the category, and the picture
  /// when the variant has none of its own.
  final Map<String, dynamic>? template;

  /// Reads the stock figures, the locations and the pending moves.
  final Future<Map<String, dynamic>> Function() loadInventory;

  /// Reads the variant's attribute values ("Color: White"). Optional; the stock
  /// does not depend on them.
  final Future<List<Map<String, String>>> Function()? loadAttributes;

  @override
  State<InventoryDetailsScreen> createState() => _InventoryDetailsScreenState();
}

class _InventoryDetailsScreenState extends State<InventoryDetailsScreen> {
  Map<String, dynamic>? _inventory;
  Object? _error;
  bool _fetching = false;
  List<Map<String, String>> _attributes = const [];
  late final Uint8List? _imageBytes = _decodeImage(
    widget.variant['image_url'] ?? widget.template?['image_url'],
  );

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _titleColor => _isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get _bodyColor => _isDark ? Colors.white : Colors.black87;
  Color get _mutedColor => _isDark ? Colors.grey[400]! : Colors.grey[600]!;
  Color get _dividerColor => _isDark ? Colors.white12 : Colors.black12;
  Color get _positiveColor => _isDark ? Colors.green[300]! : Colors.green[700]!;
  Color get _negativeColor => _isDark ? Colors.red[300]! : Colors.red[700]!;

  @override
  void initState() {
    super.initState();
    _fetch();
    _fetchAttributes();
  }

  /// Reads the stock. While nothing has been read yet the page shows a
  /// skeleton; a refresh later keeps the page and swaps the figures in place.
  Future<void> _fetch() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final inventory = await widget.loadInventory();
      if (!mounted) return;
      setState(() {
        _inventory = inventory;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (_inventory == null) {
        setState(() => _error = e);
      } else {
        CustomSnackbar.showError(
          context,
          OdooErrorHandler.toSnackbarMessage(
            e,
            fallback: 'Could not refresh the stock. Please try again.',
          ),
        );
      }
    } finally {
      _fetching = false;
    }
  }

  Future<void> _fetchAttributes() async {
    final loader = widget.loadAttributes;
    if (loader == null) return;
    try {
      final attributes = await loader();
      if (mounted) setState(() => _attributes = attributes);
    } catch (_) {
      // They only decorate the header.
    }
  }

  void _retry() {
    setState(() => _error = null);
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _isDark;
    final inventory = _inventory;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Inventory Details',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        backgroundColor: isDark ? Colors.grey[900]! : Colors.grey[50],
      ),
      body: RefreshIndicator(
        color: isDark ? Colors.blue[200] : Theme.of(context).primaryColor,
        onRefresh: _fetch,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderCard(),
              if (inventory != null)
                ..._buildSections(inventory)
              else if (_error != null)
                _buildErrorCard()
              else
                _buildSkeleton(),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- header

  Widget _buildHeaderCard() {
    final variant = widget.variant;
    final name = _displayName(variant['name']);
    final category = _text(widget.template?['category']);
    final sku = _text(variant['default_code']);
    final barcode = _text(variant['barcode']);
    final inventory = _inventory;

    double? figure(String key) => (inventory?[key] as num?)?.toDouble();
    final onHand = figure('totalInStock');
    final reserved = figure('totalReserved');
    final forecasted = figure('forecastedStock');
    final incoming = figure('totalIncoming') ?? 0;
    final outgoing = figure('totalOutgoing') ?? 0;

    return Container(
      width: double.infinity,
      decoration: _cardDecoration(radius: 16),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildImage(name),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: name.length > 20
                            ? 20
                            : (name.length > 15 ? 22 : 24),
                        fontWeight: FontWeight.bold,
                        color: _titleColor,
                      ),
                    ),
                    if (category != null || sku != null || barcode != null)
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          if (category != null)
                            _metaItem(
                              HugeIcons.strokeRoundedFilterMailCircle,
                              category,
                            ),
                          if (sku != null)
                            _metaItem(HugeIcons.strokeRoundedQrCode, sku),
                          if (barcode != null)
                            _metaItem(
                              HugeIcons.strokeRoundedBarCode02,
                              barcode,
                            ),
                        ],
                      ),
                    if (_attributes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final attribute in _attributes)
                            _attributePill(
                              '${attribute['attribute_name']}: '
                              '${attribute['value_name']}',
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: _dividerColor, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _metric(
                  'On Hand',
                  onHand,
                  color: onHand == null
                      ? null
                      : (onHand > 0 ? _positiveColor : _negativeColor),
                ),
              ),
              Expanded(child: _metric('Reserved', reserved)),
              Expanded(child: _metric('Forecasted', forecasted)),
            ],
          ),
          if (incoming > 0 || outgoing > 0) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (incoming > 0)
                  _flowPill(
                    HugeIcons.strokeRoundedCircleArrowDownLeft,
                    '${_qty(incoming)} incoming',
                  ),
                if (outgoing > 0)
                  _flowPill(
                    HugeIcons.strokeRoundedCircleArrowUpRight,
                    '${_qty(outgoing)} outgoing',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImage(String name) {
    final isDark = _isDark;
    final bytes = _imageBytes;
    final initial = Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white70 : Colors.black45,
        ),
      ),
    );

    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: _shadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: isDark ? Colors.white10 : Colors.grey[100],
          child: bytes == null
              ? initial
              : Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => initial,
                ),
        ),
      ),
    );
  }

  Widget _metaItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _mutedColor),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: _isDark ? Colors.white60 : Colors.black54,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _attributePill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: _isDark ? 0.22 : 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: _isDark ? Colors.white : AppTheme.primaryColor,
        ),
      ),
    );
  }

  /// One figure of the header: its label, and its value (a placeholder while
  /// the stock is being read, a dash when it could not be).
  Widget _metric(String label, double? value, {Color? color}) {
    final Widget valueWidget;
    if (value != null) {
      valueWidget = Text(
        _qty(value),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color ?? _bodyColor,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      );
    } else if (_error != null) {
      valueWidget = Text(
        '–',
        style: TextStyle(
          color: _mutedColor,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      );
    } else {
      valueWidget = Shimmer.fromColors(
        baseColor: _shimmerBase,
        highlightColor: _shimmerHighlight,
        child: Container(
          width: 44,
          height: 18,
          decoration: BoxDecoration(
            color: _shimmerBase,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _mutedColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 20,
          child: Align(alignment: Alignment.centerLeft, child: valueWidget),
        ),
      ],
    );
  }

  Widget _flowPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _isDark ? Colors.white10 : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _mutedColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: _bodyColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- sections

  List<Widget> _buildSections(Map<String, dynamic> inventory) {
    List<Map<String, dynamic>> rows(String key) =>
        (inventory[key] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    final stockDetails = rows('stock_details');
    final incoming = rows('incoming_stock');
    final outgoing = rows('outgoing_stock');

    // What counts towards the totals first, the reference-only locations after.
    final counted = stockDetails.where(_isCounted).toList();
    final reference = stockDetails.where((s) => !_isCounted(s)).toList();
    final locations = [...counted, ...reference];

    return [
      _sectionCard(
        title: 'Stock Locations',
        gap: 8,
        children: [
          if (locations.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No stock is recorded in any location.',
                style: TextStyle(color: _mutedColor, fontSize: 14),
              ),
            )
          else
            for (var i = 0; i < locations.length; i++)
              _locationRow(locations[i], isLast: i == locations.length - 1),
          const SizedBox(height: 12),
          _buildCalculationNote(),
        ],
      ),
      if (incoming.isNotEmpty)
        _sectionCard(
          title: 'Incoming Shipments',
          gap: 8,
          children: [
            for (var i = 0; i < incoming.length; i++)
              _shipmentRow(
                incoming[i],
                incoming: true,
                isLast: i == incoming.length - 1,
              ),
          ],
        ),
      if (outgoing.isNotEmpty)
        _sectionCard(
          title: 'Outgoing Shipments',
          gap: 8,
          children: [
            for (var i = 0; i < outgoing.length; i++)
              _shipmentRow(
                outgoing[i],
                incoming: false,
                isLast: i == outgoing.length - 1,
              ),
          ],
        ),
      const SizedBox(height: 24),
    ];
  }

  bool _isCounted(Map<String, dynamic> stock) =>
      stock['is_counted_in_totals'] == true;

  Widget _sectionCard({
    required String title,
    required List<Widget> children,
    double gap = 20,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        width: double.infinity,
        decoration: _cardDecoration(),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _titleColor,
              ),
            ),
            SizedBox(height: gap),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _locationRow(Map<String, dynamic> stock, {required bool isLast}) {
    final counted = _isCounted(stock);
    final quantity = (stock['quantity'] as num?)?.toDouble() ?? 0;
    final reserved = (stock['reserved_quantity'] as num?)?.toDouble() ?? 0;

    final name = _text(stock['warehouse']) ?? 'Unknown location';
    final String detail;
    if (counted) {
      detail = [
        'Internal',
        if (reserved > 0) '${_qty(reserved)} reserved',
      ].join(' · ');
    } else {
      final usage = _usageLabel(stock['location_type']);
      // "Customers" already says it is a customer location.
      final repeated = name.toLowerCase().contains(usage.toLowerCase());
      detail = repeated ? 'Not counted' : '$usage · Not counted';
    }

    // Only the locations that count towards the totals are coloured; a
    // customer location going negative is normal and not a warning.
    final quantityColor = !counted || quantity == 0
        ? _mutedColor
        : (quantity > 0 ? _positiveColor : _negativeColor);

    return _listRow(
      isLast: isLast,
      icon: counted
          ? HugeIcons.strokeRoundedWarehouse
          : HugeIcons.strokeRoundedLocation01,
      iconColor: counted ? AppTheme.primaryColor : _mutedColor,
      iconBackground: counted
          ? AppTheme.primaryColor.withValues(alpha: _isDark ? 0.22 : 0.1)
          : (_isDark ? Colors.white10 : Colors.grey[100]!),
      title: name,
      subtitle: Text(
        detail,
        style: TextStyle(color: _mutedColor, fontSize: 12),
      ),
      trailing: Text(
        _qty(quantity),
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: quantityColor,
        ),
      ),
    );
  }

  Widget _shipmentRow(
    Map<String, dynamic> shipment, {
    required bool incoming,
    required bool isLast,
  }) {
    final quantity = (shipment['quantity'] as num?)?.toDouble() ?? 0;
    final from = _text(shipment['from_location']) ?? 'Unknown';
    final to = _text(shipment['to_location']) ?? 'Unknown';
    final style = TextStyle(color: _mutedColor, fontSize: 12);

    return _listRow(
      isLast: isLast,
      icon: incoming
          ? HugeIcons.strokeRoundedCircleArrowDownLeft
          : HugeIcons.strokeRoundedCircleArrowUpRight,
      iconColor: _mutedColor,
      iconBackground: _isDark ? Colors.white10 : Colors.grey[100]!,
      title: '${_qty(quantity)} ${quantity == 1 ? 'item' : 'items'}',
      subtitle: Row(
        children: [
          Flexible(
            child: Text(from, style: style, overflow: TextOverflow.ellipsis),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              HugeIcons.strokeRoundedArrowRight01,
              size: 12,
              color: _mutedColor,
            ),
          ),
          Flexible(
            child: Text(to, style: style, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      trailing: Text(
        _date(shipment[incoming ? 'expected_date' : 'date_expected']),
        style: style,
      ),
    );
  }

  /// A row of a list card: a tinted icon, a title with something at its end
  /// (a quantity, a date), and a line under it as wide as the row allows.
  Widget _listRow({
    required bool isLast,
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
    required String title,
    required Widget subtitle,
    Widget? trailing,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _bodyColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 12),
                          trailing,
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    subtitle,
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast) Divider(height: 1, color: _dividerColor),
      ],
    );
  }

  /// Why some locations are listed but not added up.
  Widget _buildCalculationNote() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            HugeIcons.strokeRoundedInformationCircle,
            size: 14,
            color: _mutedColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Totals count internal warehouse locations only. Customer, '
            'vendor and other external locations are shown for reference.',
            style: TextStyle(color: _mutedColor, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------- loading and error

  Color get _shimmerBase => _isDark ? Colors.grey[800]! : Colors.grey[300]!;
  Color get _shimmerHighlight =>
      _isDark ? Colors.grey[700]! : Colors.grey[100]!;

  Widget _buildSkeleton() {
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _shimmerBase,
        borderRadius: BorderRadius.circular(4),
      ),
    );

    Widget row() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _shimmerBase,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [bar(140, 14), bar(30, 14)],
                ),
                const SizedBox(height: 6),
                bar(90, 12),
              ],
            ),
          ),
        ],
      ),
    );

    Widget card(int rows) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        width: double.infinity,
        decoration: _cardDecoration(),
        padding: const EdgeInsets.all(18),
        // Only the bars shimmer: a card painted inside the mask would turn
        // into one grey block.
        child: Shimmer.fromColors(
          baseColor: _shimmerBase,
          highlightColor: _shimmerHighlight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bar(160, 22),
              const SizedBox(height: 8),
              for (var i = 0; i < rows; i++) row(),
            ],
          ),
        ),
      ),
    );

    return Column(children: [card(3), card(2)]);
  }

  Widget _buildErrorCard() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        width: double.infinity,
        decoration: _cardDecoration(),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _negativeColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                HugeIcons.strokeRoundedAlert02,
                size: 28,
                color: _negativeColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Unable to load inventory',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _titleColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              OdooErrorHandler.toSnackbarMessage(
                _error,
                fallback: 'Please check your connection and try again.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: _mutedColor, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _retry,
              icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 18),
              label: const Text('Try again'),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- helpers

  List<BoxShadow> get _shadow => [
    BoxShadow(
      color: _isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.05),
      blurRadius: 16,
      spreadRadius: 2,
      offset: const Offset(0, 6),
    ),
  ];

  BoxDecoration _cardDecoration({double radius = 12}) => BoxDecoration(
    color: _isDark ? Colors.grey[900] : Colors.white,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: _shadow,
  );
}

/// [value] as text when it holds something: not null, not a boolean (Odoo
/// sends `false` for an empty field), not blank and not the list's `N/A`
/// placeholder.
String? _text(dynamic value) {
  if (value is! String) return null;
  final text = value.trim();
  if (text.isEmpty) return null;
  final lower = text.toLowerCase();
  if (lower == 'n/a' || lower == 'false' || lower == 'null') return null;
  return text;
}

/// The variant's name without the ` [SKU]` suffix some servers add.
String _displayName(dynamic name) =>
    (_text(name) ?? 'Unknown product').split(' [').first;

/// The picture as bytes, or null when there is none or it cannot be read.
Uint8List? _decodeImage(dynamic raw) {
  if (raw is! String || raw.isEmpty || raw.startsWith('http')) return null;
  try {
    return base64Decode(raw.split(',').last);
  } catch (_) {
    return null;
  }
}

/// A quantity without trailing zeros: `14`, `2.5`, `0.25`.
String _qty(double value) {
  if (value.abs() < 0.005) return '0';
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

/// An Odoo UTC timestamp as a local date, `12 Oct 2026`.
String _date(dynamic raw) {
  if (raw is! String || raw.isEmpty || raw == 'N/A') return 'Not specified';
  final parsed = DateTime.tryParse('${raw.replaceFirst(' ', 'T')}Z');
  if (parsed == null) return raw;
  return DateFormat('d MMM yyyy').format(parsed.toLocal());
}

/// What an Odoo location `usage` is called to the user.
String _usageLabel(dynamic usage) {
  switch (usage) {
    case 'supplier':
      return 'Vendor';
    case 'customer':
      return 'Customer';
    case 'inventory':
      return 'Inventory adjustment';
    case 'production':
      return 'Production';
    case 'transit':
      return 'Transit';
    case 'view':
      return 'View';
    case 'internal':
      return 'Internal';
    default:
      return 'Other';
  }
}
