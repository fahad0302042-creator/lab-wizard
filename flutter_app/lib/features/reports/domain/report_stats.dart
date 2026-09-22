import '../../inventory/domain/models.dart';
import 'report_range.dart';

/// Count and unit-aware quantity of one kind of action (REPORT-02).
class ActionTotals {
  const ActionTotals({this.count = 0, this.quantityByUnit = const {}});

  final int count;

  /// Summed amounts per unit ("mL" → 350, "g" → 20). Units are never mixed:
  /// 5 g and 5 mL stay two numbers.
  final Map<String, double> quantityByUnit;

  ActionTotals _add(double amount, String unit) => ActionTotals(
    count: count + 1,
    quantityByUnit: {
      ...quantityByUnit,
      unit: (quantityByUnit[unit] ?? 0) + amount,
    },
  );

  /// "350 mL · 20 g", largest first; empty when nothing was recorded.
  String get quantityLabel {
    final entries = quantityByUnit.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .map((entry) => '${formatQuantity(entry.value)} ${entry.key}'.trim())
        .join(' · ');
  }
}

/// Totals of one period, split by action.
class PeriodStats {
  const PeriodStats({required this.range, required this.byAction});

  final ReportRange range;
  final Map<InventoryAction, ActionTotals> byAction;

  ActionTotals of(InventoryAction action) =>
      byAction[action] ?? const ActionTotals();

  int get totalCount =>
      byAction.values.fold(0, (sum, totals) => sum + totals.count);
}

/// Sums the logs of [kind] that fall inside [range]. [unitOf] resolves an
/// item's unit (apparatus is always pieces); unknown items count without a
/// unit so removed items still show up in counts.
PeriodStats summarizePeriod(
  ReportRange range,
  Iterable<ConsumptionLog> logs, {
  required ItemKind kind,
  required String Function(String itemId) unitOf,
}) {
  final totals = <InventoryAction, ActionTotals>{};
  for (final log in logs) {
    if (log.itemType != kind || !range.contains(log.loggedAt)) continue;
    final unit = kind == ItemKind.apparatus ? 'pcs' : unitOf(log.itemId);
    totals[log.action] = (totals[log.action] ?? const ActionTotals())._add(
      log.amount,
      unit,
    );
  }
  return PeriodStats(range: range, byAction: totals);
}

/// The selected period next to the one before it.
class TrendComparison {
  const TrendComparison({required this.current, required this.previous});

  factory TrendComparison.compute(
    ReportRange range,
    Iterable<ConsumptionLog> logs, {
    required ItemKind kind,
    required String Function(String itemId) unitOf,
  }) {
    final list = logs.toList(growable: false);
    return TrendComparison(
      current: summarizePeriod(range, list, kind: kind, unitOf: unitOf),
      previous: summarizePeriod(
        range.previous,
        list,
        kind: kind,
        unitOf: unitOf,
      ),
    );
  }

  final PeriodStats current;
  final PeriodStats previous;

  /// Relative change of the action count, or null when the previous period
  /// had none (a ratio against zero would be meaningless).
  double? countChange(InventoryAction action) {
    final before = previous.of(action).count;
    if (before == 0) return null;
    return (current.of(action).count - before) / before;
  }

  /// Relative change of the quantity in [unit], with the same null rule.
  double? quantityChange(InventoryAction action, String unit) {
    final before = previous.of(action).quantityByUnit[unit] ?? 0;
    if (before <= 0) return null;
    final now = current.of(action).quantityByUnit[unit] ?? 0;
    return (now - before) / before;
  }

  /// Short comparison such as "+25% vs previous 7 days", "new" when the
  /// previous period was empty, "no change", or "none in either period".
  String describe(InventoryAction action) {
    final now = current.of(action).count;
    final before = previous.of(action).count;
    final versus = previousLabel;
    if (now == 0 && before == 0) return 'none in either period';
    if (before == 0) return 'none in the $versus';
    if (now == 0) return 'none, $before in the $versus';
    final change = countChange(action)!;
    if (change == 0) return 'same as the $versus';
    return '${formatChange(change)} vs $versus';
  }

  /// "previous 7 days", "previous month", "previous 12 days".
  String get previousLabel => switch (current.range.kind) {
    ReportRangeKind.last7 => 'previous 7 days',
    ReportRangeKind.last30 => 'previous 30 days',
    ReportRangeKind.month => 'previous month',
    ReportRangeKind.custom =>
      'previous ${current.range.dayCount} day'
          '${current.range.dayCount == 1 ? '' : 's'}',
  };
}

/// "+25%", "−40%" (a real minus sign), "0%".
String formatChange(double ratio) {
  final percent = (ratio * 100).round();
  if (percent == 0) return '0%';
  return percent > 0 ? '+$percent%' : '−${percent.abs()}%';
}
