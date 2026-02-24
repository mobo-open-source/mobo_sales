import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:hugeicons/hugeicons.dart';
import '../services/runtime_permission_service.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  _BarcodeScannerScreenState createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  MobileScannerController? cameraController;
  bool _screenOpened = false;
  bool _permissionRequested = false;
  bool _hasPermission = false;
  bool _isInitializing = true;

  bool _isTorchOn = false;
  CameraFacing _cameraFacing = CameraFacing.back;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (_permissionRequested) return;
    _permissionRequested = true;

    final hasPermission =
        await RuntimePermissionService.requestCameraPermission(context);

    if (mounted) {
      setState(() {
        _hasPermission = hasPermission;
        _isInitializing = false;
      });

      if (hasPermission) {
        cameraController = MobileScannerController();
      } else {
        Navigator.pop(context);
      }
    }
  }

  void _toggleTorch() {
    if (cameraController == null) return;
    setState(() {
      _isTorchOn = !_isTorchOn;
    });
    cameraController!.toggleTorch();
  }

  void _switchCamera() {
    if (cameraController == null) return;
    setState(() {
      _cameraFacing = _cameraFacing == CameraFacing.back
          ? CameraFacing.front
          : CameraFacing.back;
    });
    cameraController!.switchCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('Scan Barcode', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: Icon(HugeIcons.strokeRoundedArrowLeft01, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            color: Colors.white,
            icon: _isTorchOn
                ? Icon(HugeIcons.strokeRoundedFlash, color: Colors.yellow)
                : Icon(HugeIcons.strokeRoundedFlashOff, color: Colors.grey),
            iconSize: 32.0,
            onPressed: _toggleTorch,
          ),
          IconButton(
            color: Colors.white,
            icon: _cameraFacing == CameraFacing.back
                ? Icon(HugeIcons.strokeRoundedCamera02)
                : Icon(HugeIcons.strokeRoundedCamera01),
            iconSize: 32.0,
            onPressed: _switchCamera,
          ),
        ],
      ),
      body: _isInitializing
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Initializing camera...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            )
          : !_hasPermission
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.camera_alt_outlined,
                    size: 64,
                    color: Colors.white54,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Camera permission denied',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Please grant camera permission to scan barcodes',
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : cameraController == null
          ? Center(child: CircularProgressIndicator(color: Colors.white))
          : Stack(
              children: [
                MobileScanner(
                  controller: cameraController!,
                  onDetect: (capture) {
                    if (!_screenOpened) {
                      final List<Barcode> barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        if (barcode.rawValue != null &&
                            barcode.rawValue!.isNotEmpty) {
                          _screenOpened = true;
                          Navigator.pop(context, barcode.rawValue);
                          break;
                        }
                      }
                    }
                  },
                ),

                CustomScannerOverlay(
                  borderColor: Colors.white,
                  borderRadius: 16,
                  borderLength: 30,
                  borderWidth: 4,
                  cutOutSize: 280,
                  overlayColor: Colors.black54,
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    cameraController?.dispose();
    super.dispose();
  }
}

class CustomScannerOverlay extends StatelessWidget {
  final Color borderColor;
  final double borderWidth;
  final Color overlayColor;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  const CustomScannerOverlay({
    super.key,
    this.borderColor = Colors.white,
    this.borderWidth = 3.0,
    this.overlayColor = const Color.fromRGBO(0, 0, 0, 80),
    this.borderRadius = 0,
    this.borderLength = 40,
    this.cutOutSize = 250,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final cutOutWidth = cutOutSize < width
            ? cutOutSize
            : width - borderWidth;
        final cutOutHeight = cutOutSize < height
            ? cutOutSize
            : height - borderWidth;

        return Stack(
          children: [
            Container(color: overlayColor),

            Positioned(
              left: (width - cutOutWidth) / 2,
              top: (height - cutOutHeight) / 2,
              child: Container(
                width: cutOutWidth,
                height: cutOutHeight,
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor, width: borderWidth),
                  borderRadius: BorderRadius.circular(borderRadius),
                ),
                child: CustomPaint(
                  painter: CornerPainter(
                    borderColor: borderColor,
                    borderWidth: borderWidth,
                    borderLength: borderLength,
                    borderRadius: borderRadius,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class CornerPainter extends CustomPainter {
  final Color borderColor;
  final double borderWidth;
  final double borderLength;
  final double borderRadius;

  CornerPainter({
    required this.borderColor,
    required this.borderWidth,
    required this.borderLength,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final path = Path();

    path.moveTo(0, borderLength);
    path.lineTo(0, borderRadius);
    path.quadraticBezierTo(0, 0, borderRadius, 0);
    path.lineTo(borderLength, 0);

    path.moveTo(size.width - borderLength, 0);
    path.lineTo(size.width - borderRadius, 0);
    path.quadraticBezierTo(size.width, 0, size.width, borderRadius);
    path.lineTo(size.width, borderLength);

    path.moveTo(size.width, size.height - borderLength);
    path.lineTo(size.width, size.height - borderRadius);
    path.quadraticBezierTo(
      size.width,
      size.height,
      size.width - borderRadius,
      size.height,
    );
    path.lineTo(size.width - borderLength, size.height);

    path.moveTo(borderLength, size.height);
    path.lineTo(borderRadius, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - borderRadius);
    path.lineTo(0, size.height - borderLength);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
