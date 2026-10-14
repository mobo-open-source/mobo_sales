import 'package:flutter/material.dart';

import '../../design/mobo_tokens.dart';

/// The two buttons every dialog ends in: the secondary action on the left,
/// outlined, and the primary action on the right, filled with the brand
/// colour. Equal width, side by side.
///
/// A dialog with two buttons uses this and nothing else, so Cancel/Save,
/// No/Yes and Stay/Leave all look and sit the same way. Hand it to
/// `AlertDialog.actions` as its only child, or place it at the foot of a
/// custom dialog.
class MoboDialogButtons extends StatelessWidget {
  const MoboDialogButtons({
    super.key,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.primaryLabel,
    required this.onPrimary,
    this.isLoading = false,
  });

  /// Left, outlined: the way out — Cancel, No, Stay.
  final String secondaryLabel;
  final VoidCallback? onSecondary;

  /// Right, filled: the action the dialog is for — Save, Yes, Delete.
  final String primaryLabel;

  /// Null disables it, drawn at half strength.
  final VoidCallback? onPrimary;

  /// Swaps the primary label for a spinner and ignores taps on both buttons.
  final bool isLoading;

  static const double height = 48;
  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobo;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(MoboRadius.field),
    );
    final label = MoboType.button().copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w700,
    );

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: height,
            child: OutlinedButton(
              onPressed: isLoading ? null : onSecondary,
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.primary,
                disabledForegroundColor: colors.primary.withValues(alpha: 0.5),
                side: BorderSide(color: colors.primary, width: 1.5),
                shape: shape,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: label,
              ),
              child: Text(
                secondaryLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        const SizedBox(width: _gap),
        Expanded(
          child: SizedBox(
            height: height,
            child: ElevatedButton(
              onPressed: isLoading ? null : onPrimary,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: colors.primary.withValues(alpha: 0.5),
                disabledForegroundColor: Colors.white70,
                elevation: 0,
                shape: shape,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: label,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      primaryLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
