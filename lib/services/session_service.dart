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
import '../utils/odoo_binary.dart';
import '../utils/server_url_utils.dart';
import 'field_validation_service.dart';
import 'odoo_session_manager.dart';
import 'odoo_api_service.dart';
import 'permission_service.dart';
import 'biometric_context_service.dart';
import '../screens/others/dashboard_screen.dart';
import '../screens/invoices/invoice_list_screen.dart';
import '../screens/products/product_list_screen.dart';
import '../services/payment_status_synchronizer.dart';
import '../home_scaffold.dart';

import '../widgets/custom_snackbar.dart';
import 'sales_access.dart';
import '../utils/database_expiry.dart';

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

  /// Replaces the in-memory account list. Tests only — it seeds rows an
  /// already-affected device carries, which the public API deliberately can
  /// no longer create.
  @visibleForTesting
  void seedStoredAccountsForTesting(List<Map<String, dynamic>> accounts) {
    _storedAccounts = accounts;
  }

  /// Sets the session account matching is done against. Tests only.
  @visibleForTesting
  void setCurrentSessionForTesting(OdooSessionModel? session) {
    _currentSession = session;
  }

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
            // Credentials the server no longer accepts end this session and
            // nothing else. Calling `logout()` here deleted every saved
            // account and every cached password on the device because one of
            // them had a stale password.
            await endSessionKeepingAccounts();
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

  /// Identity of the account the company list was last loaded for.
  String? _companiesLoadedFor;

  Future<void> updateSession(OdooSessionModel newSession) async {
    _currentSession = newSession;
    _isServerUnreachable = false;

    final accountKey =
        '${newSession.serverUrl}|${newSession.database}|${newSession.userId}';
    if (_companiesLoadedFor != accountKey) {
      _companiesLoadedFor = accountKey;
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        context.read<CompanyProvider>().initialize();
      }
    }

    _updateNamespacedProviders();
    notifyListeners();
  }

  Future<void> clearSession() async {
    _companiesLoadedFor = null;
    _currentSession = null;
    _isServerUnreachable = false;

    _updateNamespacedProviders();
    notifyListeners();
  }

  /// Ends the current account's session — the other saved accounts stay.
  ///
  /// This is the only way the app ends a session the user did not ask to end.
  /// `SalesAccessGuard` and `DatabaseExpiryGuard` already sign people out
  /// exactly this way; this gives the two automatic checks in this file the
  /// same contract instead of a second, heavier one.
  ///
  /// Saved accounts and their passwords belong to the person using the phone,
  /// not to the session that happened to fail. Nothing automatic deletes
  /// them — only [logout], which the user asks for by name.
  Future<void> endSessionKeepingAccounts() async {
    try {
      await OdooSessionManager.logout();
    } catch (e) {
      // The server-side sign-out is best effort; the local session goes
      // either way, or the app is stuck holding one it cannot use.
    }

    await _clearAllProviderData(clearCompanies: true);
    await clearSession();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        CustomSnackbar.showInfo(context, 'Please sign in again');
      }
    });
  }

  /// [showNotice] shows the "Logged out" snackbar; pass false when the
  /// caller presents its own logout feedback (e.g. settings/profile screens).
  ///
  /// This is the user asking, from Settings or Profile, and it clears every
  /// saved account on the device. Nothing calls it on the user's behalf —
  /// an automatic sign-out goes through [endSessionKeepingAccounts].
  Future<void> logout({bool showNotice = true}) async {
    _isLoggingOut = true;
    notifyListeners();
    try {
      try {
        await OdooSessionManager.logout();
      } catch (e) {}

      await _clearStoredAccountsData();
      await _clearPasswordCaches();
      await _clearAllProviderData(clearCompanies: true);
      await clearSession();
    } finally {
      _isLoggingOut = false;
      notifyListeners();

      if (showNotice) {
        _showLoggedOutNoticeSafely();
      }
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

  /// Clears per-account cached data from every provider.
  ///
  /// [clearCompanies] belongs only to logout and account switching. The
  /// company list is scoped to the *user*, not to the active company, so
  /// wiping it on an ordinary data refresh empties the company selector —
  /// which is exactly what a company switch did, since `switchCompany` ends
  /// by calling `refreshAllData`.
  Future<void> _clearAllProviderData({bool clearCompanies = false}) async {
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

      if (clearCompanies) {
        try {
          final companyProvider = context.read<CompanyProvider>();
          companyProvider.clearData();
        } catch (e) {}
      }

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
        // Same as in `checkSession`: end this session, keep the accounts.
        await endSessionKeepingAccounts();
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
    final session = _currentSession;
    if (session == null) return;
    // A session whose user id is not known yet has no identity to be stored
    // under. Storing it anyway is what minted the phantom `userId: "0"` row;
    // the next pass stores it properly, once the id is in.
    if (!isUsableUserId(session.userId)) return;

    final key = sessionAccountKey(session);
    final currentExists = _storedAccounts.any(
      (account) => storedAccountKey(account) == key,
    );

    if (!currentExists) {
      await storeAccount(session, '');
    }
  }

  /// Identity of a stored account: user, server and database.
  ///
  /// Every place that upserts, de-duplicates, matches or removes an account
  /// builds its key through this, so they cannot disagree about whether two
  /// rows are the same account. The URL is normalised because the same server
  /// reaches storage spelled differently depending on which screen saved it.
  static String storedAccountKey(Map<String, dynamic> account) {
    final userId = account['userId']?.toString() ?? '';
    final serverUrl = normalizeServerUrl(
      (account['serverUrl'] ?? account['url'])?.toString(),
    );
    final database = account['database']?.toString() ?? '';
    return '${userId}_${serverUrl}_$database';
  }

  /// The same identity, read off a live session.
  ///
  /// Session and stored account are compared through one function, because
  /// a session carries the server URL exactly as it was typed while storage
  /// holds the normalised one — so a direct `==` between the two reads as a
  /// different account and quietly stores a second copy.
  static String sessionAccountKey(OdooSessionModel session) =>
      storedAccountKey({
        'userId': session.userId?.toString(),
        'serverUrl': session.serverUrl,
        'database': session.database,
      });

  /// Whether [userId] names a real Odoo user.
  ///
  /// Odoo user ids start at 1, so `0` is not a user — it is what this app
  /// wrote when it stored a session before the id was known, through
  /// `(session.userId ?? 0)`. The row that results is a second identity for
  /// an account the list already holds: keyed `0_<server>_<db>`, invisible to
  /// de-duplication, with no password, and impossible to switch into. It is
  /// why an account list shows two rows for one login.
  static bool isUsableUserId(Object? userId) {
    final text = userId?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') return false;
    return (int.tryParse(text) ?? 0) > 0;
  }

  Future<void> _cleanupDuplicateAccounts() async {
    final uniqueAccounts = <String, Map<String, dynamic>>{};

    for (final account in _storedAccounts) {
      final serverUrl = normalizeServerUrl(
        (account['serverUrl'] ?? account['url'])?.toString(),
      );
      final database = account['database']?.toString() ?? '';

      if (!isUsableUserId(account['userId']) ||
          serverUrl.isEmpty ||
          database.isEmpty) {
        continue;
      }

      final key = storedAccountKey(account);

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
    // Without a real user id there is nothing to key this account on, and a
    // fabricated `0` becomes a second, un-switchable copy of an account the
    // list already holds. [isUsableUserId] says why 0 is not a user.
    if (!isUsableUserId(session.userId)) return;

    try {
      final incomingKey = sessionAccountKey(session);
      final existing = _storedAccounts.firstWhere(
        (account) => storedAccountKey(account) == incomingKey,
        orElse: () => <String, dynamic>{},
      );

      String? imageBase64 = existing['imageBase64']?.toString();
      String userDisplayName =
          existing['userName']?.toString() ?? session.userLogin;

      final identity = await _fetchUserIdentity(
        url: session.serverUrl,
        sessionId: session.sessionId,
        userId: session.userId,
      );
      if (identity != null) {
        userDisplayName = identity.name ?? userDisplayName;
        imageBase64 = identity.imageBase64;
      }

      // An auto-store passes no password — `storeAccount(session, '')` — and
      // this method replaces the stored row wholesale. Letting that empty
      // string through erased the saved password, turning a working account
      // into one that asks to be logged in again on every switch.
      final effectivePassword = password.isNotEmpty
          ? password
          : (existing['password']?.toString() ?? '');

      // Non-null: the guard at the top of this method already refused a
      // session without a usable id, so there is no `?? 0` fallback to take.
      final userId = session.userId!.toString();

      final accountData = {
        'id': userId,
        'name': userDisplayName,
        'email': session.userLogin,
        'url': normalizeServerUrl(session.serverUrl),
        'database': session.database,
        'username': session.userLogin,
        'isCurrent': true,
        'lastLogin': DateTime.now().toIso8601String(),
        'imageBase64': imageBase64?.isNotEmpty == true ? imageBase64 : null,

        'userId': userId,
        'userName': userDisplayName,
        'serverUrl': normalizeServerUrl(session.serverUrl),
        'password': effectivePassword,
        'sessionId': session.sessionId,
      };

      for (var account in _storedAccounts) {
        account['isCurrent'] = false;
      }

      _storedAccounts.removeWhere(
        (account) => storedAccountKey(account) == incomingKey,
      );

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

  /// The name and photo of the user [userId] on [url], read with that user's
  /// own [sessionId]; null when they cannot be read (no session, an expired
  /// one, the server down).
  ///
  /// [UserIdentity.name] is null when the server returns no name; the photo is
  /// null when the user has none, which is a real answer and not a failure.
  Future<UserIdentity?> _fetchUserIdentity({
    required String url,
    required String sessionId,
    required int? userId,
  }) async {
    if (userId == null || sessionId.isEmpty) return null;
    try {
      final rows = await OdooSessionManager.callKwWithSession(
        url: normalizeServerUrl(url),
        sessionId: sessionId,
        payload: {
          'model': 'res.users',
          'method': 'read',
          'args': [
            [userId],
            ['name', 'image_1920'],
          ],
          'kwargs': const {},
        },
      ).timeout(const Duration(seconds: 20));
      if (rows is! List || rows.isEmpty || rows.first is! Map) return null;
      final row = rows.first as Map;
      final name = row['name'];
      return UserIdentity(
        name: (name is String && name.trim().isNotEmpty) ? name : null,
        imageBase64: odooBinaryToBase64(row['image_1920']),
      );
    } catch (_) {
      return null;
    }
  }

  /// Applies a freshly read [identity] to a stored [account] map, in place,
  /// and returns whether anything changed.
  ///
  /// The name goes under both keys the app has always written (`name` and
  /// `userName`). A null name leaves the stored one alone; the photo is
  /// replaced even by null, since a user who removed theirs has none.
  @visibleForTesting
  static bool applyIdentity(
    Map<String, dynamic> account,
    UserIdentity identity,
  ) {
    var changed = false;
    final name = identity.name;
    if (name != null &&
        (account['name'] != name || account['userName'] != name)) {
      account['name'] = name;
      account['userName'] = name;
      changed = true;
    }
    if (account['imageBase64'] != identity.imageBase64) {
      account['imageBase64'] = identity.imageBase64;
      changed = true;
    }
    return changed;
  }

  /// Records a profile the app has just read or saved — [name] and the photo
  /// [imageBase64] — on the stored entry of [session]'s account, so the
  /// account list shows what the profile screen shows.
  Future<void> updateStoredAccountProfile(
    OdooSessionModel session, {
    String? name,
    String? imageBase64,
  }) async {
    final key = storedAccountKey({
      'userId': session.userId?.toString(),
      'serverUrl': session.serverUrl,
      'database': session.database,
    });
    final index = _storedAccounts.indexWhere(
      (account) => storedAccountKey(account) == key,
    );
    if (index < 0) return;

    final changed = applyIdentity(
      _storedAccounts[index],
      UserIdentity(name: name, imageBase64: imageBase64),
    );
    if (!changed) return;
    await _saveStoredAccountsWithRetry();
    notifyListeners();
  }

  DateTime? _accountsRefreshedAt;
  bool _isRefreshingAccounts = false;

  /// Re-reads the name and photo of every stored account and updates the ones
  /// that changed — a rename or a new photo made on the web, say.
  ///
  /// Each account is read with its own saved session; one whose session has
  /// expired is skipped and keeps what it shows. Without [force] it runs at
  /// most once every five minutes, so opening the screen again does not repeat
  /// the work.
  Future<void> refreshStoredAccountsProfiles({bool force = false}) async {
    if (_isRefreshingAccounts || _storedAccounts.isEmpty) return;
    final last = _accountsRefreshedAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 5)) {
      return;
    }
    _isRefreshingAccounts = true;
    try {
      final current = _currentSession;
      final currentKey = current == null
          ? null
          : storedAccountKey({
              'userId': current.userId?.toString(),
              'serverUrl': current.serverUrl,
              'database': current.database,
            });

      final accounts = List<Map<String, dynamic>>.from(_storedAccounts);
      final identities = await Future.wait([
        for (final account in accounts)
          _fetchUserIdentity(
            url: (account['serverUrl'] ?? account['url'] ?? '').toString(),
            // The signed-in account's saved id can be older than its live one.
            sessionId: storedAccountKey(account) == currentKey
                ? current!.sessionId
                : (account['sessionId'] ?? '').toString(),
            userId: int.tryParse(account['userId']?.toString() ?? ''),
          ),
      ]);

      var changed = false;
      for (var i = 0; i < accounts.length; i++) {
        final identity = identities[i];
        if (identity == null) continue;
        final index = _storedAccounts.indexWhere(
          (a) => storedAccountKey(a) == storedAccountKey(accounts[i]),
        );
        if (index < 0) continue;
        if (applyIdentity(_storedAccounts[index], identity)) changed = true;
      }

      _accountsRefreshedAt = DateTime.now();
      if (changed) {
        await _saveStoredAccountsWithRetry();
        notifyListeners();
      }
    } finally {
      _isRefreshingAccounts = false;
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
      final outgoing = _currentSession;
      final outgoingKey = outgoing == null ? null : sessionAccountKey(outgoing);
      if (outgoing != null && outgoingKey != sessionAccountKey(newSession)) {
        final currentExists = _storedAccounts.any(
          (account) => storedAccountKey(account) == outgoingKey,
        );

        if (!currentExists) {
          await storeAccount(outgoing, '');
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

    try {
      FieldValidationService.clearInvalidFieldsCache();
    } catch (e) {}

    // What the previous account or company could do says nothing about this
    // one; the five-minute permission cache must not outlive the switch.
    try {
      PermissionService.instance.clearCache();
    } catch (e) {
      // A replaced PermissionService (tests) need not support clearing.
    }

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

      await _clearAllProviderData(clearCompanies: true);

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
          // Not a connection or password problem: let it reach the caller as is.
          if (e is DatabaseExpiredException) rethrow;
          if (e is SalesAccessException) rethrow;
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

    // `0` belongs here as much as null does: it is the id this app wrote for
    // a session it had not identified yet, and installs already carry those
    // rows. Dropping them on the next launch is what clears the duplicate
    // account an affected device shows.
    _storedAccounts.removeWhere(
      (account) => !isUsableUserId(account['userId']),
    );

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
          final session = _currentSession!;
          final serverUrl = normalizeServerUrl(session.serverUrl);
          for (var account in _storedAccounts) {
            // `userName` holds the display name Odoo returned, not the login,
            // so matching it against `userLogin` alone never fired and the
            // identity-less row was never repaired. Any of the three spellings
            // the app writes identifies the same user.
            final namesThisUser =
                account['userName'] == session.userLogin ||
                account['username'] == session.userLogin ||
                account['email'] == session.userLogin;
            if (!isUsableUserId(account['userId']) &&
                namesThisUser &&
                normalizeServerUrl(
                      (account['serverUrl'] ?? account['url'])?.toString(),
                    ) ==
                    serverUrl &&
                account['database'] == session.database) {
              account['userId'] = revealedUserId.toString();
              account['id'] = revealedUserId.toString();
              changed = true;
            }
          }

          if (changed) {
            // The repaired row now carries the same identity as the account's
            // real row, if it had one, so collapse them before saving.
            await _cleanupDuplicateAccounts();
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
    final session = _currentSession;
    if (session == null) return;

    final currentKey = sessionAccountKey(session);
    if (currentKey == storedAccountKey(targetAccount)) return;

    final currentExists = _storedAccounts.any(
      (account) => storedAccountKey(account) == currentKey,
    );

    if (!currentExists) {
      await storeAccount(session, '');
    }
  }

  List<Map<String, dynamic>> getUniqueStoredAccounts() {
    final uniqueAccounts = <String, Map<String, dynamic>>{};

    for (int i = 0; i < _storedAccounts.length; i++) {
      final account = _storedAccounts[i];
      uniqueAccounts[storedAccountKey(account)] = Map<String, dynamic>.from(
        account,
      );
    }

    if (_currentSession != null && isUsableUserId(_currentSession!.userId)) {
      final currentKey = sessionAccountKey(_currentSession!);

      if (!uniqueAccounts.containsKey(currentKey)) {
        uniqueAccounts[currentKey] = {
          'userId': _currentSession!.userId.toString(),
          'userName': _currentSession!.userLogin,
          'serverUrl': normalizeServerUrl(_currentSession!.serverUrl),
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
    final session = _currentSession;
    if (session == null) return false;
    return storedAccountKey(account) == sessionAccountKey(session);
  }

  Future<void> updateAccountCredentials(
    String username,
    String password,
  ) async {
    if (_currentSession == null) return;

    final currentKey = sessionAccountKey(_currentSession!);
    final accountIndex = _storedAccounts.indexWhere(
      (account) => storedAccountKey(account) == currentKey,
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
    final key = storedAccountKey({
      'userId': userId,
      'serverUrl': serverUrl,
      'database': database,
    });
    final accountIndex = _storedAccounts.indexWhere(
      (account) => storedAccountKey(account) == key,
    );

    if (accountIndex != -1) {
      _storedAccounts[accountIndex].remove('needsReauth');
      await _saveStoredAccountsWithRetry();
      notifyListeners();
    }
  }
}

/// The name and photo of an Odoo user, as read from `res.users`.
class UserIdentity {
  const UserIdentity({this.name, this.imageBase64});

  /// Null when the server gave none.
  final String? name;

  /// Base64 text of the photo, or null when the user has none.
  final String? imageBase64;
}
