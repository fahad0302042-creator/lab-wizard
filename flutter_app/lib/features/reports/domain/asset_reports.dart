import 'package:intl/intl.dart';

import '../../inventory/domain/models.dart';
import 'report_range.dart';

/// Signed whole days from [today] to [day] on the local calendar.
int daysFromToday(DateTime day, {required DateTime today}) =>
    DateTime.utc(day.year, day.month, day.day)
        .difference(DateTime.utc(today.year, today.month, today.day))
        .inDays;

/// "in 3 days", "today", "2 days ago".
String relativeDays(int days) {
  if (days == 0) return 'today';
  if (days == 1) return 'tomorrow';
  if (days == -1) return 'yesterday';
  return days > 0 ? 'in $days days' : '${-days} days ago';
}

/// One chemical with a date, for the expiry view (REPORT-04).
class ExpiryRow {
  const ExpiryRow({
    required this.chemical,
    required this.state,
    required this.days,
  });

  final Chemical chemical;
  final ExpiryState state;

  /// Days until expiry; negative when already expired.
  final int days;

  String get when =>
      '${DateFormat('d MMM yyyy').format(chemical.expiryDate!)} · '
      '${state == ExpiryState.expired ? 'expired ' : ''}${relativeDays(days)}';
}

class ExpiryReport {
  const ExpiryReport({
    required this.expired,
    required this.expiringSoon,
    required this.later,
    required this.undated,
  });

  final List<ExpiryRow> expired;
  final List<ExpiryRow> expiringSoon;
  final int later;
  final int undated;

  bool get isEmpty => expired.isEmpty && expiringSoon.isEmpty;
}

/// Expired and soon-expiring chemicals (DATA-01 dates), soonest first.
ExpiryReport expiryReport(Iterable<Chemical> chemicals, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final expired = <ExpiryRow>[];
  final soon = <ExpiryRow>[];
  var later = 0;
  var undated = 0;
  for (final chemical in chemicals) {
    final date = chemical.expiryDate;
    if (date == null) {
      undated++;
      continue;
    }
    final state = expiryStateFor(date, now: today);
    final row = ExpiryRow(
      chemical: chemical,
      state: state,
      days: daysFromToday(date, today: today),
    );
    switch (state) {
      case ExpiryState.expired:
        expired.add(row);
      case ExpiryState.expiringSoon:
        soon.add(row);
      case ExpiryState.ok:
        later++;
      case ExpiryState.none:
        undated++;
    }
  }
  int byDate(ExpiryRow a, ExpiryRow b) => a.days.compareTo(b.days);
  expired.sort(byDate);
  soon.sort(byDate);
  return ExpiryReport(
    expired: expired,
    expiringSoon: soon,
    later: later,
    undated: undated,
  );
}

/// Damage recorded for one item inside the report range.
class DamageRow {
  const DamageRow({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.incidents,
    required this.amount,
    required this.lastAt,
  });

  final String itemId;
  final String name;
  final String unit;
  final int incidents;
  final double amount;
  final DateTime lastAt;
}

class DamageReport {
  const DamageReport({required this.rows, required this.range});

  final List<DamageRow> rows;
  final ReportRange range;

  int get incidents => rows.fold(0, (sum, row) => sum + row.incidents);
  bool get isEmpty => rows.isEmpty;
}

/// Breakage entries of [kind] inside [range], grouped per item, most damage
/// first. [nameOf] / [unitOf] resolve items; removed items still count.
DamageReport damageReport(
  ReportRange range,
  Iterable<ConsumptionLog> logs, {
  required ItemKind kind,
  required String Function(String itemId) nameOf,
  required String Function(String itemId) unitOf,
}) {
  final rows = <String, DamageRow>{};
  for (final log in logs) {
    if (log.itemType != kind ||
        log.action != InventoryAction.breakage ||
        !range.contains(log.loggedAt)) {
      continue;
    }
    final current = rows[log.itemId];
    rows[log.itemId] = DamageRow(
      itemId: log.itemId,
      name: nameOf(log.itemId),
      unit: unitOf(log.itemId),
      incidents: (current?.incidents ?? 0) + 1,
      amount: (current?.amount ?? 0) + log.amount,
      lastAt: current == null || log.loggedAt.isAfter(current.lastAt)
          ? log.loggedAt
          : current.lastAt,
    );
  }
  final list = rows.values.toList()
    ..sort((a, b) {
      final byAmount = b.amount.compareTo(a.amount);
      return byAmount != 0 ? byAmount : a.name.compareTo(b.name);
    });
  return DamageReport(rows: list, range: range);
}

/// An open loan that is past its due date (GEAR-02).
class OverdueLoan {
  const OverdueLoan({
    required this.checkout,
    required this.apparatusName,
    required this.daysOverdue,
  });

  final ApparatusCheckout checkout;
  final String apparatusName;
  final int daysOverdue;

  /// "due today", "1 day overdue", "12 days overdue".
  String get when => daysOverdue == 0
      ? 'due today'
      : '$daysOverdue day${daysOverdue == 1 ? '' : 's'} overdue';
}

class LoanReport {
  const LoanReport({required this.overdue, required this.openLoans});

  final List<OverdueLoan> overdue;

  /// All open loans, overdue or not.
  final int openLoans;

  bool get isEmpty => overdue.isEmpty;
}

/// Overdue loans, most overdue first, plus the number of open loans.
LoanReport loanReport(
  Iterable<ApparatusCheckout> checkouts, {
  required String Function(String apparatusId) nameOf,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final overdue = <OverdueLoan>[];
  var open = 0;
  for (final checkout in checkouts) {
    if (!checkout.isOpen) continue;
    open++;
    final due = checkout.dueAt;
    if (due == null || !checkout.isOverdue(now: today)) continue;
    final days = -daysFromToday(due.toLocal(), today: today);
    overdue.add(
      OverdueLoan(
        checkout: checkout,
        apparatusName: nameOf(checkout.apparatusId),
        daysOverdue: days < 0 ? 0 : days,
      ),
    );
  }
  overdue.sort((a, b) => b.daysOverdue.compareTo(a.daysOverdue));
  return LoanReport(overdue: overdue, openLoans: open);
}

/// An open maintenance or calibration task that is due (GEAR-03).
class ServiceRow {
  const ServiceRow({
    required this.service,
    required this.apparatusName,
    required this.days,
  });

  final ApparatusService service;
  final String apparatusName;

  /// Days until due; negative when overdue.
  final int days;

  bool get overdue => days < 0;

  /// "overdue by 3 days", "due today", "due in 5 days".
  String get when {
    if (overdue) return 'overdue by ${-days} day${days == -1 ? '' : 's'}';
    return 'due ${relativeDays(days)}';
  }
}

class ServiceReport {
  const ServiceReport({
    required this.due,
    required this.openTasks,
    required this.completedInRange,
  });

  /// Overdue first, then due within the window.
  final List<ServiceRow> due;
  final int openTasks;
  final int completedInRange;

  bool get isEmpty => due.isEmpty;
}

/// Open tasks that are overdue or due within [soonDays], plus how many were
/// completed inside [range].
ServiceReport serviceReport(
  Iterable<ApparatusService> services, {
  required ReportRange range,
  required String Function(String apparatusId) nameOf,
  DateTime? now,
  int soonDays = 14,
}) {
  final today = now ?? DateTime.now();
  final due = <ServiceRow>[];
  var open = 0;
  var completed = 0;
  for (final service in services) {
    if (service.isDone) {
      if (range.contains(service.completedAt!)) completed++;
      continue;
    }
    open++;
    final when = service.dueAt;
    if (when == null) continue;
    final state = service.dueState(now: today, soonDays: soonDays);
    if (state != ExpiryState.expired && state != ExpiryState.expiringSoon) {
      continue;
    }
    due.add(
      ServiceRow(
        service: service,
        apparatusName: nameOf(service.apparatusId),
        days: daysFromToday(when.toLocal(), today: today),
      ),
    );
  }
  due.sort((a, b) => a.days.compareTo(b.days));
  return ServiceReport(due: due, openTasks: open, completedInRange: completed);
}
