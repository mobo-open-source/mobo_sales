import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// The loading skeleton of the Profile Details screen: the same shapes, in the
/// same places, as the screen it stands in for — the round photo with the name
/// under it, the "Personal Information" heading, then a label and an input box
/// per field down to the address — so nothing jumps when the real content
/// arrives.
///
/// One shimmer wraps the whole column, so the highlight sweeps across it as a
/// single wave rather than pulsing block by block.
class ProfileDetailsShimmer extends StatelessWidget {
  const ProfileDetailsShimmer({super.key, this.fieldCount = 8});

  /// How many label-and-box rows to draw. The screen has eight on a server
  /// without `res.partner.mobile` and nine with it.
  final int fieldCount;

  /// Matches the photo's 120 plus its 3 dp border on each side.
  static const double _avatarSize = 126;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Shimmer.fromColors(
          baseColor: base,
          highlightColor: highlight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    const _Block(
                      width: _avatarSize,
                      height: _avatarSize,
                      shape: BoxShape.circle,
                    ),
                    const SizedBox(height: 12),
                    _Block(width: 140, height: 16, radius: 8),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _Block(width: 170, height: 20, radius: 8),
              const SizedBox(height: 20),
              for (var i = 0; i < fieldCount; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                _Block(width: 84 + (i % 3) * 18.0, height: 12, radius: 6),
                const SizedBox(height: 8),
                _Block(width: double.infinity, height: 56, radius: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A solid grey shape; Shimmer paints the sweep over it.
class _Block extends StatelessWidget {
  const _Block({
    required this.width,
    required this.height,
    this.radius = 0,
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
