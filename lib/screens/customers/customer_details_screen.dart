import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/currency_provider.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:latlong2/latlong.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:mobo_sales/screens/others/profile_screen.dart';
import 'package:mobo_sales/screens/quotations/create_quote_screen.dart';
import 'package:mobo_sales/screens/invoices/create_invoice_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'dart:convert';
import '../../models/contact.dart';
import '../../services/session_service.dart';
import '../../widgets/custom_snackbar.dart';
import '../../widgets/connection_status_widget.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:math' as math;
import '../../widgets/location_map_widget.dart';
import '../../utils/customer_location_helper.dart';
import '../../providers/contact_provider.dart';
import '../../providers/last_opened_provider.dart';
import 'select_location_screen.dart';
import 'edit_customer_screen.dart';
import 'package:mobo_sales/screens/quotations/quotation_list_screen.dart';
import 'package:mobo_sales/screens/invoices/invoice_list_screen.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:mobo_sales/widgets/circular_image_widget.dart';

class ContactActionException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  ContactActionException(this.message, {this.code, this.originalError});

  @override
  String toString() => 'ContactActionException: $message';
}

Future<void> shareContact(BuildContext context, Contact contact) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final primaryColor = Theme.of(context).primaryColor;
  BuildContext? dialogContext;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      dialogContext = ctx;
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(16),
                child: LoadingAnimationWidget.fourRotatingDots(
                  color: Theme.of(context).colorScheme.primary,
                  size: 50,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Creating contact card...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please wait while we prepare the contact for sharing.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  try {
    final imageBytes = await _generateContactImage(contact);

    final docDir = await getApplicationDocumentsDirectory();
    final file = File(
      '${docDir.path}/contact_${contact.name.replaceAll(' ', '_') ?? 'card'}_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(imageBytes);

    if (dialogContext != null && Navigator.of(dialogContext!).canPop()) {
      Navigator.of(dialogContext!).pop();
    }

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Contact: ${contact.name}',
      text: contact.name,
    );
  } on ContactActionException catch (e) {
    if (dialogContext != null && Navigator.of(dialogContext!).canPop()) {
      Navigator.of(dialogContext!).pop();
    }
    _showShareErrorDialog(context, e.message);
    rethrow;
  } catch (e) {
    if (dialogContext != null && Navigator.of(dialogContext!).canPop()) {
      Navigator.of(dialogContext!).pop();
    }
    final msg = e is ContactActionException
        ? e.message
        : 'Failed to share contact. Please try again.';
    _showShareErrorDialog(context, msg);
    if (kDebugMode) {}
    throw ContactActionException(
      'Failed to share contact',
      code: 'SHARE_FAILED',
      originalError: e,
    );
  }
}

void _showShareErrorDialog(BuildContext context, String message) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      title: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red[400], size: 24),
          const SizedBox(width: 8),
          Text(
            'Share Failed',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: TextStyle(color: isDark ? Colors.grey[300] : Colors.grey[700]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<Uint8List> _generateContactImage(Contact contact) async {
  const double scaleFactor = 12.0;
  const double cardWidth = 720;
  const double cardHeight = 540;
  final double canvasWidth = cardWidth * scaleFactor;
  final double canvasHeight = cardHeight * scaleFactor;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
  );

  const primaryColor = Color(0xFFBB2649);
  const brandColor = Color(0xFFBB2649);
  const backgroundColor = Color(0xFFFFFFFF);
  const headerColor = Color(0xFFF8FAFC);
  const textColor = Color(0xFF0F172A);
  const lightTextColor = Color(0xFF64748B);
  const avatarBgColor = Color(0xFFE2E8F0);
  const borderColor = Color(0xFFE2E8F0);
  const dividerColor = Color(0xFFCBD5E1);

  final cardRect = Rect.fromLTWH(0, 0, canvasWidth, canvasHeight);

  final shadowPaint1 = Paint()
    ..color = Colors.black.withOpacity(0.05)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
  final shadowPaint2 = Paint()
    ..color = Colors.black.withOpacity(0.03)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

  canvas.drawRect(cardRect.shift(Offset(0, 4 * scaleFactor)), shadowPaint1);
  canvas.drawRect(cardRect.shift(Offset(0, 2 * scaleFactor)), shadowPaint2);

  final backgroundPaint = Paint()..color = backgroundColor;
  canvas.drawRect(cardRect, backgroundPaint);

  final headerPaint = Paint()..color = headerColor;
  final headerRect = Rect.fromLTWH(0, 0, canvasWidth, 140 * scaleFactor);
  canvas.drawRect(headerRect, headerPaint);

  final double avatarRadius = 48 * scaleFactor;
  final double avatarCenterX = canvasWidth / 2;
  final double avatarCenterY = 70 * scaleFactor;
  bool drewAvatar = false;

  if (contact.imageUrl != null &&
      contact.imageUrl!.isNotEmpty &&
      contact.imageUrl != 'false') {
    try {
      final base64String = contact.imageUrl!.contains(',')
          ? contact.imageUrl!.split(',').last
          : contact.imageUrl!;
      if (base64String.isNotEmpty) {
        final bytes = base64Decode(base64String);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final img = frame.image;

        final outerRingPaint = Paint()
          ..color = brandColor.withOpacity(0.1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * scaleFactor;
        canvas.drawCircle(
          Offset(avatarCenterX, avatarCenterY),
          avatarRadius + 4 * scaleFactor,
          outerRingPaint,
        );

        final srcRect = Rect.fromLTWH(
          0,
          0,
          img.width.toDouble(),
          img.height.toDouble(),
        );
        final dstRect = Rect.fromCircle(
          center: Offset(avatarCenterX, avatarCenterY),
          radius: avatarRadius,
        );
        canvas.save();
        canvas.clipPath(ui.Path()..addOval(dstRect));
        canvas.drawImageRect(img, srcRect, dstRect, Paint());
        canvas.restore();
        drewAvatar = true;
      }
    } catch (_) {
      drewAvatar = false;
    }
  }

  if (contact.imageUrl != null &&
      contact.imageUrl!.isNotEmpty &&
      contact.imageUrl != 'false') {
    try {
      final base64String = contact.imageUrl!.contains(',')
          ? contact.imageUrl!.split(',').last
          : contact.imageUrl!;
      if (base64String.isNotEmpty) {
        final bytes = base64Decode(base64String);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final img = frame.image;

        final outerRingPaint = Paint()
          ..color = brandColor.withOpacity(0.1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * scaleFactor;
        canvas.drawCircle(
          Offset(avatarCenterX, avatarCenterY),
          avatarRadius + 4 * scaleFactor,
          outerRingPaint,
        );

        final srcRect = Rect.fromLTWH(
          0,
          0,
          img.width.toDouble(),
          img.height.toDouble(),
        );
        final dstRect = Rect.fromCircle(
          center: Offset(avatarCenterX, avatarCenterY),
          radius: avatarRadius,
        );
        canvas.save();
        canvas.clipPath(ui.Path()..addOval(dstRect));
        canvas.drawImageRect(img, srcRect, dstRect, Paint());
        canvas.restore();
        drewAvatar = true;
      }
    } catch (_) {
      drewAvatar = false;
    }
  }

  if (!drewAvatar) {
    final gradient = ui.Gradient.linear(
      Offset(avatarCenterX - avatarRadius, avatarCenterY - avatarRadius),
      Offset(avatarCenterX + avatarRadius, avatarCenterY + avatarRadius),
      [avatarBgColor, const Color(0xFFF1F5F9)],
    );
    final gradientPaint = Paint()..shader = gradient;
    canvas.drawCircle(
      Offset(avatarCenterX, avatarCenterY),
      avatarRadius,
      gradientPaint,
    );

    final innerBorderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * scaleFactor;
    canvas.drawCircle(
      Offset(avatarCenterX, avatarCenterY),
      avatarRadius,
      innerBorderPaint,
    );

    final initial = (contact.name.isNotEmpty)
        ? contact.name.trim()[0].toUpperCase()
        : '?';
    final textStyle = ui.TextStyle(
      color: primaryColor,
      fontSize: 36 * scaleFactor,
      fontWeight: FontWeight.w600,
      fontFamily: 'SF Pro Display',
    );
    final paragraph =
        ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
          ..pushStyle(textStyle)
          ..addText(initial)
          ..pop();
    final layout = paragraph.build()
      ..layout(ui.ParagraphConstraints(width: 96 * scaleFactor));
    canvas.drawParagraph(
      layout,
      Offset(
        avatarCenterX - 48 * scaleFactor,
        avatarCenterY - 24 * scaleFactor,
      ),
    );
  }

  final nameStyle = ui.TextStyle(
    color: textColor,
    fontSize: 24 * scaleFactor,
    fontWeight: FontWeight.w700,
    fontFamily: 'SF Pro Display',
    letterSpacing: -0.5 * scaleFactor,
  );
  final titleStyle = ui.TextStyle(
    color: lightTextColor,
    fontSize: 16 * scaleFactor,
    fontWeight: FontWeight.w500,
    fontFamily: 'SF Pro Text',
    letterSpacing: -0.2 * scaleFactor,
  );
  final labelStyle = ui.TextStyle(
    color: lightTextColor,
    fontSize: 11 * scaleFactor,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.0 * scaleFactor,
    fontFamily: 'SF Pro Text',
  );
  final valueStyle = ui.TextStyle(
    color: textColor,
    fontSize: 14 * scaleFactor,
    fontWeight: FontWeight.w500,
    fontFamily: 'SF Pro Text',
    letterSpacing: -0.1 * scaleFactor,
  );

  double currentY = 155 * scaleFactor;

  bool isReal(String? v) =>
      v != null && v.trim().isNotEmpty && v.trim().toLowerCase() != 'false';

  if (contact.name.isNotEmpty && contact.name != 'false') {
    final nameParagraph =
        ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
          ..pushStyle(nameStyle)
          ..addText(contact.name)
          ..pop();
    final nameLayout = nameParagraph.build()
      ..layout(ui.ParagraphConstraints(width: canvasWidth - 80 * scaleFactor));
    canvas.drawParagraph(nameLayout, Offset(40 * scaleFactor, currentY));
    currentY += 30 * scaleFactor;
  }

  final titleText = [
    contact.title,
    contact.function,
  ].where((v) => v != null && v.isNotEmpty && v != 'false').join(' • ');
  if (titleText.isNotEmpty) {
    final titleParagraph =
        ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
          ..pushStyle(titleStyle)
          ..addText(titleText)
          ..pop();
    final titleLayout = titleParagraph.build()
      ..layout(ui.ParagraphConstraints(width: canvasWidth - 80 * scaleFactor));
    canvas.drawParagraph(titleLayout, Offset(40 * scaleFactor, currentY));
    currentY += 26 * scaleFactor;
  }

  final dividerGradient = ui.Gradient.linear(
    Offset(80 * scaleFactor, currentY),
    Offset(canvasWidth - 80 * scaleFactor, currentY),
    [
      dividerColor.withOpacity(0.0),
      dividerColor,
      dividerColor.withOpacity(0.0),
    ],
    [0.0, 0.5, 1.0],
  );
  final dividerPaint = Paint()
    ..shader = dividerGradient
    ..strokeWidth = 2 * scaleFactor;
  canvas.drawLine(
    Offset(80 * scaleFactor, currentY),
    Offset(canvasWidth - 80 * scaleFactor, currentY),
    dividerPaint,
  );
  currentY += 24 * scaleFactor;

  void drawFieldAlways(String label, String? value, IconData icon) {
    final displayValue = isReal(value) ? value! : '—';
    if (currentY + 36 * scaleFactor > canvasHeight - 20 * scaleFactor) return;

    final iconBgPaint = Paint()..color = brandColor.withOpacity(0.08);
    canvas.drawCircle(
      Offset(60 * scaleFactor, currentY + 14 * scaleFactor),
      14 * scaleFactor,
      iconBgPaint,
    );

    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          fontSize: 16 * scaleFactor,
          color: brandColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    iconPainter.layout();
    iconPainter.paint(
      canvas,
      Offset(52 * scaleFactor, currentY + 6 * scaleFactor),
    );

    final labelParagraph = ui.ParagraphBuilder(ui.ParagraphStyle())
      ..pushStyle(labelStyle)
      ..addText(label.toUpperCase())
      ..pop();
    final labelLayout = labelParagraph.build()
      ..layout(ui.ParagraphConstraints(width: canvasWidth - 120 * scaleFactor));
    canvas.drawParagraph(labelLayout, Offset(85 * scaleFactor, currentY));

    final valueColor = isReal(value) ? textColor : lightTextColor;
    final adjustedValueStyle = ui.TextStyle(
      color: valueColor,
      fontSize: 14 * scaleFactor,
      fontWeight: FontWeight.w500,
      fontFamily: 'SF Pro Text',
      letterSpacing: -0.1 * scaleFactor,
      fontStyle: isReal(value) ? FontStyle.normal : FontStyle.italic,
    );

    final valueParagraph = ui.ParagraphBuilder(ui.ParagraphStyle())
      ..pushStyle(adjustedValueStyle)
      ..addText(displayValue)
      ..pop();
    final valueLayout = valueParagraph.build()
      ..layout(ui.ParagraphConstraints(width: canvasWidth - 120 * scaleFactor));
    canvas.drawParagraph(
      valueLayout,
      Offset(85 * scaleFactor, currentY + 16 * scaleFactor),
    );

    final valueHeight = valueLayout.height;
    currentY += math.max(36 * scaleFactor, valueHeight + 20 * scaleFactor);
  }

  drawFieldAlways('Company', contact.companyName, Icons.business_outlined);
  currentY += 8 * scaleFactor;
  drawFieldAlways('Email', contact.email, Icons.email_outlined);
  currentY += 8 * scaleFactor;
  drawFieldAlways('Phone', contact.phone, Icons.phone_outlined);
  currentY += 8 * scaleFactor;
  drawFieldAlways('Mobile', contact.mobile, Icons.phone_android_outlined);
  currentY += 8 * scaleFactor;
  drawFieldAlways('Website', contact.website, Icons.language_outlined);
  currentY += 8 * scaleFactor;

  final addressParts = [
    contact.street,
    contact.street2,
    contact.city,
    contact.state,
    contact.zip,
    contact.country,
  ].where((part) => isReal(part)).toList();
  final address = addressParts.isNotEmpty ? addressParts.join(', ') : null;
  drawFieldAlways('Address', address, Icons.location_on_outlined);
  currentY += 8 * scaleFactor;

  if (contact.industry != null &&
      contact.industry!.isNotEmpty &&
      contact.industry != 'false') {
    drawFieldAlways('Industry', contact.industry, Icons.work_outline);
  }

  final picture = recorder.endRecording();
  final img = await picture.toImage(canvasWidth.toInt(), canvasHeight.toInt());
  final finalBytes = await img.toByteData(format: ui.ImageByteFormat.png);
  if (finalBytes == null) throw Exception('Failed to encode image');
  return finalBytes.buffer.asUint8List();
}

Future<void> copyContactInfo(BuildContext context, Contact contact) async {
  bool isReal(String? v) =>
      v != null && v.trim().isNotEmpty && v.trim().toLowerCase() != 'false';
  try {
    final List<String> infoLines = [];

    infoLines.add(
      'Name: 	${isReal(contact.displayName) ? contact.displayName : 'N/A'}',
    );

    if (isReal(contact.title)) {
      infoLines.add('Title: ${contact.title}');
    }

    if (isReal(contact.function)) {
      infoLines.add('Position: ${contact.function}');
    }

    if (contact.isCompany != true && isReal(contact.companyName)) {
      infoLines.add('Company: ${contact.companyName}');
    }

    infoLines.add('Email: 	${isReal(contact.email) ? contact.email : 'N/A'}');

    infoLines.add('Phone: 	${isReal(contact.phone) ? contact.phone : 'N/A'}');

    infoLines.add(
      'Mobile: 	${isReal(contact.mobile) ? contact.mobile : 'N/A'}',
    );

    final addressParts = [
      contact.street,
      contact.street2,
      contact.city,
      contact.state,
      contact.zip,
      contact.country,
    ].where((part) => isReal(part)).toList();
    final address = addressParts.isNotEmpty ? addressParts.join(', ') : null;
    infoLines.add('Address: 	${isReal(address) ? address : 'N/A'}');

    infoLines.add(
      'Website: 	${isReal(contact.website) ? contact.website : 'N/A'}',
    );

    final contactInfo = infoLines.join('\n');

    if (infoLines.every((line) => line.endsWith('N/A'))) {
      throw ContactActionException(
        'No contact information available to copy',
        code: 'NO_CONTACT_INFO',
      );
    }

    await Clipboard.setData(ClipboardData(text: contactInfo));
  } on ContactActionException {
    rethrow;
  } catch (e) {
    if (kDebugMode) {}
    throw ContactActionException(
      'Failed to copy contact info',
      code: 'COPY_FAILED',
      originalError: e,
    );
  }
}

Future<void> makePhoneCall(Contact contact) async {
  try {
    final phoneNumber = contact.phone ?? contact.mobile;

    if (phoneNumber == null || phoneNumber.isEmpty) {
      throw ContactActionException(
        'No phone number available',
        code: 'NO_PHONE_NUMBER',
      );
    }

    final cleanedNumber = phoneNumber
        .replaceAll(RegExp(r'[^\d+\(\)\.\-\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleanedNumber.isEmpty) {
      throw ContactActionException(
        'Invalid phone number format',
        code: 'INVALID_PHONE_FORMAT',
      );
    }

    final isInternational = cleanedNumber.startsWith('+');

    if (!isInternational && !cleanedNumber.startsWith('00')) {}

    final phoneUrl = 'tel:$cleanedNumber';

    try {
      await launchUrl(Uri.parse(phoneUrl));
      return;
    } catch (e) {}

    if (await canLaunchUrl(Uri.parse(phoneUrl))) {
      await launchUrl(Uri.parse(phoneUrl));
    } else {
      throw ContactActionException(
        'Phone app is not available on this device',
        code: 'PHONE_APP_UNAVAILABLE',
      );
    }
  } on ContactActionException {
    rethrow;
  } catch (e) {
    throw ContactActionException(
      'Failed to make phone call',
      code: 'PHONE_CALL_FAILED',
      originalError: e,
    );
  }
}

Future<void> handleOpenWhatsApp(BuildContext context, Contact contact) async {
  try {
    await openWhatsApp(context, contact);
  } on ContactActionException catch (e) {
    switch (e.code) {
      case 'NO_PHONE_NUMBER':
        showSnackBar(context, 'No phone number available for WhatsApp');
        break;
      case 'INVALID_PHONE_FORMAT':
        showSnackBar(context, 'Invalid phone number format for WhatsApp');
        break;
      case 'WHATSAPP_UNAVAILABLE':
        showSnackBar(
          context,
          'WhatsApp is not installed on this device. '
          'Please install WhatsApp from the app store.',
        );
        break;
      case 'WHATSAPP_OPEN_FAILED':
        showSnackBar(context, 'Could not open WhatsApp');
        break;
      default:
        showSnackBar(context, 'Could not open WhatsApp');
    }
  } catch (e) {
    showSnackBar(
      context,
      'An unexpected error occurred while opening WhatsApp',
    );
  }
}

bool _hasValidPhoneNumber(String? phoneNumber) {
  if (phoneNumber == null ||
      phoneNumber.trim().isEmpty ||
      phoneNumber == 'false') {
    return false;
  }

  String cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '').trim();
  if (cleanedNumber.isEmpty) {
    cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
  }

  return cleanedNumber.isNotEmpty && cleanedNumber.length >= 7;
}

void _showNoPhoneNumberMessage(BuildContext context) {
  CustomSnackbar.showError(
    context,
    'No phone number available for this contact',
  );
}

Future<void> sendSMS(BuildContext context, String? phoneNumber) async {
  bool hasValidPhoneNumber(String? phoneNumber) {
    if (phoneNumber == null ||
        phoneNumber.trim().isEmpty ||
        phoneNumber == 'false') {
      return false;
    }
    String cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '').trim();
    if (cleanedNumber.isEmpty) {
      cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    }
    return cleanedNumber.isNotEmpty && cleanedNumber.length >= 7;
  }

  void showNoPhoneNumberMessage(BuildContext context) {
    CustomSnackbar.showError(
      context,
      'No phone number available for this contact',
    );
  }

  if (!hasValidPhoneNumber(phoneNumber)) {
    showNoPhoneNumberMessage(context);
    return;
  }

  if (phoneNumber == null || phoneNumber.trim().isEmpty) {
    CustomSnackbar.showError(
      context,
      'No phone number available for this contact',
    );
    return;
  }

  String cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '').trim();

  if (cleanedNumber.isEmpty) {
    cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
  }

  if (cleanedNumber.isEmpty) {
    CustomSnackbar.showError(context, 'Phone number contains no valid digits');
    return;
  }

  final isInternational = cleanedNumber.startsWith('+');

  if (!isInternational && !cleanedNumber.startsWith('00')) {}

  final minLength = isInternational ? 8 : 7;
  if (cleanedNumber.length < minLength) {
    CustomSnackbar.showError(
      context,
      'Phone number is too short (minimum $minLength digits)',
    );
    return;
  }

  if (cleanedNumber.length > 20) {
    CustomSnackbar.showError(
      context,
      'Phone number is too long. Please check the format.',
    );
    return;
  }

  try {
    final smsUri = Uri(scheme: 'sms', path: cleanedNumber);

    try {
      await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      return;
    } catch (e) {}

    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri, mode: LaunchMode.externalApplication);
    } else {
      CustomSnackbar.showError(context, 'No SMS app found to send message');
    }
  } catch (e) {
    CustomSnackbar.showError(context, 'Failed to send SMS: ${e.toString()}');
  }
}

Future<void> handleChatAction(BuildContext context, Contact contact) async {
  final phoneNumber = contact.phone ?? contact.mobile;

  if (!_hasValidPhoneNumber(phoneNumber)) {
    _showNoPhoneNumberMessage(context);
    return;
  }

  _showChatOptionsBottomSheet(context, contact);
}

void _showChatOptionsBottomSheet(BuildContext context, Contact contact) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final primaryColor = Theme.of(context).primaryColor;

  showModalBottomSheet(
    context: context,
    backgroundColor: isDark ? Colors.grey[900] : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (bottomSheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Send Message',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
        Divider(height: 1, color: isDark ? Colors.white24 : Colors.grey[300]),
        ListTile(
          leading: Icon(
            HugeIcons.strokeRoundedMessage01,
            color: isDark ? Colors.white : primaryColor,
          ),
          title: Text(
            'System Messenger',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          ),
          subtitle: Text(
            'Send SMS using default messaging app',
            style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600]),
          ),
          onTap: () {
            Navigator.pop(bottomSheetContext);
            final phoneNumber = contact.phone ?? contact.mobile;
            sendSMS(context, phoneNumber);
          },
        ),
        ListTile(
          leading: Icon(HugeIcons.strokeRoundedWhatsapp, color: Colors.green),
          title: Text(
            'WhatsApp',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          ),
          subtitle: Text(
            'Send message via WhatsApp',
            style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600]),
          ),
          onTap: () {
            Navigator.pop(bottomSheetContext);
            handleOpenWhatsApp(context, contact);
          },
        ),
        SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
      ],
    ),
  );
}

Future<void> openWhatsApp(BuildContext context, Contact contact) async {
  if (!_hasValidPhoneNumber(contact.phone)) {
    _showNoPhoneNumberMessage(context);
    return;
  }
  try {
    final phoneNumber = contact.phone ?? contact.mobile;

    if (phoneNumber == null || phoneNumber.isEmpty) {
      throw ContactActionException(
        'No phone number available',
        code: 'NO_PHONE_NUMBER',
      );
    }

    final cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '').trim();

    if (cleanedNumber.isEmpty) {
      throw ContactActionException(
        'Invalid phone number format',
        code: 'INVALID_PHONE_FORMAT',
      );
    }

    String whatsappNumber = cleanedNumber;

    if (whatsappNumber.startsWith('+')) {
      whatsappNumber = whatsappNumber.substring(1);
    }

    if (whatsappNumber.length == 10) {
      if (whatsappNumber.startsWith('9') ||
          whatsappNumber.startsWith('8') ||
          whatsappNumber.startsWith('7') ||
          whatsappNumber.startsWith('6')) {
        whatsappNumber = '91$whatsappNumber';
      } else if (whatsappNumber.startsWith('2') ||
          whatsappNumber.startsWith('3') ||
          whatsappNumber.startsWith('4') ||
          whatsappNumber.startsWith('5')) {
        whatsappNumber = '1$whatsappNumber';
      }
    }

    if (whatsappNumber.length < 7) {
      throw ContactActionException(
        'Phone number too short for WhatsApp',
        code: 'INVALID_PHONE_FORMAT',
      );
    }

    if (whatsappNumber.length > 15) {
      throw ContactActionException(
        'Phone number too long for WhatsApp',
        code: 'INVALID_PHONE_FORMAT',
      );
    }

    if (!RegExp(r'^\d+$').hasMatch(whatsappNumber)) {
      throw ContactActionException(
        'Phone number contains invalid characters',
        code: 'INVALID_PHONE_FORMAT',
      );
    }

    final whatsappUrl = Uri.encodeFull('https://wa.me/$whatsappNumber');

    try {
      await launchUrl(
        Uri.parse(whatsappUrl),
        mode: LaunchMode.externalApplication,
      );
      return;
    } catch (e) {}

    if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
      await launchUrl(
        Uri.parse(whatsappUrl),
        mode: LaunchMode.externalApplication,
      );
    } else {
      throw ContactActionException(
        'WhatsApp is not available on this device',
        code: 'WHATSAPP_UNAVAILABLE',
      );
    }
  } on ContactActionException {
    rethrow;
  } catch (e) {
    throw ContactActionException(
      'Failed to open WhatsApp',
      code: 'WHATSAPP_OPEN_FAILED',
      originalError: e,
    );
  }
}

Future<void> openWebsite(BuildContext context, Contact contact) async {
  final website = contact.website;
  if (website == null || website.isEmpty || website == 'false') {
    CustomSnackbar.showError(context, 'No website available for this contact');
    return;
  }
  String url = website.startsWith('http') ? website : 'http://$website';
  try {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await Clipboard.setData(ClipboardData(text: url));
      CustomSnackbar.showWarning(
        context,
        'Could not open website. URL copied to clipboard.',
      );
    }
  } catch (e) {
    await Clipboard.setData(ClipboardData(text: url));
    CustomSnackbar.showWarning(
      context,
      'Could not open website. URL copied to clipboard.',
    );
  }
}

Future<void> openLocation(BuildContext context, Contact contact) async {
  try {
    if (contact.latitude == null || contact.longitude == null) {
      CustomSnackbar.showError(
        context,
        'No location available for this contact',
      );
      return;
    }
    final lat = contact.latitude!;
    final lng = contact.longitude!;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      CustomSnackbar.showError(context, 'Invalid location coordinates');
      return;
    }
    final url = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      final webUrl = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      );
      if (await canLaunchUrl(webUrl)) {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      } else {
        await Clipboard.setData(ClipboardData(text: '$lat,$lng'));
        CustomSnackbar.showWarning(
          context,
          'Could not open maps. Coordinates copied to clipboard.',
        );
      }
    }
  } catch (e) {
    await Clipboard.setData(
      ClipboardData(text: '${contact.latitude},${contact.longitude}'),
    );
    CustomSnackbar.showWarning(
      context,
      'Could not open maps. Coordinates copied to clipboard.',
    );
  }
}

void showSnackBar(BuildContext context, String message) {
  CustomSnackbar.showError(context, message);
}

Future<void> handleMakePhoneCall(BuildContext context, Contact contact) async {
  try {
    await makePhoneCall(contact);
  } on ContactActionException catch (e) {
    switch (e.code) {
      case 'NO_PHONE_NUMBER':
        showSnackBar(context, 'No phone number available for this contact');
        break;
      case 'INVALID_PHONE_FORMAT':
        showSnackBar(context, 'Invalid phone number format');
        break;
      case 'PHONE_APP_UNAVAILABLE':
        showSnackBar(
          context,
          'Could not find a phone app. '
          'Please install a dialer app or check your device settings.',
        );
        break;
      default:
        showSnackBar(context, 'Could not make phone call');
    }
  } catch (e) {
    showSnackBar(context, 'An unexpected error occurred while making the call');
  }
}

Future<void> handleSendEmail(BuildContext context, Contact contact) async {
  final email = contact.email;
  if (email == null || email.isEmpty || email == 'false') {
    if (context.mounted) {
      CustomSnackbar.showError(
        context,
        'No email address available for this contact',
      );
    }
    return;
  }

  final List<Uri> emailUris = [
    Uri(scheme: 'mailto', path: email),
    Uri.parse('mailto:$email'),
  ];

  bool launched = false;

  for (final uri in emailUris) {
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);

        launched = true;
        break;
      }
    } catch (e) {
      continue;
    }
  }

  if (!launched) {
    try {
      await Clipboard.setData(ClipboardData(text: email));
      if (context.mounted) {
        CustomSnackbar.showWarning(
          context,
          'Could not open email app. Email copied to clipboard.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        CustomSnackbar.showError(
          context,
          'Could not open email app or copy to clipboard.',
        );
      }
    }
  }
}

Future<void> handleOpenLocation(BuildContext context, Contact contact) async {
  final lat = contact.latitude;
  final lng = contact.longitude;
  if (lat == null || lng == null || (lat == 0.0 && lng == 0.0)) {
    CustomSnackbar.showError(
      context,
      'No location available for this contact (not geolocalized)',
    );
    return;
  }
  final googleMapsUrl =
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
  try {
    final uri = Uri.parse(googleMapsUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      final webUrl = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      );
      if (await canLaunchUrl(webUrl)) {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      } else {
        await Clipboard.setData(ClipboardData(text: '$lat,$lng'));
        CustomSnackbar.showWarning(
          context,
          'Could not open maps. Coordinates copied to clipboard.',
        );
      }
    }
  } catch (e) {
    await Clipboard.setData(
      ClipboardData(text: '${contact.latitude},${contact.longitude}'),
    );
    CustomSnackbar.showWarning(
      context,
      'Could not open maps. Coordinates copied to clipboard.',
    );
  }
}

class CustomerDetailsScreen extends StatefulWidget {
  final Contact contact;

  const CustomerDetailsScreen({super.key, required this.contact});

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen>
    with TickerProviderStateMixin {
  late Contact _contact;
  bool _isLoading = true;
  bool _isLoadingActivities = true;
  List<Map<String, dynamic>> _activities = [];
  Map<String, dynamic>? _customerStats;
  Uint8List? _customerImage;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _wasEdited = false;

  String _getDisplayName() {
    if ((_contact.isCompany ?? false) &&
        _contact.companyName != null &&
        _contact.companyName!.isNotEmpty &&
        _contact.companyName != 'false') {
      return _contact.companyName!;
    }
    if (_contact.name.isNotEmpty && _contact.name != 'false') {
      return _contact.name;
    }
    return 'Unnamed Contact';
  }

  bool _isRealValue(String? value) {
    return value != null && value.isNotEmpty && value != 'false';
  }

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _trackCustomerAccess();
    _loadCustomerData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _trackCustomerAccess() {
    try {
      final lastOpenedProvider = Provider.of<LastOpenedProvider>(
        context,
        listen: false,
      );
      final customerId = _contact.id.toString();
      final customerName = _contact.displayName;
      final customerType = _contact.isCompany == true ? 'Company' : 'Contact';

      lastOpenedProvider.trackCustomerAccess(
        customerId: customerId,
        customerName: customerName,
        customerType: customerType,
        customerData: _contact.toJson(),
      );
    } catch (e) {}
  }

  Future<void> _loadCustomerData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _isLoadingActivities = true;
    });

    try {
      await _fetchCompleteCustomerData();

      if (_contact.imageUrl != null && _contact.imageUrl!.isNotEmpty) {
        await _loadCustomerImage();
      }

      await Future.wait([_loadCustomerActivities(), _loadCustomerStats()]);

      _animationController.forward();
    } catch (e) {
      if (!mounted) return;

      CustomSnackbar.showError(
        context,
        'Error loading customer data: ${e.toString()}',
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingActivities = false;
      });
    }
  }

  Future<void> _fetchCompleteCustomerData() async {
    try {
      final sessionService = Provider.of<SessionService>(
        context,
        listen: false,
      );
      final client = await sessionService.client;
      if (client == null) {
        return;
      }

      final result = await client.callKw({
        'model': 'res.partner',
        'method': 'read',
        'args': [
          [_contact.id],
        ],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'email',
            'phone',
            'mobile',
            'website',
            'function',
            'street',
            'street2',
            'city',
            'state_id',
            'zip',
            'country_id',
            'image_1920',
            'partner_latitude',
            'partner_longitude',
            'create_date',
            'write_date',
            'is_company',
            'company_name',
            'vat',
            'company_type',
            'industry_id',
            'customer_rank',
            'user_id',
            'property_payment_term_id',
            'credit_limit',
            'property_product_pricelist',
            'title',
            'lang',
            'tz',
            'comment',
            'active',
            'type',
            'category_id',
          ],
        },
      });

      if (result is List && result.isNotEmpty) {
        final contactData = result[0] as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _contact = Contact.fromJson(contactData);
        });
      }
    } catch (e) {}
  }

  Future<void> _loadCustomerImage() async {
    try {
      final imageUrl = _contact.imageUrl;
      if (imageUrl == null || imageUrl.isEmpty) {
        return;
      }

      if (imageUrl.startsWith('http')) {
        return;
      } else {
        try {
          final base64String = imageUrl.contains(',')
              ? imageUrl.split(',').last
              : imageUrl;

          if (base64String.isEmpty) {
            return;
          }

          final bytes = base64Decode(base64String);
          if (!mounted) return;
          setState(() {
            _customerImage = bytes;
          });
        } catch (e) {}
      }
    } catch (e) {}
  }

  Future<void> _loadCustomerActivities() async {
    try {
      final sessionService = Provider.of<SessionService>(
        context,
        listen: false,
      );
      final client = await sessionService.client;
      if (client == null) {
        return;
      }

      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [
          [
            ['partner_id', '=', _contact.id],
          ],
        ],
        'kwargs': {
          'fields': [
            'name',
            'date_order',
            'amount_total',
            'state',
            'payment_term_id',
            'currency_id',
          ],
          'limit': 5,
          'order': 'date_order desc',
        },
      });

      if (result is List) {
        final activities = <Map<String, dynamic>>[];
        for (final order in result) {
          if (order is Map<String, dynamic>) {
            activities.add({
              'type': 'Order Created',
              'date': order['date_order']?.toString() ?? '',
              'amount': order['amount_total']?.toString() ?? '0.0',
              'reference': order['name']?.toString() ?? '',
              'status': order['state']?.toString() ?? '',
              'currency':
                  order['currency_id'] is List &&
                      order['currency_id'].length > 1
                  ? order['currency_id'][1]?.toString() ??
                        Provider.of<CurrencyProvider>(
                          context,
                          listen: false,
                        ).currency
                  : Provider.of<CurrencyProvider>(
                      context,
                      listen: false,
                    ).currency,
              'payment_terms':
                  order['payment_term_id'] is List &&
                      order['payment_term_id'].length > 1
                  ? order['payment_term_id'][1]?.toString() ?? ''
                  : '',
            });
          }
        }
        if (!mounted) return;
        setState(() {
          _activities = activities;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _activities = [];
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _activities = [];
      });
    }
  }

  Future<void> _loadCustomerStats() async {
    try {
      final sessionService = Provider.of<SessionService>(
        context,
        listen: false,
      );
      final client = await sessionService.client;
      if (client == null) {
        return;
      }

      final ordersResult = await client.callKw({
        'model': 'sale.order',
        'method': 'search_count',
        'args': [
          [
            ['partner_id', '=', _contact.id],
          ],
        ],
        'kwargs': {},
      });

      final totalAmountResult = await client.callKw({
        'model': 'sale.order',
        'method': 'search_read',
        'args': [
          [
            ['partner_id', '=', _contact.id],
            [
              'state',
              'in',
              ['sale', 'done'],
            ],
          ],
        ],
        'kwargs': {
          'fields': ['amount_total'],
        },
      });

      double totalAmount = 0.0;
      if (totalAmountResult is List) {
        for (final order in totalAmountResult) {
          if (order is Map<String, dynamic>) {
            final amount = order['amount_total'];
            if (amount is num) {
              totalAmount += amount.toDouble();
            }
          }
        }
      }

      final confirmedOrdersResult = await client.callKw({
        'model': 'sale.order',
        'method': 'search_count',
        'args': [
          [
            ['partner_id', '=', _contact.id],
            [
              'state',
              'in',
              ['sale', 'done'],
            ],
          ],
        ],
        'kwargs': {},
      });

      final draftOrdersResult = await client.callKw({
        'model': 'sale.order',
        'method': 'search_count',
        'args': [
          [
            ['partner_id', '=', _contact.id],
            ['state', '=', 'draft'],
          ],
        ],
        'kwargs': {},
      });

      if (!mounted) return;
      setState(() {
        _customerStats = {
          'total_orders': ordersResult is int ? ordersResult : 0,
          'confirmed_orders': confirmedOrdersResult is int
              ? confirmedOrdersResult
              : 0,
          'draft_orders': draftOrdersResult is int ? draftOrdersResult : 0,
          'total_amount': totalAmount,
          'last_order_date':
              _activities.isNotEmpty && _activities.first['date'] != null
              ? _activities.first['date'].toString()
              : null,
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _customerStats = {
          'total_orders': 0,
          'confirmed_orders': 0,
          'draft_orders': 0,
          'total_amount': 0.0,
          'last_order_date':
              _activities.isNotEmpty && _activities.first['date'] != null
              ? _activities.first['date'].toString()
              : null,
        };
      });
    }
  }

  Future<void> _showChangeCoordinatesDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Change Location',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  'Are you sure you want to change ${_contact.name}\'s location?',
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
                'Continue',
                style: TextStyle(
                  color: isDark ? Colors.white : primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                await _openSelectLocationScreen();
              },
            ),
          ],
        );
      },
    );
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

  Future<bool?> _showArchiveCustomerDialog(
    BuildContext context,
    Contact customer,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: Text(
          'Archive Customer',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Are you sure you want to archive ${customer.name}? This will deactivate the customer but preserve their data.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isDark
                ? Colors.grey[300]
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark
                        ? Colors.grey[400]
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.orange[700]
                        : Colors.orange[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    elevation: isDark ? 0 : 3,
                  ),
                  child: const Text(
                    'Archive',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _archiveCustomer(BuildContext context, Contact customer) async {
    if (customer.id == 0) {
      CustomSnackbar.showError(
        context,
        'Invalid customer ID. Cannot archive customer.',
      );
      return;
    }

    final sessionService = Provider.of<SessionService>(context, listen: false);
    final client = await sessionService.client;
    if (client == null) {
      CustomSnackbar.showError(
        context,
        'No active session. Please log in again.',
      );
      return;
    }

    final confirmArchive = await _showArchiveCustomerDialog(context, customer);

    if (confirmArchive != true) {
      return;
    }

    bool isLoadingDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primaryColor = Theme.of(context).primaryColor;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: isDark ? primaryColor : null),
                const SizedBox(width: 16),
                Text(
                  'Archiving customer...',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      isLoadingDialogOpen = false;
    });

    try {
      final result = await client.callKw({
        'model': 'res.partner',
        'method': 'write',
        'args': [
          [customer.id],
          {'active': false},
        ],
        'kwargs': {},
      });

      if (result == true) {
        final contactProvider = Provider.of<ContactProvider>(
          context,
          listen: false,
        );
        contactProvider.contacts.removeWhere((c) => c.id == customer.id);
        contactProvider.notifyListeners();

        if (isLoadingDialogOpen && context.mounted) {
          Navigator.of(context).pop();
          isLoadingDialogOpen = false;
        }

        if (context.mounted) {
          CustomSnackbar.showSuccess(context, 'Customer archived successfully');
          Navigator.of(context).pop(true);
        }
      } else {
        throw Exception('Failed to archive customer');
      }
    } catch (e) {
      if (isLoadingDialogOpen && context.mounted) {
        Navigator.of(context).pop();
        isLoadingDialogOpen = false;
      }

      if (context.mounted) {
        if (e.toString().contains(
          'Record does not exist or has been deleted',
        )) {
          CustomSnackbar.showWarning(
            context,
            'This customer has already been deleted or archived.',
          );
          Navigator.of(context).pop(true);
        } else {
          CustomSnackbar.showError(context, 'Failed to archive customer: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;
    return WillPopScope(
      onWillPop: () async {
        if (_wasEdited) {
          Navigator.pop(context, _contact);
        } else {
          Navigator.pop(context);
        }
        return false;
      },
      child: Scaffold(
        floatingActionButton: _buildSpeedDial(),
        appBar: AppBar(
          title: Text(
            'Customer Details',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              HugeIcons.strokeRoundedArrowLeft01,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          backgroundColor: isDark ? Colors.grey[900]! : Colors.grey[50]!,
          actions: [
            IconButton(
              icon: Icon(
                HugeIcons.strokeRoundedPencilEdit02,

                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[400]
                    : Colors.grey[600],
              ),
              onPressed: _isLoading
                  ? null
                  : () async {
                      final updatedContact = await Navigator.push(
                        context,

                        MaterialPageRoute(
                          builder: (context) =>
                              EditCustomerScreen(contact: _contact),
                        ),
                      );
                      if (updatedContact != null && updatedContact is Contact) {
                        setState(() {
                          _contact = updatedContact;
                          _wasEdited = true;
                        });
                        await _loadCustomerData();
                      }
                    },
            ),
            PopupMenuButton<String>(
              enabled: !_isLoading,
              icon: Icon(
                Icons.more_vert,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[400]
                    : Colors.grey[600],
                size: 20,
              ),
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[900]
                  : Colors.white,
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onSelected: (String value) {
                switch (value) {
                  case 'share':
                    shareContact(context, _contact);
                    break;
                  case 'copy':
                    copyContactInfo(context, _contact);
                    break;
                  case 'location':
                    if (_contact.latitude != null &&
                        _contact.longitude != null &&
                        _contact.latitude != 0.0 &&
                        _contact.longitude != 0.0) {
                      _showChangeCoordinatesDialog();
                    } else {
                      _handleLocationAction();
                    }
                    break;
                  case 'archive':
                    _archiveCustomer(context, _contact);
                    break;
                  case 'delete':
                    _deleteCustomer(context, _contact);
                    break;
                }
              },
              itemBuilder: (BuildContext context) {
                final isDark = Theme.of(context).brightness == Brightness.dark;

                return [
                  PopupMenuItem<String>(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(
                          HugeIcons.strokeRoundedShare01,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Share Customer Details',
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
                    value: 'copy',
                    child: Row(
                      children: [
                        Icon(
                          HugeIcons.strokeRoundedCopy02,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Copy Customer Info',
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
                    value: 'location',
                    child: Row(
                      children: [
                        Icon(
                          HugeIcons.strokeRoundedCoordinate01,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _contact.latitude != null &&
                                  _contact.longitude != null &&
                                  _contact.latitude != 0.0 &&
                                  _contact.longitude != 0.0
                              ? 'Change Customer Location'
                              : 'Set Customer Location',
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
                    value: 'archive',
                    child: Row(
                      children: [
                        Icon(
                          HugeIcons.strokeRoundedArchive03,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Archive Customer',
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
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          HugeIcons.strokeRoundedDelete02,
                          color: Colors.red[400],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Delete Customer',
                          style: TextStyle(
                            color: Colors.red[400],
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        body: Stack(
          children: [
            ConnectionStatusWidget(),
            if (!_isLoading)
              FadeTransition(
                opacity: _fadeAnimation,
                child: RefreshIndicator(
                  onRefresh: _loadCustomerData,
                  color: primaryColor,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildCustomerHeader(),
                        const SizedBox(height: 24),
                        _buildCustomerStats(),
                        const SizedBox(height: 24),
                        _buildContactInfo(),
                        const SizedBox(height: 24),
                        _buildCompanyInfo(),
                        const SizedBox(height: 24),
                        _buildBusinessInfo(),
                        const SizedBox(height: 24),
                        _buildAdditionalInfo(),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            if (_isLoading) _buildLoadingState(context),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF23272E) : Colors.white;
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCustomerHeaderShimmer(cardBg, baseColor),
            const SizedBox(height: 24),

            _buildSalesOverviewShimmer(cardBg, baseColor),
            const SizedBox(height: 24),

            _buildContactInfoShimmer(cardBg, baseColor),
            const SizedBox(height: 24),

            _buildRecentTransactionsShimmer(cardBg, baseColor),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerHeaderShimmer(Color cardBg, Color baseColor) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18.0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: baseColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 24,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),

                    Container(
                      width: 120,
                      height: 15,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Container(width: double.infinity, height: 1, color: baseColor),
          const SizedBox(height: 16),

          Row(
            children: List.generate(
              4,
              (index) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index < 3 ? 8 : 0),
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: baseColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: 50,
                        height: 12,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(4),
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
    );
  }

  Widget _buildSalesOverviewShimmer(Color cardBg, Color baseColor) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 140,
                height: 18,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: List.generate(
              2,
              (index) => Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: index == 0 ? 12 : 0),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: cardBg,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: 60,
                        height: 20,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 80,
                        height: 12,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(4),
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
    );
  }

  Widget _buildContactInfoShimmer(Color cardBg, Color baseColor) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 160,
                height: 18,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...List.generate(
            5,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 80,
                          height: 12,
                          decoration: BoxDecoration(
                            color: baseColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          height: 15,
                          decoration: BoxDecoration(
                            color: baseColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
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

  Widget _buildRecentTransactionsShimmer(Color cardBg, Color baseColor) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 180,
                height: 18,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...List.generate(
            3,
            (index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: baseColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 150,
                          height: 14,
                          decoration: BoxDecoration(
                            color: baseColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 100,
                          height: 13,
                          decoration: BoxDecoration(
                            color: baseColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 80,
                          height: 12,
                          decoration: BoxDecoration(
                            color: baseColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        width: 80,
                        height: 14,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 60,
                        height: 20,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    final addressParts = [
      if (_contact.street != null &&
          _contact.street!.trim().isNotEmpty &&
          _contact.street != 'false')
        _contact.street,
      if (_contact.street2 != null &&
          _contact.street2!.trim().isNotEmpty &&
          _contact.street2 != 'false')
        _contact.street2,
      if (_contact.city != null &&
          _contact.city!.trim().isNotEmpty &&
          _contact.city != 'false')
        _contact.city,
      if (_contact.state != null &&
          _contact.state!.trim().isNotEmpty &&
          _contact.state != 'false')
        _contact.state,
      if (_contact.zip != null &&
          _contact.zip!.trim().isNotEmpty &&
          _contact.zip != 'false')
        _contact.zip,
      if (_contact.country != null &&
          _contact.country!.trim().isNotEmpty &&
          _contact.country != 'false')
        _contact.country,
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF23272E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  children: [
                    InkWell(
                      onTap: () {
                        if (_customerImage != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  FullImageScreen(imageBytes: _customerImage!),
                            ),
                          );
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: _getDisplayName().length > 20
                              ? 28
                              : (_getDisplayName().length > 15 ? 30 : 32),
                          backgroundColor: Colors.grey.shade100,
                          backgroundImage: _customerImage != null
                              ? MemoryImage(_customerImage!)
                              : null,
                          child: _customerImage == null
                              ? Text(
                                  _contact.displayName.isNotEmpty
                                      ? _contact.displayName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: _getDisplayName().length > 20
                                        ? 20
                                        : (_getDisplayName().length > 15
                                              ? 22
                                              : 24),
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.black54
                                        : Colors.white,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                    if (_contact.isActive != null)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Tooltip(
                          message: _contact.isActive!
                              ? 'Active Customer'
                              : 'Inactive Customer',
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _contact.isActive!
                                  ? Colors.green
                                  : Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _contact.isActive! ? Icons.check : Icons.close,
                              color: _contact.isActive!
                                  ? Colors.green
                                  : Colors.red,
                              size: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getDisplayName(),
                        style: TextStyle(
                          fontSize: _getDisplayName().length > 20
                              ? 20
                              : (_getDisplayName().length > 15 ? 22 : 24),
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 0),
                      Text(
                        (_contact.isCompany ?? false) ? 'Company' : 'Customer',
                        style: TextStyle(
                          fontSize: 15,
                          color: isDark ? Colors.white60 : primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            ...[
              const SizedBox(height: 24),
              Divider(
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.grey.shade200,
                thickness: 1,
                height: 1,
              ),
              _buildQuickActionButtons(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButtons() {
    bool isReal(String? v) =>
        v != null && v.trim().isNotEmpty && v.trim().toLowerCase() != 'false';
    bool missingCoordinates =
        _contact.latitude == null ||
        _contact.longitude == null ||
        _contact.latitude == 0.0 ||
        _contact.longitude == 0.0;

    final List<Map<String, dynamic>> actions = [
      {
        'icon': HugeIcons.strokeRoundedCalling02,
        'label': 'Call',
        'color': const Color(0xFF059669),
        'isEnabled': isReal(_contact.phone) || isReal(_contact.mobile),
        'onTap': () => isReal(_contact.phone) || isReal(_contact.mobile)
            ? handleMakePhoneCall(context, _contact)
            : _showDisabledActionFeedback('No phone number available'),
      },
      {
        'icon': HugeIcons.strokeRoundedMessage01,
        'label': 'Message',
        'color': const Color(0xFF2563EB),
        'isEnabled': isReal(_contact.phone) || isReal(_contact.mobile),
        'onTap': () => isReal(_contact.phone) || isReal(_contact.mobile)
            ? handleChatAction(context, _contact)
            : _showDisabledActionFeedback(
                'No phone number available for messaging',
              ),
      },
      {
        'icon': HugeIcons.strokeRoundedMailOpen,
        'label': 'Email',
        'color': const Color(0xFFD97706),
        'isEnabled': _isRealValue(_contact.email),
        'onTap': () => _isRealValue(_contact.email)
            ? handleSendEmail(context, _contact)
            : _showDisabledActionFeedback('No email address available'),
      },

      {
        'icon': HugeIcons.strokeRoundedLocation05,
        'label': 'Location',
        'color': const Color(0xFFDC2626),
        'isEnabled': true,
        'onTap': () => _handleLocationAction(),
        'showWarning': missingCoordinates,
      },
    ];

    return Row(
      children: actions.asMap().entries.map((entry) {
        final index = entry.key;
        final action = entry.value;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index < actions.length - 1 ? 8 : 0),
            child: _buildStandardActionButton(
              icon: action['icon'],
              label: action['label'],
              color: action['color'],
              onTap: action['onTap'],
              isEnabled: action['isEnabled'] ?? true,
              showWarning: action['showWarning'] ?? false,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStandardActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool isEnabled = true,
    bool showWarning = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final effectiveColor = isEnabled
        ? color
        : (isDark ? Colors.grey[600]! : Colors.grey[400]!);
    final containerColor = isEnabled
        ? (isDark ? color.withOpacity(0.15) : Colors.white)
        : (isDark ? Colors.grey[800]!.withOpacity(0.3) : Colors.grey[100]!);
    final labelColor = isEnabled
        ? (isDark ? const Color(0xFFD1D5DB) : const Color(0xFF6B7280))
        : (isDark ? Colors.grey[600]! : Colors.grey[500]!);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: containerColor,
                      shape: BoxShape.circle,
                      boxShadow: isEnabled
                          ? [
                              BoxShadow(
                                color: isDark
                                    ? Colors.black.withOpacity(0.3)
                                    : Colors.black.withOpacity(0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                                spreadRadius: 0,
                              ),
                              if (!isDark)
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.8),
                                  blurRadius: 1,
                                  offset: const Offset(0, -1),
                                  spreadRadius: 0,
                                ),
                            ]
                          : [
                              BoxShadow(
                                color: isDark
                                    ? Colors.black.withOpacity(0.1)
                                    : Colors.black.withOpacity(0.02),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                                spreadRadius: 0,
                              ),
                            ],
                    ),
                    child: Icon(icon, size: 22, color: effectiveColor),
                  ),
                  if (showWarning)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF1F2937)
                                : Colors.white,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF59E0B).withOpacity(0.4),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                              spreadRadius: 0,
                            ),
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.warning_rounded,
                          color: Colors.white,
                          size: 10,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: labelColor,
                  fontSize: 12,
                  letterSpacing: -0.1,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDisabledActionFeedback(String message) {
    if (context.mounted) {
      CustomSnackbar.showInfo(context, message);
    }
  }

  Widget _buildProfessionalActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool showWarning = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? color.withOpacity(0.08) : color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.2), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(isDark ? 0.15 : 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 24, color: color),
                  ),
                  if (showWarning)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF23272E)
                                : Colors.white,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.warning_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF374151),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionButton(
    IconData icon,
    Color iconColor,
    String label,
    Color color,
    VoidCallback onTap, {
    Widget? indicator,
  }) {
    final labelColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF1A1A1A);
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(
                vertical: 20.0,
                horizontal: 8,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1A1A1A)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white12
                      : Colors.grey.shade200,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black26
                        : Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white.withOpacity(0.08)
                              : color.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 24, color: iconColor),
                      ),
                      if (indicator != null)
                        Positioned(top: -2, right: -2, child: indicator),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: labelColor,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerStats() {
    if (_customerStats == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    final totalOrders = _customerStats!['total_orders'] ?? 0;
    final confirmedOrders = _customerStats!['confirmed_orders'] ?? 0;
    final draftOrders = _customerStats!['draft_orders'] ?? 0;
    final totalAmount = _customerStats!['total_amount'] ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF23272E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Customer Statistics',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                HugeIcon(
                  icon: HugeIcons.strokeRoundedActivity01,
                  color: primaryColor,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildStatListItem(
              'Total Orders',
              totalOrders.toString(),
              HugeIcons.strokeRoundedShoppingBag02,
              primaryColor,
            ),
            const SizedBox(height: 12),
            _buildStatListItem(
              'Confirmed Orders',
              confirmedOrders.toString(),
              HugeIcons.strokeRoundedTickDouble03,
              Colors.green,
            ),
            const SizedBox(height: 12),
            _buildStatListItem(
              'Draft Orders',
              draftOrders.toString(),
              HugeIcons.strokeRoundedDocumentValidation,
              Colors.orange,
            ),
            const SizedBox(height: 12),
            _buildStatListItem(
              'Total Amount',
              '${totalAmount.toStringAsFixed(2)}',
              HugeIcons.strokeRoundedMoneyBag02,
              Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatListItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statValueColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final statLabelColor = isDark ? Colors.white60 : Colors.black54;

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
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: statValueColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: statLabelColor,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactInfo() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF23272E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ExpansionTile(
          initiallyExpanded: false,
          backgroundColor: isDark ? const Color(0xFF23272E) : Colors.white,
          collapsedBackgroundColor: isDark
              ? const Color(0xFF23272E)
              : Colors.white,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          childrenPadding: const EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: 20,
          ),

          title: Text(
            'Contact Information',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_contact.phone != null) ...[
                  _buildInfoRow(
                    'Phone',
                    _contact.phone,
                    HugeIcons.strokeRoundedCall02,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.mobile != null) ...[
                  _buildInfoRow(
                    'Mobile',
                    _contact.mobile,
                    HugeIcons.strokeRoundedSmartPhone01,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.email != null) ...[
                  _buildInfoRow(
                    'Email',
                    _contact.email,
                    HugeIcons.strokeRoundedMail01,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.website != null) ...[
                  _buildInfoRow(
                    'Website',
                    _contact.website,
                    HugeIcons.strokeRoundedWebDesign02,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.street != null) ...[
                  _buildInfoRow(
                    'Street',
                    _contact.street,
                    HugeIcons.strokeRoundedLocation05,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.street2 != null) ...[
                  _buildInfoRow(
                    'Street 2',
                    _contact.street2,
                    HugeIcons.strokeRoundedLocation04,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.city != null) ...[
                  _buildInfoRow(
                    'City',
                    _contact.city,
                    HugeIcons.strokeRoundedCity03,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.state != null) ...[
                  _buildInfoRow(
                    'State',
                    _contact.state,
                    HugeIcons.strokeRoundedRealEstate01,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.zip != null) ...[
                  _buildInfoRow(
                    'ZIP Code',
                    _contact.zip,
                    HugeIcons.strokeRoundedPinCode,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.country != null) ...[
                  _buildInfoRow(
                    'Country',
                    _contact.country,
                    HugeIcons.strokeRoundedEarth,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.latitude != null &&
                    _contact.longitude != null &&
                    _contact.latitude != 0.0 &&
                    _contact.longitude != 0.0) ...[
                  LocationMapWidget(
                    latitude: _contact.latitude!,
                    longitude: _contact.longitude!,
                    contact: _contact,
                    onOpenMap: () => handleCustomerLocation(
                      context: context,
                      parentContext: context,
                      contact: _contact,
                      onContactUpdated: (updatedContact) {
                        final provider = Provider.of<ContactProvider>(
                          context,
                          listen: false,
                        );
                        provider.updateContactCoordinates(updatedContact);
                        setState(() {
                          _contact = updatedContact;
                        });
                      },
                      suppressMapRedirect: false,
                    ),
                    onCoordinatesRemoved: () async {
                      setState(() {
                        _contact = _contact.copyWith(
                          latitude: 0.0,
                          longitude: 0.0,
                        );
                      });

                      final provider = Provider.of<ContactProvider>(
                        context,
                        listen: false,
                      );
                      provider.updateContactCoordinates(_contact);

                      if (mounted) {
                        CustomSnackbar.showSuccess(
                          context,
                          'Location removed successfully',
                        );
                      }
                    },
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          HugeIcons.strokeRoundedLocationOffline01,
                          color: Colors.orange[700],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No valid location coordinates found for this customer. Please geolocate or select the coordinates from map to display the mapview snippet.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange[900],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanyInfo() {
    if (!(_contact.isCompany ?? false) && _contact.companyName == null) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF23272E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ExpansionTile(
          initiallyExpanded: false,
          backgroundColor: isDark ? const Color(0xFF23272E) : Colors.white,
          collapsedBackgroundColor: isDark
              ? const Color(0xFF23272E)
              : Colors.white,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          childrenPadding: const EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: 20,
          ),

          title: Text(
            'Company Information',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_contact.companyName != null) ...[
                  _buildInfoRow(
                    'Company Name',
                    _contact.companyName,
                    HugeIcons.strokeRoundedBuilding05,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.vat != null) ...[
                  _buildInfoRow(
                    'VAT Number',
                    _contact.vat,
                    HugeIcons.strokeRoundedAccountSetting03,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.industry != null) ...[
                  _buildInfoRow(
                    'Industry',
                    _contact.industry,
                    HugeIcons.strokeRoundedWorkHistory,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.companyType != null) ...[
                  _buildInfoRow(
                    'Company Type',
                    _contact.companyType,
                    HugeIcons.strokeRoundedCatalogue,
                  ),
                  const SizedBox(height: 12),
                ],
                _buildInfoRow(
                  'Website',
                  _contact.website,
                  HugeIcons.strokeRoundedWebDesign02,
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  'Email',
                  _contact.email,
                  HugeIcons.strokeRoundedMail01,
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  'Phone',
                  _contact.phone,
                  HugeIcons.strokeRoundedCall02,
                ),
                const SizedBox(height: 12),
                if (_contact.street != null ||
                    _contact.city != null ||
                    _contact.country != null) ...[
                  _buildInfoRow(
                    'Address',
                    [
                          _contact.street,
                          _contact.street2,
                          _contact.city,
                          _contact.state,
                          _contact.zip,
                          _contact.country,
                        ]
                        .where(
                          (part) =>
                              part != null &&
                              part.trim().isNotEmpty &&
                              part != 'false',
                        )
                        .join(', '),
                    HugeIcons.strokeRoundedLocation05,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessInfo() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF23272E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ExpansionTile(
          initiallyExpanded: false,
          backgroundColor: isDark ? const Color(0xFF23272E) : Colors.white,
          collapsedBackgroundColor: isDark
              ? const Color(0xFF23272E)
              : Colors.white,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          childrenPadding: const EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: 20,
          ),

          title: Text(
            'Business Information',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_contact.salesperson != null) ...[
                  _buildInfoRow(
                    'Salesperson',
                    _contact.salesperson,
                    HugeIcons.strokeRoundedUser,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.customerRank != null) ...[
                  _buildInfoRow(
                    'Customer Rank',
                    _contact.customerRank,
                    HugeIcons.strokeRoundedRanking,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.paymentTerms != null) ...[
                  _buildInfoRow(
                    'Payment Terms',
                    _contact.paymentTerms!,
                    HugeIcons.strokeRoundedPayment02,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.creditLimit != null) ...[
                  _buildInfoRow(
                    'Credit Limit',
                    _contact.creditLimit!,
                    HugeIcons.strokeRoundedBalanceScale,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.currency != null) ...[
                  _buildInfoRow(
                    'Currency',
                    _contact.currency!,
                    HugeIcons.strokeRoundedMoneyExchange03,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.customerType != null) ...[
                  _buildInfoRow(
                    'Customer Type',
                    _contact.customerType!,
                    HugeIcons.strokeRoundedUser02,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.isActive != null) ...[
                  _buildInfoRow(
                    'Status',
                    _contact.isActive! ? 'Active' : 'Inactive',
                    _contact.isActive!
                        ? HugeIcons.strokeRoundedTickDouble03
                        : Icons.cancel_outlined,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayValue = _isRealValue(value) ? value! : 'N/A';
    if (displayValue == 'N/A') return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label:',
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              displayValue,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.normal,
                fontSize: 14,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalInfo() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF23272E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ExpansionTile(
          initiallyExpanded: false,
          backgroundColor: isDark ? const Color(0xFF23272E) : Colors.white,
          collapsedBackgroundColor: isDark
              ? const Color(0xFF23272E)
              : Colors.white,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          childrenPadding: const EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: 20,
          ),

          title: Text(
            'Additional Information',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(
                  'Title',
                  _contact.title,
                  HugeIcons.strokeRoundedUser,
                ),
                const SizedBox(height: 12),

                _buildInfoRow(
                  'Language',
                  _contact.lang,
                  HugeIcons.strokeRoundedLanguageSquare,
                ),
                const SizedBox(height: 12),

                _buildInfoRow(
                  'Timezone',
                  _contact.timezone,
                  HugeIcons.strokeRoundedTime04,
                ),
                const SizedBox(height: 12),

                if (_contact.createdAt != null) ...[
                  _buildInfoRow(
                    'Created',
                    _formatDate(_contact.createdAt!),
                    HugeIcons.strokeRoundedCalendar03,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_contact.updatedAt != null) ...[
                  _buildInfoRow(
                    'Last Updated',
                    _formatDate(_contact.updatedAt!),
                    HugeIcons.strokeRoundedCalendar01,
                  ),
                  const SizedBox(height: 12),
                ],

                _buildInfoRow(
                  'Notes',
                  _contact.comment,
                  HugeIcons.strokeRoundedNote02,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildSpeedDial() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return SpeedDial(
      animatedIcon: AnimatedIcons.menu_close,
      animatedIconTheme: IconThemeData(
        size: 22,
        color: isDark ? Colors.black : Colors.white,
      ),
      spacing: 8,
      spaceBetweenChildren: 8,
      closeManually: false,
      useRotationAnimation: true,
      animationCurve: Curves.easeOutCubic,
      animationDuration: const Duration(milliseconds: 160),
      direction: SpeedDialDirection.up,
      onOpen: () => HapticFeedback.lightImpact(),
      onClose: () => HapticFeedback.selectionClick(),
      backgroundColor: isDark ? Colors.white : primaryColor,
      foregroundColor: isDark ? Colors.black : Colors.white,
      overlayColor: Colors.black,
      overlayOpacity: isDark ? 0.30 : 0.20,
      elevation: 4,
      tooltip: 'Quick Actions',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      childPadding: const EdgeInsets.all(6),
      childMargin: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      heroTag: "speed-dial-hero-tag",
      children: [
        SpeedDialChild(
          child: Icon(
            HugeIcons.strokeRoundedNoteAdd,
            color: isDark ? Colors.white : Colors.white,
            size: 20,
          ),
          backgroundColor: isDark ? Colors.grey[800] : primaryColor,
          elevation: 3,
          label: 'Create Quotation',
          labelStyle: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
          labelBackgroundColor: isDark ? Colors.grey[850] : Colors.white,
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CreateQuoteScreen(customer: _contact),
              ),
            );
            if (result == true) {
              await _loadCustomerData();
            }
          },
        ),
        SpeedDialChild(
          child: Icon(
            HugeIcons.strokeRoundedInvoice04,
            color: isDark ? Colors.white : Colors.white,
            size: 20,
          ),
          backgroundColor: isDark ? Colors.grey[800] : primaryColor,
          elevation: 3,
          label: 'Create Invoice',
          labelStyle: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
          labelBackgroundColor: isDark ? Colors.grey[850] : Colors.white,
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CreateInvoiceScreen(customer: _contact),
              ),
            );
            if (result == true) {
              await _loadCustomerData();
            }
          },
        ),
        SpeedDialChild(
          child: Icon(
            HugeIcons.strokeRoundedShoppingBag02,
            color: isDark ? Colors.white : Colors.white,
            size: 20,
          ),
          backgroundColor: isDark ? Colors.grey[800] : primaryColor,
          elevation: 3,
          label: 'View Orders',
          labelStyle: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
          labelBackgroundColor: isDark ? Colors.grey[850] : Colors.white,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  QuotationListScreen(customerId: _contact.id),
            ),
          ),
        ),
        SpeedDialChild(
          child: Icon(
            HugeIcons.strokeRoundedInvoice03,
            color: isDark ? Colors.white : Colors.white,
            size: 20,
          ),
          backgroundColor: isDark ? Colors.grey[800] : primaryColor,
          elevation: 3,
          label: 'See Invoices',
          labelStyle: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
          labelBackgroundColor: isDark ? Colors.grey[850] : Colors.white,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => InvoiceListScreen(customerId: _contact.id),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1F2937) : Colors.white,
            borderRadius: BorderRadius.circular(16),

            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withOpacity(0.2)
                    : Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isDark ? color.withOpacity(0.15) : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withOpacity(0.3)
                            : Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                        spreadRadius: 0,
                      ),
                      if (!isDark)
                        BoxShadow(
                          color: Colors.white.withOpacity(0.8),
                          blurRadius: 1,
                          offset: const Offset(0, -1),
                          spreadRadius: 0,
                        ),
                    ],
                  ),
                  child: Icon(icon, size: 26, color: color),
                ),
                const SizedBox(height: 16),

                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFFF9FAFB)
                        : const Color(0xFF111827),
                    fontSize: 14,
                    letterSpacing: -0.1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleLocationAction() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    if (_contact.latitude != null &&
        _contact.longitude != null &&
        _contact.latitude != 0.0 &&
        _contact.longitude != 0.0) {
      final lat = _contact.latitude!;
      final lng = _contact.longitude!;
      final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
      if (await canLaunchUrlString(url)) {
        await launchUrlString(url);
      } else {
        CustomSnackbar.showWarning(context, 'Could not open maps.');
      }
      return;
    }

    showModalBottomSheet(
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bottomSheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Location Options',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white24 : Colors.grey[300]),
          ListTile(
            leading: Icon(
              HugeIcons.strokeRoundedCoordinate01,
              color: isDark ? Colors.white : primaryColor,
            ),
            title: Text(
              'Geolocalize with Odoo',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            ),
            subtitle: Text(
              'Use Odoo\'s geolocation service',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
            onTap: () async {
              Navigator.pop(bottomSheetContext);
              await handleCustomerLocation(
                context: context,
                parentContext: context,
                contact: _contact,
                onContactUpdated: (updatedContact) {
                  final provider = Provider.of<ContactProvider>(
                    context,
                    listen: false,
                  );
                  provider.updateContactCoordinates(updatedContact);
                  setState(() {
                    _contact = updatedContact;
                  });
                },
                suppressMapRedirect: true,
              );
            },
          ),
          ListTile(
            leading: Icon(
              HugeIcons.strokeRoundedMaping,
              color: isDark ? Colors.white : primaryColor,
            ),
            title: Text(
              'Select location on map',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            ),
            subtitle: Text(
              'Manually choose a location on the map',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
            onTap: () async {
              Navigator.pop(bottomSheetContext);
              final LatLng? selected = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SelectLocationScreen(
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
              if (selected != null) {
                await _saveCoordinatesToOdoo(
                  selected.latitude,
                  selected.longitude,
                );
              }
            },
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }

  Future<void> _saveCoordinatesToOdoo(double lat, double lng) async {
    final sessionService = Provider.of<SessionService>(context, listen: false);
    final client = await sessionService.client;
    if (client == null) {
      CustomSnackbar.showError(
        context,
        'No active session. Please log in again.',
      );
      return;
    }
  }

  Future<bool?> _showDeleteCustomerDialog(
    BuildContext context,
    Contact customer,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: Text(
          'Delete Customer',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Are you sure you want to delete ${customer.name}? This action is permanent and cannot be undone.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isDark
                ? Colors.grey[300]
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark
                        ? Colors.grey[400]
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.red[700]
                        : Theme.of(context).colorScheme.error,
                    foregroundColor: isDark
                        ? Colors.white
                        : Theme.of(context).colorScheme.onError,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    elevation: isDark ? 0 : 3,
                  ),
                  child: const Text(
                    'Delete',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCustomer(BuildContext context, Contact customer) async {
    if (customer.id == 0) {
      CustomSnackbar.showError(
        context,
        'Invalid customer ID. Cannot delete customer.',
      );
      return;
    }

    final confirmDelete = await _showDeleteCustomerDialog(context, customer);

    if (confirmDelete != true) {
      return;
    }

    final sessionService = Provider.of<SessionService>(context, listen: false);
    final client = await sessionService.client;
    if (client == null) {
      CustomSnackbar.showError(
        context,
        'No active session. Please log in again.',
      );
      return;
    }

    bool isLoadingDialogOpen = true;
    String dialogMessage = 'Checking dependencies...';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primaryColor = Theme.of(context).primaryColor;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: isDark ? Colors.grey[900] : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: isDark ? primaryColor : null,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      dialogMessage,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      isLoadingDialogOpen = false;
    });

    bool hasDependencies = false;
    String dependencyDetails = '';
    try {
      Future<int> safeSearchCount(String model, List domain) async {
        try {
          final modelExists =
              await client.callKw({
                    'model': 'ir.model',
                    'method': 'search_count',
                    'args': [
                      [
                        ['model', '=', model],
                      ],
                    ],
                    'kwargs': {},
                  })
                  as int;

          if (modelExists == 0) {
            return 0;
          }

          final count = await client.callKw({
            'model': model,
            'method': 'search_count',
            'args': [domain],
            'kwargs': {},
          });
          if (count is int) return count;
          return 0;
        } catch (e) {
          return 0;
        }
      }

      final counts = await Future.wait<int>([
        safeSearchCount('sale.order', [
          ['partner_id', '=', customer.id],
          ['state', '!=', 'cancel'],
        ]),
        safeSearchCount('account.move', [
          ['partner_id', '=', customer.id],
          ['move_type', '=', 'out_invoice'],
          ['payment_state', '!=', 'paid'],
        ]),

        safeSearchCount('fleet.vehicle.assignation.log', [
          ['driver_id', '=', customer.id],
        ]),
      ]);

      final openOrdersCount = counts[0];
      final unpaidInvoicesCount = counts[1];
      final vehicleLogsCount = counts[2];

      if (openOrdersCount > 0) {
        hasDependencies = true;
        dependencyDetails += 'Found $openOrdersCount open sale order(s).\n';
      }
      if (unpaidInvoicesCount > 0) {
        hasDependencies = true;
        dependencyDetails += 'Found $unpaidInvoicesCount unpaid invoice(s).\n';
      }
      if (vehicleLogsCount > 0) {
        hasDependencies = true;
        dependencyDetails +=
            'Found $vehicleLogsCount vehicle assignation log(s).\n';
      }
    } catch (e) {
      if (isLoadingDialogOpen && context.mounted) {
        Navigator.of(context).pop();
        isLoadingDialogOpen = false;
      }
      if (context.mounted) {
        CustomSnackbar.showError(context, 'Error checking dependencies: $e');
      }
      return;
    }

    if (hasDependencies) {
      if (isLoadingDialogOpen && context.mounted) {
        Navigator.of(context).pop();
        isLoadingDialogOpen = false;
      }
      if (context.mounted) {
        CustomSnackbar.showWarning(
          context,
          'Cannot delete customer due to dependencies:\n$dependencyDetails'
          'Consider archiving the customer instead.',
        );
      }
      return;
    }

    if (isLoadingDialogOpen && context.mounted) {
      dialogMessage = 'Deleting customer...';
      (context as Element).markNeedsBuild();
    }

    try {
      final result = await client.callKw({
        'model': 'res.partner',
        'method': 'unlink',
        'args': [
          [customer.id],
        ],
        'kwargs': {},
      });

      if (result == true) {
        final contactProvider = Provider.of<ContactProvider>(
          context,
          listen: false,
        );
        contactProvider.contacts.removeWhere((c) => c.id == customer.id);
        contactProvider.notifyListeners();
        if (isLoadingDialogOpen && context.mounted) {
          Navigator.of(context).pop();
          isLoadingDialogOpen = false;
        }

        if (context.mounted) {
          CustomSnackbar.showSuccess(context, 'Customer deleted successfully');
          Navigator.of(context).pop(true);
        }
      } else {
        throw Exception('Failed to delete customer');
      }
    } catch (e) {
      if (isLoadingDialogOpen && context.mounted) {
        Navigator.of(context).pop();
        isLoadingDialogOpen = false;
      }

      String errorMessage = 'Failed to delete customer.';
      bool shouldArchiveFallback = false;
      final errStr = e.toString();
      if (errStr.contains('fleet_vehicle_assignation_log_driver_id_fkey')) {
        errorMessage =
            'Cannot delete customer because they are referenced in vehicle driver history. ';
        shouldArchiveFallback = true;
      } else if (errStr.contains('ValidationError') ||
          errStr.contains('UserError') ||
          errStr.contains('Foreign Key') ||
          errStr.contains('IntegrityError')) {
        errorMessage = 'Cannot delete customer due to dependencies.';
        shouldArchiveFallback = true;
      } else if (errStr.contains('Record does not exist or has been deleted')) {
        if (context.mounted) {
          CustomSnackbar.showWarning(
            context,
            'This customer has already been deleted.',
          );
          Navigator.of(context).pop(true);
        }
        return;
      }

      if (shouldArchiveFallback) {
        try {
          final archived = await client.callKw({
            'model': 'res.partner',
            'method': 'write',
            'args': [
              [customer.id],
              {'active': false},
            ],
            'kwargs': {},
          });
          if (archived == true) {
            final contactProvider = Provider.of<ContactProvider>(
              context,
              listen: false,
            );
            contactProvider.contacts.removeWhere((c) => c.id == customer.id);
            contactProvider.notifyListeners();

            if (context.mounted) {
              CustomSnackbar.showWarning(
                context,
                'Customer archived instead (had dependencies).',
              );
              Navigator.of(context).pop(true);
            }
            return;
          }
        } catch (archiveErr) {}
      }

      if (context.mounted) {
        CustomSnackbar.showError(
          context,
          '$errorMessage Please archive the customer instead.',
        );
      }
    }
  }

  Color _getActivityColor(String type) {
    if (type.isEmpty) return Colors.grey;

    switch (type.toLowerCase()) {
      case 'order created':
        return Colors.blue;
      case 'quote created':
        return Colors.green;
      case 'invoice sent':
        return Colors.orange;
      case 'payment received':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData getActivityIcon(String type) {
    if (type.isEmpty) return HugeIcons.strokeRoundedInformationCircle;

    switch (type.toLowerCase()) {
      case 'order created':
        return HugeIcons.strokeRoundedShoppingCart01;
      case 'quote created':
        return HugeIcons.strokeRoundedFiles01;
      case 'invoice sent':
        return HugeIcons.strokeRoundedInvoice03;
      case 'payment received':
        return HugeIcons.strokeRoundedCreditCard;
      default:
        return HugeIcons.strokeRoundedInformationCircle;
    }
  }

  Color _getStatusColor(String status) {
    if (status.isEmpty) return Colors.grey;

    switch (status.toLowerCase()) {
      case 'draft':
        return Colors.grey;
      case 'sent':
        return Colors.blue;
      case 'sale':
        return Colors.green;
      case 'done':
        return Colors.green;
      case 'cancel':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<Uint8List> generateContactCardImage(
    Contact contact,
    BuildContext context,
  ) async {
    final GlobalKey cardKey = GlobalKey();
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -10000,
        top: -10000,
        child: Material(
          color: Colors.transparent,
          child: _ContactCardShareWidget(contact: contact, cardKey: cardKey),
        ),
      ),
    );

    overlay.insert(entry);
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final boundary =
          cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 4.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData!.buffer.asUint8List();
    } finally {
      entry.remove();
    }
  }

  Color _getThemedIconColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? Theme.of(context).colorScheme.secondary
        : Theme.of(context).primaryColor;
  }
}

class _ContactCardShareWidget extends StatelessWidget {
  final Contact contact;
  final GlobalKey cardKey;

  const _ContactCardShareWidget({required this.contact, required this.cardKey});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyProvider = Provider.of<CurrencyProvider>(
      context,
      listen: false,
    );
    String? formattedCreditLimit;
    if (contact.creditLimit != null &&
        contact.creditLimit!.isNotEmpty &&
        contact.creditLimit != 'false') {
      final double? credit = double.tryParse(contact.creditLimit!);
      if (credit != null) {
        formattedCreditLimit = currencyProvider.formatAmount(
          credit,
          currency: contact.currency?.toString(),
        );
      }
    }
    final avatar = CircularImageWidget(
      base64Image: contact.imageUrl,
      radius: 52,
      fallbackText: contact.name ?? '?',
      backgroundColor: Colors.grey[300]!,
      textColor: Colors.grey[800]!,
    );
    return RepaintBoundary(
      key: cardKey,
      child: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 36),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(color: Colors.black12, blurRadius: 18, spreadRadius: 2),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              avatar,
              const SizedBox(height: 24),
              Text(
                contact.name ?? '',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 30,
                ),
                textAlign: TextAlign.center,
              ),
              if ((contact.title != null &&
                      contact.title!.isNotEmpty &&
                      contact.title != 'false') ||
                  (contact.function != null &&
                      contact.function!.isNotEmpty &&
                      contact.function != 'false'))
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    [contact.title, contact.function]
                        .where((v) => v != null && v.isNotEmpty && v != 'false')
                        .join(' • '),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.grey[700],
                      fontStyle: FontStyle.italic,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 28),
              _infoRow(Icons.business_outlined, contact.companyName),
              _infoRow(Icons.email_outlined, contact.email),
              _infoRow(Icons.phone_outlined, contact.phone),
              _infoRow(Icons.phone_android_outlined, contact.mobile),
              _infoRow(Icons.language_outlined, contact.website),
              _infoRow(
                Icons.location_on_outlined,
                [
                      contact.street,
                      contact.street2,
                      contact.city,
                      contact.state,
                      contact.zip,
                      contact.country,
                    ]
                    .where((v) => v != null && v.isNotEmpty && v != 'false')
                    .join(', '),
              ),
              if (formattedCreditLimit != null)
                _infoRow(
                  Icons.account_balance_wallet_outlined,
                  formattedCreditLimit,
                ),
              if (contact.industry != null &&
                  contact.industry!.isNotEmpty &&
                  contact.industry != 'false')
                _infoRow(Icons.work_outline, contact.industry),
              if (contact.customerRank != null &&
                  contact.customerRank!.isNotEmpty &&
                  contact.customerRank != 'false')
                _infoRow(Icons.star_outline, contact.customerRank),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarFallback() {
    final initial = (contact.name.isNotEmpty)
        ? contact.name.trim()[0].toUpperCase()
        : '?';
    return CircleAvatar(
      radius: 60,
      backgroundColor: Colors.grey[300],
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w700,
          color: Colors.grey[800],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String? value) {
    if (value == null || value.isEmpty || value == 'false') {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.blue[300], size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: Colors.white70,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
