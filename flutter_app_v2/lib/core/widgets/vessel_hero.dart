import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme/app_theme.dart';
import 'jar_metrics.dart';
import 'vessel_level.dart';
import 'vessel_tilt.dart';

/// The screen's one instrument: a large vessel for whichever reagent is
/// closest to running out.
///
/// This replaces a decorative hero box. Everything in it is a fact:
///
/// * the liquid height is `quantity / capacity`, the same rule the rows use;
/// * its colour is the stock state, so it cannot disagree with the row it came
///   from;
/// * the notch is drawn in the liquid's own frame, as a ring on the glass at
///   world height `limit / capacity`, so tilting the phone can't make the line
///   sit at the wrong reading;
/// * the readout underneath is the label, quantity, order level and a tilt
///   angle — because a signature interaction with no readout is just an
///   animation.
///
/// It leans through the enclosing lean scope, which the dashboard
/// already provides, so the hero needs no provider of its own and stays
/// testable and previewable without a platform channel.
class VesselHero extends StatefulWidget {
  const VesselHero({
    required this.metrics,
    required this.name,
    required this.formula,
    required this.quantityText,
    required this.unit,
    required this.orderText,
    this.onTap,
    this.placeholder = false,
    super.key,
  });

  final JarMetrics metrics;
  final String name;
  final String formula;
  final String quantityText;
  final String unit;

  /// "order at 300 mL", or the quiet "no order level set" nudge.
  final String orderText;
  final VoidCallback? onTap;

  /// Nothing on the shelf yet: draws an empty vessel with a dash readout
  /// instead of inventing numbers.
  final bool placeholder;

  @override
  State<VesselHero> createState() => _VesselHeroState();
}

class _VesselHeroState extends State<VesselHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _surface = AnimationController(
    vsync: this,
    duration: LabMotion.wave,
    value: 1,
  );

  @override
  void didUpdateWidget(covariant VesselHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = widget.metrics.fill ?? widget.metrics.partialFill;
    final before = oldWidget.metrics.fill ?? oldWidget.metrics.partialFill;
    if ((now - before).abs() > .001 &&
        !LabMotion.reduced(context)) {
      _surface
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _surface.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lab = context.lab;
    final color = lab.forState(widget.metrics.signal);
    final reduce = LabMotion.reduced(context);

    return Semantics(
      button: widget.onTap != null,
      label: widget.placeholder
          ? 'No reagents yet'
          : '${widget.name}, ${widget.quantityText} ${widget.unit}, '
                '${widget.orderText}',
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: lab.hair),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                lab.surface,
                Color.lerp(lab.surface, lab.vignette, .35)!,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 12, 0),
                child: Row(
                  children: [
                    _LiveDot(color: widget.placeholder ? lab.inkFaint : color),
                    const SizedBox(width: 7),
                    Text(
                      widget.placeholder ? 'NO STOCK YET' : 'CLOSEST TO EMPTY',
                      style: context.label.copyWith(
                        fontSize: 9.5,
                        color: lab.inkSoft,
                      ),
                    ),
                    const Spacer(),
                    // The readout that makes the gesture legible: the glass is
                    // leaning because the phone is, and here is by how much.
                    // Wrapped so only this text repaints per sample.
                    TiltReadout(
                      builder: (context, lean) {
                        final degrees = lean.round().abs();
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: lab.canvas.withValues(alpha: .5),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: lab.hair),
                          ),
                          child: Text(
                            degrees == 0
                                ? 'LEVEL'
                                : '$degrees° ${lean > 0 ? 'R' : 'L'}',
                            style: context.label.copyWith(
                              fontSize: 9.5,
                              color: degrees == 0 ? lab.inkFaint : lab.accent,
                              letterSpacing: .6,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // The instrument. Tall enough that a 40° lean moves the surface
              // by a visible amount, short enough to leave the order list room.
              SizedBox(
                height: 152,
                width: double.infinity,
                child: RepaintBoundary(
                  // The hero leans by thumb as well as by sensor. The drag is
                  // claimed only inside this box, so the card's tap still opens
                  // the item and the page still scrolls.
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (details) =>
                        Lean.nudge(context, details.delta.dx),
                    onHorizontalDragEnd: (_) => Lean.release(context),
                    onHorizontalDragCancel: () => Lean.release(context),
                    child: TiltReadout(
                      builder: (context, lean) => AnimatedBuilder(
                        animation: _surface,
                        builder: (context, _) {
                          final t = _surface.value;
                          final amplitude = reduce
                              ? 0.0
                              : math.sin(math.pi * t).clamp(0.0, 1.0);
                          return CustomPaint(
                            painter: _HeroPainter(
                              fill: widget.placeholder
                                  ? 0
                                  : (widget.metrics.fill ??
                                        widget.metrics.partialFill),
                              notch: widget.placeholder
                                  ? null
                                  : widget.metrics.notch,
                              liquid: color,
                              glass: lab.glass,
                              line: lab.ink,
                              pageColor: lab.canvas,
                              tipRadians:
                                  reduce ? 0 : lean * math.pi / 180,
                              wavePhase: t * math.pi * 2.2,
                              waveAmplitude: (reduce ? 0.0 : amplitude) * .035,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.placeholder ? 'Add a reagent' : widget.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.itemName.copyWith(fontSize: 18),
                          ),
                          if (widget.formula.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.formula,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.formula,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: widget.quantityText,
                                style: context.figure.copyWith(
                                  fontSize: 26,
                                  color: widget.placeholder
                                      ? lab.inkFaint
                                      : lab.ink,
                                ),
                              ),
                              TextSpan(
                                text: '  ${widget.unit}',
                                style: context.label.copyWith(
                                  fontSize: 10,
                                  color: lab.inkSoft,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.orderText,
                          style: context.label.copyWith(
                            fontSize: 9.5,
                            letterSpacing: .5,
                            color: widget.placeholder
                                ? lab.inkFaint
                                : (widget.metrics.hasLimit
                                      ? color.withValues(alpha: .9)
                                      : lab.inkFaint),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: .5), blurRadius: 6)],
      ),
    );
  }
}

class _HeroPainter extends CustomPainter {
  const _HeroPainter({
    required this.fill,
    required this.notch,
    required this.liquid,
    required this.glass,
    required this.line,
    required this.pageColor,
    required this.tipRadians,
    required this.wavePhase,
    required this.waveAmplitude,
  });

  final double fill;
  final double? notch;
  final Color liquid;
  final Color glass;
  final Color line;
  final Color pageColor;
  final double tipRadians;
  final double wavePhase;
  final double waveAmplitude;

  /// The bottle's body, in its unrotated frame.
  static Rect _body(Size size) {
    final w = size.width;
    final h = size.height;
    // Tall and narrow rather than squat: a bottle that is nearly as wide as it
    // is tall hides the tilt, because a rotated square looks like the same
    // square. 0.34 of the width by 0.86 of the height gives the lean somewhere
    // to go without the bottle turning into a test tube.
    final outerW = math.min(w * .34, h * .5);
    final outer = Rect.fromCenter(
      center: Offset(w / 2, h / 2 + h * .02),
      width: outerW,
      height: h * .86,
    );
    return outer.deflate(2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final body = _body(size);
    final radius = Radius.circular(body.width * .2);
    final bodyRRect = RRect.fromRectAndRadius(body, radius);

    // A glow under the vessel grounds it on the surface instead of floating it
    // in the middle of a card.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, body.bottom + 3),
        width: body.width * 1.25,
        height: 10,
      ),
      Paint()
        ..color = liquid.withValues(alpha: .18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    canvas.drawRRect(bodyRRect, Paint()..color = pageColor);
    canvas.save();
    canvas.clipRRect(bodyRRect);

    // World-level surface, leaning by -tip in the glass's frame.
    // Same reasoning as the small vessel: the surface must stay inside the
    // glass under any lean, or the body fills edge to edge and stops reading
    // as a level liquid. The hero's body is wide and shallow, so this usually
    // leaves the fill untouched.
    final drawn = ensureVisibleFill(
      fill: fill,
      tipRadians: tipRadians,
      bodyWidth: body.width,
      bodyHeight: body.height,
      waveFraction: waveAmplitude,
    );
    final surfaceY = body.bottom - body.height * drawn;
    final reach = body.height * 1.4;
    final wave = body.height * waveAmplitude;

    Path surfacePath() {
      final path = Path();
      const steps = 20;
      for (var i = 0; i <= steps; i++) {
        final x = body.left - reach + (body.width + reach * 2) * (i / steps);
        final y =
            surfaceY +
            math.sin(wavePhase + i / steps * math.pi * 1.7) * wave +
            math.sin(wavePhase * .55 + i / steps * math.pi * .8) * wave * .45;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    if (fill > 0) {
      canvas.save();
      canvas.translate(body.center.dx, body.center.dy);
      canvas.rotate(-tipRadians);
      canvas.translate(-body.center.dx, -body.center.dy);

      final surface = surfacePath();
      final liquidPath = Path.from(surface)
        ..lineTo(body.right + reach, body.bottom + reach)
        ..lineTo(body.left - reach, body.bottom + reach)
        ..close();

      canvas.drawPath(
        liquidPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              liquid.withValues(alpha: .5),
              liquid.withValues(alpha: .8),
            ],
          ).createShader(body),
      );
      canvas.drawPath(
        surface,
        Paint()
          ..color = liquid
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      canvas.restore();
    }

    // Glass wash over the liquid: the tint reads as glass, the colour stays the
    // stock signal underneath it.
    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            glass.withValues(alpha: .12),
            Colors.transparent,
            glass.withValues(alpha: .06),
          ],
        ).createShader(body),
    );
    canvas.restore();

    // Notch, in the same leaning frame as the liquid.
    final n = notch;
    // The vessel turns with the phone — rim, notch and all — while the surface
    // inside it stays level with the ground. The old version turned the glass
    // by a third of the tip, which is why a 40° tilt barely moved it.
    canvas.save();
    canvas.translate(body.center.dx, body.center.dy);
    canvas.rotate(tipRadians);
    canvas.translate(-body.center.dx, -body.center.dy);

    if (n != null) {
      final y = body.bottom - body.height * n.clamp(0.0, 1.0);
      final paint = Paint()
        ..color = line.withValues(alpha: .55)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(body.left + body.width * .1, y),
        Offset(body.right - body.width * .1, y),
        paint,
      );
      for (final x in [
        body.left + body.width * .1,
        body.right - body.width * .1,
      ]) {
        canvas.drawLine(Offset(x, y - 3.5), Offset(x, y + 3.5), paint);
      }
    }

    // Rim, plus a highlight so it reads as a bottle rather than a bar chart.
    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..color = line.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.drawLine(
      Offset(body.left + body.width * .16, body.top + body.height * .1),
      Offset(body.left + body.width * .16, body.top + body.height * .45),
      Paint()
        ..color = line.withValues(alpha: .13)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeroPainter old) =>
      old.fill != fill ||
      old.notch != notch ||
      old.liquid != liquid ||
      old.tipRadians != tipRadians ||
      old.wavePhase != wavePhase ||
      old.waveAmplitude != waveAmplitude ||
      old.pageColor != pageColor ||
      old.line != line;
}
