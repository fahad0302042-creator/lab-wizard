import 'dart:math' as math;

import '../../core/theme/app_theme.dart';

/// Everything the jar needs to draw itself, derived from the three numbers we
/// already store. Kept free of Flutter widgets so it can be unit-tested — which
/// matters here, because this is the one rule that decides whether someone
/// reorders a reagent in time.
/// What the vessel's height is allowed to mean.
enum LevelBasis {
  /// `quantity / capacity` is a real fraction: this vessel is 24% full.
  ofCapacity,

  /// No known capacity. The vessel shows that there *is* stock, at a fraction
  /// chosen for legibility, and claims nothing about how full it is.
  partial,
}

class JarMetrics {
  const JarMetrics({
    required this.fill,
    required this.partialFill,
    required this.notch,
    required this.ticks,
    required this.signal,
    required this.hasLimit,
    required this.basis,
  });

  /// How full the vessel is, 0–1 — or null when the record has no upper bound
  /// to compare against. Null is the honest answer, and the reason this is not
  /// `1`: a vessel must never draw "full" because it does not know.
  final double? fill;

  /// The fraction to *draw* when [fill] is null. Always a legible sliver with a
  /// visible surface, because a still, flat-topped body is what made the tilt
  /// look broken. Zero when there is nothing left, and unused when [fill] is
  /// known.
  final double partialFill;

  /// What the drawn height means. Anything that words a level must ask this
  /// first rather than printing a percentage.
  LevelBasis get basis =>
      fill == null ? LevelBasis.partial : LevelBasis.ofCapacity;

  /// True when the record cannot say how full it is.
  bool get levelUnknown => fill == null;

  /// Where the order level sits on the jar, 0–1. Null when no limit is set.
  final double? notch;

  /// Filled segments below the jar, 0–5.
  final int ticks;

  /// What the row is signalling.
  final StockSignal signal;

  /// Whether an order level has been set. When false the row shows a quiet
  /// "set limit" nudge instead of a warning.
  final bool hasLimit;

  /// True when the jar should read as completely empty.
  bool get isEmpty => signal == StockSignal.empty;
}

/// Decide the vessel from the stored numbers.
///
/// The level and the state are deliberately independent:
///
/// * **Level** is `quantity / capacity`, where capacity is
///   `max(initialQuantity, quantity)`. Using the max means restocking past the
///   original bottle size fills the vessel instead of overflowing it, so the
///   vessel self-heals rather than needing the record to be edited.
/// * **State** comes only from the order level. With no level set the item is
///   *fine* however little is left — the user's rule — with one exception:
///   zero is always empty, because zero needs no threshold to be unambiguous.
///
/// **When there is no upper bound it is known, `fill` is null, not 1.** A record
/// whose `initial_quantity` is zero has no "full" reference at all, and that is
/// the normal case for most rows in an imported store room — 156 of the 160
/// imported reagents and all 105 apparatus pieces have it at zero. The earlier
/// rule drew those as *completely full*, which put five solid ticks under a
/// "5 pcs" beaker and under "27170 mL" of 2-Butanol, and made the liquid look
/// frozen because there was no surface to move. A vessel with no known capacity
/// now shows just the liquid it has — see `partialFill` — and the ticks are a
/// neutral dash, because "how full" is a question this record cannot answer.
///
/// [piecewise] switches the ticks from percentages to whole units for
/// apparatus counted in single pieces, so "3 of 5 beakers" is literally three
/// ticks rather than a rounded percentage.
JarMetrics jarMetrics({
  required double quantity,
  required double initialQuantity,
  required double threshold,
  bool piecewise = false,
}) {
  final safeQuantity = quantity.isFinite && quantity > 0 ? quantity : 0.0;
  final limit = threshold.isFinite && threshold > 0 ? threshold : 0.0;
  final hasLimit = limit > 0;
  final recorded = initialQuantity.isFinite && initialQuantity > 0
      ? initialQuantity
      : 0.0;
  // Whether the record knows an upper bound at all. It has to be asked here,
  // not derived from `capacity`: capacity is the max with the current quantity,
  // so it is never zero when something is left, and a `capacity <= 0` test is
  // unreachable — which is how every imported row ended up drawn as full.
  final hasCapacity = recorded > 0;
  final capacity = math.max(recorded, safeQuantity);

  final double? fill;
  if (safeQuantity <= 0) {
    fill = 0;
  } else if (!hasCapacity) {
    // No "full" reference to compare against, so claim nothing. The vessel
    // draws a sliver rather than inventing a fraction.
    fill = null;
  } else {
    fill = (safeQuantity / capacity).clamp(0.0, 1.0);
  }

  final StockSignal signal;
  if (safeQuantity <= 0) {
    signal = StockSignal.empty;
  } else if (hasLimit && safeQuantity <= limit) {
    signal = StockSignal.order;
  } else {
    signal = StockSignal.fine;
  }

  // With no recorded capacity, or a limit above what the jar holds, the notch
  // pins to the top. Both are the honest picture: the limit is a flat quantity,
  // so any drop below it flags.
  final double? notch = !hasLimit
      ? null
      : !hasCapacity
      ? 1
      : (limit / capacity).clamp(0.0, 1.0);

  // Ticks are a percentage of something. With no known capacity there is no
  // percentage to give, so they read as unknown rather than as five-of-five.
  final int ticks;
  if (piecewise && hasCapacity && capacity <= 6) {
    ticks = safeQuantity.round().clamp(0, 5);
  } else if (fill == null || fill <= 0) {
    ticks = 0;
  } else {
    // Round down, so a nearly-full vessel never reads as full. Any liquid at all
    // still earns one tick, so a vessel can't look empty while it isn't.
    ticks = (fill * 5).floor().clamp(1, 5);
  }

  return JarMetrics(
    fill: fill,
    partialFill: fill == null && safeQuantity > 0 ? .42 : 0,
    notch: notch,
    ticks: ticks,
    signal: signal,
    hasLimit: hasLimit,
  );
}

/// The caption under the jar. Kept next to the metrics so the wording and the
/// colour can't drift apart.
String stockCaption(JarMetrics metrics, {required bool piecewiseUnit}) {
  return switch (metrics.signal) {
    StockSignal.empty => 'empty',
    StockSignal.order => 'order',
    StockSignal.fine when !metrics.hasLimit && !piecewiseUnit => 'set limit',
    StockSignal.fine => '',
  };
}
