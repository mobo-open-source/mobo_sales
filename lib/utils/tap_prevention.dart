import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Utility for preventing rapid repeated taps (de-bouncing) on UI elements.
class TapPrevention {
  static final Map<String, DateTime> _lastTapTimes = {};
  static final Map<String, Timer> _cooldownTimers = {};

  static const Duration _defaultCooldown = Duration(milliseconds: 800);
  static const Duration _chartCooldown = Duration(milliseconds: 700);
  static const Duration _listItemCooldown = Duration(milliseconds: 600);
  static const Duration _buttonCooldown = Duration(milliseconds: 500);

  /// Checks if a tap is allowed based on the cooldown for a specific [key].
  static bool shouldAllowTap(String key, {Duration? cooldown}) {
    final now = DateTime.now();
    final lastTap = _lastTapTimes[key];
    final effectiveCooldown = cooldown ?? _defaultCooldown;

    if (lastTap == null || now.difference(lastTap) >= effectiveCooldown) {
      _lastTapTimes[key] = now;
      _resetCooldownTimer(key, effectiveCooldown);
      return true;
    }

    return false;
  }

  /// Executes a [callback] only if the cooldown for [key] has passed.
  static void executeTap(
    String key,
    VoidCallback callback, {
    Duration? cooldown,
  }) {
    if (shouldAllowTap(key, cooldown: cooldown)) {
      HapticFeedback.selectionClick();
      callback();
    }
  }

  static void executeNavigation(String key, VoidCallback callback) {
    executeTap(key, callback, cooldown: _defaultCooldown);
  }

  static void executeChartTap(String key, VoidCallback callback) {
    executeTap(key, callback, cooldown: _chartCooldown);
  }

  static void executeListItemTap(String key, VoidCallback callback) {
    executeTap(key, callback, cooldown: _listItemCooldown);
  }

  static void executeButtonTap(String key, VoidCallback callback) {
    executeTap(key, callback, cooldown: _buttonCooldown);
  }

  static void _resetCooldownTimer(String key, Duration cooldown) {
    _cooldownTimers[key]?.cancel();
    _cooldownTimers[key] = Timer(cooldown, () {
      _lastTapTimes.remove(key);
      _cooldownTimers.remove(key);
    });
  }

  static void clearAllCooldowns() {
    for (final timer in _cooldownTimers.values) {
      timer.cancel();
    }
    _lastTapTimes.clear();
    _cooldownTimers.clear();
  }

  static Duration? getRemainingCooldown(String key, {Duration? cooldown}) {
    final lastTap = _lastTapTimes[key];
    if (lastTap == null) return null;

    final effectiveCooldown = cooldown ?? _defaultCooldown;
    final elapsed = DateTime.now().difference(lastTap);
    final remaining = effectiveCooldown - elapsed;

    return remaining.isNegative ? null : remaining;
  }
}

/// A wrapper widget that applies tap prevention to its [child].
class TapPreventionWrapper extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String tapKey;
  final Duration? cooldown;
  final bool showVisualFeedback;
  final TapPreventionType type;

  const TapPreventionWrapper({
    super.key,
    required this.child,
    required this.tapKey,
    this.onTap,
    this.cooldown,
    this.showVisualFeedback = true,
    this.type = TapPreventionType.general,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              switch (type) {
                case TapPreventionType.navigation:
                  TapPrevention.executeNavigation(tapKey, onTap!);
                  break;
                case TapPreventionType.chart:
                  TapPrevention.executeChartTap(tapKey, onTap!);
                  break;
                case TapPreventionType.listItem:
                  TapPrevention.executeListItemTap(tapKey, onTap!);
                  break;
                case TapPreventionType.button:
                  TapPrevention.executeButtonTap(tapKey, onTap!);
                  break;
                case TapPreventionType.general:
                  TapPrevention.executeTap(tapKey, onTap!, cooldown: cooldown);
                  break;
              }
            },
      child: showVisualFeedback ? _TapFeedbackWidget(child: child) : child,
    );
  }
}

enum TapPreventionType { general, navigation, chart, listItem, button }

class _TapFeedbackWidget extends StatefulWidget {
  final Widget child;

  const _TapFeedbackWidget({required this.child});

  @override
  State<_TapFeedbackWidget> createState() => _TapFeedbackWidgetState();
}

class _TapFeedbackWidgetState extends State<_TapFeedbackWidget>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.96,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: widget.child,
          );
        },
      ),
    );
  }
}

mixin TapPreventionMixin<T extends StatefulWidget> on State<T> {
  void executeProtectedTap(
    String key,
    VoidCallback callback, {
    Duration? cooldown,
  }) {
    TapPrevention.executeTap(key, callback, cooldown: cooldown);
  }

  void executeProtectedNavigation(String key, VoidCallback callback) {
    TapPrevention.executeNavigation(key, callback);
  }

  void executeProtectedChartTap(String key, VoidCallback callback) {
    TapPrevention.executeChartTap(key, callback);
  }

  void executeProtectedListItemTap(String key, VoidCallback callback) {
    TapPrevention.executeListItemTap(key, callback);
  }

  bool shouldAllowTap(String key, {Duration? cooldown}) {
    return TapPrevention.shouldAllowTap(key, cooldown: cooldown);
  }
}
