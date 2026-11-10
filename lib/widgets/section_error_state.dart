import 'package:flutter/material.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import 'connection_status_widget.dart';

/// A failure inside one panel of a page that is otherwise fine.
///
/// [ConnectionStatusWidget] fills the screen, which is right when there is
/// nothing to show at all. It is wrong when the record is already on screen
/// and only one section failed to load: replacing the whole page would throw
/// away the record the user came to look at.
///
/// Rendering that section as *empty* is wrong too: a quotation whose lines
/// never arrived would say "No order lines found." directly above its own
/// total. Failed and empty are different facts and have to read differently.
///
/// The wording comes from [ConnectionStatusWidget.errorInfoFor], so one dead
/// server reads the same inside a panel as it does filling the screen.
class SectionErrorState extends StatelessWidget {
  /// The raw failure. Mapped to wording, never shown as-is.
  final String? error;
  final VoidCallback onRetry;

  const SectionErrorState({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final info = ConnectionStatusWidget.errorInfoFor(error);

    // Scrollable, because this has to survive a message longer than the
    // space available. One did: an Odoo traceback rendered here and
    // overflowed the screen by 504 pixels. The wording is sanitised now, but
    // a layout that only works for short text is one long sentence, one small
    // screen or one large font setting away from the same stripe.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Red: MOBO_UI §5.14 puts "something went wrong" in red and an
            // empty list in grey, which is the distinction being drawn here.
            Icon(
              Icons.error_outline_rounded,
              size: 36,
              color: isDark ? Colors.red[300] : Colors.red[400],
            ),
            const SizedBox(height: 12),
            Text(
              info['title']!,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              info['message']!,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.primaryColor, width: 1.2),
                foregroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
