import 'package:intl/intl.dart';

import '../../inventory/domain/models.dart';

/// Where the numbers on the report come from.
///
/// The sheet reads left to right as a sum that anyone can check by hand:
///
///     we have + added = now we have
///     now we have − used = left
///
/// `left` is the quantity on the shelf today, `used` is everything taken out
/// during the month, so `now we have` and `we have` are derived backwards from
/// those two. Nothing is estimated: if no restock was logged, the two "have"
/// columns are identical and the report prints one of them instead of two.
class ReportRow {
  const ReportRow({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.unit,
    required this.weHave,
    required this.added,
    required this.nowHave,
    required this.used,
    required this.left,
  });

  final String id;
  final String name;

  /// The formula for a chemical, the category for a piece of apparatus.
  final String subtitle;
  final String unit;
  final double weHave;
  final double added;
  final double nowHave;
  final double used;
  final double left;

  bool get hasAddition => added > 0;
}

/// One month of one shelf, ready to draw or print.
class MonthlyReport {
  const MonthlyReport({
    required this.kind,
    required this.month,
    required this.rows,
    required this.events,
    required this.lowStockCount,
  });

  final ItemKind kind;
  final DateTime month;
  final List<ReportRow> rows;

  /// Consumption events in the month, counting every entry rather than every
  /// item — three separate 100 mL pours is three events, not one.
  final int events;

  /// Items on this shelf that are at or below their order level right now,
  /// including ones with no entry this month.
  final int lowStockCount;

  bool get isEmpty => rows.isEmpty;

  /// Items that were actually drawn down. A restock-only row is not "consumed".
  int get itemsConsumed => rows.where((row) => row.used > 0).length;

  /// The added column earns its place only when something was added. A sheet of
  /// zeroes hides the numbers a reader actually wants.
  bool get hasAdditions => rows.any((row) => row.hasAddition);

  bool get isChemical => kind == ItemKind.chemical;

  String get title =>
      isChemical ? 'Chemicals Consumption Report' : 'Apparatus Usage Report';

  String get shelfName => isChemical ? 'Chemicals' : 'Apparatus';

  String get periodLabel => DateFormat('MMMM yyyy').format(month);

  /// The line under the table, assembled from what the sheet actually shows.
  String get footnote {
    final rule = hasAdditions
        ? 'We have + added = now we have. Now we have − used = left.'
        : 'We have − used = left.';
    return '$rule Only used and restocked items are listed, in alphabetical '
        'order.';
  }
}

double _round2(double value) => (value * 100).roundToDouble() / 100;

bool _sameMonth(DateTime value, DateTime month) {
  final local = value.toLocal();
  return local.year == month.year && local.month == month.month;
}

/// Builds the sheet for one shelf and one month.
///
/// Deliberately pure: no providers, no database, no clock. That is what makes
/// the arithmetic testable without a phone.
MonthlyReport buildMonthlyReport({
  required ItemKind kind,
  required List<Chemical> chemicals,
  required List<Apparatus> apparatus,
  required List<ConsumptionLog> logs,
  required DateTime month,
}) {
  final monthLogs = logs
      .where((log) => log.itemType == kind && _sameMonth(log.loggedAt, month))
      .toList();

  final used = <String, double>{};
  final added = <String, double>{};
  var events = 0;
  for (final log in monthLogs) {
    if (log.action == InventoryAction.restock) {
      added.update(
        log.itemId,
        (value) => value + log.amount,
        ifAbsent: () => log.amount,
      );
    } else {
      used.update(
        log.itemId,
        (value) => value + log.amount,
        ifAbsent: () => log.amount,
      );
      events++;
    }
  }

  final rows = <ReportRow>[];
  if (kind == ItemKind.chemical) {
    for (final item in chemicals) {
      final row = _rowFor(
        id: item.id,
        name: item.name,
        subtitle: item.formula,
        unit: item.unit,
        quantity: item.quantity,
        used: used[item.id] ?? 0,
        added: added[item.id] ?? 0,
      );
      if (row != null) rows.add(row);
    }
  } else {
    for (final item in apparatus) {
      final row = _rowFor(
        id: item.id,
        name: item.name,
        subtitle: item.category,
        unit: 'pcs',
        quantity: item.quantity,
        used: used[item.id] ?? 0,
        added: added[item.id] ?? 0,
      );
      if (row != null) rows.add(row);
    }
  }

  rows.sort(_alphabetically);

  final lowStockCount = kind == ItemKind.chemical
      ? chemicals.where((item) => item.stockState != StockState.healthy).length
      : apparatus.where((item) => item.stockState != StockState.healthy).length;

  return MonthlyReport(
    kind: kind,
    month: month,
    rows: rows,
    events: events,
    lowStockCount: lowStockCount,
  );
}

ReportRow? _rowFor({
  required String id,
  required String name,
  required String subtitle,
  required String unit,
  required double quantity,
  required double used,
  required double added,
}) {
  final usedTotal = _round2(used);
  final addedTotal = _round2(added);
  if (usedTotal <= 0 && addedTotal <= 0) return null;
  final left = _round2(quantity);
  final nowHave = _round2(left + usedTotal);
  return ReportRow(
    id: id,
    name: name,
    subtitle: subtitle,
    unit: unit,
    weHave: _round2(nowHave - addedTotal),
    added: addedTotal,
    nowHave: nowHave,
    used: usedTotal,
    left: left,
  );
}

/// People read a shelf by name, and A–Z is the order they expect. Digits and
/// punctuation sort before letters, which puts "2,4-Dinitrophenylhydrazine"
/// first — the same place a paper inventory would put it.
int _alphabetically(ReportRow a, ReportRow b) {
  final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  if (byName != 0) return byName;
  return a.name.compareTo(b.name);
}
