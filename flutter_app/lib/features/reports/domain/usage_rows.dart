import 'dart:math' as math;

import '../../inventory/domain/models.dart';

/// One chemical or apparatus that was used or restocked in the report range.
///
/// [initial] is the stock at the start of the range plus restocks in the
/// range, so a restock raises both the opening figure and [finalQuantity].
/// Used-only rows leave [initial] at the opening stock. Nothing else is
/// listed: an item with no use and no restock in the range is omitted.
class PeriodUsageRow {
  const PeriodUsageRow({
    required this.id,
    required this.name,
    required this.detail,
    required this.unit,
    required this.initial,
    required this.restocked,
    required this.used,
    required this.finalQuantity,
  });

  final String id;
  final String name;
  final String detail;
  final String unit;

  /// Opening stock plus restocks in the range.
  final double initial;
  final double restocked;

  /// Consumed and damaged amount in the range.
  final double used;
  final double finalQuantity;

  /// Remaining as a percentage of [initial].
  double get pct => initial > 0 ? finalQuantity / initial * 100 : 0;
}

/// Rows for the consumption table: restocked items and used items only.
List<PeriodUsageRow> periodUsageRows({
  required ItemKind kind,
  required Iterable<Chemical> chemicals,
  required Iterable<Apparatus> apparatus,
  required Iterable<ConsumptionLog> logsInRange,
}) {
  final rows = <PeriodUsageRow>[];
  if (kind == ItemKind.chemical) {
    for (final item in chemicals) {
      final row = _rowFor(
        id: item.id,
        name: item.name,
        detail: item.formula,
        unit: item.unit,
        quantity: item.quantity,
        logs: logsInRange.where((log) => log.itemId == item.id),
      );
      if (row != null) rows.add(row);
    }
  } else {
    for (final item in apparatus) {
      final row = _rowFor(
        id: item.id,
        name: item.name,
        detail: item.category,
        unit: 'pcs',
        quantity: item.quantity,
        logs: logsInRange.where((log) => log.itemId == item.id),
      );
      if (row != null) rows.add(row);
    }
  }
  rows.sort((a, b) {
    if (b.used != a.used) return b.used.compareTo(a.used);
    if (b.restocked != a.restocked) return b.restocked.compareTo(a.restocked);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return rows;
}

PeriodUsageRow? _rowFor({
  required String id,
  required String name,
  required String detail,
  required String unit,
  required double quantity,
  required Iterable<ConsumptionLog> logs,
}) {
  var used = 0.0;
  var restocked = 0.0;
  for (final log in logs) {
    switch (log.action) {
      case InventoryAction.consume:
      case InventoryAction.breakage:
        used += log.amount;
      case InventoryAction.restock:
        restocked += log.amount;
    }
  }
  if (used <= 0 && restocked <= 0) return null;
  // Current quantity already includes the restock, so adding [used] back
  // raises the opening figure by the same restock instead of leaving it put.
  final initial = math.max(0.0, quantity + used);
  return PeriodUsageRow(
    id: id,
    name: name,
    detail: detail,
    unit: unit,
    initial: initial,
    restocked: restocked,
    used: used,
    finalQuantity: quantity,
  );
}
