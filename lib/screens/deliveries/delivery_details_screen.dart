import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../../services/odoo_session_manager.dart';

class DeliveryDetailsScreen extends StatefulWidget {
  final int deliveryId;

  const DeliveryDetailsScreen({super.key, required this.deliveryId});

  @override
  State<DeliveryDetailsScreen> createState() => _DeliveryDetailsScreenState();
}

class _DeliveryDetailsScreenState extends State<DeliveryDetailsScreen> {
  Map<String, dynamic>? _deliveryData;
  List<Map<String, dynamic>> _productMoves = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchDeliveryDetails();
  }

  Future<void> _fetchDeliveryDetails() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No active Odoo session');
      }

      List<String> fieldsToFetch = [
        'name',
        'state',
        'partner_id',
        'scheduled_date',
        'date_deadline',
        'date_done',
        'origin',
        'picking_type_code',
        'picking_type_id',
        'location_id',
        'location_dest_id',
        'move_ids_without_package',
        'note',
        'priority',
        'user_id',
        'company_id',
        'backorder_id',
      ];

      dynamic result;
      int retryCount = 0;
      const int maxRetries = 3;

      while (retryCount < maxRetries) {
        try {
          result = await client.callKw({
            'model': 'stock.picking',
            'method': 'read',
            'args': [
              [widget.deliveryId],
            ],
            'kwargs': {'fields': fieldsToFetch},
          });
          break;
        } catch (e) {
          if (e.toString().contains('Invalid field')) {
            final fieldMatch = RegExp(
              r"Invalid field '([^']+)' on",
            ).firstMatch(e.toString());
            final invalidField = fieldMatch?.group(1);
            if (invalidField != null && fieldsToFetch.contains(invalidField)) {
              fieldsToFetch.remove(invalidField);
              retryCount++;
              await Future.delayed(const Duration(milliseconds: 300));
              continue;
            }
          }

          rethrow;
        }
      }

      if (!mounted) return;

      if (result is List && result.isNotEmpty) {
        final deliveryData = result[0] as Map<String, dynamic>;

        List<Map<String, dynamic>> moves = [];

        List<dynamic>? moveIds;
        if (deliveryData['move_ids_without_package'] != null &&
            deliveryData['move_ids_without_package'] is List &&
            (deliveryData['move_ids_without_package'] as List).isNotEmpty) {
          moveIds = deliveryData['move_ids_without_package'];
        } else {
          try {
            final moveSearchResult = await client.callKw({
              'model': 'stock.move',
              'method': 'search',
              'args': [
                [
                  ['picking_id', '=', widget.deliveryId],
                ],
              ],
              'kwargs': {'limit': 50},
            });
            if (moveSearchResult is List && moveSearchResult.isNotEmpty) {
              moveIds = moveSearchResult;
            }
          } catch (e) {}
        }

        if (moveIds != null && moveIds.isNotEmpty) {
          try {
            final moveResult = await client.callKw({
              'model': 'stock.move',
              'method': 'read',
              'args': [moveIds],
              'kwargs': {
                'fields': [
                  'product_id',
                  'product_uom_qty',
                  'quantity',
                  'product_uom',
                  'state',
                  'description_picking',
                ],
              },
            });
            if (moveResult is List) {
              moves = moveResult.cast<Map<String, dynamic>>();
            }
          } catch (e) {}
        }

        if (!mounted) return;
        setState(() {
          _deliveryData = deliveryData;
          _productMoves = moves;
          _isLoading = false;
        });
      } else {
        throw Exception('Delivery not found');
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  String _safeString(dynamic value, [String defaultValue = 'N/A']) {
    if (value == null || value == false) return defaultValue;
    if (value is List && value.length > 1) return value[1].toString();
    if (value is String) return value;
    return value.toString();
  }

  Color _getStateColor(String state) {
    switch (state) {
      case 'done':
        return Colors.green;
      case 'assigned':
        return Colors.blue;
      case 'confirmed':
        return Colors.orange;
      case 'cancel':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStateLabel(String state) {
    switch (state) {
      case 'draft':
        return 'Draft';
      case 'waiting':
        return 'Waiting';
      case 'confirmed':
        return 'Confirmed';
      case 'assigned':
        return 'Ready';
      case 'done':
        return 'Done';
      case 'cancel':
        return 'Cancelled';
      default:
        return state;
    }
  }

  String _getPriorityLabel(String priority) {
    switch (priority) {
      case '0':
        return 'Normal';
      case '1':
        return 'Urgent';
      case '2':
        return 'Very Urgent';
      default:
        return 'Normal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          'Delivery Details',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        backgroundColor: backgroundColor,
        foregroundColor: isDark ? Colors.white : Theme.of(context).primaryColor,
        elevation: 0,
      ),
      body: _isLoading
          ? _buildShimmerLoading(isDark)
          : _errorMessage != null
          ? _buildErrorState(isDark)
          : _deliveryData != null
          ? _buildDeliveryDetails(isDark)
          : const SizedBox.shrink(),
    );
  }

  Widget _buildShimmerLoading(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Shimmer.fromColors(
            baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
            highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Shimmer.fromColors(
            baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
            highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
            child: Container(
              height: 300,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Shimmer.fromColors(
            baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
            highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
              const SizedBox(height: 16),
              Text(
                'Error Loading Delivery',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Unknown error',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchDeliveryDetails,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeliveryDetails(bool isDark) {
    final state = _safeString(_deliveryData!['state'], 'draft');
    final stateColor = _getStateColor(state);

    return RefreshIndicator(
      onRefresh: _fetchDeliveryDetails,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionCard(
              title: 'Delivery Information',
              icon: HugeIcons.strokeRoundedPackageDelivered,
              iconColor: isDark ? Colors.white70 : Colors.grey[800],
              isDark: isDark,
              headerAction: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: stateColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: stateColor.withOpacity(0.25),
                    width: 1,
                  ),
                ),
                child: Text(
                  _getStateLabel(state),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: stateColor,
                  ),
                ),
              ),
              children: [
                if (_deliveryData!['partner_id'] != null)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedUser,
                    'Customer',
                    _safeString(_deliveryData!['partner_id']),
                  ),
                if (_deliveryData!['picking_type_id'] != null)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedPackage,
                    'Operation Type',
                    _safeString(_deliveryData!['picking_type_id']),
                  ),
                if (_deliveryData!['origin'] != null)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedFileAttachment,
                    'Source Document',
                    _safeString(_deliveryData!['origin']),
                  ),
                if (_deliveryData!['backorder_id'] != null &&
                    _deliveryData!['backorder_id'] != false)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedPackageRemove,
                    'Backorder of',
                    _safeString(_deliveryData!['backorder_id']),
                  ),
                if (_deliveryData!['priority'] != null &&
                    _deliveryData!['priority'] != '0')
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedFlag02,
                    'Priority',
                    _getPriorityLabel(_deliveryData!['priority'].toString()),
                  ),
                if (_deliveryData!['scheduled_date'] != null)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedCalendar03,
                    'Scheduled Date',
                    DateFormat(
                      'MMM dd, yyyy HH:mm',
                    ).format(DateTime.parse(_deliveryData!['scheduled_date'])),
                  ),
                if (_deliveryData!['date_deadline'] != null)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedAlarmClock,
                    'Deadline',
                    DateFormat(
                      'MMM dd, yyyy HH:mm',
                    ).format(DateTime.parse(_deliveryData!['date_deadline'])),
                  ),
                if (_deliveryData!['date_done'] != null &&
                    _deliveryData!['date_done'] != false)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedCheckmarkCircle02,
                    'Done Date',
                    DateFormat(
                      'MMM dd, yyyy HH:mm',
                    ).format(DateTime.parse(_deliveryData!['date_done'])),
                  ),
                if (_deliveryData!['location_id'] != null)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedLocation01,
                    'From',
                    _safeString(_deliveryData!['location_id']),
                  ),
                if (_deliveryData!['location_dest_id'] != null)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedLocation03,
                    'To',
                    _safeString(_deliveryData!['location_dest_id']),
                  ),
                if (_deliveryData!['user_id'] != null)
                  _buildInfoRow(
                    isDark,
                    HugeIcons.strokeRoundedUserCircle,
                    'Responsible',
                    _safeString(_deliveryData!['user_id']),
                  ),
              ],
            ),

            if (_productMoves.isNotEmpty)
              _buildSectionCard(
                title: 'Products (${_productMoves.length})',
                icon: HugeIcons.strokeRoundedPackage,
                iconColor: isDark ? Colors.white70 : Colors.grey[800],
                isDark: isDark,
                children: _productMoves
                    .map((move) => _buildProductMoveRow(move, isDark))
                    .toList(),
              ),

            if (_deliveryData!['note'] != null &&
                _deliveryData!['note'] != false)
              _buildSectionCard(
                title: 'Notes',
                icon: HugeIcons.strokeRoundedNote,
                iconColor: isDark ? Colors.white70 : Colors.grey[800],
                isDark: isDark,
                children: [
                  Text(
                    _safeString(_deliveryData!['note']),
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                      height: 1.5,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color? iconColor,
    required bool isDark,
    required List<Widget> children,
    Widget? headerAction,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              if (headerAction != null) headerAction,
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(bool isDark, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.grey[200] : Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductMoveRow(Map<String, dynamic> move, bool isDark) {
    final productName = _safeString(move['product_id']);
    final demandQty = move['product_uom_qty'] ?? 0;
    final doneQty = move['quantity'] ?? 0;
    final uom =
        move['product_uom'] != null &&
            move['product_uom'] is List &&
            (move['product_uom'] as List).length > 1
        ? (move['product_uom'] as List)[1]
        : 'Units';
    final state = move['state'] ?? 'draft';

    Color stateColor;
    switch (state) {
      case 'done':
        stateColor = Colors.green;
        break;
      case 'assigned':
        stateColor = Colors.blue;
        break;
      default:
        stateColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800]?.withOpacity(0.5) : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  productName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: stateColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: stateColor.withOpacity(0.3)),
                ),
                child: Text(
                  state == 'done' ? 'Done' : 'Pending',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: stateColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                HugeIcons.strokeRoundedPackage,
                size: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              const SizedBox(width: 6),
              Text(
                'Demand: ',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              Text(
                '$demandQty $uom',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                HugeIcons.strokeRoundedCheckmarkCircle02,
                size: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              const SizedBox(width: 6),
              Text(
                'Done: ',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              Text(
                '$doneQty $uom',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: doneQty >= demandQty
                      ? Colors.green
                      : (isDark ? Colors.white : Colors.black87),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
