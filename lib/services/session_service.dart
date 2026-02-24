import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../providers/company_provider.dart';
import '../providers/contact_provider.dart';
import '../providers/currency_provider.dart';
import '../providers/invoice_creation_provider.dart';
import '../providers/invoice_details_provider_enterprise.dart';
import '../providers/quotation_provider.dart';
import '../providers/stock_check_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/last_opened_provider.dart';
import '../providers/product_provider.dart';
import '../providers/login_provider.dart';
import 'odoo_session_manager.dart';
import 'odoo_api_service.dart';
import 'biometric_context_service.dart';
import '../screens/others/dashboard_screen.dart';
import '../screens/invoices/invoice_list_screen.dart';
import '../screens/products/product_list_screen.dart';
import '../services/payment_status_synchronizer.dart';
import '../home_scaffold.dart';

import '../widgets/custom_snackbar.dart';

class SessionService extends ChangeNotifier {
  static final SessionService instance = SessionService._internal();
  factory SessionService() => instance;
  SessionService._internal();

  OdooSessionModel? _currentSession;
  bool _isInitialized = false;
  bool _isCheckingSession = false;
  bool _isServerUnreachable = false;
  bool _isLoggingOut = false;
  bool _isLoading = false;
  List<Map<String, dynamic>> _storedAccounts = [];

  OdooSessionModel? get currentSession => _currentSession;
  bool get isInitialized => _isInitialized;
  bool get isCheckingSession => _isCheckingSession;
  bool get hasValidSession => _currentSession != null;
  bool get isServerUnreachable => _isServerUnreachable;
  bool get isLoggingOut => _isLoggingOut;
  List<Map<String, dynamic>> get storedAccounts => _storedAccounts;

  bool get isRefreshing => _isLoading;

  String? get _sessionKey {
    if (_currentSession == null) return null;
    final key =
        '${_currentSession!.userId}_${_currentSession!.database}_${_currentSession!.serverUrl}';
    return key.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
  }

  Future<OdooClient?> get client async {
    if (!hasValidSession) return null;
    return await getClient();
  }

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    OdooSessionManager.setSessionCallbacks(
      onSessionUpdated: (sessionModel) {
        updateSession(sessionModel);
      },
      onSessionCleared: () {
        clearSession();
      },
    );

    await checkSession();

    await _loadStoredAccounts();

    await fixCurrentSessionUserId();

    await cleanupCorruptedAccounts();

    if (_currentSession != null) {
      await _autoStoreCurrentSession();
    }

    _isInitialized = true;
    notifyListeners();
  }

  Future<bool> checkSession() async {
    if (_isCheckingSession) {
      return hasValidSession;
    }

    _isCheckingSession = true;
    _isServerUnreachable = false;
    notifyListeners();

    try {
      _currentSession = await OdooSessionManager.getCurrentSession();

      if (_currentSession != null) {
        try {
          final client = await OdooSessionManager.getClient();
          if (client == null) {
            _currentSession = null;
          } else {
            await _setAuthenticationTimestamp();
          }
        } catch (e) {
          if (_isServerUnreachableError(e) || _isHtmlResponseError(e)) {
            _isServerUnreachable = true;
          } else if (_isAuthenticationError(e)) {
            await logout();
          } else {}
        }
      } else {}
    } catch (e) {
      _currentSession = null;

      if (_isServerUnreachableError(e)) {
        _isServerUnreachable = true;
      }
    } finally {
      _isCheckingSession = false;
      _updateNamespacedProviders();
      notifyListeners();
    }

    return hasValidSession;
  }

  Future<void> updateSession(OdooSessionModel newSession) async {
    _currentSession = newSession;
    _isServerUnreachable = false;

    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      context.read<CompanyProvider>().initialize();
    }

    _updateNamespacedProviders();
    notifyListeners();
  }

  Future<void> clearSession() async {
    _currentSession = null;
    _isServerUnreachable = false;

    _updateNamespacedProviders();
    notifyListeners();
  }

  Future<void> logout() async {
    _isLoggingOut = true;
    notifyListeners();
    try {
      try {
        await OdooSessionManager.logout();
      } catch (e) {}

      await _clearStoredAccountsData();
      await _clearPasswordCaches();
      await _clearAllProviderData();
      await clearSession();
    } finally {
      _isLoggingOut = false;
      notifyListeners();

      _showLoggedOutNoticeSafely();
    }
  }

  void _showLoggedOutNoticeSafely() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final context = navigatorKey.currentContext;
        if (context != null && context.mounted) {
          await HapticFeedback.selectionClick();
          CustomSnackbar.showInfo(context, 'Logged out');
        }
      } catch (e) {}
    });
  }

  Future<void> _clearAllProviderData() async {
    BiometricContextService().reset();

    final context = navigatorKey.currentContext;
    if (context == null) {
      return;
    }

    try {
      try {
        final contactProvider = context.read<ContactProvider>();
        await contactProvider.clearData();
      } catch (e) {}

      try {
        final currencyProvider = context.read<CurrencyProvider>();
        await currencyProvider.clearData();
      } catch (e) {}

      try {
        final quotationProvider = context.read<QuotationProvider>();
        await quotationProvider.clearData();
      } catch (e) {}

      try {
        final stockCheckProvider = context.read<StockCheckProvider>();
        await stockCheckProvider.clearData();
      } catch (e) {}

      try {
        final invoiceDetailsProvider = context.read<InvoiceDetailsProvider>();
        await invoiceDetailsProvider.clearData();
      } catch (e) {}

      try {
        final createInvoiceProvider = context.read<CreateInvoiceProvider>();
        await createInvoiceProvider.clearData();
      } catch (e) {}

      try {
        final settingsProvider = context.read<SettingsProvider>();
        await settingsProvider.clearData();
      } catch (e) {}

      try {
        final companyProvider = context.read<CompanyProvider>();
        companyProvider.clearData();
      } catch (e) {}

      try {
        final settingsProvider = context.read<SettingsProvider>();
        await settingsProvider.clearCache();
      } catch (e) {}

      try {
        final lastOpenedProvider = context.read<LastOpenedProvider>();
        await lastOpenedProvider.clearItems();
      } catch (e) {}

      try {
        final productProvider = context.read<ProductProvider>();
        productProvider.clearData();
      } catch (e) {}

      try {
        final loginProvider = context.read<LoginProvider>();
        loginProvider.clearForm();
      } catch (e) {}

      await _clearSharedPreferencesCache();

      try {
        DashboardScreen.clearDashboardCache();
      } catch (e) {}

      try {
        _clearAllStaticCaches();
      } catch (e) {}
    } catch (e) {}
  }

  Future<void> _clearSharedPreferencesCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      final keysToPreserve = {
        'theme_mode',
        'permissions_asked',
        'first_launch',
        'app_version',
        'reduce_motion',
        'enable_notifications',
        'enable_sound_effects',
        'enable_haptic_feedback',
        'compact_view_mode',
        'auto_sync_enabled',
        'offline_mode_enabled',
        'sync_interval_minutes',
        'biometric_enabled',
        'hasSeenGetStarted',
        'previous_server_urls',
      };

      final keysToClear = allKeys
          .where(
            (key) =>
                !keysToPreserve.contains(key) &&
                !key.startsWith('password_') &&
                key != 'previous_server_urls' &&
                (key.startsWith('user_') ||
                    key.startsWith('cached_') ||
                    key.startsWith('dashboard_') ||
                    key.contains('profile') ||
                    key.contains('company') ||
                    key.contains('contact') ||
                    key.contains('invoice') ||
                    key.contains('quotation') ||
                    key.contains('product') ||
                    key.contains('order') ||
                    key.contains('stock') ||
                    key.contains('currency') ||
                    key == 'user_profile' ||
                    key == 'user_profile_write_date' ||
                    key == 'company_info' ||
                    key == 'available_languages' ||
                    key == 'available_currencies' ||
                    key == 'available_timezones' ||
                    key.startsWith('last_opened_items') ||
                    key == 'langs_updated_at' ||
                    key == 'currs_updated_at' ||
                    key == 'tz_updated_at'),
          )
          .toList();

      for (final key in keysToClear) {
        await prefs.remove(key);
      }
    } catch (e) {}
  }

  Future<void> refreshSessionFromStorage() async {
    _isCheckingSession = true;
    notifyListeners();

    try {
      _currentSession = await OdooSessionManager.getCurrentSession();
      _isServerUnreachable = false;
    } catch (e) {
      _currentSession = null;
    } finally {
      _isCheckingSession = false;
      notifyListeners();
    }
  }

  bool _isServerUnreachableError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    final isUnreachable =
        errorString.contains('socketexception') ||
        errorString.contains('connection refused') ||
        errorString.contains('connection timeout') ||
        errorString.contains('host unreachable') ||
        errorString.contains('no route to host') ||
        errorString.contains('network is unreachable') ||
        errorString.contains('failed to connect') ||
        errorString.contains('connection failed');

    return isUnreachable;
  }

  bool _isHtmlResponseError(dynamic error) {
    final errorString = error.toString().toLowerCase();

    final isHtml =
        errorString.contains('<html>') ||
        errorString.contains('server returned html instead of json') ||
        errorString.contains('unexpected character (at character 1)') ||
        errorString.contains('formatexception');
    return isHtml;
  }

  bool _isAuthenticationError(dynamic error) {
    final s = error.toString().toLowerCase();

    final isAuth =
        s.contains('wrong login/password') ||
        s.contains('invalid database') ||
        s.contains('invalid db') ||
        s.contains('bad credentials') ||
        s.contains('login or password');
    return isAuth;
  }

  Future<void> refreshSession() async {
    await checkSession();
  }

  Future<void> refreshAllData({bool bypassLoadingCheck = false}) async {
    if (_isLoading && !bypassLoadingCheck) {
      return;
    }
    _isLoading = true;
    notifyListeners();

    final context = navigatorKey.currentContext;
    if (context == null) {
      if (!bypassLoadingCheck) {
        _isLoading = false;
        notifyListeners();
      }
      return;
    }

    if (!context.mounted) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScaffold()),
        (route) => false,
      );

      await Future.delayed(Duration.zero);

      await _clearAllProviderData();

      if (!context.mounted) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      final contactProvider = context.read<ContactProvider>();
      final quotationProvider = context.read<QuotationProvider>();
      final currencyProvider = context.read<CurrencyProvider>();
      final settingsProvider = context.read<SettingsProvider>();
      final productProvider = context.read<ProductProvider>();

      Future.wait<dynamic>([
        contactProvider.refreshContacts().catchError((e) {}),
        quotationProvider.loadQuotations().catchError((e) {}),
        currencyProvider.fetchCompanyCurrency().catchError((e) {}),
        settingsProvider.initialize().catchError((e) {}),
        productProvider.fetchProducts(forceRefresh: true).catchError((e) {}),
      ]).catchError((e) {
        return <void>[];
      });
    } finally {
      await Future.delayed(const Duration(milliseconds: 500));
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<OdooClient?> getClient() async {
    if (!hasValidSession) {
      return null;
    }

    try {
      final client = await OdooSessionManager.getClient();
      return client;
    } catch (e) {
      if (_isServerUnreachableError(e) || _isHtmlResponseError(e)) {
        _isServerUnreachable = true;
        notifyListeners();

        return null;
      }

      if (_isAuthenticationError(e)) {
        await logout();
        return null;
      }

      return null;
    }
  }

  void clearServerUnreachableState() {
    _isServerUnreachable = false;
    notifyListeners();
  }

  Future<void> _loadStoredAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> storedAccountsJson =
          prefs.getStringList('stored_accounts') ?? [];

      _storedAccounts = storedAccountsJson
          .map((json) {
            try {
              final decoded = Map<String, dynamic>.from(jsonDecode(json));
              return decoded;
            } catch (e) {
              return null;
            }
          })
          .where((account) => account != null)
          .cast<Map<String, dynamic>>()
          .toList();

      await _cleanupDuplicateAccounts();

      await _autoStoreCurrentSession();

      for (int i = 0; i < _storedAccounts.length; i++) {}
      notifyListeners();
    } catch (e) {
      _storedAccounts = [];
    }
  }

  Future<void> _autoStoreCurrentSession() async {
    if (_currentSession == null) return;

    final currentExists = _storedAccounts.any(
      (account) =>
          account['userId'] == _currentSession!.userId.toString() &&
          account['serverUrl'] == _currentSession!.serverUrl &&
          account['database'] == _currentSession!.database,
    );

    if (!currentExists) {
      await storeAccount(_currentSession!, '');
    }
  }

  Future<void> _cleanupDuplicateAccounts() async {
    final uniqueAccounts = <String, Map<String, dynamic>>{};

    for (final account in _storedAccounts) {
      final userId = account['userId']?.toString() ?? '';
      final serverUrl = account['serverUrl']?.toString() ?? '';
      final database = account['database']?.toString() ?? '';

      if (userId.isEmpty || serverUrl.isEmpty || database.isEmpty) {
        continue;
      }

      final key = '${userId}_${serverUrl}_$database';

      if (!uniqueAccounts.containsKey(key)) {
        uniqueAccounts[key] = account;
      } else {
        final existing = uniqueAccounts[key]!;
        final currentHasPassword =
            account['password']?.toString().isNotEmpty == true;
        final existingHasPassword =
            existing['password']?.toString().isNotEmpty == true;

        if (currentHasPassword && !existingHasPassword) {
          uniqueAccounts[key] = account;
        } else {}
      }
    }

    final originalCount = _storedAccounts.length;
    _storedAccounts = uniqueAccounts.values.toList();

    if (_storedAccounts.length != originalCount) {
      await _saveStoredAccountsWithRetry();
    }
  }

  Future<void> storeAccount(OdooSessionModel session, String password) async {
    try {
      String? imageBase64;
      String userDisplayName = session.userLogin;

      try {
        final client = await getClient();

        if (client != null && session.userId != null) {
          final userDetails = await client.callKw({
            'model': 'res.users',
            'method': 'read',
            'args': [
              [session.userId],
              ['name', 'image_1920'],
            ],
          });

          if (userDetails is List && userDetails.isNotEmpty) {
            final user = userDetails.first as Map;
            final n = user['name'];
            if (n != null && n != false) {
              userDisplayName = n.toString();
            }
            final img = user['image_1920'];
            if (img != null && img != false) {
              imageBase64 = img.toString();
            }
          }
        }
      } catch (e) {}

      final accountData = {
        'id': (session.userId ?? 0).toString(),
        'name': userDisplayName,
        'email': session.userLogin,
        'url': session.serverUrl.trim(),
        'database': session.database,
        'username': session.userLogin,
        'isCurrent': true,
        'lastLogin': DateTime.now().toIso8601String(),
        'imageBase64': imageBase64?.isNotEmpty == true ? imageBase64 : null,

        'userId': (session.userId ?? 0).toString(),
        'userName': userDisplayName,
        'serverUrl': session.serverUrl,
        'password': password,
        'sessionId': session.sessionId,
      };

      for (var account in _storedAccounts) {
        account['isCurrent'] = false;
      }

      _storedAccounts.removeWhere((account) {
        final sameUrlDb =
            account['url'] == accountData['url'] &&
            account['database'] == accountData['database'];
        if (!sameUrlDb) return false;

        final accId = account['id']?.toString() ?? '0';
        return accId == '0' || accId == accountData['id'];
      });

      if (_storedAccounts.isEmpty) {
        _storedAccounts.add(accountData);
      } else {
        _storedAccounts.insert(0, accountData);
      }

      await _saveStoredAccountsWithRetry();

      if (password.isNotEmpty) {
        await _storePasswordWithMultiplePatterns(session, password);
      }

      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _storePasswordWithMultiplePatterns(
    OdooSessionModel session,
    String password,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(
        'password_${session.userId}_${session.database}',
        password,
      );
      await prefs.setString(
        'password_${session.userLogin}_${session.database}',
        password,
      );

      if (session.userLogin.contains('@')) {
        await prefs.setString(
          'password_${session.userLogin}_${session.database}',
          password,
        );
      }
    } catch (e) {}
  }

  Future<String?> _retrievePasswordWithMultiplePatterns(
    Map<String, dynamic> accountData,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = accountData['id'] ?? accountData['userId'];
      final username = accountData['username'] ?? accountData['email'];
      final database = accountData['database'];

      List<String> passwordKeys = [
        'password_${userId}_$database',
        'password_${username}_$database',
      ];

      if (username?.toString().contains('@') == true) {
        passwordKeys.add('password_${username}_$database');
      }

      if (accountData['password']?.toString().isNotEmpty == true) {
        return accountData['password'].toString();
      }

      for (String key in passwordKeys) {
        final password = prefs.getString(key);
        if (password != null && password.isNotEmpty) {
          return password;
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveStoredAccountsWithRetry() async {
    int maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        for (int i = 0; i < _storedAccounts.length; i++) {}

        final prefs = await SharedPreferences.getInstance();

        final biometricEnabled = prefs.getBool('biometric_enabled');

        final updatedAccountsJson = _storedAccounts
            .map((account) => jsonEncode(account))
            .toList();

        await prefs.setStringList('stored_accounts', updatedAccountsJson);

        if (biometricEnabled != null) {
          await prefs.setBool('biometric_enabled', biometricEnabled);
        }

        return;
      } catch (e) {
        if (attempt == maxRetries) {
        } else {
          await Future.delayed(Duration(milliseconds: 100 * attempt));
        }
      }
    }
  }

  Future<void> removeStoredAccount(int accountIndex) async {
    if (accountIndex < 0 || accountIndex >= _storedAccounts.length) {
      return;
    }

    _storedAccounts.removeAt(accountIndex);
    await _saveStoredAccountsWithRetry();
    notifyListeners();
  }

  Future<bool> switchToAccount(OdooSessionModel newSession) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (_currentSession != null &&
          (_currentSession!.userId != newSession.userId ||
              _currentSession!.serverUrl != newSession.serverUrl ||
              _currentSession!.database != newSession.database)) {
        final currentExists = _storedAccounts.any(
          (account) =>
              account['userId']?.toString() ==
                  _currentSession!.userId?.toString() &&
              account['serverUrl'] == _currentSession!.serverUrl &&
              account['database'] == _currentSession!.database,
        );

        if (!currentExists) {
          await storeAccount(_currentSession!, '');
        }
      }

      _currentSession = newSession.copyWith(
        selectedCompanyId: null,
        allowedCompanyIds: [],
      );

      await OdooSessionManager.updateSession(newSession);

      OdooApiService().updateSession(newSession);

      await refreshAllData(bypassLoadingCheck: true);

      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.pushNamedAndRemoveUntil(
          '/init',
          (route) => false,
        );
      }

      _isLoading = false;
      notifyListeners();

      return true;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateSessionDirectly(OdooSessionModel newSession) async {
    try {
      await _clearUserSpecificData();

      await Future.delayed(const Duration(milliseconds: 100));

      _currentSession = newSession;

      await OdooSessionManager.updateSession(newSession);

      await _setAuthenticationTimestamp();

      notifyListeners();

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _clearUserSpecificData() async {
    final context = navigatorKey.currentContext;
    if (context == null) {
      return;
    }

    try {
      final providersToClear = [
        () async {
          final contactProvider = context.read<ContactProvider>();
          await contactProvider.clearData();
        },
        () async {
          final quotationProvider = context.read<QuotationProvider>();
          await quotationProvider.clearData();
        },
        () async {
          final invoiceDetailsProvider = context.read<InvoiceDetailsProvider>();
          await invoiceDetailsProvider.clearData();
        },
        () async {
          final createInvoiceProvider = context.read<CreateInvoiceProvider>();
          await createInvoiceProvider.clearData();
        },
        () async {
          final stockCheckProvider = context.read<StockCheckProvider>();
          await stockCheckProvider.clearData();
        },
        () async {
          final currencyProvider = context.read<CurrencyProvider>();
          await currencyProvider.clearData();
        },
        () async {
          final settingsProvider = context.read<SettingsProvider>();
          await settingsProvider.clearData();
        },
        () async {
          final lastOpenedProvider = context.read<LastOpenedProvider>();
          await lastOpenedProvider.clearItems();
        },
        () async {
          final productProvider = context.read<ProductProvider>();
          productProvider.clearData();
        },
      ];

      await Future.wait(
        providersToClear.map((clearFunction) async {
          try {
            await clearFunction();
          } catch (e) {}
        }),
      );

      await _clearUserSpecificCache();

      try {
        DashboardScreen.clearDashboardCache();
      } catch (e) {}

      try {
        InvoiceListScreen.clearInvoiceCache();
      } catch (e) {}
    } catch (e) {}
  }

  void _updateNamespacedProviders() {
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      try {
        final lastOpenedProvider = context.read<LastOpenedProvider>();
        lastOpenedProvider.updateSession(_sessionKey);
      } catch (e) {}
    }
  }

  Future<void> _clearUserSpecificCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final userSpecificKeys = [
        'user_profile',
        'company_info',
        'langs_updated_at',
        'currs_updated_at',
        'tz_updated_at',
        'dashboard_cache',
        'contacts_cache',
        'quotations_cache',
        'invoices_cache',
        'products_cache',
        'stock_cache',
      ];

      for (final key in userSpecificKeys) {
        if (prefs.containsKey(key)) {
          await prefs.remove(key);
        }
      }
    } catch (e) {}
  }

  Future<void> _clearStoredAccountsData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final accountKeys = [
        'stored_accounts',
        'stored_accounts_backup',
        'stored_accounts_timestamp',
      ];

      for (final key in accountKeys) {
        if (prefs.containsKey(key)) {
          await prefs.remove(key);
        }
      }

      _storedAccounts.clear();
    } catch (e) {}
  }

  Future<void> _clearPasswordCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      final passwordKeys = allKeys
          .where((key) => key.startsWith('password_'))
          .toList();

      for (final key in passwordKeys) {
        await prefs.remove(key);
      }
    } catch (e) {}
  }

  void _clearAllStaticCaches() {
    try {
      InvoiceListScreen.clearInvoiceCache();
    } catch (e) {}

    try {
      ProductListScreenState.clearProductCache();
    } catch (e) {}

    try {
      PaymentStatusSynchronizer.clearAllCaches();
    } catch (e) {}

    _clearScreenStaticCaches();
    DashboardScreen.clearDashboardCache();
  }

  void _clearScreenStaticCaches() {
    try {} catch (e) {}

    try {} catch (e) {}

    try {} catch (e) {}
  }

  Future<void> _setAuthenticationTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt('lastSuccessfulAuth', currentTime);
    } catch (e) {}
  }

  Future<bool> switchToStoredAccount(int accountIndex) async {
    if (accountIndex < 0 || accountIndex >= _storedAccounts.length) {
      return false;
    }

    final accountData = _storedAccounts[accountIndex];

    try {
      final sessionId = accountData['sessionId']?.toString();
      final serverUrl = accountData['serverUrl']?.toString() ?? '';
      final database = accountData['database']?.toString() ?? '';
      final username =
          accountData['username']?.toString() ??
          accountData['userName']?.toString() ??
          '';
      String cachedPassword = accountData['password']?.toString() ?? '';

      if (sessionId != null && sessionId.isNotEmpty) {
        final ok = await OdooSessionManager.loginWithSessionId(
          serverUrl: serverUrl,
          database: database,
          userLogin: username,
          password: cachedPassword,
          sessionId: sessionId,
        );
        if (ok) {
          final newSession = await OdooSessionManager.getCurrentSession();
          if (newSession != null) {
            return await switchToAccount(newSession);
          }
        } else {}
      }

      await _storeCurrentSessionIfNeeded(accountData);

      await _clearAllProviderData();

      String? password = await _retrievePasswordWithMultiplePatterns(
        accountData,
      );

      if (password == null || password.isEmpty) {
        return false;
      }

      OdooSessionModel? newSession;
      int attempts = 0;
      const maxAttempts = 3;

      while (attempts < maxAttempts && newSession == null) {
        attempts++;
        try {
          newSession = await OdooSessionManager.authenticate(
            serverUrl: accountData['serverUrl'],
            database: accountData['database'],
            username: accountData['username'],
            password: password,
          );

          if (newSession != null) {
            break;
          }
        } catch (e) {
          if (_isConnectionError(e)) {
            if (attempts < maxAttempts) {
              await Future.delayed(Duration(milliseconds: attempts * 500));
              continue;
            }
          } else if (_isCredentialError(e) ||
              e.toString().contains('Empty password')) {
            accountData['needsReauth'] = 'true';
            await _saveStoredAccountsWithRetry();
            notifyListeners();
            throw Exception(
              'Account requires re-authentication - ${e.toString()}',
            );
          } else {
            rethrow;
          }
        }
      }

      if (newSession == null) {
        throw Exception('Authentication failed after $maxAttempts attempts');
      }

      accountData['sessionId'] = newSession.sessionId;
      accountData['lastLogin'] = DateTime.now().millisecondsSinceEpoch
          .toString();
      accountData.remove('needsReauth');
      await _saveStoredAccountsWithRetry();

      return await switchToAccount(newSession);
    } catch (e) {
      rethrow;
    }
  }

  bool _isConnectionError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('connection reset') ||
        errorString.contains('connection refused') ||
        errorString.contains('connection timeout') ||
        errorString.contains('socketexception') ||
        errorString.contains('timeout') ||
        errorString.contains('network is unreachable') ||
        errorString.contains('failed to connect');
  }

  bool _isCredentialError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('access denied') ||
        errorString.contains('wrong login/password') ||
        errorString.contains('empty password') ||
        errorString.contains('invalid credentials') ||
        errorString.contains('authentication failed') ||
        errorString.contains('account needs re-authentication') ||
        errorString.contains('re-authentication') ||
        errorString.contains('expired credentials');
  }

  Future<void> cleanupCorruptedAccounts() async {
    final originalCount = _storedAccounts.length;

    _storedAccounts.removeWhere((account) {
      final userId = account['userId'];
      final isCorrupted =
          userId == null ||
          userId.toString().isEmpty ||
          userId.toString() == 'null';
      if (isCorrupted) {}
      return isCorrupted;
    });

    final cleanedCount = _storedAccounts.length;

    if (originalCount != cleanedCount) {
      await _saveStoredAccountsWithRetry();
      notifyListeners();
    }
  }

  Future<void> fixCurrentSessionUserId() async {
    final currentUserId = _currentSession?.userId;
    if (currentUserId == null || currentUserId == 0) {
      try {
        final client = await getClient();
        final revealedUserId = client?.sessionId?.userId;

        if (revealedUserId != null && revealedUserId != 0) {
          final updatedSession = _currentSession!.copyWith(
            userId: revealedUserId,
          );
          await OdooSessionManager.updateSession(updatedSession);
          _currentSession = updatedSession;

          bool changed = false;
          for (var account in _storedAccounts) {
            final accUserIdStr = account['userId']?.toString();
            if ((accUserIdStr == null ||
                    accUserIdStr == '0' ||
                    accUserIdStr == 'null') &&
                account['userName'] == _currentSession!.userLogin &&
                account['serverUrl'] == _currentSession!.serverUrl &&
                account['database'] == _currentSession!.database) {
              account['userId'] = revealedUserId.toString();
              changed = true;
            }
          }

          if (changed) {
            await _saveStoredAccountsWithRetry();
          }
          notifyListeners();
        }
      } catch (e) {}
    }
  }

  Future<void> _storeCurrentSessionIfNeeded(
    Map<String, dynamic> targetAccount,
  ) async {
    if (_currentSession == null) return;

    final isDifferentAccount =
        _currentSession!.userId.toString() != targetAccount['userId'] ||
        _currentSession!.serverUrl != targetAccount['serverUrl'] ||
        _currentSession!.database != targetAccount['database'];

    if (!isDifferentAccount) return;

    final currentExists = _storedAccounts.any(
      (account) =>
          account['userId'] == _currentSession!.userId.toString() &&
          account['serverUrl'] == _currentSession!.serverUrl &&
          account['database'] == _currentSession!.database,
    );

    if (!currentExists) {
      await storeAccount(_currentSession!, '');
    }
  }

  List<Map<String, dynamic>> getUniqueStoredAccounts() {
    final uniqueAccounts = <String, Map<String, dynamic>>{};

    for (int i = 0; i < _storedAccounts.length; i++) {
      final account = _storedAccounts[i];
      final key =
          '${account['userId']}_${account['serverUrl']}_${account['database']}';
      uniqueAccounts[key] = Map<String, dynamic>.from(account);
    }

    if (_currentSession != null) {
      final currentKey =
          '${_currentSession!.userId}_${_currentSession!.serverUrl}_${_currentSession!.database}';

      if (!uniqueAccounts.containsKey(currentKey)) {
        uniqueAccounts[currentKey] = {
          'userId': _currentSession!.userId.toString(),
          'userName': _currentSession!.userLogin,
          'serverUrl': _currentSession!.serverUrl,
          'database': _currentSession!.database,
          'sessionId': _currentSession!.sessionId,
        };
      } else {
        uniqueAccounts[currentKey]!['sessionId'] = _currentSession!.sessionId;
        uniqueAccounts[currentKey]!['userName'] = _currentSession!.userLogin;
      }
    }

    return uniqueAccounts.values.toList();
  }

  bool isCurrentAccount(Map<String, dynamic> account) {
    if (_currentSession == null) return false;

    return account['userId'] == _currentSession!.userId.toString() &&
        account['serverUrl'] == _currentSession!.serverUrl &&
        account['database'] == _currentSession!.database;
  }

  Future<void> updateAccountCredentials(
    String username,
    String password,
  ) async {
    if (_currentSession == null) return;

    final accountIndex = _storedAccounts.indexWhere(
      (account) =>
          account['userId'] == _currentSession!.userId.toString() &&
          account['serverUrl'] == _currentSession!.serverUrl &&
          account['database'] == _currentSession!.database,
    );

    if (accountIndex != -1) {
      _storedAccounts[accountIndex]['password'] = password;
      _storedAccounts[accountIndex].remove('needsReauth');
      _storedAccounts[accountIndex]['lastLogin'] = DateTime.now()
          .millisecondsSinceEpoch
          .toString();
      await _saveStoredAccountsWithRetry();
    } else {
      await storeAccount(_currentSession!, password);
    }

    notifyListeners();
  }

  Future<void> clearReauthFlag(
    String userId,
    String serverUrl,
    String database,
  ) async {
    final accountIndex = _storedAccounts.indexWhere(
      (account) =>
          account['userId'] == userId &&
          account['serverUrl'] == serverUrl &&
          account['database'] == database,
    );

    if (accountIndex != -1) {
      _storedAccounts[accountIndex].remove('needsReauth');
      await _saveStoredAccountsWithRetry();
      notifyListeners();
    }
  }
}
