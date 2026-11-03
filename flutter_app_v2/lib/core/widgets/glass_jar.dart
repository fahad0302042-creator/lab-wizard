import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme/app_theme.dart';
import 'jar_metrics.dart';

/// The store-room jar: a small vial whose liquid level *is* the stock bar.
///
/// The jar answers "how much is left" and the colour answers "does it need
/// attention". They are independent on purpose — see [jarMetrics].
class GlassJar extends StatefulWidget {
  const GlassJar({
    required this.metrics,
    this.width = 34,
    this.height = 42,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final JarMetrics metrics;
  final double width;
  final double height;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  State<GlassJar> createState() => _GlassJarState();
}

class _GlassJarState extends State<GlassJar> with TickerProviderStateMixin {
  /// Drives the surface. Runs 0→1 whenever the level changes; the painter turns
  /// that into a damped wave so the liquid sloshes and settles.
  late final AnimationController _surface = AnimationController(
    vsync: this,
    duration: LabMotion.wave,
    value: 1,
  );

  /// A single pulse when a jar becomes empty. Not a shake, not a loop.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );

  late double _shownFill = widget.metrics.fill;

  @override
  void didUpdateWidget(covariant GlassJar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.metrics.fill;
    if ((next - _shownFill).abs() > .001) {
      _shownFill = next;
      if (!LabMotion.reduced(context)) {
        _surface
          ..reset()
          ..forward();
      }
    }

    final becameEmpty =
        widget.metrics.isEmpty && !oldWidget.metrics.isEmpty;
    if (becameEmpty && !LabMotion.reduced(context)) {
      _pulse.reverse().then((_) {
        if (mounted) _pulse.forward();
      });
    }
  }

  @override
  void dispose() {
    _surface.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final color = lab.forState(widget.metrics.signal);

    return Semantics(
      label: widget.semanticLabel,
      button: widget.onTap != null,
      excludeSemantics: widget.semanticLabel != null,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: Listenable.merge([_surface, _pulse]),
          builder: (context, _) {
            // Decay the wave as the settle progresses. sin(π·t) peaks halfway
            // and is exactly zero at both ends, so the surface always comes
            // back to rest flat.
            final t = _surface.value;
            final amplitude = math.sin(math.pi * t).clamp(0.0, 1.0);
            final scale = 1 + .02 * (1 - _pulse.value);

            return Transform.scale(
              scale: scale,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: _shownFill),
                duration: LabMotion.reduced(context)
                    ? Duration.zero
                    : LabMotion.wave,
                curve: Curves.easeOutCubic,
                builder: (context, fill, _) => CustomPaint(
                  size: Size(widget.width, widget.height),
                  painter: _JarPainter(
                    fill: fill,
                    notch: widget.metrics.notch,
                    liquid: color,
                    ink: lab.ink,
                    card: lab.card,
                    wavePhase: t * math.pi * 2.2,
                    waveAmplitude: amplitude * 0.055,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _JarPainter extends CustomPainter {
  const _JarPainter({
    required this.fill,
    required this.notch,
    required this.liquid,
    required this.ink,
    required this.card,
    required this.wavePhase,
    required this.waveAmplitude,
  });

  final double fill;
  final double? notch;
  final Color liquid;
  final Color ink;
  final Color card;
  final double wavePhase;

  /// Expressed as a fraction of the jar height so it scales with the widget.
  final double waveAmplitude;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final capHeight = h * .14;
    final body = Rect.fromLTWH(.7, capHeight, w - 1.4, h - capHeight - .7);
    final bodyRRect = RRect.fromRectAndRadius(
      body,
      Radius.circular(w * .16),
    );

    // Body, filled with the page colour first so the liquid sits behind glass
    // rather than floating on the background.
    canvas.drawRRect(bodyRRect, Paint()..color = card);

    if (fill > 0) {
      canvas.save();
      canvas.clipRRect(bodyRRect);

      final surfaceY = body.bottom - body.height * fill;
      final wave = body.height * waveAmplitude;
      final path = Path()..moveTo(body.left, surfaceY);
      const steps = 14;
      for (var i = 0; i <= steps; i++) {
        final x = body.left + body.width * (i / steps);
        final y =
            surfaceY +
            math.sin(wavePhase + i / steps * math.pi * 1.6) * wave +
            // A second, slower component keeps it from looking like a spring.
            math.sin(wavePhase * .6 + i / steps * math.pi * .9) * wave * .4;
        path.lineTo(x, y);
      }
      path
        ..lineTo(body.right, body.bottom)
        ..lineTo(body.left, body.bottom)
        ..close();

      canvas.drawPath(path, Paint()..color = liquid.withValues(alpha: .34));

      // A slightly darker meniscus so the surface reads as a surface.
      canvas.drawPath(
        path,
        Paint()
          ..color = liquid.withValues(alpha: .55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .9,
      );
      canvas.restore();
    }

    // Order-level notch: a hairline across the jar where "order" begins, so you
    // can see the level and the line at the same time.
    final n = notch;
    if (n != null) {
      final y = body.bottom - body.height * n;
      final line = Paint()
        ..color = ink.withValues(alpha: .5)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(body.left + 1, y),
        Offset(body.right - 1, y),
        line,
      );
      // Small ticks either side so the line reads as a marker, not a fill edge.
      canvas.drawLine(
        Offset(body.left, y - 1.6),
        Offset(body.left, y + 1.6),
        line,
      );
      canvas.drawLine(
        Offset(body.right, y - 1.6),
        Offset(body.right, y + 1.6),
        line,
      );
    }

    // Glass outline.
    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..color = ink.withValues(alpha: .8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );

    // Cap.
    final capWidth = w * .46;
    final cap = RRect.fromRectAndRadius(
      Rect.fromLTWH((w - capWidth) / 2, .6, capWidth, capHeight),
      const Radius.circular(1.6),
    );
    canvas.drawRRect(cap, Paint()..color = ink.withValues(alpha: .72));
  }

  @override
  bool shouldRepaint(covariant _JarPainter old) =>
      old.fill != fill ||
      old.notch != notch ||
      old.liquid != liquid ||
      old.ink != ink ||
      old.card != card ||
      old.wavePhase != wavePhase ||
      old.waveAmplitude != waveAmplitude;
}

/// The five segments under the jar. Rounded down in [jarMetrics] so a
/// nearly-full jar never reads as full.
class JarTicks extends StatelessWidget {
  const JarTicks({
    required this.count,
    required this.color,
    this.segments = 5,
    this.width = 15,
    this.height = 3.5,
    super.key,
  });

  final int count;
  final Color color;
  final int segments;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final hair = context.lab.hair;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(segments, (index) {
        final on = index < count;
        return Padding(
          padding: EdgeInsets.only(right: index == segments - 1 ? 0 : 3),
          child: AnimatedContainer(
            duration: LabMotion.of(context, LabMotion.quick),
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: on ? color : hair,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}
