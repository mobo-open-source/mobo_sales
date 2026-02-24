import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/session_service.dart';
import '../services/auth_service.dart';
import '../screens/login/totp_page.dart';

/// Manages user login form state, database discovery, and authentication flow.
class LoginProvider with ChangeNotifier {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  bool urlCheck = false;
  bool disableFields = false;
  String? database;
  String? errorMessage;
  bool isLoading = false;
  bool isLoadingDatabases = false;
  List<String> dropdownItems = [];
  OdooClient? client;
  bool obscurePassword = true;
  List<String> _previousUrls = [];
  List<String> get previousUrls => _previousUrls;
  bool _disposed = false;
  String _selectedProtocol = 'https://';
  String get selectedProtocol => _selectedProtocol;

  final TextEditingController urlController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final AuthService _authService;

  LoginProvider({AuthService? authService})
    : _authService = authService ?? AuthService() {
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _disposed = true;
    urlController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _safeNotifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Toggles the password field's visibility between hidden and visible.
  void togglePasswordVisibility() {
    obscurePassword = !obscurePassword;
    notifyListeners();
  }

  /// Sets the URL protocol (e.g. `https://` or `http://`) for subsequent requests.
  void setProtocol(String protocol) {
    _selectedProtocol = protocol;
    notifyListeners();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final urls = prefs.getStringList('previous_server_urls') ?? [];
      _previousUrls = urls;

      _safeNotifyListeners();
    } catch (e) {}
  }

  Future<void> _saveCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fullUrl = getFullUrl();

      List<String> urls = prefs.getStringList('previous_server_urls') ?? [];
      if (fullUrl.isNotEmpty && !urls.contains(fullUrl)) {
        urls.insert(0, fullUrl);

        if (urls.length > 10) {
          urls = urls.take(10).toList();
        }
        await prefs.setStringList('previous_server_urls', urls);
        _previousUrls = urls;
      }
    } catch (e) {}
  }

  String _normalizeUrl(String url) {
    String normalizedUrl = url.trim();

    if (!normalizedUrl.startsWith('http://') &&
        !normalizedUrl.startsWith('https://')) {
      normalizedUrl = '$_selectedProtocol$normalizedUrl';
    }

    if (normalizedUrl.endsWith('/')) {
      normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 1);
    }

    return normalizedUrl;
  }

  /// Returns the full URL combining the selected protocol and the URL field text.
  String getFullUrl() {
    final url = urlController.text.trim();
    if (url.isEmpty) return '';

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    return '$_selectedProtocol$url';
  }

  /// Extracts the protocol prefix (`https://` or `http://`) from [fullUrl].
  String extractProtocol(String fullUrl) {
    if (fullUrl.startsWith('https://')) {
      return 'https://';
    } else if (fullUrl.startsWith('http://')) {
      return 'http://';
    }
    return _selectedProtocol;
  }

  /// Strips the protocol prefix from [fullUrl] and returns only the domain portion.
  String extractDomain(String fullUrl) {
    if (fullUrl.startsWith('https://')) {
      return fullUrl.substring(8);
    } else if (fullUrl.startsWith('http://')) {
      return fullUrl.substring(7);
    }
    return fullUrl;
  }

  /// Parses [fullUrl] and populates the URL controller and protocol accordingly.
  void setUrlFromFullUrl(String fullUrl) {
    final protocol = extractProtocol(fullUrl);
    final domain = extractDomain(fullUrl);

    _selectedProtocol = protocol;

    urlController.text = domain;
  }

  /// Clears all form fields and resets state.
  void clearForm() {
    urlController.clear();
    emailController.clear();
    passwordController.clear();
    database = null;
    dropdownItems.clear();
    urlCheck = false;
    errorMessage = null;
    isLoading = false;
    isLoadingDatabases = false;
    disableFields = false;
    notifyListeners();
  }

  /// Fetches the list of databases available at the entered server URL.
  Future<void> fetchDatabaseList() async {
    if (urlController.text.trim().isEmpty) {
      _resetDatabaseState();
      errorMessage = 'Please enter a server URL first.';
      _safeNotifyListeners();
      return;
    }

    if (!isValidUrl(urlController.text.trim())) {
      _resetDatabaseState();
      errorMessage = 'Please enter a valid server URL.';
      _safeNotifyListeners();
      return;
    }

    final previousDatabase = database;

    isLoadingDatabases = true;
    urlCheck = false;
    errorMessage = null;
    dropdownItems.clear();
    _safeNotifyListeners();

    try {
      final baseUrl = _normalizeUrl(urlController.text);

      final dbList = await _authService.fetchDatabaseList(baseUrl);

      if (dbList.isEmpty) {
        errorMessage = 'No databases found on this server.';
        urlCheck = false;
      } else {
        final uniqueDbList = dbList.toSet().toList();
        uniqueDbList.sort((a, b) => a.toString().compareTo(b.toString()));

        dropdownItems = uniqueDbList.map((db) => db.toString()).toList();

        urlCheck = true;
        errorMessage = null;

        if (previousDatabase != null &&
            uniqueDbList.contains(previousDatabase)) {
          database = previousDatabase;
        } else if (uniqueDbList.isNotEmpty) {
          database = uniqueDbList.first.toString();
        }
      }
    } on SocketException catch (e) {
      if (e.toString().contains('Network is unreachable')) {
        errorMessage =
            'No internet connection. Please check your network settings and try again.';
      } else if (e.toString().contains('Connection refused')) {
        errorMessage =
            'Server is not responding. Please verify the server URL and ensure the server is running.';
      } else {
        errorMessage =
            'Network error occurred. Please check your internet connection and server URL.';
      }
      _resetDatabaseState();
    } on TimeoutException catch (_) {
      errorMessage =
          'Connection timed out. The server may be slow or unreachable. Please try again.';
      _resetDatabaseState();
    } on OdooException catch (e) {
      errorMessage = _formatOdooError(e);
      _resetDatabaseState();
    } on FormatException catch (e) {
      if (e.toString().toLowerCase().contains('html')) {
        errorMessage =
            'Invalid server response. This may not be an Odoo server or the URL path is incorrect.';
      } else {
        errorMessage =
            'Server sent invalid data format. Please verify this is an Odoo server.';
      }
      _resetDatabaseState();
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('handshake')) {
        errorMessage =
            'SSL connection failed. Try using HTTP instead of HTTPS or contact your administrator.';
      } else if (errorStr.contains('certificate')) {
        errorMessage =
            'SSL certificate error. The server certificate may be invalid or expired.';
      } else if (errorStr.contains('host')) {
        errorMessage =
            'Cannot reach server. Please check the server URL and your internet connection.';
      } else {
        errorMessage =
            'Unable to connect to server. Please verify the server URL is correct.';
      }
      _resetDatabaseState();
    } finally {
      isLoadingDatabases = false;
      _safeNotifyListeners();
    }
  }

  void _resetDatabaseState() {
    database = null;
    urlCheck = false;
    dropdownItems.clear();
  }

  String _formatOdooError(OdooException e) {
    final message = e.message.toLowerCase();

    if (message.contains('404') || message.contains('not found')) {
      return 'Server not found. Please verify your server URL is correct and the server is running.';
    } else if (message.contains('403') || message.contains('forbidden')) {
      return 'Access denied. The server may not allow database listing or requires authentication.';
    } else if (message.contains('500') ||
        message.contains('internal server error')) {
      return 'Server error occurred. Please contact your system administrator or try again later.';
    } else if (message.contains('timeout') || message.contains('timed out')) {
      return 'Connection timed out. Please check your internet connection and try again.';
    } else if (message.contains('ssl') || message.contains('certificate')) {
      return 'SSL certificate error. Try using HTTP instead of HTTPS, or contact your administrator.';
    } else if (message.contains('connection refused') ||
        message.contains('refused')) {
      return 'Connection refused. Please verify the server URL and port number are correct.';
    } else {
      return 'Unable to connect to server. Please check your server URL and internet connection.';
    }
  }

  /// Sets the currently selected [value] database.
  void setDatabase(String? value) {
    database = value;
    notifyListeners();
  }

  String _formatLoginError(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('html instead of json') ||
        errorStr.contains('formatexception')) {
      return 'Server configuration issue. This may not be an Odoo server or the URL is incorrect.';
    } else if (errorStr.contains('invalid login') ||
        errorStr.contains('wrong credentials')) {
      return 'Incorrect email or password. Please check your login credentials.';
    } else if (errorStr.contains('user not found') ||
        errorStr.contains('no such user')) {
      return 'User account not found. Please check your email address or contact your administrator.';
    } else if (errorStr.contains('database') &&
        errorStr.contains('not found')) {
      return 'Selected database is not available. Please choose a different database.';
    } else if (errorStr.contains('network') || errorStr.contains('socket')) {
      return 'Network connection failed. Please check your internet connection.';
    } else if (errorStr.contains('timeout')) {
      return 'Connection timed out. The server may be slow or unreachable.';
    } else if (errorStr.contains('unauthorized') || errorStr.contains('403')) {
      return 'Access denied. Your account may not have permission to access this database.';
    } else if (errorStr.contains('server') || errorStr.contains('500')) {
      return 'Server error occurred. Please try again later or contact your administrator.';
    } else if (errorStr.contains('ssl') || errorStr.contains('certificate')) {
      return 'SSL connection failed. Try using HTTP instead of HTTPS.';
    } else if (errorStr.contains('connection refused')) {
      return 'Server is not responding. Please verify the server URL and try again.';
    } else {
      return 'Login failed. Please check your credentials and server settings.';
    }
  }

  /// Attempts to log in with the current form values and navigates on success.
  Future<bool> login(BuildContext context) async {
    if (formKey.currentState != null && !formKey.currentState!.validate()) {
      return false;
    }

    if (database == null || database!.isEmpty) {
      errorMessage = 'Please select a database first.';
      _safeNotifyListeners();
      return false;
    }

    isLoading = true;
    errorMessage = null;
    disableFields = true;
    _safeNotifyListeners();

    try {
      final serverUrl = _normalizeUrl(urlController.text);
      final userLogin = emailController.text.trim();
      final password = passwordController.text.trim();

      if (serverUrl.isEmpty || userLogin.isEmpty || password.isEmpty) {
        throw Exception('Please fill in all required fields.');
      }

      final loginSuccess = await _authService.loginAndSaveSession(
        serverUrl: serverUrl,
        database: database!,
        userLogin: userLogin,
        password: password,
      );

      if (loginSuccess) {
        await _saveCredentials();

        await _setAuthenticationTimestamp();

        try {
          final sessionService = SessionService();
          await sessionService.updateAccountCredentials(userLogin, password);
        } catch (e) {}

        return true;
      } else {
        errorMessage = 'Login failed. Please check your credentials.';
        return false;
      }
    } on SocketException {
      errorMessage =
          'Network connection failed. Please check your internet connection.';
      return false;
    } on TimeoutException {
      errorMessage =
          'Connection timed out. The server may be slow or unreachable.';
      return false;
    } on OdooException catch (e) {
      errorMessage = _formatOdooError(e);
      return false;
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('mfa') ||
          errorStr.contains('two-factor') ||
          errorStr.contains('two factor') ||
          errorStr.contains('2fa') ||
          errorStr.contains('totp') ||
          errorStr.contains('verification code required')) {
        if (context.mounted) {
          final serverUrl = _normalizeUrl(urlController.text);
          final userLogin = emailController.text.trim();
          final password = passwordController.text.trim();

          if (context.mounted) {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TotpPage(
                  serverUrl: serverUrl,
                  database: database!,
                  username: userLogin,
                  password: password,
                  protocol: _selectedProtocol,
                  isAddingAccount: false,
                ),
              ),
            );

            if (result == true) {
              await _saveCredentials();
              await _setAuthenticationTimestamp();
              return true;
            }
          }
        }
        return false;
      }

      errorMessage = _formatLoginError(e);
      return false;
    } finally {
      isLoading = false;
      disableFields = false;
      _safeNotifyListeners();
    }
  }

  Future<void> _setAuthenticationTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt('lastSuccessfulAuth', currentTime);
    } catch (e) {}
  }

  /// Returns `true` if [url] is a syntactically valid HTTP(S) URL.
  bool isValidUrl(String url) {
    try {
      String urlToValidate = url.trim();
      if (!urlToValidate.startsWith('http://') &&
          !urlToValidate.startsWith('https://')) {
        urlToValidate = '$_selectedProtocol$urlToValidate';
      }

      final uri = Uri.parse(urlToValidate);
      return uri.hasScheme && uri.host.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  bool get isFormReady {
    return urlController.text.trim().isNotEmpty &&
        emailController.text.trim().isNotEmpty &&
        passwordController.text.trim().isNotEmpty &&
        database != null &&
        database!.isNotEmpty &&
        !isLoading &&
        !isLoadingDatabases;
  }
}
