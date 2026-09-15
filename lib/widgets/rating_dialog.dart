import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/review_service.dart';

/// "How's your experience?" — the rate-us prompt.
///
/// Five tap-to-set stars, a Submit button and "Skip for Now". 4-5 stars
/// triggers [onGoodReview] (the store sheet); 1-3 triggers [onBadReview]
/// (a support email), so a complaint does not land on the public listing.
class CustomRatingDialog extends StatefulWidget {
  final Function(double, String) onGoodReview;
  final Function(double, String) onBadReview;

  const CustomRatingDialog({
    Key? key,
    required this.onGoodReview,
    required this.onBadReview,
  }) : super(key: key);

  @override
  _CustomRatingDialogState createState() => _CustomRatingDialogState();

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => CustomRatingDialog(
        onGoodReview: (rating, comment) async {
          Navigator.pop(context);
          // Set "Never Ask Again" so they aren't prompted again in 30 days
          await ReviewService().neverAskAgain();
          ReviewService().forceRequestReview();
        },
        onBadReview: (rating, comment) async {
          if (context.mounted) Navigator.pop(context);
          // Trigger 6-month cooldown instead of permanent disable
          await ReviewService().markFeedbackGiven();
          ReviewService().sendEmailFeedback(rating, comment);
        },
      ),
    );
  }
}

const int _kStarCount = 5;
const double _kStarGap = 6;
const double _kStarSize = 44;

class _CustomRatingDialogState extends State<CustomRatingDialog> {
  /// Three, as the design opens: a prefilled five reads as the app asking for
  /// five rather than asking a question.
  int _rating = 3;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final titleColor = isDark ? Colors.white : Colors.black;
    final subtitleColor = isDark ? Colors.white70 : const Color(0xFF8A8A8A);
    final buttonColor = isDark ? Colors.white : Colors.black;
    final buttonTextColor = isDark ? Colors.black : Colors.white;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'How’s your experience ?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Your feedback helps us improve\nand serve you better.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w400,
                fontSize: 14,
                height: 1.4,
                color: subtitleColor,
              ),
            ),
            const SizedBox(height: 32),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_kStarCount, (index) {
                  final filled = index < _rating;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _rating = index + 1),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: _kStarGap),
                      child: SvgPicture.asset(
                        filled
                            ? 'assets/icons/star_filled.svg'
                            : 'assets/icons/star_outlined.svg',
                        width: _kStarSize,
                        height: _kStarSize,
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: buttonColor,
                  foregroundColor: buttonTextColor,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _submit,
                child: const Text(
                  'Submit',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: _skip,
              child: Text(
                'Skip for Now',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: titleColor.withValues(alpha: 0.5),
                  decoration: TextDecoration.underline,
                  decorationColor: titleColor.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final rating = _rating.toDouble();
    if (rating >= 4) {
      widget.onGoodReview(rating, '');
    } else {
      widget.onBadReview(rating, '');
    }
  }

  void _skip() => Navigator.of(context).pop();
}
