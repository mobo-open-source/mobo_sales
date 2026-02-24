import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:mobo_sales/models/product.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/widgets/custom_snackbar.dart';
import 'package:provider/provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/last_opened_provider.dart';
import 'package:mobo_sales/screens/products/product_sales_history_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/app_theme.dart';
import '../../widgets/full_image_screen.dart';
import 'create_product_screen.dart';
import '../../services/permission_service.dart';
import '../../services/field_validation_service.dart';

class ProductDetailsPage extends StatefulWidget {
  final Product product;

  const ProductDetailsPage({super.key, required this.product});

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  bool _isFetchingImage = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  static final Map<String, Product> _productCache = {};
  Map<String, dynamic>? _salesOrderLines;
  Map<String, dynamic>? _quotationLines;
  double? _totalSold;
  double? _averageOrderValue;
  bool hasInventoryModule = false;
  Product? _loadedProduct;
  bool _attributesExpanded = false;

  bool _hasUsefulDirectAttributes(Product product) {
    final attrs = product.attributes;
    if (attrs == null || attrs.isEmpty) return false;
    for (final a in attrs) {
      if (a.values.isNotEmpty) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trackProductAccess();
      _loadProductDetails();
      _checkInventoryModule();
    });
  }

  void _trackProductAccess() {
    try {
      final lastOpenedProvider = Provider.of<LastOpenedProvider>(
        context,
        listen: false,
      );
      final productId = widget.product.id.toString() ?? '';
      final productName = widget.product.name ?? 'Product';
      final category =
          widget.product.category ?? widget.product.categId?.toString();

      lastOpenedProvider.trackProductAccess(
        productId: productId,
        productName: productName,
        category: category,
        productData: widget.product.toJson(),
      );
    } catch (e) {}
  }

  Future<void> _checkInventoryModule() async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        if (mounted) {
          CustomSnackbar.showError(
            context,
            'No active Odoo session. Please log in again.',
          );
        }
        return;
      }

      final inventoryModule = await client.callKw({
        'model': 'ir.module.module',
        'method': 'search_read',
        'args': [
          [
            ['name', '=', 'stock'],
            ['state', '=', 'installed'],
          ],
        ],
        'kwargs': {
          'fields': ['state', 'name'],
          'limit': 1,
        },
      });

      if (mounted) {
        setState(() {
          hasInventoryModule =
              inventoryModule is List && inventoryModule.isNotEmpty;
        });
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Failed to check inventory module: $e',
        );
      }
    }
  }

  Future<void> _ensureAttributesResolved() async {
    try {
      final product = _productCache[widget.product.id] ?? widget.product;
      final alreadyResolved =
          (product.extraData != null &&
          (product.extraData!['resolvedAttributes'] is List) &&
          (product.extraData!['resolvedAttributes'] as List).isNotEmpty);
      if (alreadyResolved) return;
      final bool attrsMissing = !_hasUsefulDirectAttributes(product);
      final bool hasPTAV = product.productTemplateAttributeValueIds.isNotEmpty;
      final bool canUseTemplate = (product.templateId != null);
      final bool needsResolve = attrsMissing && (hasPTAV || canUseTemplate);
      if (!needsResolve) return;
      final client = await OdooSessionManager.getClient();
      if (client == null) return;
      final valueIds = product.productTemplateAttributeValueIds;
      var values = [];
      if (hasPTAV) {
        values = await client.callKw({
          'model': 'product.template.attribute.value',
          'method': 'search_read',
          'args': [
            [
              ['id', 'in', valueIds],
            ],
          ],
          'kwargs': {
            'fields': [
              'name',
              'display_name',
              'attribute_id',
              'product_attribute_value_id',
            ],
            'limit': valueIds.length,
          },
        });
      }
      final Map<String, List<String>> grouped = {};
      for (final v in values) {
        final attrName =
            (v['attribute_id'] is List && v['attribute_id'].length > 1)
            ? (v['attribute_id'][1]?.toString() ?? 'Attribute')
            : 'Attribute';
        String valName = (v['name']?.toString() ?? '').trim();
        if (valName.isEmpty) {
          valName = (v['display_name']?.toString() ?? '').trim();
        }
        if (valName.isEmpty &&
            v['product_attribute_value_id'] is List &&
            v['product_attribute_value_id'].length > 1) {
          valName = v['product_attribute_value_id'][1]?.toString() ?? '';
        }
        if (valName.isEmpty) continue;
        grouped.putIfAbsent(attrName, () => []);
        if (!grouped[attrName]!.contains(valName)) {
          grouped[attrName]!.add(valName);
        }
      }
      if (grouped.isEmpty && (product.templateId != null)) {
        final groupedFromTemplate = await _resolveAttributesViaTemplate(
          client,
          product.templateId!,
        );
        grouped.addAll(groupedFromTemplate);
      }
      if (grouped.isEmpty && canUseTemplate) {
        final tplGrouped = await _resolveAttributesViaTemplate(
          client,
          product.templateId!,
        );
        grouped.addAll(tplGrouped);
      }
      if (grouped.isNotEmpty) {
        final resolvedAttributes = grouped.entries
            .map((e) => {'name': e.key, 'values': e.value})
            .toList();
        product.extraData ??= {};
        product.extraData!['resolvedAttributes'] = resolvedAttributes;
        if (mounted) setState(() {});
      }
    } catch (e) {}
  }

  Future<Map<String, List<String>>> _resolveAttributesViaTemplate(
    dynamic client,
    int templateId,
  ) async {
    final Map<String, List<String>> grouped = {};
    try {
      final lines = await client.callKw({
        'model': 'product.template.attribute.line',
        'method': 'search_read',
        'args': [
          [
            ['product_tmpl_id', '=', templateId],
          ],
        ],
        'kwargs': {
          'fields': ['attribute_id', 'value_ids'],
          'limit': 100,
        },
      });
      if (lines is! List || lines.isEmpty) return grouped;
      final Set<int> valueIds = {};
      final List<Map<String, dynamic>> castLines =
          List<Map<String, dynamic>>.from(lines);
      for (final ln in castLines) {
        final vals =
            (ln['value_ids'] as List?)?.whereType<int>().toList() ?? const [];
        valueIds.addAll(vals);
      }
      if (valueIds.isEmpty) return grouped;
      final values = await client.callKw({
        'model': 'product.attribute.value',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', valueIds.toList()],
          ],
        ],
        'kwargs': {
          'fields': ['name', 'attribute_id'],
          'limit': valueIds.length,
        },
      });
      if (values is List) {
        for (final v in values) {
          final attrName =
              (v['attribute_id'] is List && v['attribute_id'].length > 1)
              ? (v['attribute_id'][1]?.toString() ?? 'Attribute')
              : 'Attribute';
          final valName = (v['name']?.toString() ?? '').trim();
          if (valName.isEmpty) continue;
          grouped.putIfAbsent(attrName, () => []);
          if (!grouped[attrName]!.contains(valName)) {
            grouped[attrName]!.add(valName);
          }
        }
      }
    } catch (e) {}
    return grouped;
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadProductDetails({bool forceRefresh = false}) async {
    final id = widget.product.id;
    if (!forceRefresh && _productCache.containsKey(id)) {
      await _ensureAnalyticsLoaded();
      await _ensureAttributesResolved();

      if (mounted) {
        setState(() => _isLoading = false);
        if (!_fadeController.isAnimating && !_fadeController.isCompleted) {
          _fadeController.forward();
        }
      }
      return;
    }

    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No Odoo client');

      final availableFieldsResult = await client.callKw({
        'model': 'product.product',
        'method': 'fields_get',
        'args': [],
        'kwargs': {
          'attributes': ['name'],
        },
      });
      final availableFields = availableFieldsResult.keys
          .toList()
          .cast<String>();

      final List<String> fields = [
        'id',
        'name',
        'list_price',
        'default_code',
        'barcode',
        'categ_id',
        'image_1920',
        'description_sale',
        'create_date',
        'currency_id',
        'standard_price',
        'list_price',
        'product_variant_count',
        'product_template_attribute_value_ids',
        'product_template_variant_value_ids',
        'product_tmpl_id',
        'taxes_id',
        'seller_ids',
        'active',
        'type',
        'company_id',
        'write_date',
      ];

      final List<String> optionalFields = [
        'attributes',
        'qty_available',
        'virtual_available',
        'outgoing_qty',
        'weight',
        'volume',
        'dimensions',
        'lead_time',
        'procurement_route',
        'cost_method',
        'property_account_income',
        'property_account_expense',
        'property_stock_inventory',
        'property_stock_production',
        'sale_ok',
        'purchase_ok',
        'invoice_policy',
        'sale_delay',
        'customer_lead',
        'description',
        'description_purchase',
        'uom_id',
        'uom_po_id',
      ];
      for (final field in optionalFields) {
        if (availableFields.contains(field)) fields.add(field);
      }

      final result =
          await FieldValidationService.executeWithFieldValidation<
            List<dynamic>
          >(
            model: 'product.product',
            apiCall: (currentFields) async {
              return await client.callKw({
                'model': 'product.product',
                'method': 'read',
                'args': [
                  [int.parse(id)],
                ],
                'kwargs': {'fields': currentFields},
              });
            },
            initialFields: fields,
          );

      if (result.isNotEmpty) {
        try {
          final product = Product.fromJson(result[0]);
          try {
            product.extraData ??= {};
            if (widget.product.selectedVariants != null &&
                widget.product.selectedVariants!.isNotEmpty) {
              product.extraData!['passedSelectedVariants'] =
                  Map<String, String>.from(widget.product.selectedVariants!);
            }
            if (widget.product.attributes != null &&
                widget.product.attributes!.isNotEmpty) {
              product.extraData!['passedAttributes'] = widget
                  .product
                  .attributes!
                  .map(
                    (a) => {
                      'name': a.name,
                      'values': List<String>.from(a.values),
                    },
                  )
                  .toList();
            }
          } catch (_) {}
          _productCache[id] = product;

          List<String> taxNames = [];
          if (result[0]['taxes_id'] is List &&
              (result[0]['taxes_id'] as List).isNotEmpty) {
            final taxes = await client.callKw({
              'model': 'account.tax',
              'method': 'search_read',
              'args': [
                [
                  ['id', 'in', result[0]['taxes_id']],
                ],
              ],
              'kwargs': {
                'fields': ['name'],
              },
            });
            taxNames = taxes
                .map<String>((t) => (t['name']?.toString() ?? 'Unknown Tax'))
                .toList();
          }
          product.extraData ??= {};
          product.extraData?['taxNames'] = taxNames;

          List<Map<String, dynamic>> suppliers = [];
          List<String> supplierFields = ['name', 'price'];
          int supplierRetryCount = 0;
          const int supplierMaxRetries = 3;
          while (supplierRetryCount < supplierMaxRetries) {
            try {
              if (result[0]['seller_ids'] is List &&
                  (result[0]['seller_ids'] as List).isNotEmpty &&
                  supplierFields.isNotEmpty) {
                final sellers = await client.callKw({
                  'model': 'product.supplierinfo',
                  'method': 'search_read',
                  'args': [
                    [
                      ['id', 'in', result[0]['seller_ids']],
                    ],
                  ],
                  'kwargs': {'fields': supplierFields},
                });
                suppliers = List<Map<String, dynamic>>.from(sellers);
              }
              break;
            } catch (e) {
              if (e.toString().contains('Invalid field')) {
                final fieldMatch = RegExp(
                  r"Invalid field '([^']+)' on model",
                ).firstMatch(e.toString());
                final invalidField = fieldMatch?.group(1);
                if (invalidField != null &&
                    supplierFields.contains(invalidField)) {
                  supplierFields.remove(invalidField);
                  supplierRetryCount++;
                  await Future.delayed(const Duration(milliseconds: 300));
                  continue;
                }
              }

              break;
            }
          }
          product.extraData?['suppliers'] = suppliers;

          try {
            final bool attrsMissing = !_hasUsefulDirectAttributes(product);
            final List<int> ptavIds = product.productTemplateAttributeValueIds;
            final raw = result[0] as Map<String, dynamic>;
            final variantIds =
                (raw['product_template_variant_value_ids'] as List?)
                    ?.whereType<int>()
                    .toList() ??
                const [];
            final allValueIds = {...ptavIds, ...variantIds}.toList();
            final bool hasPTAV = allValueIds.isNotEmpty;
            final bool canUseTemplate = (product.templateId != null);
            final bool needsResolve =
                attrsMissing && (hasPTAV || canUseTemplate);
            if (needsResolve) {
              final Map<String, List<String>> grouped = {};
              if (hasPTAV) {
                final valueIds = allValueIds;
                final values = await client.callKw({
                  'model': 'product.template.attribute.value',
                  'method': 'search_read',
                  'args': [
                    [
                      ['id', 'in', valueIds],
                    ],
                  ],
                  'kwargs': {
                    'fields': [
                      'name',
                      'display_name',
                      'attribute_id',
                      'product_attribute_value_id',
                    ],
                    'limit': valueIds.length,
                  },
                });
                if (values is List) {
                  for (final v in values) {
                    final attrName =
                        (v['attribute_id'] is List &&
                            v['attribute_id'].length > 1)
                        ? (v['attribute_id'][1]?.toString() ?? 'Attribute')
                        : 'Attribute';
                    String valName = (v['name']?.toString() ?? '').trim();
                    if (valName.isEmpty) {
                      valName = (v['display_name']?.toString() ?? '').trim();
                    }
                    if (valName.isEmpty &&
                        v['product_attribute_value_id'] is List &&
                        v['product_attribute_value_id'].length > 1) {
                      valName =
                          v['product_attribute_value_id'][1]?.toString() ?? '';
                    }
                    if (valName.isEmpty) continue;
                    grouped.putIfAbsent(attrName, () => []);
                    if (!grouped[attrName]!.contains(valName)) {
                      grouped[attrName]!.add(valName);
                    }
                  }
                }
              }
              if (grouped.isEmpty && canUseTemplate) {
                final fromTpl = await _resolveAttributesViaTemplate(
                  client,
                  product.templateId!,
                );
                grouped.addAll(fromTpl);
              }

              if (grouped.isNotEmpty) {
                final resolvedAttributes = grouped.entries
                    .map((e) => {'name': e.key, 'values': e.value})
                    .toList();
                product.extraData ??= {};
                product.extraData!['resolvedAttributes'] = resolvedAttributes;
              }
            }
          } catch (e) {}

          List<dynamic> sales = [];
          List<String> salesFields = ['order_id', 'create_date'];
          int salesRetryCount = 0;
          const int salesMaxRetries = 3;
          while (salesRetryCount < salesMaxRetries) {
            try {
              sales = await client.callKw({
                'model': 'sale.order.line',
                'method': 'search_read',
                'args': [
                  [
                    ['product_id', '=', int.parse(id)],
                  ],
                ],
                'kwargs': {'fields': salesFields, 'limit': 100},
              });
              break;
            } catch (e) {
              final es = e.toString();
              if (es.contains('Invalid field')) {
                final match = RegExp(
                  r"Invalid field '([^']+)' on",
                ).firstMatch(es);
                final invalidField = match?.group(1);
                if (invalidField != null &&
                    salesFields.contains(invalidField)) {
                  salesFields.remove(invalidField);
                  salesRetryCount++;
                  await Future.delayed(const Duration(milliseconds: 300));
                  continue;
                }
              }

              break;
            }
          }
          int totalSales = sales.length;
          String lastSaleDate =
              sales.isNotEmpty && salesFields.contains('create_date')
              ? sales
                    .map((s) => s['create_date'])
                    .reduce((a, b) => a.compareTo(b) > 0 ? a : b)
              : 'N/A';
          Map<String, int> customerCount = {};
          String topCustomer = customerCount.entries.isNotEmpty
              ? customerCount.entries
                    .reduce((a, b) => a.value > b.value ? a : b)
                    .key
              : 'N/A';
          product.extraData?['salesAnalytics'] = {
            'totalSales': totalSales,
            'lastSaleDate': lastSaleDate,
            'topCustomer': topCustomer,
          };

          await _loadSalesAnalytics(client, int.parse(id));

          await _ensureAttributesResolved();

          if (mounted) {
            setState(() {
              _isLoading = false;
              _loadedProduct = product;
            });
            if (!_fadeController.isAnimating && !_fadeController.isCompleted) {
              _fadeController.forward();
            }
          }
        } catch (e) {
          if (mounted) {
            setState(() => _isLoading = false);
          }
        }
      } else {
        throw Exception('Product not found');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to load product details: ${e.toString().contains('not found') ? 'Product not found' : 'Please try again'}',
            ),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                setState(() => _isLoading = true);
                _loadProductDetails(forceRefresh: true);
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadSalesAnalytics(client, int productId) async {
    try {
      final salesOrderResult = await client.callKw({
        'model': 'sale.order.line',
        'method': 'search_read',
        'args': [
          [
            ['product_id', '=', productId],
            [
              'state',
              'in',
              ['sale', 'done'],
            ],
          ],
        ],
        'kwargs': {
          'fields': [
            'product_uom_qty',
            'price_subtotal',
            'order_id',
            'create_date',
          ],
          'limit': 100,
        },
      });

      if (salesOrderResult is List) {
        double totalQuantity = 0;
        double totalValue = 0;
        for (var line in salesOrderResult) {
          totalQuantity += (line['product_uom_qty'] ?? 0.0);
          totalValue += (line['price_subtotal'] ?? 0.0);
        }
        _totalSold = totalQuantity;
        _averageOrderValue = salesOrderResult.isNotEmpty
            ? totalValue / salesOrderResult.length
            : 0;
      }

      final quotationResult = await client.callKw({
        'model': 'sale.order.line',
        'method': 'search_read',
        'args': [
          [
            ['product_id', '=', productId],
            ['state', '=', 'draft'],
          ],
        ],
        'kwargs': {
          'fields': ['product_uom_qty', 'price_subtotal'],
          'limit': 50,
        },
      });

      if (quotationResult is List) {
        double quotationQty = 0;
        for (var line in quotationResult) {
          quotationQty += (line['product_uom_qty'] ?? 0.0);
        }
        _quotationLines = {
          'total_qty': quotationQty,
          'count': quotationResult.length,
        };
      }
    } catch (e) {}
  }

  Product get _product => _productCache[widget.product.id] ?? widget.product;

  Widget _buildShimmer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shimmerBase = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final shimmerHighlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Shimmer.fromColors(
        baseColor: shimmerBase,
        highlightColor: shimmerHighlight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildShimmerCard([
              Center(
                child: Container(
                  width: 200,
                  height: 160,
                  decoration: BoxDecoration(
                    color: shimmerBase,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ]),

            const SizedBox(height: 16),

            _buildShimmerCard([
              Container(height: 28, width: 280, color: shimmerBase),
              const SizedBox(height: 12),
              Container(height: 18, width: 150, color: shimmerBase),
              const SizedBox(height: 8),
              Container(height: 18, width: 120, color: shimmerBase),
              const SizedBox(height: 8),
              Container(height: 24, width: 100, color: shimmerBase),
            ]),

            const SizedBox(height: 16),

            _buildShimmerCard([
              Container(height: 24, width: 180, color: shimmerBase),
              const SizedBox(height: 16),
              _buildShimmerInfoRow(),
              const SizedBox(height: 12),
              _buildShimmerInfoRow(),
              const SizedBox(height: 12),

              _buildShimmerInfoRow(),
              const SizedBox(height: 12),

              _buildShimmerInfoRow(),
              const SizedBox(height: 12),

              _buildShimmerInfoRow(),
            ]),

            const SizedBox(height: 16),

            _buildShimmerCard([
              Container(height: 24, width: 160, color: shimmerBase),
              const SizedBox(height: 16),

              _buildShimmerInfoRow(),
              const SizedBox(height: 12),

              _buildShimmerInfoRow(),
              const SizedBox(height: 12),

              _buildShimmerInfoRow(),
            ]),

            const SizedBox(height: 16),

            _buildShimmerCard([
              Container(height: 24, width: 140, color: shimmerBase),
              const SizedBox(height: 16),
              Container(height: 18, width: double.infinity, color: shimmerBase),
              const SizedBox(height: 8),
              Container(height: 18, width: 250, color: shimmerBase),
              const SizedBox(height: 12),
              _buildShimmerInfoRow(),
              const SizedBox(height: 12),
              _buildShimmerInfoRow(),
              const SizedBox(height: 12),
              _buildShimmerInfoRow(),
            ]),

            const SizedBox(height: 16),

            _buildShimmerCard([
              Container(height: 24, width: 120, color: shimmerBase),
              const SizedBox(height: 16),
              _buildShimmerInfoRow(),
              const SizedBox(height: 12),
              _buildShimmerInfoRow(),
              const SizedBox(height: 12),
              _buildShimmerInfoRow(),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerCard(List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _buildShimmerInfoRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shimmerBase = isDark ? Colors.grey[800]! : Colors.grey[300]!;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(height: 18, width: 100, color: shimmerBase),
        Container(height: 18, width: 120, color: shimmerBase),
      ],
    );
  }

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
    IconData? icon,
    Color? iconColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Color _getThemedIconColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? Colors.white70 : Theme.of(context).primaryColor;
  }

  String _displayValue(dynamic value, {String empty = 'N/A'}) {
    if (value == null) return empty;
    if (value is String) {
      final v = value.trim();
      if (v.isEmpty ||
          v.toLowerCase() == 'false' ||
          v.toLowerCase() == 'null') {
        return empty;
      }
      return v;
    }
    if (value is num) {
      return value.toString();
    }
    if (value is List) {
      return value.isEmpty ? empty : value.join(', ');
    }
    return value.toString();
  }

  Widget _buildInfoRow(
    String label,
    String? value, {
    bool highlight = false,
    Color? valueColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final display = _displayValue(value);
    if (display == 'N/A') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label:',
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              display,
              style: TextStyle(
                color: valueColor ?? (isDark ? Colors.white : Colors.black87),
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                fontSize: highlight ? 16 : 14,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, {Color? color, IconData? icon}) {
    return Chip(
      avatar: icon != null ? Icon(icon, size: 16, color: Colors.white) : null,
      label: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: color ?? Theme.of(context).primaryColor,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  List<Map<String, String>> _collectAttributesForDisplay(Product product) {
    final List<Map<String, String>> list = [];
    if (product.selectedVariants != null &&
        product.selectedVariants!.isNotEmpty) {
      product.selectedVariants!.forEach((k, v) {
        list.add({'name': k, 'value': v});
      });
    }
    if ((product.attributes?.isNotEmpty ?? false)) {
      for (final a in product.attributes!) {
        if (a.values.isEmpty) continue;
        list.add({'name': a.name, 'value': a.values.join(', ')});
      }
    } else {
      final resolved =
          (product.extraData?['resolvedAttributes'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      for (final m in resolved) {
        final name = m['name']?.toString() ?? 'Attribute';
        final values =
            (m['values'] as List?)?.map((e) => e.toString()).toList() ??
            const [];
        if (values.isEmpty) continue;
        list.add({'name': name, 'value': values.join(', ')});
      }

      if (resolved.isEmpty) {
        final passed =
            (product.extraData?['passedAttributes'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            const [];
        for (final m in passed) {
          final name = m['name']?.toString() ?? 'Attribute';
          final values =
              (m['values'] as List?)?.map((e) => e.toString()).toList() ??
              const [];
          if (values.isEmpty) continue;
          list.add({'name': name, 'value': values.join(', ')});
        }
      }
    }

    if (list.isEmpty) {
      final passedSel =
          (product.extraData?['passedSelectedVariants'] as Map?)
              ?.cast<String, String>() ??
          const {};
      passedSel.forEach((k, v) {
        if (k.trim().isEmpty || v.trim().isEmpty) {
          return;
        }
        list.add({'name': k, 'value': v});
      });
    }
    return list;
  }

  Widget _buildAttributeChip(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.purple.shade700 : Colors.purple;
    final display = value.length > 22 ? '${value.substring(0, 22)}…' : value;
    return Chip(
      label: Text(
        '$label: $display',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: bg,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    final product = _product;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtle = isDark ? Colors.white60 : Colors.black54;
    final dividerColor = isDark ? Colors.white12 : Colors.black12;

    Widget buildMetric(String label, String value, {Color? valueColor}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? (isDark ? Colors.white : Colors.black87),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
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
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InkWell(
                onTap: () {
                  if (_product.imageUrl != null &&
                      _product.imageUrl!.isNotEmpty) {
                    _fetchHighResImage(context);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black26
                            : Colors.black.withOpacity(0.05),
                        blurRadius: 16,
                        spreadRadius: 2,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      color: isDark ? Colors.white10 : Colors.grey[100],
                      child:
                          product.imageUrl != null &&
                              product.imageUrl!.isNotEmpty
                          ? Image.memory(
                              base64Decode(product.imageUrl!.split(',').last),
                              fit: BoxFit.cover,
                            )
                          : Center(
                              child: Text(
                                product.name.isNotEmpty
                                    ? product.name[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black45,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: TextStyle(
                        fontSize: product.name.length > 20
                            ? 20
                            : (product.name.length > 15 ? 22 : 24),
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 0),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (product.category != null &&
                            product.category!.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                HugeIcons.strokeRoundedFilterMailCircle,
                                size: 14,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[700],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                product.category!,
                                style: TextStyle(color: subtle, fontSize: 12),
                              ),
                            ],
                          ),
                        if (product.defaultCode.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                HugeIcons.strokeRoundedQrCode,
                                size: 14,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[700],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                product.defaultCode,
                                style: TextStyle(color: subtle, fontSize: 12),
                              ),
                            ],
                          ),
                        if (product.barcode != null &&
                            product.barcode!.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                HugeIcons.strokeRoundedBarCode02,
                                size: 14,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[700],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                product.barcode!,
                                style: TextStyle(color: subtle, fontSize: 12),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: dividerColor, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: buildMetric(
                  'Sale Price',
                  product.listPrice.toStringAsFixed(2),
                  valueColor: isDark ? Colors.white : Colors.black,
                ),
              ),

              Expanded(
                child: buildMetric(
                  'Available',
                  product.qtyAvailable.toStringAsFixed(0),
                  valueColor: isDark ? Colors.white : Colors.black,
                ),
              ),

              Expanded(
                child: buildMetric(
                  'Status',
                  product.stockStatus,
                  valueColor: product.isInStock
                      ? (isDark ? Colors.green[300] : Colors.green[700])
                      : (isDark ? Colors.red[300] : Colors.red[700]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<bool?> _showArchiveConfirmationDialog(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: Text(
          'Archive Product',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Are you sure you want to archive this product? This will deactivate the product but preserve its data.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isDark
                ? Colors.grey[300]
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark
                        ? Colors.grey[400]
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    elevation: isDark ? 0 : 3,
                  ),
                  child: const Text(
                    'Archive',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showArchiveProductDialog(BuildContext context) async {
    final product = _product;
    final int productId = int.tryParse(product.id) ?? 0;

    final confirmed = await _showArchiveConfirmationDialog(context);
    if (confirmed == true && context.mounted) {
      final success = await _archiveProduct(context, productId);
      if (success && context.mounted) {
        Navigator.of(context).pop(true);
      }
    }
  }

  Future<bool> _archiveProduct(BuildContext context, int productId) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No active Odoo session. Please log in again.');
      }

      final result = await Future.any([
        _performArchiveOperation(client, productId),
        Future.delayed(
          const Duration(seconds: 30),
          () => throw Exception('Archive operation timed out after 30 seconds'),
        ),
      ]);

      return result;
    } catch (e) {
      String errorMessage = 'Failed to archive product: ${e.toString()}';
      if (context.mounted) {
        CustomSnackbar.showError(context, errorMessage);
      }
      return false;
    }
  }

  Future<bool> _performArchiveOperation(dynamic client, int productId) async {
    final productResult = await client
        .callKw({
          'model': 'product.product',
          'method': 'read',
          'args': [
            [productId],
            ['product_tmpl_id'],
          ],
          'kwargs': {},
        })
        .timeout(const Duration(seconds: 10));

    if (productResult.isEmpty) {
      throw Exception('Product not found');
    }
    final templateId = (productResult[0]['product_tmpl_id'] as List?)?.first;

    final result1 = await client
        .callKw({
          'model': 'product.product',
          'method': 'write',
          'args': [
            [productId],
            {'active': false},
          ],
          'kwargs': {},
        })
        .timeout(const Duration(seconds: 10));

    var result2 = true;
    if (templateId != null) {
      result2 = await client
          .callKw({
            'model': 'product.template',
            'method': 'write',
            'args': [
              [templateId],
              {'active': false},
            ],
            'kwargs': {},
          })
          .timeout(const Duration(seconds: 10));
    }
    if (result1 == true && result2 == true) {
      if (context.mounted) {
        CustomSnackbar.showSuccess(context, 'Product archived successfully');
      }
      return true;
    } else {
      throw Exception('Failed to archive product or template');
    }
  }

  Widget _buildQuickActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(
                vertical: 20.0,
                horizontal: 8,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black26
                        : Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    icon,
                    size: 24,
                    color: isDark
                        ? Colors.white
                        : Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final product = _product;
    final extra = product.extraData ?? {};

    try {
      final resolved = (extra['resolvedAttributes'] as List?)?.length ?? 0;
      final direct = product.attributes?.length ?? 0;
      final ptavCount = product.productTemplateAttributeValueIds.length;
    } catch (_) {}
    final List<String> taxNames = (extra['taxNames'] as List<String>? ?? []);
    final List<Map<String, dynamic>> suppliers =
        (extra['suppliers'] as List<Map<String, dynamic>>? ?? []);
    final Map<String, dynamic> salesAnalytics =
        (extra['salesAnalytics'] as Map<String, dynamic>? ?? {});

    final realVendors = suppliers.where((s) {
      final name = (s['name'] is List && s['name'].length > 1)
          ? s['name'][1]?.toString().trim()
          : s['name']?.toString().trim();
      final isRealName =
          name != null &&
          name.isNotEmpty &&
          name.toLowerCase() != 'false' &&
          name.toLowerCase() != 'null' &&
          name.toLowerCase() != 'unknown vendor';
      return isRealName;
    }).toList();

    final hasRealVendors = realVendors.isNotEmpty;
    final backgroundColor = isDark ? Colors.grey[900] : Colors.grey[50];

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          'Product Details',
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
        actions: [
          IconButton(
            onPressed: () async {
              final result = _isLoading
                  ? null
                  : await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => CreateProductScreen(
                          product:
                              _productCache[widget.product.id] ??
                              widget.product,
                        ),
                      ),
                    );
              if (result != null && result == true) {
                if (mounted) {
                  CustomSnackbar.showSuccess(
                    context,
                    'Product updated successfully',
                  );
                }

                _productCache.remove(widget.product.id);
                _totalSold = null;
                _averageOrderValue = null;
                _quotationLines = null;
                _salesOrderLines = null;

                if (mounted) {
                  setState(() => _isLoading = true);
                  await _loadProductDetails(forceRefresh: true);
                }
              }
            },
            icon: Icon(
              HugeIcons.strokeRoundedPencilEdit02,
              color: (Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[400]
                  : Colors.grey[600]),
            ),
            tooltip: 'Edit Product',
          ),
          PopupMenuButton<String>(
            enabled: !_isLoading,
            icon: Icon(
              Icons.more_vert,
              color:
                  (Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[400]
                          : Colors.grey[600])
                      ?.withOpacity(_isLoading ? 0.4 : 1.0),
              size: 20,
            ),
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[900]
                : Colors.white,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'share_product',
                child: Row(
                  children: [
                    Icon(
                      HugeIcons.strokeRoundedShare08,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[300]
                          : Colors.grey[800],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Share Product',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'add_to_quote',
                child: Row(
                  children: [
                    Icon(
                      HugeIcons.strokeRoundedShoppingCart01,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[300]
                          : Colors.grey[800],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Add to Quote/Sale',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'view_sales_history',
                child: Row(
                  children: [
                    Icon(
                      HugeIcons.strokeRoundedAnalytics02,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[300]
                          : Colors.grey[800],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'View Sales History',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'generate_barcode',
                child: Row(
                  children: [
                    Icon(
                      HugeIcons.strokeRoundedQrCode,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[300]
                          : Colors.grey[800],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Generate Barcode',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),

              PopupMenuItem<String>(
                value: 'archive_product',
                child: Row(
                  children: [
                    Icon(
                      HugeIcons.strokeRoundedArchive03,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[300]
                          : Colors.grey[800],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Archive Product',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            onSelected: (value) async {
              switch (value) {
                case 'share_product':
                  _showShareProductDialog(context);
                  break;
                case 'add_to_quote':
                  _showAddToQuoteDialog(context);
                  break;
                case 'view_sales_history':
                  _showSalesHistoryScreen(context);
                  break;
                case 'generate_barcode':
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _showBarcodeGeneratorDialog(context);
                  });
                  break;

                case 'archive_product':
                  _showArchiveProductDialog(context);
                  break;
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? _buildShimmer(context)
          : FadeTransition(
              opacity: _fadeAnimation,
              child: RefreshIndicator(
                color: isDark
                    ? Colors.blue[200]
                    : Theme.of(context).primaryColor,
                onRefresh: () async {
                  _productCache.remove(widget.product.id);
                  _totalSold = null;
                  _averageOrderValue = null;
                  _quotationLines = null;
                  _salesOrderLines = null;
                  setState(() => _isLoading = true);
                  await _loadProductDetails(forceRefresh: true);
                },
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeaderCard(context),

                      _buildSectionCard(
                        title: 'Pricing Information',
                        icon: HugeIcons.strokeRoundedMoneyBag02,
                        iconColor: isDark
                            ? Colors.white70
                            : AppTheme.primaryColor,
                        children: [
                          Consumer<CurrencyProvider>(
                            builder: (context, currencyProvider, child) {
                              return _buildInfoRow(
                                'Sale Price',
                                currencyProvider.formatAmount(
                                  product.listPrice,
                                ),
                                highlight: true,
                                valueColor: isDark
                                    ? Colors.white70
                                    : AppTheme.primaryColor,
                              );
                            },
                          ),
                          if (product.currencyId != null &&
                              product.currencyId!.length > 1)
                            _buildInfoRow(
                              'Currency',
                              product.currencyId![1].toString(),
                            ),
                          if (product.standardPrice != null)
                            Consumer<CurrencyProvider>(
                              builder: (context, currencyProvider, child) {
                                return _buildInfoRow(
                                  'Standard Price',
                                  currencyProvider.formatAmount(
                                    product.standardPrice!,
                                  ),
                                );
                              },
                            ),
                          if (product.cost != null)
                            Consumer<CurrencyProvider>(
                              builder: (context, currencyProvider, child) {
                                return _buildInfoRow(
                                  'Cost',
                                  currencyProvider.formatAmount(product.cost!),
                                );
                              },
                            ),
                          _buildInfoRow(
                            'Taxes',
                            taxNames.isNotEmpty ? taxNames.join(', ') : 'None',
                          ),
                        ],
                      ),

                      if (_totalSold != null || _quotationLines != null)
                        _buildSectionCard(
                          title: 'Sales Performance',
                          icon: HugeIcons.strokeRoundedLaptopPerformance,
                          iconColor: isDark ? Colors.white70 : Colors.blue,
                          children: [
                            if (_totalSold != null)
                              _buildInfoRow(
                                'Total Sold',
                                '${_totalSold!.toStringAsFixed(1)} units',
                                highlight: false,
                                valueColor: isDark
                                    ? Colors.white70
                                    : Colors.black,
                              ),
                            if (_averageOrderValue != null)
                              Consumer<CurrencyProvider>(
                                builder: (context, currencyProvider, child) {
                                  return _buildInfoRow(
                                    'Avg Order Value',
                                    currencyProvider.formatAmount(
                                      _averageOrderValue!,
                                    ),
                                    valueColor: isDark
                                        ? Colors.white70
                                        : Colors.black,
                                  );
                                },
                              ),
                            if (_quotationLines != null)
                              _buildInfoRow(
                                'In Quotations',
                                '${_quotationLines!['total_qty']?.toStringAsFixed(1)} units (${_quotationLines!['count']} quotes)',
                                valueColor: isDark
                                    ? Colors.white70
                                    : Colors.black,
                              ),
                          ],
                        ),

                      if (salesAnalytics.isNotEmpty)
                        _buildSectionCard(
                          title: 'Sales Analytics',
                          icon: HugeIcons.strokeRoundedAnalyticsUp,
                          iconColor: isDark
                              ? Colors.white70
                              : Colors.deepPurple,
                          children: [
                            _buildInfoRow(
                              'Total Sales',
                              salesAnalytics['totalSales']?.toString() ?? '0',
                            ),
                            _buildInfoRow(
                              'Last Sale Date',
                              salesAnalytics['lastSaleDate'] ?? 'N/A',
                            ),
                            _buildInfoRow(
                              'Top Customer',
                              salesAnalytics['topCustomer'] ?? 'N/A',
                            ),
                          ],
                        ),

                      _buildSectionCard(
                        title: 'Inventory Information',
                        icon: HugeIcons.strokeRoundedPackageDimensions02,
                        iconColor: isDark ? Colors.white70 : Colors.indigo,
                        children: [
                          _buildInfoRow(
                            'Available Quantity',
                            '${product.qtyAvailable}',
                            highlight: true,
                            valueColor: isDark
                                ? Colors.white70
                                : product.isInStock
                                ? Colors.green[700]
                                : Colors.red[700],
                          ),
                          _buildInfoRow('Stock Status', product.stockStatus),
                          if (product.propertyStockInventory != null)
                            _buildInfoRow(
                              'Inventory Location',
                              _extractLocationName(
                                product.propertyStockInventory,
                              ),
                            ),
                          if (product.propertyStockProduction != null)
                            _buildInfoRow(
                              'Production Location',
                              _extractLocationName(
                                product.propertyStockProduction,
                              ),
                            ),
                        ],
                      ),

                      () {
                        final resolved =
                            (extra['resolvedAttributes'] as List?)
                                ?.cast<Map<String, dynamic>>() ??
                            const [];
                        final title = product.variantCount > 1
                            ? 'Product Variants'
                            : 'Product Attributes';

                        final List<Widget> attributeRows = [];
                        if (product.attributes != null &&
                            product.attributes!.isNotEmpty) {
                          attributeRows.addAll(
                            product.attributes!.map(
                              (attr) => _buildInfoRow(
                                attr.name,
                                attr.values.join(', '),
                              ),
                            ),
                          );
                        } else if (resolved.isNotEmpty) {
                          attributeRows.addAll(
                            resolved.map(
                              (attr) => _buildInfoRow(
                                attr['name']?.toString() ?? 'Attribute',
                                (attr['values'] as List).join(', '),
                              ),
                            ),
                          );
                        }
                        if (product.selectedVariants != null &&
                            product.selectedVariants!.isNotEmpty) {
                          attributeRows.addAll(
                            product.selectedVariants!.entries.map(
                              (entry) => _buildInfoRow(entry.key, entry.value),
                            ),
                          );
                        }

                        if (attributeRows.isEmpty &&
                            product.variantCount <= 1) {
                          return const SizedBox.shrink();
                        }

                        final bool needsCollapse = attributeRows.length > 4;
                        final List<Widget> rowsToShow =
                            !_attributesExpanded && needsCollapse
                            ? attributeRows.take(4).toList()
                            : attributeRows;

                        return _buildSectionCard(
                          title: title,
                          icon: HugeIcons.strokeRoundedPackaging,
                          iconColor: isDark ? Colors.white70 : Colors.purple,
                          children: [
                            if (product.variantCount > 1)
                              _buildInfoRow(
                                'Variant Count',
                                '${product.variantCount}',
                                highlight: true,
                                valueColor: isDark
                                    ? Colors.white
                                    : Colors.purple[700],
                              ),
                            ...rowsToShow,
                            if (needsCollapse)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _attributesExpanded =
                                          !_attributesExpanded;
                                    });
                                  },
                                  icon: Icon(
                                    _attributesExpanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    color: isDark
                                        ? Colors.white
                                        : Theme.of(context).primaryColor,
                                  ),
                                  label: Text(
                                    _attributesExpanded
                                        ? 'Show less'
                                        : 'Show more',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : Theme.of(context).primaryColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      }(),

                      if (product.weight != null ||
                          product.volume != null ||
                          product.dimensions != null)
                        _buildSectionCard(
                          title: 'Shipping Information',
                          icon: HugeIcons.strokeRoundedShippingTruck02,
                          iconColor: isDark ? Colors.white70 : Colors.teal,
                          children: [
                            if (product.weight != null)
                              _buildInfoRow('Weight', '${product.weight} kg'),
                            if (product.volume != null)
                              _buildInfoRow('Volume', '${product.volume} m³'),
                            if (product.dimensions != null)
                              _buildInfoRow('Dimensions', product.dimensions!),
                          ],
                        ),

                      if (hasRealVendors)
                        _buildSectionCard(
                          title: 'Vendors',
                          icon: HugeIcons.strokeRoundedUserStory,
                          iconColor: isDark ? Colors.white70 : Colors.indigo,
                          children: realVendors.map((s) {
                            final name =
                                (s['name'] is List && s['name'].length > 1)
                                ? s['name'][1]?.toString().trim()
                                : s['name']?.toString().trim();
                            final price = s['price']?.toString();
                            String display = name ?? 'Unknown Vendor';
                            if (price != null &&
                                price != '0' &&
                                price != '0.0' &&
                                price != '') {
                              display += ' (Price: $price)';
                            }
                            return _buildInfoRow('Vendor', display);
                          }).toList(),
                        ),

                      if (product.leadTime != null ||
                          product.procurementRoute != null ||
                          product.costMethod != null)
                        _buildSectionCard(
                          title: 'Operations',
                          icon: HugeIcons.strokeRoundedSettings04,
                          iconColor: isDark ? Colors.white70 : Colors.orange,
                          children: [
                            if (product.leadTime != null)
                              _buildInfoRow(
                                'Lead Time',
                                '${product.leadTime} days',
                              ),
                            if (product.procurementRoute != null)
                              _buildInfoRow(
                                'Procurement Route',
                                product.procurementRoute!,
                              ),
                            if (product.costMethod != null)
                              _buildInfoRow('Cost Method', product.costMethod!),
                          ],
                        ),

                      if (product.propertyAccountIncome != null ||
                          product.propertyAccountExpense != null)
                        _buildSectionCard(
                          title: 'Accounting',
                          icon: HugeIcons.strokeRoundedListView,
                          iconColor: isDark ? Colors.white70 : Colors.brown,
                          children: [
                            if (product.propertyAccountIncome != null)
                              _buildInfoRow(
                                'Income Account',
                                product.propertyAccountIncome!,
                              ),
                            if (product.propertyAccountExpense != null)
                              _buildInfoRow(
                                'Expense Account',
                                product.propertyAccountExpense!,
                              ),
                          ],
                        ),

                      if (product.description != null &&
                          product.description!.isNotEmpty)
                        _buildSectionCard(
                          title: 'Product Description',
                          icon: HugeIcons.strokeRoundedNote,
                          iconColor: isDark ? Colors.white70 : Colors.brown,
                          children: [
                            Text(
                              product.description!,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),

                      _buildSectionCard(
                        title: 'System Information',
                        icon: HugeIcons.strokeRoundedInformationCircle,
                        iconColor: isDark ? Colors.white70 : Colors.grey,
                        children: [
                          if (product.creationDate != null)
                            _buildInfoRow(
                              'Created',
                              product.creationDate!.toString().split('.')[0],
                            ),
                          _buildInfoRow('Product ID', product.id),
                          if (product
                              .productTemplateAttributeValueIds
                              .isNotEmpty)
                            _buildInfoRow(
                              'Template Attribute IDs',
                              product.productTemplateAttributeValueIds
                                  .toString(),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _ensureAnalyticsLoaded() async {
    try {
      if (_totalSold != null || _quotationLines != null) return;
      final client = await OdooSessionManager.getClient();
      if (client == null) return;
      final pid = int.tryParse(widget.product.id);
      if (pid == null) return;
      await _loadSalesAnalytics(client, pid);
    } catch (_) {}
  }

  String _extractLocationName(dynamic location) {
    if (location == null) return 'N/A';
    if (location is List && location.length >= 2) {
      return location[1]?.toString() ?? 'N/A';
    }
    return location.toString();
  }

  void _showShareProductDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final product = _product;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        title: Text(
          'Share Product',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Choose how you want to share "${product.name}"',
              style: TextStyle(
                color: isDark ? Colors.grey[300] : Colors.grey[600],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildShareOption(
                  context,
                  icon: HugeIcons.strokeRoundedMail01,
                  label: 'Email',
                  color: Colors.blue,
                  onTap: () => _shareViaEmail(product),
                ),
                _buildShareOption(
                  context,
                  icon: HugeIcons.strokeRoundedWhatsapp,
                  label: 'WhatsApp',
                  color: Colors.green,
                  onTap: () => _shareViaWhatsApp(product),
                ),
                _buildShareOption(
                  context,
                  icon: HugeIcons.strokeRoundedShare08,
                  label: 'More',
                  color: Colors.orange,
                  onTap: () => _shareViaSystem(product),
                ),
              ],
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    elevation: isDark ? 0 : 3,
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShareOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _generateProductShareText(Product product) {
    final buffer = StringBuffer();
    buffer.writeln('🏷️ *${product.name}*');
    buffer.writeln();

    if (product.defaultCode.isNotEmpty) {
      buffer.writeln('📋 *Code:* ${product.defaultCode}');
    }

    if (product.listPrice > 0) {
      buffer.writeln('💰 *Price:* \$${product.listPrice.toStringAsFixed(2)}');
    }

    if (product.category != null && product.category!.isNotEmpty) {
      buffer.writeln('📂 *Category:* ${product.category}');
    }

    buffer.writeln('📦 *Stock:* ${product.qtyAvailable} units');

    if (product.barcode?.isNotEmpty == true) {
      buffer.writeln('🔢 *Barcode:* ${product.barcode}');
    }

    if (product.description?.isNotEmpty == true) {
      buffer.writeln();
      buffer.writeln('📝 *Description:*');
      buffer.writeln(product.description);
    }

    buffer.writeln();
    buffer.writeln('📱 Shared from Sales App');

    return buffer.toString();
  }

  Future<void> _shareViaEmail(Product product) async {
    try {
      final subject = Uri.encodeComponent(
        'Product Information: ${product.name}',
      );
      final body = Uri.encodeComponent(_generateProductShareText(product));
      final emailUrl = 'mailto:?subject=$subject&body=$body';

      if (await canLaunchUrl(Uri.parse(emailUrl))) {
        await launchUrl(Uri.parse(emailUrl));
      } else {
        await _shareViaSystem(product);
      }
    } catch (e) {
      CustomSnackbar.showError(context, 'Failed to open email app: $e');
    }
  }

  Future<void> _shareViaWhatsApp(Product product) async {
    try {
      final text = Uri.encodeComponent(_generateProductShareText(product));
      final whatsappUrl = 'whatsapp://send?text=$text';

      if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
        await launchUrl(Uri.parse(whatsappUrl));
      } else {
        await _shareViaSystem(product);
      }
    } catch (e) {
      CustomSnackbar.showError(context, 'Failed to open WhatsApp: $e');
    }
  }

  Future<void> _shareViaSystem(Product product) async {
    try {
      final text = _generateProductShareText(product);
      await Share.share(text, subject: 'Product Information: ${product.name}');
    } catch (e) {
      CustomSnackbar.showError(context, 'Failed to share product: $e');
    }
  }

  void _showAddToQuoteDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final product = _product;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        title: Text(
          'Add to Sales Order',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).primaryColor.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    HugeIcons.strokeRoundedPackage,
                    color: Theme.of(context).primaryColor,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (product.defaultCode.isNotEmpty == true)
                          Text(
                            'Code: ${product.defaultCode}',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        Text(
                          'Price: \$${product.listPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Choose an option:',
              style: TextStyle(
                color: isDark ? Colors.grey[300] : Colors.grey[700],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildQuoteOption(
                    context,
                    icon: HugeIcons.strokeRoundedFileAdd,
                    label: 'Create New\nQuotation',
                    color: Colors.blue,
                    onTap: () => _createNewQuote(product),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildQuoteOption(
                    context,
                    icon: HugeIcons.strokeRoundedShoppingCart01,
                    label: 'Add to Existing\nDraft Order',
                    color: Colors.green,
                    onTap: () => _addToExistingOrder(product),
                  ),
                ),
              ],
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Colors.grey[400] : Colors.grey[600],
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createNewQuote(Product product) async {
    try {
      if (mounted) {
        CustomSnackbar.show(
          context: context,
          title: 'Loading',
          message: 'Preparing quotation...',
          type: SnackbarType.info,
        );
      }

      final client = await OdooSessionManager.getClient();
      if (client == null) {
        if (mounted) {
          CustomSnackbar.show(
            context: context,
            title: 'Session Error',
            message: 'No active Odoo session. Please log in again.',
            type: SnackbarType.error,
          );
        }
        return;
      }

      if (product.listPrice <= 0) {
        if (mounted) {
          CustomSnackbar.show(
            context: context,
            title: 'Product Error',
            message:
                'Product price is not set. Please update the product first.',
            type: SnackbarType.warning,
          );
        }
        return;
      }

      final customers = await _fetchCustomers(client);
      if (customers.isEmpty) {
        if (mounted) {
          CustomSnackbar.show(
            context: context,
            title: 'No Customers',
            message: 'No customers found. Please add customers first.',
            type: SnackbarType.warning,
          );
        }
        return;
      }

      final selectedCustomer = await _showCustomerSelectionDialog(customers);
      if (selectedCustomer == null) return;

      final orderDetails = await _showEnhancedQuantityDialog(product);
      if (orderDetails == null) return;

      final confirmed = await _showOrderConfirmationDialog(
        product: product,
        customer: selectedCustomer,
        quantity: orderDetails['quantity'],
        unitPrice: orderDetails['unitPrice'],
        discount: orderDetails['discount'],
        isNewOrder: true,
      );
      if (!confirmed) return;

      final quoteData = {
        'partner_id': selectedCustomer['id'],
        'state': 'draft',
        'order_line': [
          [
            0,
            0,
            {
              'product_id': int.parse(product.id),
              'name': product.name,
              'product_uom_qty': orderDetails['quantity'],
              'price_unit': orderDetails['unitPrice'],
              'discount': orderDetails['discount'] ?? 0.0,
            },
          ],
        ],
      };

      final canCreateOrder = await PermissionService.instance.canCreate(
        'sale.order',
      );
      final canCreateLine = await PermissionService.instance.canCreate(
        'sale.order.line',
      );
      if (!canCreateOrder || !canCreateLine) {
        if (mounted) {
          CustomSnackbar.showError(
            context,
            'You do not have permission to create quotations or their lines.',
          );
        }
        return;
      }
      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'create',
        'args': [quoteData],
        'kwargs': {},
      });

      if (result != null && mounted) {
        final total =
            (orderDetails['quantity'] *
            orderDetails['unitPrice'] *
            (1 - (orderDetails['discount'] ?? 0) / 100));
        CustomSnackbar.show(
          context: context,
          title: 'Quotation Created Successfully',
          message:
              'Quote #$result created for ${selectedCustomer['name']} - Total: \$${total.toStringAsFixed(2)}',
          type: SnackbarType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.show(
          context: context,
          title: 'Creation Failed',
          message:
              'Failed to create quotation: ${e.toString().contains('Exception:') ? e.toString().split('Exception: ')[1] : e.toString()}',
          type: SnackbarType.error,
        );
      }
    }
  }

  Future<void> _addToExistingOrder(Product product) async {
    try {
      if (mounted) {
        CustomSnackbar.show(
          context: context,
          title: 'Loading',
          message: 'Fetching draft orders...',
          type: SnackbarType.info,
        );
      }

      final client = await OdooSessionManager.getClient();
      if (client == null) {
        if (mounted) {
          CustomSnackbar.show(
            context: context,
            title: 'Session Error',
            message: 'No active Odoo session. Please log in again.',
            type: SnackbarType.error,
          );
        }
        return;
      }

      if (product.listPrice <= 0) {
        if (mounted) {
          CustomSnackbar.show(
            context: context,
            title: 'Product Error',
            message:
                'Product price is not set. Please update the product first.',
            type: SnackbarType.warning,
          );
        }
        return;
      }

      final orders = await _fetchDraftOrders(client);
      if (orders.isEmpty) {
        if (mounted) {
          CustomSnackbar.show(
            context: context,
            title: 'No Draft Orders',
            message:
                'No draft orders found. Would you like to create a new quotation instead?',
            type: SnackbarType.warning,
          );
        }
        return;
      }

      final selectedOrder = await _showOrderSelectionDialog(orders);
      if (selectedOrder == null) return;

      final orderDetails = await _showEnhancedQuantityDialog(product);
      if (orderDetails == null) return;

      final customerName = selectedOrder['partner_id'] is List
          ? selectedOrder['partner_id'][1]
          : 'Unknown Customer';

      final customerInfo = {'name': customerName};

      final confirmed = await _showOrderConfirmationDialog(
        product: product,
        customer: customerInfo,
        quantity: orderDetails['quantity'],
        unitPrice: orderDetails['unitPrice'],
        discount: orderDetails['discount'],
        isNewOrder: false,
      );
      if (!confirmed) return;

      final lineData = {
        'order_id': selectedOrder['id'],
        'product_id': int.parse(product.id),
        'name': product.name,
        'product_uom_qty': orderDetails['quantity'],
        'price_unit': orderDetails['unitPrice'],
        'discount': orderDetails['discount'] ?? 0.0,
      };

      final canCreateLine = await PermissionService.instance.canCreate(
        'sale.order.line',
      );
      if (!canCreateLine) {
        if (mounted) {
          CustomSnackbar.showError(
            context,
            'You do not have permission to add products to orders.',
          );
        }
        return;
      }
      final result = await client.callKw({
        'model': 'sale.order.line',
        'method': 'create',
        'args': [lineData],
        'kwargs': {},
      });

      if (result != null && mounted) {
        final total =
            (orderDetails['quantity'] *
            orderDetails['unitPrice'] *
            (1 - (orderDetails['discount'] ?? 0) / 100));
        CustomSnackbar.show(
          context: context,
          title: 'Product Added Successfully',
          message:
              '${product.name} added to ${selectedOrder['name']} - Line Total: \$${total.toStringAsFixed(2)}',
          type: SnackbarType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.show(
          context: context,
          title: 'Addition Failed',
          message:
              'Failed to add product to order: ${e.toString().contains('Exception:') ? e.toString().split('Exception: ')[1] : e.toString()}',
          type: SnackbarType.error,
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCustomers(dynamic client) async {
    try {
      final result = await client.callKw({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [
          [
            '|',
            ['is_company', '=', true],
            ['is_company', '=', false],
            ['active', '=', true],
          ],
        ],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'email',
            'phone',
            'is_company',
            'customer_rank',
          ],
          'limit': 200,
          'order': 'name asc',
        },
      });

      final customers =
          (result as List?)?.where((partner) {
            final name = partner['name']?.toString() ?? '';

            return name.isNotEmpty &&
                !name.toLowerCase().contains('odoobot') &&
                !name.toLowerCase().contains('public user') &&
                !name.toLowerCase().contains('portal user');
          }).toList() ??
          [];

      return List<Map<String, dynamic>>.from(customers);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchDraftOrders(dynamic client) async {
    try {
      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [
          [
            ['state', '=', 'draft'],
          ],
        ],
        'kwargs': {
          'fields': ['id', 'name', 'partner_id', 'amount_total', 'create_date'],
          'limit': 50,
          'order': 'create_date desc',
        },
      });
      return List<Map<String, dynamic>>.from(result ?? []);
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> _showCustomerSelectionDialog(
    List<Map<String, dynamic>> customers,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customerSearchController = TextEditingController();
    Map<String, dynamic>? selectedCustomer;
    List<Map<String, dynamic>> filteredCustomers = List.from(customers);
    bool showDropdown = false;
    bool isSearching = false;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: isDark ? 0 : 8,
          title: Text(
            'Select Customer',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Search and select a customer for the quotation',
                  style: TextStyle(
                    color: isDark ? Colors.grey[300] : Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                Column(
                  children: [
                    TextFormField(
                      controller: customerSearchController,
                      style: TextStyle(
                        color: isDark
                            ? Colors.white70
                            : const Color(0xff000000),
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Type to search customers...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Theme.of(context).primaryColor,
                            width: 1,
                          ),
                        ),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF2A2A2A)
                            : const Color(0xffF8FAFB),
                        prefixIcon: Icon(
                          HugeIcons.strokeRoundedSearch01,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xff7F7F7F),
                        ),
                        suffixIcon: selectedCustomer != null
                            ? IconButton(
                                icon: Icon(
                                  HugeIcons.strokeRoundedCancel01,
                                  color: isDark
                                      ? Colors.white70
                                      : const Color(0xff7F7F7F),
                                ),
                                onPressed: () {
                                  setState(() {
                                    selectedCustomer = null;
                                    customerSearchController.clear();
                                    filteredCustomers = List.from(customers);
                                    showDropdown = false;
                                  });
                                },
                              )
                            : isSearching
                            ? Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Theme.of(context).primaryColor,
                                    ),
                                  ),
                                ),
                              )
                            : IconButton(
                                icon: Icon(
                                  showDropdown
                                      ? HugeIcons.strokeRoundedArrowUp01
                                      : HugeIcons.strokeRoundedArrowDown01,
                                  color: isDark
                                      ? Colors.white70
                                      : const Color(0xff7F7F7F),
                                ),
                                onPressed: () {
                                  setState(() {
                                    showDropdown = !showDropdown;
                                    if (showDropdown &&
                                        customerSearchController.text.isEmpty) {
                                      filteredCustomers = List.from(customers);
                                    }
                                  });
                                },
                              ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          isSearching = true;
                          showDropdown = true;
                        });

                        Future.delayed(const Duration(milliseconds: 300), () {
                          if (mounted) {
                            setState(() {
                              isSearching = false;
                              if (value.isEmpty) {
                                filteredCustomers = List.from(customers);
                              } else {
                                filteredCustomers = customers.where((customer) {
                                  final name =
                                      customer['name']
                                          ?.toString()
                                          .toLowerCase() ??
                                      '';
                                  final email =
                                      customer['email']
                                          ?.toString()
                                          .toLowerCase() ??
                                      '';
                                  final phone =
                                      customer['phone']
                                          ?.toString()
                                          .toLowerCase() ??
                                      '';
                                  final searchTerm = value.toLowerCase();

                                  return name.contains(searchTerm) ||
                                      email.contains(searchTerm) ||
                                      phone.contains(searchTerm);
                                }).toList();
                              }
                            });
                          }
                        });
                      },
                    ),
                    if (showDropdown && filteredCustomers.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.white,
                          border: Border.all(
                            color: isDark
                                ? Colors.grey[700]!
                                : Colors.grey[300]!,
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
                          itemCount: filteredCustomers.length,
                          itemBuilder: (context, index) {
                            final customer = filteredCustomers[index];
                            return ListTile(
                              dense: true,
                              title: Text(
                                customer['name'],
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle:
                                  (customer['email'] != null &&
                                      customer['email'] != false &&
                                      customer['email'].toString().isNotEmpty)
                                  ? Text(
                                      customer['email'].toString(),
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    )
                                  : (customer['phone'] != null &&
                                        customer['phone'] != false &&
                                        customer['phone'].toString().isNotEmpty)
                                  ? Text(
                                      customer['phone'].toString(),
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    )
                                  : null,
                              onTap: () {
                                setState(() {
                                  selectedCustomer = customer;
                                  customerSearchController.text =
                                      customer['name'];
                                  showDropdown = false;
                                });
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
                if (selectedCustomer != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).primaryColor.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          HugeIcons.strokeRoundedCheckmarkCircle02,
                          color: Colors.green,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Selected: ${selectedCustomer!['name']}',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark
                          ? Colors.grey[400]
                          : Colors.grey[600],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: selectedCustomer != null
                        ? () => Navigator.of(context).pop(selectedCustomer)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      elevation: isDark ? 0 : 3,
                    ),
                    child: const Text(
                      'Select',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _showOrderSelectionDialog(
    List<Map<String, dynamic>> orders,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        title: Text(
          'Select Draft Order',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final customerName = order['partner_id'] is List
                  ? order['partner_id'][1]
                  : 'Unknown Customer';

              return ListTile(
                title: Text(
                  order['name'],
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customerName,
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    Text(
                      'Total: ${(order['amount_total'] ?? 0.0).toStringAsFixed(2)}',
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                onTap: () => Navigator.of(context).pop(order),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<double?> _showQuantityDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: '1');

    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        title: Text(
          'Enter Quantity',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Quantity',
            labelStyle: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).primaryColor),
            ),
          ),
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark
                        ? Colors.grey[400]
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    final quantity = double.tryParse(controller.text);
                    Navigator.of(context).pop(quantity);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    elevation: isDark ? 0 : 3,
                  ),
                  child: const Text(
                    'Add',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _showEnhancedQuantityDialog(
    Product product,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final quantityController = TextEditingController(text: '1');
    final priceController = TextEditingController(
      text: product.listPrice.toStringAsFixed(2) ?? '0.00',
    );
    final discountController = TextEditingController(text: '0');

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        title: Text(
          'Order Details',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Configure the order details for ${product.name}',
                style: TextStyle(
                  color: isDark ? Colors.grey[300] : Colors.grey[600],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  prefixIcon: Icon(HugeIcons.strokeRoundedPackage, size: 20),
                  labelStyle: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Unit Price (\$)',
                  prefixIcon: Icon(HugeIcons.strokeRoundedDollar01, size: 20),
                  labelStyle: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: discountController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Discount (%)',
                  prefixIcon: Icon(HugeIcons.strokeRoundedDiscount, size: 20),
                  labelStyle: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark
                        ? Colors.grey[400]
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    final quantity =
                        double.tryParse(quantityController.text) ?? 1.0;
                    final unitPrice =
                        double.tryParse(priceController.text) ?? 0.0;
                    final discount =
                        double.tryParse(discountController.text) ?? 0.0;

                    if (quantity <= 0) {
                      CustomSnackbar.show(
                        context: context,
                        title: 'Invalid Quantity',
                        message: 'Quantity must be greater than 0',
                        type: SnackbarType.warning,
                      );
                      return;
                    }

                    if (unitPrice <= 0) {
                      CustomSnackbar.show(
                        context: context,
                        title: 'Invalid Price',
                        message: 'Unit price must be greater than 0',
                        type: SnackbarType.warning,
                      );
                      return;
                    }

                    Navigator.of(context).pop({
                      'quantity': quantity,
                      'unitPrice': unitPrice,
                      'discount': discount,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    elevation: isDark ? 0 : 3,
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<bool> _showOrderConfirmationDialog({
    required Product product,
    required Map<String, dynamic> customer,
    required double quantity,
    required double unitPrice,
    double? discount,
    required bool isNewOrder,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtotal = quantity * unitPrice;
    final discountAmount = subtotal * ((discount ?? 0) / 100);
    final total = subtotal - discountAmount;

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: isDark ? Colors.grey[900] : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: isDark ? 0 : 8,
            title: Text(
              'Confirm Order',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isNewOrder
                      ? 'Create new quotation with the following details:'
                      : 'Add to existing order with the following details:',
                  style: TextStyle(
                    color: isDark ? Colors.grey[300] : Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).primaryColor.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildConfirmationRow(
                        'Customer:',
                        customer['name'],
                        isDark,
                      ),
                      _buildConfirmationRow('Product:', product.name, isDark),
                      _buildConfirmationRow(
                        'Quantity:',
                        quantity.toString(),
                        isDark,
                      ),
                      _buildConfirmationRow(
                        'Unit Price:',
                        '\$${unitPrice.toStringAsFixed(2)}',
                        isDark,
                      ),
                      if (discount != null && discount > 0)
                        _buildConfirmationRow(
                          'Discount:',
                          '${discount.toStringAsFixed(1)}%',
                          isDark,
                        ),
                      const Divider(),
                      _buildConfirmationRow(
                        'Total:',
                        '\$${total.toStringAsFixed(2)}',
                        isDark,
                        highlight: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actionsPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: isDark
                            ? Colors.grey[400]
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        elevation: isDark ? 0 : 3,
                      ),
                      child: const Text(
                        'Confirm',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildConfirmationRow(
    String label,
    String value,
    bool isDark, {
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: highlight
                  ? (isDark ? Colors.white : Colors.black87)
                  : (isDark ? Colors.white70 : Colors.black87),
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              fontSize: highlight ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  void _showSalesHistoryScreen(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ProductSalesHistoryScreen(product: _product),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeInOut)),
            ),
            child: child,
          );
        },
      ),
    );
  }

  void _showBarcodeGeneratorDialog(BuildContext context) {
    final product = _product;

    _generateBarcode(product);
  }

  Widget _buildBarcodeOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateBarcode(Product product) async {
    final barcodeData = _getOdooBarcodeData(product);
    if (barcodeData.isEmpty) {
      if (mounted) {
        final rootCtx = Navigator.of(context, rootNavigator: true).context;
        CustomSnackbar.showError(
          rootCtx,
          'No barcode available for this product',
        );
      }
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        contentPadding: const EdgeInsets.all(20),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Product Barcode',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(HugeIcons.strokeRoundedCancel01),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                product.name,
                style: TextStyle(
                  color: isDark ? Colors.grey[300] : Colors.grey[600],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[850] : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _buildOdooBarcodeWidget(product),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _shareBarcodeImage(product);
                      },
                      icon: const Icon(Icons.image, size: 18),
                      label: const Text(
                        'Share Image',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: isDark
                            ? Colors.grey[400]
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _shareBarcodePDF(product);
                      },
                      icon: const Icon(Icons.picture_as_pdf, size: 18),
                      label: const Text(
                        'Share PDF',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        elevation: isDark ? 0 : 3,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOdooBarcodeWidget(Product product) {
    final barcodeData = _getOdooBarcodeData(product);

    if (barcodeData.isEmpty) {
      return Column(
        children: [
          Icon(
            HugeIcons.strokeRoundedBarCode02,
            size: 48,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 8),
          Text(
            'No barcode available for this product',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return BarcodeWidget(
      barcode: Barcode.code128(),

      data: barcodeData,
      width: 250,
      height: 100,
      drawText: true,
    );
  }

  String _getOdooBarcodeData(Product product) {
    if (product.barcode?.isNotEmpty == true) {
      return product.barcode!;
    }
    return '';
  }

  Future<void> _shareBarcodeImage(Product product) async {
    try {
      final barcodeData = _getOdooBarcodeData(product);

      if (barcodeData.isEmpty) {
        if (mounted) {
          final rootCtx = Navigator.of(context, rootNavigator: true).context;
          CustomSnackbar.showError(
            rootCtx,
            'No barcode data available to share',
          );
        }
        return;
      }

      final GlobalKey repaintBoundaryKey = GlobalKey();

      final Widget barcodeImageWidget = RepaintBoundary(
        key: repaintBoundaryKey,
        child: Container(
          width: 600,
          height: 400,
          color: Colors.white,
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                product.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              BarcodeWidget(
                barcode: Barcode.code128(),
                data: barcodeData,
                width: 400,
                height: 120,
                drawText: true,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Product Code: $barcodeData',
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
              if (product.listPrice > 0)
                Text(
                  'Price: \$${product.listPrice.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
            ],
          ),
        ),
      );

      late OverlayEntry overlayEntry;
      overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          left: -1000,
          top: -1000,
          child: Material(color: Colors.transparent, child: barcodeImageWidget),
        ),
      );

      Overlay.of(context).insert(overlayEntry);

      await Future.delayed(const Duration(milliseconds: 100));

      try {
        final RenderRepaintBoundary boundary =
            repaintBoundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;

        final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
        final ByteData? byteData = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );

        if (byteData == null) {
          throw Exception('Failed to convert barcode to image');
        }

        final Uint8List pngBytes = byteData.buffer.asUint8List();

        final output = await getTemporaryDirectory();
        final file = File('${output.path}/barcode_${product.id}.png');
        await file.writeAsBytes(pngBytes);

        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Product Barcode: ${product.name}',
          text: 'Barcode for ${product.name}',
        );

        if (mounted) {
          CustomSnackbar.show(
            context: context,
            title: 'Image Shared',
            message: 'Barcode image has been shared successfully',
            type: SnackbarType.success,
          );
        }
      } finally {
        overlayEntry.remove();
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Failed to generate barcode image: $e',
        );
      }
    }
  }

  Future<void> _shareBarcodePDF(Product product) async {
    try {
      final barcodeData = _getOdooBarcodeData(product);

      if (barcodeData.isEmpty) {
        if (mounted) {
          final rootCtx = Navigator.of(context, rootNavigator: true).context;
          CustomSnackbar.showError(
            rootCtx,
            'No barcode data available to share',
          );
        }
        return;
      }

      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    product.name,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 30),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: barcodeData,
                    width: 300,
                    height: 100,
                    drawText: true,
                    textStyle: const pw.TextStyle(fontSize: 14),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text(
                    'Product Code: $barcodeData',
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                  if (product.listPrice > 0)
                    pw.Text(
                      'Price: \$${product.listPrice.toStringAsFixed(2)}',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                ],
              ),
            );
          },
        ),
      );

      final output = await getTemporaryDirectory();
      final file = File('${output.path}/barcode_${product.id}.pdf');
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Product Barcode: ${product.name}',
        text: 'Barcode for ${product.name}',
      );

      if (mounted) {
        CustomSnackbar.show(
          context: context,
          title: 'PDF Shared',
          message: 'Barcode PDF has been shared successfully',
          type: SnackbarType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(context, 'Failed to generate barcode PDF: $e');
      }
    }
  }

  Future<void> _generateQRCode(Product product) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final qrData = _generateQRCodeData(product);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        contentPadding: const EdgeInsets.all(20),
        title: Text(
          'Product QR Code',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                product.name,
                style: TextStyle(
                  color: isDark ? Colors.grey[300] : Colors.grey[600],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Scan to view product details',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: () => _shareQRCode(product, qrData),
                    icon: Icon(
                      HugeIcons.strokeRoundedShare08,
                      size: 18,
                      color: Theme.of(context).primaryColor,
                    ),
                    label: Text(
                      'Share',
                      style: TextStyle(color: Theme.of(context).primaryColor),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _saveQRCode(product, qrData),
                    icon: Icon(
                      HugeIcons.strokeRoundedDownload01,
                      size: 18,
                      color: Theme.of(context).primaryColor,
                    ),
                    label: Text(
                      'Save',
                      style: TextStyle(color: Theme.of(context).primaryColor),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark
                        ? Colors.grey[400]
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    elevation: isDark ? 0 : 3,
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _generateQRCodeData(Product product) {
    final Map<String, dynamic> productData = {
      'id': product.id,
      'name': product.name,
      'code': product.defaultCode,
      'price': product.listPrice,
      'barcode': product.barcode,
      'category': product.category,
      'description': product.description,
    };

    productData.removeWhere((key, value) => value == null || value == '');

    final buffer = StringBuffer();
    buffer.writeln('PRODUCT INFO');
    buffer.writeln('Name: ${product.name}');
    if (product.defaultCode.isNotEmpty == true) {
      buffer.writeln('Code: ${product.defaultCode}');
    }
    if (product.listPrice > 0) {
      buffer.writeln('Price: \$${product.listPrice.toStringAsFixed(2)}');
    }
    if (product.barcode?.isNotEmpty == true) {
      buffer.writeln('Barcode: ${product.barcode}');
    }
    if (product.category != null && product.category!.isNotEmpty) {
      buffer.writeln('Category: ${product.category}');
    }

    return buffer.toString();
  }

  Future<void> _shareQRCode(Product product, String qrData) async {
    try {
      await Share.share(qrData, subject: 'Product QR Code: ${product.name}');
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(context, 'Failed to share QR code: $e');
      }
    }
  }

  Future<void> _saveQRCode(Product product, String qrData) async {
    try {
      await Clipboard.setData(ClipboardData(text: qrData));
      if (mounted) {
        CustomSnackbar.show(
          context: context,
          title: 'QR Code Data Saved',
          message: 'QR code data copied to clipboard',
          type: SnackbarType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(context, 'Failed to save QR code: $e');
      }
    }
  }

  Future<void> _fetchHighResImage(BuildContext context) async {
    if (_isFetchingImage) return;

    final imageBase64 = _product.imageUrl;

    if (imageBase64 == null || imageBase64.isEmpty) return;

    setState(() => _isFetchingImage = true);

    try {
      String? highResBase64;
      final client = await OdooSessionManager.getClient();
      if (client != null) {
        final result = await client.callKw({
          'model': 'product.product',
          'method': 'read',
          'args': [
            [int.parse(_product.id)],
            ['image_1920'],
          ],
          'kwargs': {},
        });

        if (result is List && result.isNotEmpty) {
          final val = result[0]['image_1920'];
          if (val is String && val.isNotEmpty && val != 'false') {
            highResBase64 = val;
          }
        }
      }

      highResBase64 ??= imageBase64.split(',').last;

      if (!mounted) return;

      final bytes = base64Decode(highResBase64);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              FullImageScreen(imageBytes: bytes, title: _product.name),
        ),
      );
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(context, 'Could not load full image');
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingImage = false);
      }
    }
  }
}
