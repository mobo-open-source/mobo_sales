import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../utils/tap_prevention.dart';

class RevenueLineChart extends StatefulWidget {
  final List<Map<String, dynamic>> revenueData;
  final bool isDark;
  final Color primaryColor;

  const RevenueLineChart({
    super.key,
    required this.revenueData,
    required this.isDark,
    required this.primaryColor,
  });

  @override
  State<RevenueLineChart> createState() => _RevenueLineChartState();
}

class _RevenueLineChartState extends State<RevenueLineChart> {
  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  void setState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      super.setState(fn);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDisposed) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: widget.isDark
                ? Colors.black26
                : Colors.black.withOpacity(0.05),
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
            children: [
              Text(
                'Revenue Trend',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child:
                (widget.revenueData.isEmpty ||
                    widget.revenueData.every((e) => (e['value'] as num) == 0))
                ? _buildEmptyState()
                : Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: LineChart(_mainData()),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            HugeIcons.strokeRoundedAnalytics01,
            size: 32,
            color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 8),
          Text(
            'No revenue data available',
            style: TextStyle(
              color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  LineChartData _mainData() {
    final spots = _getSpots();
    final maxY = _getMaxValue();

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxY > 0 ? maxY / 4 : 1,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: widget.isDark ? Colors.grey[800] : Colors.grey[200],
            strokeWidth: 1,
            dashArray: [5, 5],
          );
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 1,
            getTitlesWidget: _bottomTitleWidgets,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: maxY > 0 ? maxY / 4 : 1,
            getTitlesWidget: _leftTitleWidgets,
            reservedSize: 42,
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: (widget.revenueData.length - 1).toDouble(),
      minY: 0,
      maxY: maxY,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          preventCurveOverShooting: true,
          color: widget.primaryColor,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: widget.primaryColor.withOpacity(0.1),
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (touchedSpot) =>
              widget.isDark ? Colors.grey[800]! : Colors.white,
          getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
            return touchedBarSpots.map((barSpot) {
              final flSpot = barSpot;
              if (flSpot.x < 0 || flSpot.x >= widget.revenueData.length) {
                return null;
              }
              final data = widget.revenueData[flSpot.x.toInt()];
              return LineTooltipItem(
                '${data['label']}\n',
                TextStyle(
                  color: widget.isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
                children: [
                  TextSpan(
                    text: flSpot.y.toStringAsFixed(2),
                    style: TextStyle(
                      color: widget.primaryColor,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              );
            }).toList();
          },
        ),
      ),
    );
  }

  Widget _bottomTitleWidgets(double value, TitleMeta meta) {
    if (value < 0 || value >= widget.revenueData.length) {
      return const SizedBox.shrink();
    }

    final style = TextStyle(
      color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
      fontWeight: FontWeight.bold,
      fontSize: 10,
    );

    if (widget.revenueData.length > 7 && value.toInt() % 2 != 0) {
      return const SizedBox.shrink();
    }

    final label = widget.revenueData[value.toInt()]['label'] ?? '';

    return SideTitleWidget(
      meta: meta,
      child: Text(label, style: style),
    );
  }

  Widget _leftTitleWidgets(double value, TitleMeta meta) {
    final style = TextStyle(
      color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
      fontWeight: FontWeight.bold,
      fontSize: 10,
    );
    String text;
    if (value >= 1000000000) {
      text = '${(value / 1000000000).toStringAsFixed(1)}B';
    } else if (value >= 1000000) {
      text = '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      text = '${(value / 1000).toStringAsFixed(1)}K';
    } else {
      text = value.toStringAsFixed(0);
    }

    return Text(text, style: style, textAlign: TextAlign.left);
  }

  List<FlSpot> _getSpots() {
    List<FlSpot> spots = [];
    for (int i = 0; i < widget.revenueData.length; i++) {
      final value = (widget.revenueData[i]['value'] as num).toDouble();
      spots.add(FlSpot(i.toDouble(), value));
    }
    return spots;
  }

  double _getMaxValue() {
    if (widget.revenueData.isEmpty) return 100;
    final maxValue = widget.revenueData
        .map((data) => (data['value'] as num).toDouble())
        .reduce((a, b) => a > b ? a : b);
    return maxValue * 1.2;
  }
}

class RevenueChartSample {
  final String label;
  final double value;

  RevenueChartSample({required this.label, required this.value});
}

class ProductPerformanceBarChart extends StatefulWidget {
  final List<Map<String, dynamic>> productData;
  final bool isDark;
  final Color primaryColor;
  final void Function(int index)? onBarTap;

  const ProductPerformanceBarChart({
    super.key,
    required this.productData,
    required this.isDark,
    required this.primaryColor,
    this.onBarTap,
  });

  @override
  State<ProductPerformanceBarChart> createState() =>
      _ProductPerformanceBarChartState();
}

class _ProductPerformanceBarChartState
    extends State<ProductPerformanceBarChart> {
  int touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: widget.isDark
                ? Colors.black26
                : Colors.black.withOpacity(0.05),
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
            children: [
              Text(
                'Top Products',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              const Spacer(),
              Text(
                'Tap bars for details',
                style: TextStyle(
                  fontSize: 11,
                  color: widget.isDark ? Colors.grey[500] : Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child:
                (widget.productData.isEmpty ||
                    widget.productData.every((e) => (e['value'] as num) == 0))
                ? _buildEmptyState()
                : BarChart(_mainBarData()),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            HugeIcons.strokeRoundedBarChart,
            size: 32,
            color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 8),
          Text(
            'No product data available',
            style: TextStyle(
              color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  BarChartData _mainBarData() {
    final maxY = _getMaxValue();

    return BarChartData(
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (group) =>
              widget.isDark ? Colors.grey[800]! : Colors.white,
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final product = widget.productData[group.x.toInt()];
            return BarTooltipItem(
              '${product['name']}\n',
              TextStyle(
                color: widget.isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
              ),
              children: <TextSpan>[
                TextSpan(
                  text: rod.toY.toStringAsFixed(2),
                  style: TextStyle(
                    color: widget.primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(
                  text: '\nQty: ${product['qty']}',
                  style: TextStyle(
                    color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            );
          },
        ),
        touchCallback: (FlTouchEvent event, barTouchResponse) {
          setState(() {
            if (!event.isInterestedForInteractions ||
                barTouchResponse == null ||
                barTouchResponse.spot == null) {
              touchedIndex = -1;
              return;
            }
            touchedIndex = barTouchResponse.spot!.touchedBarGroupIndex;
          });

          if (event is FlTapUpEvent &&
              barTouchResponse != null &&
              barTouchResponse.spot != null) {
            if (widget.onBarTap != null) {
              final idx = barTouchResponse.spot!.touchedBarGroupIndex;
              final tapKey = 'product_details_navigate_$idx';
              TapPrevention.executeNavigation(tapKey, () {
                widget.onBarTap!(idx);
              });
            }
          }
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: _getBottomTitles,
            reservedSize: 38,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: maxY > 0 ? maxY / 4 : 1,
            getTitlesWidget: _leftTitles,
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      barGroups: _getBarGroups(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxY > 0 ? maxY / 4 : 1,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: widget.isDark ? Colors.grey[800] : Colors.grey[200],
            strokeWidth: 1,
            dashArray: [5, 5],
          );
        },
      ),
      maxY: maxY,
    );
  }

  Widget _getBottomTitles(double value, TitleMeta meta) {
    final style = TextStyle(
      color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
      fontWeight: FontWeight.bold,
      fontSize: 10,
    );

    if (value.toInt() >= widget.productData.length) {
      return const SizedBox.shrink();
    }

    String text = widget.productData[value.toInt()]['name'] ?? '';
    if (text.length > 8) {
      text = '${text.substring(0, 6)}..';
    }

    return SideTitleWidget(
      meta: meta,
      space: 4,
      child: Text(text, style: style),
    );
  }

  Widget _leftTitles(double value, TitleMeta meta) {
    final style = TextStyle(
      color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
      fontWeight: FontWeight.bold,
      fontSize: 10,
    );
    String text;
    if (value >= 1000000000) {
      text = '${(value / 1000000000).toStringAsFixed(1)}B';
    } else if (value >= 1000000) {
      text = '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      text = '${(value / 1000).toStringAsFixed(1)}K';
    } else {
      text = value.toStringAsFixed(0);
    }
    return SideTitleWidget(
      meta: meta,
      space: 0,
      child: Text(text, style: style),
    );
  }

  List<BarChartGroupData> _getBarGroups() {
    List<BarChartGroupData> groups = [];
    for (int i = 0; i < widget.productData.length; i++) {
      final value = (widget.productData[i]['value'] as num).toDouble();
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: value,
              color: touchedIndex == i
                  ? widget.primaryColor.withOpacity(0.8)
                  : widget.primaryColor,
              width: 16,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
          ],
        ),
      );
    }
    return groups;
  }

  double _getMaxValue() {
    if (widget.productData.isEmpty) return 100;
    final maxValue = widget.productData
        .map((data) => (data['value'] as num).toDouble())
        .reduce((a, b) => a > b ? a : b);
    return maxValue * 1.2;
  }
}
