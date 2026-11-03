import 'dart:math' as math;

import '../../core/theme/app_theme.dart';

/// Everything the jar needs to draw itself, derived from the three numbers we
/// already store. Kept free of Flutter widgets so it can be unit-tested — which
/// matters here, because this is the one rule that decides whether someone
/// reorders a reagent in time.
class JarMetrics {
  const JarMetrics({
    required this.fill,
    required this.notch,
    required this.ticks,
    required this.signal,
    required this.hasLimit,
  });

  /// How full the jar looks, 0–1.
  final double fill;

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

/// Decide the jar from the stored numbers.
///
/// The level and the state are deliberately independent:
///
/// * **Level** is `quantity / capacity`, where capacity is
///   `max(initialQuantity, quantity)`. Using the max means restocking past the
///   original bottle size fills the jar instead of overflowing it, so the jar
///   self-heals rather than needing the record to be edited.
/// * **State** comes only from the order level. With no level set the item is
///   *fine* however little is left — the user's rule — with one exception:
///   zero is always empty, because zero needs no threshold to be unambiguous.
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
  final capacity = math.max(
    initialQuantity.isFinite ? initialQuantity : 0.0,
    safeQuantity,
  );

  final double fill;
  if (safeQuantity <= 0) {
    fill = 0;
  } else if (capacity <= 0) {
    // No "full" reference to compare against. Claiming a fraction would be
    // inventing one, so the jar reads full and only the state carries meaning.
    fill = 1;
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

  // The notch pins to the top when the limit is set above what the jar holds,
  // which is the honest picture: you would order as soon as it drops at all.
  final double? notch = !hasLimit
      ? null
      : capacity <= 0
      ? 1
      : (limit / capacity).clamp(0.0, 1.0);

  final int ticks;
  if (piecewise && capacity > 0 && capacity <= 6) {
    ticks = safeQuantity.round().clamp(0, 5);
  } else if (fill <= 0) {
    ticks = 0;
  } else {
    // Round down, so a nearly-full jar never reads as full. Any liquid at all
    // still earns one tick, so a jar can't look empty while it isn't.
    ticks = (fill * 5).floor().clamp(1, 5);
  }

  return JarMetrics(
    fill: fill,
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
