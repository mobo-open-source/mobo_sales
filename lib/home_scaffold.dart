import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_snake_navigationbar/flutter_snake_navigationbar.dart';
import 'package:mobo_sales/providers/quotation_provider.dart';
import 'package:mobo_sales/providers/settings_provider.dart';
import 'package:mobo_sales/utils/date_picker_utils.dart';
import 'widgets/custom_snackbar.dart';
import 'widgets/company_selector_widget.dart';
import 'screens/customers/customer_list_screen.dart';
import 'screens/quotations/quotation_list_screen.dart';
import 'screens/invoices/invoice_list_screen.dart';
import 'screens/products/product_list_screen.dart';
import 'screens/others/dashboard_screen.dart';
import 'screens/others/profile_screen.dart';
import 'package:intl/intl.dart';
import 'package:mobo_sales/widgets/circular_image_widget.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import 'widgets/lazy_load_indexed_stack.dart';

class HomeScaffold extends StatefulWidget {
  const HomeScaffold({super.key});

  @override
  HomeScaffoldState createState() => HomeScaffoldState();
}

class HomeScaffoldState extends State<HomeScaffold> {
  int _selectedIndex = 0;
  bool _hasInitializedSettings = false;
  late List<String> _titles;
  final GlobalKey<ProductListScreenState> _productListKey = GlobalKey();
  final GlobalKey<InvoiceListScreenState> _invoiceListKey = GlobalKey();
  final GlobalKey<CustomerListScreenState> _customerListKey = GlobalKey();

  Widget? _cachedProfileAction;

  @override
  void initState() {
    super.initState();
    _initializeTitles();

    _initializeSettingsProvider();
  }

  @override
  void dispose() {
    _cachedProfileAction = null;
    super.dispose();
  }

  void clearProfileActionCache() {
    setState(() {
      _cachedProfileAction = null;
    });
  }

  Future<void> _initializeSettingsProvider() async {
    if (_hasInitializedSettings) return;

    try {
      final settingsProvider = Provider.of<SettingsProvider>(
        context,
        listen: false,
      );
      await settingsProvider.fetchAllOdooData();
      _hasInitializedSettings = true;
    } catch (e) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !_hasInitializedSettings) {
          _initializeSettingsProvider();
        }
      });
    }
  }

  void _initializeTitles() {
    _titles = ['Dashboard', 'Customers', 'Quotations', 'Products', 'Invoices'];
  }

  void changeTab(int index) {
    if (index >= 0 && index < _titles.length) {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  List<Widget>? _buildPageActions(BuildContext context, int index) {
    return _buildProfileActions(context);
  }

  List<Widget> _buildScreens() {
    return [
      _buildScreenWithAppBar(const DashboardScreen(), 0),
      _buildScreenWithAppBar(CustomerListScreen(key: _customerListKey), 1),
      _buildScreenWithAppBar(const QuotationListScreen(), 2),
      _buildScreenWithAppBar(ProductListScreen(key: _productListKey), 3),
      _buildScreenWithAppBar(InvoiceListScreen(key: _invoiceListKey), 4),
    ];
  }

  Widget _buildScreenWithAppBar(Widget screen, int index) {
    return Builder(
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,

            title: Text(
              _titles[index],
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: _buildPageActions(context, index),
            backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
            foregroundColor: isDark
                ? Colors.white
                : Theme.of(context).primaryColor,
            elevation: 0,
            centerTitle: false,

            surfaceTintColor: Colors.transparent,
          ),
          body: screen,
        );
      },
    );
  }

  List<Widget> _buildProfileActions(BuildContext context) {
    _cachedProfileAction ??= _buildProfileActionWidget(context);
    return [const CompanySelectorWidget(), _cachedProfileAction!];
  }

  Widget _buildProfileActionWidget(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 14),
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          String? avatarData;

          try {
            final dynamic img = settings.userProfile != null
                ? settings.userProfile!['image_1920']
                : null;
            if (img is String && img.isNotEmpty && img != 'false') {
              avatarData = img;
            } else if (img is List && img.isNotEmpty) {}
          } catch (e) {}

          return CircularImageWidget(
            base64Image: avatarData,
            radius: 16,
            fallbackText:
                settings.userProfile != null &&
                    settings.userProfile!['name'] != null
                ? settings.userProfile!['name'].toString()
                : 'User',
            backgroundColor: AppTheme.primaryColor,
            textColor: Colors.white,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
            isLoading: settings.isLoadingUserProfile,
          );
        },
      ),
    );
  }

  static const Map<String, String> kQuotationFilters = {
    'quotation': 'Quotations',
    'sale': 'Sale Orders',
    'user_quotations': 'My Quotations',
    'invoiced': 'Invoiced',
    'to_invoice': 'To Invoice',
    'delivered': 'Delivered',
    'to_deliver': 'To Deliver',
    'expired': 'Expired Quotes',
  };

  static const Map<String, String> kQuotationGroupByOptions = {
    'state': 'Status',
    'partner_id': 'Customer',
    'user_id': 'Salesperson',
    'date_order': 'Order Date',
    'validity_date': 'Validity Date',
    'currency_id': 'Currency',
    'amount_total': 'Amount Range',
  };

  Set<String> _activeFilters = {};
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedGroupBy;

  bool _isFilterDisabled(String filter, Set<String> selected) {
    if (selected.contains('quotation')) {
      return filter != 'quotation';
    }
    if (selected.contains('sale')) {
      return filter == 'quotation';
    }
    if (selected.contains('invoiced') || selected.contains('to_invoice')) {
      return filter == 'quotation';
    }
    if (selected.contains('delivered') || selected.contains('to_deliver')) {
      return filter == 'quotation';
    }
    return false;
  }

  void showQuotationFilterAndGroupByBottomSheet() async {
    try {
      final provider = Provider.of<QuotationProvider>(context, listen: false);

      _activeFilters = Set.from(provider.activeFilters);
      _startDate = provider.startDate;
      _endDate = provider.endDate;

      await provider.fetchGroupByOptions();

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: true,
        enableDrag: true,
        builder: (context) => DefaultTabController(
          length: 2,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              final theme = Theme.of(context);
              final isDark = theme.brightness == Brightness.dark;

              return Container(
                height: MediaQuery.of(context).size.height * 0.8,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF232323) : Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Filter & Group By',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(
                              Icons.close,
                              color: isDark ? Colors.white : Colors.black54,
                            ),
                            splashRadius: 20,
                          ),
                        ],
                      ),
                    ),

                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[800] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TabBar(
                        indicator: BoxDecoration(
                          color: theme.primaryColor,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: theme.primaryColor.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        indicatorPadding: const EdgeInsets.all(4),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelColor: Colors.white,
                        unselectedLabelColor: isDark
                            ? Colors.grey[400]
                            : Colors.grey[600],
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        tabs: const [
                          Tab(height: 48, text: 'Filter'),
                          Tab(height: 48, text: 'Group By'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildFilterTab(
                            context,
                            setDialogState,
                            isDark,
                            theme,
                            provider,
                          ),
                          _buildGroupByTab(
                            context,
                            setDialogState,
                            isDark,
                            theme,
                            provider,
                          ),
                        ],
                      ),
                    ),

                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[850] : Colors.grey[50],
                        border: Border(
                          top: BorderSide(
                            color: isDark
                                ? Colors.grey[700]!
                                : Colors.grey[200]!,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                setDialogState(() {
                                  _activeFilters.clear();
                                  _startDate = null;
                                  _endDate = null;
                                  _selectedGroupBy = null;
                                });

                                final provider = Provider.of<QuotationProvider>(
                                  context,
                                  listen: false,
                                );
                                provider.setDateRange(null, null);
                                await provider.loadQuotations(
                                  filters: const {},
                                  clearGroupBy: true,
                                );
                                if (mounted) {
                                  CustomSnackbar.showInfo(
                                    context,
                                    'All filters cleared',
                                  );
                                  Navigator.of(context).pop();
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark
                                    ? Colors.white
                                    : Colors.black87,
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.grey[600]!
                                      : Colors.grey[300]!,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text('Clear All'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: () async {
                                try {
                                  Navigator.of(context).pop();

                                  provider.setDateRange(_startDate, _endDate);
                                  await provider.loadQuotations(
                                    filters: _activeFilters,
                                    groupBy: _selectedGroupBy,
                                  );

                                  final hasDateFilter =
                                      _startDate != null || _endDate != null;
                                  final totalFilters =
                                      _activeFilters.length +
                                      (hasDateFilter ? 1 : 0);

                                  if (mounted) {
                                    CustomSnackbar.showInfo(
                                      context,
                                      totalFilters == 0
                                          ? 'All filters cleared'
                                          : 'Applied $totalFilters filter${totalFilters > 1 ? 's' : ''}',
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    CustomSnackbar.showError(
                                      context,
                                      'Failed to apply filters: ${e.toString()}',
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text('Apply'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Failed to open filter dialog: ${e.toString()}',
        );
      }
    }
  }

  Widget _buildFilterTab(
    BuildContext context,
    StateSetter setDialogState,
    bool isDark,
    ThemeData theme,
    QuotationProvider provider,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_activeFilters.isNotEmpty) ...[
            Text(
              'Active Filters',
              style: theme.textTheme.labelMedium?.copyWith(
                color: isDark ? Colors.white : theme.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _activeFilters.map((filter) {
                final filterName = kQuotationFilters[filter] ?? filter;
                return Chip(
                  label: Text(filterName, style: const TextStyle(fontSize: 13)),
                  backgroundColor: isDark
                      ? Colors.white.withOpacity(.08)
                      : theme.primaryColor.withOpacity(0.08),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setDialogState(() {
                      _activeFilters.remove(filter);
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],

          Text(
            'Status',
            style: theme.textTheme.labelMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kQuotationFilters.entries.map((entry) {
              final selected = _activeFilters.contains(entry.key);
              final disabled = _isFilterDisabled(entry.key, _activeFilters);
              return ChoiceChip(
                label: Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: disabled
                        ? (isDark ? Colors.grey[700] : Colors.grey[400])
                        : (selected
                              ? Colors.white
                              : (isDark ? Colors.white : Colors.black87)),
                  ),
                ),
                selected: selected,
                selectedColor: theme.primaryColor,
                disabledColor: isDark ? Colors.grey[800] : Colors.grey[200],
                backgroundColor: isDark
                    ? Colors.white.withOpacity(.08)
                    : theme.primaryColor.withOpacity(0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                  ),
                ),
                onSelected: disabled
                    ? null
                    : (isSelected) {
                        setDialogState(() {
                          if (isSelected) {
                            _activeFilters.add(entry.key);
                          } else {
                            _activeFilters.remove(entry.key);
                          }
                        });
                      },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          Text(
            'Date Range (Creation Date)',
            style: theme.textTheme.labelMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start Date',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.grey[300] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        try {
                          final picked =
                              await DatePickerUtils.showStandardDatePicker(
                                context: context,
                                initialDate: _startDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 365),
                                ),
                              );
                          if (picked != null) {
                            setDialogState(() {
                              _startDate = picked;
                            });
                          }
                        } catch (e) {
                          if (mounted) {
                            CustomSnackbar.showError(
                              context,
                              'Failed to open date picker: ${e.toString()}',
                            );
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark
                                ? Colors.grey[600]!
                                : Colors.grey[400]!,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _startDate != null
                                    ? DateFormat(
                                        'MMM dd, yyyy',
                                      ).format(_startDate!)
                                    : 'Select start date',
                                style: TextStyle(
                                  color: _startDate != null
                                      ? (isDark ? Colors.white : Colors.black87)
                                      : (isDark
                                            ? Colors.grey[500]
                                            : Colors.grey[500]),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'End Date',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.grey[300] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        try {
                          final picked =
                              await DatePickerUtils.showStandardDatePicker(
                                context: context,
                                initialDate: _endDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 365),
                                ),
                              );
                          if (picked != null) {
                            setDialogState(() {
                              _endDate = picked;
                            });
                          }
                        } catch (e) {
                          if (mounted) {
                            CustomSnackbar.showError(
                              context,
                              'Failed to open date picker: ${e.toString()}',
                            );
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark
                                ? Colors.grey[600]!
                                : Colors.grey[400]!,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _endDate != null
                                    ? DateFormat(
                                        'MMM dd, yyyy',
                                      ).format(_endDate!)
                                    : 'Select end date',
                                style: TextStyle(
                                  color: _endDate != null
                                      ? (isDark ? Colors.white : Colors.black87)
                                      : (isDark
                                            ? Colors.grey[500]
                                            : Colors.grey[500]),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_startDate != null || _endDate != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  setDialogState(() {
                    _startDate = null;
                    _endDate = null;
                  });
                },
                icon: Icon(Icons.clear, size: 16, color: Colors.grey[600]),
                label: Text(
                  'Clear date range',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildGroupByTab(
    BuildContext context,
    StateSetter setDialogState,
    bool isDark,
    ThemeData theme,
    QuotationProvider provider,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Group quotations by',
            style: theme.textTheme.labelMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          RadioListTile<String?>(
            title: Text(
              'None',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              'Display as a simple list',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 12,
              ),
            ),
            value: null,
            groupValue: _selectedGroupBy,
            onChanged: (value) {
              setDialogState(() {
                _selectedGroupBy = value;
              });
            },
            activeColor: theme.primaryColor,
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(),

          if (provider.groupByOptions.isEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'No group by options available',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Retry',
                  icon: Icon(
                    Icons.refresh,
                    color: isDark ? Colors.white : Colors.black54,
                  ),
                  onPressed: () async {
                    try {
                      await provider.fetchGroupByOptions();
                      setDialogState(() {});
                    } catch (_) {}
                  },
                ),
              ],
            ),
          ] else ...[
            ...provider.groupByOptions.entries.map((entry) {
              String description = '';
              switch (entry.key) {
                case 'state':
                  description =
                      'Group by quotation status (Draft, Sent, Confirmed, etc.)';
                  break;
                case 'partner_id':
                  description = 'Group by customer name';
                  break;
                case 'user_id':
                  description = 'Group by assigned salesperson';
                  break;
                case 'date_order':
                  description = 'Group by order creation date';
                  break;
                case 'validity_date':
                  description = 'Group by quotation expiry date';
                  break;
                case 'currency_id':
                  description = 'Group by currency type';
                  break;
                case 'amount_total':
                  description = 'Group by total amount ranges';
                  break;
                default:
                  description = 'Group by ${entry.value.toLowerCase()}';
              }

              return RadioListTile<String>(
                title: Text(
                  entry.value,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  description,
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                value: entry.key,
                groupValue: _selectedGroupBy,
                onChanged: (value) {
                  setDialogState(() {
                    _selectedGroupBy = value;
                  });
                },
                activeColor: theme.primaryColor,
                contentPadding: EdgeInsets.zero,
              );
            }),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<BottomNavigationBarItem> _navBarItems() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return [
      BottomNavigationBarItem(
        icon: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5.0),
          child: Icon(HugeIcons.strokeRoundedDashboardSquare02),
        ),
        label: 'Dashboard',
        activeIcon: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5.0),
          child: Icon(
            HugeIcons.strokeRoundedDashboardSquare02,
            color: isDark ? Colors.white : Theme.of(context).primaryColor,
          ),
        ),
      ),
      BottomNavigationBarItem(
        icon: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5.0),
          child: Icon(HugeIcons.strokeRoundedContact01),
        ),
        label: 'Customers',
        activeIcon: Padding(
          padding: EdgeInsets.symmetric(vertical: 5.0),
          child: Icon(
            HugeIcons.strokeRoundedContact01,
            color: isDark ? Colors.white : Theme.of(context).primaryColor,
          ),
        ),
      ),
      BottomNavigationBarItem(
        icon: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5.0),
          child: Icon(HugeIcons.strokeRoundedFiles01),
        ),
        label: 'Quotations',
        activeIcon: Padding(
          padding: EdgeInsets.symmetric(vertical: 5.0),
          child: Icon(
            HugeIcons.strokeRoundedFiles01,
            color: isDark ? Colors.white : Theme.of(context).primaryColor,
          ),
        ),
      ),
      BottomNavigationBarItem(
        icon: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5.0),
          child: Icon(HugeIcons.strokeRoundedPackageOpen),
        ),
        label: 'Products',
        activeIcon: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5.0),
          child: Icon(
            HugeIcons.strokeRoundedPackageOpen,
            color: isDark ? Colors.white : Theme.of(context).primaryColor,
          ),
        ),
      ),
      BottomNavigationBarItem(
        icon: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5.0),
          child: Icon(HugeIcons.strokeRoundedInvoice03),
        ),
        label: 'Invoices',
        activeIcon: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5.0),
          child: Icon(
            HugeIcons.strokeRoundedInvoice03,
            color: isDark ? Colors.white : Theme.of(context).primaryColor,
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return WillPopScope(
      onWillPop: () async {
        if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
          });
          return false;
        }

        return true;
      },
      child: Scaffold(
        body: LazyLoadIndexedStack(
          index: _selectedIndex,
          children: _buildScreens(),
        ),
        bottomNavigationBar: SnakeNavigationBar.color(
          behaviour: SnakeBarBehaviour.pinned,
          snakeShape: SnakeShape.indicator,
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          selectedItemColor: isDark ? Colors.white : colorScheme.primary,
          unselectedItemColor: isDark ? Colors.grey[400] : Colors.black,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          items: _navBarItems(),
          snakeViewColor: isDark ? colorScheme.primary : colorScheme.primary,
          unselectedLabelStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          selectedLabelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : colorScheme.primary,
          ),
          shadowColor: isDark ? Colors.black26 : Colors.grey[200]!,
          elevation: 8,
          height: 70,
        ),
      ),
    );
  }
}
