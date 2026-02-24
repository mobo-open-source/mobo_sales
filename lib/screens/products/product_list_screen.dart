import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import 'package:shimmer/shimmer.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

import '../../models/product.dart';
import '../../services/connectivity_service.dart';
import '../../services/odoo_session_manager.dart';
import '../../services/runtime_permission_service.dart';
import '../../services/session_service.dart';
import '../../services/field_validation_service.dart';
import '../../widgets/connection_status_widget.dart';
import '../../widgets/custom_snackbar.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/list_shimmer.dart';
import '../../providers/product_provider.dart';
import '../../providers/company_provider.dart';
import '../../widgets/barcode_scanner_screen.dart';
import '../../widgets/product_list_tile.dart';
import 'product_details_page.dart';
import 'create_product_screen.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => ProductListScreenState();
}

class ProductListScreenState extends State<ProductListScreen>
    with AutomaticKeepAliveClientMixin {
  late final TextEditingController _searchController;
  late final ScrollController _scrollController;
  List<Map<String, dynamic>> _filteredProductTemplates = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  bool _hasLoaded = false;
  bool _isInitialLoad = true;

  static const int _pageSize = 40;
  int _currentPage = 0;
  int _totalProducts = 0;

  int get pageSize => _pageSize;

  int get currentPage => _currentPage;

  int get currentStartIndex => (_currentPage * _pageSize) + 1;

  int get currentEndIndex => _filteredProductTemplates.length;

  int get totalPages =>
      _totalProducts > 0 ? ((_totalProducts - 1) ~/ _pageSize) + 1 : 0;

  bool get canGoToPreviousPage {
    final productProvider = context.read<ProductProvider>();
    return productProvider.canGoToPreviousPage;
  }

  bool get canGoToNextPage {
    final productProvider = context.read<ProductProvider>();
    return productProvider.canGoToNextPage;
  }

  String getPaginationText() {
    final productProvider = context.read<ProductProvider>();
    return productProvider.getPaginationText();
  }

  Future<void> goToNextPage() async {
    final productProvider = context.read<ProductProvider>();
    if (!productProvider.canGoToNextPage || _isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await productProvider.goToNextPage();

      if (mounted) {
        setState(() {
          _currentPage = productProvider.currentPage;
          _totalProducts = productProvider.totalProducts;
          _hasMoreData = productProvider.hasMoreData;
          _isLoading = false;
        });
        _updateProductTemplates();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> goToPreviousPage() async {
    final productProvider = context.read<ProductProvider>();
    if (!productProvider.canGoToPreviousPage || _isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await productProvider.goToPreviousPage();

      if (mounted) {
        setState(() {
          _currentPage = productProvider.currentPage;
          _totalProducts = productProvider.totalProducts;
          _hasMoreData = productProvider.hasMoreData;
          _isLoading = false;
        });
        _updateProductTemplates();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  final ValueNotifier<bool> _isInitialProductsLoaded = ValueNotifier<bool>(
    false,
  );

  bool get isInitialProductsLoaded => _isInitialProductsLoaded.value;

  ValueListenable<bool> get isInitialProductsLoadedListenable =>
      _isInitialProductsLoaded;
  bool _isOffline = false;
  final bool _isServerUnreachable = false;
  bool _showScrollToTop = false;
  String? _clickedTileId;
  Timer? _debounceTimer;
  late final ConnectivityService _connectivityService;
  Timer? _retryTimer;

  static final List<Product> _cachedProducts = [];
  static DateTime? _lastFetchTime;
  static const Duration _cacheDuration = Duration(minutes: 5);
  static String _cachedSearchQuery = '';
  static int _cachedTotalProducts = 0;

  static void clearProductCache() {
    _cachedProducts.clear();
    _lastFetchTime = null;
    _cachedSearchQuery = '';
    _cachedTotalProducts = 0;
  }

  bool _hasSession = false;
  final bool _isActivePage = true;

  final Map<String, Uint8List> _base64ImageCache = {};

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _voiceInput = '';
  bool _isListeningDialogShown = false;
  Timer? _listeningTimeoutTimer;
  VoidCallback? _updateDialogCallback;
  bool _isProcessingSpeech = false;
  String _speechStatus = '';
  bool _isScanning = false;

  final Map<String, bool> _expandedProductGroups = {};
  bool _allProductGroupsExpanded = false;

  Map<String, int> _groupSummary = {};
  Map<String, List<Product>> _loadedGroups = {};
  final Map<String, int> _groupLoadedCounts = {};
  final Map<String, bool> _groupHasMore = {};
  final Map<String, bool> _groupLoading = {};

  Map<String, int> _cachedGroupSummary = {};
  final Map<String, List<Product>> _cachedLoadedGroups = {};
  String? _cachedGroupByField;

  @override
  bool get wantKeepAlive {
    return true;
  }

  bool _showServicesOnly = false;
  bool _showConsumablesOnly = false;
  bool _showStorableOnly = false;
  bool _showAvailableOnly = false;

  String _lastSearchValue = '';

  bool _isCacheValid() {
    final currentSearchQuery = _searchController.text.trim();
    final productProvider = context.read<ProductProvider>();
    final currentGroupBy = productProvider.selectedGroupBy;

    final isValid =
        _cachedProducts.isNotEmpty &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheDuration &&
        _cachedSearchQuery == currentSearchQuery &&
        _cachedGroupByField == currentGroupBy;

    return isValid;
  }

  @override
  void initState() {
    super.initState();

    _searchController = TextEditingController();
    _scrollController = ScrollController();
    _hasSession = false;

    _connectivityService = context.read<ConnectivityService>();
    _setupConnectivityListener();
    _scrollController.addListener(_onScroll);

    _searchController.addListener(() {
      final currentValue = _searchController.text;
      if (currentValue == _lastSearchValue) return;
      _lastSearchValue = currentValue;
      if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;

        setState(() {
          _currentPage = 0;
          _hasMoreData = true;
          _isLoading = true;
          _hasLoaded = false;
        });
        _loadProducts();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        final productProvider = context.read<ProductProvider>();
        if (productProvider.groupByOptions.isEmpty) {
          await productProvider.fetchGroupByOptions();
        }
      }
    });

    if (_isCacheValid()) {
      _totalProducts = _cachedTotalProducts;
      _updateProductTemplates();

      final productProvider = context.read<ProductProvider>();
      if (productProvider.selectedGroupBy != null &&
          productProvider.selectedGroupBy == _cachedGroupByField &&
          _cachedGroupSummary.isNotEmpty) {
        _groupSummary = Map.from(_cachedGroupSummary);
        _loadedGroups = Map.from(_cachedLoadedGroups);
      }

      setState(() {
        _isLoading = false;
        _hasLoaded = true;
        _isInitialLoad = false;
        _hasSession = true;
      });
      if (_filteredProductTemplates.isNotEmpty) {
        _isInitialProductsLoaded.value = true;
      }

      return;
    } else {
      final productProvider = context.read<ProductProvider>();
      if (productProvider.products.isNotEmpty) {
        _totalProducts = productProvider.totalProducts;
        _updateProductTemplates();
        setState(() {
          _isLoading = false;
          _hasLoaded = true;
          _isInitialLoad = false;
          _hasSession = true;
        });
        if (_filteredProductTemplates.isNotEmpty) {
          _isInitialProductsLoaded.value = true;
        }
      } else {
        setState(() {
          _isLoading = true;
        });
      }
    }

    _initializeAndLoadProducts();
  }

  void showProductFilterBottomSheet() async {
    try {
      final productProvider = context.read<ProductProvider>();

      final Map<String, dynamic> tempState = {
        'showServicesOnly': _showServicesOnly,
        'showConsumablesOnly': _showConsumablesOnly,
        'showStorableOnly': _showStorableOnly,
        'showAvailableOnly': _showAvailableOnly,
        'selectedGroupBy': productProvider.selectedGroupBy,
      };

      _showFilterBottomSheetUI(tempState, productProvider);
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Failed to open filter dialog: ${e.toString()}',
        );
      }
    }
  }

  void _showFilterBottomSheetUI(
    Map<String, dynamic> tempState,
    ProductProvider productProvider,
  ) {
    showModalBottomSheet<void>(
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
              child: SafeArea(
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
                    const SizedBox(height: 12),

                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildProductFilterTab(
                            context,
                            setDialogState,
                            isDark,
                            theme,
                            productProvider,
                            tempState,
                          ),
                          _buildProductGroupByTab(
                            context,
                            setDialogState,
                            isDark,
                            theme,
                            productProvider,
                            tempState,
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
                                  tempState['showServicesOnly'] = false;
                                  tempState['showConsumablesOnly'] = false;
                                  tempState['showStorableOnly'] = false;
                                  tempState['showAvailableOnly'] = false;
                                  tempState['selectedGroupBy'] = null;
                                });

                                setState(() {
                                  _showServicesOnly = false;
                                  _showConsumablesOnly = false;
                                  _showStorableOnly = false;
                                  _showAvailableOnly = false;

                                  _searchController.clear();
                                  _currentPage = 0;
                                  _isLoading = true;
                                  _hasLoaded = false;
                                  _filteredProductTemplates = [];
                                });

                                productProvider.setGroupBy(null);

                                setState(() {
                                  _currentPage = 0;
                                  _hasMoreData = true;
                                  _isLoading = true;
                                });
                                await _loadProducts();

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

                                  setState(() {
                                    _showServicesOnly =
                                        tempState['showServicesOnly'] ?? false;
                                    _showConsumablesOnly =
                                        tempState['showConsumablesOnly'] ??
                                        false;
                                    _showStorableOnly =
                                        tempState['showStorableOnly'] ?? false;
                                    _showAvailableOnly =
                                        tempState['showAvailableOnly'] ?? false;

                                    _currentPage = 0;
                                    _isLoading = true;
                                    _hasLoaded = false;
                                    _filteredProductTemplates = [];
                                  });

                                  _groupSummary.clear();
                                  _loadedGroups.clear();
                                  _groupLoadedCounts.clear();
                                  _groupHasMore.clear();
                                  _cachedGroupSummary.clear();
                                  _cachedLoadedGroups.clear();
                                  _cachedGroupByField = null;

                                  final provider = productProvider;

                                  provider.setFilterState(
                                    showServicesOnly: _showServicesOnly,
                                    showConsumablesOnly: _showConsumablesOnly,
                                    showStorableOnly: _showStorableOnly,
                                    showAvailableOnly: _showAvailableOnly,
                                  );

                                  provider.setGroupBy(
                                    tempState['selectedGroupBy'] as String?,
                                  );

                                  setState(() {
                                    _currentPage = 0;
                                    _hasMoreData = true;
                                    _isLoading = true;
                                  });
                                  await _loadProducts();

                                  final totalFilters =
                                      (tempState['showServicesOnly'] == true
                                          ? 1
                                          : 0) +
                                      (tempState['showConsumablesOnly'] == true
                                          ? 1
                                          : 0) +
                                      (tempState['showStorableOnly'] == true
                                          ? 1
                                          : 0) +
                                      (tempState['showAvailableOnly'] == true
                                          ? 1
                                          : 0);
                                  final hasGroupBy =
                                      tempState['selectedGroupBy'] != null;

                                  if (mounted) {
                                    String message;
                                    if (totalFilters == 0 && !hasGroupBy) {
                                      message = 'All filters cleared';
                                    } else {
                                      final parts = <String>[];
                                      if (totalFilters > 0) {
                                        parts.add(
                                          '$totalFilters filter${totalFilters > 1 ? 's' : ''}',
                                        );
                                      }
                                      if (hasGroupBy) {
                                        parts.add('group by');
                                      }
                                      message =
                                          'Applied ${parts.join(' and ')}';
                                    }
                                    CustomSnackbar.showInfo(context, message);
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
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProductFilterTab(
    BuildContext context,
    StateSetter setDialogState,
    bool isDark,
    ThemeData theme,
    ProductProvider productProvider,
    Map<String, dynamic> tempState,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tempState['showServicesOnly'] == true ||
              tempState['showConsumablesOnly'] == true ||
              tempState['showStorableOnly'] == true ||
              tempState['showAvailableOnly'] == true) ...[
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
              children: [
                if (tempState['showServicesOnly'] == true)
                  Chip(
                    label: const Text(
                      'Services',
                      style: TextStyle(fontSize: 13),
                    ),
                    backgroundColor: isDark
                        ? Colors.white.withOpacity(.08)
                        : theme.primaryColor.withOpacity(0.08),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setDialogState(
                      () => tempState['showServicesOnly'] = false,
                    ),
                  ),
                if (tempState['showConsumablesOnly'] == true)
                  Chip(
                    label: const Text(
                      'Consumables',
                      style: TextStyle(fontSize: 13),
                    ),
                    backgroundColor: isDark
                        ? Colors.white.withOpacity(.08)
                        : theme.primaryColor.withOpacity(0.08),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setDialogState(
                      () => tempState['showConsumablesOnly'] = false,
                    ),
                  ),
                if (tempState['showStorableOnly'] == true)
                  Chip(
                    label: const Text(
                      'Storable',
                      style: TextStyle(fontSize: 13),
                    ),
                    backgroundColor: isDark
                        ? Colors.white.withOpacity(.08)
                        : theme.primaryColor.withOpacity(0.08),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setDialogState(
                      () => tempState['showStorableOnly'] = false,
                    ),
                  ),
                if (tempState['showAvailableOnly'] == true)
                  Chip(
                    label: const Text(
                      'Available Only',
                      style: TextStyle(fontSize: 13),
                    ),
                    backgroundColor: isDark
                        ? Colors.white.withOpacity(.08)
                        : theme.primaryColor.withOpacity(0.08),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setDialogState(
                      () => tempState['showAvailableOnly'] = false,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          Text(
            'Product Type',
            style: theme.textTheme.labelMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: Text(
                  'Services',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: tempState['showServicesOnly'] == true
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: tempState['showServicesOnly'] == true
                        ? Colors.white
                        : (isDark ? Colors.white : Colors.black87),
                  ),
                ),
                selected: tempState['showServicesOnly'] == true,
                selectedColor: theme.primaryColor,
                backgroundColor: isDark
                    ? Colors.white.withOpacity(.08)
                    : theme.primaryColor.withOpacity(0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                  ),
                ),
                onSelected: (val) {
                  setDialogState(() {
                    tempState['showServicesOnly'] = val;
                  });
                },
              ),
              ChoiceChip(
                label: Text(
                  'Consumables',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: tempState['showConsumablesOnly'] == true
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: tempState['showConsumablesOnly'] == true
                        ? Colors.white
                        : (isDark ? Colors.white : Colors.black87),
                  ),
                ),
                selected: tempState['showConsumablesOnly'] == true,
                selectedColor: theme.primaryColor,
                backgroundColor: isDark
                    ? Colors.white.withOpacity(.08)
                    : theme.primaryColor.withOpacity(0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                  ),
                ),
                onSelected: (val) {
                  setDialogState(() {
                    tempState['showConsumablesOnly'] = val;
                  });
                },
              ),
              ChoiceChip(
                label: Text(
                  'Storable',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: tempState['showStorableOnly'] == true
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: tempState['showStorableOnly'] == true
                        ? Colors.white
                        : (isDark ? Colors.white : Colors.black87),
                  ),
                ),
                selected: tempState['showStorableOnly'] == true,
                selectedColor: theme.primaryColor,
                backgroundColor: isDark
                    ? Colors.white.withOpacity(.08)
                    : theme.primaryColor.withOpacity(0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                  ),
                ),
                onSelected: (val) {
                  setDialogState(() {
                    tempState['showStorableOnly'] = val;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text(
            'Availability',
            style: theme.textTheme.labelMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: Text(
                  'Available Only',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: tempState['showAvailableOnly'] == true
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: tempState['showAvailableOnly'] == true
                        ? Colors.white
                        : (isDark ? Colors.white : Colors.black87),
                  ),
                ),
                selected: tempState['showAvailableOnly'] == true,
                selectedColor: theme.primaryColor,
                backgroundColor: isDark
                    ? Colors.white.withOpacity(.08)
                    : theme.primaryColor.withOpacity(0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                  ),
                ),
                onSelected: (val) {
                  setDialogState(() {
                    tempState['showAvailableOnly'] = val;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildProductGroupByTab(
    BuildContext context,
    StateSetter setDialogState,
    bool isDark,
    ThemeData theme,
    ProductProvider productProvider,
    Map<String, dynamic> tempState,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Group products by',
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
            groupValue: tempState['selectedGroupBy'],
            onChanged: (value) {
              setDialogState(() {
                tempState['selectedGroupBy'] = value;
              });
            },
            activeColor: theme.primaryColor,
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(),

          if (productProvider.groupByOptions.isEmpty) ...[
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
                      await productProvider.fetchGroupByOptions();
                      setDialogState(() {});
                    } catch (_) {}
                  },
                ),
              ],
            ),
          ] else ...[
            ...productProvider.groupByOptions.entries.map((entry) {
              String description = '';
              switch (entry.key) {
                case 'categ_id':
                  description = 'Group by product category';
                  break;
                case 'type':
                  description =
                      'Group by product type (Consumable, Service, Storable)';
                  break;
                case 'pos_categ_id':
                  description = 'Group by POS product category';
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
                groupValue: tempState['selectedGroupBy'],
                onChanged: (value) {
                  setDialogState(() {
                    tempState['selectedGroupBy'] = value;
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

  Future<void> _initializeAndLoadProducts() async {
    if (_isCacheValid()) {
      return;
    }

    final connectivityService = context.read<ConnectivityService>();
    final sessionService = context.read<SessionService>();
    final companyProvider = context.read<CompanyProvider>();

    while (companyProvider.isLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (connectivityService.isConnected && sessionService.hasValidSession) {
      if (mounted) _loadProducts();
    } else {
      setState(() {
        _isLoading = false;
        _hasSession = false;
        _hasLoaded = true;
        _isInitialLoad = false;
      });
    }
  }

  Future<void> _showPermissionDialog() async {
    if (!mounted) return;

    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Microphone Permission'),
        content: const Text(
          'Voice search requires microphone access to convert your speech to text.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not Now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );

    if (shouldOpenSettings == true) {
      await openAppSettings();

      if (mounted) {
        final status = await Permission.microphone.status;
        if (status.isGranted) {
          _listen();
        }
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels > 300 && !_showScrollToTop) {
      setState(() => _showScrollToTop = true);
    } else if (_scrollController.position.pixels <= 300 && _showScrollToTop) {
      setState(() => _showScrollToTop = false);
    }
  }

  Future<void> _loadMoreData() async {
    if (!_hasMoreData || _isLoadingMore || !mounted) return;

    try {
      setState(() {
        _isLoadingMore = true;
      });
      await _loadProducts(isLoadMore: true);
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
        CustomSnackbar.showError(context, 'Failed to load more products: $e');
      }
    }
  }

  void _onConnectivityChanged() {
    if (mounted) {
      final wasOffline = _isOffline;
      final nowOffline = !_connectivityService.isConnected;
      setState(() {
        _isOffline = nowOffline;
      });

      if (!nowOffline && wasOffline) {
        _loadProducts();
      }
    }
  }

  void _setupConnectivityListener() {
    _connectivityService.addListener(_onConnectivityChanged);
  }

  Future<void> _checkConnectivity() async {
    if (mounted) {
      setState(() {
        _isOffline = !_connectivityService.isConnected;
      });
    }
  }

  void _startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadProducts();
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _loadProducts({bool isLoadMore = false}) async {
    if (!mounted) return;

    if (isLoadMore) {
      if (_isLoadingMore) return;
    } else {
      if (_isLoading && _hasLoaded) return;
    }

    if (mounted) {
      setState(() {
        if (isLoadMore) {
          _isLoadingMore = true;
        } else {
          _isLoading = true;
        }
      });
    }

    final sessionService = context.read<SessionService>();
    final productProvider = context.read<ProductProvider>();

    try {
      await _checkConnectivity();
      if (_isOffline) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
        return;
      }

      if (!sessionService.hasValidSession) {
        if (mounted) {
          setState(() {
            _hasSession = false;
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
        return;
      }

      bool shouldFetchGroupSummary = productProvider.selectedGroupBy != null;

      final searchQuery = _searchController.text.trim();

      final filters = {
        'showServicesOnly': _showServicesOnly,
        'showConsumablesOnly': _showConsumablesOnly,
        'showStorableOnly': _showStorableOnly,
        'showAvailableOnly': _showAvailableOnly,
      };

      if (isLoadMore) {
        await productProvider.goToNextPage();
      } else {
        await productProvider.fetchProducts(
          searchQuery: searchQuery,
          filters: filters,
        );
      }

      if (!mounted) return;

      setState(() {
        _totalProducts = productProvider.totalProducts;
        _hasMoreData = productProvider.hasMoreData;
        _currentPage = productProvider.currentPage;
        _isLoading = false;
        _isLoadingMore = false;
      });

      _updateProductTemplates();

      if (shouldFetchGroupSummary) {
        await _fetchGroupSummary();

        if (mounted) {
          _cachedGroupSummary = Map.from(_groupSummary);
          _cachedGroupByField = productProvider.selectedGroupBy;
        }
      } else {
        _groupSummary.clear();
        _loadedGroups.clear();
      }

      if (!_isInitialProductsLoaded.value &&
          _filteredProductTemplates.isNotEmpty) {
        _isInitialProductsLoaded.value = true;
      }

      setState(() {
        _hasLoaded = true;
        _isInitialLoad = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasSession = sessionService.hasValidSession;
          _hasLoaded = true;
          _isInitialLoad = false;

          if (productProvider.accessErrorMessage != null) {
          } else {
            final errorMsg = _getErrorMessage(e);
            if (errorMsg.contains('Server data issue')) {
              _showErrorSnackBar(
                'Loading products with basic information. Some details may be limited.',
              );
            } else {
              _showErrorSnackBar('Failed to load products: $errorMsg');
            }
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final productProvider = context.read<ProductProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.grey[850] : Colors.white;
    final borderColor = isDark ? Colors.grey[800]! : Colors.grey[200]!;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[300] : Colors.grey[700];
    final backgroundColor = isDark ? Colors.grey[900] : Colors.grey[50];

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 16, bottom: 16),
            child: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF000000).withOpacity(0.05),
                    offset: Offset(0, 6),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                enabled: !_isLoading,
                style: TextStyle(
                  color: isDark ? Colors.white : Color(0xff1E1E1E),
                  fontWeight: FontWeight.w400,
                  fontStyle: FontStyle.normal,
                  fontSize: 15,
                  height: 1.0,
                  letterSpacing: 0.0,
                ),
                decoration: InputDecoration(
                  hintText: 'Search products...',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white : Color(0xff1E1E1E),
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.normal,
                    fontSize: 15,
                    height: 1.0,
                    letterSpacing: 0.0,
                  ),
                  prefixIcon: IconButton(
                    icon: Icon(
                      HugeIcons.strokeRoundedFilterHorizontal,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      size: 18,
                    ),
                    tooltip: 'Filter & Group By',
                    onPressed: () {
                      showProductFilterBottomSheet();
                    },
                  ),
                  suffixIcon: Container(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (_searchController.text.isNotEmpty)
                          Transform.translate(
                            offset: const Offset(4, 0),
                            child: IconButton(
                              icon: Icon(
                                Icons.clear,
                                color: isDark ? Colors.grey[400] : Colors.grey,
                                size: 20,
                              ),
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      _searchController.clear();
                                    },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                            ),
                          ),
                        Transform.translate(
                          offset: const Offset(-4, 0),
                          child: IconButton(
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: _isListening
                                  ? Icon(
                                      HugeIcons.strokeRoundedMic01,
                                      key: const ValueKey('listening'),
                                      color: Colors.red,
                                      size: 20,
                                    )
                                  : Icon(
                                      HugeIcons.strokeRoundedMic01,
                                      key: const ValueKey('idle'),
                                      color: isDark
                                          ? Colors.grey[400]
                                          : Colors.grey[600],
                                      size: 20,
                                    ),
                            ),
                            onPressed: _isLoading ? null : _listen,
                            tooltip: _isLoading
                                ? 'Loading...'
                                : (_isListening
                                      ? 'Listening...'
                                      : 'Voice Search'),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                          ),
                        ),
                        Transform.translate(
                          offset: const Offset(-8, 0),
                          child: IconButton(
                            icon: _isScanning
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  )
                                : Icon(
                                    HugeIcons.strokeRoundedCameraAi,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                    size: 20,
                                  ),
                            onPressed: _isLoading
                                ? null
                                : _isScanning
                                ? null
                                : _scanBarcode,
                            tooltip: 'Scan Barcode',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  filled: true,
                  fillColor: isDark ? Colors.grey[850] : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  isDense: true,
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                _buildFilterIndicator(isDark, productProvider.isGrouped),

                if (productProvider.isGrouped) ...[
                  const SizedBox(width: 8),
                  _buildGroupByPill(
                    isDark,
                    productProvider.groupByOptions[productProvider
                            .selectedGroupBy] ??
                        productProvider.selectedGroupBy!,
                  ),
                ],

                const Spacer(),

                _buildTopPaginationBar(productProvider),
              ],
            ),
          ),
          Expanded(
            child: Consumer2<ConnectivityService, SessionService>(
              builder: (context, connectivityService, sessionService, child) {
                final productProvider = context.read<ProductProvider>();
                if (!connectivityService.isConnected) {
                  return ConnectionStatusWidget(
                    onRetry: () {
                      if (connectivityService.isConnected &&
                          sessionService.hasValidSession) {
                        _loadProducts();
                      }
                    },
                    customMessage:
                        'No internet connection. Please check your connection and try again.',
                  );
                }
                if (productProvider.isServerUnreachable) {
                  return ConnectionStatusWidget(
                    onRetry: () {
                      if (connectivityService.isConnected &&
                          sessionService.hasValidSession) {
                        _loadProducts();
                      }
                    },
                    customMessage:
                        'Unable to load products from server/database. Please check your server or try again.',
                    serverUnreachable: productProvider.isServerUnreachable,
                    serverErrorMessage: productProvider.isServerUnreachable
                        ? 'Unable to load products from server/database. Please check your server or try again.'
                        : null,
                  );
                }

                if (productProvider.accessErrorMessage != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 20,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.06)
                                  : Theme.of(
                                      context,
                                    ).colorScheme.error.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withOpacity(0.18)
                                    : Theme.of(
                                        context,
                                      ).colorScheme.error.withOpacity(0.18),
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: isDark
                                      ? Colors.white.withOpacity(0.85)
                                      : Theme.of(
                                          context,
                                        ).colorScheme.error.withOpacity(0.85),
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Access Error',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Theme.of(context).colorScheme.error,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  productProvider.accessErrorMessage!,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white.withOpacity(0.8)
                                        : Theme.of(
                                            context,
                                          ).colorScheme.error.withOpacity(0.8),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isDark
                                          ? Colors.white.withOpacity(0.1)
                                          : Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                      foregroundColor: isDark
                                          ? Colors.white
                                          : Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                    onPressed: () {
                                      _loadProducts();
                                    },
                                    icon: Icon(Icons.refresh, size: 20),
                                    label: Text(
                                      'Retry',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (_isLoading ||
                    _isInitialLoad ||
                    productProvider.isLoading ||
                    (!productProvider.hasInitiallyLoaded &&
                        _filteredProductTemplates.isEmpty)) {
                  return ListShimmer.buildListShimmer(
                    context,
                    itemCount: 8,
                    type: ShimmerType.product,
                  );
                }

                if (_hasLoaded && _filteredProductTemplates.isNotEmpty) {
                  return _buildProductList(
                    context,
                    cardColor!,
                    borderColor,
                    textColor,
                    subtitleColor!,
                    isDark,
                  );
                }

                return _buildProductList(
                  context,
                  cardColor!,
                  borderColor,
                  textColor,
                  subtitleColor!,
                  isDark,
                );
              },
            ),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_create_product',
        onPressed: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => CreateProductScreen()),
          );
          if (result != null) {
            _cachedProducts.clear();
            _lastFetchTime = null;
            if (mounted) setState(() => _isLoading = true);
            await _loadProducts();
          }
        },
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : Theme.of(context).primaryColor,
        child: Icon(
          HugeIcons.strokeRoundedPackageAdd,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.black
              : Colors.white,
        ),
      ),
    );
  }

  Widget _buildProductsListShimmer(
    Color shimmerBase,
    Color shimmerHighlight,
    Color cardColor,
    Color borderColor,
  ) {
    return Shimmer.fromColors(
      baseColor: shimmerBase,
      highlightColor: shimmerHighlight,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 5,
        itemBuilder: (context, index) {
          return Card(
            color: cardColor,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: borderColor, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 150, height: 16, color: Colors.white),
                        const SizedBox(height: 8),
                        Container(width: 100, height: 12, color: Colors.white),
                        const SizedBox(height: 8),
                        Container(width: 120, height: 12, color: Colors.white),
                        const SizedBox(height: 12),
                        Row(
                          children: List.generate(
                            2,
                            (i) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Container(
                                width: 40,
                                height: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductList(
    BuildContext context,
    Color cardColor,
    Color borderColor,
    Color textColor,
    Color subtitleColor,
    bool isDark,
  ) {
    final productProvider = context.read<ProductProvider>();
    final activeGroupKey = productProvider.selectedGroupBy;

    if (_filteredProductTemplates.isEmpty) {
      if (_isLoadingMore || _isLoading || _isInitialLoad || !_hasLoaded) {
        return ListShimmer.buildListShimmer(
          context,
          itemCount: 8,
          type: ShimmerType.product,
        );
      }

      final hasActiveFilters =
          _showServicesOnly ||
          _showConsumablesOnly ||
          _showStorableOnly ||
          _showAvailableOnly ||
          _searchController.text.isNotEmpty;

      if (productProvider.isServerUnreachable ||
          (productProvider.error != null &&
              _isServerUnreachableError(productProvider.error!))) {
        return ConnectionStatusWidget(
          serverUnreachable: true,
          serverErrorMessage: productProvider.error,
          onRetry: _refreshProducts,
        );
      }

      if (productProvider.error != null) {
        return RefreshIndicator(
          onRefresh: _refreshProducts,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyStateWidget(
                  icon: HugeIcons.strokeRoundedPackage,
                  title: 'Error Loading Products',
                  message: productProvider.error!,
                  showRetry: true,
                  onRetry: _refreshProducts,
                ),
              ),
            ],
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: _refreshProducts,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStateWidget.products(
                hasSearchQuery: _searchController.text.isNotEmpty,
                hasFilters: hasActiveFilters,
                onClearFilters: hasActiveFilters
                    ? () async {
                        setState(() {
                          _showServicesOnly = false;
                          _showConsumablesOnly = false;
                          _showStorableOnly = false;
                          _showAvailableOnly = false;
                          _searchController.clear();
                        });

                        setState(() => _isLoading = true);
                        await _loadProducts(isLoadMore: false);
                      }
                    : null,
                onRetry: _refreshProducts,
              ),
            ),
          ],
        ),
      );
    }

    if (activeGroupKey != null) {
      if (_groupSummary.isEmpty) {
        return ListShimmer.buildListShimmer(
          context,
          itemCount: 8,
          type: ShimmerType.product,
        );
      }

      for (final groupKey in _groupSummary.keys) {
        if (!_expandedProductGroups.containsKey(groupKey)) {
          _expandedProductGroups[groupKey] = false;
        }
      }

      _expandedProductGroups.removeWhere(
        (key, value) => !_groupSummary.containsKey(key),
      );

      return Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshProducts,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _groupSummary.length,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemBuilder: (context, index) {
                  try {
                    final groupKey = _groupSummary.keys.elementAt(index);
                    final count = _groupSummary[groupKey]!;
                    final isExpanded =
                        _expandedProductGroups[groupKey] ?? false;
                    final loadedProducts = _loadedGroups[groupKey] ?? [];

                    return _buildOdooStyleProductGroupTile(
                      groupKey,
                      count,
                      loadedProducts,
                      isExpanded,
                      isDark,
                      cardColor,
                      borderColor,
                      textColor,
                      subtitleColor,
                    );
                  } catch (e) {
                    return const SizedBox.shrink();
                  }
                },
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshProducts,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filteredProductTemplates.length,
              itemBuilder: (context, index) {
                final template = _filteredProductTemplates[index];
                return _buildProductCard(
                  template,
                  cardColor,
                  borderColor,
                  textColor,
                  subtitleColor,
                  isDark,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOdooStyleProductGroupTile(
    String groupKey,
    int count,
    List<Product> loadedProducts,
    bool isExpanded,
    bool isDark,
    Color cardColor,
    Color borderColor,
    Color textColor,
    Color subtitleColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 6),
              color: Colors.black.withOpacity(0.08),
            ),
        ],
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          InkWell(
            onTap: () async {
              try {
                setState(() {
                  _expandedProductGroups[groupKey] = !isExpanded;
                  _allProductGroupsExpanded = _expandedProductGroups.values
                      .every((expanded) => expanded);
                });

                if (!isExpanded && !_loadedGroups.containsKey(groupKey)) {
                  await loadGroupProducts(groupKey);
                }
              } catch (e) {}
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          groupKey,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$count product${count != 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),

          if (isExpanded) ...[
            if (loadedProducts.isEmpty && _groupLoading[groupKey] == true)
              Container(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.primaryColor,
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Loading products...',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (loadedProducts.isEmpty && _groupLoading[groupKey] != true)
              Container(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No products found',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
              )
            else ...[
              ...loadedProducts.map((product) {
                final imageUrl = product.imageUrl;
                Uint8List? imageBytes;
                if (imageUrl != null &&
                    imageUrl.isNotEmpty &&
                    !imageUrl.startsWith('http')) {
                  try {
                    final base64String = imageUrl.contains(',')
                        ? imageUrl.split(',')[1]
                        : imageUrl;

                    if (base64String.isNotEmpty &&
                        base64String.length % 4 == 0 &&
                        RegExp(
                          r'^[A-Za-z0-9+/]*={0,2}$',
                        ).hasMatch(base64String)) {
                      final decoded = base64Decode(base64String);

                      if (decoded.isNotEmpty && decoded.length > 100) {
                        imageBytes = decoded;
                      }
                    }
                  } catch (e) {
                    imageBytes = null;
                  }
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: ProductListTile(
                    id: product.id.toString(),
                    name: product.name,
                    defaultCode: product.defaultCode,
                    listPrice: product.listPrice,
                    currencyId: product.currencyId,
                    category: product.category,
                    qtyAvailable: product.qtyAvailable,
                    imageUrl: imageUrl,
                    imageBytes: imageBytes,
                    isDark: isDark,
                    onTap: () {
                      Product navProduct = product;
                      if (product.productVariantIds != null &&
                          product.productVariantIds!.isNotEmpty) {
                        navProduct = product.copyWith(
                          id: product.productVariantIds![0].toString(),
                        );
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ProductDetailsPage(product: navProduct),
                        ),
                      );
                    },
                  ),
                );
              }),

              if (_groupHasMore[groupKey] == true)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _groupLoading[groupKey] == true
                      ? Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppTheme.primaryColor,
                              ),
                            ),
                          ),
                        )
                      : TextButton.icon(
                          onPressed: () async {
                            await loadGroupProducts(groupKey);
                          },
                          icon: Icon(Icons.expand_more, size: 20),
                          label: Text(
                            'Load More (${_groupLoadedCounts[groupKey]}/$count)',
                            style: TextStyle(fontSize: 14),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primaryColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                        ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildProductCard(
    Map<String, dynamic> template,
    Color cardColor,
    Color borderColor,
    Color textColor,
    Color subtitleColor,
    bool isDark,
  ) {
    final imageUrl = template['imageUrl'] as String?;
    Uint8List? imageBytes;
    if (imageUrl != null &&
        imageUrl.isNotEmpty &&
        !imageUrl.startsWith('http')) {
      try {
        final base64String = imageUrl.contains(',')
            ? imageUrl.split(',')[1]
            : imageUrl;
        imageBytes = base64Decode(base64String);
      } catch (e) {}
    }
    return ProductListTile(
      id: template['id'].toString(),
      name: template['name'] as String,
      defaultCode: template['defaultCode']?.toString(),
      listPrice: (template['listPrice'] as num?)?.toDouble() ?? 0.0,
      currencyId: template['currencyId'] as List?,
      category: template['category']?.toString(),
      qtyAvailable: (template['qtyAvailable'] as num?)?.toDouble() ?? 0.0,
      imageUrl: imageUrl,
      imageBytes: imageBytes,
      variantCount: (template['variantCount'] as int?) ?? 1,
      isDark: isDark,
      imageCache: _base64ImageCache,
      onTap: () async {
        if ((template['variantCount'] as int? ?? 1) > 1) {
          final odooClient = await OdooSessionManager.getClient();
          if (odooClient != null) {
            _showVariantsDialog(context, template, odooClient, null);
          }
        } else {
          final variants = template['variants'] as List?;
          if (variants != null && variants.isNotEmpty) {
            Product navProduct = variants[0] as Product;
            final variantIds = template['productVariantIds'] as List<int>?;
            if (variantIds != null && variantIds.isNotEmpty) {
              navProduct = navProduct.copyWith(id: variantIds[0].toString());
            }
            _navigateToDetails(navProduct);
          }
        }
      },
    );
  }

  Widget _buildTag({
    required String text,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildProductImage(
    String? imageUrl,
    Uint8List? imageBytes,
    String name,
  ) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: imageUrl != null && imageUrl.isNotEmpty
            ? imageUrl.startsWith('http')
                  ? _buildFadeInNetworkImage(imageUrl, name)
                  : _buildFadeInBase64Image(imageUrl, name)
            : const Icon(
                HugeIcons.strokeRoundedImage03,
                color: Colors.grey,
                size: 30,
              ),
      ),
    );
  }

  Widget _buildFadeInNetworkImage(String imageUrl, String name) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: 60,
      height: 60,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (context, url) => Container(color: Colors.grey[200]),
      errorWidget: (context, url, error) {
        return const Icon(
          HugeIcons.strokeRoundedImage03,
          color: Colors.grey,
          size: 24,
        );
      },
    );
  }

  Widget _buildFadeInBase64Image(String imageUrl, String name) {
    if (_base64ImageCache.containsKey(imageUrl)) {
      return _FadeInMemoryImage(bytes: _base64ImageCache[imageUrl]!);
    }
    return FutureBuilder<Uint8List?>(
      future: _decodeBase64Image(imageUrl, name),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData) {
          return _FadeInMemoryImage(bytes: snapshot.data!);
        }
        return Container(
          color: Colors.grey[100],
          child: const Center(
            child: Icon(
              HugeIcons.strokeRoundedImage03,
              color: Colors.grey,
              size: 24,
            ),
          ),
        );
      },
    );
  }

  Future<Uint8List?> _decodeBase64Image(String imageUrl, String name) async {
    if (_base64ImageCache.containsKey(imageUrl)) {
      return _base64ImageCache[imageUrl];
    }
    try {
      var base64String = imageUrl.contains(',')
          ? imageUrl.split(',')[1]
          : imageUrl;

      base64String = base64String.replaceAll(RegExp(r'\s+'), '');

      if (base64String.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 10));
        final bytes = base64Decode(base64String);

        if (bytes.isNotEmpty) {
          if (bytes[0] == 0x3c) {
            return null;
          }
        }

        _base64ImageCache[imageUrl] = bytes;
        return bytes;
      }
    } catch (e) {}
    return null;
  }

  Future<void> _showVariantsDialog(
    BuildContext context,
    Map<String, dynamic> template,
    OdooClient odooClient,
    Map<String, String>? selectedAttributes,
  ) async {
    List<Product> variants = (template['variants'] as List<dynamic>)
        .cast<Product>()
        .toList();
    final variantCount = template['variantCount'] as int? ?? 1;
    final variantIds = template['productVariantIds'] as List<int>?;

    if (variants.length < variantCount &&
        variantIds != null &&
        variantIds.isNotEmpty) {
      try {
        final result =
            await FieldValidationService.executeWithFieldValidation<
              List<dynamic>
            >(
              model: 'product.product',
              apiCall: (fields) async {
                return await odooClient.callKw({
                  'model': 'product.product',
                  'method': 'search_read',
                  'args': [
                    [
                      ['id', 'in', variantIds],
                    ],
                  ],
                  'kwargs': {'fields': fields},
                });
              },
              initialFields: [
                'id',
                'name',
                'list_price',
                'qty_available',
                'default_code',
                'image_128',
                'barcode',
                'categ_id',
                'product_tmpl_id',
                'currency_id',
                'product_template_attribute_value_ids',
              ],
            );

        variants = result.map((data) => Product.fromJson(data)).toList();
        template['variants'] = variants;
      } catch (e) {}
    }

    if (variants.isEmpty) return;

    final deviceSize = MediaQuery.of(context).size;
    final dialogHeight = deviceSize.height * 0.75;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final maxListHeight = MediaQuery.of(dialogContext).size.height * 0.6;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 8,
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: dialogHeight,
              minHeight: 300,
              maxWidth: MediaQuery.of(context).size.width - 32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Product Variants',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              template["name"] ?? 'Unknown Product',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: maxListHeight,
                      minHeight: 200,
                    ),
                    child:
                        FutureBuilder<
                          List<Map<Product, List<Map<String, String>>>>
                        >(
                          future: Future.wait(
                            variants.map((variant) async {
                              final attributes = await _fetchVariantAttributes(
                                odooClient,
                                variant.productTemplateAttributeValueIds,
                              );
                              return {variant: attributes};
                            }),
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const VariantsDialogShimmer();
                            }
                            if (snapshot.hasError) {
                              return const Center(
                                child: Text('Error loading variants'),
                              );
                            }
                            final variantAttributes = snapshot.data ?? [];
                            final uniqueVariants =
                                <
                                  String,
                                  Map<Product, List<Map<String, String>>>
                                >{};
                            for (var entry in variantAttributes) {
                              final variant = entry.keys.first;
                              final attrs = entry.values.first;
                              final key =
                                  '${variant.defaultCode ?? variant.id}_${attrs.map((a) => '${a['attribute_name']}:${a['value_name']}').join('|')}';
                              uniqueVariants[key] = entry;
                            }

                            return ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              shrinkWrap: true,
                              itemCount: uniqueVariants.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                thickness: 0.5,
                                indent: 16,
                                endIndent: 16,
                                color: isDark
                                    ? Colors.grey[700]
                                    : Colors.grey[300],
                              ),
                              itemBuilder: (context, index) {
                                final entry = uniqueVariants.values.elementAt(
                                  index,
                                );
                                final variant = entry.keys.first;
                                final attributes = entry.values.first;
                                return _buildVariantListItem(
                                  variant: variant,
                                  dialogContext: dialogContext,
                                  template: template,
                                  attributes: attributes,
                                  selectedAttributes: selectedAttributes,
                                  isDark: isDark,
                                );
                              },
                            );
                          },
                        ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVariantListItem({
    required Product variant,
    required BuildContext dialogContext,
    required Map<String, dynamic> template,
    required List<Map<String, String>> attributes,
    required Map<String, String>? selectedAttributes,
    bool isDark = false,
  }) {
    final imageUrl = variant.imageUrl ?? template['imageUrl'] as String?;
    Uint8List? imageBytes;
    if (imageUrl != null &&
        imageUrl.isNotEmpty &&
        !imageUrl.startsWith('http')) {
      try {
        final base64String = imageUrl.contains(',')
            ? imageUrl.split(',')[1]
            : imageUrl;
        if (RegExp(r'^[a-zA-Z0-9+/]*={0,2}$').hasMatch(base64String)) {
          imageBytes = base64Decode(base64String);
        }
      } catch (e) {}
    }

    return ProductListTile(
      id: variant.id.toString(),
      name: variant.name.split(' [').first,
      defaultCode: variant.defaultCode ?? 'N/A',
      listPrice: variant.listPrice,
      currencyId: variant.currencyId,
      category: template['category']?.toString(),
      qtyAvailable: variant.qtyAvailable,
      imageUrl: variant.imageUrl ?? template['imageUrl'] as String?,
      imageBytes: imageBytes,
      variantCount: 1,
      isDark: isDark,
      imageCache: _base64ImageCache,
      attributes: attributes.isNotEmpty ? attributes : null,
      actionButtons: null,
      onTap: () {
        Navigator.of(dialogContext).pop();
        _navigateToDetails(variant);
      },
      popupMenu: attributes.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Tooltip(
                message: attributes
                    .map(
                      (attr) =>
                          '${attr['attribute_name']}: ${attr['value_name']}',
                    )
                    .join('\n'),
                child: Icon(
                  HugeIcons.strokeRoundedTags,
                  size: 18,
                  color: isDark ? Colors.grey[300] : Colors.deepPurple,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildLoadingMoreIndicator() {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  void _updateProductTemplates() {
    if (!mounted) return;

    final productProvider = context.read<ProductProvider>();
    final products = productProvider.products;

    if (products.isEmpty) {
      if (mounted) {
        setState(() {
          _filteredProductTemplates = [];
        });
      }
      return;
    }

    final templateMap = <String, Map<String, dynamic>>{};

    for (var product in products) {
      final templateId = product.id;
      final templateName = product.name;

      templateMap[templateId] = {
        'id': templateId,
        'name': templateName,
        'defaultCode': product.defaultCode.isNotEmpty
            ? product.defaultCode
            : 'N/A',
        'listPrice': product.listPrice,
        'qtyAvailable': product.qtyAvailable,
        'imageUrl': product.imageUrl,
        'category': product.category ?? 'Uncategorized',
        'attributes': product.attributes ?? [],
        'variants': [product],
        'variantCount': product.variantCount > 1 ? product.variantCount : 1,
        'currencyId': product.currencyId,
        'productVariantIds': product.productVariantIds,
        'isLoading': false,
        'lastUpdated': DateTime.now(),
      };
    }

    if (mounted) {
      final productProvider = context.read<ProductProvider>();
      final groupKey = productProvider.selectedGroupBy;

      String computeGroup(Map<String, dynamic> tmpl) {
        switch (groupKey) {
          case 'categ_id':
            return (tmpl['category'] as String?)?.trim().isNotEmpty == true
                ? (tmpl['category'] as String)
                : 'Uncategorized';
          case 'uom_id':
            final variants = (tmpl['variants'] as List).cast<Product>();
            String? uom;
            if (variants.isNotEmpty) {
              final v = variants.first;
              final u = v.uomId;
              if (u is List && u.length >= 2 && u[1] is String) {
                uom = u[1] as String;
              } else if (u is String) {
                uom = u;
              }
            }
            return (uom != null && uom.trim().isNotEmpty) ? uom : 'Unknown UoM';
          case 'active':
            final variants = (tmpl['variants'] as List).cast<Product>();
            final anyActive = variants.any((v) => (v.active ?? true));
            return anyActive ? 'Active' : 'Inactive';
          case 'list_price':
            final price = (tmpl['listPrice'] as num?)?.toDouble() ?? 0.0;
            if (price < 50) return '< 50';
            if (price < 100) return '50 - 99';
            if (price < 200) return '100 - 199';
            if (price < 500) return '200 - 499';
            if (price < 1000) return '500 - 999';
            return '≥ 1000';
          case 'create_date':
            final variants = (tmpl['variants'] as List).cast<Product>();
            DateTime? minDate;
            for (final v in variants) {
              if (v.creationDate != null) {
                minDate = minDate == null
                    ? v.creationDate
                    : (v.creationDate!.isBefore(minDate)
                          ? v.creationDate
                          : minDate);
              }
            }
            if (minDate == null) return 'Unknown Date';
            return DateFormat(
              'yyyy MMM',
            ).format(DateTime(minDate.year, minDate.month));
          case 'write_date':
            final variants = (tmpl['variants'] as List).cast<Product>();
            DateTime? maxDate;
            for (final v in variants) {
              if (v.writeDate != null) {
                maxDate = maxDate == null
                    ? v.writeDate
                    : (v.writeDate!.isAfter(maxDate) ? v.writeDate : maxDate);
              }
            }
            if (maxDate == null) return 'Unknown Date';
            return DateFormat(
              'yyyy MMM',
            ).format(DateTime(maxDate.year, maxDate.month));
          default:
            return 'All Products';
        }
      }

      for (final tmpl in templateMap.values) {
        tmpl['__group'] = computeGroup(tmpl);
      }

      if (templateMap.length != products.length) {}

      setState(() {
        final list = templateMap.values.toList();

        list.sort((a, b) {
          if (groupKey != null) {
            final ga = (a['__group'] as String?) ?? '';
            final gb = (b['__group'] as String?) ?? '';
            if (groupKey == 'create_date' || groupKey == 'write_date') {
              DateTime? da;
              DateTime? db;
              try {
                da = ga == 'Unknown Date'
                    ? null
                    : DateFormat('yyyy MMM').parse(ga);
              } catch (_) {}
              try {
                db = gb == 'Unknown Date'
                    ? null
                    : DateFormat('yyyy MMM').parse(gb);
              } catch (_) {}
              if (da != null && db != null) {
                final cmpDate = db.compareTo(da);
                if (cmpDate != 0) return cmpDate;
              } else if (da != null) {
                return -1;
              } else if (db != null) {
                return 1;
              }
            } else {
              final cmp = ga.compareTo(gb);
              if (cmp != 0) return cmp;
            }
          }
          return (a['name'] as String).compareTo(b['name'] as String);
        });
        _filteredProductTemplates = list;
      });
    }
  }

  Future<void> _fetchGroupSummary() async {
    final productProvider = context.read<ProductProvider>();
    final groupByField = productProvider.selectedGroupBy;

    if (groupByField == null) {
      return;
    }

    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        return;
      }

      List<dynamic> domain = [
        ['sale_ok', '=', true],
      ];

      if (_showServicesOnly) domain.add(['type', '=', 'service']);
      if (_showConsumablesOnly) domain.add(['type', '=', 'consu']);
      if (_showStorableOnly) domain.add(['type', '=', 'product']);
      if (_showAvailableOnly) domain.add(['qty_available', '>', 0]);

      if (_searchController.text.trim().isNotEmpty) {
        final searchQuery = _searchController.text.trim();
        domain.add('|');
        domain.add('|');
        domain.add(['name', 'ilike', searchQuery]);
        domain.add(['default_code', 'ilike', searchQuery]);
        domain.add(['barcode', 'ilike', searchQuery]);
      }

      final result = await client.callKw({
        'model': 'product.template',
        'method': 'read_group',
        'args': [domain],
        'kwargs': {
          'fields': ['id'],
          'groupby': [groupByField],
          'lazy': false,
        },
      });

      if (result is List) {
        _groupSummary.clear();
        int totalCountFromGroups = 0;

        for (final group in result) {
          if (group is Map) {
            final groupKey = _getGroupKeyFromReadGroup(group, groupByField);
            final count = (group['__count'] ?? 0) as int;
            _groupSummary[groupKey] = count;
            totalCountFromGroups += count;
          }
        }

        if (mounted) {
          setState(() {});
        } else {}
      } else {}
    } catch (e) {}
  }

  String _getGroupKeyFromReadGroup(
    Map<dynamic, dynamic> group,
    String groupByField,
  ) {
    try {
      final value = group[groupByField];

      if (groupByField == 'categ_id') {
        if (value is List && value.length >= 2) {
          return value[1].toString();
        }
        return 'Uncategorized';
      } else if (groupByField == 'uom_id') {
        if (value is List && value.length >= 2) {
          return value[1].toString();
        }
        return 'Unknown UoM';
      } else if (groupByField == 'active') {
        return value == true ? 'Active' : 'Inactive';
      } else if (groupByField == 'list_price' ||
          groupByField == 'standard_price') {
        final price = (value is num) ? value.toDouble() : 0.0;
        if (price < 50) return '< 50';
        if (price < 100) return '50 - 99';
        if (price < 200) return '100 - 199';
        if (price < 500) return '200 - 499';
        if (price < 1000) return '500 - 999';
        return '≥ 1000';
      } else if (groupByField == 'create_date' ||
          groupByField == 'write_date') {
        if (value != null && value.toString().isNotEmpty) {
          try {
            final date = DateTime.parse(value.toString());
            return DateFormat(
              'yyyy MMM',
            ).format(DateTime(date.year, date.month));
          } catch (e) {
            return 'Unknown Date';
          }
        }
        return 'Unknown Date';
      }

      return value?.toString() ?? 'Unknown';
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<void> loadGroupProducts(String groupKey) async {
    final productProvider = context.read<ProductProvider>();
    final groupByField = productProvider.selectedGroupBy;

    if (groupByField == null) return;

    if (_groupLoading[groupKey] == true) {
      return;
    }

    if (_loadedGroups.containsKey(groupKey) &&
        _groupLoadedCounts[groupKey] != null) {
      if (_groupHasMore[groupKey] != true) {
        return;
      }
    }

    setState(() {
      _groupLoading[groupKey] = true;
    });

    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        setState(() {
          _groupLoading[groupKey] = false;
        });
        return;
      }

      List<dynamic> domain = [
        ['sale_ok', '=', true],
      ];

      if (_showServicesOnly) domain.add(['type', '=', 'service']);
      if (_showConsumablesOnly) domain.add(['type', '=', 'consu']);
      if (_showStorableOnly) domain.add(['type', '=', 'product']);
      if (_showAvailableOnly) domain.add(['qty_available', '>', 0]);

      if (_searchController.text.trim().isNotEmpty) {
        final searchQuery = _searchController.text.trim();
        domain.add('|');
        domain.add('|');
        domain.add(['name', 'ilike', searchQuery]);
        domain.add(['default_code', 'ilike', searchQuery]);
        domain.add(['barcode', 'ilike', searchQuery]);
      }

      final groupDomain = _buildGroupDomain(groupKey, groupByField);
      domain.addAll(groupDomain);

      final alreadyLoadedCount = _loadedGroups[groupKey]?.length ?? 0;
      final limit = 30;

      List<dynamic> variantDomain = [];

      for (var condition in domain) {
        if (condition is List && condition.isNotEmpty) {
          final field = condition[0];

          if (field == 'product_variant_count') continue;
          variantDomain.add(condition);
        } else {
          variantDomain.add(condition);
        }
      }

      if (!variantDomain.any(
        (d) => d is List && d.isNotEmpty && d[0] == 'sale_ok',
      )) {
        variantDomain.add(['sale_ok', '=', true]);
      }

      final result =
          await FieldValidationService.executeWithFieldValidation<
            List<dynamic>
          >(
            model: 'product.product',
            apiCall: (fields) async {
              return await client
                  .callKw({
                    'model': 'product.product',
                    'method': 'search_read',
                    'args': [variantDomain],
                    'kwargs': {
                      'fields': fields,
                      'order': 'name asc, id asc',
                      'limit': limit,
                      'offset': alreadyLoadedCount,
                    },
                  })
                  .timeout(
                    Duration(seconds: 30),
                    onTimeout: () {
                      throw TimeoutException('Product load timed out');
                    },
                  );
            },
            initialFields: [
              'id',
              'name',
              'default_code',
              'list_price',
              'product_variant_count',
              'categ_id',
              'image_1920',
              'qty_available',
              'barcode',
              'product_tmpl_id',
              'currency_id',
              'active',
              'product_template_attribute_value_ids',
              'taxes_id',
              'uom_id',
              'type',
              'write_date',
              'create_date',
            ],
          );

      final products = result
          .whereType<Map<String, dynamic>>()
          .map((json) {
            try {
              final product = Product.fromJson(json);
              return product;
            } catch (e) {
              return null;
            }
          })
          .where((p) => p != null)
          .cast<Product>()
          .toList();

      if (_loadedGroups.containsKey(groupKey)) {
        final existingIds = _loadedGroups[groupKey]!.map((p) => p.id).toSet();
        final newProducts = products
            .where((p) => !existingIds.contains(p.id))
            .toList();
        _loadedGroups[groupKey]!.addAll(newProducts);

        for (int i = 0; i < _loadedGroups[groupKey]!.length && i < 5; i++) {}
      } else {
        _loadedGroups[groupKey] = products;

        for (int i = 0; i < products.length && i < 5; i++) {}
      }

      _groupLoadedCounts[groupKey] = _loadedGroups[groupKey]!.length;
      final totalCount = _groupSummary[groupKey] ?? 0;

      _groupHasMore[groupKey] =
          products.length >= limit &&
          _groupLoadedCounts[groupKey]! < totalCount;

      if (mounted) {
        setState(() {
          _groupLoading[groupKey] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _groupLoading[groupKey] = false;

          _groupHasMore[groupKey] = false;
        });

        String errorMessage = 'Failed to load products';
        if (e.toString().contains('timeout')) {
          errorMessage = 'Request timed out. Please try again.';
        } else if (e.toString().contains('not found')) {
          errorMessage = 'Products not found for this group';
        } else if (e.toString().contains('Invalid field')) {
          errorMessage = 'Some product fields are not available';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                setState(() {
                  _loadedGroups.remove(groupKey);
                  _groupLoadedCounts.remove(groupKey);
                  _groupLoading.remove(groupKey);
                  _groupHasMore.remove(groupKey);
                });
                loadGroupProducts(groupKey);
              },
            ),
          ),
        );
      }
    }
  }

  List<dynamic> _buildGroupDomain(String groupKey, String groupByField) {
    try {
      switch (groupByField) {
        case 'categ_id':
          if (groupKey == 'Uncategorized') {
            return [
              ['categ_id', '=', false],
            ];
          }

          final leafCategory = groupKey.split(' / ').last.trim();

          return [
            ['categ_id.name', 'ilike', leafCategory],
          ];
        case 'uom_id':
          if (groupKey == 'Unknown UoM') {
            return [
              ['uom_id', '=', false],
            ];
          }

          return [
            ['uom_id.name', '=', groupKey],
          ];
        case 'active':
          return [
            ['active', '=', groupKey == 'Active'],
          ];
        case 'list_price':
        case 'standard_price':
          if (groupKey == '< 50') {
            return [
              [groupByField, '<', 50],
            ];
          } else if (groupKey == '50 - 99') {
            return [
              [groupByField, '>=', 50],
              [groupByField, '<', 100],
            ];
          } else if (groupKey == '100 - 199') {
            return [
              [groupByField, '>=', 100],
              [groupByField, '<', 200],
            ];
          } else if (groupKey == '200 - 499') {
            return [
              [groupByField, '>=', 200],
              [groupByField, '<', 500],
            ];
          } else if (groupKey == '500 - 999') {
            return [
              [groupByField, '>=', 500],
              [groupByField, '<', 1000],
            ];
          } else if (groupKey == '≥ 1000') {
            return [
              [groupByField, '>=', 1000],
            ];
          }
          return [];
        case 'create_date':
        case 'write_date':
          if (groupKey == 'Unknown Date') {
            return [
              [groupByField, '=', false],
            ];
          }
          try {
            final dateFormat = DateFormat('yyyy MMM');
            final parsedDate = dateFormat.parse(groupKey);
            final startDate = DateTime(parsedDate.year, parsedDate.month, 1);
            final endDate = DateTime(
              parsedDate.year,
              parsedDate.month + 1,
              0,
              23,
              59,
              59,
            );
            return [
              [
                groupByField,
                '>=',
                DateFormat('yyyy-MM-dd HH:mm:ss').format(startDate),
              ],
              [
                groupByField,
                '<=',
                DateFormat('yyyy-MM-dd HH:mm:ss').format(endDate),
              ],
            ];
          } catch (e) {}
          return [];
        default:
          if (groupKey == 'Unknown') {
            return [
              [groupByField, '=', false],
            ];
          }
          return [
            [groupByField, '=', groupKey],
          ];
      }
    } catch (e) {
      return [];
    }
  }

  Widget _buildAllProductsFetched(int count) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final textColor = isDark
        ? (Colors.grey[400] ?? const Color(0xFFBDBDBD))
        : (Colors.grey[600] ?? const Color(0xFF757575));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 16, top: 8),
      child: Center(
        child: Text(
          'All products loaded ($count total)',
          style: TextStyle(
            color: textColor,
            fontSize: 14,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Future<void> _refreshProducts() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _hasLoaded = false;
      _isInitialLoad = true;
    });

    try {
      final productProvider = context.read<ProductProvider>();

      setState(() {
        _currentPage = 0;
        _hasMoreData = true;
        _cachedProducts.clear();
        _lastFetchTime = null;
        _filteredProductTemplates.clear();
      });

      await _loadProducts(isLoadMore: false);

      setState(() {
        _hasMoreData = productProvider.hasMoreData;
        _currentPage = productProvider.currentPage;
        _totalProducts = productProvider.totalProducts;
      });

      _showSuccessSnackBar('Products refreshed successfully');
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(
          'Failed to refresh products: ${_getErrorMessage(e)}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasLoaded = true;
          _isInitialLoad = false;
        });
      }
    }
  }

  String _getErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();
    if (errorString.contains('socketexception') ||
        errorString.contains('connection refused') ||
        errorString.contains('connection timeout') ||
        errorString.contains('host unreachable') ||
        errorString.contains('no route to host') ||
        errorString.contains('network is unreachable') ||
        errorString.contains('failed to connect') ||
        errorString.contains('connection failed') ||
        errorString.contains('server returned html instead of json') ||
        errorString.contains('server may be down') ||
        errorString.contains('url incorrect') ||
        errorString.contains('odoo server error') ||
        errorString.contains('unexpected response')) {
      return 'Server/Database Unreachable';
    } else if (errorString.contains('timeoutexception')) {
      return 'Request timed out';
    } else if (errorString.contains('formatexception')) {
      return 'Invalid data format';
    } else if (errorString.contains('unauthorized')) {
      return 'Session expired, please login again';
    } else if (errorString.contains('builtins.valueerror') ||
        errorString.contains('invalid field') ||
        errorString.contains('odooexception')) {
      return 'Server data issue - retrying with simplified view';
    } else if (errorString.contains('accesserror') ||
        errorString.contains('not allowed to access')) {
      return 'Permission denied - contact administrator';
    }
    return 'An unexpected error occurred';
  }

  bool _isServerUnreachableError(String error) {
    final errorString = error.toLowerCase();
    return errorString.contains('socketexception') ||
        errorString.contains('connection refused') ||
        errorString.contains('connection timeout') ||
        errorString.contains('host unreachable') ||
        errorString.contains('no route to host') ||
        errorString.contains('network is unreachable') ||
        errorString.contains('failed to connect') ||
        errorString.contains('connection failed') ||
        errorString.contains('server returned html instead of json') ||
        errorString.contains('server may be down') ||
        errorString.contains('url incorrect') ||
        errorString.contains('odoo server error') ||
        errorString.contains('unexpected response') ||
        errorString.contains('404') ||
        errorString.contains('not found') ||
        errorString.contains('500') ||
        errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('504');
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    CustomSnackbar.showError(context, message);
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;

    CustomSnackbar.showSuccess(context, message);
  }

  Widget _buildFullPageShimmer() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
      highlightColor: isDarkMode ? Colors.grey[600]! : Colors.grey[100]!,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: 10,
            ),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[800] : Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 16,
                ),
                child: Row(
                  children: [
                    Container(width: 20, height: 20, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(child: Container(height: 20, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: 8,
              itemBuilder: (context, index) => _buildProductCardShimmer(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCardShimmer() {
    return Card(
      color: Colors.white,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Shimmer.fromColors(
              baseColor: Colors.grey[300]!,
              highlightColor: Colors.grey[100]!,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: Container(
                      width: double.infinity,
                      height: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Shimmer.fromColors(
                        baseColor: Colors.grey[300]!,
                        highlightColor: Colors.grey[100]!,
                        child: Container(
                          width: 80,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Shimmer.fromColors(
                        baseColor: Colors.grey[300]!,
                        highlightColor: Colors.grey[100]!,
                        child: Container(
                          width: 60,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Shimmer.fromColors(
                        baseColor: Colors.grey[300]!,
                        highlightColor: Colors.grey[100]!,
                        child: Container(
                          width: 80,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Shimmer.fromColors(
                        baseColor: Colors.grey[300]!,
                        highlightColor: Colors.grey[100]!,
                        child: Container(
                          width: 60,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _requestMicrophonePermission({bool showRationale = true}) async {
    return await RuntimePermissionService.requestMicrophonePermission(
      context,
      showRationale: showRationale,
    );
  }

  Future<void> _listen() async {
    if (_isLoading || _isProcessingSpeech) return;

    try {
      if (!_isListening) {
        final hasPermission = await _requestMicrophonePermission(
          showRationale: true,
        );

        if (!hasPermission) {
          if (!mounted) return;
          _showPermissionDialog();
          return;
        }

        if (!_speech.isAvailable) {
          final isInitialized = await _speech.initialize(
            onStatus: _handleSpeechStatusUpdate,
            onError: _handleSpeechError,
          );

          if (!isInitialized) {
            throw Exception('Failed to initialize speech recognition');
          }
        }

        setState(() {
          _isListening = true;
          _speechStatus = 'initializing';
        });
        _showListeningDialog();
        _startListeningTimeout();

        await _speech.listen(
          onResult: (result) {
            if (!mounted) return;
            setState(() {
              _voiceInput = result.recognizedWords;
              _searchController.text = _voiceInput;
              _searchController.selection = TextSelection.fromPosition(
                TextPosition(offset: _searchController.text.length),
              );
            });

            _updateDialogCallback?.call();

            if (result.recognizedWords.isNotEmpty && result.finalResult) {
              HapticFeedback.lightImpact();
            }
          },
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.dictation,
        );
      } else {
        await _speech.stop();
        setState(() {
          _isListening = false;
          _isProcessingSpeech = false;
        });
        _dismissListeningDialog();
        _cancelListeningTimeout();
      }
    } catch (e) {
      if (!mounted) return;
      _handleSpeechError('Error during voice recognition: ${e.toString()}');
    }
  }

  void _handleSpeechStatusUpdate(String status) {
    if (!mounted) return;

    setState(() {
      _speechStatus = status;

      switch (status) {
        case 'listening':
          _isListening = true;
          _isProcessingSpeech = false;

          break;

        case 'done':
        case 'notListening':
          _isListening = false;
          _isProcessingSpeech = false;
          _dismissListeningDialog();
          _cancelListeningTimeout();
          if (_voiceInput.isNotEmpty) {
            _performVoiceSearch();
          }

          break;

        case 'processing':
          _isProcessingSpeech = true;
          break;

        default:
          _isListening = false;
          _isProcessingSpeech = false;
          break;
      }
    });
  }

  void _handleSpeechError(dynamic error) {
    if (!mounted) return;

    setState(() {
      _isListening = false;
      _isProcessingSpeech = false;
      _speechStatus = 'error';
    });

    _dismissListeningDialog();
    _cancelListeningTimeout();

    String errorMessage = 'An error occurred during voice recognition';

    if (error is String) {
      errorMessage = error;
    } else if (error is Exception) {
      errorMessage = error.toString();
    } else {
      errorMessage = error?.toString() ?? 'Unknown speech recognition error';
    }

    if (mounted) {
      CustomSnackbar.showError(context, errorMessage);
    }
  }

  void _showListeningDialog() {
    if (_isListeningDialogShown) return;
    _isListeningDialogShown = true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void updateDialogText() {
            setDialogState(() {});
          }

          _updateDialogCallback = updateDialogText;

          return AlertDialog(
            backgroundColor: isDark ? Colors.grey[900] : Colors.white,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                width: 1,
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    'Voice Search',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showVoiceSearchTips();
                  },
                  icon: Icon(
                    HugeIcons.strokeRoundedHelpCircle,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    size: 24,
                  ),
                  tooltip: 'Voice Search Tips',
                  style: IconButton.styleFrom(padding: const EdgeInsets.all(4)),
                ),
              ],
            ),
            content: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? Colors.white.withOpacity(.1)
                              : primaryColor.withOpacity(0.1),
                        ),
                      ),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? Colors.white.withOpacity(.2)
                              : primaryColor.withOpacity(0.2),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: LoadingAnimationWidget.staggeredDotsWave(
                          color: isDark ? Colors.white : primaryColor,
                          size: 48,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _isProcessingSpeech
                        ? 'Processing speech...'
                        : _speechStatus == 'listening'
                        ? 'Listening...'
                        : _speechStatus == 'initializing'
                        ? 'Starting microphone...'
                        : 'Ready to listen',
                    style: TextStyle(
                      color: isDark ? Colors.grey[300] : Colors.grey[800],
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(.1)
                          : _isProcessingSpeech
                          ? Colors.blue.withOpacity(0.1)
                          : _speechStatus == 'listening'
                          ? Colors.green.withOpacity(0.1)
                          : _speechStatus == 'initializing'
                          ? Colors.orange.withOpacity(0.1)
                          : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(.3)
                            : _isProcessingSpeech
                            ? Colors.blue.withOpacity(0.3)
                            : _speechStatus == 'listening'
                            ? Colors.green.withOpacity(0.3)
                            : _speechStatus == 'initializing'
                            ? Colors.orange.withOpacity(0.3)
                            : Colors.grey.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _isProcessingSpeech
                          ? 'Processing'
                          : _speechStatus == 'listening'
                          ? 'Active'
                          : _speechStatus == 'initializing'
                          ? 'Starting'
                          : 'Standby',
                      style: TextStyle(
                        color: isDark
                            ? Colors.white
                            : _isProcessingSpeech
                            ? Colors.blue
                            : _speechStatus == 'listening'
                            ? Colors.green
                            : _speechStatus == 'initializing'
                            ? Colors.orange
                            : Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[850] : Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Recognized Text:',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (_voiceInput.isNotEmpty)
                              Text(
                                '${_voiceInput.split(' ').length} words',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                  fontSize: 10,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(minHeight: 60),
                          child: Text(
                            _voiceInput.isEmpty
                                ? 'Start speaking clearly into your microphone...\n\nTry saying: "laptop", "phone", "shoes", etc.'
                                : _voiceInput,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ),
                        if (_voiceInput.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 14,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Tap "Search" to find products or continue speaking',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () {
                  setState(() => _isListening = false);
                  _speech.stop();
                  _updateDialogCallback = null;
                  _dismissListeningDialog();
                  _cancelListeningTimeout();
                },
                icon: Icon(
                  HugeIcons.strokeRoundedCancelCircleHalfDot,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  size: 20,
                ),
                label: Text(
                  'Cancel',
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              if (_voiceInput.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () {
                    _dismissListeningDialog();
                    _cancelListeningTimeout();
                    _performVoiceSearch();
                  },
                  icon: Icon(Icons.search, color: Colors.white, size: 20),
                  label: Text(
                    'Search',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 2,
                  ),
                ),
            ],
            actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          );
        },
      ),
    );
  }

  void _dismissListeningDialog() {
    if (_isListeningDialogShown) {
      setState(() {
        _isListening = false;
        _isProcessingSpeech = false;
      });
      Navigator.of(context, rootNavigator: true).pop();
      _isListeningDialogShown = false;
      _updateDialogCallback = null;
    }
  }

  void _startListeningTimeout() {
    _cancelListeningTimeout();
    _listeningTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (_isListening) {
        setState(() => _isListening = false);
        _speech.stop();
        _dismissListeningDialog();
        CustomSnackbar.showWarning(
          context,
          'Listening timed out after 15 seconds. Please try again.',
        );
      }
    });
  }

  void _cancelListeningTimeout() {
    _listeningTimeoutTimer?.cancel();
    _listeningTimeoutTimer = null;
  }

  void _showVoiceSearchTips() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              HugeIcons.strokeRoundedBulb,
              color: isDark
                  ? Colors.white
                  : Theme.of(context).colorScheme.primary,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              'Voice Search Tips',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTipItem(
              'Speak clearly and at a normal pace',
              HugeIcons.strokeRoundedVoice,
              isDark,
            ),
            _buildTipItem(
              'Use specific product names: "laptop", "phone", "shoes"',
              HugeIcons.strokeRoundedSearch01,
              isDark,
            ),
            _buildTipItem(
              'Try brand names: "Apple", "Samsung", "Nike"',
              HugeIcons.strokeRoundedBrandfetch,
              isDark,
            ),
            _buildTipItem(
              'Use categories: "electronics", "clothing", "books"',
              HugeIcons.strokeRoundedPackage,
              isDark,
            ),
            _buildTipItem(
              'Speak in a quiet environment for better accuracy',
              HugeIcons.strokeRoundedVolumeLow,
              isDark,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Got it!',
              style: TextStyle(
                color: isDark
                    ? Colors.white
                    : Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipItem(String text, IconData icon, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isDark ? Colors.grey[300] : Colors.grey[700],
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _performVoiceSearch() {
    if (_voiceInput.trim().isEmpty) {
      _showAllProducts();
      return;
    }

    CustomSnackbar.showSuccess(
      context,
      'Searching for: "${_voiceInput.trim()}"',
    );

    setState(() {
      _searchController.text = _voiceInput.trim();
    });

    setState(() {
      _currentPage = 0;
      _hasMoreData = true;
      _isLoading = true;
    });

    _loadProducts();
  }

  void _showAllProducts() {
    setState(() {
      _voiceInput = '';
      _searchController.clear();
    });

    setState(() {
      _currentPage = 0;
      _hasMoreData = true;
      _cachedProducts.clear();
      _lastFetchTime = null;
      _isLoading = true;
    });
    _loadProducts();
  }

  void _startListening() async {
    setState(() {
      _voiceInput = '';
      _searchController.clear();
    });
    if (!_isListening) {
      bool available = false;
      try {
        available = await _speech.initialize(
          onStatus: (val) {
            if (!mounted) return;
            setState(() {
              _speechStatus = val;
              if (val == 'done' || val == 'notListening') {
                _isListening = false;
                _isProcessingSpeech = false;
              } else if (val == 'listening') {
                _isListening = true;
                _isProcessingSpeech = false;
              } else if (val == 'processing') {
                _isProcessingSpeech = true;
              }
            });
            if (val == 'done' || val == 'notListening') {
              _dismissListeningDialog();
              _cancelListeningTimeout();
              if (_voiceInput.isNotEmpty) {
                _performVoiceSearch();
              }
            }
          },
          onError: (val) {
            if (!mounted) return;
            setState(() {
              _isListening = false;
              _isProcessingSpeech = false;
              _speechStatus = 'error';
            });
            _dismissListeningDialog();
            _cancelListeningTimeout();
            _handleSpeechError(val.errorMsg ?? val.toString());
          },
        );
      } catch (e) {
        available = false;
        _handleSpeechError(e.toString());
      }
      if (available) {
        setState(() => _isListening = true);
        _showListeningDialog();
        _startListeningTimeout();
        _speech.listen(
          onResult: (val) {
            if (!mounted) return;
            setState(() {
              _voiceInput = val.recognizedWords;
              _searchController.text = _voiceInput;
              _searchController.selection = TextSelection.fromPosition(
                TextPosition(offset: _searchController.text.length),
              );
            });
            _updateDialogCallback?.call();
            if (val.recognizedWords.isNotEmpty && val.finalResult) {
              HapticFeedback.lightImpact();
            }
          },
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          cancelOnError: false,
        );
      } else {
        setState(() => _isListening = false);
        _handleSpeechError(
          'Voice search is not available or permission denied.',
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
      _dismissListeningDialog();
      _cancelListeningTimeout();
    }
  }

  static final Map<String, List<Map<String, String>>> _attributeCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};

  Future<List<Map<String, String>>> _fetchVariantAttributes(
    OdooClient odooClient,
    List<int> attributeValueIds,
  ) async {
    if (attributeValueIds.isEmpty) return [];

    try {
      final cacheKey = attributeValueIds.join(',');
      final now = DateTime.now();
      if (_attributeCache.containsKey(cacheKey) &&
          _cacheTimestamps.containsKey(cacheKey) &&
          now.difference(_cacheTimestamps[cacheKey]!) < _cacheDuration) {
        return _attributeCache[cacheKey]!;
      }

      final attributeValueResult = await odooClient.callKw({
        'model': 'product.template.attribute.value',
        'method': 'read',
        'args': [attributeValueIds],
        'kwargs': {
          'fields': ['product_attribute_value_id', 'attribute_id'],
        },
      });

      if (attributeValueResult.isEmpty) return [];

      final valueIds = <int>[];
      final attributeIds = <int>[];
      final valueToAttributeMap = <int, int>{};

      for (var attrValue in attributeValueResult) {
        final valueId = attrValue['product_attribute_value_id'] is List
            ? attrValue['product_attribute_value_id'][0] as int
            : attrValue['product_attribute_value_id'] as int;
        final attributeId = attrValue['attribute_id'] is List
            ? attrValue['attribute_id'][0] as int
            : attrValue['attribute_id'] as int;
        valueIds.add(valueId);
        attributeIds.add(attributeId);
        valueToAttributeMap[valueId] = attributeId;
      }

      final valueData = await odooClient.callKw({
        'model': 'product.attribute.value',
        'method': 'read',
        'args': [valueIds],
        'kwargs': {
          'fields': ['name'],
        },
      });

      final attributeData = await odooClient.callKw({
        'model': 'product.attribute',
        'method': 'read',
        'args': [attributeIds.toSet().toList()],
        'kwargs': {
          'fields': ['name'],
        },
      });

      final valueMap = <int, String>{};
      for (var value in valueData) {
        valueMap[value['id'] as int] = value['name'] as String;
      }

      final attributeMap = <int, String>{};
      for (var attr in attributeData) {
        attributeMap[attr['id'] as int] = attr['name'] as String;
      }

      final attributes = <Map<String, String>>[];
      for (var attrValue in attributeValueResult) {
        final valueId = attrValue['product_attribute_value_id'] is List
            ? attrValue['product_attribute_value_id'][0] as int
            : attrValue['product_attribute_value_id'] as int;
        final attributeId = attrValue['attribute_id'] is List
            ? attrValue['attribute_id'][0] as int
            : attrValue['attribute_id'] as int;

        final valueName = valueMap[valueId];
        final attributeName = attributeMap[attributeId];

        if (valueName != null && attributeName != null) {
          attributes.add({
            'attribute_name': attributeName,
            'value_name': valueName,
          });
        }
      }

      _attributeCache[cacheKey] = attributes;
      _cacheTimestamps[cacheKey] = now;

      return attributes;
    } catch (e) {
      return [];
    }
  }

  Future<void> _scanBarcode() async {
    setState(() => _isScanning = true);
    try {
      final String? barcode = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => BarcodeScannerScreen()),
      );

      if (barcode != null && barcode.isNotEmpty) {
        setState(() {
          _searchController.text = barcode;
        });

        _performTextSearch(barcode);
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(context, 'Error scanning barcode: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  void _performTextSearch(String query) async {
    if (_searchController.text != query) {
      setState(() {
        _searchController.text = query;
      });
    }

    setState(() {
      _currentPage = 0;
      _hasMoreData = true;
      _cachedProducts.clear();
      _lastFetchTime = null;
      _isLoading = true;
      _filteredProductTemplates.clear();
    });
    await _loadProducts();

    if (mounted && _filteredProductTemplates.isEmpty) {
      CustomSnackbar.showWarning(
        context,
        'No product found with barcode: $query',
      );
    }
  }

  Widget _buildFilterIndicator(bool isDark, bool hasGroupBy) {
    final count =
        (_showServicesOnly ? 1 : 0) +
        (_showConsumablesOnly ? 1 : 0) +
        (_showStorableOnly ? 1 : 0) +
        (_showAvailableOnly ? 1 : 0);

    if (count == 0) {
      if (hasGroupBy) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'No filters applied',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white70 : Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white70 : Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count active',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.black : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupByPill(bool isDark, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white70 : Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedLayer,
            size: 14,
            color: isDark ? Colors.black : Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.black : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  bool _hasActiveFilters() {
    return _showServicesOnly ||
        _showConsumablesOnly ||
        _showStorableOnly ||
        _showAvailableOnly;
  }

  String _getGroupByDisplayName(String? groupBy) {
    if (groupBy == null) return '';

    const groupByOptions = {
      'categ_id': 'Category',
      'detailed_type': 'Product Type',
      'sale_ok': 'Can be Sold',
      'purchase_ok': 'Can be Purchased',
      'active': 'Status',
      'list_price': 'Sales Price',
      'standard_price': 'Cost Price',
      'company_id': 'Company',
      'uom_id': 'Unit of Measure',
      'create_date': 'Creation Date',
      'write_date': 'Last Modified',
      'responsible_id': 'Responsible Person',
    };

    return groupByOptions[groupBy] ?? groupBy;
  }

  bool _listEquals(List<String> list1, List<String> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }

  Widget _buildTopPaginationBar(ProductProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.only(right: 0, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  provider.getPaginationText(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          if (!provider.isGrouped) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: (provider.canGoToPreviousPage && !_isLoading)
                      ? goToPreviousPage
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8.0,
                      horizontal: 4,
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowLeft01,
                      size: 20,
                      color: (provider.canGoToPreviousPage && !_isLoading)
                          ? (isDark ? Colors.white : Colors.black87)
                          : (isDark ? Colors.grey[600]! : Colors.grey[400]!),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: (provider.canGoToNextPage && !_isLoading)
                      ? goToNextPage
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8.0,
                      horizontal: 4,
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowRight01,
                      size: 20,
                      color: (provider.canGoToNextPage && !_isLoading)
                          ? (isDark ? Colors.white : Colors.black87)
                          : (isDark ? Colors.grey[600]! : Colors.grey[400]!),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _navigateToDetails(Product product) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailsPage(product: product),
      ),
    );

    if (result == true || result == 'updated') {
      _loadProducts();
    }
  }

  @override
  void dispose() {
    _cancelListeningTimeout();
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    _listeningTimeoutTimer?.cancel();
    _connectivityService.removeListener(_onConnectivityChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchController.dispose();
      _scrollController.dispose();
    });

    super.dispose();
  }
}

class _FadeInMemoryImage extends StatefulWidget {
  final Uint8List bytes;

  const _FadeInMemoryImage({required this.bytes});

  @override
  State<_FadeInMemoryImage> createState() => _FadeInMemoryImageState();
}

class _FadeInMemoryImageState extends State<_FadeInMemoryImage> {
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _opacity = 1.0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeIn,
      child: Image.memory(
        widget.bytes,
        fit: BoxFit.cover,
        width: 60,
        height: 60,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(
            Icons.inventory_2_rounded,
            color: Colors.grey,
            size: 24,
          );
        },
      ),
    );
  }
}

class VariantsDialogShimmer extends StatelessWidget {
  const VariantsDialogShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      shrinkWrap: true,
      itemCount: 4,

      itemBuilder: (context, index) =>
          _buildVariantListItemShimmer(isDark: isDark),
    );
  }

  Widget _buildVariantListItemShimmer({required bool isDark}) {
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[600]! : Colors.grey[100]!;

    return Card(
      color: isDark ? Colors.grey[900] : Colors.white,
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Shimmer.fromColors(
              baseColor: baseColor,
              highlightColor: highlightColor,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!, width: 1),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Shimmer.fromColors(
                    baseColor: baseColor,
                    highlightColor: highlightColor,
                    child: Container(
                      width: double.infinity,
                      height: 15,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Shimmer.fromColors(
                    baseColor: baseColor,
                    highlightColor: highlightColor,
                    child: Container(
                      width: 150,
                      height: 12,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Shimmer.fromColors(
                        baseColor: baseColor,
                        highlightColor: highlightColor,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey[900]!
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          width: 80,
                          height: 16,
                        ),
                      ),
                      Shimmer.fromColors(
                        baseColor: baseColor,
                        highlightColor: highlightColor,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey[900]!
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          width: 100,
                          height: 16,
                        ),
                      ),
                      Shimmer.fromColors(
                        baseColor: baseColor,
                        highlightColor: highlightColor,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey[900]!
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          width: 80,
                          height: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
