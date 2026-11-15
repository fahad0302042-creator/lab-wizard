/// The store room vessel: a small vial whose liquid level *is* the stock bar,
/// and whose liquid tips when the phone tips.
///
/// Two things make the tilt honest, and they are the whole point of this file:
///
/// 1. **Gravity, not the widget, defines "down".** The liquid surface is drawn
///    in the *world* frame: it stays level with the ground while the glass leans
///    around it. A drop that merely rotated the whole jar would read as a
///    sticker turning, not a liquid finding its level.
/// 2. **The order-level notch lives in the same frame as the liquid.** It is a
///    ring painted onto the glass at world height `limit / capacity`, so when
///    the liquid tips, the line tips with the glass and the comparison between
///    them is still true. A line pinned to the screen instead would quietly lie
///    every time the phone was tilted — which is the exact moment the app is
///    asking to be believed.
///
/// The liquid is drawn at full strength (it is a real quantity, not a
/// decoration) in the stock state's colour; the glass on top of it is a cool
/// translucent wash with a rim light, so the tint stays glass and the colour
/// stays data.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme/app_theme.dart';
import 'jar_metrics.dart';
import 'vessel_level.dart';

/// What the vessel is drawn as. Shape carries meaning: reagents live in
/// stoppered bottles, apparatus on open beakers. Drawing GEAR rows as bottles
/// was the one thing on that tab that read as a mistake.
enum VesselShape {
  /// A reagent bottle: narrow stopper, shouldered body.
  bottle,

  /// Apparatus: an open vessel with a lip and no stopper.
  beaker,
}

/// A shelf vessel: the liquid level is the stock bar, and the liquid finds its
/// level when the phone tips.
class Vessel extends StatefulWidget {
  const Vessel({
    required this.metrics,
    this.width = 34,
    this.height = 42,
    this.tipDegrees = 0,
    this.onTap,
    this.semanticLabel,
    this.tiltSensitivity = 1.0,
    this.shape = VesselShape.bottle,
    super.key,
  });

  final JarMetrics metrics;
  final double width;
  final double height;

  /// Bottle for chemicals, beaker for apparatus.
  final VesselShape shape;

  /// How far the liquid should lean, in degrees. Supplied by a [VesselTilt]
  /// ancestor (or a drag); the vessel itself never reads the sensor.
  final double tipDegrees;

  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Multiplier on [tipDegrees]. Small vessels need more lean to read at all.
  final double tiltSensitivity;

  @override
  State<Vessel> createState() => _VesselState();
}

class _VesselState extends State<Vessel> with TickerProviderStateMixin {
  /// Drives the surface. Runs 0→1 whenever the level changes; the painter turns
  /// that into a damped wave so the liquid sloshes and settles.
  late final AnimationController _surface = AnimationController(
    vsync: this,
    duration: LabMotion.wave,
    value: 1,
  );

  /// A single pulse when a vessel becomes empty. Not a shake, not a loop.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );

  late double _shownFill = widget.metrics.fill ?? widget.metrics.partialFill;

  @override
  void didUpdateWidget(covariant Vessel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.metrics.fill ?? widget.metrics.partialFill;
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
    final reduce = LabMotion.reduced(context);
    // A record with no known capacity still has stock, so it shows a sliver
    // rather than a still, full-looking body.
    final target = widget.metrics.fill ?? widget.metrics.partialFill;

    return Semantics(
      label: widget.semanticLabel,
      button: widget.onTap != null,
      excludeSemantics: widget.semanticLabel != null,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_surface, _pulse]),
            builder: (context, _) {
              final t = _surface.value;
              final amplitude = reduce ? 0.0 : math.sin(math.pi * t).clamp(0.0, 1.0);
              final scale = 1 + .02 * (1 - _pulse.value);

              return Transform.scale(
                scale: scale,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: target),
                  duration: reduce ? Duration.zero : LabMotion.wave,
                  curve: Curves.easeOutCubic,
                  builder: (context, fill, _) => CustomPaint(
                    size: Size(widget.width, widget.height),
                    painter: _VesselPainter(
                      fill: fill,
                      notch: widget.metrics.notch,
                      liquid: color,
                      glass: lab.glass,
                      line: lab.ink,
                      tipRadians:
                          reduce
                              ? 0
                              : (widget.tipDegrees * widget.tiltSensitivity) *
                                    math.pi /
                                    180,
                      wavePhase: t * math.pi * 2.2,
                      waveAmplitude: (reduce ? 0.0 : amplitude) * .085,
                      dark: lab.canvas,
                      shape: widget.shape,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _VesselPainter extends CustomPainter {
  const _VesselPainter({
    required this.fill,
    required this.notch,
    required this.liquid,
    required this.glass,
    required this.line,
    required this.tipRadians,
    required this.wavePhase,
    required this.waveAmplitude,
    required this.dark,
    required this.shape,
  });

  final double fill;
  final double? notch;

  /// The stock state's colour. The only colour the liquid is ever drawn in.
  final Color liquid;

  /// Cool glass wash laid over the liquid so the tint reads as glass.
  final Color glass;

  /// Outline, cap and notch ink.
  final Color line;

  final double tipRadians;
  final double wavePhase;

  /// As a fraction of the vessel height, so it scales with the widget.
  final double waveAmplitude;

  /// The page colour, so the liquid is drawn over the background rather than
  /// over whatever happens to be behind the widget.
  final Color dark;

  final VesselShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final capHeight = h * .14;
    // The body, in its own (unrotated) frame: the shape the liquid fills.
    final body = Rect.fromLTWH(
      .7,
      capHeight,
      w - 1.4,
      h - capHeight - .7,
    );
    final bodyRRect = RRect.fromRectAndRadius(
      body,
      Radius.circular(w * .16),
    );

    // Body, filled with the page colour first so the vessel reads as an object
    // against the row rather than a hole in it.
    canvas.drawRRect(bodyRRect, Paint()..color = dark);

    // --- The settled-world ring the notch needs, in body space. -------------
    if (fill > 0) {
      canvas.save();
      canvas.clipRRect(bodyRRect);

      // The surface stays level in *world* terms but must sit inside the
      // vessel in *body* terms. Under a hard lean a lightly-filled bottle
      // would otherwise lift its surface past the shoulder, out of the clip,
      // and the whole body fills — still, and apparently full.
      final drawn = ensureVisibleFill(
        fill: fill,
        tipRadians: tipRadians,
        bodyWidth: body.width,
        bodyHeight: body.height,
        waveFraction: waveAmplitude,
      );
      final surfaceY = body.bottom - body.height * drawn;
      final wave = body.height * waveAmplitude;

      // World "down" expressed in the glass's frame: tilting the phone by θ
      // means the liquid surface, which stays level with the ground, appears to
      // the glass to be rotated by -θ. Drawing the surface under that rotation
      // is what keeps it level on screen.
      final lean = -tipRadians;

      // Liquid is a large region; rotate about the body's centre and extend it
      // well past the edges so no corner is ever exposed by the lean.
      canvas.save();
      canvas.translate(body.center.dx, body.center.dy);
      canvas.rotate(lean);
      canvas.translate(-body.center.dx, -body.center.dy);

      // Extend horizontally past the body so rotation can't reveal a gap.
      final reach = body.height * 1.2;
      final path = Path()..moveTo(body.left - reach, surfaceY);
      const steps = 16;
      for (var i = 0; i <= steps; i++) {
        final x = body.left - reach + (body.width + reach * 2) * (i / steps);
        final y =
            surfaceY +
            math.sin(wavePhase + i / steps * math.pi * 1.6) * wave +
            // A second, slower component keeps it from looking like a spring.
            math.sin(wavePhase * .6 + i / steps * math.pi * .9) * wave * .4;
        path.lineTo(x, y);
      }
      path
        ..lineTo(body.right + reach, body.bottom + reach)
        ..lineTo(body.left - reach, body.bottom + reach)
        ..close();

      // Full-strength liquid: a real quantity, so it is allowed to be the
      // loudest thing in the widget. A vertical shade gives it depth without
      // inventing a colour.
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              liquid.withValues(alpha: .55),
              liquid.withValues(alpha: .78),
            ],
          ).createShader(body),
      );

      // Meniscus: a brighter hairline on the surface, which is what makes the
      // tilt readable at a glance. Drawn along the same leaning path.
      final surface = Path()
        ..moveTo(body.left - reach, surfaceY);
      for (var i = 0; i <= steps; i++) {
        final x = body.left - reach + (body.width + reach * 2) * (i / steps);
        final y =
            surfaceY +
            math.sin(wavePhase + i / steps * math.pi * 1.6) * wave +
            math.sin(wavePhase * .6 + i / steps * math.pi * .9) * wave * .4;
        if (i > 0) {
          surface.lineTo(x, y);
        }
      }
      canvas.drawPath(
        surface,
        Paint()
          ..color = liquid.withValues(alpha: .95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(.9, h * .022),
      );
      canvas.restore();

      canvas.restore();
    }

    // --- Glass: a cool wash over the liquid, then the rim. ------------------
    // The *whole* vessel turns with the phone: body, rim, cap and all. Only the
    // surface inside it stays level with the ground. That difference is the
    // entire illusion — when the outline stood still and only the liquid
    // moved, a 40° tilt looked like nothing at all on a 30 dp vessel.
    canvas.save();
    canvas.translate(body.center.dx, body.center.dy);
    canvas.rotate(tipRadians);
    canvas.translate(-body.center.dx, -body.center.dy);

    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            glass.withValues(alpha: .16),
            glass.withValues(alpha: .02),
          ],
        ).createShader(body),
    );

    // The order-level notch. In body space, so it tips with the glass and can
    // never disagree with the liquid it is comparing itself to.
    final n = notch;
    if (n != null) {
      final y = body.bottom - body.height * n.clamp(0.0, 1.0);
      final notchPaint = Paint()
        ..color = line.withValues(alpha: .62)
        ..strokeWidth = math.max(.8, h * .018);
      final inset = body.width * .12;
      canvas.drawLine(
        Offset(body.left + inset, y),
        Offset(body.right - inset, y),
        notchPaint,
      );
      // Short ticks at both ends so it reads as a marker, not a fill edge.
      for (final x in [body.left + inset, body.right - inset]) {
        canvas.drawLine(
          Offset(x, y - h * .028),
          Offset(x, y + h * .028),
          notchPaint,
        );
      }
    }

    // Rim: hairline plus a highlight down one side, so it reads as glass.
    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..color = line.withValues(alpha: .82)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, w * .032),
    );
    canvas.drawLine(
      Offset(body.left + w * .17, body.top + body.height * .18),
      Offset(body.left + w * .17, body.top + body.height * .55),
      Paint()
        ..color = line.withValues(alpha: .18)
        ..strokeWidth = math.max(1, w * .05)
        ..strokeCap = StrokeCap.round,
    );

    // The mouth. A bottle gets a stopper sitting proud of the body; a beaker
    // gets an open rim with a lip on one side, which is what makes it read as
    // apparatus rather than as a bottle with its lid missing.
    if (shape == VesselShape.bottle) {
      final capWidth = w * .46;
      final cap = RRect.fromRectAndRadius(
        Rect.fromLTWH((w - capWidth) / 2, .6, capWidth, capHeight),
        const Radius.circular(1.6),
      );
      canvas.drawRRect(cap, Paint()..color = line.withValues(alpha: .55));
    } else {
      final rim = Paint()
        ..color = line.withValues(alpha: .7)
        ..strokeWidth = math.max(1, w * .06)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(body.left, body.top),
        Offset(body.right, body.top),
        rim,
      );
      // The lip: a short flare above the rim on the right, so the open end is
      // legible even at 30 dp.
      canvas.drawLine(
        Offset(body.right, body.top),
        Offset(body.right + w * .07, body.top - capHeight * .5),
        rim,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VesselPainter old) =>
      old.fill != fill ||
      old.notch != notch ||
      old.liquid != liquid ||
      old.glass != glass ||
      old.line != line ||
      old.tipRadians != tipRadians ||
      old.wavePhase != wavePhase ||
      old.waveAmplitude != waveAmplitude ||
      old.dark != dark ||
      old.shape != shape;
}

/// The five segments under a vessel. Rounded down in [jarMetrics] so a
/// nearly-full vessel never reads as full.
class JarTicks extends StatelessWidget {
  const JarTicks({
    required this.count,
    required this.color,
    this.unknown = false,
    this.segments = 5,
    this.width = 15,
    this.height = 3.5,
    super.key,
  });

  final int count;
  final Color color;

  /// No known capacity, so there is no fraction to show. The row becomes a
  /// single dash rather than five lit segments — five green bars under "5 pcs"
  /// reads as *full*, which is the opposite of what a record with no capacity
  /// can actually claim.
  final bool unknown;
  final int segments;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final hair = context.lab.hairStrong;
    if (unknown) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: width * .8,
            height: height,
            decoration: BoxDecoration(
              color: hair,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: width * .35),
          Text(
            'level not set',
            style: context.label.copyWith(
              fontSize: 9,
              letterSpacing: .6,
              color: context.lab.inkFaint,
            ),
          ),
        ],
      );
    }
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
