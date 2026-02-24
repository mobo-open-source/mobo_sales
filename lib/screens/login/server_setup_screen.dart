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
                  _CustomAutocompleteField(
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

class _CustomAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final List<String> suggestions;
  final Function(String) onSuggestionSelected;
  final Widget child;

  const _CustomAutocompleteField({
    required this.controller,
    required this.suggestions,
    required this.onSuggestionSelected,
    required this.child,
  });

  @override
  State<_CustomAutocompleteField> createState() =>
      _CustomAutocompleteFieldState();
}

class _CustomAutocompleteFieldState extends State<_CustomAutocompleteField> {
  bool _showSuggestions = false;
  List<String> _filteredSuggestions = [];
  late FocusNode _focusNode;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    widget.controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _updateSuggestions();
      if (_filteredSuggestions.isNotEmpty) {
        _showSuggestionsOverlay();
      }
    } else {
      _hideSuggestions();
    }
  }

  void _onTextChanged() {
    if (_focusNode.hasFocus) {
      _updateSuggestions();
      if (_overlayEntry != null) {
        if (_showSuggestions && _filteredSuggestions.isNotEmpty) {
          _overlayEntry!.markNeedsBuild();
        } else {
          _removeOverlay();
        }
      }
    }
  }

  void _updateSuggestions() {
    final text = widget.controller.text.toLowerCase().trim();

    if (text.isEmpty) {
      _filteredSuggestions = List.from(widget.suggestions);
    } else {
      _filteredSuggestions = widget.suggestions.where((suggestion) {
        final suggestionLower = suggestion.toLowerCase();

        if (text == 'h') {
          return suggestionLower.startsWith('https://');
        } else if (text == 'ht') {
          return suggestionLower.startsWith('http://') ||
              suggestionLower.startsWith('https://');
        } else if (text == 'htt') {
          return suggestionLower.startsWith('http://') ||
              suggestionLower.startsWith('https://');
        } else if (text == 'http') {
          return suggestionLower.startsWith('http://') ||
              suggestionLower.startsWith('https://');
        } else if (text == 'https') {
          return suggestionLower.startsWith('https://');
        } else if (text.startsWith('http://') || text.startsWith('https://')) {
          return suggestionLower.startsWith(text);
        }

        final textDomain = _extractDomainFromUrl(text);
        final suggestionDomain = _extractDomainFromUrl(suggestionLower);

        final matches = suggestionDomain.startsWith(textDomain);

        return matches;
      }).toList();
    }

    for (int i = 0; i < _filteredSuggestions.length; i++) {}

    setState(() {
      _showSuggestions = _filteredSuggestions.isNotEmpty;
    });

    if (_overlayEntry != null) {
      if (_filteredSuggestions.isEmpty) {
        _removeOverlay();
      } else {
        _overlayEntry!.markNeedsBuild();
      }
    } else if (_filteredSuggestions.isNotEmpty) {
      _showSuggestionsOverlay();
    }
  }

  String _extractDomainFromUrl(String url) {
    if (url.startsWith('https://')) {
      return url.substring(8);
    } else if (url.startsWith('http://')) {
      return url.substring(7);
    }
    return url;
  }

  void _showSuggestionsOverlay() {
    if (_filteredSuggestions.isEmpty) {
      return;
    }

    if (_overlayEntry != null) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    final fieldWidth =
        renderBox?.size.width ?? (MediaQuery.of(context).size.width - 48);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hoverColor = isDark
        ? Colors.white.withOpacity(0.1)
        : Colors.black.withOpacity(0.05);

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        width: fieldWidth,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 60),
          child: Material(
            elevation: 12.0,
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            shadowColor: Colors.black.withOpacity(0.2),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.1)
                      : Colors.black.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shrinkWrap: true,
                  itemCount: _filteredSuggestions.length,
                  itemBuilder: (context, index) {
                    final suggestion = _filteredSuggestions[index];
                    return InkWell(
                      onTap: () {
                        widget.onSuggestionSelected(suggestion);
                        _hideSuggestions();
                        _focusNode.unfocus();
                      },
                      hoverColor: hoverColor,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                suggestion,
                                style: GoogleFonts.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: textColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideSuggestions() {
    _removeOverlay();
    setState(() {
      _showSuggestions = false;
    });
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  final LayerLink _layerLink = LayerLink();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Focus(focusNode: _focusNode, child: widget.child),
    );
  }
}
