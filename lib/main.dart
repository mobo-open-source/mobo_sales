import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:mobo_sales/providers/invoice_creation_provider.dart';
import 'package:mobo_sales/providers/invoice_details_provider_enterprise.dart';
import 'package:mobo_sales/providers/last_opened_provider.dart';
import 'package:mobo_sales/providers/product_provider.dart';
import 'package:mobo_sales/providers/stock_check_provider.dart';
import 'package:mobo_sales/providers/quotation_provider.dart';
import 'package:mobo_sales/providers/settings_provider.dart';
import 'package:mobo_sales/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login/server_setup_screen.dart';
import 'screens/others/webview_screen.dart';
import 'screens/others/get_started_screen.dart';
import 'services/connectivity_service.dart';
import 'services/session_service.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';
import 'providers/contact_provider.dart';
import 'providers/company_provider.dart';
import 'providers/currency_provider.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'auth/auth_check.dart';
import 'screens/splash/splash_screen.dart';
export 'package:flutter/material.dart' show navigatorKey;
export 'package:flutter/material.dart' show GlobalKey, ScaffoldMessengerState;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ContactProvider()),
        ChangeNotifierProvider(create: (_) => CompanyProvider()),
        ChangeNotifierProvider(create: (_) => CurrencyProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => QuotationProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityService()),
        ChangeNotifierProvider(create: (_) => SessionService()),
        ChangeNotifierProvider(create: (_) => StockCheckProvider()),
        ChangeNotifierProvider(create: (_) => InvoiceDetailsProvider()),
        ChangeNotifierProvider(create: (_) => CreateInvoiceProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => LastOpenedProvider()),
        Provider(create: (_) => PreferencesService()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        if (!themeProvider.isInitialized) {
          return const SizedBox.shrink();
        }

        return MaterialApp(
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: scaffoldMessengerKey,
          title: 'mobo sales',
          theme: themeProvider.lightTheme,
          darkTheme: themeProvider.darkTheme,
          themeMode: themeProvider.themeMode,
          home: const SplashScreen(),
          routes: {
            '/get_started': (context) => const GetStartedScreen(),
            '/server_setup': (context) => const ServerSetupScreen(),
            '/login': (context) => const ServerSetupScreen(),
            '/init': (context) => const AuthCheck(),
            '/app': (context) => const AppEntryPoint(),
            '/webview': (context) {
              final args =
                  ModalRoute.of(context)?.settings.arguments
                      as Map<String, dynamic>?;
              return WebViewScreen(
                url: args?['url'] ?? 'https://demo.odoo.com',
                title: args?['title'] ?? 'Web View',
              );
            },
          },
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class AppEntryPoint extends StatefulWidget {
  const AppEntryPoint({super.key});

  @override
  State<AppEntryPoint> createState() => AppEntryPointState();
}

class AppEntryPointState extends State<AppEntryPoint> {
  bool _isInitializing = true;
  String? _errorMessage;
  bool _permissionsGranted = false;
  int _permissionRetryCount = 0;
  static const int _maxRetries = 3;
  bool _hasSeenGetStarted = false;
  SessionService? _sessionService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeApp();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sessionService = context.read<SessionService>();
      _sessionService?.addListener(_onSessionChanged);
    });
  }

  @override
  void dispose() {
    _sessionService?.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() async {}

  Future<void> _initializeApp() async {
    try {
      await _initializePreferences();
      await _checkGetStartedStatus();

      final permissionResult = await _handlePermissions();
      if (!permissionResult) {
        return;
      }

      await _initializeServices();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize app. Please try again.';
      });
    } finally {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  Future<void> _checkGetStartedStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenGetStarted = prefs.getBool('hasSeenGetStarted') ?? false;
      setState(() {
        _hasSeenGetStarted = hasSeenGetStarted;
      });

      if (hasSeenGetStarted) {}
    } catch (e) {
      setState(() {
        _hasSeenGetStarted = false;
      });
    }
  }

  Future<void> _initializePreferences() async {
    try {
      final preferencesService = context.read<PreferencesService>();
      await preferencesService.initialize();
    } catch (e) {
      throw Exception('PreferencesService initialization failed: $e');
    }
  }

  Future<bool> _handlePermissions() async {
    try {
      final preferencesService = context.read<PreferencesService>();
      final isFirstLaunch = preferencesService.isFirstLaunch;
      final permissionsAsked = preferencesService.permissionsAsked;

      if (!isFirstLaunch && permissionsAsked) {
        if (!Platform.isIOS) {
          setState(() {
            _permissionsGranted = true;
          });
          return true;
        }
      }

      final permissionManager = PermissionManager();
      final result = await permissionManager.requestAllPermissions(context);
      await preferencesService.markPermissionsAsked();
      if (isFirstLaunch) {
        await preferencesService.markAppLaunched();
      }

      setState(() {
        _permissionsGranted = result;
      });

      return result;
    } catch (e) {
      return false;
    }
  }

  Future<void> _initializeServices() async {
    try {
      await context.read<ConnectivityService>().initialize().timeout(
        const Duration(seconds: 10),
      );
      await context.read<SessionService>().initialize().timeout(
        const Duration(seconds: 15),
      );
      await context.read<CompanyProvider>().initialize().timeout(
        const Duration(seconds: 15),
      );
    } catch (e) {
      throw Exception('Service initialization failed: $e');
    }
  }

  Future<void> _retryInitialization() async {
    if (_permissionRetryCount >= _maxRetries) {
      setState(() {
        _errorMessage =
            'Maximum retry attempts reached. Please restart the app.';
      });
      return;
    }

    _permissionRetryCount++;
    final delay = Duration(seconds: _permissionRetryCount * 2);

    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    await Future.delayed(delay);
    await _initializeApp();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ConnectivityService, SessionService>(
      builder: (context, connectivityService, sessionService, child) {
        if (_isInitializing) {
          return _buildLoadingScreen2();
        }

        if (_errorMessage != null) {
          return _buildErrorScreen(context);
        }

        if (!_permissionsGranted) {
          return _buildPermissionDeniedScreen();
        }

        if (!connectivityService.isInitialized ||
            !sessionService.isInitialized) {
          return _buildLoadingScreen2();
        }

        if (sessionService.isLoggingOut) {
          return _buildLoadingScreen2(message: 'Logging out...');
        }

        return const AuthCheck();
      },
    );
  }

  Widget _buildLoadingScreen2({String? message}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: Center(
        child: Semantics(
          label: 'Loading, please wait',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LoadingAnimationWidget.staggeredDotsWave(
                color: isDark ? Colors.white : theme.colorScheme.primary,
                size: 50,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Theme.of(context).colorScheme.error,
                size: 80,
              ),
              const SizedBox(height: 24),
              Text(
                'Oops! Something went wrong',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? 'An unexpected error occurred',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => _retryInitialization(),
                    child: const Text('Retry'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: () => _retryInitialization(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                    child: Text(
                      'Try Again (${_maxRetries - _permissionRetryCount} left)',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedScreen() {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 80,
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome to mobo Sales!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Permissions will be requested when you use specific features like voice search, scanning, or location services.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => setState(() {
                  _permissionsGranted = true;
                }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
                child: const Text('Get Started'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PermissionManager {
  PermissionManager();

  Future<bool> requestAllPermissions(BuildContext context) async {
    try {
      return true;
    } catch (e) {
      return false;
    }
  }
}
