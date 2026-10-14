import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Skeletons for the loads that fill part of a page or a whole read-only page:
/// the "Other Info" tabs, attachment and company lists, and the product sales
/// history. Each one draws the shapes of the content it stands in for, so
/// nothing jumps when the real content arrives, and each wraps a single
/// [Shimmer] so the highlight sweeps across it as one wave.
///
/// The list, form and detail skeletons live in `list_shimmer.dart`; the
/// profile's is `profile_details_shimmer.dart`.
class SkeletonPalette {
  const SkeletonPalette._(this.base, this.highlight, this.card, this.border);

  final Color base;
  final Color highlight;
  final Color card;
  final Color border;

  factory SkeletonPalette.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SkeletonPalette._(
      isDark ? Colors.grey[800]! : Colors.grey[300]!,
      isDark ? Colors.grey[700]! : Colors.grey[100]!,
      isDark ? Colors.grey[900]! : Colors.white,
      isDark ? Colors.grey[700]! : Colors.grey[200]!,
    );
  }
}

/// A solid shape; the enclosing [Shimmer] paints the sweep over it.
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.radius = 6,
    this.shape = BoxShape.rectangle,
  });

  final double width;
  final double height;
  final double radius;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: shape,
        borderRadius: shape == BoxShape.circle
            ? null
            : BorderRadius.circular(radius),
      ),
    );
  }
}

Widget _shimmer(BuildContext context, Widget child) {
  final palette = SkeletonPalette.of(context);
  return Shimmer.fromColors(
    baseColor: palette.base,
    highlightColor: palette.highlight,
    child: child,
  );
}

/// The "Other Info" tab of a quotation or invoice while its extra fields load:
/// a small heading and a bordered card of label / value rows per section.
class InfoSectionsSkeleton extends StatelessWidget {
  const InfoSectionsSkeleton({
    super.key,
    this.rowsPerSection = const [6, 2, 3, 5],
  });

  final List<int> rowsPerSection;

  @override
  Widget build(BuildContext context) {
    final palette = SkeletonPalette.of(context);
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: _shimmer(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var s = 0; s < rowsPerSection.length; s++) ...[
              if (s > 0) const SizedBox(height: 20),
              const SkeletonBlock(width: 90, height: 12),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: palette.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  children: [
                    for (var r = 0; r < rowsPerSection[s]; r++)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          border: r == rowsPerSection[s] - 1
                              ? null
                              : Border(
                                  bottom: BorderSide(color: palette.border),
                                ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: SkeletonBlock(
                                  width: 60 + (r % 3) * 14.0,
                                  height: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 3,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: SkeletonBlock(
                                  width: 90 + ((r + s) % 3) * 22.0,
                                  height: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rows of a rounded square with two lines beside it: attachments, companies,
/// anything list-like that loads inside a card or a sheet.
class RowsSkeleton extends StatelessWidget {
  const RowsSkeleton({
    super.key,
    this.count = 3,
    this.leadingSize = 40,
    this.circleLeading = false,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  final int count;
  final double leadingSize;
  final bool circleLeading;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => _shimmer(
    context,
    _rows(
      count: count,
      leadingSize: leadingSize,
      circleLeading: circleLeading,
      padding: padding,
    ),
  );
}

/// The rows themselves, without a [Shimmer] of their own, so a larger skeleton
/// can include them under its single sweep.
Widget _rows({
  required int count,
  required double leadingSize,
  bool circleLeading = false,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(vertical: 8),
}) {
  return Column(
    children: [
      for (var i = 0; i < count; i++)
        Padding(
          padding: padding,
          child: Row(
            children: [
              SkeletonBlock(
                width: leadingSize,
                height: leadingSize,
                radius: 10,
                shape: circleLeading ? BoxShape.circle : BoxShape.rectangle,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBlock(width: 150 + (i % 3) * 20.0, height: 14),
                    const SizedBox(height: 8),
                    SkeletonBlock(width: 90 + (i % 2) * 24.0, height: 11),
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// The product sales history while its orders load: the "Analytics Overview"
/// heading and its four tiles, the sales-trend card with its chart area, and
/// the recent-sales rows.
class SalesHistorySkeleton extends StatelessWidget {
  const SalesHistorySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = SkeletonPalette.of(context);

    Widget card({required Widget child, double padding = 16}) => Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: _shimmer(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBlock(width: 190, height: 20, radius: 8),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 16.0;
                final tileWidth = (constraints.maxWidth - spacing) / 2;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (var i = 0; i < 4; i++)
                      SizedBox(
                        width: tileWidth,
                        height: 120,
                        child: card(
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SkeletonBlock(width: 80, height: 20),
                              SizedBox(height: 10),
                              SkeletonBlock(width: 60, height: 12),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            card(
              padding: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SkeletonBlock(width: 110, height: 18),
                      SkeletonBlock(width: 120, height: 40, radius: 12),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 200,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < 6; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          Expanded(
                            child: SkeletonBlock(
                              height: 60.0 + ((i * 37) % 5) * 28,
                              radius: 4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SkeletonBlock(width: 140, height: 18),
            const SizedBox(height: 16),
            _rows(count: 4, leadingSize: 44),
          ],
        ),
      ),
    );
  }
}
