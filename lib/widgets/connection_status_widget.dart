import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import '../services/connectivity_service.dart';
import '../services/session_service.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lottie/lottie.dart';

class ConnectionStatusWidget extends StatelessWidget {
  final VoidCallback? onRetry;
  final String? customMessage;
  final bool showRetryButton;
  final bool serverUnreachable;
  final String? serverErrorMessage;

  const ConnectionStatusWidget({
    super.key,
    this.onRetry,
    this.customMessage,
    this.showRetryButton = true,
    this.serverUnreachable = false,
    this.serverErrorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.grey.shade900 : Colors.grey[50]!;

    if (serverUnreachable) {
      final errorInfo = _getErrorInfo(serverErrorMessage);

      return _buildLottieErrorState(
        context,
        isDark,
        backgroundColor,
        title: errorInfo['title']!,
        subtitle: errorInfo['message']!,
        buttonText: 'Retry',
        onAction: onRetry,
      );
    }

    return Consumer2<ConnectivityService, SessionService>(
      builder: (context, connectivityService, sessionService, child) {
        if (!connectivityService.isInitialized ||
            !sessionService.isInitialized ||
            sessionService.isCheckingSession) {
          return _buildLoadingState(context, isDark, backgroundColor);
        }

        if (!connectivityService.isConnected) {
          return _buildLottieErrorState(
            context,
            isDark,
            backgroundColor,
            title: 'No Internet Connection',
            subtitle:
                customMessage ??
                'Please check your internet connection and try again.',
            buttonText: 'Retry',
            onAction:
                onRetry ??
                () {
                  context.read<ConnectivityService>().checkConnectivityOnce();
                },
          );
        }

        if (sessionService.isServerUnreachable) {
          return _buildLottieErrorState(
            context,
            isDark,
            backgroundColor,
            title: 'Can\'t Reach Server',
            subtitle:
                'Unable to connect to your Odoo server. Please check your network connection and try again.',
            buttonText: 'Retry',
            onAction: onRetry ?? () => sessionService.checkSession(),
          );
        }

        if (!sessionService.hasValidSession) {
          return _buildLottieErrorState(
            context,
            isDark,
            backgroundColor,
            title: 'Session Expired',
            subtitle:
                'Your session has expired or you have been logged out. Please log in again to continue.',
            buttonText: 'Go to Login',
            onAction: () {
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/login', (route) => false);
            },
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Map<String, String> _getErrorInfo(String? error) {
    if (error == null || error.isEmpty) {
      return {
        'title': 'Can\'t Reach Server',
        'message':
            'Unable to connect to your Odoo server. Please check your network or server status and try again.',
      };
    }

    final errorLower = error.toLowerCase();

    if (errorLower.contains('session expired') ||
        errorLower.contains('access denied') ||
        errorLower.contains('odoo session expired')) {
      return {
        'title': 'Session Expired',
        'message': 'Your session has expired. Please log in again to continue.',
      };
    }

    if (errorLower.contains('socketexception') ||
        errorLower.contains('no route to host') ||
        errorLower.contains('failed host lookup') ||
        errorLower.contains('connection refused') ||
        errorLower.contains('network is unreachable') ||
        errorLower.contains('clientexception') ||
        errorLower.contains('odoo server error')) {
      String serverHint = '';
      final addressMatch = RegExp(r'address = ([^,]+)').firstMatch(error);
      if (addressMatch != null) {
        serverHint = '\n\nServer: ${addressMatch.group(1)}';
      }

      return {
        'title': 'Can\'t Reach Server',
        'message':
            'Unable to connect to your Odoo server. Please check your network connection and try again.$serverHint',
      };
    }

    if (errorLower.contains('formatexception') ||
        errorLower.contains('html') ||
        errorLower.contains('unexpected character')) {
      return {
        'title': 'Server Error',
        'message':
            'The server returned an unexpected response. Please try again later.',
      };
    }

    if (errorLower.contains('500 internal server error')) {
      return {
        'title': 'Server Error (500)',
        'message': 'The server encountered an error. Please try again later.',
      };
    }
    if (errorLower.contains('502 bad gateway')) {
      return {
        'title': 'Server Error (502)',
        'message': 'Bad gateway. The server is temporarily unavailable.',
      };
    }
    if (errorLower.contains('503 service unavailable')) {
      return {
        'title': 'Server Unavailable (503)',
        'message':
            'The server is temporarily unavailable. Please try again later.',
      };
    }
    if (errorLower.contains('504 gateway timeout')) {
      return {
        'title': 'Server Timeout (504)',
        'message': 'The server took too long to respond. Please try again.',
      };
    }

    return {'title': 'Error', 'message': error};
  }

  Widget _buildLoadingState(
    BuildContext context,
    bool isDark,
    Color backgroundColor,
  ) {
    final textColor = isDark ? Colors.white : Colors.black87;
    return Container(
      color: backgroundColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: LoadingAnimationWidget.fourRotatingDots(
                      color: isDark ? Colors.white : Colors.grey[600]!,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Checking connection...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLottieErrorState(
    BuildContext context,
    bool isDark,
    Color backgroundColor, {
    required String title,
    required String subtitle,
    required String buttonText,
    required VoidCallback? onAction,
  }) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    final isSessionError =
        title.toLowerCase().contains('session expired') ||
        subtitle.toLowerCase().contains('session has expired') ||
        subtitle.toLowerCase().contains('log in again');

    final effectiveButtonText = isSessionError ? 'Log In' : buttonText;
    final effectiveOnAction = isSessionError
        ? () {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/login', (route) => false);
          }
        : onAction;

    return Container(
      color: backgroundColor,
      width: double.infinity,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Lottie.asset(
                'assets/lotti/error_404.json',
                width: MediaQuery.of(context).size.width * 0.6,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 15,
                  color: subtitleColor,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              if (showRetryButton && effectiveOnAction != null) ...[
                const SizedBox(height: 32),
                SizedBox(
                  width: 140,
                  child: OutlinedButton(
                    onPressed: effectiveOnAction,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppTheme.primaryColor,
                        width: 1.2,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      foregroundColor: AppTheme.primaryColor,
                    ),
                    child: Text(
                      effectiveButtonText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
