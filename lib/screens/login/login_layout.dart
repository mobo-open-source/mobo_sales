import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'dart:async';

class LoginLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? backButton;

  const LoginLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.backButton,
  });

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
                                  _buildSignInHeader(),
                                  const SizedBox(height: 40),

                                  Theme(
                                    data: Theme.of(context).copyWith(
                                      inputDecorationTheme: Theme.of(context)
                                          .inputDecorationTheme
                                          .copyWith(
                                            errorStyle: const TextStyle(
                                              color: Colors.white,
                                            ),
                                            errorBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                color: Colors.red[900]!,
                                                width: 1.0,
                                              ),
                                            ),
                                            focusedErrorBorder:
                                                OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: const BorderSide(
                                                    color: Colors.white,
                                                    width: 1.5,
                                                  ),
                                                ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide.none,
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide.none,
                                            ),
                                          ),
                                    ),
                                    child: child,
                                  ),
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

          if (backButton != null) backButton!,
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
          width: 28,
          height: 28,
          fit: BoxFit.fitWidth,
        ),
        const SizedBox(width: 12),
        Text(
          'mobo sales',
          style: const TextStyle(
            fontFamily: 'YaroRg',
            color: Colors.white,
            fontSize: 28,
          ),
        ),
      ],
    );
  }

  Widget _buildSignInHeader() {
    return Column(
      children: [
        Text(
          title,
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontSize: 22,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),

        Text(
          subtitle,
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

class LoginTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final String? Function(String?)? validator;
  final Widget? suffixIcon;
  final bool hasError;
  final ValueChanged<String>? onChanged;
  final AutovalidateMode? autovalidateMode;
  final FocusNode? focusNode;
  final bool autofocus;
  final Iterable<String>? autofillHints;

  const LoginTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.validator,
    this.suffixIcon,
    this.hasError = false,
    this.onChanged,
    this.autovalidateMode,
    this.focusNode,
    this.autofocus = false,
    this.autofillHints,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      cursorColor: Colors.black,
      style: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: Colors.black,
      ),
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      keyboardType: keyboardType,
      obscureText: obscureText,
      enabled: enabled,
      validator: validator,
      autovalidateMode: autovalidateMode,
      onChanged: onChanged,
      autofillHints: autofillHints,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Colors.black.withOpacity(.4),
        ),
        prefixIcon: Icon(prefixIcon, size: 20),
        prefixIconColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? Colors.black26
              : Colors.black54,
        ),
        suffixIcon: hasError
            ? Icon(Icons.error_outline, color: Colors.red, size: 20)
            : suffixIcon,
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
      ),
    );
  }
}

class LoginDropdownField extends StatefulWidget {
  final String hint;
  final String? value;
  final List<String> items;
  final void Function(String?)? onChanged;
  final String? Function(String?)? validator;
  final bool hasError;
  final AutovalidateMode? autovalidateMode;

  const LoginDropdownField({
    super.key,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.validator,
    this.hasError = false,
    this.autovalidateMode,
  });

  @override
  State<LoginDropdownField> createState() => _LoginDropdownFieldState();
}

class _LoginDropdownFieldState extends State<LoginDropdownField> {
  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _handleMenuOpen(BuildContext context) async {
    FocusScope.of(context).unfocus();

    await Future.delayed(const Duration(milliseconds: 250));

    if (!mounted) return;
    _openDropdownMenu(context);
  }

  Future<void> _openDropdownMenu(BuildContext context) async {
    final uniqueItems = widget.items.toSet().toList();

    final RenderBox? button = context.findRenderObject() as RenderBox?;
    if (button == null) return;

    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero, ancestor: overlay);
    final Size size = button.size;

    final double spaceBelow = overlay.size.height - (offset.dy + size.height);
    final double spaceAbove = offset.dy;

    const double maxMenuHeight = 240.0;
    final double menuHeight = (uniqueItems.length * 48.0).clamp(
      0.0,
      maxMenuHeight,
    );

    final bool openUpwards = spaceBelow < menuHeight && spaceAbove > spaceBelow;

    final selected = await showMenu<String>(
      context: context,
      color: Colors.white,
      position: RelativeRect.fromRect(
        openUpwards
            ? Rect.fromLTWH(offset.dx, offset.dy - menuHeight, size.width, 0)
            : Rect.fromLTWH(
                offset.dx,
                offset.dy + size.height - 1,
                size.width,
                0,
              ),
        Offset.zero & overlay.size,
      ),
      constraints: BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: maxMenuHeight,
      ),
      items: uniqueItems.map((item) {
        return PopupMenuItem<String>(
          value: item,
          height: 48,
          child: Text(
            item,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Colors.black,
            ),
          ),
        );
      }).toList(),
    );

    if (selected != null && mounted) {
      widget.onChanged?.call(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uniqueItems = widget.items.toSet().toList();
    final safeValue = uniqueItems.contains(widget.value) ? widget.value : null;
    final bool isEnabled = widget.onChanged != null;

    return FormField<String>(
      key: ValueKey(safeValue),
      initialValue: safeValue,
      validator: widget.validator,
      autovalidateMode: widget.autovalidateMode,
      builder: (field) {
        final effectiveValue = safeValue;
        final showErrorIcon =
            widget.hasError &&
            (effectiveValue == null || effectiveValue.isEmpty);

        return Builder(
          builder: (rowCtx) {
            return InkWell(
              onTap: isEnabled ? () => _handleMenuOpen(rowCtx) : null,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                isEmpty: (effectiveValue == null || effectiveValue.isEmpty),
                decoration: InputDecoration(
                  enabled: isEnabled,
                  prefixIcon: Icon(HugeIcons.strokeRoundedDatabase, size: 20),
                  prefixIconColor: WidgetStateColor.resolveWith(
                    (states) => states.contains(WidgetState.disabled)
                        ? Colors.black26
                        : Colors.black54,
                  ),
                  suffixIcon: showErrorIcon
                      ? Icon(
                          HugeIcons.strokeRoundedAlertCircle,
                          color: Colors.red[900],
                          size: 20,
                        )
                      : Icon(
                          Icons.keyboard_arrow_down,
                          size: 20,
                          color: isEnabled ? Colors.black54 : Colors.black26,
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
                  errorText: field.errorText,
                  errorStyle: const TextStyle(color: Colors.white),
                ),
                child: Text(
                  effectiveValue ?? widget.hint,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: (effectiveValue == null || effectiveValue.isEmpty)
                        ? Colors.black.withOpacity(.4)
                        : Colors.black,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class LoginErrorDisplay extends StatelessWidget {
  final String? error;

  const LoginErrorDisplay({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: error != null
            ? Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
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
                        error!,
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
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class LoginUrlTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final bool enabled;
  final String? Function(String?)? validator;
  final bool hasError;
  final ValueChanged<String>? onChanged;
  final AutovalidateMode? autovalidateMode;
  final FocusNode? focusNode;
  final bool autofocus;
  final String selectedProtocol;
  final ValueChanged<String>? onProtocolChanged;
  final bool isLoading;

  const LoginUrlTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    this.enabled = true,
    this.validator,
    this.hasError = false,
    this.onChanged,
    this.autovalidateMode,
    this.focusNode,
    this.autofocus = false,
    this.selectedProtocol = 'https://',
    this.onProtocolChanged,
    this.isLoading = false,
  });

  @override
  State<LoginUrlTextField> createState() => _LoginUrlTextFieldState();
}

class _LoginUrlTextFieldState extends State<LoginUrlTextField> {
  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _handleProtocolMenuOpen(BuildContext context) async {
    FocusScope.of(context).unfocus();

    await Future.delayed(const Duration(milliseconds: 250));

    if (!mounted) return;
    _openProtocolMenu(context);
  }

  Future<void> _openProtocolMenu(BuildContext context) async {
    final RenderBox? button = context.findRenderObject() as RenderBox?;
    if (button == null) return;

    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero, ancestor: overlay);
    final Size size = button.size;

    final selected = await showMenu<String>(
      context: context,
      color: Colors.white,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(offset.dx, offset.dy + size.height, size.width, 0),
        Offset.zero & overlay.size,
      ),
      constraints: BoxConstraints(minWidth: size.width, maxWidth: size.width),
      items: ['http://', 'https://']
          .map(
            (p) => PopupMenuItem<String>(
              value: p,
              child: Text(
                p,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
            ),
          )
          .toList(),
    );

    if (selected != null && mounted) {
      widget.onProtocolChanged?.call(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      cursorColor: Colors.black,
      style: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: Colors.black,
      ),
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      validator: widget.validator,
      autovalidateMode: widget.autovalidateMode,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Colors.black.withOpacity(.4),
        ),
        prefixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Icon(
                widget.prefixIcon,
                size: 20,
                color: widget.enabled ? Colors.black54 : Colors.black26,
              ),
            ),

            Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: Colors.black.withOpacity(0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Builder(
                builder: (ctx) {
                  return InkWell(
                    onTap: () => _handleProtocolMenuOpen(ctx),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.selectedProtocol,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: widget.enabled
                                  ? Colors.black
                                  : Colors.black26,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.keyboard_arrow_down,
                            size: 16,
                            color: widget.enabled
                                ? Colors.black54
                                : Colors.black26,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: widget.hasError
            ? Icon(Icons.error_outline, color: Colors.red, size: 20)
            : widget.isLoading
            ? Padding(
                padding: const EdgeInsets.all(12.0),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black54),
                  ),
                ),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.only(
          left: 0,
          right: 20,
          top: 16,
          bottom: 16,
        ),
      ),
    );
  }
}

class LoginButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget? loadingWidget;

  const LoginButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.loadingWidget,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
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
        child: isLoading && loadingWidget != null
            ? loadingWidget!
            : Text(
                text,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
