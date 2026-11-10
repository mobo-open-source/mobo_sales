import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import '../services/connectivity_service.dart';
import '../services/odoo_error_classifier.dart';
import '../services/odoo_error_handler.dart';
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
      final errorInfo = errorInfoFor(serverErrorMessage);

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

  /// Maps a raw error string to the title and wording shown for it.
  ///
  /// Public and static so a screen that renders the failure in its own
  /// layout — rather than with this widget's full-screen illustration —
  /// still gets the same words. Duplicating the matching elsewhere is how
  /// two parts of the app end up disagreeing about what the same error
  /// means.

  /// The one wording for "the server could not be reached", whichever screen
  /// hit it.
  ///
  /// Screens do not pass a sentence of their own. One dead server otherwise
  /// reads four different ways, under two different titles, on four tabs of
  /// the same app, and naming the entity that failed to load adds nothing:
  /// the user is looking at the screen it failed on.
  static const Map<String, String> cantReachServer = {
    'title': 'Can\'t Reach Server',
    'message':
        'Unable to connect to your Odoo server. Please check your network or server status and try again.',
  };

  static Map<String, String> errorInfoFor(String? error) {
    if (error == null || error.isEmpty) return cantReachServer;

    final errorLower = error.toLowerCase();

    // Signing in again is the only way out of this one, so it keeps its own
    // wording and its own button.
    if (errorLower.contains('session expired') ||
        errorLower.contains('access denied') ||
        errorLower.contains('odoo session expired')) {
      return {
        'title': 'Session Expired',
        'message': 'Your session has expired. Please log in again to continue.',
      };
    }

    // A named HTTP status means the server answered, so it is worth saying
    // which one: waiting helps here, checking the network does not. Tested
    // before the general case below, which would otherwise swallow them.
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

    // Everything else that means "no usable answer came back" is one
    // condition with one set of words. A refused socket, a proxy's HTML error
    // page, a FormatException from jsonDecode meeting that page, the sentence
    // the providers set — the user does the same thing about all of them, and
    // splitting them is what had Customers saying "Can't Reach Server" while
    // Quotations said "Server Error" about the very same dead server.
    if (_namesATransportFailure(errorLower) ||
        OdooErrorClassifier.isServerUnreachable(error)) {
      final address = RegExp(r'address = ([^,]+)').firstMatch(error);
      if (address == null) return cantReachServer;
      return {
        'title': cantReachServer['title']!,
        'message': '${cantReachServer['message']!}'
            '\n\nServer: ${address.group(1)}',
      };
    }

    // Everything above recognised the failure. This is the one that got
    // away, and it goes through the same gate as every snackbar rather than
    // straight onto the screen.
    //
    // Returning `error` as-is puts Odoo's Python traceback on screen: a read
    // that asks for a field the server does not have arrives as an
    // OdooException carrying file paths, line numbers and all.
    return {
      'title': 'Error',
      'message': OdooErrorHandler.toSnackbarMessage(error),
    };
  }

  /// The shapes a transport failure arrives in that the shared classifier
  /// does not name, because they are wordings this app chose itself.
  static bool _namesATransportFailure(String errorLower) =>
      errorLower.contains('unreachable') ||
      errorLower.contains('from server/database') ||
      errorLower.contains('formatexception') ||
      errorLower.contains('html') ||
      errorLower.contains('unexpected character') ||
      errorLower.contains('no route to host') ||
      errorLower.contains('failed host lookup') ||
      errorLower.contains('connection refused');

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
