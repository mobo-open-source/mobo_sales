import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/screens/products/create_product_screen.dart';
import 'package:mobo_sales/screens/stock_check/stock_check_screen.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import 'package:mobo_sales/providers/settings_provider.dart';
import 'package:mobo_sales/widgets/dashboard_charts.dart';
import 'package:mobo_sales/widgets/dashboard_quick_actions.dart';
import 'package:mobo_sales/widgets/responsive_layout.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import '../../models/contact.dart';
import '../../widgets/dashboard_shimmer.dart';
import '../../widgets/custom_snackbar.dart';
import '../../models/product.dart';
import '../../models/quote.dart';
import '../../providers/currency_provider.dart';
import '../../providers/last_opened_provider.dart';
import '../../home_scaffold.dart';
import '../../main.dart';
import '../customers/edit_customer_screen.dart';
import '../invoices/create_invoice_screen.dart';
import '../invoices/invoice_details_screen.dart';
import '../invoices/invoice_list_screen.dart';
import '../products/product_details_page.dart';
import '../quotations/create_quote_screen.dart';
import '../quotations/quotation_details_screen.dart';
import '../quotations/quotation_list_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import '../customers/customer_details_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import '../../services/session_service.dart';
import '../../utils/tap_prevention.dart';
import 'package:mobo_sales/widgets/circular_image_widget.dart';
import '../../services/odoo_session_manager.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  static void clearDashboardCache() {
    _DashboardScreenState._clearStaticCaches();
  }

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver, RouteAware {
  static const List<String> _quotationFields = [
    'id',
    'name',
    'partner_id',
    'date_order',
    'amount_total',
    'amount_untaxed',
    'amount_tax',
    'state',
    'currency_id',
    'note',
    'validity_date',
    'create_date',
    'write_date',
    'currency_rate',
    'order_line',
  ];

  String? userName;
  String? userAvatar;
  late final bool _barNavInProgress = false;
  String? userLogin;
  bool _initialLoadComplete = false;

  bool isLoadingDashboardAll = true;
  bool isLoadingCharts = true;

  DateTime? _loadingStart;
  static const Duration _minShimmerDisplay = Duration(milliseconds: 250);

  bool _isToggling = false;
  Timer? _debounceTimer;
  bool _isServerUnreachable = false;
  bool _isForceRefreshing = false;
  bool _isCheckingConnectivity = false;
  bool _handlingSessionChange = false;

  int? contactsCount;
  int? quotesCount;
  int? invoicesCount;
  int? productsCount;
  int? approvalsCount;
  int? documentsCount;

  double? monthlyRevenue;
  double? weeklyRevenue;
  double? conversionRate;
  double? averageDealSize;
  int? overdueInvoicesCount;
  int? expiredQuotesCount;
  int? todayTasksCount;
  List<Map<String, dynamic>> recentActivities = [];
  List<Map<String, dynamic>> topProducts = [];
  List<Map<String, dynamic>> continueWorkingItems = [];
  bool isLoadingContinueWorking = false;
  DateTime? _lastContinueWorkingFetch;
  double? outstandingReceivables;
  double? totalUntaxedInvoiceAmount;
  List<Map<String, dynamic>> _dailyRevenueData = [];

  bool hasInventoryModule = false;

  String? _dashboardErrorMessage;

  bool _isOffline = false;
  bool _hasSession = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  static final Map<String, Map<String, dynamic>> _accountCachedUserData = {};
  static final Map<String, Map<String, int?>> _accountCachedDashboardCounts =
      {};
  static final Map<String, Map<String, dynamic>> _accountCachedSalesMetrics =
      {};
  static final Map<String, DateTime> _lastCacheTimes = {};

  static String _getCurrentAccountKey() {
    final session = SessionService.instance.currentSession;
    if (session == null) return 'global';
    final cleanDb = session.database.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return '${cleanDb}_${session.userId}';
  }

  static const Duration _countsCacheDuration = Duration(minutes: 15);
  static const Duration _metricsCacheDuration = Duration(minutes: 30);
  static const Duration _backgroundRefreshInterval = Duration(minutes: 5);
  static const Duration _userDataCacheDuration = Duration(minutes: 30);

  static void _clearStaticCaches() {
    _accountCachedUserData.clear();
    _accountCachedDashboardCounts.clear();
    _accountCachedSalesMetrics.clear();
    _lastCacheTimes.clear();
  }

  bool _useAbbreviatedCurrency = true;

  SessionService? _sessionService;
  late final ScrollController _scrollController;
  bool _showScrollToTop = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(() {
      final shouldShow =
          _scrollController.hasClients && _scrollController.offset > 300;
      if (shouldShow != _showScrollToTop) {
        if (mounted) {
          setState(() {
            _showScrollToTop = shouldShow;
          });
        }
      }
    });
    _setupConnectivityListener();

    try {
      _sessionService = context.read<SessionService>();
      _sessionService?.addListener(_onSessionChanged);
    } catch (e) {}

    final sessionService = context.read<SessionService>();
    if (sessionService.isServerUnreachable) {
      _isServerUnreachable = true;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeUserDataFromSettings();
      _checkConnectivityAndSession();
    });
  }

  void _initializeUserDataFromSettings() {
    try {
      final settingsProvider = context.read<SettingsProvider>();
      final userProfile = settingsProvider.userProfile;
      if (userProfile != null) {
        final name = userProfile['name'];
        if (name != null && name.toString().isNotEmpty) {
          setState(() {
            userName = name.toString();
          });
        }

        final img = userProfile['image_1920'];
        if (img != null && img != false && img.toString().isNotEmpty) {
          setState(() {
            userAvatar = img.toString();
          });
        }
      }
    } catch (e) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  void _refreshContinueWorkingItems() {
    if (!mounted || isLoadingContinueWorking) return;

    final now = DateTime.now();
    final shouldRefresh =
        _lastContinueWorkingFetch == null ||
        now.difference(_lastContinueWorkingFetch!) >
            const Duration(minutes: 2) ||
        continueWorkingItems.isEmpty;

    if (shouldRefresh) {
      _fetchContinueWorkingItems();
    }
  }

  Future<void> _refreshUserDataWithRetry({int maxRetries = 2}) async {
    if (!mounted) return;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        await _fetchUserInfo(forceRefresh: true);

        break;
      } catch (e) {
        if (attempt == maxRetries) {
          _loadCachedUserDataOrDefaults();
        } else {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
    }
  }

  void _forceRefreshContinueWorkingItems() {
    if (mounted && !isLoadingContinueWorking) {
      _fetchContinueWorkingItems();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshContinueWorkingItems();
      });
    }
  }

  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (mounted) {
        setState(() {
          _isOffline = results.contains(ConnectivityResult.none);
        });
        if (!_isOffline) {
          _checkConnectivityAndSession();
        }
      }
    });
  }

  @override
  void dispose() {
    _sessionService?.removeListener(_onSessionChanged);

    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _debounceTimer?.cancel();

    try {
      _scrollController.dispose();
    } catch (e) {}

    try {
      routeObserver.unsubscribe(this);
    } catch (e) {}

    super.dispose();
  }

  @override
  void didPopNext() {
    _refreshUserDataWithRetry();

    if (!_isDataStale()) {
      _loadCachedDataIfNeeded();
      return;
    }

    _refreshHeaderIfNeeded();
    _refreshContinueWorkingItems();
  }

  @override
  void didPushNext() {}

  void _refreshHeaderIfNeeded() {
    if (!mounted) return;

    if (!_isDataStale() &&
        _accountCachedUserData.containsKey(_getCurrentAccountKey())) {
      userName = _accountCachedUserData[_getCurrentAccountKey()]?['userName'];
      userAvatar =
          _accountCachedUserData[_getCurrentAccountKey()]?['userAvatar'];
      userLogin = _accountCachedUserData[_getCurrentAccountKey()]?['userLogin'];
      _loadCachedData();
      return;
    }

    final hasName =
        (userName != null && userName!.trim().isNotEmpty && userName != 'User');
    final hasSession = _sessionService?.hasValidSession ?? true;

    if (_accountCachedUserData.containsKey(_getCurrentAccountKey()) &&
        !hasName) {
      _loadCachedUserData();
    }

    if (hasSession && !hasName) {
      _initializeUserDataFromSettings();

      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 150), () {
        if (mounted) {
          _refreshUserDataWithRetry();
        }
      });
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning';
    } else if (hour < 17) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
    }
  }

  String _buildGreetingText() {
    String? nameToUse = userName;

    if (nameToUse == null || nameToUse.trim().isEmpty || nameToUse == 'User') {
      try {
        final settingsProvider = context.read<SettingsProvider>();
        final profileName = settingsProvider.userProfile?['name'];
        if (profileName != null && profileName.toString().isNotEmpty) {
          nameToUse = profileName.toString();
        }
      } catch (_) {}
    }
    if (nameToUse == null || nameToUse.trim().isEmpty) {
      nameToUse = 'User';
    }

    final firstName = nameToUse.split(' ')[0];
    return '${_getGreeting()} $firstName!';
  }

  bool _isDataStale() {
    final key = _getCurrentAccountKey();
    final lastTime = _lastCacheTimes[key];
    if (lastTime == null) return true;
    return DateTime.now().difference(lastTime) > _backgroundRefreshInterval;
  }

  bool _isUserDataStale() {
    final key = 'userData_${_getCurrentAccountKey()}';
    final lastTime = _lastCacheTimes[key];
    if (lastTime == null) return true;
    return DateTime.now().difference(lastTime) > _userDataCacheDuration;
  }

  bool _areCountsStale() {
    final key = 'counts_${_getCurrentAccountKey()}';
    final lastTime = _lastCacheTimes[key];
    if (lastTime == null) return true;
    return DateTime.now().difference(lastTime) > _countsCacheDuration;
  }

  bool _areMetricsStale() {
    final key = 'metrics_${_getCurrentAccountKey()}';
    final lastTime = _lastCacheTimes[key];
    if (lastTime == null) return true;
    return DateTime.now().difference(lastTime) > _metricsCacheDuration;
  }

  Future<void> _checkConnectivityAndSession() async {
    if (_isCheckingConnectivity) {
      return;
    }

    if (_isServerUnreachable) {
      if (mounted) {
        setState(() {
          isLoadingDashboardAll = false;
          isLoadingCharts = false;
        });
      }
      return;
    }

    _isCheckingConnectivity = true;

    try {
      final key = _getCurrentAccountKey();
      final hasUserData =
          _accountCachedUserData.containsKey(key) && !_isUserDataStale();
      final hasCounts =
          _accountCachedDashboardCounts.containsKey(key) && !_areCountsStale();
      final hasMetrics =
          _accountCachedSalesMetrics.containsKey(key) && !_areMetricsStale();

      final hasUIData =
          contactsCount != null &&
          quotesCount != null &&
          invoicesCount != null &&
          productsCount != null;

      if (hasUserData && hasCounts && hasMetrics && hasUIData) {
        if (mounted) {
          setState(() {
            _initialLoadComplete = true;
            isLoadingDashboardAll = false;
            isLoadingCharts = false;
          });
        }
        return;
      }

      if (!hasUserData &&
          _accountCachedUserData.containsKey(_getCurrentAccountKey())) {
        _loadCachedUserData();
      }

      if ((hasCounts || hasMetrics) && !hasUIData) {
        _loadCachedDataIfNeeded();
      }

      final connectivityResult = await Connectivity().checkConnectivity();
      final offline = connectivityResult.contains(ConnectivityResult.none);

      if (!mounted) return;

      SessionService? sessionService;
      bool hasSession = false;

      try {
        sessionService = context.read<SessionService>();
        hasSession = sessionService.hasValidSession;
      } catch (e) {
        return;
      }

      if (mounted) {
        setState(() {
          _isOffline = offline;
          _hasSession = hasSession;

          if ((offline || !hasSession) && !(hasCounts || hasMetrics)) {
            isLoadingDashboardAll = false;
            _dashboardErrorMessage = offline
                ? 'No internet connection. Please check your network and try again.'
                : 'Session expired. Please log in again.';
          } else if (!offline && hasSession) {
            if (!hasUserData || !hasCounts || !hasMetrics) {
              isLoadingDashboardAll = !hasCounts;
              isLoadingCharts = !hasMetrics;
              if (!hasCounts || !hasMetrics) {
                _loadingStart = DateTime.now();
              }
            }
            _dashboardErrorMessage = null;
          }
        });
      }

      if (!offline && hasSession) {
        final fetchTasks = <Future>[];

        if (!hasUserData) {
          fetchTasks.add(_refreshUserDataWithRetry());
        }

        if (!hasCounts) {
          fetchTasks.add(_fetchDashboardCounts(forceRefresh: true));
        }

        if (!hasMetrics) {
          fetchTasks.add(_fetchSalesMetrics(forceRefresh: true));
        }

        try {
          if (fetchTasks.isNotEmpty) {
            await Future.wait(fetchTasks);
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _dashboardErrorMessage =
                  'Failed to load dashboard data. Please try again.';
            });
          }
        } finally {
          if (mounted) {
            setState(() {
              isLoadingDashboardAll = false;
              isLoadingCharts = false;
              _initialLoadComplete = true;
            });
          }
        }
      }
    } finally {
      _isCheckingConnectivity = false;
    }
  }

  void _cacheDashboardCounts() {
    final key = _getCurrentAccountKey();
    _accountCachedDashboardCounts[key] = {
      'contactsCount': contactsCount,
      'quotesCount': quotesCount,
      'invoicesCount': invoicesCount,
      'productsCount': productsCount,
      'approvalsCount': approvalsCount,
      'documentsCount': documentsCount,
      'hasInventoryModule': hasInventoryModule ? 1 : 0,
    };
    _lastCacheTimes['counts_$key'] = DateTime.now();
  }

  void _loadCachedCounts() {
    final key = _getCurrentAccountKey();
    final cached = _accountCachedDashboardCounts[key];
    if (cached != null && mounted) {
      setState(() {
        contactsCount = cached['contactsCount'];
        quotesCount = cached['quotesCount'];
        invoicesCount = cached['invoicesCount'];
        productsCount = cached['productsCount'];
        approvalsCount = cached['approvalsCount'];
        documentsCount = cached['documentsCount'];
        hasInventoryModule = cached['hasInventoryModule'] == 1;
      });
    }
  }

  void _loadCachedSalesMetrics() {
    final key = 'metrics_${_getCurrentAccountKey()}';
    final cached = _accountCachedSalesMetrics[key];
    if (cached != null && mounted) {
      setState(() {
        monthlyRevenue = cached['monthlyRevenue'];
        weeklyRevenue = cached['weeklyRevenue'];
        conversionRate = cached['conversionRate'];
        averageDealSize = cached['averageDealSize'];
        overdueInvoicesCount = cached['overdueInvoicesCount'];
        expiredQuotesCount = cached['expiredQuotesCount'];
        todayTasksCount = cached['todayTasksCount'];
        outstandingReceivables = cached['outstandingReceivables'];
        totalUntaxedInvoiceAmount = cached['totalUntaxedInvoiceAmount'];

        final cachedTopProducts = cached['topProducts'];
        if (cachedTopProducts is List) {
          topProducts = cachedTopProducts
              .cast<Map<String, dynamic>>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        } else {
          topProducts = [];
        }

        final cachedDailyRevenue = cached['dailyRevenueData'];
        if (cachedDailyRevenue is List) {
          _dailyRevenueData = cachedDailyRevenue
              .cast<Map<String, dynamic>>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        } else {
          _dailyRevenueData = [];
        }

        isLoadingDashboardAll = false;
        isLoadingCharts = false;
      });
    }
  }

  void _loadCachedData() {
    _loadCachedUserData();
    _loadCachedCounts();
    _loadCachedSalesMetrics();
  }

  void _loadCachedDataIfNeeded() {
    if (!mounted) return;

    final key = _getCurrentAccountKey();
    final hasCache =
        _accountCachedUserData.containsKey(key) &&
        _accountCachedDashboardCounts.containsKey(key) &&
        _accountCachedSalesMetrics.containsKey(key);

    final stateIsEmpty =
        contactsCount == null ||
        quotesCount == null ||
        invoicesCount == null ||
        productsCount == null;

    if (hasCache && stateIsEmpty) {
      _loadCachedData();
    }
  }

  void _cacheSalesMetrics() {
    final key = _getCurrentAccountKey();
    _accountCachedSalesMetrics[key] = {
      'monthlyRevenue': monthlyRevenue,
      'weeklyRevenue': weeklyRevenue,
      'conversionRate': conversionRate,
      'averageDealSize': averageDealSize,
      'overdueInvoicesCount': overdueInvoicesCount,
      'expiredQuotesCount': expiredQuotesCount,
      'todayTasksCount': todayTasksCount,
      'outstandingReceivables': outstandingReceivables,
      'totalUntaxedInvoiceAmount': totalUntaxedInvoiceAmount,
      'topProducts': topProducts
          .map((p) => Map<String, dynamic>.from(p))
          .toList(),
      'dailyRevenueData': _dailyRevenueData
          .map((d) => Map<String, dynamic>.from(d))
          .toList(),
    };
    final now = DateTime.now();
    _lastCacheTimes['metrics_$key'] = now;
    _lastCacheTimes[key] = now;
  }

  double _parseAmount(dynamic amount) {
    if (amount == null || amount == false) return 0.0;

    if (amount is String) {
      String cleanAmount = amount.replaceAll(RegExp(r'[^\d.-]'), '');
      return double.tryParse(cleanAmount) ?? 0.0;
    } else if (amount is num) {
      return amount.toDouble();
    }

    return 0.0;
  }

  num? _safeToNum(dynamic value) {
    if (value == null || value == false) return null;
    if (value is num) return value;
    if (value is String) {
      return num.tryParse(value);
    }
    return null;
  }

  Future<void> _fetchSalesMetrics({bool forceRefresh = false}) async {
    if (!mounted ||
        (!forceRefresh &&
            !_areMetricsStale() &&
            _accountCachedSalesMetrics.containsKey(_getCurrentAccountKey()))) {
      return;
    }

    SessionService? sessionService;
    try {
      sessionService = context.read<SessionService>();
    } catch (e) {
      return;
    }

    if (!sessionService.hasValidSession) {
      return;
    }

    if (_isServerUnreachable) {
      _isServerUnreachable = false;
      sessionService.clearServerUnreachableState();
    }

    try {
      final now = DateTime.now();

      final monthStart = DateTime(now.year, now.month, 1);
      final monthEnd = DateTime(
        now.year,
        now.month + 1,
        1,
      ).subtract(Duration(days: 1));

      final last7DaysStart = now.subtract(Duration(days: 6));
      final last7DaysEnd = now;

      final currentWeekday = now.weekday;
      final weekStart = now.subtract(Duration(days: currentWeekday - 1));
      final weekEnd = weekStart.add(Duration(days: 6));

      final startOfYear = DateTime(now.year, 1, 1);

      String formatDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final monthStartStr = formatDate(monthStart);
      final monthEndStr = formatDate(monthEnd);
      final weekStartStr = formatDate(weekStart);
      final weekEndStr = formatDate(weekEnd);
      final last7DaysStartStr = formatDate(last7DaysStart);
      final last7DaysEndStr = formatDate(last7DaysEnd);

      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final results = await Future.wait<dynamic>([
        _safeAggregateSum(
          model: 'sale.order',
          domain: [
            [
              'state',
              'in',
              ['sale', 'done'],
            ],
            ['date_order', '>=', monthStartStr],
            ['date_order', '<=', monthEndStr],
          ],
          sumField: 'amount_total',
        ),

        _safeAggregateSum(
          model: 'sale.order',
          domain: [
            [
              'state',
              'in',
              ['sale', 'done'],
            ],
            ['date_order', '>=', weekStartStr],
            ['date_order', '<=', weekEndStr],

            ['date_order', '>=', monthStartStr],
            ['date_order', '<=', monthEndStr],
          ],
          sumField: 'amount_total',
        ),

        OdooSessionManager.callKwWithCompany({
          'model': 'account.move',
          'method': 'search_count',
          'args': [
            [
              ['move_type', '=', 'out_invoice'],
              ['state', '=', 'posted'],
              [
                'payment_state',
                'in',
                ['not_paid', 'partial'],
              ],
              ['invoice_date_due', '<', todayStr],
            ],
          ],
          'kwargs': {},
        }),

        _safeAggregateSum(
          model: 'account.move',
          domain: [
            ['move_type', '=', 'out_invoice'],
            ['state', '=', 'posted'],
            [
              'payment_state',
              'in',
              ['not_paid', 'partial'],
            ],
          ],
          sumField: 'amount_residual',
        ),

        _safeAggregateSum(
          model: 'account.move',
          domain: [
            ['move_type', '=', 'out_invoice'],
            ['state', '=', 'posted'],
          ],
          sumField: 'amount_untaxed',
        ),

        _safeTopProducts(
          domain: [
            [
              'order_id.state',
              'in',
              ['sale', 'done'],
            ],

            ['product_id', '!=', false],

            [
              'product_id.type',
              'in',
              ['product', 'consu'],
            ],

            ['product_id.active', '=', true],
            ['product_id.sale_ok', '=', true],
          ],
        ),

        _fetchDailyRevenue(last7DaysStartStr, last7DaysEndStr, last7DaysStart),
      ]);

      final monthlyAgg = (results[0] is Map)
          ? results[0] as Map<String, dynamic>
          : const <String, dynamic>{};
      final weeklyAgg = (results[1] is Map)
          ? results[1] as Map<String, dynamic>
          : const <String, dynamic>{};
      final overdueCount = results[2] as int;
      final outstandingAgg = (results[3] is Map)
          ? results[3] as Map<String, dynamic>
          : const <String, dynamic>{};
      final untaxedInvoiceAgg = (results[4] is Map)
          ? results[4] as Map<String, dynamic>
          : const <String, dynamic>{};
      final List<Map<String, dynamic>> topProductsGrouped = (results[5] is List)
          ? (results[5] as List).cast<Map<String, dynamic>>()
          : const <Map<String, dynamic>>[];
      final List<Map<String, dynamic>> dailyRevenueList = (results[6] is List)
          ? (results[6] as List).cast<Map<String, dynamic>>()
          : const <Map<String, dynamic>>[];

      final double monthlyRev = monthlyAgg.isNotEmpty
          ? (_safeToNum(monthlyAgg['sum'])?.toDouble() ?? 0.0)
          : 0.0;
      final int monthlyCount = monthlyAgg.isNotEmpty
          ? (_safeToNum(monthlyAgg['count'])?.toInt() ?? 0)
          : 0;

      final double weeklyRev = weeklyAgg.isNotEmpty
          ? (_safeToNum(weeklyAgg['sum'])?.toDouble() ?? 0.0)
          : 0.0;

      final double outstanding = outstandingAgg.isNotEmpty
          ? (_safeToNum(outstandingAgg['sum'])?.toDouble() ?? 0.0)
          : 0.0;

      final double totalUntaxed = untaxedInvoiceAgg.isNotEmpty
          ? (_safeToNum(untaxedInvoiceAgg['sum'])?.toDouble() ?? 0.0)
          : 0.0;

      final List<Map<String, dynamic>> topProductsList = topProductsGrouped;

      double convRate = 0.0;
      try {
        final totalQuotesResult = await OdooSessionManager.callKwWithCompany({
          'model': 'sale.order',
          'method': 'search_count',
          'args': [
            [
              ['date_order', '>=', monthStartStr],
              ['date_order', '<=', monthEndStr],
              ['state', '!=', 'cancel'],
            ],
          ],
          'kwargs': {},
        });

        final confirmedOrdersResult =
            await OdooSessionManager.callKwWithCompany({
              'model': 'sale.order',
              'method': 'search_count',
              'args': [
                [
                  [
                    'state',
                    'in',
                    ['sale', 'done'],
                  ],
                  ['date_order', '>=', monthStartStr],
                  ['date_order', '<=', monthEndStr],
                ],
              ],
              'kwargs': {},
            });

        if (totalQuotesResult > 0) {
          convRate = (confirmedOrdersResult / totalQuotesResult) * 100;
        }
      } catch (e) {}

      double avgDeal = 0.0;
      if (monthlyCount > 0) {
        avgDeal = monthlyRev / monthlyCount;
      }

      int expiredCount = 0;
      int tasksToday = 0;
      try {
        expiredCount = await OdooSessionManager.callKwWithCompany({
          'model': 'sale.order',
          'method': 'search_count',
          'args': [
            [
              [
                'state',
                'in',
                ['draft', 'sent'],
              ],
              ['validity_date', '!=', false],
              ['validity_date', '<', todayStr],
            ],
          ],
          'kwargs': {},
        });
      } catch (e) {}
      try {
        final uid = sessionService.currentSession?.userId;
        if (uid != null) {
          tasksToday = await OdooSessionManager.callKwWithCompany({
            'model': 'mail.activity',
            'method': 'search_count',
            'args': [
              [
                ['user_id', '=', uid],
                ['date_deadline', '=', todayStr],

                ['active', '=', true],
              ],
            ],
            'kwargs': {},
          });
        }
      } catch (e) {}

      if (!mounted) return;
      setState(() {
        monthlyRevenue = monthlyRev;
        weeklyRevenue = weeklyRev;
        conversionRate = convRate;
        averageDealSize = avgDeal;
        overdueInvoicesCount = overdueCount;
        outstandingReceivables = outstanding;
        totalUntaxedInvoiceAmount = totalUntaxed;
        todayTasksCount = tasksToday;
        expiredQuotesCount = expiredCount;
        topProducts = topProductsList;
        _dailyRevenueData = dailyRevenueList;
      });

      _cacheSalesMetrics();

      if (_isServerUnreachable && mounted) {
        setState(() {
          _isServerUnreachable = false;
        });
        try {
          sessionService.clearServerUnreachableState();
        } catch (e) {}
      }
    } catch (e) {
      final errorString = e.toString().toLowerCase();
      final isServerError =
          errorString.contains('server unavailable') ||
          errorString.contains('database does not exist') ||
          errorString.contains('wrong database') ||
          errorString.contains('access denied');

      if (mounted && isServerError) {
        setState(() {
          _isServerUnreachable = true;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _safeAggregateSum({
    required String model,
    required List<dynamic> domain,
    required String sumField,
  }) async {
    try {
      final res = await OdooSessionManager.callKwWithCompany({
        'model': model,
        'method': 'read_group',
        'args': [domain],
        'kwargs': {
          'fields': ['$sumField:sum'],
          'groupby': [],
        },
      });
      if (res is List && res.isNotEmpty) {
        final row = res.first as Map<String, dynamic>;
        final sumVal = _safeToNum(row[sumField])?.toDouble() ?? 0.0;
        final cnt = _safeToNum(row['__count'])?.toInt() ?? 0;
        return {'sum': sumVal, 'count': cnt};
      }
      return {'sum': 0.0, 'count': 0};
    } catch (e) {
      final es = e.toString();
      if (!es.contains('does not exist') && !es.contains('read_group')) {
        rethrow;
      }

      try {
        final recs = await OdooSessionManager.callKwWithCompany({
          'model': model,
          'method': 'search_read',
          'args': [domain],
          'kwargs': {
            'fields': [sumField],
            'limit': 1000,
          },
        });
        double sum = 0.0;
        int count = 0;
        if (recs is List) {
          for (final r in recs) {
            final v = _safeToNum(r[sumField])?.toDouble();
            if (v != null) sum += v;
            count += 1;
          }
        }
        return {'sum': sum, 'count': count};
      } catch (_) {
        return {'sum': 0.0, 'count': 0};
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchDailyRevenue(
    String startDate,
    String endDate,
    DateTime rangeStart,
  ) async {
    try {
      final result = await OdooSessionManager.callKwWithCompany({
        'model': 'sale.order',
        'method': 'read_group',
        'args': [
          [
            [
              'state',
              'in',
              ['sale', 'done'],
            ],
            ['date_order', '>=', startDate],
            ['date_order', '<=', endDate],
          ],
        ],
        'kwargs': {
          'fields': ['date_order', 'amount_total:sum'],
          'groupby': ['date_order:day'],
          'orderby': 'date_order:day',
        },
      });

      final Map<String, double> revenueByDate = {};

      if (result is List && result.isNotEmpty) {
        for (final group in result) {
          try {
            final dateStr =
                group['date_order:day'] as String? ??
                group['date_order'] as String? ??
                group['__domain'] as String?;
            final revenue =
                _safeToNum(group['amount_total'])?.toDouble() ?? 0.0;

            if (dateStr != null && dateStr.isNotEmpty) {
              DateTime date;
              if (dateStr.contains(' ')) {
                final parts = dateStr.split(' ');
                if (parts.length >= 3 && parts[1].length == 3) {
                  final day = int.parse(parts[0]);
                  final monthMap = {
                    'Jan': 1,
                    'Feb': 2,
                    'Mar': 3,
                    'Apr': 4,
                    'May': 5,
                    'Jun': 6,
                    'Jul': 7,
                    'Aug': 8,
                    'Sep': 9,
                    'Oct': 10,
                    'Nov': 11,
                    'Dec': 12,
                  };
                  final month = monthMap[parts[1]] ?? 1;
                  final year = int.parse(parts[2]);
                  date = DateTime(year, month, day);
                } else {
                  date = DateTime.parse(parts[0]);
                }
              } else {
                date = DateTime.parse(dateStr);
              }

              final dateKey =
                  '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
              revenueByDate[dateKey] = revenue;
            }
          } catch (e) {}
        }
      }

      final List<Map<String, dynamic>> dailyData = [];
      const monthNames = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];

      for (int i = 0; i < 7; i++) {
        final date = rangeStart.add(Duration(days: i));
        final dateKey =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final revenue = revenueByDate[dateKey] ?? 0.0;

        final monthName = monthNames[date.month - 1];
        final dayLabel = '$monthName ${date.day}';

        dailyData.add({'label': dayLabel, 'value': revenue, 'date': date});
      }

      return dailyData;
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _safeTopProducts({
    required List<dynamic> domain,
    int limit = 10,
  }) async {
    try {
      final res = await OdooSessionManager.callKwWithCompany({
        'model': 'sale.order.line',
        'method': 'read_group',
        'args': [domain],
        'kwargs': {
          'fields': ['product_id', 'product_uom_qty:sum', 'price_total:sum'],
          'groupby': ['product_id'],
          'orderby': 'product_uom_qty:sum desc',
          'limit': limit,
        },
      });

      if (res is List) {
        final List<Map<String, dynamic>> items = [];

        for (final group in res) {
          try {
            final productInfo = group['product_id'];
            if (productInfo is List && productInfo.length >= 2) {
              final productId = productInfo[0] as int;

              final ordersCountRes = await OdooSessionManager.callKwWithCompany(
                {
                  'model': 'sale.order.line',
                  'method': 'read_group',
                  'args': [
                    [
                      ...domain,
                      ['product_id', '=', productId],
                    ],
                  ],
                  'kwargs': {
                    'fields': ['order_id'],
                    'groupby': ['order_id'],
                  },
                },
              );

              final ordersCount = (ordersCountRes is List)
                  ? ordersCountRes.length
                  : 0;

              items.add({
                'id': productId,
                'name': productInfo[1] as String,
                'qty': _safeToNum(group['product_uom_qty'])?.toDouble() ?? 0.0,
                'total': _safeToNum(group['price_total'])?.toDouble() ?? 0.0,
                'orders_count': ordersCount,
              });
            }
          } catch (_) {}
        }
        return items;
      }
      return [];
    } catch (e) {
      final es = e.toString();
      if (!es.contains('does not exist') && !es.contains('read_group')) {
        rethrow;
      }

      try {
        final recs = await OdooSessionManager.callKwWithCompany({
          'model': 'sale.order.line',
          'method': 'search_read',
          'args': [domain],
          'kwargs': {
            'fields': [
              'product_id',
              'product_uom_qty',
              'price_total',
              'order_id',
            ],
            'limit': 2000,
          },
        });
        final Map<int, Map<String, dynamic>> agg = {};
        final Map<int, Set<int>> productOrders = {};

        if (recs is List) {
          for (final r in recs) {
            final productInfo = r['product_id'];
            final orderInfo = r['order_id'];
            if (productInfo is List &&
                productInfo.length >= 2 &&
                orderInfo is List &&
                orderInfo.length >= 2) {
              final id = productInfo[0] as int;
              final name = productInfo[1] as String;
              final orderId = orderInfo[0] as int;
              final qty = _safeToNum(r['product_uom_qty'])?.toDouble() ?? 0.0;
              final total = _safeToNum(r['price_total'])?.toDouble() ?? 0.0;

              final entry =
                  agg[id] ??
                  {
                    'id': id,
                    'name': name,
                    'qty': 0.0,
                    'total': 0.0,
                    'orders_count': 0,
                  };
              entry['qty'] = (entry['qty'] as double) + qty;
              entry['total'] = (entry['total'] as double) + total;

              productOrders[id] ??= <int>{};
              productOrders[id]!.add(orderId);
              entry['orders_count'] = productOrders[id]!.length;

              agg[id] = entry;
            }
          }
        }
        final list = agg.values.toList()
          ..sort((a, b) => (b['qty'] as double).compareTo(a['qty'] as double));
        if (list.length > limit) {
          return list.sublist(0, limit);
        }
        return list;
      } catch (_) {
        return [];
      }
    }
  }

  Future<void> _fetchUserInfo({bool forceRefresh = false}) async {
    if (!mounted) return;

    final key = _getCurrentAccountKey();
    if (!forceRefresh &&
        _accountCachedUserData.containsKey(key) &&
        !_isUserDataStale()) {
      _loadCachedUserData();
      return;
    }

    SessionService? sessionService;
    try {
      sessionService = context.read<SessionService>();
    } catch (e) {
      return;
    }

    final session = sessionService.currentSession;
    if (session == null) {
      if (!mounted) return;
      _loadCachedUserDataOrDefaults();
      return;
    }

    userLogin = session.userLogin;

    if (!sessionService.hasValidSession) {
      if (!mounted) return;
      _loadCachedUserDataOrDefaults();
      return;
    }

    final uid = session.userId;
    if (uid == null) {
      if (!mounted) return;
      _loadCachedUserDataOrDefaults();
      return;
    }

    try {
      final result = await OdooSessionManager.callKwWithCompany({
        'model': 'res.users',
        'method': 'read',
        'args': [uid],
        'kwargs': {
          'fields': [
            'name',
            'image_1920',
            'phone',
            'website',
            'function',
            'company_id',
            'street',
            'street2',
            'city',
            'state_id',
            'zip',
            'country_id',
            'active',
          ],
        },
      });

      if (mounted && result is List && result.isNotEmpty) {
        final userData = result.first;
        final fetchedName = userData['name']?.toString() ?? 'User';
        String? fetchedAvatar;

        try {
          if (userData['image_1920'] != false &&
              userData['image_1920'] != null) {
            final imageData = userData['image_1920'].toString();
            if (imageData.isNotEmpty) {
              fetchedAvatar = imageData;
            }
          }
        } catch (e) {
          fetchedAvatar = null;
        }

        setState(() {
          userName = fetchedName;
          userAvatar = fetchedAvatar;
        });

        _cacheUserData();
      } else {
        _loadCachedUserDataOrDefaults();
      }
    } catch (e) {
      final errorString = e.toString().toLowerCase();
      final isServerError =
          errorString.contains('server unavailable') ||
          errorString.contains('database does not exist') ||
          errorString.contains('wrong database') ||
          errorString.contains('access denied');

      if (mounted) {
        if (isServerError) {
          setState(() {
            _isServerUnreachable = true;
          });
        }
        _loadCachedUserDataOrDefaults();
      }
    }
  }

  void _cacheUserData() {
    final key = _getCurrentAccountKey();
    _accountCachedUserData[key] = {
      'userName': userName,
      'userLogin': userLogin,
      'userAvatar': userAvatar,
    };
    final now = DateTime.now();
    _lastCacheTimes['userData_$key'] = now;
    _lastCacheTimes[key] = now;
  }

  void _loadCachedUserData() {
    final key = _getCurrentAccountKey();
    final cachedData = _accountCachedUserData[key];
    if (cachedData != null && mounted) {
      setState(() {
        userName = cachedData['userName'];
        userLogin = cachedData['userLogin'];
        userAvatar = cachedData['userAvatar'];
      });
    }
  }

  void _loadCachedUserDataOrDefaults() {
    final key = _getCurrentAccountKey();
    if (_accountCachedUserData.containsKey(key)) {
      _loadCachedUserData();
    } else {
      setState(() {
        userName = userName ?? 'User';
        userLogin = userLogin;
        userAvatar = userAvatar;
      });
    }
  }

  Widget _buildUserAvatar() {
    return isLoadingDashboardAll
        ? Shimmer.fromColors(
            baseColor: Colors.white.withOpacity(0.3),
            highlightColor: Colors.white.withOpacity(0.6),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.4),
                shape: BoxShape.circle,
              ),
            ),
          )
        : _buildAvatarContent();
  }

  Widget _buildAvatarContent() {
    String? avatarData = userAvatar;
    String fallbackName = userName ?? 'User';

    if (avatarData == null || avatarData.isEmpty || fallbackName == 'User') {
      try {
        final settingsProvider = context.read<SettingsProvider>();
        final userProfile = settingsProvider.userProfile;
        if (userProfile != null) {
          if (avatarData == null || avatarData.isEmpty) {
            final img = userProfile['image_1920'];
            if (img != null && img != false && img.toString().isNotEmpty) {
              avatarData = img.toString();
            }
          }

          if (fallbackName == 'User') {
            final name = userProfile['name'];
            if (name != null && name.toString().isNotEmpty) {
              fallbackName = name.toString();
            }
          }
        }
      } catch (e) {}
    }

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CircularImageWidget(
        base64Image: avatarData,
        radius: 28,
        fallbackText: fallbackName,
        backgroundColor: AppTheme.primaryColor,
        textColor: Colors.white,
      ),
    );
  }

  Future<void> _fetchDashboardCounts({bool forceRefresh = false}) async {
    if (!mounted ||
        (!forceRefresh &&
            !_areCountsStale() &&
            _accountCachedDashboardCounts.containsKey(
              _getCurrentAccountKey(),
            ))) {
      return;
    }

    SessionService? sessionService;
    try {
      sessionService = context.read<SessionService>();
    } catch (e) {
      return;
    }

    if (!sessionService.hasValidSession) {
      return;
    }

    if (_isServerUnreachable) {
      _isServerUnreachable = false;
      sessionService.clearServerUnreachableState();
    }

    try {
      final results = await Future.wait([
        OdooSessionManager.callKwWithCompany({
          'model': 'res.partner',
          'method': 'search_count',
          'args': [
            [
              ['active', '=', true],
              ['customer_rank', '>', 0],
            ],
          ],
          'kwargs': {},
        }),
        OdooSessionManager.callKwWithCompany({
          'model': 'sale.order',
          'method': 'search_count',
          'args': [
            [
              [
                'state',
                'in',
                ['draft', 'sent', 'sale', 'done', 'cancel'],
              ],
            ],
          ],
          'kwargs': {},
        }),
        OdooSessionManager.callKwWithCompany({
          'model': 'account.move',
          'method': 'search_count',
          'args': [
            [
              [
                'move_type',
                'in',
                ['out_invoice', 'out_refund'],
              ],
            ],
          ],
          'kwargs': {},
        }),
        OdooSessionManager.callKwWithCompany({
          'model': 'product.template',
          'method': 'search_count',
          'args': [
            [
              ['sale_ok', '=', true],
            ],
          ],
          'kwargs': {},
        }),
        OdooSessionManager.callKwWithCompany({
          'model': 'sale.order',
          'method': 'search_count',
          'args': [
            [
              ['state', '=', 'to_approve'],
            ],
          ],
          'kwargs': {},
        }),
      ]);

      bool inventoryModuleInstalled = false;
      try {
        final inventoryModule = await OdooSessionManager.callKwWithCompany({
          'model': 'ir.module.module',
          'method': 'search_read',
          'args': [
            [
              ['name', '=', 'stock'],
              ['state', '=', 'installed'],
            ],
          ],
          'kwargs': {
            'fields': ['state'],
            'limit': 1,
          },
        });
        if (inventoryModule is List && inventoryModule.isNotEmpty) {
          inventoryModuleInstalled = true;
        }
      } catch (e) {}

      if (!mounted) return;
      setState(() {
        contactsCount = results[0] as int;
        quotesCount = results[1] as int;
        invoicesCount = results[2] as int;
        productsCount = results[3] as int;
        approvalsCount = results[4] as int;

        hasInventoryModule = inventoryModuleInstalled;
        _dashboardErrorMessage = null;

        if (_isServerUnreachable) {
          _isServerUnreachable = false;
        }
      });
      _cacheDashboardCounts();

      if (mounted) {
        try {
          sessionService.clearServerUnreachableState();
        } catch (e) {}
      }
    } catch (e) {
      final errorString = e.toString().toLowerCase();
      final isServerError =
          errorString.contains('server unavailable') ||
          errorString.contains('database does not exist') ||
          errorString.contains('wrong database') ||
          errorString.contains('access denied');

      if (!mounted) return;
      setState(() {
        if (isServerError) {
          _isServerUnreachable = true;
        }
      });
    }
  }

  String _formatCurrency(double? amount) {
    if (amount == null) {
      final currencyProvider = Provider.of<CurrencyProvider>(
        context,
        listen: false,
      );
      return currencyProvider.formatAmount(0);
    }

    final currencyProvider = Provider.of<CurrencyProvider>(
      context,
      listen: false,
    );

    if (!_useAbbreviatedCurrency) {
      return currencyProvider.formatAmount(amount);
    }

    final isNegative = amount < 0;
    final absoluteAmount = amount.abs();

    String formattedAmount;

    if (absoluteAmount < 10000) {
      formattedAmount = currencyProvider.formatAmount(absoluteAmount);
    } else if (absoluteAmount < 1000000) {
      formattedAmount = '${(absoluteAmount / 1000).toStringAsFixed(1)}K';
    } else if (absoluteAmount < 1000000000) {
      formattedAmount = '${(absoluteAmount / 1000000).toStringAsFixed(1)}M';
    } else {
      formattedAmount = '${(absoluteAmount / 1000000000).toStringAsFixed(1)}B';
    }

    if (isNegative) {
      formattedAmount = '-$formattedAmount';
    }

    return formattedAmount;
  }

  String _formatCurrencyFull(double? amount, {int decimalDigits = 2}) {
    if (amount == null) {
      final dynamicSymbol = _currencySymbol();
      return '$dynamicSymbol 0.00';
    }

    final dynamicSymbol = _currencySymbol();
    final isNegative = amount < 0;
    final absVal = amount.abs();
    final numStr = _formatNumberWithThousands(absVal, decimalDigits);
    return isNegative ? '$dynamicSymbol -$numStr' : '$dynamicSymbol $numStr';
  }

  String _currencySymbol() {
    try {
      final currencyProvider = Provider.of<CurrencyProvider>(
        context,
        listen: false,
      );
      final sym = currencyProvider.currencyFormat.currencySymbol;
      if (sym.isNotEmpty) return sym;

      final code = currencyProvider.currency;
      if (code.isNotEmpty) return code;
      return '';
    } catch (e) {
      return '';
    }
  }

  String _formatNumberWithThousands(double value, int decimalDigits) {
    final fixed = value.toStringAsFixed(decimalDigits);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final fracPart = parts.length > 1 ? parts[1] : '';

    final reg = RegExp(r"(\d)(?=(\d{3})+(?!\d))");
    final withCommas = intPart.replaceAllMapped(reg, (Match m) => '${m[1]},');

    return fracPart.isNotEmpty ? '$withCommas.$fracPart' : '$withCommas.00';
  }

  String _getCardCount(int? count) {
    if (_isOffline || !_hasSession) {
      return count != null ? '${count.toString()} (cached)' : '--';
    }
    if (isLoadingDashboardAll) {
      return '...';
    }

    if (count == null) {
      return '0';
    }
    return count.toString();
  }

  String _getMetricValue(dynamic value) {
    if (_isOffline || !_hasSession) {
      if (value is double) {
        final formatted = _formatCurrency(value);
        final result = formatted.isEmpty
            ? '${_currencySymbol()} 0.00'
            : formatted;
        return '$result (cached)';
      }
      return value != null ? '${value.toString()} (cached)' : '--';
    }
    if (isLoadingDashboardAll || isLoadingCharts) {
      return '...';
    }
    if (value is double) {
      final formatted = _formatCurrency(value);
      return formatted.isEmpty ? '${_currencySymbol()} 0.00' : formatted;
    }

    if (value == null) {
      return '0';
    }
    return value.toString();
  }

  Widget buildTopProductShimmer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shimmerBase = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final shimmerHighlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    final placeholderColor = isDark ? Colors.grey[900]! : Colors.white;

    return Shimmer.fromColors(
      baseColor: shimmerBase,
      highlightColor: shimmerHighlight,
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: placeholderColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 80,
              height: 14,
              decoration: BoxDecoration(
                color: shimmerBase,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 50,
              height: 12,
              decoration: BoxDecoration(
                color: shimmerBase,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 60,
              height: 12,
              decoration: BoxDecoration(
                color: shimmerBase,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getMetricValueWithCurrency(double? amount) {
    if (_isOffline || !_hasSession) {
      if (amount == null) return '--';
      return '${_formatCurrency(amount)} (cached)';
    }
    if (isLoadingDashboardAll || isLoadingCharts) {
      return '...';
    }
    if (amount == null) {
      return '${_currencySymbol()} 0.00';
    }
    return _formatCurrency(amount);
  }

  String _formatCurrencyFullWithProvider(double? amount) {
    if (amount == null) {
      final currencyProvider = Provider.of<CurrencyProvider>(
        context,
        listen: false,
      );
      return currencyProvider.formatAmount(0);
    }

    final currencyProvider = Provider.of<CurrencyProvider>(
      context,
      listen: false,
    );
    return currencyProvider.formatAmount(amount);
  }

  List<Map<String, dynamic>> _getRevenueChartData() {
    if (isLoadingDashboardAll || _dailyRevenueData.isEmpty) {
      return [];
    }
    return _dailyRevenueData;
  }

  List<Map<String, dynamic>> _getSalesBreakdownData() {
    if (isLoadingDashboardAll) {
      return [];
    }
    return [
      {'label': 'Quotations', 'value': (quotesCount ?? 0).toDouble()},
      {'label': 'Invoices', 'value': (invoicesCount ?? 0).toDouble()},
      {'label': 'Customers', 'value': (contactsCount ?? 0).toDouble()},
      {'label': 'Products', 'value': (productsCount ?? 0).toDouble()},
    ];
  }

  List<Map<String, dynamic>> _getProductPerformanceData() {
    if (isLoadingDashboardAll || topProducts.isEmpty) {
      return [];
    }

    final List<Map<String, dynamic>> sorted = List<Map<String, dynamic>>.from(
      topProducts,
    );
    sorted.sort((a, b) {
      final qa = (a['qty'] is num) ? (a['qty'] as num).toDouble() : 0.0;
      final qb = (b['qty'] is num) ? (b['qty'] as num).toDouble() : 0.0;
      return qb.compareTo(qa);
    });

    return sorted.take(6).map((p) {
      final name = (p['name'] ?? '') as String;
      final qty = (p['qty'] is num) ? (p['qty'] as num).toDouble() : 0.0;
      final total = (p['total'] is num) ? (p['total'] as num).toDouble() : 0.0;
      final ordersCount = p['orders_count'] ?? 0;
      final id = p['id'] ?? 0;
      return {
        'name': name,
        'value': qty,
        'qty': qty,
        'total': total,
        'orders_count': ordersCount,
        'id': id,
      };
    }).toList();
  }

  Widget buildContinueItemTile(Map item) {
    return ListTile(
      title: Text(item['name']),
      subtitle: Text(item['subtitle']),
      onTap: item['onTap'],
    );
  }

  void _navigateToLastOpenedItem(LastOpenedItem item) {
    switch (item.type) {
      case 'quotation':
        if (item.data != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  QuotationDetailScreen(quotation: Quote.fromJson(item.data!)),
            ),
          );
        }
        break;
      case 'invoice':
        if (item.data != null && item.data!['id'] != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  InvoiceDetailsPage(invoiceId: item.data!['id'].toString()),
            ),
          );
        }
        break;
      case 'product':
        if (item.data != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  ProductDetailsPage(product: Product.fromJson(item.data!)),
            ),
          );
        }
        break;
      case 'customer':
        if (item.data != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  CustomerDetailsScreen(contact: Contact.fromJson(item.data!)),
            ),
          );
        }
        break;
      case 'page':
        switch (item.route) {
          case '/quotation_list':
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => QuotationListScreen()),
            );
            break;
          case '/invoice_list':
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => InvoiceListScreen()),
            );
            break;
          case '/settings':
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => SettingsScreen()),
            );
            break;
          case '/profile':
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ProfileScreen()),
            );
            break;
          default:
        }
        break;
      default:
    }
  }

  Future<void> _fetchContinueWorkingItems() async {
    if (mounted) {
      setState(() {
        isLoadingContinueWorking = true;
      });
    }

    SessionService? sessionService;
    try {
      sessionService = context.read<SessionService>();
    } catch (e) {
      return;
    }

    try {
      final List<Map<String, dynamic>> items = [];
      final now = DateTime.now();
      final Set<int> loadingTaps = <int>{};

      final userId = sessionService.currentSession?.userId;
      if (userId != null) {
        final quotations = await OdooSessionManager.callKwWithCompany({
          'model': 'sale.order',
          'method': 'search_read',
          'args': [
            [
              [
                'state',
                'in',
                ['draft', 'sent'],
              ],
              ['user_id', '=', userId],
            ],
          ],
          'kwargs': {
            'fields': _quotationFields,
            'limit': 3,
            'order': 'write_date desc',
          },
        });
        if (quotations is List) {
          for (var q in quotations) {
            final id = q['id'];
            final writeDate = DateTime.tryParse(q['write_date'].toString());
            final elapsed = writeDate != null
                ? _formatTimeAgo(writeDate, now)
                : '';
            String partnerName = 'Customer';
            final partnerValue = q['partner_id'];
            if (partnerValue is List &&
                partnerValue.length > 1 &&
                partnerValue[1] is String) {
              partnerName = partnerValue[1];
            }
            items.add({
              'type': 'quotation',
              'name': (q['name'] is String) ? q['name'] : 'Draft Quotation',
              'subtitle': 'For $partnerName',
              'lastModified': elapsed,
              'onTap': () async {
                if (loadingTaps.contains(id)) return;
                loadingTaps.add(id);
                try {
                  SessionService? sessionService;
                  try {
                    sessionService = context.read<SessionService>();
                  } catch (e) {
                    return;
                  }

                  final hasSession = sessionService.hasValidSession;
                  if (!hasSession) throw Exception('No session found');

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          QuotationDetailScreen(quotation: Quote.fromJson(q)),
                    ),
                  );
                } catch (e) {
                  if (context.mounted) {
                    CustomSnackbar.showError(
                      context,
                      'Failed to open quotation: $e',
                    );
                  }
                } finally {
                  loadingTaps.remove(id);
                }
              },
            });
          }
        }
      }
      if (userId != null) {
        final invoices = await OdooSessionManager.callKwWithCompany({
          'model': 'account.move',
          'method': 'search_read',
          'args': [
            [
              ['move_type', '=', 'out_invoice'],
              ['state', '=', 'draft'],
              ['invoice_user_id', '=', userId],
            ],
          ],
          'kwargs': {
            'fields': [
              'id',
              'name',
              'invoice_date',
              'write_date',
              'partner_id',
              'state',
            ],
            'limit': 2,
            'order': 'write_date desc',
          },
        });
        if (invoices is List) {
          for (var inv in invoices) {
            final writeDate = DateTime.tryParse(inv['write_date'].toString());
            final elapsed = writeDate != null
                ? _formatTimeAgo(writeDate, now)
                : '';
            String partnerName = 'Customer';
            final partnerValue = inv['partner_id'];
            if (partnerValue is List &&
                partnerValue.length > 1 &&
                partnerValue[1] is String) {
              partnerName = partnerValue[1];
            }
            items.add({
              'type': 'invoice',
              'name': (inv['name'] is String) ? inv['name'] : 'Draft Invoice',
              'subtitle': 'For $partnerName',
              'lastModified': elapsed,
              'onTap': () async {
                final id = inv['id'];
                if (loadingTaps.contains(id)) return;
                loadingTaps.add(id);
                try {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          InvoiceDetailsPage(invoiceId: id.toString()),
                    ),
                  );
                } catch (e) {
                  if (context.mounted) {
                    CustomSnackbar.showError(
                      context,
                      'Failed to open invoice: $e',
                    );
                  }
                } finally {
                  loadingTaps.remove(id);
                }
              },
            });
          }
        }
      }
      if (!mounted) return;
      setState(() {
        continueWorkingItems = items;
        isLoadingContinueWorking = false;
        _lastContinueWorkingFetch = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        continueWorkingItems = [];
        isLoadingContinueWorking = false;
        _lastContinueWorkingFetch = DateTime.now();
      });
    }
  }

  String _formatTimeAgo(DateTime dt, DateTime now) {
    final duration = now.difference(dt);
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds}s ago';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes}m ago';
    } else if (duration.inHours < 24) {
      return '${duration.inHours}h ago';
    } else {
      return '${duration.inDays}d ago';
    }
  }

  List<Map<String, dynamic>> _getSmartSuggestions() {
    if (isLoadingDashboardAll) {
      return [];
    }

    final suggestions = <Map<String, dynamic>>[];

    if ((overdueInvoicesCount ?? 0) > 0) {
      suggestions.add({
        'title': 'Follow up on overdue invoices',
        'description':
            "${overdueInvoicesCount ?? 0} invoice${overdueInvoicesCount == 1 ? '' : 's'} ${overdueInvoicesCount == 1 ? 'is' : 'are'} overdue. Try reminding your customers.",
        'priority': 'high',
        'onTap': () {
          TapPrevention.executeNavigation(
            'suggestion_overdue_invoices',

            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => InvoiceListScreen(overdueOnly: true),
              ),
            ),
          );
        },
      });
    } else {}

    if ((expiredQuotesCount ?? 0) > 0) {
      suggestions.add({
        'title': 'Review expired quotations',
        'description':
            '${expiredQuotesCount ?? 0} quote${(expiredQuotesCount ?? 0) == 1 ? '' : 's'} have expired and need updates or follow-up.',
        'priority': 'medium',
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => QuotationListScreen(
                initialFilters: {'expired'},
                showForcedAppBar: true,
                forcedAppBarTitle: 'Expired Quotations',

                expiringSoonOnly: false,
              ),
            ),
          );
        },
      });
    } else {}

    final convRate = conversionRate ?? 0;
    final monthRev = monthlyRevenue ?? 0;

    if (convRate < 20 && monthRev > 0) {
      suggestions.add({
        'title': 'Improve conversion rate',
        'description':
            'Conversion rate is low (${conversionRate?.toStringAsFixed(1) ?? '0.0'}% this month). Review pipeline and lost opportunities.',
        'priority': 'medium',
        'onTap': () {
          TapPrevention.executeNavigation(
            'suggestion_conversion_rate',

            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => QuotationListScreen()),
            ),
          );
        },
      });
    } else {}

    suggestions.add({
      'title': 'Check Stock Levels',
      'description': 'Quickly check current product inventory',
      'priority': 'medium',
      'onTap': () {
        TapPrevention.executeNavigation(
          'suggestion_stock_check',

          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => StockCheckPage()),
          ),
        );
      },
    });

    for (int i = 0; i < suggestions.length; i++) {}

    if (suggestions.isEmpty) {
      suggestions.add({
        'title': 'No urgent actions',
        'description':
            'Nothing critical detected right now. Keep up the good work!',
        'priority': 'low',
        'onTap': () {},
      });
    }
    return suggestions;
  }

  Widget _buildCurrencyFormatToggle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 36,
      decoration: BoxDecoration(
        color: _isToggling
            ? (isDark ? Colors.grey[700] : Colors.grey[300])
            : (isDark ? Colors.grey[800] : Colors.grey[200]),
        borderRadius: BorderRadius.circular(18),
        border: _isToggling
            ? Border.all(
                color: isDark ? Colors.blue[400]! : Colors.black,
                width: 1.5,
              )
            : null,
      ),
      child: Stack(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildToggleOption(
                context,
                'Abbrev',
                _useAbbreviatedCurrency,
                isDark,
                () => _handleToggle(true),
              ),
              _buildToggleOption(
                context,
                'Full',
                !_useAbbreviatedCurrency,
                isDark,
                () => _handleToggle(false),
              ),
            ],
          ),

          if (_isToggling)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: (isDark ? Colors.black : Colors.white).withOpacity(
                    0.3,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDark
                            ? Colors.blue[300]!
                            : Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToggleOption(
    BuildContext context,
    String text,
    bool isActive,
    bool isDark,
    VoidCallback onTap,
  ) {
    final isEnabled = !_isToggling;

    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark ? Colors.white : Colors.black)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isActive && !_isToggling
              ? [
                  BoxShadow(
                    color: (isDark ? Colors.white : Colors.black).withOpacity(
                      0.09,
                    ),
                    blurRadius: 16,
                    spreadRadius: 2,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: !isEnabled
                  ? (isDark ? Colors.grey[500] : Colors.grey[400])
                  : isActive
                  ? (isDark ? Colors.black : Colors.white)
                  : (isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
            child: Text(
              text,
              style: TextStyle(fontFamily: GoogleFonts.inter().fontFamily),
            ),
          ),
        ),
      ),
    );
  }

  void _handleToggle(bool useAbbreviated) {
    if (_isToggling || _useAbbreviatedCurrency == useAbbreviated) {
      return;
    }

    _debounceTimer?.cancel();

    setState(() {
      _isToggling = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _useAbbreviatedCurrency = useAbbreviated;
          _isToggling = false;
        });

        HapticFeedback.selectionClick();

        CustomSnackbar.showSuccess(
          context,
          'Currency format changed to ${_useAbbreviatedCurrency ? 'abbreviated' : 'full'}',
        );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {});
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.grey[900]! : Colors.grey[50]!;

    return Scaffold(
      backgroundColor: backgroundColor,
      floatingActionButton: SpeedDial(
        animatedIcon: AnimatedIcons.menu_close,
        animatedIconTheme: IconThemeData(
          size: 22,
          color: isDark ? Colors.black : Colors.white,
        ),
        spacing: 8,
        spaceBetweenChildren: 8,
        closeManually: false,
        useRotationAnimation: true,
        animationCurve: Curves.easeOutCubic,
        animationDuration: const Duration(milliseconds: 160),
        direction: SpeedDialDirection.up,
        onOpen: () => HapticFeedback.lightImpact(),
        onClose: () => HapticFeedback.selectionClick(),

        backgroundColor: isDark
            ? Colors.white
            : Theme.of(context).colorScheme.primary,
        foregroundColor: isDark
            ? Colors.black
            : Theme.of(context).colorScheme.onPrimary,
        overlayColor: Colors.black,
        overlayOpacity: isDark ? 0.30 : 0.20,
        elevation: 4,
        tooltip: 'Create',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        childPadding: const EdgeInsets.all(6),
        childMargin: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        heroTag: 'fab_speed_dial_dashboard',

        children: [
          SpeedDialChild(
            child: Icon(
              HugeIcons.strokeRoundedFiles01,
              color: isDark
                  ? Colors.white
                  : Theme.of(context).colorScheme.onPrimary,
              size: 20,
            ),
            backgroundColor: isDark
                ? Colors.grey[800]
                : Theme.of(context).colorScheme.primary,
            elevation: 3,
            label: 'Create Quotation',
            labelStyle: TextStyle(
              color: isDark
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            labelBackgroundColor: isDark
                ? Colors.grey[800]
                : Theme.of(context).colorScheme.surface,

            onTap: () => TapPrevention.executeNavigation(
              'speed_dial_create_quote',
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreateQuoteScreen(),
                ),
              ),
            ),
          ),

          SpeedDialChild(
            child: Icon(
              HugeIcons.strokeRoundedInvoice03,
              color: isDark
                  ? Colors.white
                  : Theme.of(context).colorScheme.onPrimary,
              size: 20,
            ),
            backgroundColor: isDark
                ? Colors.grey[800]
                : Theme.of(context).colorScheme.primary,
            elevation: 3,
            label: 'Create Invoice',
            labelStyle: TextStyle(
              color: isDark
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            labelBackgroundColor: isDark
                ? Colors.grey[800]
                : Theme.of(context).colorScheme.surface,

            onTap: () => TapPrevention.executeNavigation(
              'speed_dial_create_invoice',

              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreateInvoiceScreen(),
                ),
              ),
            ),
          ),

          SpeedDialChild(
            child: Icon(
              HugeIcons.strokeRoundedContact01,
              color: isDark
                  ? Colors.white
                  : Theme.of(context).colorScheme.onPrimary,
              size: 20,
            ),
            backgroundColor: isDark
                ? Colors.grey[800]
                : Theme.of(context).colorScheme.primary,
            elevation: 3,
            label: 'Create Customer',
            labelStyle: TextStyle(
              color: isDark
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            labelBackgroundColor: isDark
                ? Colors.grey[800]
                : Theme.of(context).colorScheme.surface,

            onTap: () => TapPrevention.executeNavigation(
              'speed_dial_add_customer',

              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const EditCustomerScreen(),
                ),
              ),
            ),
          ),

          SpeedDialChild(
            child: Icon(
              HugeIcons.strokeRoundedPackageOpen,
              color: isDark
                  ? Colors.white
                  : Theme.of(context).colorScheme.onPrimary,
              size: 20,
            ),
            backgroundColor: isDark
                ? Colors.grey[800]
                : Theme.of(context).colorScheme.primary,
            elevation: 3,
            label: 'Create Product',
            labelStyle: TextStyle(
              color: isDark
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            labelBackgroundColor: isDark
                ? Colors.grey[800]
                : Theme.of(context).colorScheme.surface,

            onTap: () => TapPrevention.executeNavigation(
              'speed_dial_add_product',

              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreateProductScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _forceRefreshAllData();
              },
              child: Stack(
                children: [
                  CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Builder(
                          builder: (context) {
                            final isDark =
                                Theme.of(context).brightness == Brightness.dark;
                            return GestureDetector(
                              onTap: () async {},

                              child: Container(
                                margin: const EdgeInsets.all(16),
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          isLoadingDashboardAll
                                              ? Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Shimmer.fromColors(
                                                      baseColor: Colors.white
                                                          .withOpacity(0.3),
                                                      highlightColor: Colors
                                                          .white
                                                          .withOpacity(0.6),
                                                      child: Container(
                                                        height: 28,
                                                        width: 200,
                                                        decoration: BoxDecoration(
                                                          color: Colors.white
                                                              .withOpacity(0.4),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                6,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Shimmer.fromColors(
                                                      baseColor: Colors.white
                                                          .withOpacity(0.2),
                                                      highlightColor: Colors
                                                          .white
                                                          .withOpacity(0.4),
                                                      child: Container(
                                                        height: 18,
                                                        width: 280,
                                                        decoration: BoxDecoration(
                                                          color: Colors.white
                                                              .withOpacity(0.3),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      _buildGreetingText(),
                                                      style:
                                                          GoogleFonts.manrope(
                                                            color: Colors.white,
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            letterSpacing: 0.5,
                                                            height: 1.2,
                                                          ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      _isOffline
                                                          ? 'Working offline - some features may be limited'
                                                          : (!_hasSession
                                                                ? 'Server not connected'
                                                                : (_dashboardErrorMessage !=
                                                                          null
                                                                      ? _dashboardErrorMessage!
                                                                      : 'Manage Your Sales Operations Efficiently')),
                                                      style: GoogleFonts.manrope(
                                                        color: _isOffline
                                                            ? Colors.orange[200]
                                                            : (!_hasSession
                                                                  ? Colors
                                                                        .orange[200]
                                                                  : (_dashboardErrorMessage !=
                                                                            null
                                                                        ? (Theme.of(
                                                                                    context,
                                                                                  ).brightness ==
                                                                                  Brightness.dark
                                                                              ? Colors.white
                                                                              : Colors.white)
                                                                        : Colors.white.withOpacity(
                                                                            0.9,
                                                                          ))),
                                                        fontSize: 14,
                                                        letterSpacing: 0,
                                                        fontWeight:
                                                            FontWeight.w400,
                                                        height: 1.3,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    _buildUserAvatar(),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Sales Performance',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontFamily:
                                          GoogleFonts.inter().fontFamily,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  if (!isLoadingCharts &&
                                      monthlyRevenue != null &&
                                      weeklyRevenue != null &&
                                      (monthlyRevenue! >= 10000 ||
                                          weeklyRevenue! >= 10000))
                                    _buildCurrencyFormatToggle(context),
                                ],
                              ),
                              const SizedBox(height: 12),

                              if (_isServerUnreachable ||
                                  _isOffline ||
                                  !_hasSession)
                                _buildSectionErrorState(
                                  context,
                                  'Sales Performance',
                                  _getSalesPerformanceErrorMessage(),
                                  HugeIcons.strokeRoundedMoney04,
                                )
                              else
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final isTabletOrLarger =
                                        ResponsiveLayout.isTablet(context) ||
                                        ResponsiveLayout.isDesktop(context);
                                    return Consumer<CurrencyProvider>(
                                      builder: (context, currencyProvider, child) {
                                        if (isTabletOrLarger) {
                                          return GridView.count(
                                            crossAxisCount: 3,
                                            crossAxisSpacing: 12,
                                            mainAxisSpacing: 12,
                                            childAspectRatio: 1.4,

                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            shrinkWrap: true,

                                            children: isLoadingCharts
                                                ? [
                                                    DashboardShimmer.buildMetricCardShimmer(
                                                      context,
                                                    ),
                                                    DashboardShimmer.buildMetricCardShimmer(
                                                      context,
                                                    ),
                                                    DashboardShimmer.buildMetricCardShimmer(
                                                      context,
                                                    ),
                                                    DashboardShimmer.buildMetricCardShimmer(
                                                      context,
                                                    ),
                                                    DashboardShimmer.buildMetricCardShimmer(
                                                      context,
                                                    ),
                                                  ]
                                                : [
                                                    _buildMetricCard(
                                                      context,
                                                      'Monthly Revenue',
                                                      HugeIcons
                                                          .strokeRoundedMoney04,
                                                      const Color(0xFF4CAF50),
                                                      _getMetricValueWithCurrency(
                                                        monthlyRevenue,
                                                      ),
                                                      'This month\'s sales',
                                                      _formatCurrencyFull(
                                                        monthlyRevenue,
                                                      ),
                                                      true,
                                                    ),
                                                    _buildMetricCard(
                                                      context,
                                                      'Weekly Revenue',
                                                      HugeIcons
                                                          .strokeRoundedMoneyBag02,
                                                      const Color(0xFF2196F3),
                                                      _getMetricValueWithCurrency(
                                                        weeklyRevenue,
                                                      ),
                                                      'Current week (ISO)',
                                                      _formatCurrencyFull(
                                                        weeklyRevenue,
                                                      ),
                                                      true,
                                                    ),
                                                    _buildMetricCard(
                                                      context,
                                                      'Conversion Rate',
                                                      HugeIcons
                                                          .strokeRoundedTarget03,
                                                      const Color(0xFFFF9800),
                                                      isLoadingCharts
                                                          ? '...'
                                                          : '${conversionRate?.toStringAsFixed(1) ?? '0'}%',
                                                      'Quote to sale ratio',
                                                      isLoadingCharts
                                                          ? '...'
                                                          : '${conversionRate?.toStringAsFixed(1) ?? '0'}%',
                                                    ),
                                                    _buildMetricCard(
                                                      context,
                                                      'Untaxed Invoices',
                                                      HugeIcons
                                                          .strokeRoundedInvoice03,
                                                      const Color(0xFF9C27B0),
                                                      _getMetricValueWithCurrency(
                                                        totalUntaxedInvoiceAmount,
                                                      ),
                                                      'Total untaxed amount',
                                                      _formatCurrencyFull(
                                                        totalUntaxedInvoiceAmount,
                                                      ),
                                                      true,
                                                    ),
                                                    _buildMetricCard(
                                                      context,
                                                      'Avg Deal Size',
                                                      HugeIcons
                                                          .strokeRoundedCalculator,
                                                      const Color(0xFFFF5722),
                                                      _getMetricValue(
                                                        averageDealSize,
                                                      ),
                                                      'Average order value',
                                                      _formatCurrencyFull(
                                                        averageDealSize,
                                                      ),
                                                      true,
                                                    ),
                                                    _buildMetricCard(
                                                      context,
                                                      'Outstanding',
                                                      HugeIcons
                                                          .strokeRoundedMoney01,
                                                      const Color(0xFF607D8B),
                                                      _getMetricValue(
                                                        outstandingReceivables,
                                                      ),
                                                      'Total receivables',
                                                      _formatCurrencyFull(
                                                        outstandingReceivables,
                                                      ),
                                                      true,
                                                    ),
                                                  ],
                                          );
                                        } else {
                                          return SizedBox(
                                            height: 160,
                                            child: ListView(
                                              scrollDirection: Axis.horizontal,
                                              children: isLoadingCharts
                                                  ? [
                                                      const SizedBox(width: 4),
                                                      DashboardShimmer.buildMetricCardShimmer(
                                                        context,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      DashboardShimmer.buildMetricCardShimmer(
                                                        context,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      DashboardShimmer.buildMetricCardShimmer(
                                                        context,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      DashboardShimmer.buildMetricCardShimmer(
                                                        context,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      DashboardShimmer.buildMetricCardShimmer(
                                                        context,
                                                      ),
                                                      const SizedBox(width: 4),
                                                    ]
                                                  : [
                                                      _buildMetricCard(
                                                        context,
                                                        'Monthly Revenue',
                                                        HugeIcons
                                                            .strokeRoundedMoney04,
                                                        const Color(0xFF4CAF50),
                                                        _getMetricValueWithCurrency(
                                                          monthlyRevenue,
                                                        ),
                                                        'This month\'s sales',
                                                        _formatCurrencyFull(
                                                          monthlyRevenue,
                                                        ),
                                                        true,
                                                      ),
                                                      _buildMetricCard(
                                                        context,
                                                        'Weekly Revenue',
                                                        HugeIcons
                                                            .strokeRoundedMoneyBag02,
                                                        const Color(0xFF2196F3),
                                                        _getMetricValueWithCurrency(
                                                          weeklyRevenue,
                                                        ),
                                                        'Current week (ISO)',
                                                        _formatCurrencyFull(
                                                          weeklyRevenue,
                                                        ),
                                                        true,
                                                      ),
                                                      _buildMetricCard(
                                                        context,
                                                        'Conversion Rate',
                                                        HugeIcons
                                                            .strokeRoundedTarget03,
                                                        const Color(0xFFFF9800),
                                                        isLoadingCharts
                                                            ? '...'
                                                            : '${conversionRate?.toStringAsFixed(1) ?? '0'}%',
                                                        'Quote to sale ratio',
                                                        isLoadingCharts
                                                            ? '...'
                                                            : '${conversionRate?.toStringAsFixed(1) ?? '0'}%',
                                                      ),
                                                      _buildMetricCard(
                                                        context,
                                                        'Untaxed Invoices',
                                                        HugeIcons
                                                            .strokeRoundedInvoice03,
                                                        const Color(0xFF9C27B0),
                                                        _getMetricValueWithCurrency(
                                                          totalUntaxedInvoiceAmount,
                                                        ),
                                                        'Total untaxed amount',
                                                        _formatCurrencyFull(
                                                          totalUntaxedInvoiceAmount,
                                                        ),
                                                        true,
                                                      ),
                                                      _buildMetricCard(
                                                        context,
                                                        'Avg Deal Size',
                                                        HugeIcons
                                                            .strokeRoundedCalculator,
                                                        const Color(0xFFFF5722),
                                                        _getMetricValue(
                                                          averageDealSize,
                                                        ),
                                                        'Average order value',
                                                        _formatCurrencyFull(
                                                          averageDealSize,
                                                        ),
                                                        true,
                                                      ),
                                                      _buildMetricCard(
                                                        context,
                                                        'Outstanding',
                                                        HugeIcons
                                                            .strokeRoundedMoney01,
                                                        const Color(0xFF607D8B),
                                                        _getMetricValue(
                                                          outstandingReceivables,
                                                        ),
                                                        'Total receivables',
                                                        _formatCurrencyFull(
                                                          outstandingReceivables,
                                                        ),
                                                        true,
                                                      ),
                                                    ],
                                            ),
                                          );
                                        }
                                      },
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),

                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final isNarrow = ResponsiveLayout.isMobile(
                                    context,
                                  );
                                  if (isNarrow) {
                                    return Column(
                                      children: [
                                        SmartSuggestionsWidget(
                                          suggestions: _getSmartSuggestions(),
                                          isLoading:
                                              (isLoadingDashboardAll ||
                                              isLoadingCharts),
                                          isDark: isDark,
                                        ),
                                        const SizedBox(height: 16),
                                        Consumer<LastOpenedProvider>(
                                          builder: (context, lastOpenedProvider, child) {
                                            return RecentItemsWidget(
                                              recentItems: lastOpenedProvider
                                                  .items
                                                  .map(
                                                    (item) => {
                                                      'type': item.type,
                                                      'name': item.title,
                                                      'subtitle': item.subtitle,
                                                      'lastModified':
                                                          lastOpenedProvider
                                                              .getTimeAgo(
                                                                item.lastAccessed,
                                                              ),
                                                      'icon':
                                                          LastOpenedProvider.iconFromKey(
                                                            item.iconKey,
                                                          ),
                                                      'onTap': () =>
                                                          _navigateToLastOpenedItem(
                                                            item,
                                                          ),
                                                    },
                                                  )
                                                  .toList(),
                                              isLoading: false,
                                              isDark: isDark,
                                              onViewAll: () {},
                                            );
                                          },
                                        ),
                                      ],
                                    );
                                  }
                                  return IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: SmartSuggestionsWidget(
                                            suggestions: _getSmartSuggestions(),
                                            isLoading:
                                                (isLoadingDashboardAll ||
                                                isLoadingCharts),
                                            isDark: isDark,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Consumer<LastOpenedProvider>(
                                            builder: (context, lastOpenedProvider, child) {
                                              return RecentItemsWidget(
                                                recentItems: lastOpenedProvider
                                                    .items
                                                    .map(
                                                      (item) => {
                                                        'type': item.type,
                                                        'name': item.title,
                                                        'subtitle':
                                                            item.subtitle,
                                                        'lastModified':
                                                            lastOpenedProvider
                                                                .getTimeAgo(
                                                                  item.lastAccessed,
                                                                ),
                                                        'icon':
                                                            LastOpenedProvider.iconFromKey(
                                                              item.iconKey,
                                                            ),
                                                        'onTap': () =>
                                                            _navigateToLastOpenedItem(
                                                              item,
                                                            ),
                                                      },
                                                    )
                                                    .toList(),
                                                isLoading: false,
                                                isDark: isDark,
                                                onViewAll: () {},
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),

                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Business Overview',
                            style: TextStyle(
                              fontSize: 18,
                              fontFamily: GoogleFonts.inter().fontFamily,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 12)),

                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver:
                            (_isServerUnreachable || _isOffline || !_hasSession)
                            ? SliverToBoxAdapter(
                                child: _buildSectionErrorState(
                                  context,
                                  'Dashboard Overview',
                                  _getDashboardCardsErrorMessage(),
                                  HugeIcons.strokeRoundedDashboardSquare02,
                                ),
                              )
                            : isLoadingDashboardAll
                            ? SliverGrid(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount:
                                          ResponsiveLayout.getGridColumns(
                                            context,
                                          ),
                                      crossAxisSpacing: 16,
                                      mainAxisSpacing: 16,
                                      childAspectRatio:
                                          ResponsiveLayout.getCardAspectRatio(
                                            context,
                                          ),
                                    ),
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  return DashboardShimmer.buildDashboardCardShimmer(
                                    context,
                                  );
                                }, childCount: 4),
                              )
                            : SliverGrid(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount:
                                          ResponsiveLayout.getGridColumns(
                                            context,
                                          ),
                                      crossAxisSpacing: 16,
                                      mainAxisSpacing: 16,
                                      childAspectRatio:
                                          ResponsiveLayout.getCardAspectRatio(
                                            context,
                                          ),
                                    ),
                                delegate: SliverChildListDelegate([
                                  _buildDashboardCard(
                                    context,
                                    'Quotations',
                                    HugeIcons.strokeRoundedFiles01,
                                    const Color(0xFF4CAF50),
                                    _getCardCount(quotesCount),
                                    'Track sales quotations',
                                    () {
                                      final salesAppState = context
                                          .findAncestorStateOfType<
                                            HomeScaffoldState
                                          >();
                                      if (salesAppState != null) {
                                        salesAppState.changeTab(2);
                                      }
                                    },
                                  ),
                                  _buildDashboardCard(
                                    context,
                                    'Invoices',
                                    HugeIcons.strokeRoundedInvoice03,
                                    const Color(0xFFFF9800),
                                    _getCardCount(invoicesCount),
                                    'Monitor customer invoices',
                                    () {
                                      final salesAppState = context
                                          .findAncestorStateOfType<
                                            HomeScaffoldState
                                          >();
                                      if (salesAppState != null) {
                                        salesAppState.changeTab(4);
                                      }
                                    },
                                  ),
                                  _buildDashboardCard(
                                    context,
                                    'Customers',
                                    HugeIcons.strokeRoundedContact01,
                                    const Color(0xFF2196F3),
                                    _getCardCount(contactsCount),
                                    'Manage customer relationships',
                                    () {
                                      final salesAppState = context
                                          .findAncestorStateOfType<
                                            HomeScaffoldState
                                          >();
                                      if (salesAppState != null) {
                                        salesAppState.changeTab(1);
                                      }
                                    },
                                  ),
                                  _buildDashboardCard(
                                    context,
                                    'Products',
                                    HugeIcons.strokeRoundedPackageOpen,
                                    const Color(0xFF9C27B0),
                                    _getCardCount(productsCount),
                                    'View product catalog',
                                    () {
                                      final salesAppState = context
                                          .findAncestorStateOfType<
                                            HomeScaffoldState
                                          >();
                                      if (salesAppState != null) {
                                        salesAppState.changeTab(3);
                                      }
                                    },
                                  ),
                                ]),
                              ),
                      ),

                      const SliverToBoxAdapter(child: SizedBox(height: 24)),

                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Analytics & Insights',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontFamily: GoogleFonts.inter().fontFamily,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 16),

                              if (_isServerUnreachable ||
                                  _isOffline ||
                                  !_hasSession)
                                _buildSectionErrorState(
                                  context,
                                  'Analytics & Insights',
                                  _getAnalyticsErrorMessage(),
                                  HugeIcons.strokeRoundedAnalytics01,
                                )
                              else if (isLoadingCharts)
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildRevenueChartShimmer(context),

                                    const SizedBox(height: 16),
                                    _buildProductPerformanceShimmer(context),
                                  ],
                                )
                              else ...[
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final isNarrow = ResponsiveLayout.isMobile(
                                      context,
                                    );
                                    if (isNarrow) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          RevenueLineChart(
                                            revenueData: _getRevenueChartData(),
                                            isDark: isDark,
                                            primaryColor: Theme.of(
                                              context,
                                            ).primaryColor,
                                          ),
                                        ],
                                      );
                                    }
                                    return IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: RevenueLineChart(
                                              revenueData:
                                                  _getRevenueChartData(),
                                              isDark: isDark,
                                              primaryColor: Theme.of(
                                                context,
                                              ).primaryColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 18),

                                ProductPerformanceBarChart(
                                  productData: _getProductPerformanceData(),
                                  isDark: isDark,
                                  primaryColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  onBarTap: (int index) async {
                                    if (index < 0 ||
                                        index >= topProducts.length) {
                                      return;
                                    }
                                    final tapped = topProducts[index];
                                    final productId = tapped['id'];
                                    final productName = tapped['name'];

                                    try {
                                      final result =
                                          await OdooSessionManager.callKwWithCompany(
                                            {
                                              'model': 'product.product',
                                              'method': 'search_read',
                                              'args': [
                                                [
                                                  ['id', '=', productId],
                                                  ['active', '=', true],
                                                ],
                                              ],
                                              'kwargs': {
                                                'fields': [
                                                  'id',
                                                  'name',
                                                  'list_price',
                                                  'qty_available',
                                                  'default_code',
                                                  'image_1920',
                                                  'barcode',
                                                  'categ_id',
                                                  'product_tmpl_id',
                                                  'create_date',
                                                  'description_sale',
                                                  'weight',
                                                  'volume',
                                                  'standard_price',
                                                  'taxes_id',
                                                  'active',
                                                  'sale_ok',
                                                  'purchase_ok',
                                                  'type',
                                                ],
                                                'limit': 1,
                                              },
                                            },
                                          );

                                      if (result is List && result.isNotEmpty) {
                                        final productData = result[0];

                                        final productObj = Product.fromJson(
                                          productData,
                                        );
                                        if (context.mounted) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  ProductDetailsPage(
                                                    product: productObj,
                                                  ),
                                            ),
                                          );
                                        }
                                      } else {
                                        if (context.mounted) {
                                          CustomSnackbar.showError(
                                            context,
                                            'Product not found or inactive',
                                          );
                                        }
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        CustomSnackbar.showError(
                                          context,
                                          'Error loading product details',
                                        );
                                      }
                                    }
                                  },
                                ),
                                const SizedBox(height: 36),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    String value,
    String subtitle, [
    String? tooltip,
    bool isApproximate = false,
  ]) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: const BoxConstraints(
        minWidth: 160,
        maxWidth: 240,
        minHeight: 120,
      ),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.05),
            blurRadius: 4,
            spreadRadius: 2,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[300] : Colors.grey[600],
              letterSpacing: 0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 12),

          Tooltip(
            message: tooltip ?? value,
            triggerMode: TooltipTriggerMode.longPress,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (isApproximate)
                  Text(
                    '≈ ',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      color: isDark ? Colors.grey[400] : Colors.grey[500],
                    ),
                  ),
                Flexible(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.grey[900],
                      letterSpacing: -0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey[400] : Colors.grey[500],
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 12),
          Container(
            height: 3,
            width: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    String count,
    String subtitle,
    VoidCallback onTap,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,

      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[850] : Colors.white,
          borderRadius: BorderRadius.circular(12),

          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withOpacity(0.15)
                  : color.withOpacity(0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          count,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? color.withOpacity(0.6)
                          : color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: isDark ? Colors.white : color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _forceRefreshAllData() async {
    _isForceRefreshing = true;

    _isServerUnreachable = false;
    _clearAllCaches();
    if (mounted) {
      setState(() {
        isLoadingDashboardAll = true;
        isLoadingCharts = true;
        _dashboardErrorMessage = null;
        _isServerUnreachable = false;
      });
    }

    try {
      final sessionService = context.read<SessionService>();

      final results = await Future.wait([
        _fetchUserInfo(forceRefresh: true).catchError((e) {
          final errorString = e.toString().toLowerCase();
          if (errorString.contains('connection refused') ||
              errorString.contains('connection timed out') ||
              errorString.contains('network is unreachable')) {
            throw e;
          }
          return null;
        }),
        _fetchDashboardCounts(forceRefresh: true).catchError((e) {
          final errorString = e.toString().toLowerCase();
          if (errorString.contains('connection refused') ||
              errorString.contains('connection timed out') ||
              errorString.contains('network is unreachable')) {
            throw e;
          }
          return null;
        }),
        _fetchSalesMetrics(forceRefresh: true).catchError((e) {
          final errorString = e.toString().toLowerCase();
          if (errorString.contains('connection refused') ||
              errorString.contains('connection timed out') ||
              errorString.contains('network is unreachable')) {
            throw e;
          }
          return null;
        }),
      ]);

      _forceRefreshContinueWorkingItems();

      if (mounted) {
        setState(() {
          _dashboardErrorMessage = null;
          _isServerUnreachable = false;
        });

        try {
          sessionService.clearServerUnreachableState();
        } catch (e) {}
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _dashboardErrorMessage =
              'Failed to refresh dashboard data. Please try again.';

          final errorString = e.toString().toLowerCase();
          if (errorString.contains('connection refused') ||
              errorString.contains('connection timed out') ||
              errorString.contains('network is unreachable')) {
            _isServerUnreachable = true;
          }
        });
      }
    } finally {
      _isForceRefreshing = false;

      if (mounted) {
        setState(() {
          isLoadingDashboardAll = false;
          isLoadingCharts = false;
        });
      }
    }
  }

  void _onSessionChanged() {
    if (!mounted) return;

    userName = null;
    userAvatar = null;
    userLogin = null;

    try {
      final svc = context.read<SessionService>();
      if (svc.isRefreshing) {
        setState(() {});
        return;
      }
    } catch (_) {}

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        setState(() {
          isLoadingDashboardAll = true;
          isLoadingCharts = true;
          _initialLoadComplete = false;
        });

        _clearAllCaches();
        _checkConnectivityAndSession();
      } catch (e) {
        if (e.toString().contains('disposed') ||
            e.toString().contains('deactivated')) {
          _handlingSessionChange = false;
          return;
        }
      }
      _handlingSessionChange = false;
    });
  }

  String _getSalesPerformanceErrorMessage() {
    if (_isOffline) {
      return 'No internet connection. Sales metrics require network access to load from your Odoo server.';
    } else if (!_hasSession) {
      return 'Session expired. Please log in again to view your sales performance data.';
    } else if (_isServerUnreachable) {
      return 'Unable to connect to your Odoo server. Please check your server connection and try again.';
    }
    return 'Failed to load sales performance data. Please try again.';
  }

  String _getDashboardCardsErrorMessage() {
    if (_isOffline) {
      return 'No internet connection. Dashboard counts require network access to load from your Odoo server.';
    } else if (!_hasSession) {
      return 'Session expired. Please log in again to view your dashboard data.';
    } else if (_isServerUnreachable) {
      return 'Unable to connect to your Odoo server. Please check your server connection and try again.';
    }
    return 'Failed to load dashboard data. Please try again.';
  }

  String _getAnalyticsErrorMessage() {
    if (_isOffline) {
      return 'No internet connection. Analytics and charts require network access to load from your Odoo server.';
    } else if (!_hasSession) {
      return 'Session expired. Please log in again to view your analytics data.';
    } else if (_isServerUnreachable) {
      return 'Unable to connect to your Odoo server. Please check your server connection and try again.';
    }
    return 'Failed to load analytics data. Please try again.';
  }

  void _clearAllCaches() {
    _clearStaticCaches();
  }

  Future<void> _handlePullToRefresh() async {
    if (!mounted) return;

    try {
      _clearAllCaches();

      if (mounted) {
        setState(() {
          isLoadingDashboardAll = true;
          isLoadingCharts = true;
          _dashboardErrorMessage = null;
        });
      }

      await Future.wait([
        _fetchUserInfo(forceRefresh: true),
        _fetchDashboardCounts(forceRefresh: true),
        _fetchSalesMetrics(forceRefresh: true),
      ]);

      _forceRefreshContinueWorkingItems();

      if (mounted) {
        setState(() {
          isLoadingDashboardAll = false;
          isLoadingCharts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoadingDashboardAll = false;
          isLoadingCharts = false;
          _dashboardErrorMessage = 'Failed to refresh data. Please try again.';
        });
      }
    }
  }

  void _resetDashboardState() {
    if (!mounted) return;
    setState(() {
      userName = null;
      userLogin = null;
      userAvatar = null;
      contactsCount = null;
      quotesCount = null;
      invoicesCount = null;
      productsCount = null;
      approvalsCount = null;
      documentsCount = null;
      monthlyRevenue = null;
      weeklyRevenue = null;
      conversionRate = null;
      averageDealSize = null;
      overdueInvoicesCount = null;
      expiredQuotesCount = null;
      todayTasksCount = null;
      outstandingReceivables = null;
      _dashboardErrorMessage = null;
      _initialLoadComplete = false;
      isLoadingDashboardAll = false;
    });
  }
}

Widget _buildRevenueChartShimmer(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
  final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
  final cardBg = isDark ? Colors.grey[850]! : Colors.white;
  final border = isDark ? Colors.grey[800]! : Colors.grey[200]!;

  return Shimmer.fromColors(
    baseColor: base,
    highlightColor: highlight,
    child: Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 16,
                width: 120,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildSalesBreakdownShimmer(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
  final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
  final cardBg = isDark ? Colors.grey[850]! : Colors.white;
  final border = isDark ? Colors.grey[800]! : Colors.grey[200]!;

  return Shimmer.fromColors(
    baseColor: base,
    highlightColor: highlight,
    child: Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 16,
                width: 140,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: base,
                      shape: BoxShape.rectangle,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 1,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (i) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: base,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 12,
                                decoration: BoxDecoration(
                                  color: base,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
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

Widget _buildSectionErrorState(
  BuildContext context,
  String sectionTitle,
  String errorMessage,
  IconData icon,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: isDark ? Colors.grey[850] : Colors.grey[50],
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        width: 1,
      ),
    ),
    child: Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 24, color: Colors.orange.shade400),
        ),
        const SizedBox(height: 16),
        Text(
          'Unable to load $sectionTitle',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          errorMessage,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

Widget _buildProductPerformanceShimmer(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
  final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
  final cardBg = isDark ? Colors.grey[850]! : Colors.white;
  final border = isDark ? Colors.grey[800]! : Colors.grey[200]!;

  return Shimmer.fromColors(
    baseColor: base,
    highlightColor: highlight,
    child: Container(
      height: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 16,
                width: 110,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const Spacer(),
              Container(
                height: 14,
                width: 120,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
