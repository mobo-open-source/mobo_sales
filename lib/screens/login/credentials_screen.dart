import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:provider/provider.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../../providers/login_provider.dart';
import 'reset_password_screen.dart';
import 'login_layout.dart';
import '../../services/session_service.dart';
import '../../services/odoo_session_manager.dart';
import '../../services/biometric_context_service.dart';

class CredentialsScreen extends StatefulWidget {
  final String url;
  final String database;
  final bool isAddingAccount;
  final String? prefilledUsername;

  const CredentialsScreen({
    super.key,
    required this.url,
    required this.database,
    this.isAddingAccount = false,
    this.prefilledUsername,
  });

  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends State<CredentialsScreen> {
  late LoginProvider _provider;

  bool _shouldValidate = false;

  bool emailHasError = false;
  bool passwordHasError = false;

  String? inlineError;

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _provider = LoginProvider();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _provider.urlController.text = widget.url;
      _provider.setDatabase(widget.database);

      if (widget.prefilledUsername != null &&
          widget.prefilledUsername!.isNotEmpty) {
        _provider.emailController.text = widget.prefilledUsername!;
      }

      if (mounted) {
        if (_provider.emailController.text.isEmpty) {
          FocusScope.of(context).requestFocus(_emailFocus);
        } else {
          FocusScope.of(context).requestFocus(_passwordFocus);
        }
      }
    });
  }

  @override
  void dispose() {
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _provider.dispose();
    super.dispose();
  }

  Future<bool> _addNewAccount(LoginProvider provider) async {
    try {
      final newSession = await OdooSessionManager.authenticate(
        serverUrl: widget.url,
        database: widget.database,
        username: provider.emailController.text.trim(),
        password: provider.passwordController.text,
      );

      if (newSession == null) {
        provider.errorMessage =
            'Authentication failed. Please check your credentials.';
        return false;
      }

      final sessionService = SessionService.instance;
      await sessionService.storeAccount(
        newSession,
        provider.passwordController.text,
      );

      TextInput.finishAutofillContext();

      return true;
    } catch (e) {
      provider.errorMessage = 'Failed to add account: ${e.toString()}';
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Consumer<LoginProvider>(
        builder: (context, provider, child) {
          if (provider.errorMessage != inlineError) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                inlineError = provider.errorMessage;
              });
            });
          }

          return LoginLayout(
            title: widget.isAddingAccount ? 'Add Account' : 'Sign In',
            subtitle: widget.isAddingAccount
                ? 'Enter credentials for the new account'
                : 'Enter your credentials to continue',
            backButton: Positioned(
              top: 24,
              left: 0,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(32),
                  child: Container(
                    height: 64,
                    width: 64,
                    alignment: Alignment.center,
                    child: const Icon(
                      HugeIcons.strokeRoundedArrowLeft01,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
            child: Form(
              key: provider.formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AutofillGroup(
                    child: Column(
                      children: [
                        LoginTextField(
                          controller: provider.emailController,
                          hint: 'Email',
                          prefixIcon: HugeIcons.strokeRoundedMail01,
                          keyboardType: TextInputType.emailAddress,
                          enabled: !provider.disableFields,
                          focusNode: _emailFocus,
                          hasError: emailHasError,
                          autofillHints: const [
                            AutofillHints.email,
                            AutofillHints.username,
                          ],
                          autovalidateMode: _shouldValidate
                              ? AutovalidateMode.onUserInteraction
                              : AutovalidateMode.disabled,
                          validator: (value) {
                            if (provider.isLoadingDatabases ||
                                !_shouldValidate) {
                              return null;
                            }
                            if (value == null || value.isEmpty) {
                              return 'Email is required';
                            }
                            return null;
                          },
                          onChanged: (val) {
                            setState(() {
                              emailHasError = val.isEmpty;
                              if (inlineError != null) {
                                inlineError = null;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 16),

                        LoginTextField(
                          controller: provider.passwordController,
                          hint: 'Password',
                          prefixIcon: HugeIcons.strokeRoundedLockPassword,
                          obscureText: provider.obscurePassword,
                          enabled: !provider.disableFields,
                          focusNode: _passwordFocus,
                          hasError: passwordHasError,
                          autofillHints: const [AutofillHints.password],
                          autovalidateMode: _shouldValidate
                              ? AutovalidateMode.onUserInteraction
                              : AutovalidateMode.disabled,
                          validator: (value) {
                            if (provider.isLoadingDatabases ||
                                !_shouldValidate) {
                              return null;
                            }
                            if (value == null || value.isEmpty) {
                              return 'Password is required';
                            }
                            if (value.isEmpty) {
                              return 'Password must be at least 1 characters';
                            }
                            return null;
                          },
                          suffixIcon: IconButton(
                            icon: Icon(
                              provider.obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.black54,
                              size: 20,
                            ),
                            onPressed: provider.togglePasswordVisibility,
                          ),
                          onChanged: (val) {
                            setState(() {
                              passwordHasError = val.isEmpty || val.isEmpty;
                              if (inlineError != null) {
                                inlineError = null;
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ResetPasswordScreen(
                              url: widget.url,
                              database: widget.database,
                            ),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Forgot Password?',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  LoginErrorDisplay(error: inlineError),

                  LoginButton(
                    text: widget.isAddingAccount ? 'Add Account' : 'Sign In',
                    isLoading: provider.isLoading,
                    loadingWidget: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.isAddingAccount
                              ? 'Adding Account'
                              : 'Signing In',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 12),
                        LoadingAnimationWidget.staggeredDotsWave(
                          color: Colors.white,
                          size: 28,
                        ),
                      ],
                    ),
                    onPressed: provider.isLoading || provider.isLoadingDatabases
                        ? null
                        : () async {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              _shouldValidate = true;
                            });
                            final formValid =
                                provider.formKey.currentState?.validate() ??
                                false;
                            setState(() {
                              emailHasError =
                                  provider.emailController.text.isEmpty;
                              final pwd = provider.passwordController.text;
                              passwordHasError = pwd.isEmpty || pwd.isEmpty;
                              inlineError = null;
                            });

                            if (!formValid) {
                              await HapticFeedback.lightImpact();
                              return;
                            }

                            if (widget.isAddingAccount) {
                              final success = await _addNewAccount(provider);
                              if (!mounted) return;
                              if (success) {
                                setState(() {
                                  inlineError = null;
                                });

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Account added successfully'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                Navigator.of(context).pop();
                              } else {
                                await HapticFeedback.heavyImpact();
                                if (!mounted) return;
                                setState(() {
                                  inlineError =
                                      provider.errorMessage ??
                                      'Failed to add account';
                                });
                              }
                            } else {
                              final biometricContext =
                                  BiometricContextService();
                              biometricContext.startAccountOperation(
                                'account_add',
                              );

                              final ok = await provider.login(context);
                              if (!mounted) return;
                              if (ok) {
                                if (!mounted) return;
                                setState(() {
                                  inlineError = null;
                                });

                                TextInput.finishAutofillContext();

                                Navigator.of(context).pushNamedAndRemoveUntil(
                                  '/app',
                                  (route) => false,
                                );

                                biometricContext.endAccountOperation(
                                  'account_add',
                                );
                              } else if (!ok && provider.errorMessage != null) {
                                await HapticFeedback.heavyImpact();
                                if (!mounted) return;
                                setState(() {
                                  inlineError = provider.errorMessage;
                                });
                              }
                            }
                          },
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
