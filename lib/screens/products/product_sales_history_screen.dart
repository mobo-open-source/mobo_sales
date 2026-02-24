import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../models/product.dart';
import '../../providers/currency_provider.dart';
import '../../services/odoo_session_manager.dart';
import '../../widgets/custom_snackbar.dart';

class ProductSalesHistoryScreen extends StatefulWidget {
  final Product product;

  const ProductSalesHistoryScreen({super.key, required this.product});

  @override
  State<ProductSalesHistoryScreen> createState() =>
      _ProductSalesHistoryScreenState();
}

class _ProductSalesHistoryScreenState extends State<ProductSalesHistoryScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _salesHistory = [];
  List<Map<String, dynamic>> _quotationHistory = [];
  Map<String, dynamic> _analytics = {};
  List<SalesData> _chartData = [];
  String _selectedPeriod = '6M';

  final Map<int, String> _orderPartnerNames = {};

  @override
  void initState() {
    super.initState();
    _loadSalesHistory();
  }

  Future<void> _loadSalesHistory() async {
    try {
      setState(() => _isLoading = true);

      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No Odoo client available');
      }

      final productId = int.parse(widget.product.id);

      final salesResult = await client.callKw({
        'model': 'sale.order.line',
        'method': 'search_read',
        'args': [
          [
            ['product_id', '=', productId],
          ],
        ],
        'kwargs': {
          'fields': [
            'order_id',
            'product_uom_qty',
            'price_unit',
            'price_subtotal',
            'create_date',
            'state',
          ],
          'limit': 200,
          'order': 'create_date desc',
        },
      });

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
          'fields': [
            'order_id',
            'product_uom_qty',
            'price_unit',
            'price_subtotal',
            'create_date',
          ],
          'limit': 100,
          'order': 'create_date desc',
        },
      });

      try {
        final Set<int> orderIds = {};
        for (final m in (salesResult ?? [])) {
          final oid = (m['order_id'] is List && m['order_id'].isNotEmpty)
              ? (m['order_id'][0] as int)
              : (m['order_id'] is int ? m['order_id'] as int : null);
          if (oid != null) orderIds.add(oid);
        }
        for (final m in (quotationResult ?? [])) {
          final oid = (m['order_id'] is List && m['order_id'].isNotEmpty)
              ? (m['order_id'][0] as int)
              : (m['order_id'] is int ? m['order_id'] as int : null);
          if (oid != null) orderIds.add(oid);
        }
        if (orderIds.isNotEmpty) {
          final orderInfo = await client.callKw({
            'model': 'sale.order',
            'method': 'read',
            'args': [orderIds.toList()],
            'kwargs': {
              'fields': ['id', 'name', 'partner_id'],
            },
          });
          if (orderInfo is List) {
            _orderPartnerNames.clear();
            for (final o in orderInfo) {
              final int? id = o['id'] as int?;
              String? partnerName;
              final p = o['partner_id'];
              if (p is List && p.length > 1) {
                partnerName = p[1]?.toString();
              }
              if (id != null && partnerName != null) {
                _orderPartnerNames[id] = partnerName;
              }
            }
          }
        }
      } catch (e) {}

      if (mounted) {
        setState(() {
          _salesHistory = List<Map<String, dynamic>>.from(salesResult ?? []);
          _quotationHistory = List<Map<String, dynamic>>.from(
            quotationResult ?? [],
          );
          _analytics = _calculateAnalytics();
          _chartData = _generateChartData();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        CustomSnackbar.showError(context, 'Failed to load sales history: $e');
      }
    }
  }

  Map<String, dynamic> _calculateAnalytics() {
    double totalRevenue = 0;
    double totalQuantity = 0;
    int totalOrders = _salesHistory.length;
    Set<String> uniqueCustomers = {};

    DateTime? firstSale;
    DateTime? lastSale;

    for (final sale in _salesHistory) {
      totalRevenue += (sale['price_subtotal'] ?? 0.0);
      totalQuantity += (sale['product_uom_qty'] ?? 0.0);

      final oid = (sale['order_id'] is List && sale['order_id'].isNotEmpty)
          ? (sale['order_id'][0] as int)
          : (sale['order_id'] is int ? sale['order_id'] as int : null);
      if (oid != null) {
        final name = _orderPartnerNames[oid];
        if (name != null && name.isNotEmpty) {
          uniqueCustomers.add(name);
        }
      }

      if (sale['create_date'] != null) {
        final date = DateTime.parse(sale['create_date']);
        if (firstSale == null || date.isBefore(firstSale)) {
          firstSale = date;
        }
        if (lastSale == null || date.isAfter(lastSale)) {
          lastSale = date;
        }
      }
    }

    double averageOrderValue = totalOrders > 0 ? totalRevenue / totalOrders : 0;
    double averageQuantityPerOrder = totalOrders > 0
        ? totalQuantity / totalOrders
        : 0;

    return {
      'totalRevenue': totalRevenue,
      'totalQuantity': totalQuantity,
      'totalOrders': totalOrders,
      'uniqueCustomers': uniqueCustomers.length,
      'averageOrderValue': averageOrderValue,
      'averageQuantityPerOrder': averageQuantityPerOrder,
      'firstSale': firstSale,
      'lastSale': lastSale,
    };
  }

  List<SalesData> _generateChartData() {
    final Map<String, double> monthlyData = {};
    final now = DateTime.now();
    final months = _selectedPeriod == '6M' ? 6 : 12;

    for (int i = months - 1; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final key = DateFormat('MMM yyyy').format(month);
      monthlyData[key] = 0;
    }

    for (final sale in _salesHistory) {
      if (sale['create_date'] != null) {
        final date = DateTime.parse(sale['create_date']);
        final monthKey = DateFormat('MMM yyyy').format(date);
        if (monthlyData.containsKey(monthKey)) {
          monthlyData[monthKey] =
              (monthlyData[monthKey] ?? 0) + (sale['price_subtotal'] ?? 0.0);
        }
      }
    }

    return monthlyData.entries.map((e) => SalesData(e.key, e.value)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.grey[50],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sales History',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              widget.product.name,
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        backgroundColor: isDark ? Colors.grey[900]! : Colors.white,
      ),
      body: _isLoading
          ? _buildLoadingState()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAnalyticsCards(),
                  const SizedBox(height: 24),
                  _buildSalesChart(),
                  const SizedBox(height: 24),
                  _buildRecentSales(),
                  const SizedBox(height: 24),
                  _buildQuotations(),
                ],
              ),
            ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildAnalyticsCards() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Analytics Overview',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final double maxWidth = constraints.maxWidth;

            int crossAxisCount;
            if (maxWidth >= 1200) {
              crossAxisCount = 4;
            } else if (maxWidth >= 900) {
              crossAxisCount = 3;
            } else if (maxWidth >= 600) {
              crossAxisCount = 2;
            } else {
              crossAxisCount = 2;
            }

            const double spacing = 16.0;
            final double totalSpacing = spacing * (crossAxisCount - 1);
            final double itemWidth = (maxWidth - totalSpacing) / crossAxisCount;

            final double itemHeight = 120.0;
            final double childAspectRatio = itemWidth / itemHeight;

            final List<_AnalyticsItem> items = [
              _AnalyticsItem(
                label: 'Total Revenue',
                value: _analytics['totalRevenue']?.toStringAsFixed(2) ?? '0.00',
                color: Colors.green,
              ),
              _AnalyticsItem(
                label: 'Total Orders',
                value: (_analytics['totalOrders'] ?? 0).toString(),
                color: Colors.blue,
              ),
              _AnalyticsItem(
                label: 'Units Sold',
                value: _analytics['totalQuantity']?.toStringAsFixed(0) ?? '0',
                color: Colors.orange,
              ),
              _AnalyticsItem(
                label: 'Unique Customers',
                value: (_analytics['uniqueCustomers'] ?? 0).toString(),
                color: Colors.purple,
              ),
            ];

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: childAspectRatio,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final it = items[index];
                return _buildAnalyticsCard(
                  it.label,
                  it.value,
                  HugeIcons.strokeRoundedAddCircle,
                  it.color,
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildAnalyticsCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesChart() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sales Trend',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              DropdownButton<String>(
                value: _selectedPeriod,
                dropdownColor: isDark ? Colors.grey[800] : Colors.white,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                items: const [
                  DropdownMenuItem(value: '6M', child: Text('6 Months')),
                  DropdownMenuItem(value: '12M', child: Text('12 Months')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedPeriod = value;
                      _chartData = _generateChartData();
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: _chartData.isEmpty
                ? Center(
                    child: Text(
                      'No sales data',
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  )
                : BarChart(
                    BarChartData(
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (group) =>
                              isDark ? Colors.grey[800]! : Colors.white,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            if (group.x.toInt() >= _chartData.length) {
                              return null;
                            }
                            final data = _chartData[group.x.toInt()];
                            return BarTooltipItem(
                              '${data.month}\n',
                              TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                              children: [
                                TextSpan(
                                  text: data.sales.toStringAsFixed(2),
                                  style: TextStyle(
                                    color: Theme.of(context).primaryColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (value, meta) {
                              if (value.toInt() >= _chartData.length) {
                                return const SizedBox.shrink();
                              }
                              return SideTitleWidget(
                                meta: meta,
                                child: Text(
                                  _chartData[value.toInt()].month,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                    fontSize: 10,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                value.toStringAsFixed(0),
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                  fontSize: 10,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: isDark ? Colors.grey[800] : Colors.grey[200],
                            strokeWidth: 1,
                          );
                        },
                      ),
                      barGroups: List.generate(_chartData.length, (i) {
                        return BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: _chartData[i].sales,
                              color: Theme.of(context).primaryColor,
                              width: 14,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSales() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Sales',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          if (_salesHistory.isEmpty)
            Center(
              child: Text(
                'No sales history found',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _salesHistory.take(5).length,
              separatorBuilder: (context, index) =>
                  Divider(color: isDark ? Colors.grey[800] : Colors.grey[200]),
              itemBuilder: (context, index) {
                final sale = _salesHistory[index];
                final orderId =
                    (sale['order_id'] is List && sale['order_id'].isNotEmpty)
                    ? sale['order_id'][0] as int
                    : (sale['order_id'] is int ? sale['order_id'] as int : -1);
                final customerName =
                    _orderPartnerNames[orderId] ?? 'Unknown Customer';
                final orderName = sale['order_id'] is List
                    ? sale['order_id'][1]
                    : 'Unknown Order';
                final date = sale['create_date'] != null
                    ? DateFormat(
                        'MMM dd, yyyy',
                      ).format(DateTime.parse(sale['create_date']))
                    : 'Unknown Date';

                return ListTile(
                  contentPadding: EdgeInsets.zero,

                  title: Text(
                    orderName,
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
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        date,
                        style: TextStyle(
                          color: isDark ? Colors.grey[500] : Colors.grey[500],
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Consumer<CurrencyProvider>(
                        builder: (context, currencyProvider, child) {
                          return Text(
                            currencyProvider.formatAmount(
                              sale['price_subtotal'] ?? 0.0,
                            ),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
                      ),
                      Text(
                        '${(sale['product_uom_qty'] ?? 0.0).toStringAsFixed(0)} units',
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildQuotations() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pending Quotations',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          if (_quotationHistory.isEmpty)
            Center(
              child: Text(
                'No pending quotations',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _quotationHistory.take(3).length,
              separatorBuilder: (context, index) =>
                  Divider(color: isDark ? Colors.grey[800] : Colors.grey[200]),
              itemBuilder: (context, index) {
                final quote = _quotationHistory[index];
                final orderId =
                    (quote['order_id'] is List && quote['order_id'].isNotEmpty)
                    ? quote['order_id'][0] as int
                    : (quote['order_id'] is int
                          ? quote['order_id'] as int
                          : -1);
                final customerName =
                    _orderPartnerNames[orderId] ?? 'Unknown Customer';
                final orderName = quote['order_id'] is List
                    ? quote['order_id'][1]
                    : 'Unknown Quote';
                final date = quote['create_date'] != null
                    ? DateFormat(
                        'MMM dd, yyyy',
                      ).format(DateTime.parse(quote['create_date']))
                    : 'Unknown Date';

                return ListTile(
                  contentPadding: EdgeInsets.zero,

                  title: Text(
                    orderName,
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
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        date,
                        style: TextStyle(
                          color: isDark ? Colors.grey[500] : Colors.grey[500],
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Consumer<CurrencyProvider>(
                        builder: (context, currencyProvider, child) {
                          return Text(
                            currencyProvider.formatAmount(
                              quote['price_subtotal'] ?? 0.0,
                            ),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
                      ),
                      Text(
                        '${(quote['product_uom_qty'] ?? 0.0).toStringAsFixed(0)} units',
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class SalesData {
  final String month;
  final double sales;

  SalesData(this.month, this.sales);
}

class _AnalyticsItem {
  final String label;
  final String value;
  final Color color;

  _AnalyticsItem({
    required this.label,
    required this.value,
    required this.color,
  });
}
