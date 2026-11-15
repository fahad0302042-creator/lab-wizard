import 'dart:math' as math;

/// Where a *level* liquid surface can sit inside a vessel that is itself
/// leaning by [tipRadians].
///
/// The surface is always drawn level with the ground, so in the leaning glass's
/// own frame it is a line tilted by `-tip`. Push that line far enough down and
/// it leaves the body through both walls; push it up and every corner is
/// underwater, the clip fills edge to edge, and the vessel reads as completely
/// full no matter what it actually holds. That last case is the one that made
/// a tilted bottle look frozen.
///
/// The honest bound is the projection of the body's half-diagonal onto the
/// surface normal, which is `|sin θ|·W/2 + |cos θ|·H/2`. Expressing that as a
/// fraction of the body height gives the range of *visible* fills:
///
///     span = (|sin θ|·W/2 + |cos θ|·H/2) / H
///     visible fill ∈ [0.5 - span, 0.5 + span]
///
/// A 24%-full tall test tube lying on its side therefore cannot show 24%; the
/// lower bound lifts it until the surface is back inside the glass. The band
/// only binds for narrow vessels at hard leans: the shelf-row bottle
/// (30x34, W/H 0.88) and the dashboard hero never bind at all, and only tubes
/// narrower than about W/H 0.5 start lifting, from around 35 degrees of phone
/// tilt. A wide, shallow body has span > 0.5 and is never clamped, which is
/// correct — its surface can always be seen.
///
/// This is a floor for honesty, **not** the fix for a still-looking vessel.
/// A vessel that reads as frozen is almost always being *filled* wrongly, not
/// clipped wrongly; see [jarMetrics] and the no-capacity case. In the common
/// case `ensureVisibleFill` returns `fill` untouched, so the drawn height keeps
/// carrying the real quantity.
double ensureVisibleFill({
  required double fill,
  required double tipRadians,
  required double bodyWidth,
  required double bodyHeight,
  double waveFraction = 0,
}) {
  if (!fill.isFinite || bodyHeight <= 0 || bodyWidth <= 0) return fill;

  final angle = tipRadians.abs();
  // The wave rides on top of the surface, so it counts against the margin
  // twice: once as the crest rising toward the shoulder, once as the trough
  // dropping toward the base.
  final span =
      (math.sin(angle) * bodyWidth / 2 +
          math.cos(angle) * bodyHeight / 2 +
          waveFraction * bodyHeight) /
      bodyHeight;

  final low = (0.5 - span).clamp(0.0, 1.0);
  final high = (0.5 + span).clamp(0.0, 1.0);

  // `span` is non-negative, so `low <= high` and clamp can never be handed an
  // inverted range — which would assert in debug and silently misbehave in
  // release. A previous revision derived this from the half-diagonal and did
  // exactly that on wide vessels.
  return fill.clamp(low, high);
}
