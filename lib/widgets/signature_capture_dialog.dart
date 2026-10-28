import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';

import '../shared/widgets/mobo/mobo_dialog_buttons.dart';
import '../utils/app_theme.dart';
import 'custom_snackbar.dart';

/// A pop-up for capturing a signature, as mobo Delivery captures one.
///
/// The signature used to be drawn inline, in whatever height was left over
/// inside the quotation's tab strip — a few dozen points on a tall order. A
/// dialog gets a canvas worth signing on whatever else is on the page.
///
/// Returns the signature as a base64 PNG, or null if dismissed.
class SignatureCaptureDialog extends StatefulWidget {
  const SignatureCaptureDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const SignatureCaptureDialog(),
    );
  }

  @override
  State<SignatureCaptureDialog> createState() => _SignatureCaptureDialogState();
}

class _SignatureCaptureDialogState extends State<SignatureCaptureDialog> {
  /// CSS `DarkBlue`, the colour Odoo's own signature widget draws in.
  static const Color _inkColor = Color(0xFF00008B);

  /// White space kept around the drawing when it is exported.
  ///
  /// [SignatureController.toImage] crops hard to the ink's bounding box, so a
  /// short stroke exported without bounds becomes a tiny image that whatever
  /// shows it then stretches to fit — which is why a signature came back
  /// looking nothing like what was drawn.
  static const int _exportMargin = 32;

  static const double _canvasHeight = 220;

  late final SignatureController _controller;

  /// A signature chosen from the gallery instead of drawn, matching the
  /// "Load" tab Odoo offers beside "Draw".
  Uint8List? _loaded;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(penColor: _inkColor, penStrokeWidth: 2);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _loaded = bytes;
        _controller.clear();
      });
    } catch (_) {
      if (mounted) {
        CustomSnackbar.showError(context, 'Could not open that image.');
      }
    }
  }

  void _clear() {
    setState(() {
      _controller.clear();
      _loaded = null;
    });
  }

  Future<void> _done() async {
    if (_loaded != null) {
      Navigator.pop(context, base64Encode(_loaded!));
      return;
    }

    if (_controller.isEmpty) {
      CustomSnackbar.showError(context, 'Please sign before saving.');
      return;
    }

    final width = _controller.defaultWidth;
    final height = _controller.defaultHeight;
    final bytes = await _controller.toPngBytes(
      width: width == null ? null : width + _exportMargin * 2,
      height: height == null ? null : height + _exportMargin * 2,
    );
    if (bytes == null || !mounted) return;
    Navigator.pop(context, base64Encode(bytes));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Signature',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                // Always offered, as in mobo Delivery: tracking whether
                // there is ink yet would mean rebuilding on every stroke.
                GestureDetector(
                  onTap: _clear,
                  child: const Text(
                    'Clear',
                    style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _load,
                icon: const Icon(
                  HugeIcons.strokeRoundedUploadSquare02,
                  size: 18,
                  color: AppTheme.primaryColor,
                ),
                label: Text(
                  _loaded == null ? 'Load from image' : 'Choose another',
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: _canvasHeight,
              decoration: BoxDecoration(
                // White whichever theme is on: a signature is ink on paper,
                // and it is stored as an image that keeps this background.
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: _loaded != null
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Image.memory(_loaded!, fit: BoxFit.contain),
                    )
                  : Signature(
                      controller: _controller,
                      backgroundColor: Colors.white,
                      height: _canvasHeight,
                    ),
            ),
            const SizedBox(height: 16),
            MoboDialogButtons(
              secondaryLabel: 'Cancel',
              onSecondary: () => Navigator.pop(context),
              primaryLabel: 'Done',
              onPrimary: _done,
            ),
          ],
        ),
      ),
    );
  }
}
