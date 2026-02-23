import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/contact.dart';
import '../screens/customers/select_location_screen.dart';
import '../services/session_service.dart';
import 'custom_snackbar.dart';

class LocationMapWidget extends StatefulWidget {
  final double latitude;
  final double longitude;
  final Contact contact;
  final VoidCallback onOpenMap;
  final VoidCallback? onCoordinatesRemoved;

  const LocationMapWidget({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.contact,
    required this.onOpenMap,
    this.onCoordinatesRemoved,
  });

  @override
  State<LocationMapWidget> createState() => _LocationMapWidgetState();
}

class _LocationMapWidgetState extends State<LocationMapWidget> {
  bool _tileError = false;
  late Contact _contact;

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
  }

  Future<void> _showRemoveCoordinatesDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Remove Coordinates',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  'Are you sure you want to remove ${_contact.name}\'s coordinates?',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          backgroundColor: isDark ? const Color(0xFF181A20) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(
                'Remove',
                style: TextStyle(
                  color: isDark ? Colors.white : primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                await _resetLocation();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _resetLocation() async {
    final sessionService = Provider.of<SessionService>(context, listen: false);
    final client = await sessionService.client;
    if (client == null) return;

    try {
      final result = await client.callKw({
        'model': 'res.partner',
        'method': 'write',
        'args': [
          [_contact.id],
          {},
        ],
        'kwargs': {},
      });

      if (result == true) {
        setState(() {
          _contact = _contact.copyWith(latitude: 0.0, longitude: 0.0);
        });
        if (widget.onCoordinatesRemoved != null) {
          widget.onCoordinatesRemoved!();
        }
        if (mounted) {
          CustomSnackbar.showSuccess(context, 'Location reset successfully!');
        }
      } else {
        if (mounted) {
          CustomSnackbar.showError(context, 'Failed to reset location');
        }
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(context, 'Error: $e');
      }
    }
  }

  Future<void> _openSelectLocationScreen() async {
    final LatLng? selected = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SelectLocationScreen(
          initialLocation: _contact.hasValidCoordinates()
              ? LatLng(_contact.latitude!, _contact.longitude!)
              : null,
          onSaveLocation: (LatLng latLng) async {
            final sessionService = Provider.of<SessionService>(
              context,
              listen: false,
            );
            final client = await sessionService.client;
            if (client == null) {
              return false;
            }
            try {
              final result = await client.callKw({
                'model': 'res.partner',
                'method': 'write',
                'args': [
                  [_contact.id],
                  {
                    'partner_latitude': latLng.latitude,
                    'partner_longitude': latLng.longitude,
                  },
                ],
                'kwargs': {},
              });
              Future.microtask(() {
                CustomSnackbar.showSuccess(
                  context,
                  'Location updated successfully!',
                );
              });
              if (result == true) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _contact = _contact.copyWith(
                        latitude: latLng.latitude,
                        longitude: latLng.longitude,
                      );
                    });
                  }
                });
                return true;
              } else {
                return false;
              }
            } catch (e) {
              return false;
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181A20) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.map,
                      size: 18,
                      color: isDark
                          ? Colors.white
                          : _getThemedIconColor(context),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Location',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  size: 20,
                ),
                color: isDark ? Colors.grey[900] : Colors.white,
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (String value) {
                  if (value == 'change_coordinates') {
                    _openSelectLocationScreen();
                  } else if (value == 'open_in_maps') {
                    widget.onOpenMap();
                  } else if (value == 'remove_coordinates') {
                    _showRemoveCoordinatesDialog();
                  }
                },
                itemBuilder: (BuildContext context) => [
                  PopupMenuItem<String>(
                    value: 'open_in_maps',
                    child: Row(
                      children: [
                        Icon(
                          HugeIcons.strokeRoundedMaps,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Open in Maps',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'change_coordinates',
                    child: Row(
                      children: [
                        Icon(
                          HugeIcons.strokeRoundedCoordinate01,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Change Location',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'remove_coordinates',
                    child: Row(
                      children: [
                        Icon(
                          HugeIcons.strokeRoundedDelete02,
                          color: Colors.red[400],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Remove Coordinates',
                          style: TextStyle(
                            color: Colors.red[400],
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                tooltip: 'Menu',
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(widget.latitude, widget.longitude),
                      initialZoom: 15.0,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://cartodb-basemaps-a.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.yourapp.package',
                        maxZoom: 19,
                        errorTileCallback: (tile, error, stackTrace) {
                          if (!_tileError) {
                            setState(() {
                              _tileError = true;
                            });
                          }
                        },
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            width: 40.0,
                            height: 40.0,
                            point: LatLng(widget.latitude, widget.longitude),
                            child: Icon(
                              Icons.location_pin,
                              color: isDark
                                  ? Colors.grey.shade700
                                  : primaryColor,
                              size: 40.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.black.withOpacity(0.7)
                            : Colors.white.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                        ),
                      ),
                      child: Text(
                        '${widget.latitude.toStringAsFixed(6)}, ${widget.longitude.toStringAsFixed(6)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[300] : Colors.grey[500],
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  if (_tileError)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          alignment: Alignment.center,
                          child: Opacity(
                            opacity: 0.85,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.map_outlined,
                                  size: 48,
                                  color: isDark
                                      ? Colors.grey[700]
                                      : Colors.grey[400],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Map tiles unavailable',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.grey[300]
                                        : Colors.grey[600],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Check your network connection.',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getThemedIconColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? Theme.of(context).colorScheme.secondary
        : Theme.of(context).primaryColor;
  }
}
