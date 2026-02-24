import 'package:flutter/material.dart';

/// A utility widget for building responsive UI that adapts to mobile, tablet, and desktop screen sizes.
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 768;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= 768 &&
      MediaQuery.of(context).size.width < 1200;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1200;

  static int getGridColumns(BuildContext context) {
    if (isDesktop(context) || (isTablet(context))) return 4;
    return 2;
  }

  static double getCardAspectRatio(BuildContext context) {
    if (isDesktop(context)) return 1.4;
    if (isTablet(context)) return 1.3;
    return 1.15;
  }

  static EdgeInsets getScreenPadding(BuildContext context) {
    if (isDesktop(context)) return const EdgeInsets.all(24);
    if (isTablet(context)) return const EdgeInsets.all(20);
    return const EdgeInsets.all(16);
  }

  static double getChartHeight(BuildContext context) {
    if (isDesktop(context)) return 300;
    if (isTablet(context)) return 250;
    return 200;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    if (size.width >= 1200) {
      return desktop ?? tablet ?? mobile;
    } else if (size.width >= 768) {
      return tablet ?? mobile;
    } else {
      return mobile;
    }
  }
}

/// A GridView that automatically adjusts its column count based on the available screen width.
class ResponsiveGridView extends StatelessWidget {
  final List<Widget> children;
  final double? childAspectRatio;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  const ResponsiveGridView({
    super.key,
    required this.children,
    this.childAspectRatio,
    this.mainAxisSpacing = 16,
    this.crossAxisSpacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    final columns = ResponsiveLayout.getGridColumns(context);
    final aspectRatio =
        childAspectRatio ?? ResponsiveLayout.getCardAspectRatio(context);

    return GridView.count(
      crossAxisCount: columns,
      childAspectRatio: aspectRatio,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: children,
    );
  }
}

class ResponsiveRow extends StatelessWidget {
  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final bool forceColumn;

  const ResponsiveRow({
    super.key,
    required this.children,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.forceColumn = false,
  });

  @override
  Widget build(BuildContext context) {
    if (forceColumn || ResponsiveLayout.isMobile(context)) {
      return Column(
        mainAxisAlignment: mainAxisAlignment,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children
            .map(
              (child) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: child,
              ),
            )
            .toList(),
      );
    }

    return Row(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      children: children
          .map(
            (child) => Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: child,
              ),
            ),
          )
          .toList(),
    );
  }
}

/// A container that applies standard responsive padding and max-width constraints.
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final double? maxWidth;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.padding,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final screenPadding = padding ?? ResponsiveLayout.getScreenPadding(context);

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
      padding: screenPadding,
      child: child,
    );
  }
}

class ResponsiveCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final bool isDark;

  const ResponsiveCard({
    super.key,
    required this.child,
    this.padding,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cardPadding = padding ?? const EdgeInsets.all(16);

    return Container(
      padding: cardPadding,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          width: 1,
        ),
        boxShadow: ResponsiveLayout.isDesktop(context)
            ? [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

class ResponsiveText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const ResponsiveText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? const TextStyle();
    final scaleFactor = ResponsiveLayout.isDesktop(context)
        ? 1.1
        : ResponsiveLayout.isTablet(context)
        ? 1.05
        : 1.0;

    return Text(
      text,
      style: baseStyle.copyWith(
        fontSize: (baseStyle.fontSize ?? 14) * scaleFactor,
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
