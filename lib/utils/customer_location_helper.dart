import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/contact.dart';
import '../services/session_service.dart';
import '../shared/widgets/mobo/mobo_dialog_buttons.dart';
import '../widgets/custom_snackbar.dart';
import '../widgets/loading_dialog.dart';

/// Logic for geolocalizing a customer and opening their location in a maps application.
Future<void> handleCustomerLocation({
  required BuildContext context,
  required BuildContext parentContext,
  required Contact contact,
  required void Function(Contact updatedContact) onContactUpdated,
  bool suppressMapRedirect = false,
  bool skipConfirmation = false,
}) async {
  final theme = Theme.of(parentContext);
  final isDark = theme.brightness == Brightness.dark;
  double? lat = contact.latitude;
  double? lng = contact.longitude;

  if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
    if (!suppressMapRedirect) {
      await _launchMaps(parentContext, lat, lng, contact.name);
    }
    return;
  }

  bool isEmptyOrFalse(String? value) =>
      value == null ||
      value.trim().isEmpty ||
      value.trim().toLowerCase() == 'false';
  final hasAddress =
      !isEmptyOrFalse(contact.street) ||
      !isEmptyOrFalse(contact.city) ||
      !isEmptyOrFalse(contact.zip);
  if (!hasAddress) {
    CustomSnackbar.showWarning(
      context,
      'Cannot geolocalize: No address available for this customer.',
    );
    return;
  }

  final bool shouldGeo;

  if (skipConfirmation) {
    shouldGeo = true;
  } else {
    shouldGeo =
        await showDialog<bool>(
          context: parentContext,
          barrierDismissible: true,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: isDark ? 0 : 8,
            backgroundColor: isDark ? Colors.grey[900] : Colors.white,
            title: Text(
              'Geolocalize Customer',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : theme.colorScheme.onSurface,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No location coordinates available. Would you like to geolocalize this customer using their address?',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark
                        ? Colors.grey[300]
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.orange[900]?.withOpacity(0.2)
                        : Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.orange[700]! : Colors.orange[200]!,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: isDark ? Colors.orange[300] : Colors.orange[700],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Note: Geolocation must be enabled in Odoo settings. It is OFF by default.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.orange[300]
                                : Colors.orange[700],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            actions: [
              MoboDialogButtons(
                secondaryLabel: 'Cancel',
                onSecondary: () => Navigator.of(ctx).pop(false),
                primaryLabel: 'Geolocalize',
                onPrimary: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        ) ??
        false;
  }

  if (shouldGeo == true) {
    BuildContext? dialogContext;

    showDialog(
      context: parentContext,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return const LoadingDialog(
          message: 'Geolocalizing customer...',
          subtitle: 'Please wait while we fetch the location.',
        );
      },
    );
    final updatedContact = await _geoLocalizeCustomer(parentContext, contact);
    if (dialogContext != null && Navigator.of(dialogContext!).canPop()) {
      Navigator.of(dialogContext!).pop();
    }
    if (updatedContact != null &&
        updatedContact.latitude != null &&
        updatedContact.longitude != null &&
        updatedContact.latitude != 0.0 &&
        updatedContact.longitude != 0.0) {
      onContactUpdated(updatedContact);
      if (!suppressMapRedirect) {}

      if (parentContext.mounted) {
        CustomSnackbar.showSuccess(context, 'Geolocalization successful!');
      }
    } else {
      if (parentContext.mounted) {
        CustomSnackbar.showError(
          context,
          'No valid location data found after geolocalization',
        );
      }
    }
  }
}

Future<void> _launchMaps(
  BuildContext context,
  double lat,
  double lng,
  String label,
) async {
  final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');

  try {
    if (await canLaunchUrl(geoUri)) {
      await launchUrl(geoUri, mode: LaunchMode.externalApplication);
      return;
    }
  } catch (e) {}

  final webUri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
  );

  try {
    if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
      return;
    }
  } catch (e) {}

  final fallbackUri = Uri.parse('https://maps.google.com/?q=$lat,$lng');

  try {
    if (await canLaunchUrl(fallbackUri)) {
      await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      return;
    }
  } catch (e) {}

  if (context.mounted) {
    CustomSnackbar.showError(
      context,
      'Could not open Maps application. Please install Google Maps or another maps app.',
    );
  }
}

Future<Contact?> _geoLocalizeCustomer(
  BuildContext context,
  Contact contact,
) async {
  try {
    final sessionService = Provider.of<SessionService>(context, listen: false);
    final client = await sessionService.client;
    if (client == null) {
      _showErrorSnackBar(context, 'No active session. Please log in again.');
      return null;
    }

    final result = await client.callKw({
      'model': 'res.partner',
      'method': 'geo_localize',
      'args': [
        [contact.id],
      ],
      'kwargs': {
        'context': {'force_geo_localize': true},
      },
    });

    if (result == true) {
      final customerResult = await client.callKw({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', contact.id],
          ],
        ],
        // Only the coordinates. An empty list reads every field, including
        // the contact statistics Odoo 20 added, which count documents across
        // every installed app: a lot of work to get two numbers.
        'kwargs': {
          'fields': ['partner_latitude', 'partner_longitude'],
          'limit': 1,
        },
      });

      if (customerResult is List && customerResult.isNotEmpty) {
        final updatedData = customerResult[0];
        return contact.copyWith(
          latitude: updatedData['partner_latitude']?.toDouble(),
          longitude: updatedData['partner_longitude']?.toDouble(),
        );
      }
    }
    _showErrorSnackBar(context, 'Geolocation data could not be retrieved.');
    return null;
  } catch (e) {
    String userMessage =
        'Geolocation is currently unavailable. Please try again later.';
    if (e.toString().contains('res.partner.geo_localize')) {
      userMessage =
          'Geolocation is not enabled on the server. Contact your administrator to enable this feature.';
    } else {}
    _showErrorSnackBar(context, userMessage);
    return null;
  }
}

void _showErrorSnackBar(BuildContext context, String message) {
  CustomSnackbar.showError(context, message);
}
