import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The Mobo design tokens.
///
/// Every widget in `shared/widgets/mobo/` reads its colours, radii, shadows,
/// type and spacing from here, so none of them repeats a raw hex literal and
/// a change lands everywhere at once.
///
/// Colours resolve per theme through [MoboColors.of], and the brand colour
/// always comes from `Theme.of(context).primaryColor` rather than being
/// hard-coded, so an app that re-brands gets it for free.

/// Resolved colour set for the current theme.
///
/// Read it with `context.mobo` rather than constructing one.
class MoboColors {
  const MoboColors._({
    required this.primary,
    required this.primaryTint,
    required this.scaffold,
    required this.surface,
    required this.popupSurface,
    required this.inputFill,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.error,
    required this.searchIcon,
    required this.isDark,
  });

  /// Brand: selected states, focus borders, primary buttons.
  final Color primary;

  /// Selected rows, selected chips, tinted cards.
  final Color primaryTint;

  /// Page background.
  final Color scaffold;

  /// Cards, search field, panels.
  final Color surface;

  /// Overlay dropdown panels, which sit lifted off the page.
  final Color popupSurface;

  /// Closed field fill.
  final Color inputFill;

  /// Hairlines.
  final Color divider;

  /// Titles and values.
  final Color textPrimary;

  /// Labels, meta, hints.
  final Color textSecondary;

  /// Invalid borders and messages.
  final Color error;

  /// The search field's leading glyph, which sits lighter than
  /// [textSecondary] so it reads as decoration rather than as content.
  final Color searchIcon;

  final bool isDark;

  static MoboColors of(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;
    final isDark = theme.brightness == Brightness.dark;

    return isDark
        ? MoboColors._(
            primary: primary,
            primaryTint: primary.withValues(alpha: 0.18),
            scaffold: const Color(0xFF181A20),
            surface: Colors.grey[850]!,
            popupSurface: const Color(0xFF2C2C2E),
            inputFill: Colors.grey[850]!,
            divider: Colors.grey[800]!,
            textPrimary: Colors.white,
            textSecondary: Colors.grey[400]!,
            error: MoboStatusColors.red,
            searchIcon: Colors.white.withValues(alpha: 0.7),
            isDark: true,
          )
        : MoboColors._(
            primary: primary,
            primaryTint: const Color(0xFFFCE7EE),
            scaffold: const Color(0xFFF5F7FA),
            surface: Colors.white,
            popupSurface: Colors.white,
            inputFill: const Color(0xFFF2F4F6),
            divider: const Color(0xFFE0E0E0),
            textPrimary: const Color(0xFF101010),
            textSecondary: const Color(0xFF666666),
            error: MoboStatusColors.red,
            searchIcon: const Color(0xFF99A1AF),
            isDark: false,
          );
  }
}

extension MoboColorsContext on BuildContext {
  /// The resolved Mobo palette for this context's theme.
  MoboColors get mobo => MoboColors.of(this);
}

/// Semantic status colours — one per stage, with [grey] as the fallback for
/// a status this app does not recognise.
abstract final class MoboStatusColors {
  static const Color green = Color(0xFF00A63E);
  static const Color blue = Color(0xFF3B82F6);
  static const Color orange = Color(0xFFF97316);
  static const Color red = Color(0xFFEF4444);
  static const Color teal = Color(0xFF14B8A6);
  static const Color grey = Color(0xFF6B7280);
}

abstract final class MoboRadius {
  static const double button = 16;
  static const double card = 14;

  /// Inputs, overlay panels and fields all share one radius.
  static const double field = 12;
  static const double chip = 20;
  static const double pill = 999;
  static const double sheetTop = 25;
  static const double checkbox = 4;
}

/// Depth comes from these alone — every Material in the system stays at
/// `elevation: 0`.
abstract final class MoboShadows {
  /// List items and form cards.
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0D000000),
      offset: Offset(0, 6),
      blurRadius: 16,
      spreadRadius: 2,
    ),
  ];

  /// The standard list card in this app.
  static final List<BoxShadow> soft = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 10,
      offset: const Offset(6, 6),
    ),
  ];

  /// Pill and rounded search bars only.
  static const List<BoxShadow> search = [
    BoxShadow(
      color: Color(0x0A000000),
      offset: Offset(3, 11),
      blurRadius: 8.5,
      spreadRadius: -3,
    ),
  ];
}

/// Manrope throughout. Each getter takes its colour explicitly so a caller
/// never has to remember which token a given role uses.
abstract final class MoboType {
  static TextStyle title(Color color) => GoogleFonts.manrope(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: color,
  );

  static TextStyle h3(Color color) => GoogleFonts.manrope(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: color,
  );

  static TextStyle body(Color color) => GoogleFonts.manrope(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: color,
  );

  static TextStyle label(Color color) => GoogleFonts.manrope(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: color,
  );

  static TextStyle fieldValue(Color color) => GoogleFonts.manrope(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: color,
  );

  static TextStyle hint(Color color, {double size = 14}) => GoogleFonts.manrope(
    fontSize: size,
    fontWeight: FontWeight.w400,
    color: color,
  );

  static TextStyle chip(Color color) => GoogleFonts.manrope(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: color,
  );

  static TextStyle meta(Color color) => GoogleFonts.manrope(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: color,
  );

  static TextStyle badge(Color color, {FontWeight weight = FontWeight.w600}) =>
      GoogleFonts.manrope(fontSize: 11, fontWeight: weight, color: color);

  /// Button labels. The colour comes from the button's own foreground, so this
  /// deliberately sets none — passing one here would fight the disabled state.
  static TextStyle button() =>
      GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600);
}

abstract final class MoboSpacing {
  static const double page = 20;

  /// Between list cards.
  static const double listGap = 10;

  /// Between form fields.
  static const double fieldGap = 16;

  static const double fieldMinHeight = 48;
  static const double iconButton = 48;

  /// Every button in the app is this tall, so a Cancel/Save pair sits level.
  static const double buttonHeight = 50;

  /// No tap target in the system goes below this.
  static const double minTouchTarget = 36;
}
