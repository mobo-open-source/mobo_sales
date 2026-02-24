import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../models/quote.dart';
import '../services/odoo_session_manager.dart';
import '../utils/date_picker_utils.dart';
import 'custom_snackbar.dart';

class SignatureWidget extends StatefulWidget {
  final Quote quotation;
  final Function(Map<String, dynamic>) onSignatureUpdated;

  const SignatureWidget({
    super.key,
    required this.quotation,
    required this.onSignatureUpdated,
  });

  @override
  State<SignatureWidget> createState() => _SignatureWidgetState();
}

class _SignatureWidgetState extends State<SignatureWidget> {
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  final TextEditingController _signedByController = TextEditingController();
  DateTime? _signedOnDate;
  Uint8List? _signatureImageBytes;
  bool _isLoading = false;
  bool _hasSignature = false;
  bool _isSignatureFromUpload = false;

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

      if (quotation.extraData!['signed_on'] != null &&
          quotation.extraData!['signed_on'] != false) {
        try {
          _signedOnDate = DateTime.parse(
            quotation.extraData!['signed_on'].toString(),
          );
        } catch (e) {}
      }

      if (quotation.extraData!['signature'] != null &&
          quotation.extraData!['signature'] != false) {
        try {
          final signatureData = quotation.extraData!['signature'].toString();
          _signatureImageBytes = base64Decode(signatureData);
          _hasSignature = true;
          _isSignatureFromUpload = true;
        } catch (e) {
          _hasSignature = false;
          _isSignatureFromUpload = false;
        }
      }
    }
  }

  Future<void> _captureSignature() async {
    if (_hasSignature &&
        _signatureImageBytes != null &&
        _signatureController.isEmpty) {
      CustomSnackbar.showInfo(
        context,
        'A signature image is already uploaded. Draw a new signature to replace it, or clear the existing one first.',
      );
      return;
    }

    if (_hasSignature &&
        _signatureImageBytes != null &&
        _signatureController.isNotEmpty &&
        _isSignatureFromUpload) {
      final shouldReplace = await _showReplaceSignatureDialog(
        contentText:
            'A signature image was uploaded. Do you want to replace it with the drawn signature?',
      );
      if (!shouldReplace) return;
    }

    if (_signatureController.isEmpty) {
      CustomSnackbar.showError(context, 'Please draw your signature first');
      return;
    }

    try {
      final signature = await _signatureController.toPngBytes();
      if (signature != null) {
        final wasExistingSignature =
            _hasSignature && _signatureImageBytes != null;
        setState(() {
          _signatureImageBytes = signature;
          _hasSignature = true;
          _isSignatureFromUpload = false;
        });
        CustomSnackbar.showSuccess(
          context,
          wasExistingSignature
              ? 'Signature updated successfully'
              : 'Signature captured successfully',
        );
      }
    } catch (e) {
      CustomSnackbar.showError(context, 'Failed to capture signature: $e');
    }
  }

  Future<void> _uploadSignatureImage() async {
    if (_hasSignature && _signatureImageBytes != null) {
      final shouldReplace = await _showReplaceSignatureDialog();
      if (!shouldReplace) {
        return;
      }
    }

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      try {
        final bytes = await image.readAsBytes();
        final wasExistingSignature =
            _hasSignature && _signatureImageBytes != null;

        setState(() {
          _signatureImageBytes = bytes;
          _hasSignature = true;
          _isSignatureFromUpload = true;

          _signatureController.clear();
        });

        if (wasExistingSignature) {
          CustomSnackbar.showSuccess(
            context,
            'Signature image replaced successfully',
          );
        } else {
          CustomSnackbar.showSuccess(
            context,
            'Signature image uploaded successfully',
          );
        }
      } catch (e) {
        CustomSnackbar.showError(context, 'Failed to upload image: $e');
      }
    }
  }

  Future<bool> _showReplaceSignatureDialog({String? contentText}) async {
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
                'Replace Signature',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              content: Text(
                contentText ??
                    'A signature already exists. Do you want to replace it with a new image?',
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
                        onPressed: () => Navigator.of(context).pop(false),
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
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark
                              ? Theme.of(context).primaryColor
                              : Theme.of(context).primaryColor,
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
                          'Replace',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ) ??
        false;
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
        _signatureController.clear();
        _signatureImageBytes = null;
        _hasSignature = false;
        _isSignatureFromUpload = false;
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
                'This will remove the signature image but keep the signed by and signed on information. Are you sure?',
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
                        onPressed: () => Navigator.of(context).pop(false),
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
                        onPressed: () => Navigator.of(context).pop(true),
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
                          'Clear Image',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
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

      setState(() {
        _signatureController.clear();
        _signatureImageBytes = null;
        _hasSignature = false;
        _isSignatureFromUpload = false;
      });

      if (widget.quotation.extraData != null) {
        widget.quotation.extraData!['signature'] = false;
      }

      widget.onSignatureUpdated(clearData);

      CustomSnackbar.showSuccess(
        context,
        'Signature image cleared successfully',
      );
    } catch (e) {
      CustomSnackbar.showError(context, 'Failed to clear signature image: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSignature() async {
    if (_signedByController.text.trim().isEmpty) {
      CustomSnackbar.showError(context, 'Please enter who signed the document');
      return;
    }

    if (!_hasSignature && _signatureController.isEmpty) {
      CustomSnackbar.showError(context, 'Please provide a signature');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      Uint8List? signatureBytes = _signatureImageBytes;
      if (signatureBytes == null && _signatureController.isNotEmpty) {
        signatureBytes = await _signatureController.toPngBytes();
      }

      if (signatureBytes == null) {
        throw Exception('No signature data available');
      }

      final signedOn = _signedOnDate ?? DateTime.now();

      final signatureBase64 = base64Encode(signatureBytes);

      final formattedDateTime = DateFormat(
        'yyyy-MM-dd HH:mm:ss',
      ).format(signedOn);

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

      setState(() {
        _signedOnDate = signedOn;
      });

      CustomSnackbar.showSuccess(context, 'Signature saved successfully');
    } catch (e) {
      CustomSnackbar.showError(context, 'Failed to save signature: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateQuotationSignature(
    Map<String, dynamic> signatureData,
  ) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        throw Exception('No Odoo client available');
      }

      final result = await client.callKw({
        'model': 'sale.order',
        'method': 'write',
        'args': [
          [widget.quotation.id],
          signatureData,
        ],
        'kwargs': {},
      });
    } catch (e) {
      rethrow;
    }
  }

  @override
  void dispose() {
    _signatureController.dispose();
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
        _hasSignature && _signatureImageBytes != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Signed By',
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
        _hasSignature && _signatureImageBytes != null;

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
                    lastDate: DateTime.now().add(const Duration(days: 365)),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Signature',
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
          height: 200,
          decoration: BoxDecoration(
            border: Border.all(
              color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
            ),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: _hasSignature && _signatureImageBytes != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _signatureImageBytes!,
                    fit: BoxFit.contain,
                  ),
                )
              : Signature(
                  controller: _signatureController,
                  backgroundColor: Colors.white,
                ),
        ),
        const SizedBox(height: 12),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              onPressed: _uploadSignatureImage,
              icon: Icon(
                Icons.upload_file_outlined,
                size: 18,
                color: isDark ? Colors.white : Colors.black87,
              ),
              label: Text(
                'Upload',
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
            Container(
              height: 24,
              width: 1,
              color: isDark ? Colors.grey[600] : Colors.grey[300],
            ),
            TextButton.icon(
              onPressed: _captureSignature,
              icon: Icon(
                Icons.check_circle_outline,
                size: 18,
                color: isDark ? Colors.white : Colors.black87,
              ),
              label: Text(
                'Capture',
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
        ),
      ],
    );
  }

  Widget _buildActionButtons(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _saveSignature,
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
                : const Icon(Icons.save, size: 18),
            label: Text(_isLoading ? 'Saving...' : 'Save Signature'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
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
