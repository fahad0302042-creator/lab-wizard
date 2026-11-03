import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Motion rules for the whole app, in one place so timing stays consistent and
/// "reduced motion" is honoured everywhere rather than screen by screen.
abstract final class LabMotion {
  /// Springs used for anything that settles into place.
  static const settle = SpringDescription(
    mass: 1,
    stiffness: 180,
    damping: 18,
  );

  static const quick = Duration(milliseconds: 220);
  static const standard = Duration(milliseconds: 320);
  static const listStagger = Duration(milliseconds: 40);

  /// The liquid surface settle. Long enough to read as liquid, short enough
  /// that logging five things in a row doesn't feel slow.
  static const wave = Duration(milliseconds: 460);

  /// How long the undo bar stays available.
  static const undoWindow = Duration(seconds: 5);

  /// True when animation should be skipped entirely — either the user turned it
  /// on in settings, or Android's own "remove animations" is set.
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// Durations collapse to zero so callers can stay declarative.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;

  static Curve get enterCurve => Curves.easeOutCubic;
}

/// Fades and lifts a row on first paint, offset by [index] so a shelf arrives
/// like things being put down rather than all at once.
///
/// Skipped entirely under reduced motion, and only runs once per widget so
/// scrolling back to a row doesn't replay it.
class ShelfRowIn extends StatefulWidget {
  const ShelfRowIn({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  @override
  State<ShelfRowIn> createState() => _ShelfRowInState();
}

class _ShelfRowInState extends State<ShelfRowIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: LabMotion.standard,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: LabMotion.enterCurve,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (LabMotion.reduced(context)) {
        _controller.value = 1;
        return;
      }
      // Cap the stagger so a long shelf doesn't take forever to arrive.
      final delay = math.min(widget.index, 8) * 40;
      Future<void>.delayed(Duration(milliseconds: delay), () {
        if (mounted) _controller.forward();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - _curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Counts a number up or down instead of snapping.
///
/// Used for quantities and summary figures. Tabular figures in the theme keep
/// the text from reflowing while it runs.
class CountUp extends StatelessWidget {
  const CountUp({
    required this.value,
    required this.builder,
    this.duration = const Duration(milliseconds: 260),
    super.key,
  });

  final double value;
  final Widget Function(BuildContext context, double value) builder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (LabMotion.reduced(context)) return builder(context, value);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: duration,
      curve: Curves.easeOut,
      builder: (context, animated, _) => builder(context, animated),
    );
  }
}
