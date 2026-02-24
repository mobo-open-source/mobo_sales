import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/odoo_session_manager.dart';
import '../../services/session_service.dart';
import '../../home_scaffold.dart';

class TotpPage extends StatefulWidget {
  final String serverUrl;
  final String database;
  final String username;
  final String password;
  final String protocol;
  final bool isAddingAccount;

  const TotpPage({
    super.key,
    required this.serverUrl,
    required this.database,
    required this.username,
    required this.password,
    required this.protocol,
    this.isAddingAccount = false,
  });

  @override
  State<TotpPage> createState() => _TotpPageState();
}

class _TotpPageState extends State<TotpPage> {
  InAppWebViewController? _webController;
  final _totpController = TextEditingController();
  String? _error;
  bool _loading = true;
  bool _verifying = false;
  bool _isButtonEnabled = false;
  final _formKey = GlobalKey<FormState>();
  bool _credentialsInjected = false;
  bool _isSessionExtracted = false;
  bool _loginSuccess = false;

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
                  image: const AssetImage('assets/login_background.png'),
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

          Positioned.fill(
            child: Opacity(
              opacity: 0.0,
              child: InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(
                    '${widget.serverUrl}/web/login?db=${widget.database}',
                  ),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  cacheEnabled: false,
                  clearCache: true,
                  userAgent: OdooSessionManager.USER_AGENT,
                  useHybridComposition: true,
                  allowContentAccess: true,
                  allowFileAccess: true,
                  mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                  forceDark: ForceDark.AUTO,
                  disableDefaultErrorPage: true,
                ),
                onWebViewCreated: (controller) {
                  _webController = controller;
                },
                onReceivedServerTrustAuthRequest:
                    (controller, challenge) async {
                      return ServerTrustAuthResponse(
                        action: ServerTrustAuthResponseAction.PROCEED,
                      );
                    },
                onReceivedError: (controller, request, error) {
                  if (mounted) {
                    setState(() {
                      _loading = false;
                      _error = 'Failed to load: ${error.description}';
                    });
                  }
                },
                onLoadStop: (controller, url) async {
                  final urlStr = url?.toString() ?? '';

                  if (urlStr.contains('/web/database/selector') ||
                      urlStr.contains('/web/database/manager')) {
                    await _handleDatabaseSelector();
                    return;
                  }

                  if (urlStr.contains('/web/login') && !_credentialsInjected) {
                    await Future.delayed(const Duration(milliseconds: 800));
                    await _injectCredentials();
                    return;
                  }

                  if (urlStr.contains('/web/login/totp') ||
                      urlStr.contains('totp_token')) {
                    if (mounted) {
                      setState(() {
                        _loading = false;
                      });
                    }
                    await Future.delayed(const Duration(milliseconds: 600));
                    await _focusTotpField();
                    return;
                  }

                  if ((urlStr.contains('/web') ||
                          urlStr.contains('/odoo/discuss') ||
                          urlStr.contains('/odoo') ||
                          urlStr.contains('/odoo/apps') ||
                          urlStr.contains('/website')) &&
                      !urlStr.contains('/login') &&
                      !urlStr.contains('/totp')) {
                    final sessionInfo = await controller.evaluateJavascript(
                      source: """
                      (function () {
                        return odoo && odoo.session_info ? odoo.session_info : null;
                      })();
                      """,
                    );
                    final success = await _saveSessionData(
                      sessionInfo: sessionInfo,
                    );
                    if (success && mounted) {
                      setState(() {
                        _loginSuccess = true;
                        _loading = false;
                      });
                    }
                  }
                },
              ),
            ),
          ),

          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              bottom: false,
              child: IgnorePointer(
                ignoring: _loading,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(32),
                    child: Container(
                      height: 64,
                      width: 64,
                      alignment: Alignment.center,
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowLeft01,
                        color: _loading ? Colors.white54 : Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                _buildForm(),
              ],
            ),
          ),

          if (_loading)
            Container(
              color: Colors.white70,
              child: Center(
                child: LoadingAnimationWidget.fourRotatingDots(
                  color: Theme.of(context).colorScheme.primary,
                  size: 60,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const HugeIcon(
          icon: HugeIcons.strokeRoundedTwoFactorAccess,
          color: Colors.white,
          size: 48,
        ),
        const SizedBox(height: 24),
        Text(
          'Two-factor Authentication',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontSize: 25,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'To login, enter below the six-digit authentication code provided by your Authenticator app.',
          style: GoogleFonts.montserrat(
            fontSize: 14,
            color: Colors.white70,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        if (widget.serverUrl.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Server: ${widget.serverUrl}',
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: Colors.white60,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _totpController,
            keyboardType: TextInputType.number,
            enabled: !_loading && !_verifying,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'TOTP is required';
              }
              return null;
            },
            onChanged: (value) {
              setState(() {
                _isButtonEnabled = value.trim().isNotEmpty;
                _formKey.currentState?.validate();
                if (_error != null) _error = null;
              });
            },
            cursorColor: Colors.black,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Colors.black,
            ),
            decoration: InputDecoration(
              hintText: 'Enter TOTP Code',
              hintStyle: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Colors.black.withValues(alpha: 0.4),
              ),
              prefixIcon: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Transform.scale(
                    scale: 20 / 24.0,
                    child: const HugeIcon(
                      icon: HugeIcons.strokeRoundedSmsCode,
                      color: Colors.black54,
                      size: 24,
                    ),
                  ),
                ),
              ),
              prefixIconColor: WidgetStateColor.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? Colors.black26
                    : Colors.black54,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
              errorStyle: const TextStyle(color: Colors.white),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.red[900]!, width: 1.0),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 10),

          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: _error != null ? 48 : 0,
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const HugeIcon(
                          icon: HugeIcons.strokeRoundedAlertCircle,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: GoogleFonts.manrope(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
          ),

          const SizedBox(height: 20),

          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: (_verifying || !_isButtonEnabled) ? null : _submitTotp,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _verifying
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Authenticating',
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
                    )
                  : Text(
                      'Authenticate',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _injectCredentials() async {
    if (_credentialsInjected) return;

    final safeUser = jsonEncode(widget.username);
    final safePass = jsonEncode(widget.password);
    final safeDb = jsonEncode(widget.database);

    await _webController?.evaluateJavascript(
      source:
          """
      (function() {
        const login = document.querySelector('input[name="login"], input[type="email"]');
        const password = document.querySelector('input[name="password"]');
        const db = document.querySelector('input[name="db"], select[name="db"]');
        const form = document.querySelector('form[action*="/web/login"]');

        if (!login || !password || !form) return "missing";

        login.value = $safeUser;
        password.value = $safePass;
        if (db) {
          if (db.tagName === 'INPUT') db.value = $safeDb;
          else db.value = $safeDb;
        }

        const btn = form.querySelector('button[type="submit"]');
        if (btn) btn.click();
        else form.requestSubmit();

        return "submitted";
      })();
    """,
    );
    _credentialsInjected = true;
  }

  Future<void> _handleDatabaseSelector() async {
    await _webController?.evaluateJavascript(
      source:
          """
      const select = document.querySelector('select[name="db"]');
      if (select) {
        select.value = '${widget.database}';
        const btn = document.querySelector('button[type="submit"]');
        if (btn) btn.click();
      }
    """,
    );
  }

  Future<void> _focusTotpField() async {
    await _webController?.evaluateJavascript(
      source: """
      const input = document.querySelector('input[name="totp_token"], input[autocomplete="one-time-code"]');
      if (input) {
        input.focus();
        input.select();
      }
    """,
    );
  }

  Future<void> _submitTotp() async {
    if (_verifying || _webController == null) return;

    setState(() {
      _verifying = true;
      _error = null;
    });

    final totp = _totpController.text.trim();
    if (totp.length != 6 || !RegExp(r'^\d{6}$').hasMatch(totp)) {
      setState(() {
        _error = 'Please enter a valid 6-digit code';
        _verifying = false;
      });
      return;
    }

    try {
      await _webController!.evaluateJavascript(
        source:
            """
        (function() {
          let input = document.querySelector(
            'input[name="totp_token"], input[autocomplete="one-time-code"], input[type="text"][maxlength="6"], input[type="number"][maxlength="6"]'
          );
          if (!input) return "totp_input_not_found";
          
          
          input.focus();
          input.value = '$totp';
          ['input', 'change', 'keydown', 'keyup', 'keypress'].forEach(eventType => {
            input.dispatchEvent(new KeyboardEvent(eventType, {key: 'Enter', bubbles: true, cancelable: true}));
          });
          
          
          const trustCheckbox = document.querySelector('input[name="trust_device"], input[type="checkbox"], [name="trust"]');
          if (trustCheckbox && !trustCheckbox.checked) {
            trustCheckbox.checked = true;
            trustCheckbox.dispatchEvent(new Event('change', {bubbles: true}));
          }
          
          
          const form = input.closest('form') || document.querySelector('form[action*="/web/login"]');
          if (form) {
            const btn = form.querySelector('button[type="submit"], button.btn-primary, button[name="submit"], button.btn-block');
            if (btn) {
              btn.click();
            } else {
              form.submit();  
            }
            return "totp_submitted";
          }
          return "form_not_found";
        })();
      """,
      );

      await Future.delayed(const Duration(seconds: 2));

      for (int i = 0; i < 20; i++) {
        final isLoggedIn = await _webController!.evaluateJavascript(
          source: """
          (function() {
            const userMenu = document.querySelector('.o_user_menu, .oe_topbar_avatar, .o_apps_switcher, [data-menu="account"]');
            const webClient = document.querySelector('.o_web_client, .o_action_manager');
            const error = document.querySelector('.alert-danger, .o_error_dialog');
            if (userMenu || webClient) return true;
            if (error) return 'error';
            return false;
          })();
          """,
        );
        if (isLoggedIn == 'error') {
          setState(
            () => _error = "Invalid code or login failed. Please try again.",
          );
          return;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }

      await Future.delayed(const Duration(seconds: 4));

      final currentUrl = await _webController!.getUrl();
      final urlStr = currentUrl?.toString() ?? '';

      final cookies = await CookieManager.instance().getCookies(
        url: currentUrl!,
      );

      final sessionCookie = cookies.firstWhere(
        (c) => c.name == 'session_id',
        orElse: () => Cookie(name: 'session_id', value: ''),
      );

      final sessionInfo = await _webController!.evaluateJavascript(
        source: """
        (function () {
          return odoo && odoo.session_info ? odoo.session_info : null;
        })();
      """,
      );

      final domSuccess = await _webController!.evaluateJavascript(
        source: """
        (function() {
          const hasUserMenu = !!document.querySelector('.o_user_menu, .oe_topbar_avatar');
          const hasWebClient = !!document.querySelector('.o_web_client');
          return hasUserMenu || hasWebClient;
        })();
      """,
      );

      bool success = false;
      if (domSuccess == true ||
          urlStr.contains('/web?') ||
          urlStr.contains('/odoo/discuss?') ||
          urlStr.contains('/odoo') ||
          urlStr.contains('/odoo/apps?')) {
        success = await _saveSessionData(sessionInfo: sessionInfo);
      }

      if (success) {
        await _onLoginSuccess();
        return;
      }

      if (!success) {
        final isSuccess =
            sessionCookie.value.isNotEmpty &&
            sessionCookie.value.length > 20 &&
            ((urlStr.contains('/web') ||
                    (urlStr.contains('/odoo/discuss')) ||
                    (urlStr.contains('/odoo')) ||
                    (urlStr.contains('/odoo/apps'))) &&
                !urlStr.contains('/login') &&
                !urlStr.contains('/totp'));

        if (!isSuccess) {
          if (mounted) {
            setState(() {
              _error = 'Invalid code or login failed. Please try again.';
              _verifying = false;
            });
          }
          return;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Authentication failed. Please try again.';
          _verifying = false;
        });
      }
    } finally {
      if (mounted && !_loginSuccess) {
        setState(() {
          _verifying = false;
        });
      }
    }
  }

  Future<void> _onLoginSuccess() async {
    if (!mounted) return;

    setState(() {
      _loginSuccess = true;
      _verifying = true;
    });

    try {
      final session = await OdooSessionManager.getCurrentSession();
      if (!mounted) return;

      if (session != null) {
        final sessionService = Provider.of<SessionService>(
          context,
          listen: false,
        );

        if (widget.isAddingAccount) {
          Navigator.pop(context, true);
          return;
        }

        await sessionService.switchToAccount(session);

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScaffold()),
          (route) => false,
        );
      } else {
        if (widget.isAddingAccount) {
          Navigator.pop(context, true);
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const HomeScaffold()),
            (route) => false,
          );
        }
      }
    } catch (_) {
      if (!mounted) return;

      if (widget.isAddingAccount) {
        Navigator.pop(context, true);
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScaffold()),
          (route) => false,
        );
      }
    }
  }

  Future<bool> _saveSessionData({Map<String, dynamic>? sessionInfo}) async {
    if (_isSessionExtracted) return true;

    try {
      final currentUrl = await _webController?.getUrl();
      final cookies = await CookieManager.instance().getCookies(
        url: currentUrl ?? WebUri(widget.serverUrl),
      );

      final sessionCookie = cookies.firstWhere(
        (cookie) => cookie.name == 'session_id',
        orElse: () => Cookie(name: '', value: ''),
      );

      if (sessionCookie.value.isNotEmpty) {
        if (!mounted) return false;
        final authService = AuthService();
        final success = await authService.loginWithSessionId(
          serverUrl: widget.serverUrl,
          database: widget.database,
          userLogin: widget.username.trim(),
          password: widget.password.trim(),
          sessionId: sessionCookie.value,
          sessionInfo: sessionInfo,
        );

        if (success) {
          _isSessionExtracted = true;
          return true;
        } else {
          if (mounted && !_verifying) {
            setState(() {
              _error = 'Invalid code or login failed. Please try again.';
            });
          }
          return false;
        }
      } else {
        if (mounted && !_verifying) {
          setState(() {
            _error = 'Invalid code or login failed. Please try again.';
          });
        }
        return false;
      }
    } catch (e) {
      if (mounted && !_verifying) {
        setState(() {
          _error = 'Invalid code or login failed. Please try again.';
        });
      }
      return false;
    }
  }
}
