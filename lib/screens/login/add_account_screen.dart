import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/session_service.dart';
import '../../services/odoo_session_manager.dart';
import '../../services/odoo_api_service.dart';
import 'login_layout.dart'
    show
        LoginLayout,
        LoginTextField,
        LoginButton,
        LoginErrorDisplay,
        LoginUrlTextField,
        LoginDropdownField;
import '../../widgets/custom_snackbar.dart';
import 'totp_page.dart';

enum AddAccountStep { server, credentials }

class AddAccountScreen extends StatefulWidget {
  const AddAccountScreen({super.key});

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  AddAccountStep _currentStep = AddAccountStep.server;
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isLoadingDatabases = false;
  bool _shouldValidate = false;
  bool _urlHasError = false;
  bool _dbHasError = false;
  bool _emailHasError = false;
  bool _passwordHasError = false;
  String? _inlineError;
  String? _errorMessage;
  String? _dbInfoMessage;

  String _selectedProtocol = 'https://';
  String? _selectedDatabase;
  List<String> _databases = [];
  List<String> _urlHistory = [];
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadCurrentSessionInfo();
  }

  Future<void> _loadCurrentSessionInfo() async {
    final sessionService = SessionService.instance;
    final currentSession = sessionService.currentSession;
    final prefs = await SharedPreferences.getInstance();

    final urlHistoryList = prefs.getStringList('previous_server_urls') ?? [];

    if (mounted) {
      setState(() {
        _urlHistory = urlHistoryList;
      });
    }

    if (currentSession != null) {
      String cleanUrl = currentSession.serverUrl;
      String protocol = 'https://';

      if (cleanUrl.startsWith('https://')) {
        protocol = 'https://';
        cleanUrl = cleanUrl.substring(8);
      } else if (cleanUrl.startsWith('http://')) {
        protocol = 'http://';
        cleanUrl = cleanUrl.substring(7);
      }

      if (mounted) {
        setState(() {
          _selectedProtocol = protocol;
          _urlController.text = cleanUrl;
          _selectedDatabase = currentSession.database;
        });

        _validateUrlAndFetchDatabases();
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  String _extractProtocol(String fullUrl) {
    if (fullUrl.startsWith('https://')) return 'https://';
    if (fullUrl.startsWith('http://')) return 'http://';
    return _selectedProtocol;
  }

  String _extractDomain(String fullUrl) {
    if (fullUrl.startsWith('https://')) return fullUrl.substring(8);
    if (fullUrl.startsWith('http://')) return fullUrl.substring(7);
    return fullUrl;
  }

  bool _isValidUrl(String url) {
    try {
      String urlToValidate = url.trim();
      if (urlToValidate.isEmpty) return false;

      if (!urlToValidate.startsWith('http://') &&
          !urlToValidate.startsWith('https://')) {
        urlToValidate = '$_selectedProtocol$urlToValidate';
      }

      final uri = Uri.parse(urlToValidate);
      if (!uri.hasScheme || uri.host.isEmpty) {
        return false;
      }
      if (uri.path.isNotEmpty && uri.path != '/') {
        return false;
      }
      if (uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
        return false;
      }

      final host = uri.host.toLowerCase();
      if (host.contains(' ') || host.startsWith('.') || host.endsWith('.')) {
        return false;
      }

      final validHostPattern = RegExp(r'^[a-zA-Z0-9.-]+$');
      if (!validHostPattern.hasMatch(host)) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  String _normalizeUrl(String url) {
    String normalizedUrl = url.trim();

    if (!normalizedUrl.startsWith('http://') &&
        !normalizedUrl.startsWith('https://')) {
      normalizedUrl = '$_selectedProtocol$normalizedUrl';
    }

    try {
      final uri = Uri.parse(normalizedUrl);
      final origin = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : 0,
      );
      final originStr = origin.hasPort && origin.port != 0
          ? '${origin.scheme}://${origin.host}:${origin.port}'
          : '${origin.scheme}://${origin.host}';
      return originStr;
    } catch (_) {
      if (normalizedUrl.endsWith('/')) {
        normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 1);
      }
      return normalizedUrl;
    }
  }

  Future<void> _validateUrlAndFetchDatabases() async {
    final trimmedUrl = _urlController.text.trim();

    if (trimmedUrl.isEmpty) {
      setState(() {
        _databases.clear();
        _selectedDatabase = null;
        _errorMessage = null;
        _isLoadingDatabases = false;
      });
      return;
    }

    if (!_isValidUrl(trimmedUrl)) {
      setState(() {
        _databases.clear();
        _selectedDatabase = null;
        _errorMessage = 'Please enter a valid server URL';
        _isLoadingDatabases = false;
      });
      return;
    }

    if (!mounted) return;

    setState(() {
      _isLoadingDatabases = true;
      _errorMessage = null;
      _databases.clear();
    });

    try {
      final baseUrl = _normalizeUrl(trimmedUrl);

      final databases = await OdooApiService()
          .listDatabasesForUrl(baseUrl)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw Exception(
                'Connection timeout. Please check your internet connection.',
              );
            },
          );

      if (!mounted) return;

      final previousSelected = _selectedDatabase;
      setState(() {
        _databases = databases;
        _isLoadingDatabases = false;
        _urlHasError = false;
        if (_databases.isEmpty) {
          _selectedDatabase = null;
          _errorMessage = null;
        } else {
          if (previousSelected != null &&
              _databases.contains(previousSelected)) {
            _selectedDatabase = previousSelected;
          } else {
            _selectedDatabase = _databases.first;
          }
          _errorMessage = null;
        }
      });

      if (mounted && _databases.isEmpty) {
        final defaultDb = await OdooApiService.getDefaultDatabase(baseUrl);
        if (!mounted) return;
        setState(() {
          if (defaultDb != null && defaultDb.isNotEmpty) {
            _databases = [defaultDb];
            _selectedDatabase = defaultDb;
            _errorMessage = null;
            _dbInfoMessage = 'Detected default database: $defaultDb';
          } else {
            _selectedDatabase = null;
            _errorMessage =
                'This server does not expose the database list and no default database could be detected.';
            _dbInfoMessage = null;
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      final errStr = e.toString();
      if (errStr.contains('ACCESS_DENIED_DB_LIST')) {
        if (!mounted) return;
        setState(() {
          _isLoadingDatabases = false;
          _databases.clear();
          _selectedDatabase = null;
          _errorMessage =
              'Database listing is disabled (list_db=false). Cannot fetch databases automatically.';
          _dbInfoMessage = null;
        });
      } else {
        String errorMessage =
            'Could not connect to server. Please check the URL and try again.';

        if (errStr.contains('timeout') ||
            errStr.contains('Connection timeout')) {
          errorMessage =
              'Connection timeout. Please check your internet connection and try again.';
        } else if (errStr.contains('404') || errStr.contains('not found')) {
          errorMessage = 'Server not found. Please verify the URL is correct.';
        } else if (errStr.contains('connection') ||
            errStr.contains('network') ||
            errStr.contains('SocketException')) {
          errorMessage =
              'Unable to connect to server. Check URL and network connection.';
        } else if (errStr.contains('FormatException') ||
            errStr.contains('Invalid')) {
          errorMessage =
              'Invalid server URL format. Please check and try again.';
        }

        final baseUrl = _normalizeUrl(trimmedUrl);
        final defaultDb = await OdooApiService.getDefaultDatabase(baseUrl);
        if (!mounted) return;
        if (defaultDb != null && defaultDb.isNotEmpty) {
          setState(() {
            _isLoadingDatabases = false;
            _databases = [defaultDb];
            _selectedDatabase = defaultDb;
            _errorMessage = null;
            _dbInfoMessage = 'Detected default database: $defaultDb';
          });
        } else {
          setState(() {
            _isLoadingDatabases = false;
            _databases.clear();
            _selectedDatabase = null;
            _errorMessage = errorMessage;
            _dbInfoMessage = null;
          });
        }
      }
    }
  }

  String _getFullUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return '';

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    return '$_selectedProtocol$url';
  }

  Future<void> _addAccount() async {
    final fullUrl = _getFullUrl();
    final finalDb = _selectedDatabase ?? '';
    if (fullUrl.isEmpty || finalDb.isEmpty) {
      setState(() {
        _errorMessage = 'Please configure server and database first.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final newSession = await OdooSessionManager.authenticate(
        serverUrl: fullUrl,
        database: finalDb,
        username: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (newSession == null) {
        setState(() {
          _errorMessage =
              'Authentication failed. Please check your credentials.';
          _isLoading = false;
        });
        return;
      }

      final sessionService = SessionService.instance;
      await sessionService.storeAccount(newSession, _passwordController.text);

      try {
        final prefs = await SharedPreferences.getInstance();
        List<String> urls = prefs.getStringList('previous_server_urls') ?? [];
        urls.removeWhere((u) => u == fullUrl);
        urls.insert(0, fullUrl);
        if (urls.length > 10) {
          urls = urls.take(10).toList();
        }
        await prefs.setStringList('previous_server_urls', urls);
      } catch (_) {}

      await sessionService.switchToAccount(newSession);

      try {
        TextInput.finishAutofillContext(shouldSave: true);
      } catch (_) {}

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        CustomSnackbar.showSuccess(
          context,
          'Account added and switched successfully',
        );
      });
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('mfa') ||
          errorStr.contains('two factor') ||
          errorStr.contains('2fa') ||
          errorStr.contains('totp') ||
          errorStr.contains('verification code required')) {
        if (mounted) {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TotpPage(
                serverUrl: fullUrl,
                database: finalDb,
                username: _emailController.text.trim(),
                password: _passwordController.text,
                protocol: _selectedProtocol,
                isAddingAccount: true,
              ),
            ),
          );

          if (result == true) {
            try {
              final session = await OdooSessionManager.getCurrentSession();
              if (session != null) {
                final sessionService = SessionService.instance;
                await sessionService.storeAccount(
                  session,
                  _passwordController.text,
                );

                try {
                  final prefs = await SharedPreferences.getInstance();
                  List<String> urls =
                      prefs.getStringList('previous_server_urls') ?? [];
                  urls.removeWhere((u) => u == fullUrl);
                  urls.insert(0, fullUrl);
                  if (urls.length > 10) {
                    urls = urls.take(10).toList();
                  }
                  await prefs.setStringList('previous_server_urls', urls);
                } catch (_) {}

                await sessionService.switchToAccount(session);
                try {
                  TextInput.finishAutofillContext(shouldSave: true);
                } catch (_) {}

                if (!mounted) return;
                setState(() {
                  _isLoading = false;
                });
                CustomSnackbar.showSuccess(
                  context,
                  'Account added and switched successfully',
                );
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/app', (route) => false);
                return;
              }
            } catch (e) {}
          }

          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      setState(() {
        _errorMessage = _parseLoginError(e.toString());
        _isLoading = false;
      });
    }
  }

  String _parseLoginError(String error) {
    final errorLower = error.toLowerCase();

    if (errorLower.contains('access denied') ||
        errorLower.contains('invalid login') ||
        errorLower.contains('authentication failed') ||
        errorLower.contains('wrong login/password') ||
        errorLower.contains('invalid username or password') ||
        errorLower.contains('login failed')) {
      return 'Invalid username or password. Please check your credentials and try again.';
    }

    if ((errorLower.contains('database') && errorLower.contains('not found')) ||
        (errorLower.contains('database') &&
            errorLower.contains('does not exist')) ||
        (errorLower.contains('psycopg2.operationalerror') &&
            errorLower.contains('does not exist')) ||
        (errorLower.contains('fatal:') &&
            errorLower.contains('does not exist'))) {
      final dbNameMatch = RegExp(
        r'database\s+"?([A-Za-z0-9_\-]+)"?\s+does not exist',
      ).firstMatch(error);
      final dbName = dbNameMatch?.group(1);
      if (dbName != null && dbName.isNotEmpty) {
        return 'The database "$dbName" does not exist on this server. Please verify the name or contact your administrator.';
      }
      return 'The specified database does not exist on this server. Please verify the name or contact your administrator.';
    }

    if (errorLower.contains('connection') ||
        errorLower.contains('network') ||
        errorLower.contains('timeout') ||
        errorLower.contains('unreachable')) {
      return 'Unable to connect to server. Please check your internet connection and server URL.';
    }

    if (errorLower.contains('500') ||
        errorLower.contains('internal server error')) {
      return 'Server error occurred. Please try again later or contact your administrator.';
    }

    return 'Failed to add account: $error';
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != _inlineError) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _inlineError = _errorMessage;
        });
      });
    }

    return LoginLayout(
      title: 'Add Account',
      subtitle: _currentStep == AddAccountStep.server
          ? 'Configure your server connection'
          : 'Enter your credentials',
      backButton: Positioned(
        top: 24,
        left: 0,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (_currentStep == AddAccountStep.credentials) {
                setState(() {
                  _currentStep = AddAccountStep.server;
                  _errorMessage = null;
                  _inlineError = null;
                });
              } else {
                Navigator.of(context).pop();
              }
            },
            borderRadius: BorderRadius.circular(32),
            child: Container(
              height: 64,
              width: 64,
              alignment: Alignment.center,
              child: const HugeIcon(
                icon: HugeIcons.strokeRoundedArrowLeft01,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_currentStep == AddAccountStep.server) ...[
              LoginUrlTextField(
                controller: _urlController,
                hint: 'Server Address',
                prefixIcon: HugeIcons.strokeRoundedServerStack01,
                enabled: !_isLoading,
                hasError: _urlHasError,
                selectedProtocol: _selectedProtocol,
                isLoading: _isLoadingDatabases,
                autovalidateMode: _shouldValidate
                    ? AutovalidateMode.onUserInteraction
                    : AutovalidateMode.disabled,
                validator: (value) {
                  if (!_shouldValidate) return null;
                  if (value == null || value.isEmpty) {
                    return 'Server URL is required';
                  }
                  return null;
                },
                onProtocolChanged: (protocol) {
                  setState(() {
                    _selectedProtocol = protocol;
                  });
                  _validateUrlAndFetchDatabases();
                },
                onChanged: (value) {
                  _debounceTimer?.cancel();
                  setState(() {
                    _urlHasError = false;
                    _errorMessage = null;
                  });

                  _debounceTimer = Timer(const Duration(milliseconds: 700), () {
                    if (mounted) {
                      _validateUrlAndFetchDatabases();
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              if (_databases.isNotEmpty || _isLoadingDatabases) ...[
                LoginDropdownField(
                  hint: _isLoadingDatabases ? 'Loading...' : 'Database',
                  value: _selectedDatabase,
                  items: _databases,
                  onChanged: _isLoading || _isLoadingDatabases
                      ? null
                      : (String? newValue) {
                          setState(() {
                            _selectedDatabase = newValue;
                            _dbHasError =
                                (newValue == null || newValue.isEmpty);
                            _errorMessage = null;
                          });
                        },
                  validator: (value) {
                    if (!_shouldValidate) return null;
                    if (value == null || value.isEmpty) {
                      return 'Database is required';
                    }
                    return null;
                  },
                  hasError: _dbHasError,
                  autovalidateMode: _shouldValidate
                      ? AutovalidateMode.onUserInteraction
                      : AutovalidateMode.disabled,
                ),
                const SizedBox(height: 16),
                if (_dbInfoMessage != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      _dbInfoMessage!,
                      style: GoogleFonts.manrope(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ],

              LoginErrorDisplay(error: _inlineError),

              LoginButton(
                text: 'Next',
                isLoading: _isLoadingDatabases,
                onPressed: (!_isLoadingDatabases) && (_selectedDatabase != null)
                    ? () {
                        setState(() {
                          _shouldValidate = true;
                        });
                        final canProceed = _selectedDatabase != null;
                        if (canProceed) {
                          setState(() {
                            _currentStep = AddAccountStep.credentials;
                            _shouldValidate = false;
                            _errorMessage = null;
                            _inlineError = null;
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              FocusScope.of(context).requestFocus(_emailFocus);
                            }
                          });
                        }
                      }
                    : null,
              ),
            ] else ...[
              AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LoginTextField(
                      controller: _emailController,
                      hint: 'Email / Username',
                      prefixIcon: HugeIcons.strokeRoundedMail01,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !_isLoading,
                      focusNode: _emailFocus,
                      hasError: _emailHasError,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                      ],
                      autovalidateMode: _shouldValidate
                          ? AutovalidateMode.onUserInteraction
                          : AutovalidateMode.disabled,
                      validator: (value) {
                        if (!_shouldValidate) return null;
                        if (value == null || value.isEmpty) {
                          return 'Email is required';
                        }
                        return null;
                      },
                      onChanged: (val) {
                        setState(() {
                          _emailHasError = val.isEmpty;
                          if (_inlineError != null) {
                            _inlineError = null;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    LoginTextField(
                      controller: _passwordController,
                      hint: 'Password',
                      prefixIcon: HugeIcons.strokeRoundedLockPassword,
                      obscureText: _obscurePassword,
                      enabled: !_isLoading,
                      focusNode: _passwordFocus,
                      hasError: _passwordHasError,
                      autofillHints: const [AutofillHints.password],
                      autovalidateMode: _shouldValidate
                          ? AutovalidateMode.onUserInteraction
                          : AutovalidateMode.disabled,
                      validator: (value) {
                        if (!_shouldValidate) return null;
                        if (value == null || value.isEmpty) {
                          return 'Password is required';
                        }
                        return null;
                      },
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? HugeIcons.strokeRoundedView
                              : HugeIcons.strokeRoundedViewOff,
                          size: 20,
                          color: Colors.black54,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      onChanged: (val) {
                        setState(() {
                          _passwordHasError = val.isEmpty;
                          if (_inlineError != null) {
                            _inlineError = null;
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              LoginErrorDisplay(error: _inlineError),

              LoginButton(
                text: 'Add Account',
                isLoading: _isLoading,
                loadingWidget: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Adding Account',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    LoadingAnimationWidget.staggeredDotsWave(
                      color: Colors.white,
                      size: 28,
                    ),
                  ],
                ),
                onPressed: _isLoading
                    ? null
                    : () async {
                        FocusScope.of(context).unfocus();
                        setState(() {
                          _shouldValidate = true;
                        });

                        final formValid =
                            _formKey.currentState?.validate() ?? false;
                        setState(() {
                          _emailHasError = _emailController.text.isEmpty;
                          final pwd = _passwordController.text;
                          _passwordHasError = pwd.isEmpty;
                          _inlineError = null;
                        });

                        if (!formValid) {
                          await HapticFeedback.lightImpact();
                          return;
                        }

                        await _addAccount();

                        if (!mounted) return;
                        if (_errorMessage != null) {
                          await HapticFeedback.heavyImpact();
                          setState(() {
                            _inlineError = _errorMessage;
                          });
                        }
                      },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
