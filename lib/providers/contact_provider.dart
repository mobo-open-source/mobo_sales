import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../models/contact.dart';
import '../services/odoo_session_manager.dart';
import '../services/connectivity_service.dart';
import '../services/session_service.dart';
import '../services/customer_service.dart';
import '../services/field_validation_service.dart';

/// Manages the customer/contact list with pagination, filtering, grouping, and search.
class ContactProvider with ChangeNotifier {
  final ConnectivityService _connectivityService;
  final SessionService _sessionService;
  final CustomerService _customerService;

  ContactProvider({
    ConnectivityService? connectivityService,
    SessionService? sessionService,
    CustomerService? customerService,
  }) : _connectivityService =
           connectivityService ?? ConnectivityService.instance,
       _sessionService = sessionService ?? SessionService.instance,
       _customerService = customerService ?? CustomerService.instance;

  List<Contact> _contacts = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isSearching = false;

  static const int _pageSize = 40;
  int _currentPage = 0;
  bool _hasMoreData = true;
  String _currentSearchQuery = '';
  Map<String, dynamic>? _currentFilters;
  int _totalContacts = 0;
  String? _error;
  DateTime? _lastFetchTime;
  bool _isServerUnreachable = false;
  bool _hasInitiallyLoaded = false;
  static const cacheDuration = Duration(minutes: 10);

  String? _accessErrorMessage;
  String? get accessErrorMessage => _accessErrorMessage;

  final Map<int, Uint8List> _base64ImageCache = {};

  Map<String, String> _groupByOptions = {};
  String? _selectedGroupBy;
  bool _isGrouped = false;
  List<String> _availableFields = [];
  bool _isFieldsFetched = false;

  final Map<int, String> _categoryNameCache = {};

  final Set<String> _activeFilters = {};
  bool _showActiveOnly = true;
  bool _showCompaniesOnly = false;
  bool _showIndividualsOnly = false;
  bool _showCreditBreachesOnly = false;
  String? _selectedIndustry;
  String? _selectedCountry;
  DateTime? _startDate;
  DateTime? _endDate;

  List<Contact> get contacts => _contacts;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isSearching => _isSearching;
  bool get hasMoreData => _hasMoreData;

  int get totalContacts => _totalContacts;
  String? get error => _error;
  DateTime? get lastFetchTime => _lastFetchTime;

  Set<String> get activeFilters => _activeFilters;
  bool get showActiveOnly => _showActiveOnly;
  bool get showCompaniesOnly => _showCompaniesOnly;
  bool get showIndividualsOnly => _showIndividualsOnly;
  bool get showCreditBreachesOnly => _showCreditBreachesOnly;
  String? get selectedIndustry => _selectedIndustry;
  String? get selectedCountry => _selectedCountry;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  bool get isServerUnreachable => _isServerUnreachable;
  bool get hasInitiallyLoaded => _hasInitiallyLoaded;

  Map<String, String> get groupByOptions => _groupByOptions;
  String? get selectedGroupBy => _selectedGroupBy;
  bool get isGrouped => _isGrouped;

  final Map<String, int> _groupSummary = {};

  /// Applies one or more filter values to the current state without fetching.
  void setFilterState({
    bool? showActiveOnly,
    bool? showCompaniesOnly,
    bool? showIndividualsOnly,
    bool? showCreditBreachesOnly,
    String? selectedIndustry,
    String? selectedCountry,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    if (showActiveOnly != null) _showActiveOnly = showActiveOnly;
    if (showCompaniesOnly != null) _showCompaniesOnly = showCompaniesOnly;
    if (showIndividualsOnly != null) _showIndividualsOnly = showIndividualsOnly;
    if (showCreditBreachesOnly != null) {
      _showCreditBreachesOnly = showCreditBreachesOnly;
    }
    if (selectedIndustry != null) _selectedIndustry = selectedIndustry;
    if (selectedCountry != null) _selectedCountry = selectedCountry;
    if (startDate != null) _startDate = startDate;
    if (endDate != null) _endDate = endDate;
    notifyListeners();
  }

  /// Resets all active filters to their defaults.
  void clearFilters() {
    _activeFilters.clear();
    _showActiveOnly = true;
    _showCompaniesOnly = false;
    _showIndividualsOnly = false;
    _showCreditBreachesOnly = false;
    _selectedIndustry = null;
    _selectedCountry = null;
    _startDate = null;
    _endDate = null;
    notifyListeners();
  }

  Map<String, int> get groupSummary => _groupSummary;

  final Map<String, List<Contact>> _loadedGroups = {};
  Map<String, List<Contact>> get loadedGroups => _loadedGroups;

  int get pageSize => _pageSize;
  int get currentPage => _currentPage;
  int get currentStartIndex => (_currentPage * _pageSize) + 1;
  int get currentEndIndex => _contacts.length;
  int get totalPages =>
      _totalContacts > 0 ? ((_totalContacts - 1) ~/ _pageSize) + 1 : 0;
  bool get canGoToPreviousPage => _currentPage > 0;
  bool get canGoToNextPage => _hasMoreData;

  /// Returns a string like '1-40/200' describing the current pagination position.
  String getPaginationText() {
    if (_totalContacts == 0 && _contacts.isEmpty) return "0 items";
    if (_totalContacts == 0) return "${_contacts.length} items";

    final pageStart = (_currentPage * _pageSize) + 1;

    final expectedPageEnd = (_currentPage + 1) * _pageSize;
    final pageEnd = expectedPageEnd > _totalContacts
        ? _totalContacts
        : expectedPageEnd;
    return "$pageStart-$pageEnd/$_totalContacts";
  }

  /// Jumps to the given page index and fetches the corresponding contacts.
  Future<void> goToPage(int page) async {
    if (page < 0 || page == _currentPage) return;

    _currentPage = page;
    await _fetchSpecificPage();
  }

  /// Advances to the next page of contacts.
  Future<void> goToNextPage() async {
    if (!canGoToNextPage) return;
    _currentPage++;
    await _fetchSpecificPage();
  }

  /// Returns to the previous page of contacts.
  Future<void> goToPreviousPage() async {
    if (!canGoToPreviousPage) return;
    _currentPage--;
    await _fetchSpecificPage();
  }

  Future<void> _fetchSpecificPage() async {
    if (_isLoading || _isLoadingMore) return;

    if (!_connectivityService.isConnected || !_sessionService.hasValidSession) {
      _error = "No connection or session available.";
      notifyListeners();
      return;
    }

    _isLoadingMore = true;
    _error = null;
    notifyListeners();

    try {
      List<dynamic> domain = _buildDomain(_currentSearchQuery, _currentFilters);

      final List<String> fieldsToFetch = [
        'id',
        'name',
        'phone',
        'email',
        'street',
        'street2',
        'city',
        'state_id',
        'zip',
        'country_id',
        'image_128',
        'is_company',
        'company_name',
        'company_id',
        'active',
        'type',
        'user_id',
        'category_id',
        'create_date',
        'write_date',
        'credit_limit',
        'credit',
      ];

      final result =
          await FieldValidationService.executeWithFieldValidation<
            List<Map<String, dynamic>>
          >(
            model: 'res.partner',
            initialFields: fieldsToFetch,
            apiCall: (currentFields) => _customerService.fetchContacts(
              domain: domain,
              fields: currentFields,
              limit: _pageSize,
              offset: _currentPage * _pageSize,
            ),
          );

      final fetchedContacts = result
          .map((contactData) {
            try {
              return Contact.fromJson(contactData);
            } catch (_) {
              return null;
            }
          })
          .where((c) => c != null)
          .cast<Contact>()
          .toList();

      _contacts = fetchedContacts;

      if (_totalContacts > 0) {
        _hasMoreData = (_currentPage + 1) * _pageSize < _totalContacts;
      } else {
        _hasMoreData = fetchedContacts.length == _pageSize;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Uint8List? getCachedBase64Image(int contactId) =>
      _base64ImageCache[contactId];
  void cacheBase64Image(int contactId, Uint8List bytes) =>
      _base64ImageCache[contactId] = bytes;

  bool _isServerUnreachableError(dynamic error) {
    final errorString = error.toString().toLowerCase();
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
        errorString.contains('unexpected response');
  }

  List<dynamic> _buildDomain(
    String searchQuery,
    Map<String, dynamic>? filters,
  ) {
    final List<dynamic> domain = [];

    if (filters != null) {
      if (filters['showActiveOnly'] == true) {
        domain.add(['active', '=', true]);
      }
      if (filters['showCompaniesOnly'] == true) {
        domain.add(['is_company', '=', true]);
      }
      if (filters['showIndividualsOnly'] == true) {
        domain.add(['is_company', '=', false]);
      }

      if (filters['startDate'] != null || filters['endDate'] != null) {
        if (filters['startDate'] != null && filters['endDate'] != null) {
          final start = filters['startDate'] as DateTime;
          final end = filters['endDate'] as DateTime;
          final startStr =
              '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')} 00:00:00';
          final endStr =
              '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')} 23:59:59';

          domain.add(['create_date', '>=', startStr]);
          domain.add(['create_date', '<=', endStr]);
        } else if (filters['startDate'] != null) {
          final start = filters['startDate'] as DateTime;
          final startStr =
              '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')} 00:00:00';
          domain.add(['create_date', '>=', startStr]);
        } else if (filters['endDate'] != null) {
          final end = filters['endDate'] as DateTime;
          final endStr =
              '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')} 23:59:59';
          domain.add(['create_date', '<=', endStr]);
        }
      }
    }

    final q = searchQuery.trim();
    if (q.isNotEmpty) {
      domain.add('|');
      domain.add(['name', 'ilike', q]);
      domain.add('|');
      domain.add(['email', 'ilike', q]);
      domain.add('|');
      domain.add(['phone', 'ilike', q]);
      domain.add(['company_name', 'ilike', q]);
    }

    domain.add(['customer_rank', '>', 0]);

    return domain;
  }

  /// Fetches contacts from Odoo, using cache unless [forceRefresh] is set.
  Future<void> fetchContacts({
    bool forceRefresh = false,
    String? searchQuery,
    Map<String, dynamic>? filters,
  }) async {
    if (_isLoading || _isSearching) return;

    _currentSearchQuery = (searchQuery ?? '').trim();
    if (_currentSearchQuery.isNotEmpty) {
      _isSearching = true;
    } else {
      _isLoading = true;
    }
    _error = null;
    _isServerUnreachable = false;
    _accessErrorMessage = null;
    notifyListeners();

    if (!forceRefresh &&
        _contacts.isNotEmpty &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < cacheDuration &&
        searchQuery == null) {
      _isLoading = false;
      _isSearching = false;
      notifyListeners();
      return;
    }

    if (!_connectivityService.isConnected) {
      _error = "No internet connection available.";
      _isLoading = false;
      _isSearching = false;
      _isServerUnreachable = false;
      _accessErrorMessage = null;
      notifyListeners();
      return;
    }

    if (!_sessionService.hasValidSession) {
      _error = "No active Odoo session.";
      _isLoading = false;
      _isSearching = false;
      _isServerUnreachable = false;
      _accessErrorMessage = null;
      notifyListeners();
      return;
    }

    _currentFilters = filters;
    _currentPage = 0;
    _hasMoreData = true;
    _contacts = [];

    try {
      List<dynamic> domain = _buildDomain(_currentSearchQuery, _currentFilters);

      final List<String> fieldsToFetch = [
        'id',
        'name',
        'phone',
        'email',
        'street',
        'street2',
        'city',
        'state_id',
        'zip',
        'country_id',
        'image_128',
        'is_company',
        'company_name',
        'company_id',
        'active',
        'type',
        'user_id',
        'category_id',
        'create_date',
        'write_date',
        'credit_limit',
        'credit',
      ];

      final listFuture =
          FieldValidationService.executeWithFieldValidation<
            List<Map<String, dynamic>>
          >(
            model: 'res.partner',
            initialFields: fieldsToFetch,
            apiCall: (currentFields) => _customerService.fetchContacts(
              domain: domain,
              fields: currentFields,
              limit: _pageSize,
              offset: _currentPage * _pageSize,
            ),
          );

      (() async {
        try {
          final total = await _customerService.getContactCount(domain);
          _totalContacts = total;
          _hasMoreData = _contacts.length < _totalContacts;
          notifyListeners();
        } catch (_) {}
      })();

      final result = await listFuture;

      final fetchedContacts = result
          .map((contactData) {
            try {
              return Contact.fromJson(contactData);
            } catch (_) {
              return null;
            }
          })
          .where((c) => c != null)
          .cast<Contact>()
          .toList();

      _contacts = fetchedContacts;

      if (_totalContacts > 0) {
        _hasMoreData = (_currentPage + 1) * _pageSize < _totalContacts;
      } else {
        _hasMoreData = _contacts.length == _pageSize;
      }
      _lastFetchTime = DateTime.now();
      _hasInitiallyLoaded = true;
      _error = null;
      _isServerUnreachable = false;
      _accessErrorMessage = null;
      if (_totalContacts > 0) {
        _hasMoreData = _contacts.length < _totalContacts;
      }
    } catch (e) {
      if (_isServerUnreachableError(e)) {
        _isServerUnreachable = true;
        _error =
            "Server/Database unreachable. Please check your server or try again.";
        _accessErrorMessage = null;
      } else if (e.toString().contains('AccessError') ||
          e.toString().contains('not allowed to access')) {
        _accessErrorMessage =
            "You do not have permission to view customers. Please contact your administrator to request access.";
        _error = null;
        _isServerUnreachable = false;
      } else {
        _error = e.toString();
        _isServerUnreachable = false;
        _accessErrorMessage = null;
      }
    } finally {
      _isLoading = false;
      _isSearching = false;
      notifyListeners();
    }
  }

  /// Force-refreshes the contact list with optional search and filter overrides.
  Future<void> refreshContacts({
    String? searchQuery,
    Map<String, dynamic>? filters,
  }) async {
    await fetchContacts(
      forceRefresh: true,
      searchQuery: searchQuery,
      filters: filters,
    );
  }

  /// Loads the next page of contacts (alias for [goToNextPage]).
  Future<void> loadMoreContacts() async {
    await goToNextPage();
  }

  /// Clears the server-unreachable error flag.
  void clearServerUnreachableState() {
    _isServerUnreachable = false;
    notifyListeners();
  }

  /// Sets the group-by field and triggers a group summary fetch.
  void setGroupBy(String? groupBy) {
    _selectedGroupBy = groupBy;
    _isGrouped = groupBy != null;

    _groupSummary.clear();
    _loadedGroups.clear();
    _contacts.clear();
    _lastFetchTime = null;

    if (_isGrouped) {
      _fetchGroupSummary();
    }
    notifyListeners();
  }

  Future<void> _fetchGroupSummary() async {
    if (!_isGrouped || _selectedGroupBy == null) return;

    try {
      List<dynamic> domain = _buildDomain(_currentSearchQuery, _currentFilters);

      final result = await _customerService.fetchGroupSummary(
        domain: domain,
        groupBy: _selectedGroupBy!,
      );

      _groupSummary.clear();

      int totalGroupedCount = 0;
      for (final group in result) {
        final groupKey = _getGroupKeyFromReadGroup(group, _selectedGroupBy!);
        final count = group['__count'] ?? 0;
        _groupSummary[groupKey] = count;
        totalGroupedCount += count as int;
      }

      if (_totalContacts > totalGroupedCount) {
        final missingCount = _totalContacts - totalGroupedCount;
        String undefinedLabel;

        if (_selectedGroupBy == 'user_id') {
          undefinedLabel = 'Unassigned';
        } else if (_selectedGroupBy == 'country_id') {
          undefinedLabel = 'Unknown Country';
        } else if (_selectedGroupBy == 'state_id') {
          undefinedLabel = 'Unknown State';
        } else if (_selectedGroupBy == 'parent_id' ||
            _selectedGroupBy == 'company_id') {
          undefinedLabel = 'None';
        } else {
          undefinedLabel = 'Undefined';
        }

        _groupSummary[undefinedLabel] = missingCount;
      }

      notifyListeners();
    } catch (e) {}
  }

  /// Loads all contacts belonging to the group identified by [groupKey].
  Future<void> loadGroupContacts(String groupKey) async {
    if (!_isGrouped || _selectedGroupBy == null) return;

    if (_loadedGroups.containsKey(groupKey)) return;

    try {
      List<dynamic> domain = _buildDomain(_currentSearchQuery, _currentFilters);

      final groupDomain = _buildGroupDomain(groupKey, _selectedGroupBy!);
      domain.addAll(groupDomain);

      final result = await _customerService.fetchContacts(
        domain: domain,
        fields: [
          'id',
          'name',
          'phone',
          'email',
          'street',
          'street2',
          'city',
          'state_id',
          'zip',
          'country_id',
          'image_128',
          'is_company',
          'company_name',
          'company_id',
          'active',
          'type',
          'user_id',
          'category_id',
          'create_date',
          'write_date',
          'credit_limit',
          'credit',
        ],
        limit: 1000,
      );

      final contacts = result.map((data) => Contact.fromJson(data)).toList();
      _loadedGroups[groupKey] = contacts;
      notifyListeners();
    } catch (e) {}
  }

  Future<List<String>> _fetchAvailableFields() async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return [];

      final result = await OdooSessionManager.safeCallKw({
        'model': 'res.partner',
        'method': 'fields_get',
        'args': [],
        'kwargs': {},
      });

      if (result is Map) {
        return result.keys.cast<String>().toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  String _labelForField(String field) {
    switch (field) {
      case 'country_id':
        return 'Country';
      case 'state_id':
        return 'State';
      case 'city':
        return 'City';
      case 'is_company':
        return 'Type';
      case 'category_id':
        return 'Tags';
      case 'user_id':
        return 'Salesperson';
      case 'company_id':
        return 'Company';
      case 'parent_id':
        return 'Company';
      case 'create_date':
        return 'Creation Date';
      case 'write_date':
        return 'Last Modified';
      case 'active':
        return 'Status';
      default:
        return field
            .split('_')
            .map((w) => w.isEmpty ? w : (w[0].toUpperCase() + w.substring(1)))
            .join(' ');
    }
  }

  /// Returns the available group-by field options as a label map.
  Future<Map<String, String>> fetchGroupByOptions() async {
    try {
      if (!_isFieldsFetched || _availableFields.isEmpty) {
        _availableFields = await _fetchAvailableFields();
        _isFieldsFetched = true;
      }

      final baseline = <String>[
        'user_id',
        'country_id',
        'state_id',
        'parent_id',
      ];

      final validFields = baseline
          .where(
            (f) => _availableFields.isEmpty || _availableFields.contains(f),
          )
          .toList();

      final map = <String, String>{
        for (final f in validFields) f: _labelForField(f),
      };

      _groupByOptions = map;
      notifyListeners();
      return _groupByOptions;
    } catch (e) {
      return _groupByOptions;
    }
  }

  /// Groups [contacts] by the currently selected group-by field.
  Map<String, List<Contact>> groupContacts(List<Contact> contacts) {
    try {
      if (!_isGrouped ||
          _selectedGroupBy == null ||
          _selectedGroupBy!.isEmpty) {
        return {};
      }

      if (contacts.isEmpty) {
        return {};
      }

      final groups = <String, List<Contact>>{};

      if (_selectedGroupBy == 'category_id') {
        final Set<int> toFetch = {};
        for (final contact in contacts) {
          try {
            final ids = contact.categoryIds ?? const <int>[];
            if (ids.isEmpty) {
              groups.putIfAbsent('No Tags', () => []).add(contact);
              continue;
            }
            for (final id in ids) {
              final name = _categoryNameCache[id];
              final key = (name == null || name.trim().isEmpty)
                  ? 'Tag $id'
                  : name.trim();
              if (name == null) toFetch.add(id);
              groups.putIfAbsent(key, () => []).add(contact);
            }
          } catch (e) {
            groups.putIfAbsent('No Tags', () => []).add(contact);
          }
        }

        if (toFetch.isNotEmpty) {
          _fetchCategoryNames(toFetch).then((_) {
            notifyListeners();
          });
        }
      } else {
        for (final contact in contacts) {
          try {
            final groupKey = _getGroupKey(contact, _selectedGroupBy!);
            if (groupKey.isNotEmpty) {
              groups.putIfAbsent(groupKey, () => []).add(contact);
            } else {
              groups.putIfAbsent('Unknown', () => []).add(contact);
            }
          } catch (e) {
            groups.putIfAbsent('Unknown', () => []).add(contact);
          }
        }
      }

      if (groups.isEmpty) {
        return {};
      }

      try {
        final sortedGroups = Map.fromEntries(
          groups.entries.toList()..sort((a, b) {
            final keyA = a.key;
            final keyB = b.key;

            if (keyA.toLowerCase().contains('unknown') &&
                !keyB.toLowerCase().contains('unknown')) {
              return 1;
            }
            if (!keyA.toLowerCase().contains('unknown') &&
                keyB.toLowerCase().contains('unknown')) {
              return -1;
            }

            return keyA.compareTo(keyB);
          }),
        );

        return sortedGroups;
      } catch (e) {
        return groups;
      }
    } catch (e) {
      return {};
    }
  }

  String _getGroupKey(Contact contact, String groupByField) {
    try {
      switch (groupByField) {
        case 'country_id':
          final country = contact.country;
          if (country == null ||
              country.trim().isEmpty ||
              country.toLowerCase() == 'false') {
            return 'Unknown Country';
          }
          return country.trim();
        case 'state_id':
          final state = contact.state;
          if (state == null ||
              state.trim().isEmpty ||
              state.toLowerCase() == 'false') {
            return 'Unknown State';
          }
          return state.trim();
        case 'city':
          final city = contact.city;
          if (city == null ||
              city.trim().isEmpty ||
              city.toLowerCase() == 'false') {
            return 'Unknown City';
          }
          return city.trim();
        case 'is_company':
          return contact.isCompany == true ? 'Companies' : 'Individuals';
        case 'company_id':
          final companyName = contact.companyName;
          if (companyName == null ||
              companyName.trim().isEmpty ||
              companyName.toLowerCase() == 'false') {
            return 'No Company';
          }
          return companyName.trim();
        case 'parent_id':
          final parentCompany = contact.companyName;
          if (parentCompany == null ||
              parentCompany.trim().isEmpty ||
              parentCompany.toLowerCase() == 'false') {
            return 'None';
          }
          return parentCompany.trim();
        case 'category_id':
          final ids = contact.categoryIds ?? const <int>[];
          if (ids.isEmpty) return 'No Tags';
          final id = ids.first;
          final name = _categoryNameCache[id];
          return (name == null || name.trim().isEmpty)
              ? 'Tag $id'
              : name.trim();
        case 'user_id':
          final salesperson = contact.salesperson;
          if (salesperson == null ||
              salesperson.trim().isEmpty ||
              salesperson.toLowerCase() == 'false') {
            return 'Unassigned';
          }
          return salesperson.trim();
        case 'create_date':
          if (contact.createdAt != null) {
            final date = contact.createdAt!;
            final monthNames = [
              'January',
              'February',
              'March',
              'April',
              'May',
              'June',
              'July',
              'August',
              'September',
              'October',
              'November',
              'December',
            ];
            return '${monthNames[date.month - 1]} ${date.year}';
          }
          return 'Unknown Date';
        case 'active':
          return contact.isActive == true ? 'Active' : 'Inactive';
        default:
          return 'Other';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<void> _fetchCategoryNames(Set<int> ids) async {
    if (ids.isEmpty) return;
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return;
      final idList = ids.toList();
      final result = await client.callKw({
        'model': 'res.partner.category',
        'method': 'read',
        'args': [idList],
        'kwargs': {
          'fields': ['name'],
        },
      });
      if (result is List) {
        for (final rec in result) {
          if (rec is Map && rec['id'] is int) {
            final id = rec['id'] as int;
            final name = rec['name']?.toString() ?? '';
            if (name.isNotEmpty) {
              _categoryNameCache[id] = name;
            }
          }
        }
      }
    } catch (e) {}
  }

  void updateContactCoordinates(Contact updatedContact) {
    final index = _contacts.indexWhere((c) => c.id == updatedContact.id);
    if (index != -1) {
      _contacts[index] = updatedContact;
      notifyListeners();
    }
  }

  void updateContact(Contact updatedContact) {
    final index = _contacts.indexWhere((c) => c.id == updatedContact.id);
    if (index != -1) {
      _contacts[index] = updatedContact;
      notifyListeners();
    }
  }

  Future<void> clearData() async {
    _contacts = [];
    _isLoading = false;
    _isLoadingMore = false;
    _isSearching = false;
    _currentPage = 0;
    _hasMoreData = true;
    _currentSearchQuery = '';
    _totalContacts = 0;
    _error = null;
    _lastFetchTime = null;
    _isServerUnreachable = false;
    _hasInitiallyLoaded = false;
    _accessErrorMessage = null;
    _base64ImageCache.clear();
    _groupByOptions = {};
    _selectedGroupBy = null;
    _isGrouped = false;
    _availableFields = [];
    _isFieldsFetched = false;
    notifyListeners();
  }

  void clearSearchState() {
    _currentSearchQuery = '';
    _currentFilters = null;
    notifyListeners();
  }

  String _getGroupKeyFromReadGroup(Map group, String groupByField) {
    final value = group[groupByField];
    if (value == null || value == false) {
      return 'Undefined';
    }

    if (value is List && value.length >= 2) {
      final name = value[1].toString();

      return name.isEmpty || name.toLowerCase() == 'false' ? 'Undefined' : name;
    }

    return value.toString();
  }

  List<dynamic> _buildGroupDomain(String groupKey, String groupByField) {
    if (groupKey == 'Undefined' ||
        groupKey == 'No Company' ||
        groupKey == 'None' ||
        groupKey == 'Unassigned') {
      return [
        '|',
        [groupByField, '=', false],
        [groupByField, '=', null],
      ];
    }

    if (groupByField.endsWith('_id')) {
      return [
        ['$groupByField.name', '=', groupKey],
      ];
    }

    return [
      [groupByField, '=', groupKey],
    ];
  }
}
