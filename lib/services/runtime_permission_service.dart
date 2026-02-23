import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/custom_snackbar.dart';

class RuntimePermissionService {
  static Future<bool> requestMicrophonePermission(
    BuildContext context, {
    bool showRationale = true,
  }) async {
    try {
      var status = await Permission.microphone.status;

      if (status.isGranted) return true;

      if (showRationale &&
          await Permission.microphone.shouldShowRequestRationale) {
        final shouldRequest = await _showPermissionRationale(
          context,
          'Microphone Access',
          'This app needs microphone access to enable voice search functionality. You can search for products, customers, and invoices using your voice.',
          Icons.mic,
        );

        if (!shouldRequest) return false;
      }

      status = await Permission.microphone.request();

      if (status.isPermanentlyDenied) {
        await _showPermanentlyDeniedDialog(
          context,
          'Microphone Permission',
          'Microphone permission is permanently denied. Please enable it in app settings to use voice search.',
        );
        return false;
      }

      if (!status.isGranted) {
        if (context.mounted) {
          CustomSnackbar.showError(
            context,
            'Microphone permission denied. Voice search will not work.',
          );
        }
        return false;
      }

      return true;
    } catch (e) {
      if (context.mounted) {
        CustomSnackbar.showError(
          context,
          'Failed to request microphone permission',
        );
      }
      return false;
    }
  }

  static Future<bool> requestCameraPermission(
    BuildContext context, {
    bool showRationale = true,
  }) async {
    try {
      var status = await Permission.camera.status;

      if (status.isGranted) return true;

      if (showRationale && await Permission.camera.shouldShowRequestRationale) {
        final shouldRequest = await _showPermissionRationale(
          context,
          'Camera Access',
          'This app needs camera access to scan barcodes and QR codes for quick product lookup and invoice processing.',
          Icons.camera_alt,
        );

        if (!shouldRequest) return false;
      }

      status = await Permission.camera.request();

      if (status.isPermanentlyDenied) {
        await _showPermanentlyDeniedDialog(
          context,
          'Camera Permission',
          'Camera permission is permanently denied. Please enable it in app settings to use scanning features.',
        );
        return false;
      }

      if (!status.isGranted) {
        if (context.mounted) {
          CustomSnackbar.showError(
            context,
            'Camera permission denied. Scanning will not work.',
          );
        }
        return false;
      }

      return true;
    } catch (e) {
      if (context.mounted) {
        CustomSnackbar.showError(
          context,
          'Failed to request camera permission',
        );
      }
      return false;
    }
  }

  static Future<bool> requestLocationPermission(
    BuildContext context, {
    bool showRationale = true,
  }) async {
    try {
      var status = await Permission.location.status;

      if (status.isGranted) return true;

      if (showRationale &&
          await Permission.location.shouldShowRequestRationale) {
        final shouldRequest = await _showPermissionRationale(
          context,
          'Location Access',
          'This app needs location access to show customer locations on maps, find nearby customers, and provide location-based services.',
          Icons.location_on,
        );

        if (!shouldRequest) return false;
      }

      status = await Permission.location.request();

      if (status.isPermanentlyDenied) {
        await _showPermanentlyDeniedDialog(
          context,
          'Location Permission',
          'Location permission is permanently denied. Please enable it in app settings to use location features.',
        );
        return false;
      }

      if (!status.isGranted) {
        if (context.mounted) {
          CustomSnackbar.showError(
            context,
            'Location permission denied. Location features will not work.',
          );
        }
        return false;
      }

      return true;
    } catch (e) {
      if (context.mounted) {
        CustomSnackbar.showError(
          context,
          'Failed to request location permission',
        );
      }
      return false;
    }
  }

  static Future<bool> requestPhonePermission(
    BuildContext context, {
    bool showRationale = true,
  }) async {
    try {
      var status = await Permission.phone.status;

      if (status.isGranted) return true;

      if (showRationale && await Permission.phone.shouldShowRequestRationale) {
        final shouldRequest = await _showPermissionRationale(
          context,
          'Phone Access',
          'This app needs phone access to make direct calls to customers from their contact information.',
          Icons.phone,
        );

        if (!shouldRequest) return false;
      }

      status = await Permission.phone.request();

      if (status.isPermanentlyDenied) {
        await _showPermanentlyDeniedDialog(
          context,
          'Phone Permission',
          'Phone permission is permanently denied. Please enable it in app settings to make calls.',
        );
        return false;
      }

      if (!status.isGranted) {
        if (context.mounted) {
          CustomSnackbar.showError(
            context,
            'Phone permission denied. Calling will not work.',
          );
        }
        return false;
      }

      return true;
    } catch (e) {
      if (context.mounted) {
        CustomSnackbar.showError(context, 'Failed to request phone permission');
      }
      return false;
    }
  }

  static Future<bool> requestStoragePermission(
    BuildContext context, {
    bool showRationale = true,
  }) async {
    try {
      Permission permission;

      if (Platform.isAndroid) {
        final androidInfo = await Permission.storage.status;

        permission = Permission.photos;
        var status = await permission.status;

        if (status == PermissionStatus.denied) {
          permission = Permission.storage;
          status = await permission.status;
        }

        if (status.isGranted) return true;
      } else {
        permission = Permission.photos;
        var status = await permission.status;
        if (status.isGranted) return true;
      }

      if (showRationale && await permission.shouldShowRequestRationale) {
        final shouldRequest = await _showPermissionRationale(
          context,
          'Storage Access',
          'This app needs storage access to save and share documents, invoices, and other files.',
          Icons.folder,
        );

        if (!shouldRequest) return false;
      }

      final status = await permission.request();

      if (status.isPermanentlyDenied) {
        await _showPermanentlyDeniedDialog(
          context,
          'Storage Permission',
          'Storage permission is permanently denied. Please enable it in app settings to save and share files.',
        );
        return false;
      }

      if (!status.isGranted) {
        if (context.mounted) {
          CustomSnackbar.showError(
            context,
            'Storage permission denied. File operations may not work.',
          );
        }
        return false;
      }

      return true;
    } catch (e) {
      if (context.mounted) {
        CustomSnackbar.showError(
          context,
          'Failed to request storage permission',
        );
      }
      return false;
    }
  }

  static Future<bool> _showPermissionRationale(
    BuildContext context,
    String title,
    String message,
    IconData icon,
  ) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(icon, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 12),
                  Expanded(child: Text(title)),
                ],
              ),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Not Now'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Grant Permission'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  static Future<void> _showPermanentlyDeniedDialog(
    BuildContext context,
    String title,
    String message,
  ) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.settings, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 12),
              Expanded(child: Text(title)),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  static Future<bool> isPermissionGranted(Permission permission) async {
    final status = await permission.status;
    return status.isGranted;
  }

  static Future<Map<Permission, bool>> checkMultiplePermissions(
    List<Permission> permissions,
  ) async {
    final Map<Permission, bool> results = {};

    for (final permission in permissions) {
      results[permission] = await isPermissionGranted(permission);
    }

    return results;
  }
}
