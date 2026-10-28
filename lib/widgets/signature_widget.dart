import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import '../models/quote.dart';
import '../services/data_change_bus.dart';
import '../services/odoo_error_handler.dart';
import '../services/odoo_session_manager.dart';
import '../utils/odoo_binary.dart';
import '../shared/widgets/mobo/mobo_dialog_buttons.dart';
import '../shared/widgets/mobo/mobo_field_label.dart';
import '../utils/date_picker_utils.dart';
import 'custom_snackbar.dart';
import 'signature_capture_dialog.dart';

class SignatureWidget extends StatefulWidget {
  final Quote quotation;
  final Function(Map<String, dynamic>) onSignatureUpdated;

  /// Whether Odoo would accept a signature for this order right now
  /// (`sale.order._has_to_be_signed()`, see [saleOrderHasToBeSigned]).
  ///
  /// False leaves the tab showing what is on file and nothing to draw with:
  /// a confirmed, expired or already-signed order is not signable in Odoo,
  /// and a salesperson never captures this in the backend at all — the
  /// customer signs on the portal.
  final bool canSign;

  /// Where the signature is written; the signed-in session when null. A test
  /// passes its own.
  @visibleForTesting
  final Future<dynamic> Function(Map<String, dynamic> payload)? callKw;

  const SignatureWidget({
    this.canSign = false,
    super.key,
    required this.quotation,
    required this.onSignatureUpdated,
    this.callKw,
  });

  @override
  State<SignatureWidget> createState() => _SignatureWidgetState();
}

class _SignatureWidgetState extends State<SignatureWidget> {

  final TextEditingController _signedByController = TextEditingController();
  DateTime? _signedOnDate;
  Uint8List? _signatureImageBytes;
  bool _isLoading = false;
  bool _hasSignature = false;

  @override
  void initState() {
    super.initState();
    _loadExistingSignatureData();
  }

  void _loadExistingSignatureData() {
    final quotation = widget.quotation;

    if (quotation.extraData != null) {
      if (quotation.extraData!['signed_by'] != null &&
          quotation.extraData!['signed_by'] != false) {
        _signedByController.text = quotation.extraData!['signed_by'].toString();
      }

      final signedOn = quotation.extraData!['signed_on'];
      if (signedOn != null && signedOn != false) {
        _signedOnDate = parseOdooDatetime(signedOn.toString());
      }

      // The image as base64 text, whether the server sent the text (Odoo 17 to
      // 19), a `{content, size}` object (20) or a data URI.
      final signature = odooBinaryToBase64(quotation.extraData!['signature']);
      if (signature != null) {
        try {
          final comma = signature.indexOf(',');
          _signatureImageBytes = base64Decode(
            signature.startsWith('data:') && comma != -1
                ? signature.substring(comma + 1)
                : signature,
          );
          _hasSignature = true;
        } catch (e) {
          _hasSignature = false;
        }
      }
    }
  }

  /// Opens the capture dialog and keeps what comes back.
  ///
  /// The drawing used to happen inline, in whatever height the tab strip had
  /// left; the dialog gives it a canvas regardless of how long the order is.
  /// Nothing is sent to Odoo until Save Signature.
  Future<void> _captureSignature() async {
    final base64Png = await SignatureCaptureDialog.show(context);
    if (base64Png == null || !mounted) return;

    final replaced = _hasSignature && _signatureImageBytes != null;
    setState(() {
      _signatureImageBytes = base64Decode(base64Png);
      _hasSignature = true;
    });
    CustomSnackbar.showSuccess(
      context,
      replaced
          ? 'Signature updated — tap Save Signature to send it'
          : 'Signature captured — tap Save Signature to send it',
    );
  }

  Future<void> _clearSignature() async {
    final hasBackendSignature =
        widget.quotation.extraData != null &&
        widget.quotation.extraData!['signature'] != null &&
        widget.quotation.extraData!['signature'] != false;

    if (hasBackendSignature) {
      final shouldClear = await _showClearConfirmationDialog();
      if (!shouldClear) return;

      await _clearSignatureImageFromBackend();
    } else {
      setState(() {
          _signatureImageBytes = null;
        _hasSignature = false;
      });
      CustomSnackbar.showSuccess(context, 'Signature image cleared');
    }
  }

  Future<bool> _showClearConfirmationDialog() async {
    if (!mounted) return false;

    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: isDark ? 0 : 8,
              backgroundColor: isDark ? Colors.grey[900] : Colors.white,
              title: Text(
                'Clear Signature Image',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              content: Text(
                'This will remove the signature image. The signed by and signed on details stay until you save a new signature. Are you sure?',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? Colors.grey[300]
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              actions: [
                MoboDialogButtons(
                  secondaryLabel: 'Cancel',
                  onSecondary: () => Navigator.of(context).pop(false),
                  primaryLabel: 'Clear Image',
                  onPrimary: () => Navigator.of(context).pop(true),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _clearSignatureImageFromBackend() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final clearData = {'signature': false};

      await _updateQuotationSignature(clearData);

      if (widget.quotation.extraData != null) {
        widget.quotation.extraData!['signature'] = false;
      }

      widget.onSignatureUpdated(clearData);

      if (!mounted) return;
      setState(() {
          _signatureImageBytes = null;
        _hasSignature = false;
        // The next signature is signed when it is saved, not when the cleared
        // one was.
        _signedOnDate = null;
      });

      CustomSnackbar.showSuccess(
        context,
        'Signature image cleared successfully',
      );
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          OdooErrorHandler.toSnackbarMessage(
            e,
            fallback: 'Could not clear the signature. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveSignature() async {
    if (_signedByController.text.trim().isEmpty) {
      CustomSnackbar.showError(context, 'Please enter who signed the document');
      return;
    }

    if (!_hasSignature) {
      CustomSnackbar.showError(context, 'Please provide a signature');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final Uint8List? signatureBytes = _signatureImageBytes;
      if (signatureBytes == null) {
        throw Exception('No signature data available');
      }

      final signedOn = _signedOnDate ?? DateTime.now();

      final signatureBase64 = base64Encode(signatureBytes);

      final formattedDateTime = formatOdooDatetime(signedOn);

      final updateData = {
        'signed_by': _signedByController.text.trim(),
        'signed_on': formattedDateTime,
        'signature': signatureBase64,
      };

      await _updateQuotationSignature(updateData);

      if (widget.quotation.extraData != null) {
        widget.quotation.extraData!['signed_by'] = updateData['signed_by'];
        widget.quotation.extraData!['signed_on'] = updateData['signed_on'];
        widget.quotation.extraData!['signature'] = updateData['signature'];
      }

      widget.onSignatureUpdated(updateData);

      if (!mounted) return;
      setState(() {
        _signedOnDate = signedOn;
      });

      CustomSnackbar.showSuccess(context, 'Signature saved successfully');
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          OdooErrorHandler.toSnackbarMessage(
            e,
            fallback: 'Could not save the signature. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateQuotationSignature(
    Map<String, dynamic> signatureData,
  ) async {
    try {
      var callKw = widget.callKw;
      if (callKw == null) {
        final client = await OdooSessionManager.getClient();
        if (client == null) {
          throw Exception('No Odoo client available');
        }
        callKw = client.callKw;
      }

      await callKw({
        'model': 'sale.order',
        'method': 'write',
        'args': [
          [widget.quotation.id],
          signatureData,
        ],
        'kwargs': {},
      });

      // The server has the signature (or has dropped it): the quotation is not
      // what the lists and the pages open behind this one last showed.
      DataChangeBus.instance.quotationChanged(widget.quotation.id);
    } catch (e) {
      rethrow;
    }
  }

  @override
  void dispose() {
    _signedByController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSignedByField(isDark),
          const SizedBox(height: 20),

          _buildSignedOnField(isDark),
          const SizedBox(height: 20),

          _buildSignatureField(isDark),
          const SizedBox(height: 30),

          _buildActionButtons(isDark),
        ],
      ),
    );
  }

  Widget _buildSignedByField(bool isDark) {
    final bool isSignatureLocked =
        !widget.canSign || (_hasSignature && _signatureImageBytes != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            MoboFieldLabel(
              'Signed By',
              isRequired: true,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            if (isSignatureLocked) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.lock_outline,
                size: 16,
                color: isDark ? Colors.grey[300] : Colors.grey[600],
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _signedByController,
          enabled: !isSignatureLocked,
          decoration: InputDecoration(
            hintText: isSignatureLocked
                ? 'Locked - Clear signature to edit'
                : 'Enter name of person signing',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).primaryColor,
                width: 2,
              ),
            ),
            filled: true,
            fillColor: isSignatureLocked
                ? (isDark ? Colors.grey[850] : Colors.grey[100])
                : (isDark ? Colors.grey[800] : Colors.grey[50]),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          style: TextStyle(
            color: isSignatureLocked
                ? (isDark ? Colors.grey[500] : Colors.grey[500])
                : (isDark ? Colors.white : Colors.black87),
          ),
        ),
      ],
    );
  }

  Widget _buildSignedOnField(bool isDark) {
    final bool isSignatureLocked =
        !widget.canSign || (_hasSignature && _signatureImageBytes != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Signed On',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            if (isSignatureLocked) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.lock_outline,
                size: 16,
                color: isDark ? Colors.grey[300] : Colors.grey[600],
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: isSignatureLocked
              ? null
              : () async {
                  final date = await DatePickerUtils.showStandardDatePicker(
                    context: context,
                    initialDate: _signedOnDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    // Nobody signs in the future: Odoo stamps the moment of
                    // signing.
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    final time = await DatePickerUtils.showStandardTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(
                        _signedOnDate ?? DateTime.now(),
                      ),
                    );
                    if (time != null) {
                      setState(() {
                        _signedOnDate = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                      });
                    }
                  }
                },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSignatureLocked
                    ? (isDark ? Colors.grey[700]! : Colors.grey[200]!)
                    : (isDark ? Colors.grey[600]! : Colors.grey[300]!),
              ),
              borderRadius: BorderRadius.circular(8),
              color: isSignatureLocked
                  ? (isDark ? Colors.grey[850] : Colors.grey[100])
                  : (isDark ? Colors.grey[800] : Colors.grey[50]),
            ),
            child: Text(
              isSignatureLocked && _signedOnDate == null
                  ? 'Locked - Clear signature to edit'
                  : _signedOnDate != null
                  ? DateFormat('MMM dd, yyyy - HH:mm').format(_signedOnDate!)
                  : 'Select date and time',
              style: TextStyle(
                color: isSignatureLocked
                    ? (isDark ? Colors.grey[500] : Colors.grey[500])
                    : _signedOnDate != null
                    ? (isDark ? Colors.white : Colors.black87)
                    : (isDark ? Colors.grey[400] : Colors.grey[600]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignatureField(bool isDark) {
    final hasImage = _hasSignature && _signatureImageBytes != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            MoboFieldLabel(
              'Signature',
              isRequired: widget.canSign,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Container(
          width: double.infinity,
          height: 160,
          decoration: BoxDecoration(
            border: Border.all(
              color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
            ),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          clipBehavior: Clip.antiAlias,
          child: hasImage
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.memory(
                    _signatureImageBytes!,
                    fit: BoxFit.contain,
                  ),
                )
              : Center(
                  child: Text(
                    'Not signed yet',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ),
        ),

        // Drawing happens in a dialog, not here: inside the page's tab strip
        // the canvas was a couple of dozen points tall, and `toImage` crops
        // to the ink, so a stroke squeezed into that space came back cropped
        // and stretched out of shape.
        if (widget.canSign) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: _captureSignature,
                icon: Icon(
                  HugeIcons.strokeRoundedPenTool03,
                  size: 18,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                label: Text(
                  hasImage ? 'Sign again' : 'Sign',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  minimumSize: const Size(80, 36),
                ),
              ),
              if (hasImage) ...[
                Container(
                  height: 24,
                  width: 1,
                  color: isDark ? Colors.grey[600] : Colors.grey[300],
                ),
                TextButton.icon(
                  onPressed: _clearSignature,
                  icon: const Icon(
                    Icons.clear_outlined,
                    size: 18,
                    color: Colors.red,
                  ),
                  label: const Text(
                    'Clear',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    minimumSize: const Size(80, 36),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  /// Why Save Signature cannot be pressed, or null when it can.
  ///
  /// The button stays on screen and greyed rather than disappearing: a
  /// control that vanishes leaves the user wondering what they did wrong,
  /// where one that is plainly off and says why does not.
  String? get _saveBlockedReason {
    if (!widget.canSign) {
      if (_hasSignature) {
        return 'This order is already signed. Odoo does not take a second '
            'signature for the same order.';
      }
      return 'This order cannot be signed. Odoo only accepts a signature on a '
          'quotation that asks for one, has not expired and is not already '
          'signed.';
    }
    if (!_hasSignature) {
      return 'There is nothing to save yet. Tap Sign to capture a signature '
          'first.';
    }
    return null;
  }

  Widget _buildActionButtons(bool isDark) {
    final blocked = _saveBlockedReason;
    final enabled = blocked == null && !_isLoading;

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            // Still tappable while blocked, so the tap can explain itself
            // instead of doing nothing.
            onPressed: _isLoading
                ? null
                : enabled
                ? _saveSignature
                : () => CustomSnackbar.showInfo(context, blocked!),
            icon: _isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDark ? Colors.grey[400]! : Colors.grey[600]!,
                      ),
                    ),
                  )
                : Icon(
                    Icons.save,
                    size: 18,
                    color: enabled ? Colors.white : Colors.white70,
                  ),
            label: Text(
              _isLoading ? 'Saving...' : 'Save Signature',
              style: TextStyle(color: enabled ? Colors.white : Colors.white70),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: enabled
                  ? Theme.of(context).primaryColor
                  : (isDark ? Colors.grey[700] : Colors.grey[400]),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A datetime as Odoo sends it (`2026-10-01 10:00:00`, always UTC), in the
/// user's time zone. Null when [value] is not one.
@visibleForTesting
DateTime? parseOdooDatetime(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;
  final hasZone = RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(text);
  final parsed = DateTime.tryParse(
    hasZone ? text : '${text.replaceFirst(' ', 'T')}Z',
  );
  return parsed?.toLocal();
}

/// [moment] as Odoo wants a datetime written: UTC, `yyyy-MM-dd HH:mm:ss`.
@visibleForTesting
String formatOdooDatetime(DateTime moment) =>
    DateFormat('yyyy-MM-dd HH:mm:ss').format(moment.toUtc());
