import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Represents a recently accessed record (quotation, invoice, product, etc.).
class LastOpenedItem {
  final String id;
  final String type;
  final String title;
  final String subtitle;
  final String route;
  final Map<String, dynamic>? data;
  final DateTime lastAccessed;

  final String iconKey;

  LastOpenedItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.route,
    this.data,
    required this.lastAccessed,
    required this.iconKey,
  });

  /// Serialises this item to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'subtitle': subtitle,
      'route': route,
      'data': data,
      'lastAccessed': lastAccessed.toIso8601String(),
      'iconKey': iconKey,
    };
  }

  /// Returns the [IconData] corresponding to the stored icon [key].
  static IconData iconFromKey(String key) {
    switch (key) {
      case 'description_outlined':
        return Icons.description_outlined;
      case 'receipt_outlined':
        return Icons.receipt_outlined;
      case 'inventory_2_outlined':
        return Icons.inventory_2_outlined;
      case 'person_outline':
        return Icons.person_outline;
      case 'settings':
        return Icons.settings;
      case 'profile':
        return Icons.person;
      case 'dashboard':
        return Icons.dashboard_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  static String _iconKeyForIcon(IconData icon) {
    if (identical(icon, Icons.description_outlined)) {
      return 'description_outlined';
    }
    if (identical(icon, Icons.receipt_outlined)) return 'receipt_outlined';
    if (identical(icon, Icons.inventory_2_outlined)) {
      return 'inventory_2_outlined';
    }
    if (identical(icon, Icons.person_outline)) return 'person_outline';
    if (identical(icon, Icons.settings)) return 'settings';
    if (identical(icon, Icons.person)) return 'profile';
    if (identical(icon, Icons.dashboard_outlined)) return 'dashboard';
    return 'page';
  }

  /// Deserialises a [LastOpenedItem] from a JSON map.
  static LastOpenedItem fromJson(Map<String, dynamic> json) {
    return LastOpenedItem(
      id: json['id'],
      type: json['type'],
      title: json['title'],
      subtitle: json['subtitle'],
      route: json['route'],
      data: json['data'],
      lastAccessed: DateTime.parse(json['lastAccessed']),
      iconKey: json['iconKey'] ?? 'page',
    );
  }
}

/// Tracks and persists the last accessed records for the current session.
class LastOpenedProvider extends ChangeNotifier {
  String? _currentSessionId;
  String get _storageKey => _currentSessionId != null
      ? 'last_opened_items_$_currentSessionId'
      : 'last_opened_items';
  static const int _maxItems = 10;

  List<LastOpenedItem> _items = [];

  static IconData iconFromKey(String key) => LastOpenedItem.iconFromKey(key);

  List<LastOpenedItem> get items {
    final businessItems = _items.where((item) {
      if (['quotation', 'invoice', 'product', 'customer'].contains(item.type)) {
        return true;
      }

      if (item.type == 'page') {
        final excludedRoutes = {'/settings', '/profile'};
        return !excludedRoutes.contains(item.route);
      }

      return true;
    }).toList();

    return List.unmodifiable(businessItems);
  }

  LastOpenedItem? get lastOpened => _items.isNotEmpty ? _items.first : null;

  LastOpenedProvider() {
    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString != null) {
        final List<dynamic> jsonList = json.decode(jsonString);
        _items = jsonList.map((json) => LastOpenedItem.fromJson(json)).toList();

        _items.sort((a, b) => b.lastAccessed.compareTo(a.lastAccessed));
      } else {
        _items = [];
      }
      notifyListeners();
    } catch (e) {
      _items = [];
      notifyListeners();
    }
  }

  Future<void> _saveItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _items.map((item) => item.toJson()).toList();
      await prefs.setString(_storageKey, json.encode(jsonList));
    } catch (e) {}
  }

  /// Reloads items when the active session changes.
  void updateSession(String? sessionId) {
    if (_currentSessionId == sessionId) return;
    _currentSessionId = sessionId;
    _loadItems();
  }

  /// Adds [item] to the top of the history, removing any duplicate.
  Future<void> addItem(LastOpenedItem item) async {
    _items.removeWhere((existingItem) => existingItem.id == item.id);

    _items.insert(0, item);

    if (_items.length > _maxItems) {
      _items = _items.take(_maxItems).toList();
    }

    await _saveItems();
    notifyListeners();
  }

  /// Records access to a quotation identified by [quotationId].
  Future<void> trackQuotationAccess({
    required String quotationId,
    required String quotationName,
    required String customerName,
    Map<String, dynamic>? quotationData,
  }) async {
    final item = LastOpenedItem(
      id: 'quotation_$quotationId',
      type: 'quotation',
      title: quotationName,
      subtitle: 'Quotation for $customerName',
      route: '/quotation_details',
      data: quotationData,
      lastAccessed: DateTime.now(),
      iconKey: 'description_outlined',
    );

    await addItem(item);
  }

  /// Records access to an invoice identified by [invoiceId].
  Future<void> trackInvoiceAccess({
    required String invoiceId,
    required String invoiceName,
    required String customerName,
    Map<String, dynamic>? invoiceData,
  }) async {
    final item = LastOpenedItem(
      id: 'invoice_$invoiceId',
      type: 'invoice',
      title: invoiceName,
      subtitle: 'Invoice for $customerName',
      route: '/invoice_details',
      data: invoiceData,
      lastAccessed: DateTime.now(),
      iconKey: 'receipt_outlined',
    );

    await addItem(item);
  }

  /// Records access to a product identified by [productId].
  Future<void> trackProductAccess({
    required String productId,
    required String productName,
    String? category,
    Map<String, dynamic>? productData,
  }) async {
    final item = LastOpenedItem(
      id: 'product_$productId',
      type: 'product',
      title: productName,
      subtitle: category != null ? 'Product in $category' : 'Product',
      route: '/product_details',
      data: productData,
      lastAccessed: DateTime.now(),
      iconKey: 'inventory_2_outlined',
    );

    await addItem(item);
  }

  /// Records access to a customer identified by [customerId].
  Future<void> trackCustomerAccess({
    required String customerId,
    required String customerName,
    String? customerType,
    Map<String, dynamic>? customerData,
  }) async {
    final item = LastOpenedItem(
      id: 'customer_$customerId',
      type: 'customer',
      title: customerName,
      subtitle: customerType ?? 'Customer',
      route: '/customer_details',
      data: customerData,
      lastAccessed: DateTime.now(),
      iconKey: 'person_outline',
    );

    await addItem(item);
  }

  /// Records access to a generic page, excluding settings and profile.
  Future<void> trackPageAccess({
    required String pageId,
    required String pageTitle,
    required String pageSubtitle,
    required String route,
    required IconData icon,
    Map<String, dynamic>? pageData,
  }) async {
    final excludedPages = {'settings', 'profile'};
    if (excludedPages.contains(pageId)) {
      return;
    }

    final item = LastOpenedItem(
      id: 'page_$pageId',
      type: 'page',
      title: pageTitle,
      subtitle: pageSubtitle,
      route: route,
      data: pageData,
      lastAccessed: DateTime.now(),
      iconKey: LastOpenedItem._iconKeyForIcon(icon),
    );

    await addItem(item);
  }

  /// Clears all history items.
  Future<void> clearItems() async {
    _items.clear();
    await _saveItems();
    notifyListeners();
  }

  /// Removes a single item with [itemId] from the history.
  Future<void> removeItem(String itemId) async {
    _items.removeWhere((item) => item.id == itemId);
    await _saveItems();
    notifyListeners();
  }

  /// Returns a human-readable relative time string for [dateTime] (e.g. '5m ago').
  String getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${(difference.inDays / 7).floor()}w ago';
    }
  }
}
