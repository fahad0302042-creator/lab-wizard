import 'dart:math' as math;

import '../../inventory/domain/models.dart';

/// One chemical or apparatus that was used or restocked in the report range.
///
/// [opening] is the stock at the start of the range, before restocks in the
/// range. [restocked] is the increase. [initial] is opening plus that
/// increase, so initial − used = [finalQuantity]. An item with neither use
/// nor restock is omitted.
class PeriodUsageRow {
  const PeriodUsageRow({
    required this.id,
    required this.name,
    required this.detail,
    required this.unit,
    required this.opening,
    required this.initial,
    required this.restocked,
    required this.used,
    required this.finalQuantity,
    required this.pct,
  });

  final String id;
  final String name;
  final String detail;
  final String unit;

  /// Stock before restocks in the range. This is the start-stock column.
  final double opening;

  /// [opening] plus restocks in the range.
  final double initial;
  final double restocked;

  /// Consumed and damaged amount in the range.
  final double used;
  final double finalQuantity;

  /// Remaining as a percentage of the catalog opening, matching the
  /// original report when nothing was added.
  final double pct;
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
        catalogInitial: item.initialQuantity,
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
        catalogInitial: item.initialQuantity,
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
  required double catalogInitial,
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
  // Current quantity already includes the restock. Subtracting it leaves the
  // start-stock column put, and the increase column carries the addition.
  final opening = math.max(0.0, quantity + used - restocked);
  final initial = math.max(0.0, quantity + used);
  final pct = catalogInitial > 0
      ? quantity / catalogInitial * 100
      : (opening > 0 ? quantity / opening * 100 : 100.0);
  return PeriodUsageRow(
    id: id,
    name: name,
    detail: detail,
    unit: unit,
    opening: opening,
    initial: initial,
    restocked: restocked,
    used: used,
    finalQuantity: quantity,
    pct: pct,
  );
}
