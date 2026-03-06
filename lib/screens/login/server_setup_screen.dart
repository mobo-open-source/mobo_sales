import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/login_provider.dart';
import 'credentials_screen.dart';
import 'login_layout.dart';

class ServerSetupScreen extends StatefulWidget {
  final bool isAddingAccount;

  const ServerSetupScreen({super.key, this.isAddingAccount = false});

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen>
    with TickerProviderStateMixin {
  late AnimationController _databaseFadeController;
  late Animation<double> _databaseFadeAnimation;

  bool _shouldValidate = false;

  bool urlHasError = false;
  bool dbHasError = false;

  String? inlineError;

  Timer? _urlDebounce;

  @override
  void initState() {
    super.initState();
    _databaseFadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _databaseFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _databaseFadeController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _urlDebounce?.cancel();
    _databaseFadeController.dispose();
    super.dispose();
  }

  void _handleDatabaseFetch(LoginProvider provider) {
    if (provider.urlCheck && provider.dropdownItems.isNotEmpty) {
      _databaseFadeController.forward();
    } else if (!provider.urlCheck || provider.dropdownItems.isEmpty) {
      _databaseFadeController.reverse();
    }
  }

  void _goToCredentials(LoginProvider provider) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CredentialsScreen(
          url: provider.getFullUrl(),
          database: provider.database!,
          isAddingAccount: widget.isAddingAccount,
        ),
      ),
    );
  }

  bool _canProceedToCredentials(LoginProvider provider) {
    return provider.urlController.text.trim().isNotEmpty &&
        provider.database != null &&
        provider.database!.isNotEmpty &&
        !provider.isLoadingDatabases &&
        provider.urlCheck;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LoginProvider(),
      child: Consumer<LoginProvider>(
        builder: (context, provider, child) {
          _handleDatabaseFetch(provider);

          if (!provider.isLoadingDatabases &&
              provider.errorMessage != inlineError) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                inlineError = provider.errorMessage;
              });
            });
          }

          return LoginLayout(
            title: 'Sign In',
            subtitle: 'Configure your server connection',
            child: Form(
              key: provider.formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LoginUrlAutocompleteField(
                    controller: provider.urlController,
                    suggestions: provider.previousUrls,
                    onSuggestionSelected: (String selection) {
                      provider.setUrlFromFullUrl(selection);

                      final domain = provider.extractDomain(selection);

                      setState(() {
                        urlHasError = domain.isEmpty;
                      });

                      if (domain.trim().isNotEmpty) {
                        _urlDebounce?.cancel();
                        if (!provider.isLoadingDatabases &&
                            provider.isValidUrl(domain)) {
                          setState(() {
                            dbHasError = false;
                            inlineError = null;
                            _shouldValidate = false;
                          });
                          provider.formKey.currentState?.validate();
                          provider.fetchDatabaseList();
                        }
                      }
                    },
                    child: LoginUrlTextField(
                      controller: provider.urlController,
                      hint: 'Enter Server Address',
                      prefixIcon: HugeIcons.strokeRoundedServerStack01,
                      enabled: !provider.disableFields,
                      hasError: urlHasError,
                      selectedProtocol: provider.selectedProtocol,
                      isLoading: provider.isLoadingDatabases,
                      autovalidateMode: _shouldValidate
                          ? AutovalidateMode.onUserInteraction
                          : AutovalidateMode.disabled,
                      validator: (value) {
                        if (provider.isLoadingDatabases || !_shouldValidate) {
                          return null;
                        }
                        if (value == null || value.isEmpty) {
                          return 'Server URL is required';
                        }
                        return null;
                      },
                      onChanged: (val) {
                        final newUrlHasError = val.isEmpty;
                        if (urlHasError != newUrlHasError ||
                            dbHasError ||
                            inlineError != null ||
                            _shouldValidate) {
                          setState(() {
                            urlHasError = newUrlHasError;
                            dbHasError = false;
                            inlineError = null;
                            _shouldValidate = false;
                          });
                          provider.formKey.currentState?.validate();
                        }

                        _urlDebounce?.cancel();
                        final trimmed = val.trim();
                        if (trimmed.isEmpty) {
                          provider.fetchDatabaseList();
                        } else {
                          _urlDebounce = Timer(
                            const Duration(milliseconds: 700),
                            () {
                              if (!mounted) return;
                              if (provider.isValidUrl(trimmed)) {
                                if (dbHasError || inlineError != null) {
                                  setState(() {
                                    dbHasError = false;
                                    inlineError = null;
                                  });
                                  provider.formKey.currentState?.validate();
                                }
                                provider.fetchDatabaseList();
                              }
                            },
                          );
                        }
                      },
                      onProtocolChanged: (protocol) {
                        provider.setProtocol(protocol);

                        final trimmed = provider.urlController.text.trim();
                        if (trimmed.isNotEmpty &&
                            provider.isValidUrl(trimmed)) {
                          _urlDebounce?.cancel();
                          _urlDebounce = Timer(
                            const Duration(milliseconds: 300),
                            () {
                              if (!mounted) return;
                              provider.fetchDatabaseList();
                            },
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  AnimatedBuilder(
                    animation: _databaseFadeAnimation,
                    builder: (context, child) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: _databaseFadeAnimation.value > 0 ? null : 0,
                        child: Opacity(
                          opacity: _databaseFadeAnimation.value,
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              (1 - _databaseFadeAnimation.value) * -20,
                            ),
                            child: Column(
                              children: [
                                LoginDropdownField(
                                  hint: provider.isLoadingDatabases
                                      ? 'Loading...'
                                      : provider.errorMessage != null
                                      ? 'Unable to load'
                                      : 'Database',
                                  value: provider.database,
                                  items:
                                      provider.urlCheck &&
                                          provider.dropdownItems.isNotEmpty
                                      ? provider.dropdownItems
                                      : [],
                                  onChanged:
                                      (provider.disableFields ||
                                          provider.isLoadingDatabases)
                                      ? null
                                      : (val) {
                                          provider.setDatabase(val);
                                          setState(() {
                                            dbHasError =
                                                (val == null || val.isEmpty);
                                            inlineError = null;
                                          });
                                          provider.formKey.currentState
                                              ?.validate();
                                        },
                                  validator: (value) {
                                    if (provider.isLoadingDatabases ||
                                        !_shouldValidate) {
                                      return null;
                                    }
                                    if (value == null || value.isEmpty) {
                                      return 'Database is required';
                                    }
                                    return null;
                                  },
                                  hasError: dbHasError,
                                  autovalidateMode: _shouldValidate
                                      ? AutovalidateMode.onUserInteraction
                                      : AutovalidateMode.disabled,
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  LoginErrorDisplay(error: inlineError),

                  LoginButton(
                    text: 'Next',
                    onPressed: _canProceedToCredentials(provider)
                        ? () => _goToCredentials(provider)
                        : null,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}


