import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/odoo_session_manager.dart';
import '../services/company_local_datasource.dart';
import '../services/session_service.dart';
import '../utils/session_companies.dart';

/// Manages the list of available companies and the active company selection.
class CompanyProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _companies = [];
  int? _selectedCompanyId;

  List<int> _selectedAllowedCompanyIds = [];
  bool _loading = false;
  bool _switching = false;
  String? _error;

  // Whether the last attempt ended without an answer from the server, as
  // opposed to an answer saying the user has no companies. The pill reads it,
  // because "No companies" shown for a failed load is what made a perfectly
  // good account look empty.
  bool _lastLoadFailed = false;

  // initialize() requested while one is in flight: run it again afterwards
  // instead of dropping it.
  bool _rerunQueued = false;
  // Backoff retries after a failed load (a cold start often happens before the
  // network / server is usable).
  Timer? _retryTimer;
  int _retryAttempt = 0;

  /// How long the pill stays in its loading state at minimum.
  ///
  /// An attempt can finish in a couple of milliseconds — the no-session path
  /// below never touches the network, and a refused request comes back almost
  /// as fast — and a spinner shown for less than one frame is a spinner nobody
  /// sees. That is why tapping "Tap to retry" or pulling the page down looked
  /// like it did nothing at all: the work ran and finished between two frames.
  /// Holding the state briefly is the difference the user reads as "it tried".
  static const Duration _minVisibleLoading = Duration(milliseconds: 450);

  static const _retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
  ];

  List<Map<String, dynamic>> get companies => _companies;
  int? get selectedCompanyId => _selectedCompanyId;
  List<int> get selectedAllowedCompanyIds => _selectedAllowedCompanyIds;
  bool get isLoading => _loading;
  bool get isSwitching => _switching;
  String? get error => _error;

  /// Whether the companies could not be loaded, rather than there being none.
  bool get loadFailed => _lastLoadFailed;

  Map<String, dynamic>? get selectedCompany {
    if (_selectedCompanyId == null) return null;
    try {
      return _companies.firstWhere((c) => c['id'] == _selectedCompanyId);
    } catch (e) {
      return null;
    }
  }

  /// Updates the allowed company list and persists it to preferences.
  Future<void> setAllowedCompanies(List<int> allowedIds) async {
    final availableIds = _companies.map((c) => c['id'] as int).toSet();
    final filtered = allowedIds
        .where((id) => availableIds.contains(id))
        .toList();

    if (_selectedCompanyId != null && !filtered.contains(_selectedCompanyId)) {
      filtered.add(_selectedCompanyId!);
    }
    _selectedAllowedCompanyIds = filtered;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'selected_allowed_company_ids',
      _selectedAllowedCompanyIds.map((e) => e.toString()).toList(),
    );

    if (_selectedCompanyId != null) {
      await OdooSessionManager.updateCompanySelection(
        companyId: _selectedCompanyId!,
        allowedCompanyIds: _selectedAllowedCompanyIds,
      );
    }
    notifyListeners();
  }

  /// Resets the provider to an empty state.
  void clearData() {
    _companies = [];
    _selectedCompanyId = null;
    _selectedAllowedCompanyIds = [];
    _error = null;
    _lastLoadFailed = false;
    notifyListeners();
  }

  /// Loads companies and resolves the active company from Odoo and local cache.
  /// Manual retry (tapping the "No companies" pill).
  Future<void> retry() {
    _retryAttempt = 0;
    return initialize();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (_retryAttempt >= _retryDelays.length) return;
    final delay = _retryDelays[_retryAttempt++];
    _retryTimer = Timer(delay, () {
      if (!_loading) initialize();
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> initialize() async {
    if (_loading) {
      _rerunQueued = true;
      return;
    }
    _retryTimer?.cancel();
    _loading = true;
    _error = null;
    _lastLoadFailed = false;
    notifyListeners();
    final startedAt = DateTime.now();
    const local = CompanyLocalDataSource();
    try {
      await Future(() async {
        final session = await OdooSessionManager.getCurrentSession();
        final uid = session?.userId;
        final db = session?.database;

        if (session == null || session.userId == null) {
          _companies = await local.getAllCompanies(userId: uid, database: db);
          _selectedCompanyId = null;
          // No session yet is not an account without companies — nothing was
          // determined at all. A cold start reaches here before the session is
          // restored, so say "could not load" and try again rather than
          // settling on "none" and stopping.
          if (_companies.isEmpty) {
            _lastLoadFailed = true;
            _scheduleRetry();
          }
          return;
        }

        int effectiveUserId = session.userId ?? 0;
        if (effectiveUserId == 0) {
          try {
            final info = await OdooSessionManager.getSessionInfo(
              session.serverUrl,
              session.sessionId,
            );
            if (info['uid'] != null) {
              final recoveredId = info['uid'] is int
                  ? info['uid']
                  : int.tryParse(info['uid'].toString()) ?? 0;
              if (recoveredId > 0) {
                effectiveUserId = recoveredId;

                await OdooSessionManager.updateSession(
                  session.copyWith(userId: effectiveUserId),
                );
              }
            }
          } catch (e) {}
        }

        final prefs = await SharedPreferences.getInstance();
        final restoredId = prefs.getInt('selected_company_id');
        final restoredAllowed =
            prefs
                .getStringList('selected_allowed_company_ids')
                ?.map((e) => int.tryParse(e) ?? -1)
                .where((e) => e > 0)
                .toList() ??
            [];

        if (restoredId != null && _selectedCompanyId == null) {
          _selectedCompanyId = restoredId;
          _selectedAllowedCompanyIds = restoredAllowed;
          notifyListeners();
        }

        // Show the last known companies straight away (cold start / offline);
        // the server call below replaces them when it succeeds.
        if (_companies.isEmpty) {
          final cached = await local.getAllCompanies(userId: uid, database: db);
          if (cached.isNotEmpty) {
            _companies = cached;
            _selectedCompanyId ??= cached.first['id'] as int?;
            notifyListeners();
          }
        }

        List<int> companyIds = [];
        int? currentCompanyId;

        // Ask the server what the web client asks: `session_info` carries
        // `user_companies`, built for the logged-in user and — on 19 and 20 —
        // through `.sudo()`. The `res.users` read below is the older path and
        // loses to Odoo's own field-access rules, because `company_ids` is not
        // a field a user may read on themselves.
        SessionCompanies? fromSession;
        try {
          final info = await OdooSessionManager.getSessionInfo(
            session.serverUrl,
            session.sessionId,
          );
          fromSession = parseSessionCompanies(info);
        } catch (_) {
          // Fall through to the read below.
        }

        if (fromSession != null) {
          companyIds = fromSession.ids;
          currentCompanyId = fromSession.currentId;
          _companies = fromSession.companies;
          await local.putAllCompanies(_companies, userId: uid, database: db);
          _retryAttempt = 0;
        }

        final userRes = companyIds.isNotEmpty
            ? null
            : await OdooSessionManager.safeCallKwWithoutCompany({
                'model': 'res.users',
                'method': 'read',
                'args': [
                  [effectiveUserId],
                  ['company_id', 'company_ids'],
                ],
                'kwargs': {},
              });

        if (userRes is List && userRes.isNotEmpty && userRes.first != null) {
          final row = userRes.first as Map<String, dynamic>;
          if (row['company_ids'] is List) {
            final raw = row['company_ids'] as List;
            companyIds = raw.whereType<int>().toList();
          }
          if (row['company_id'] is List &&
              (row['company_id'] as List).isNotEmpty) {
            currentCompanyId = (row['company_id'] as List).first as int?;
          } else if (row['company_id'] is int) {
            currentCompanyId = row['company_id'];
          }
        }

        if (companyIds.isEmpty) {
          // Usually a failed/partial reply, not "no companies": keep the
          // cached list and try again shortly.
          _lastLoadFailed = true;
          if (_companies.isEmpty) {
            _companies = await local.getAllCompanies(userId: uid, database: db);
          }
          _selectedCompanyId = restoredId ?? currentCompanyId;
          _scheduleRetry();
          return;
        }

        final companiesRes = fromSession != null
            ? null
            : await OdooSessionManager.safeCallKwWithoutCompany({
                'model': 'res.company',
                'method': 'search_read',
                'args': [
                  [
                    ['id', 'in', companyIds],
                  ],
                ],
                'kwargs': {
                  'fields': ['id', 'name'],
                  'order': 'name asc',
                },
              });

        final serverCompanies = (companiesRes is List)
            ? companiesRes.cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];

        if (serverCompanies.isNotEmpty) {
          _companies = serverCompanies;
          await local.putAllCompanies(_companies, userId: uid, database: db);
          _retryAttempt = 0;
        } else if (fromSession == null) {
          _companies = await local.getAllCompanies(userId: uid, database: db);
        }

        final pendingId = prefs.getInt('pending_company_id');

        int? desiredId =
            pendingId ??
            restoredId ??
            session.selectedCompanyId ??
            currentCompanyId ??
            (companyIds.isNotEmpty ? companyIds.first : null);
        _selectedCompanyId = desiredId;

        List<int> defaultAllowed = companyIds;
        final restoredValid = restoredAllowed
            .where((id) => companyIds.contains(id))
            .toList();
        _selectedAllowedCompanyIds = restoredValid.isNotEmpty
            ? restoredValid
            : defaultAllowed;

        if (_selectedCompanyId == null ||
            !companyIds.contains(_selectedCompanyId)) {
          if (companyIds.isNotEmpty) {
            _selectedCompanyId = companyIds.first;
          }
        }

        if (_selectedCompanyId != null &&
            !_selectedAllowedCompanyIds.contains(_selectedCompanyId)) {
          _selectedAllowedCompanyIds = [
            ..._selectedAllowedCompanyIds,
            _selectedCompanyId!,
          ];
        }

        if (_selectedCompanyId != null) {
          await prefs.setInt('selected_company_id', _selectedCompanyId!);
        }
        await prefs.setStringList(
          'selected_allowed_company_ids',
          _selectedAllowedCompanyIds.map((e) => e.toString()).toList(),
        );

        if (_selectedCompanyId != null) {
          await OdooSessionManager.updateCompanySelection(
            companyId: _selectedCompanyId!,
            allowedCompanyIds: _selectedAllowedCompanyIds,
          );
        }

        if (pendingId != null && companyIds.contains(pendingId)) {
          try {
            await _applyCompanyOnServer(session.userId!, pendingId);
            await OdooSessionManager.refreshSession();
            await OdooSessionManager.restoreSession(companyId: pendingId);
            await prefs.remove('pending_company_id');
          } catch (_) {}
        } else if (desiredId != null &&
            currentCompanyId != desiredId &&
            companyIds.contains(desiredId)) {
          try {
            await _applyCompanyOnServer(session.userId!, desiredId);
            await OdooSessionManager.refreshSession();
            await OdooSessionManager.restoreSession(companyId: desiredId);
          } catch (_) {}
        }
      }).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException(
            'Loading companies timed out after 15 seconds',
          );
        },
      );
    } catch (e) {
      try {
        final session = await OdooSessionManager.getCurrentSession();
        final uid = session?.userId;
        final db = session?.database;

        _companies = await local.getAllCompanies(userId: uid, database: db);
        if (_selectedCompanyId == null) {
          final prefs = await SharedPreferences.getInstance();
          _selectedCompanyId = prefs.getInt('selected_company_id');
          _selectedAllowedCompanyIds =
              prefs
                  .getStringList('selected_allowed_company_ids')
                  ?.map((e) => int.tryParse(e) ?? -1)
                  .where((e) => e > 0)
                  .toList() ??
              [];
        }
        if (_companies.isEmpty) {
          _error = e.toString();
        }
      } catch (_) {
        _error = e.toString();
      }
      _lastLoadFailed = true;
      _scheduleRetry();
    } finally {
      // The one place the load ends, so every path — including the two that
      // return early above — is held on screen long enough to be seen.
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed < _minVisibleLoading) {
        await Future.delayed(_minVisibleLoading - elapsed);
      }
      _loading = false;
      notifyListeners();
      if (_rerunQueued) {
        _rerunQueued = false;
        unawaited(initialize());
      }
    }
  }

  /// Refreshes the company list from the Odoo server, falling back to local cache.
  Future<void> refreshCompaniesList() async {
    _loading = true;
    notifyListeners();
    const local = CompanyLocalDataSource();
    try {
      final session = await OdooSessionManager.getCurrentSession();
      final list = await OdooSessionManager.getAllowedCompaniesList();
      if (list.isNotEmpty) {
        _companies = list;
        await local.putAllCompanies(
          _companies,
          userId: session?.userId,
          database: session?.database,
        );
      } else {
        _companies = await local.getAllCompanies(
          userId: session?.userId,
          database: session?.database,
        );
      }
    } catch (_) {
      try {
        final session = await OdooSessionManager.getCurrentSession();
        _companies = await local.getAllCompanies(
          userId: session?.userId,
          database: session?.database,
        );
      } catch (_) {}
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Switches the active company to [companyId] and refreshes session data.
  Future<bool> switchCompany(
    int companyId, {
    List<int>? allowedCompanyIds,
  }) async {
    if (_selectedCompanyId == companyId) return true;
    bool appliedImmediately = false;
    try {
      _switching = true;
      _error = null;
      notifyListeners();
      final session = await OdooSessionManager.getCurrentSession();
      if (session == null || session.userId == null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('selected_company_id', companyId);
        await prefs.setInt('pending_company_id', companyId);
        _selectedCompanyId = companyId;
        _selectedAllowedCompanyIds = allowedCompanyIds ?? [companyId];
        await prefs.setStringList(
          'selected_allowed_company_ids',
          _selectedAllowedCompanyIds.map((e) => e.toString()).toList(),
        );
        notifyListeners();
        return false;
      }

      try {
        await _applyCompanyOnServer(session.userId!, companyId);
        await OdooSessionManager.refreshSession();
        await OdooSessionManager.restoreSession(companyId: companyId);

        List<int> allowed = allowedCompanyIds ?? [companyId];
        await OdooSessionManager.updateCompanySelection(
          companyId: companyId,
          allowedCompanyIds: allowed,
        );

        appliedImmediately = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('pending_company_id');
      } catch (_) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('pending_company_id', companyId);
        appliedImmediately = false;
        List<int> allowed = allowedCompanyIds ?? [companyId];
        await OdooSessionManager.updateCompanySelection(
          companyId: companyId,
          allowedCompanyIds: allowed,
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('selected_company_id', companyId);
      _selectedAllowedCompanyIds = allowedCompanyIds ?? [companyId];
      await prefs.setStringList(
        'selected_allowed_company_ids',
        _selectedAllowedCompanyIds.map((e) => e.toString()).toList(),
      );

      _selectedCompanyId = companyId;
      notifyListeners();
      await refreshCompaniesList();
      await SessionService.instance.refreshAllData();
      return appliedImmediately;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _switching = false;
      notifyListeners();
    }
  }

  Future<void> _applyCompanyOnServer(int userId, int companyId) async {
    await OdooSessionManager.callKwWithCompany({
      'model': 'res.users',
      'method': 'write',
      'args': [
        [userId],
        {'company_id': companyId},
      ],
      'kwargs': {},
    });
  }

  /// Adds or removes [companyId] from the allowed companies set.
  Future<void> toggleAllowedCompany(int companyId) async {
    if (_selectedAllowedCompanyIds.contains(companyId)) {
      if (companyId == _selectedCompanyId) {
        return;
      }
      _selectedAllowedCompanyIds = _selectedAllowedCompanyIds
          .where((id) => id != companyId)
          .toList();
    } else {
      _selectedAllowedCompanyIds = [..._selectedAllowedCompanyIds, companyId];
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'selected_allowed_company_ids',
      _selectedAllowedCompanyIds.map((e) => e.toString()).toList(),
    );

    if (_selectedCompanyId != null) {
      await OdooSessionManager.updateCompanySelection(
        companyId: _selectedCompanyId!,
        allowedCompanyIds: _selectedAllowedCompanyIds,
      );
    }
    notifyListeners();
  }
}
