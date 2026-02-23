import 'dart:convert';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import '../models/contact.dart';

class CustomerListTile extends StatelessWidget {
  final Contact contact;
  final VoidCallback? onTap;
  final Widget? popupMenu;
  final bool isDark;
  final Map<String, Uint8List>? imageCache;
  final VoidCallback? onCall;
  final VoidCallback? onMessage;
  final VoidCallback? onEmail;
  final VoidCallback? onLocation;

  const CustomerListTile({
    super.key,
    required this.contact,
    this.onTap,
    this.popupMenu,
    required this.isDark,
    this.imageCache,
    this.onCall,
    this.onMessage,
    this.onEmail,
    this.onLocation,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[850] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey[850]! : Colors.grey[200]!,
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 6),
              spreadRadius: 2,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.only(
            left: 16,
            right: 12,
            top: 12,
            bottom: 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAvatar(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white
                                : AppTheme.primaryColor,
                            letterSpacing: -0.1,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),

                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _hasValidPhone()
                                ? contact.phone!
                                : 'No phone number',
                            style: TextStyle(
                              fontSize: 12,
                              color: _hasValidPhone()
                                  ? (isDark
                                        ? Colors.grey[100]
                                        : Color(0xff6D717F))
                                  : (isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[400]),
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0,
                              fontStyle: _hasValidPhone()
                                  ? FontStyle.normal
                                  : FontStyle.italic,
                            ),
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _hasValidAddress()
                                ? _getFormattedAddress()
                                : 'No address available',
                            style: TextStyle(
                              fontSize: 12,
                              color: _hasValidAddress()
                                  ? (isDark
                                        ? Colors.grey[100]
                                        : Color(0xff6D717F))
                                  : (isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[400]),
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0,
                              fontStyle: _hasValidAddress()
                                  ? FontStyle.normal
                                  : FontStyle.italic,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      _buildContactBadge(),
                      if (popupMenu != null) ...[
                        popupMenu!,
                      ] else ...[
                        _buildActionMenu(),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : Colors.black.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          color: isDark ? Colors.grey[800] : Colors.grey[100],
          child: _buildImageWidget(),
        ),
      ),
    );
  }

  Widget _buildImageWidget() {
    final imageUrl = contact.imageUrl;

    if (imageUrl != null && imageUrl.isNotEmpty && imageUrl != 'false') {
      if (imageUrl.startsWith('http')) {
        return CachedNetworkImage(
          imageUrl: imageUrl,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: isDark ? Colors.grey[800] : Colors.grey[100],
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
            ),
          ),
          errorWidget: (context, url, error) => _buildAvatarFallback(),
        );
      } else {
        return _buildBase64Image();
      }
    }

    return _buildAvatarFallback();
  }

  Widget _buildBase64Image() {
    final imageUrl = contact.imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) {
      return _buildAvatarFallback();
    }

    if (imageUrl.toLowerCase() == 'false' || imageUrl.length < 24) {
      return _buildAvatarFallback();
    }

    if (imageCache?.containsKey(imageUrl) == true) {
      return Image.memory(
        imageCache![imageUrl]!,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildAvatarFallback(),
      );
    }

    try {
      final base64String = imageUrl.contains(',')
          ? imageUrl.split(',').last
          : imageUrl;

      if (!RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(base64String)) {
        return _buildAvatarFallback();
      }

      if (base64String.length < 4 ||
          (base64String.length % 4 != 0 &&
              base64String.length % 4 != 2 &&
              base64String.length % 4 != 3)) {
        return _buildAvatarFallback();
      }

      final bytes = base64Decode(base64String);

      if (imageCache != null) {
        imageCache![imageUrl] = bytes;
      }

      return Image.memory(
        bytes,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildAvatarFallback(),
      );
    } catch (e) {
      return _buildAvatarFallback();
    }
  }

  Widget _buildAvatarFallback() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          colors: [Colors.grey[300]!, Colors.grey[400]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          contact.name.isNotEmpty
              ? contact.name.length >= 2
                    ? contact.name.substring(0, 2).toUpperCase()
                    : contact.name.substring(0, 1).toUpperCase()
              : '?',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildContactBadge() {
    final isCompany = contact.isCompany ?? false;
    final badgeText = isCompany ? 'Company' : 'Customer';

    final badgeColor = isCompany ? Colors.blue : Colors.green;

    final textColor = isDark ? Colors.white : badgeColor;
    final backgroundColor = isDark
        ? Colors.white.withOpacity(0.15)
        : badgeColor.withOpacity(0.10);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        badgeText,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  bool _hasValidAddress() {
    return (contact.street != null &&
            contact.street!.isNotEmpty &&
            contact.street != 'false') ||
        (contact.street2 != null &&
            contact.street2!.isNotEmpty &&
            contact.street2 != 'false') ||
        (contact.city != null &&
            contact.city!.isNotEmpty &&
            contact.city != 'false') ||
        (contact.state != null &&
            contact.state!.isNotEmpty &&
            contact.state != 'false') ||
        (contact.zip != null &&
            contact.zip!.isNotEmpty &&
            contact.zip != 'false') ||
        (contact.country != null &&
            contact.country!.isNotEmpty &&
            contact.country != 'false');
  }

  bool _hasValidPhone() {
    return contact.phone != null &&
        contact.phone!.isNotEmpty &&
        contact.phone != 'false';
  }

  bool _hasValidEmail() {
    return contact.email != null &&
        contact.email!.isNotEmpty &&
        contact.email != 'false';
  }

  String _getFormattedAddress() {
    final addressParts =
        [
              if (contact.street != null &&
                  contact.street!.isNotEmpty &&
                  contact.street != 'false')
                contact.street,
              if (contact.street2 != null &&
                  contact.street2!.isNotEmpty &&
                  contact.street2 != 'false')
                contact.street2,
              if (contact.city != null &&
                  contact.city!.isNotEmpty &&
                  contact.city != 'false')
                contact.city,
              if (contact.state != null &&
                  contact.state!.isNotEmpty &&
                  contact.state != 'false')
                contact.state,
              if (contact.zip != null &&
                  contact.zip!.isNotEmpty &&
                  contact.zip != 'false')
                contact.zip,
              if (contact.country != null &&
                  contact.country!.isNotEmpty &&
                  contact.country != 'false')
                contact.country,
            ]
            .where((part) => part != null && part.isNotEmpty && part != 'false')
            .toList();

    return addressParts.join(', ');
  }

  Widget _buildActionMenu() {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      color: isDark ? Colors.grey[900] : Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'call',
          enabled: _hasValidPhone(),
          child: Row(
            children: [
              Icon(
                HugeIcons.strokeRoundedCall,
                color: _hasValidPhone()
                    ? (isDark ? Colors.grey[300] : Colors.grey[800])
                    : Colors.grey[500],
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                'Call Contact',
                style: TextStyle(
                  color: _hasValidPhone()
                      ? (isDark ? Colors.white : Colors.black87)
                      : Colors.grey[500],
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'message',
          enabled: _hasValidPhone(),
          child: Row(
            children: [
              Icon(
                HugeIcons.strokeRoundedMessage01,
                color: _hasValidPhone()
                    ? (isDark ? Colors.grey[300] : Colors.grey[800])
                    : Colors.grey[500],
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                'Send Message',
                style: TextStyle(
                  color: _hasValidPhone()
                      ? (isDark ? Colors.white : Colors.black87)
                      : Colors.grey[500],
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'email',
          enabled: _hasValidEmail(),
          child: Row(
            children: [
              Icon(
                HugeIcons.strokeRoundedMail01,
                color: _hasValidEmail()
                    ? (isDark ? Colors.grey[300] : Colors.grey[800])
                    : Colors.grey[500],
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                'Send Email',
                style: TextStyle(
                  color: _hasValidEmail()
                      ? (isDark ? Colors.white : Colors.black87)
                      : Colors.grey[500],
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'location',
          child: Row(
            children: [
              Icon(
                _hasValidCoordinates()
                    ? HugeIcons.strokeRoundedLocation01
                    : HugeIcons.strokeRoundedLocation04,

                color: (isDark ? Colors.white : Colors.black87),
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                'View Location',
                style: TextStyle(
                  color: (isDark ? Colors.white : Colors.black87),
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'call':
            if (_hasValidPhone() && onCall != null) {
              onCall!();
            }
            break;
          case 'message':
            if (_hasValidPhone() && onMessage != null) {
              onMessage!();
            }
            break;
          case 'email':
            if (_hasValidEmail() && onEmail != null) {
              onEmail!();
            }
            break;
          case 'location':
            if (onLocation != null) {
              onLocation!();
            }
            break;
        }
      },

      child: SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: Icon(
            Icons.more_vert,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            size: 20,
          ),
        ),
      ),
    );
  }

  bool _hasValidCoordinates() {
    return contact.latitude != null &&
        contact.longitude != null &&
        contact.latitude != 0.0 &&
        contact.longitude != 0.0;
  }
}
