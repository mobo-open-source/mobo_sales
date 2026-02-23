import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Monitors network connectivity and notifies listeners on changes.
class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService instance = ConnectivityService._internal();
  factory ConnectivityService() => instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isConnected = true;
  bool _isInitialized = false;

  /// Whether the device currently has an active network connection.
  bool get isConnected => _isConnected;

  /// Whether the service has completed its initial connectivity check.
  bool get isInitialized => _isInitialized;

  /// Initialises the service and starts listening for connectivity changes.
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _checkConnectivity();

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      _updateConnectivityStatus(results);
    });

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateConnectivityStatus(results);
    } catch (e) {
      _isConnected = false;
      notifyListeners();
    }
  }

  void _updateConnectivityStatus(List<ConnectivityResult> results) {
    final wasConnected = _isConnected;
    _isConnected = !results.contains(ConnectivityResult.none);

    if (wasConnected != _isConnected) {
      notifyListeners();
    }
  }

  /// Performs a one-off connectivity check and returns the result.
  Future<bool> checkConnectivityOnce() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return !results.contains(ConnectivityResult.none);
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
