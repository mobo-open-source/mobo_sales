import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:mobo_sales/services/biometric_service.dart';

class AppLockScreen extends StatefulWidget {
  final VoidCallback? onAuthenticationSuccess;

  const AppLockScreen({super.key, this.onAuthenticationSuccess});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  bool _isAuthenticating = false;
  bool _authenticationFailed = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _performAuthentication();
    });
  }

  Future<void> _performAuthentication() async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    try {
      final success = await BiometricService.authenticateWithBiometrics(
        reason: 'Please authenticate to access the MOBO Sales App',
      );

      if (mounted) {
        setState(() {
          _isAuthenticating = false;
        });

        if (success) {
          setState(() {
            _authenticationFailed = false;
            _errorMessage = null;
          });

          widget.onAuthenticationSuccess?.call();
        } else {
          setState(() {
            _authenticationFailed = true;
            _errorMessage = 'Authentication failed or was cancelled';
          });
        }
      } else {}
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
          _authenticationFailed = true;
          _errorMessage = 'Unexpected authentication error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[950] : Colors.grey[50],
                image: DecorationImage(
                  image: AssetImage('assets/login_background.png'),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    isDark
                        ? Colors.black.withOpacity(1)
                        : Colors.white.withOpacity(1),
                    BlendMode.dstATop,
                  ),
                ),
              ),
            ),
          ),

          LayoutBuilder(
            builder: (context, viewportConstraints) {
              return Column(
                children: [
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 68),
                      child: _buildAppHeader(),
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: viewportConstraints.maxHeight - 180,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildAuthHeader(),
                                  const SizedBox(height: 24),

                                  if (_isAuthenticating)
                                    _buildAuthenticatingDisplay()
                                  else if (_authenticationFailed)
                                    _buildRetryButton()
                                  else
                                    _buildInitialDisplay(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAppHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(
          'assets/logo_white.png',
          width: 32,
          height: 32,
          fit: BoxFit.fitWidth,
        ),
        const SizedBox(width: 12),
        Text(
          'mobo sales',
          style: const TextStyle(
            fontFamily: 'YaroRg',
            color: Colors.white,
            fontSize: 24,
          ),
        ),
      ],
    );
  }

  Widget _buildAuthHeader() {
    return Column(
      children: [
        Text(
          'App Locked',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontSize: 22,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),

        Text(
          'Please authenticate to continue',
          style: GoogleFonts.manrope(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildAuthenticatingDisplay() {
    return Column(
      children: [
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Authenticating...',
          style: GoogleFonts.manrope(
            color: Colors.white70,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildRetryButton() {
    return Column(
      children: [
        if (_errorMessage != null) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                HugeIcons.strokeRoundedAlertCircle,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        SizedBox(
          height: 48,
          width: MediaQuery.of(context).size.width * .7,
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                _authenticationFailed = false;
                _errorMessage = null;
              });
              _performAuthentication();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.black.withOpacity(.2),
              disabledForegroundColor: Colors.white,
              overlayColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Try Again',
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInitialDisplay() {
    return Column(
      children: [
        Icon(Icons.fingerprint, size: 48, color: Colors.white.withOpacity(0.8)),
        const SizedBox(height: 16),
        Text(
          'Touch sensor or use face unlock',
          style: GoogleFonts.manrope(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
