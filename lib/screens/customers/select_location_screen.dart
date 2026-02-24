import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/runtime_permission_service.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class SelectLocationScreen extends StatefulWidget {
  final LatLng? initialLocation;
  final Future<bool> Function(LatLng)? onSaveLocation;

  const SelectLocationScreen({
    super.key,
    this.initialLocation,
    this.onSaveLocation,
  });

  @override
  _SelectLocationScreenState createState() => _SelectLocationScreenState();
}

class _SelectLocationScreenState extends State<SelectLocationScreen> {
  LatLng? _selectedLocation;
  LatLng? _currentLocation;
  bool _isLocationLoading = true;
  bool _hasLocationPermission = false;
  String? _errorMessage;
  final MapController _mapController = MapController();
  bool _mapReady = false;
  bool _pendingMoveToCurrentLocation = false;
  bool _isSaving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    try {
      await _getCurrentLocation();
    } catch (e) {
      _handleLocationError(
        'Failed to initialize location:  [31m${e.toString()} [0m',
      );
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLocationLoading = true;
      _errorMessage = null;
    });

    if (widget.initialLocation != null) {
      setState(() {
        _currentLocation = widget.initialLocation;
        _isLocationLoading = false;
      });

      if (_mapReady) {
        _mapController.move(_currentLocation!, 15.0);
      } else {
        _pendingMoveToCurrentLocation = true;
      }
      return;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _handleLocationError(
          'Location services are disabled. Please enable them in settings.',
        );
        return;
      }

      final hasLocationPermission =
          await RuntimePermissionService.requestLocationPermission(context);
      if (!hasLocationPermission) {
        _handleLocationError(
          'Location permission is required to use this feature.',
        );
        return;
      }

      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        );

        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _hasLocationPermission = true;
          _isLocationLoading = false;
          _errorMessage = null;
        });

        if (_mapReady && _currentLocation != null) {
          _mapController.move(_currentLocation!, 15.0);
        } else if (_currentLocation != null) {
          _pendingMoveToCurrentLocation = true;
        }
      } on TimeoutException {
        _handleLocationError('Location request timed out. Please try again.');
      } catch (e) {
        _handleLocationError('Unable to get location: ${e.toString()}');
      }
    } catch (e) {
      _handleLocationError('Unable to get location: ${e.toString()}');
    }
  }

  void _handleLocationError(String message) {
    setState(() {
      _isLocationLoading = false;
      _errorMessage = message;
      _hasLocationPermission = false;
    });
  }

  Future<void> _recenterMap() async {
    setState(() {
      _isLocationLoading = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _handleLocationError('Location services are disabled');
        return;
      }

      final hasLocationPermission =
          await RuntimePermissionService.requestLocationPermission(context);
      if (!hasLocationPermission) {
        _handleLocationError(
          'Location permission is required to use this feature.',
        );
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 30),
      );

      final deviceLocation = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentLocation = deviceLocation;
        _isLocationLoading = false;
      });

      if (_mapReady) {
        _mapController.move(deviceLocation, 15.0);
      }
    } catch (e) {
      _handleLocationError('Failed to get current location: ${e.toString()}');
    }
  }

  void _onMapReady() {
    setState(() {
      _mapReady = true;
    });
    if (_pendingMoveToCurrentLocation && _currentLocation != null) {
      _mapController.move(_currentLocation!, 15.0);
      _pendingMoveToCurrentLocation = false;
    }
  }

  void _retryLocation() {
    _getCurrentLocation();
  }

  Future<void> _confirmLocation() async {
    if (_selectedLocation == null || widget.onSaveLocation == null) return;
    if (!mounted) return;
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    bool success = false;
    try {
      success = await widget.onSaveLocation!(_selectedLocation!);
    } catch (e) {
      success = false;
    }
    if (!mounted) return;
    if (success) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pop(context, _selectedLocation);
        }
      });
    } else {
      setState(() {
        _isSaving = false;
        _saveError = 'Failed to save location.';
      });
    }
  }

  void _showLocationHelp() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Location Help'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• Tap anywhere on the map to select a location'),
            SizedBox(height: 8),
            Text(
              '• Use the location button to center on your current position',
            ),
            SizedBox(height: 8),
            Text('• Red marker shows your selected location'),
            SizedBox(height: 8),
            Text('• The other one shows your current location'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Got it',
              style: TextStyle(
                color: isDark
                    ? Colors.white
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Select Location',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(HugeIcons.strokeRoundedArrowLeft01),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline),
            onPressed: _showLocationHelp,
            tooltip: 'Help',
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_isLocationLoading)
            Container(
              color: colorScheme.surface,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    LoadingAnimationWidget.fourRotatingDots(
                      color: isDark
                          ? Colors.white
                          : Theme.of(context).colorScheme.primary,
                      size: 50,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Getting your location...',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please wait while we fetch your current location.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_errorMessage != null && !_isLocationLoading)
            Container(
              color: colorScheme.surface,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.location_off,
                        size: 64,
                        color: colorScheme.error,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Location Error',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _retryLocation,
                        icon: Icon(Icons.refresh, color: colorScheme.onPrimary),
                        label: Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (!_isLocationLoading && _errorMessage == null)
            ClipRRect(
              borderRadius: BorderRadius.zero,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentLocation ?? LatLng(20, 0),
                  initialZoom: _currentLocation != null ? 15.0 : 2.0,
                  minZoom: 2.0,
                  maxZoom: 18.0,
                  onTap: (tapPosition, latLng) {
                    setState(() {
                      _selectedLocation = latLng;
                    });
                  },
                  onMapReady: _onMapReady,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.sales_app',
                    errorTileCallback: (tile, error, [stackTrace]) {},
                  ),
                  if (_currentLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _currentLocation!,
                          width: 50,
                          height: 50,
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorScheme.surface,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.my_location,
                              color: colorScheme.onPrimary,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (_selectedLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _selectedLocation!,
                          width: 50,
                          height: 50,
                          child: Container(
                            decoration: BoxDecoration(
                              color: colorScheme.error,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorScheme.surface,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.location_on,
                              color: colorScheme.onError,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

          if (!_isLocationLoading && _errorMessage == null)
            Positioned(
              bottom: _selectedLocation != null ? 160 : 100,
              right: 16,
              child: Column(
                children: [
                  FloatingActionButton(
                    heroTag: 'recenter',
                    mini: true,
                    backgroundColor: colorScheme.surface,
                    foregroundColor: colorScheme.onSurface,
                    elevation: 4,
                    onPressed: _currentLocation != null && _mapReady
                        ? _recenterMap
                        : null,
                    tooltip: 'Recenter to your location',
                    child: Icon(Icons.my_location),
                  ),
                  SizedBox(height: 8),
                  FloatingActionButton(
                    heroTag: 'retry',
                    mini: true,
                    backgroundColor: colorScheme.surface,
                    foregroundColor: colorScheme.onSurface,
                    elevation: 4,
                    onPressed: _retryLocation,
                    tooltip: 'Refresh location',
                    child: Icon(Icons.refresh),
                  ),
                ],
              ),
            ),

          if (!_isLocationLoading &&
              _errorMessage == null &&
              _selectedLocation == null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: isDark
                          ? Colors.white
                          : Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tap anywhere on the map to select a location',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_isSaving)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                  color: Colors.black.withOpacity(0.6),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[900]
                            : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.1)
                                  : Theme.of(
                                      context,
                                    ).primaryColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: LoadingAnimationWidget.fourRotatingDots(
                              color: isDark
                                  ? Colors.white
                                  : Theme.of(context).primaryColor,
                              size: 35,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Saving location...',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Colors.grey[800],
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Please wait while we save your location',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.grey[300]
                                      : Colors.grey[600],
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_saveError != null && !_isSaving)
            Positioned(
              bottom: 32,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[400],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _saveError!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _selectedLocation != null
          ? FloatingActionButton.extended(
              onPressed: _isSaving ? null : _confirmLocation,
              backgroundColor: isDark
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              elevation: 6,
              label: _isSaving
                  ? Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Saving...',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Confirm Location',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
              icon: _isSaving ? null : Icon(Icons.check, color: Colors.white),
            )
          : null,
    );
  }
}
