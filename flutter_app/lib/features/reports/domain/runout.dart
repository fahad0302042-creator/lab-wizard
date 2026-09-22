import 'package:intl/intl.dart';

import '../../inventory/domain/models.dart';
import 'report_range.dart';

/// How much history an estimate needs before it is shown (REPORT-03).
const runOutLookbackDays = 90;
const runOutMinEntries = 3;
const runOutMinSpanDays = 7;

/// Either an estimate or the reason there is none.
sealed class RunOutResult {
  const RunOutResult();
}

/// Why no estimate is shown for an item.
enum RunOutGap { noUse, tooFewEntries, tooShortHistory }

class RunOutMissing extends RunOutResult {
  const RunOutMissing(this.gap);

  final RunOutGap gap;
}

/// A projected run-out for one item, with the numbers behind it.
class RunOutEstimate extends RunOutResult {
  const RunOutEstimate({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.consumedTotal,
    required this.entries,
    required this.historyDays,
    required this.today,
  });

  final String itemId;
  final String name;
  final String unit;
  final double quantity;

  /// Amount used across [entries] consume entries in the last [historyDays].
  final double consumedTotal;
  final int entries;
  final int historyDays;
  final DateTime today;

  /// Average use per day over the history window.
  double get dailyRate => consumedTotal / historyDays;

  /// Whole days until the stock reaches zero at the current pace; 0 when it
  /// is already empty. Multiplies before dividing so 3 mL at 3 mL per 20
  /// days is exactly 20, not 19.999….
  int get daysLeft => quantity <= 0
      ? 0
      : (quantity * historyDays / consumedTotal + 1e-9).floor();

  /// Local calendar day on which the stock is expected to run out.
  DateTime get runsOutOn =>
      DateTime(today.year, today.month, today.day + daysLeft);

  bool get isOut => quantity <= 0;
  bool get urgent => daysLeft <= 7;
  bool get soon => daysLeft <= 30;

  /// "~12 days · 3 Oct", "today" or "already out".
  String get headline {
    if (isOut) return 'already out';
    if (daysLeft == 0) return 'today';
    return '~$daysLeft day${daysLeft == 1 ? '' : 's'} · '
        '${DateFormat('d MMM').format(runsOutOn)}';
  }

  /// The reasoning in one sentence, so the number is never a black box.
  String get explanation =>
      '${formatQuantity(quantity)} $unit left; $entries use'
      '${entries == 1 ? '' : 's'} totalling ${formatQuantity(consumedTotal)} '
      '$unit over the last $historyDays days, about '
      '${formatQuantity(_round(dailyRate))} $unit per day.';

  static double _round(double value) =>
      value >= 10 ? value.roundToDouble() : (value * 100).round() / 100;
}

/// Estimates when [quantity] of one item runs out from its consume entries.
///
/// Returns the estimate, or a [RunOutMissing] explaining why the history is
/// not adequate: fewer than [runOutMinEntries] uses, or uses that span fewer
/// than [runOutMinSpanDays] days, inside the last [runOutLookbackDays] days.
/// A pace of zero never yields an estimate.
RunOutResult estimateRunOut({
  required String itemId,
  required String name,
  required String unit,
  required double quantity,
  required Iterable<ConsumptionLog> logs,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final window = ReportRange.lastDays(runOutLookbackDays, today: today);
  final uses = logs
      .where(
        (log) =>
            log.itemId == itemId &&
            log.action == InventoryAction.consume &&
            log.amount > 0 &&
            window.contains(log.loggedAt),
      )
      .toList();
  if (uses.isEmpty) return const RunOutMissing(RunOutGap.noUse);
  if (uses.length < runOutMinEntries) {
    return const RunOutMissing(RunOutGap.tooFewEntries);
  }
  var earliest = uses.first.loggedAt.toLocal();
  var total = 0.0;
  for (final log in uses) {
    final local = log.loggedAt.toLocal();
    if (local.isBefore(earliest)) earliest = local;
    total += log.amount;
  }
  final historyDays =
      DateTime.utc(today.year, today.month, today.day)
          .difference(DateTime.utc(earliest.year, earliest.month, earliest.day))
          .inDays +
      1;
  if (historyDays < runOutMinSpanDays) {
    return const RunOutMissing(RunOutGap.tooShortHistory);
  }
  return RunOutEstimate(
    itemId: itemId,
    name: name,
    unit: unit,
    quantity: quantity,
    consumedTotal: total,
    entries: uses.length,
    historyDays: historyDays,
    today: DateTime(today.year, today.month, today.day),
  );
}

/// Estimates for a whole shelf, soonest first, plus how many items lack
/// adequate history.
class RunOutReport {
  const RunOutReport({required this.estimates, required this.gaps});

  final List<RunOutEstimate> estimates;
  final Map<RunOutGap, int> gaps;

  int get withoutEstimate => gaps.values.fold(0, (sum, count) => sum + count);

  /// "4 items have too little history (need 3+ uses over 7+ days in the
  /// last 90 days)."
  String get gapSummary {
    final count = withoutEstimate;
    if (count == 0) return '';
    return '$count item${count == 1 ? ' has' : 's have'} too little history '
        '(need $runOutMinEntries+ uses over $runOutMinSpanDays+ days in the '
        'last $runOutLookbackDays days).';
  }
}

RunOutReport runOutReportForChemicals(
  Iterable<Chemical> chemicals,
  Iterable<ConsumptionLog> logs, {
  DateTime? now,
}) {
  final list = logs.toList(growable: false);
  return _collect([
    for (final item in chemicals)
      estimateRunOut(
        itemId: item.id,
        name: item.name,
        unit: item.unit,
        quantity: item.quantity,
        logs: list,
        now: now,
      ),
  ]);
}

RunOutReport runOutReportForApparatus(
  Iterable<Apparatus> apparatus,
  Iterable<ConsumptionLog> logs, {
  DateTime? now,
}) {
  final list = logs.toList(growable: false);
  return _collect([
    for (final item in apparatus)
      estimateRunOut(
        itemId: item.id,
        name: item.name,
        unit: 'pcs',
        quantity: item.quantity,
        logs: list,
        now: now,
      ),
  ]);
}

RunOutReport _collect(List<RunOutResult> results) {
  final estimates = <RunOutEstimate>[];
  final gaps = <RunOutGap, int>{};
  for (final result in results) {
    switch (result) {
      case RunOutEstimate():
        estimates.add(result);
      case RunOutMissing(:final gap):
        gaps[gap] = (gaps[gap] ?? 0) + 1;
    }
  }
  estimates.sort((a, b) {
    final byDays = a.daysLeft.compareTo(b.daysLeft);
    return byDays != 0 ? byDays : a.name.compareTo(b.name);
  });
  return RunOutReport(estimates: estimates, gaps: gaps);
}
