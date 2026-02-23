import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'dart:math';

void showInvoiceSentConfettiDialog(BuildContext context, String invoiceName) {
  final confettiController = ConfettiController(
    duration: const Duration(seconds: 3),
  );

  try {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;
        final textTheme = theme.textTheme;
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;

        Future.delayed(const Duration(milliseconds: 300), () {
          try {
            confettiController.play();
          } catch (_) {}
        });

        return Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24.0,
            vertical: 40.0,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            child: Container(
              width: double.maxFinite,
              constraints: const BoxConstraints(
                maxWidth: 340.0,
                minHeight: 300.0,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(24.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24.0),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            isDark
                                ? Colors.white.withOpacity(0.02)
                                : colorScheme.primary.withOpacity(0.02),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      height: 300,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24.0),
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.topCenter,
                              child: ConfettiWidget(
                                confettiController: confettiController,
                                blastDirection: pi / 2,
                                blastDirectionality:
                                    BlastDirectionality.directional,
                                shouldLoop: false,
                                numberOfParticles: 5,

                                maxBlastForce: 8,
                                minBlastForce: 4,
                                emissionFrequency: 0.03,
                                gravity: 0.12,
                                particleDrag: 0.03,
                                colors: isDark
                                    ? [
                                        Colors.white.withOpacity(0.9),
                                        const Color(0xFFE5E5E7),
                                        const Color(0xFFD1D1D6),
                                        Colors.grey.shade200,
                                      ]
                                    : [
                                        colorScheme.primary.withOpacity(0.8),
                                        colorScheme.secondary.withOpacity(0.7),
                                        const Color(0xFFFFD700),
                                        const Color(0xFF00C896),
                                        colorScheme.tertiary.withOpacity(0.6),
                                      ],
                                createParticlePath: (size) {
                                  final path = Path();
                                  if (Random().nextBool()) {
                                    path.addRRect(
                                      RRect.fromRectAndRadius(
                                        Rect.fromLTWH(
                                          0,
                                          0,
                                          size.width * 0.6,
                                          size.height * 0.8,
                                        ),
                                        const Radius.circular(1),
                                      ),
                                    );
                                  } else {
                                    path.moveTo(size.width / 2, 0);
                                    path.lineTo(size.width, size.height / 2);
                                    path.lineTo(size.width / 2, size.height);
                                    path.lineTo(0, size.height / 2);
                                    path.close();
                                  }
                                  return path;
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(28.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Invoice Sent Successfully',
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white
                                : colorScheme.onSurface,
                            letterSpacing: -0.2,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16.0),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 12.0,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey.shade800.withOpacity(0.6)
                                : colorScheme.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12.0),
                            border: Border.all(
                              color: isDark
                                  ? Colors.grey.shade700
                                  : colorScheme.primary.withOpacity(0.1),
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            invoiceName,
                            style: textTheme.titleMedium?.copyWith(
                              color: isDark
                                  ? Colors.white
                                  : colorScheme.primary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 16.0),
                        Text(
                          'Your invoice has been successfully delivered to the recipient\'s email address.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? Colors.grey.shade400
                                : colorScheme.onSurface.withOpacity(0.65),
                            height: 1.4,
                            letterSpacing: 0.1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28.0),
                        SizedBox(
                          width: double.infinity,
                          height: 48.0,
                          child: ElevatedButton(
                            style:
                                ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: colorScheme.onPrimary,
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                ).copyWith(
                                  overlayColor: WidgetStateProperty.all(
                                    colorScheme.onPrimary.withOpacity(0.08),
                                  ),
                                ),
                            onPressed: () {
                              confettiController.stop();
                              Navigator.of(dialogContext).pop();
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  HugeIcons.strokeRoundedCheckmarkCircle02,
                                  size: 18.0,
                                  color: isDark
                                      ? Colors.white
                                      : colorScheme.onPrimary,
                                ),
                                const SizedBox(width: 8.0),
                                Text(
                                  'Perfect!',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15.0,
                                    letterSpacing: 0.2,
                                    color: isDark
                                        ? Colors.white
                                        : colorScheme.onPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) {
      confettiController.dispose();
    });
  } catch (e) {
    confettiController.dispose();
  }
}

void showQuotationSentConfettiDialog(
  BuildContext context,
  String quotationName,
) {
  final confettiController = ConfettiController(
    duration: const Duration(seconds: 3),
  );

  try {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;
        final textTheme = theme.textTheme;
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;

        Future.delayed(const Duration(milliseconds: 300), () {
          try {
            confettiController.play();
          } catch (_) {}
        });

        return Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24.0,
            vertical: 40.0,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            child: Container(
              width: double.maxFinite,
              constraints: const BoxConstraints(
                maxWidth: 340.0,
                minHeight: 300.0,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(24.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24.0),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            isDark
                                ? Colors.white.withOpacity(0.02)
                                : colorScheme.primary.withOpacity(0.02),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      height: 300,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24.0),
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.topCenter,
                              child: ConfettiWidget(
                                confettiController: confettiController,
                                blastDirection: pi / 2,
                                blastDirectionality:
                                    BlastDirectionality.directional,
                                shouldLoop: false,
                                numberOfParticles: 5,
                                maxBlastForce: 8,
                                minBlastForce: 4,
                                emissionFrequency: 0.03,
                                gravity: 0.12,
                                particleDrag: 0.03,
                                colors: isDark
                                    ? [
                                        Colors.white.withOpacity(0.9),
                                        const Color(0xFFE5E5E7),
                                        const Color(0xFFD1D1D6),
                                        Colors.grey.shade200,
                                      ]
                                    : [
                                        colorScheme.primary.withOpacity(0.8),
                                        colorScheme.secondary.withOpacity(0.7),
                                        const Color(0xFFFFD700),
                                        const Color(0xFF00C896),
                                        colorScheme.tertiary.withOpacity(0.6),
                                      ],
                                createParticlePath: (size) {
                                  final path = Path();
                                  if (Random().nextBool()) {
                                    path.addRRect(
                                      RRect.fromRectAndRadius(
                                        Rect.fromLTWH(
                                          0,
                                          0,
                                          size.width * 0.6,
                                          size.height * 0.8,
                                        ),
                                        const Radius.circular(1),
                                      ),
                                    );
                                  } else {
                                    path.moveTo(size.width / 2, 0);
                                    path.lineTo(size.width, size.height / 2);
                                    path.lineTo(size.width / 2, size.height);
                                    path.lineTo(0, size.height / 2);
                                    path.close();
                                  }
                                  return path;
                                },
                              ),
                            ),
                            Positioned(
                              top: 20,
                              left: 0,
                              right: 0,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: ConfettiWidget(
                                  confettiController: confettiController,
                                  blastDirection: pi / 2,
                                  blastDirectionality:
                                      BlastDirectionality.directional,
                                  shouldLoop: false,
                                  numberOfParticles: 5,
                                  maxBlastForce: 6,
                                  minBlastForce: 3,
                                  emissionFrequency: 0.015,
                                  gravity: 0.1,
                                  particleDrag: 0.04,
                                  colors: isDark
                                      ? [
                                          Colors.white.withOpacity(0.4),
                                          Colors.grey.shade300.withOpacity(0.5),
                                        ]
                                      : [
                                          colorScheme.primary.withOpacity(0.3),
                                          colorScheme.secondary.withOpacity(
                                            0.4,
                                          ),
                                          const Color(
                                            0xFFFFD700,
                                          ).withOpacity(0.5),
                                        ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(28.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Quotation Sent Successfully',
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white
                                : colorScheme.onSurface,
                            letterSpacing: -0.2,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16.0),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 12.0,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey.shade800.withOpacity(0.6)
                                : colorScheme.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12.0),
                            border: Border.all(
                              color: isDark
                                  ? Colors.grey.shade700
                                  : colorScheme.primary.withOpacity(0.1),
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            quotationName,
                            style: textTheme.titleMedium?.copyWith(
                              color: isDark
                                  ? Colors.white
                                  : colorScheme.primary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 16.0),
                        Text(
                          'Your quotation has been successfully delivered to the recipient\'s email address.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? Colors.grey.shade400
                                : colorScheme.onSurface.withOpacity(0.65),
                            height: 1.4,
                            letterSpacing: 0.1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28.0),
                        SizedBox(
                          width: double.infinity,
                          height: 48.0,
                          child: ElevatedButton(
                            style:
                                ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: colorScheme.onPrimary,
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                ).copyWith(
                                  overlayColor: WidgetStateProperty.all(
                                    colorScheme.onPrimary.withOpacity(0.08),
                                  ),
                                ),
                            onPressed: () {
                              confettiController.stop();
                              Navigator.of(dialogContext).pop();
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  HugeIcons.strokeRoundedCheckmarkCircle02,
                                  size: 18.0,
                                  color: isDark
                                      ? Colors.white
                                      : colorScheme.onPrimary,
                                ),
                                const SizedBox(width: 8.0),
                                Text(
                                  'Perfect!',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15.0,
                                    letterSpacing: 0.2,
                                    color: isDark
                                        ? Colors.white
                                        : colorScheme.onPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) {
      confettiController.dispose();
    });
  } catch (e) {
    confettiController.dispose();
  }
}

Future<void> showInvoiceCreatedConfettiDialog(
  BuildContext context,
  String invoiceName,
) async {
  final confettiController = ConfettiController(
    duration: const Duration(seconds: 3),
  );

  try {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;
        final textTheme = theme.textTheme;
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;

        Future.delayed(const Duration(milliseconds: 300), () {
          try {
            confettiController.play();
          } catch (_) {}
        });

        return Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24.0,
            vertical: 40.0,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            child: Container(
              width: double.maxFinite,
              constraints: const BoxConstraints(
                maxWidth: 340.0,
                minHeight: 300.0,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(24.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24.0),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            isDark
                                ? Colors.white.withOpacity(0.02)
                                : colorScheme.primary.withOpacity(0.02),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      height: 300,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24.0),
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.topCenter,
                              child: ConfettiWidget(
                                confettiController: confettiController,
                                blastDirection: pi / 2,
                                blastDirectionality:
                                    BlastDirectionality.directional,
                                shouldLoop: false,
                                numberOfParticles: 5,
                                maxBlastForce: 8,
                                minBlastForce: 4,
                                emissionFrequency: 0.03,
                                gravity: 0.12,
                                particleDrag: 0.03,
                                colors: isDark
                                    ? [
                                        Colors.white.withOpacity(0.9),
                                        const Color(0xFFE5E5E7),
                                        const Color(0xFFD1D1D6),
                                        Colors.grey.shade200,
                                      ]
                                    : [
                                        colorScheme.primary.withOpacity(0.8),
                                        colorScheme.secondary.withOpacity(0.7),
                                        const Color(0xFFFFD700),
                                        const Color(0xFF00C896),
                                        colorScheme.tertiary.withOpacity(0.6),
                                      ],
                                createParticlePath: (size) {
                                  final path = Path();
                                  if (Random().nextBool()) {
                                    path.addRRect(
                                      RRect.fromRectAndRadius(
                                        Rect.fromLTWH(
                                          0,
                                          0,
                                          size.width * 0.6,
                                          size.height * 0.8,
                                        ),
                                        const Radius.circular(1),
                                      ),
                                    );
                                  } else {
                                    path.moveTo(size.width / 2, 0);
                                    path.lineTo(size.width, size.height / 2);
                                    path.lineTo(size.width / 2, size.height);
                                    path.lineTo(0, size.height / 2);
                                    path.close();
                                  }
                                  return path;
                                },
                              ),
                            ),
                            Positioned(
                              top: 20,
                              left: 0,
                              right: 0,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: ConfettiWidget(
                                  confettiController: confettiController,
                                  blastDirection: pi / 2,
                                  blastDirectionality:
                                      BlastDirectionality.directional,
                                  shouldLoop: false,
                                  numberOfParticles: 3,
                                  maxBlastForce: 6,
                                  minBlastForce: 3,
                                  emissionFrequency: 0.015,
                                  gravity: 0.1,
                                  particleDrag: 0.04,
                                  colors: isDark
                                      ? [
                                          Colors.white.withOpacity(0.4),
                                          Colors.grey.shade300.withOpacity(0.5),
                                        ]
                                      : [
                                          colorScheme.primary.withOpacity(0.3),
                                          colorScheme.secondary.withOpacity(
                                            0.4,
                                          ),
                                          const Color(
                                            0xFFFFD700,
                                          ).withOpacity(0.5),
                                        ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(28.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 72.0,
                          height: 72.0,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white : colorScheme.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: isDark
                                    ? Colors.white.withOpacity(.01)
                                    : colorScheme.primary.withOpacity(0.2),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Icon(
                            HugeIcons.strokeRoundedInvoice01,
                            color: isDark
                                ? Colors.black
                                : colorScheme.onPrimary,
                            size: 32.0,
                          ),
                        ),
                        const SizedBox(height: 24.0),
                        Text(
                          'Draft Invoice Created',
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white
                                : colorScheme.onSurface,
                            letterSpacing: -0.2,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16.0),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 12.0,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey.shade800.withOpacity(0.6)
                                : colorScheme.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12.0),
                            border: Border.all(
                              color: isDark
                                  ? Colors.grey.shade700
                                  : colorScheme.primary.withOpacity(0.1),
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            invoiceName,
                            style: textTheme.titleMedium?.copyWith(
                              color: isDark
                                  ? Colors.white
                                  : colorScheme.primary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 16.0),
                        Text(
                          'Your draft invoice has been created. You can review and confirm it in Odoo before sending to your customer.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? Colors.grey.shade400
                                : colorScheme.onSurface.withOpacity(0.65),
                            height: 1.4,
                            letterSpacing: 0.1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28.0),
                        SizedBox(
                          width: double.infinity,
                          height: 48.0,
                          child: ElevatedButton(
                            style:
                                ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: colorScheme.onPrimary,
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                ).copyWith(
                                  overlayColor: WidgetStateProperty.all(
                                    colorScheme.onPrimary.withOpacity(0.08),
                                  ),
                                ),
                            onPressed: () {
                              confettiController.stop();
                              Navigator.of(dialogContext).pop();
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  HugeIcons.strokeRoundedCheckmarkCircle02,
                                  size: 18.0,
                                  color: isDark
                                      ? Colors.white
                                      : colorScheme.onPrimary,
                                ),
                                const SizedBox(width: 8.0),
                                Text(
                                  'Perfect!',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15.0,
                                    letterSpacing: 0.2,
                                    color: isDark
                                        ? Colors.white
                                        : colorScheme.onPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) {
      confettiController.dispose();
    });
  } catch (e) {
    confettiController.dispose();
  }
}

Future<void> showQuotationCreatedConfettiDialog(
  BuildContext context,
  String quotationName,
) async {
  final confettiController = ConfettiController(
    duration: const Duration(seconds: 3),
  );

  try {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;
        final textTheme = theme.textTheme;
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;

        Future.delayed(const Duration(milliseconds: 300), () {
          try {
            confettiController.play();
          } catch (_) {}
        });

        return Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24.0,
            vertical: 40.0,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            child: Container(
              width: double.maxFinite,
              constraints: const BoxConstraints(
                maxWidth: 340.0,
                minHeight: 300.0,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(24.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24.0),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            isDark
                                ? Colors.white.withOpacity(0.02)
                                : colorScheme.primary.withOpacity(0.02),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      height: 300,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24.0),
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.topCenter,
                              child: ConfettiWidget(
                                confettiController: confettiController,
                                blastDirection: pi / 2,
                                blastDirectionality:
                                    BlastDirectionality.directional,
                                shouldLoop: false,
                                numberOfParticles: 5,
                                maxBlastForce: 8,
                                minBlastForce: 4,
                                emissionFrequency: 0.03,
                                gravity: 0.12,
                                particleDrag: 0.03,
                                colors: isDark
                                    ? [
                                        Colors.white.withOpacity(0.9),
                                        const Color(0xFFE5E5E7),
                                        const Color(0xFFD1D1D6),
                                        Colors.grey.shade200,
                                      ]
                                    : [
                                        colorScheme.primary.withOpacity(0.8),
                                        colorScheme.secondary.withOpacity(0.7),
                                        const Color(0xFFFFD700),
                                        const Color(0xFF00C896),
                                        colorScheme.tertiary.withOpacity(0.6),
                                      ],
                                createParticlePath: (size) {
                                  final path = Path();
                                  if (Random().nextBool()) {
                                    path.addRRect(
                                      RRect.fromRectAndRadius(
                                        Rect.fromLTWH(
                                          0,
                                          0,
                                          size.width * 0.6,
                                          size.height * 0.8,
                                        ),
                                        const Radius.circular(1),
                                      ),
                                    );
                                  } else {
                                    path.moveTo(size.width / 2, 0);
                                    path.lineTo(size.width, size.height / 2);
                                    path.lineTo(size.width / 2, size.height);
                                    path.lineTo(0, size.height / 2);
                                    path.close();
                                  }
                                  return path;
                                },
                              ),
                            ),
                            Positioned(
                              top: 20,
                              left: 0,
                              right: 0,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: ConfettiWidget(
                                  confettiController: confettiController,
                                  blastDirection: pi / 2,
                                  blastDirectionality:
                                      BlastDirectionality.directional,
                                  shouldLoop: false,
                                  numberOfParticles: 3,
                                  maxBlastForce: 6,
                                  minBlastForce: 3,
                                  emissionFrequency: 0.015,
                                  gravity: 0.1,
                                  particleDrag: 0.04,
                                  colors: isDark
                                      ? [
                                          Colors.white.withOpacity(0.4),
                                          Colors.grey.shade300.withOpacity(0.5),
                                        ]
                                      : [
                                          colorScheme.primary.withOpacity(0.3),
                                          colorScheme.secondary.withOpacity(
                                            0.4,
                                          ),
                                          const Color(
                                            0xFFFFD700,
                                          ).withOpacity(0.5),
                                        ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(28.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Quotation Created Successfully',
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white
                                : colorScheme.onSurface,
                            letterSpacing: -0.2,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16.0),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 12.0,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey.shade800.withOpacity(0.6)
                                : colorScheme.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12.0),
                            border: Border.all(
                              color: isDark
                                  ? Colors.grey.shade700
                                  : colorScheme.primary.withOpacity(0.1),
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            quotationName,
                            style: textTheme.titleMedium?.copyWith(
                              color: isDark
                                  ? Colors.white
                                  : colorScheme.primary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 16.0),
                        Text(
                          'Your quotation has been successfully created and is ready to be sent to your customer.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? Colors.grey.shade400
                                : colorScheme.onSurface.withOpacity(0.65),
                            height: 1.4,
                            letterSpacing: 0.1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28.0),
                        SizedBox(
                          width: double.infinity,
                          height: 48.0,
                          child: ElevatedButton(
                            style:
                                ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: colorScheme.onPrimary,
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                ).copyWith(
                                  overlayColor: WidgetStateProperty.all(
                                    colorScheme.onPrimary.withOpacity(0.08),
                                  ),
                                ),
                            onPressed: () {
                              confettiController.stop();
                              Navigator.of(dialogContext).pop();
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  HugeIcons.strokeRoundedCheckmarkCircle02,
                                  size: 18.0,
                                  color: isDark
                                      ? Colors.white
                                      : colorScheme.onPrimary,
                                ),
                                const SizedBox(width: 8.0),
                                Text(
                                  'Perfect!',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15.0,
                                    letterSpacing: 0.2,
                                    color: isDark
                                        ? Colors.white
                                        : colorScheme.onPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) {
      confettiController.dispose();
    });
  } catch (e) {
    confettiController.dispose();
  }
}

Future<void> showCustomerCreatedConfettiDialog(
  BuildContext context,
  String customerName,
) async {
  final confettiController = ConfettiController(
    duration: const Duration(seconds: 3),
  );

  try {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;
        final textTheme = theme.textTheme;
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;

        Future.delayed(const Duration(milliseconds: 300), () {
          try {
            confettiController.play();
          } catch (_) {}
        });

        return Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24.0,
            vertical: 40.0,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            child: Container(
              width: double.maxFinite,
              constraints: const BoxConstraints(
                maxWidth: 340.0,
                minHeight: 300.0,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(24.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24.0),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            isDark
                                ? Colors.white.withOpacity(0.02)
                                : colorScheme.primary.withOpacity(0.02),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      height: 300,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24.0),
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.topCenter,
                              child: ConfettiWidget(
                                confettiController: confettiController,
                                blastDirection: pi / 2,
                                blastDirectionality:
                                    BlastDirectionality.directional,
                                shouldLoop: false,
                                numberOfParticles: 5,
                                maxBlastForce: 8,
                                minBlastForce: 4,
                                emissionFrequency: 0.03,
                                gravity: 0.12,
                                particleDrag: 0.03,
                                colors: isDark
                                    ? [
                                        Colors.white.withOpacity(0.9),
                                        const Color(0xFFE5E5E7),
                                        const Color(0xFFD1D1D6),
                                        Colors.grey.shade200,
                                      ]
                                    : [
                                        colorScheme.primary.withOpacity(0.8),
                                        colorScheme.secondary.withOpacity(0.7),
                                        const Color(0xFFFFD700),
                                        const Color(0xFF00C896),
                                        colorScheme.tertiary.withOpacity(0.6),
                                      ],
                                createParticlePath: (size) {
                                  final path = Path();
                                  if (Random().nextBool()) {
                                    path.addRRect(
                                      RRect.fromRectAndRadius(
                                        Rect.fromLTWH(
                                          0,
                                          0,
                                          size.width * 0.6,
                                          size.height * 0.8,
                                        ),
                                        const Radius.circular(1),
                                      ),
                                    );
                                  } else {
                                    path.moveTo(size.width / 2, 0);
                                    path.lineTo(size.width, size.height / 2);
                                    path.lineTo(size.width / 2, size.height);
                                    path.lineTo(0, size.height / 2);
                                    path.close();
                                  }
                                  return path;
                                },
                              ),
                            ),
                            Positioned(
                              top: 20,
                              left: 0,
                              right: 0,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: ConfettiWidget(
                                  confettiController: confettiController,
                                  blastDirection: pi / 2,
                                  blastDirectionality:
                                      BlastDirectionality.directional,
                                  shouldLoop: false,
                                  numberOfParticles: 3,
                                  maxBlastForce: 6,
                                  minBlastForce: 3,
                                  emissionFrequency: 0.015,
                                  gravity: 0.1,
                                  particleDrag: 0.04,
                                  colors: isDark
                                      ? [
                                          Colors.white.withOpacity(0.4),
                                          Colors.grey.shade300.withOpacity(0.5),
                                        ]
                                      : [
                                          colorScheme.primary.withOpacity(0.3),
                                          colorScheme.secondary.withOpacity(
                                            0.4,
                                          ),
                                          const Color(
                                            0xFFFFD700,
                                          ).withOpacity(0.5),
                                        ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(28.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Customer Created Successfully',
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white
                                : colorScheme.onSurface,
                            letterSpacing: -0.2,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16.0),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 12.0,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey.shade800.withOpacity(0.6)
                                : colorScheme.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12.0),
                            border: Border.all(
                              color: isDark
                                  ? Colors.grey.shade700
                                  : colorScheme.primary.withOpacity(0.1),
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            customerName,
                            style: textTheme.titleMedium?.copyWith(
                              color: isDark
                                  ? Colors.white
                                  : colorScheme.primary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 16.0),
                        Text(
                          'Your new customer has been successfully added to your database and is ready for business.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? Colors.grey.shade400
                                : colorScheme.onSurface.withOpacity(0.65),
                            height: 1.4,
                            letterSpacing: 0.1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28.0),
                        SizedBox(
                          width: double.infinity,
                          height: 48.0,
                          child: ElevatedButton(
                            style:
                                ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: colorScheme.onPrimary,
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                ).copyWith(
                                  overlayColor: WidgetStateProperty.all(
                                    colorScheme.onPrimary.withOpacity(0.08),
                                  ),
                                ),
                            onPressed: () {
                              confettiController.stop();
                              Navigator.of(dialogContext).pop();
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  HugeIcons.strokeRoundedCheckmarkCircle02,
                                  size: 18.0,
                                  color: isDark
                                      ? Colors.white
                                      : colorScheme.onPrimary,
                                ),
                                const SizedBox(width: 8.0),
                                Text(
                                  'Perfect!',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15.0,
                                    letterSpacing: 0.2,
                                    color: isDark
                                        ? Colors.white
                                        : colorScheme.onPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) {
      confettiController.dispose();
    });
  } catch (e) {
    confettiController.dispose();
  }
}

Future<void> showProductCreatedConfettiDialog(
  BuildContext context,
  String productName,
) async {
  final confettiController = ConfettiController(
    duration: const Duration(seconds: 3),
  );

  try {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;
        final textTheme = theme.textTheme;
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;

        Future.delayed(const Duration(milliseconds: 300), () {
          try {
            confettiController.play();
          } catch (_) {}
        });

        return Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24.0,
            vertical: 40.0,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            child: Container(
              width: double.maxFinite,
              constraints: const BoxConstraints(
                maxWidth: 340.0,
                minHeight: 300.0,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(24.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24.0),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            isDark
                                ? Colors.white.withOpacity(0.02)
                                : colorScheme.primary.withOpacity(0.02),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      height: 300,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24.0),
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.topCenter,
                              child: ConfettiWidget(
                                confettiController: confettiController,
                                blastDirection: pi / 2,
                                blastDirectionality:
                                    BlastDirectionality.directional,
                                shouldLoop: false,
                                numberOfParticles: 5,
                                maxBlastForce: 8,
                                minBlastForce: 4,
                                emissionFrequency: 0.03,
                                gravity: 0.12,
                                particleDrag: 0.03,
                                colors: isDark
                                    ? [
                                        Colors.white.withOpacity(0.9),
                                        const Color(0xFFE5E5E7),
                                        const Color(0xFFD1D1D6),
                                        Colors.grey.shade200,
                                      ]
                                    : [
                                        colorScheme.primary.withOpacity(0.8),
                                        colorScheme.secondary.withOpacity(0.7),
                                        const Color(0xFFFFD700),
                                        const Color(0xFF00C896),
                                        colorScheme.tertiary.withOpacity(0.6),
                                      ],
                                createParticlePath: (size) {
                                  final path = Path();
                                  if (Random().nextBool()) {
                                    path.addRRect(
                                      RRect.fromRectAndRadius(
                                        Rect.fromLTWH(
                                          0,
                                          0,
                                          size.width * 0.6,
                                          size.height * 0.8,
                                        ),
                                        const Radius.circular(1),
                                      ),
                                    );
                                  } else {
                                    path.moveTo(size.width / 2, 0);
                                    path.lineTo(size.width, size.height / 2);
                                    path.lineTo(size.width / 2, size.height);
                                    path.lineTo(0, size.height / 2);
                                    path.close();
                                  }
                                  return path;
                                },
                              ),
                            ),
                            Positioned(
                              top: 20,
                              left: 0,
                              right: 0,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: ConfettiWidget(
                                  confettiController: confettiController,
                                  blastDirection: pi / 2,
                                  blastDirectionality:
                                      BlastDirectionality.directional,
                                  shouldLoop: false,
                                  numberOfParticles: 3,
                                  maxBlastForce: 6,
                                  minBlastForce: 3,
                                  emissionFrequency: 0.015,
                                  gravity: 0.1,
                                  particleDrag: 0.04,
                                  colors: isDark
                                      ? [
                                          Colors.white.withOpacity(0.4),
                                          Colors.grey.shade300.withOpacity(0.5),
                                        ]
                                      : [
                                          colorScheme.primary.withOpacity(0.3),
                                          colorScheme.secondary.withOpacity(
                                            0.4,
                                          ),
                                          const Color(
                                            0xFFFFD700,
                                          ).withOpacity(0.5),
                                        ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(28.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Product Created Successfully',
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white
                                : colorScheme.onSurface,
                            letterSpacing: -0.2,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16.0),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 12.0,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey.shade800.withOpacity(0.6)
                                : colorScheme.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12.0),
                            border: Border.all(
                              color: isDark
                                  ? Colors.grey.shade700
                                  : colorScheme.primary.withOpacity(0.1),
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            productName,
                            style: textTheme.titleMedium?.copyWith(
                              color: isDark
                                  ? Colors.white
                                  : colorScheme.primary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 16.0),
                        Text(
                          'Your new product has been successfully added to your catalog and is ready for sale.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? Colors.grey.shade400
                                : colorScheme.onSurface.withOpacity(0.65),
                            height: 1.4,
                            letterSpacing: 0.1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28.0),
                        SizedBox(
                          width: double.infinity,
                          height: 48.0,
                          child: ElevatedButton(
                            style:
                                ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: colorScheme.onPrimary,
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                ).copyWith(
                                  overlayColor: WidgetStateProperty.all(
                                    colorScheme.onPrimary.withOpacity(0.08),
                                  ),
                                ),
                            onPressed: () {
                              confettiController.stop();
                              Navigator.of(dialogContext).pop();
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  HugeIcons.strokeRoundedCheckmarkCircle02,
                                  size: 18.0,
                                  color: isDark
                                      ? Colors.white
                                      : colorScheme.onPrimary,
                                ),
                                const SizedBox(width: 8.0),
                                Text(
                                  'Perfect!',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15.0,
                                    letterSpacing: 0.2,
                                    color: isDark
                                        ? Colors.white
                                        : colorScheme.onPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) {
      confettiController.dispose();
    });
  } catch (e) {
    confettiController.dispose();
  }
}
