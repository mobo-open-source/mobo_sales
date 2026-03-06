import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A circular avatar widget that can display a base64-encoded image or
/// fallback text initials. Handles both raster and SVG formats.
class CircularImageWidget extends StatelessWidget {
  final String? base64Image;
  final double radius;
  final String fallbackText;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback? onTap;
  final bool isLoading;

  const CircularImageWidget({
    super.key,
    this.base64Image,
    required this.radius,
    required this.fallbackText,
    this.backgroundColor = Colors.grey,
    this.textColor = Colors.white,
    this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = _buildContent();

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: content,
      );
    }
    return content;
  }

  Widget _buildContent() {
    if (base64Image != null &&
        base64Image is String &&
        base64Image!.isNotEmpty &&
        base64Image != 'false') {
      try {
        var raw = base64Image!.trim();

        final dataUrlSvgUtf8 = RegExp(
          r'^data:image\/svg\+xml;utf8,',
          caseSensitive: false,
        );
        if (dataUrlSvgUtf8.hasMatch(raw)) {
          final svgText = Uri.decodeFull(raw.replaceFirst(dataUrlSvgUtf8, ''));

          return _buildSvgAvatar(svgText);
        }

        if (raw.trimLeft().startsWith('<svg')) {
          return _buildSvgAvatar(raw);
        }

        final dataUrlBase64 = RegExp(r'^data:image\/[a-zA-Z0-9.+-]+;base64,');
        raw = raw.replaceFirst(dataUrlBase64, '');

        final cleanBase64 = raw.replaceAll(RegExp(r'\s+'), '');

        if (cleanBase64.isNotEmpty) {
          try {
            final Uint8List bytes = base64Decode(cleanBase64);
            if (_looksLikeImage(bytes)) {
              return CircleAvatar(
                radius: radius,
                backgroundImage: MemoryImage(bytes),
                backgroundColor: backgroundColor,
                onBackgroundImageError: (exception, stackTrace) {},
              );
            } else {
              try {
                final text = String.fromCharCodes(bytes);
                if (text.trimLeft().startsWith('<svg')) {
                  return _buildSvgAvatar(text);
                }
              } catch (_) {}
            }
          } catch (e) {}
        }
      } catch (e) {}
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: Center(
        child: isLoading
            ? SizedBox(
                width: radius * 0.8,
                height: radius * 0.8,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: textColor,
                ),
              )
            : Text(
                fallbackText.isEmpty
                    ? '?'
                    : fallbackText.substring(0, 1).toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor,
                  fontSize: radius * 0.8,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),
      ),
    );
  }

  Widget _buildSvgAvatar(String svgString) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: ClipOval(
        child: SvgPicture.string(
          svgString,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          placeholderBuilder: (context) => Container(
            color: backgroundColor,
            padding: EdgeInsets.all(radius * 0.5),
            child: CircularProgressIndicator(strokeWidth: 2, color: textColor),
          ),
        ),
      ),
    );
  }

  bool _looksLikeImage(List<int> bytes) {
    if (bytes.length < 4) return false;

    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }

    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;

    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return true;

    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return false;
  }
}
