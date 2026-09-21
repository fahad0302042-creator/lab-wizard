import 'package:intl/intl.dart';

import '../../inventory/domain/models.dart';
import 'notification_preferences.dart';

/// Kinds of things the app can warn about. Order = severity, most urgent
/// first.
enum AlertKind {
  empty('out of stock'),
  expired('expired'),
  overdueReturn('overdue return'),
  serviceOverdue('service overdue'),
  syncFailed('sync problem'),
  lowStock('low stock'),
  expiringSoon('expiring soon'),
  serviceDue('service due');

  const AlertKind(this.label);

  final String label;

  /// Kinds that need action now rather than soon.
  bool get urgent => index <= AlertKind.syncFailed.index;

  /// Which notification channel the kind belongs to.
  AlertChannel get channel => switch (this) {
    AlertKind.empty || AlertKind.lowStock => AlertChannel.stock,
    AlertKind.expired || AlertKind.expiringSoon => AlertChannel.expiry,
    AlertKind.overdueReturn ||
    AlertKind.serviceOverdue ||
    AlertKind.serviceDue => AlertChannel.apparatus,
    AlertKind.syncFailed => AlertChannel.sync,
  };
}

/// Android notification channels (one per topic so the user can mute them
/// individually in system settings).
enum AlertChannel {
  stock('lab_wizard_stock', 'Stock levels', 'Low and empty stock'),
  expiry('lab_wizard_expiry', 'Expiry', 'Expired and expiring chemicals'),
  apparatus(
    'lab_wizard_apparatus',
    'Apparatus',
    'Overdue returns, maintenance and calibration',
  ),
  sync('lab_wizard_sync', 'Sync', 'Changes that could not be saved'),
  summary('lab_wizard_summary', 'Weekly summary', 'One digest per week');

  const AlertChannel(this.id, this.name, this.description);

  final String id;
  final String name;
  final String description;
}

/// One thing that needs attention right now.
class AppAlert {
  const AppAlert({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    this.itemKind,
    this.itemId,
  });

  /// Stable across rebuilds, e.g. `lowStock:c1`; used to avoid repeats.
  final String id;
  final AlertKind kind;
  final String title;
  final String body;
  final ItemKind? itemKind;
  final String? itemId;

  /// Payload carried by a system notification so a tap can open the item.
  String get payload {
    if (kind == AlertKind.syncFailed) return 'sync';
    if (itemId == null || itemKind == null) return 'alerts';
    return '${itemKind!.name}:$itemId';
  }

  /// Whether the alert is about the same subject as [other] (same kind and
  /// item), so a refreshed body does not count as a new alert.
  bool sameSubjectAs(AppAlert other) => id == other.id;
}

/// Everything the current data says needs attention, most urgent first
/// (NOTIFY-02/03/04). Pure: no clocks, no platform calls.
List<AppAlert> buildAlerts({
  required NotificationPreferences preferences,
  Iterable<Chemical> chemicals = const [],
  Iterable<Apparatus> apparatus = const [],
  Iterable<ApparatusCheckout> checkouts = const [],
  Iterable<ApparatusService> services = const [],
  Iterable<PendingOperation> outbox = const [],
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final alerts = <AppAlert>[];

  if (preferences.lowStock) {
    for (final item in chemicals) {
      final alert = _stockAlert(
        item.stockState,
        id: item.id,
        kind: ItemKind.chemical,
        name: item.name,
        quantity: item.quantity,
        unit: item.unit,
        threshold: item.lowStockThreshold,
      );
      if (alert != null) alerts.add(alert);
    }
    for (final item in apparatus) {
      final alert = _stockAlert(
        item.stockState,
        id: item.id,
        kind: ItemKind.apparatus,
        name: item.name,
        quantity: item.quantity,
        unit: 'pcs',
        threshold: item.lowStockThreshold,
      );
      if (alert != null) alerts.add(alert);
    }
  }

  if (preferences.expiry) {
    for (final item in chemicals) {
      final expiry = item.expiryDate;
      if (expiry == null) continue;
      final day = DateTime(expiry.year, expiry.month, expiry.day);
      final days = day.difference(today).inDays;
      if (days < 0) {
        alerts.add(
          AppAlert(
            id: 'expired:${item.id}',
            kind: AlertKind.expired,
            title: '${item.name} has expired',
            body: 'Expired ${_daysAgo(-days)} · ${_date(day)}',
            itemKind: ItemKind.chemical,
            itemId: item.id,
          ),
        );
      } else if (days <= preferences.expiryDays) {
        alerts.add(
          AppAlert(
            id: 'expiring:${item.id}',
            kind: AlertKind.expiringSoon,
            title: '${item.name} expires ${_inDays(days)}',
            body: 'Expiry date ${_date(day)}',
            itemKind: ItemKind.chemical,
            itemId: item.id,
          ),
        );
      }
    }
  }

  final apparatusNames = {for (final item in apparatus) item.id: item.name};
  if (preferences.returns) {
    for (final checkout in checkouts) {
      if (!checkout.isOverdue(now: reference)) continue;
      final due = checkout.dueAt!;
      final days = today
          .difference(DateTime(due.year, due.month, due.day))
          .inDays;
      final name = apparatusNames[checkout.apparatusId] ?? 'Apparatus';
      alerts.add(
        AppAlert(
          id: 'overdueReturn:${checkout.id}',
          kind: AlertKind.overdueReturn,
          title:
              '$name not back from '
              '${checkout.person.isEmpty ? 'loan' : checkout.person}',
          body:
              '${formatQuantity(checkout.outstanding)} pcs · '
              '${days <= 0 ? 'was due today' : 'overdue by $days day${days == 1 ? '' : 's'}'}',
          itemKind: ItemKind.apparatus,
          itemId: checkout.apparatusId,
        ),
      );
    }
  }

  if (preferences.service) {
    for (final service in services) {
      final due = service.dueAt;
      if (!service.isOpen || due == null) continue;
      final days = DateTime(
        due.year,
        due.month,
        due.day,
      ).difference(today).inDays;
      final name = apparatusNames[service.apparatusId] ?? 'Apparatus';
      final task = service.displayTitle.toLowerCase();
      if (days < 0) {
        alerts.add(
          AppAlert(
            id: 'serviceOverdue:${service.id}',
            kind: AlertKind.serviceOverdue,
            title: '$name · $task overdue',
            body: 'Was due ${_date(due)} · ${_daysAgo(-days)}',
            itemKind: ItemKind.apparatus,
            itemId: service.apparatusId,
          ),
        );
      } else if (days <= preferences.serviceDays) {
        alerts.add(
          AppAlert(
            id: 'serviceDue:${service.id}',
            kind: AlertKind.serviceDue,
            title: '$name · $task ${_inDays(days)}',
            body: 'Due ${_date(due)}',
            itemKind: ItemKind.apparatus,
            itemId: service.apparatusId,
          ),
        );
      }
    }
  }

  if (preferences.syncProblems) {
    final failed = outbox.where((operation) => operation.isFailed).toList();
    if (failed.isNotEmpty) {
      final more = failed.length > 1 ? ' and ${failed.length - 1} more' : '';
      alerts.add(
        AppAlert(
          id: 'syncFailed',
          kind: AlertKind.syncFailed,
          title:
              '${failed.length} change${failed.length == 1 ? '' : 's'} could '
              'not be saved',
          body: '${failed.first.description}$more — open the sync center',
        ),
      );
    }
  }

  alerts.sort((a, b) {
    final byKind = a.kind.index.compareTo(b.kind.index);
    return byKind != 0 ? byKind : a.title.compareTo(b.title);
  });
  return alerts;
}

AppAlert? _stockAlert(
  StockState state, {
  required String id,
  required ItemKind kind,
  required String name,
  required double quantity,
  required String unit,
  required double threshold,
}) => switch (state) {
  StockState.empty => AppAlert(
    id: 'empty:$id',
    kind: AlertKind.empty,
    title: '$name is out',
    body: 'Nothing left — restock before the next session',
    itemKind: kind,
    itemId: id,
  ),
  StockState.low => AppAlert(
    id: 'low:$id',
    kind: AlertKind.lowStock,
    title: '$name is running low',
    body:
        '${formatQuantity(quantity)} $unit left · warning level '
        '${formatQuantity(threshold)} $unit',
    itemKind: kind,
    itemId: id,
  ),
  StockState.healthy => null,
};

String _date(DateTime day) => DateFormat('d MMM yyyy').format(day);

String _inDays(int days) => switch (days) {
  0 => 'today',
  1 => 'tomorrow',
  _ => 'in $days days',
};

String _daysAgo(int days) => switch (days) {
  0 => 'today',
  1 => 'yesterday',
  _ => '$days days ago',
};

/// One notification the device should fire later, computed from due dates
/// so reminders arrive even while the app is closed.
class PlannedReminder {
  const PlannedReminder({
    required this.key,
    required this.at,
    required this.title,
    required this.body,
    required this.channel,
    this.payload = 'alerts',
    this.weekly = false,
  });

  /// Stable text key; the platform id is derived from it.
  final String key;
  final DateTime at;
  final String title;
  final String body;
  final AlertChannel channel;
  final String payload;

  /// Repeats every week at the same weekday and time.
  final bool weekly;

  /// Deterministic 31-bit id for the platform.
  int get id => notificationIdFor(key);
}

/// Deterministic, positive, 31-bit hash of a reminder key (Android ids are
/// `int`s and must stay stable across launches so they can be replaced).
int notificationIdFor(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}

/// Reminders worth scheduling from the current data (NOTIFY-02/03/04): loan
/// due times, service due dates (early warning + due day), chemical expiry
/// (early warning + expiry day) and the weekly summary. Only future times
/// are returned, soonest first, capped at [limit].
List<PlannedReminder> planReminders({
  required NotificationPreferences preferences,
  Iterable<Chemical> chemicals = const [],
  Iterable<Apparatus> apparatus = const [],
  Iterable<ApparatusCheckout> checkouts = const [],
  Iterable<ApparatusService> services = const [],
  DateTime? now,
  int limit = 60,
}) {
  if (!preferences.enabled) return const [];
  final reference = now ?? DateTime.now();
  final hour = preferences.reminderHour;
  DateTime atHour(DateTime day) =>
      DateTime(day.year, day.month, day.day, hour);
  final planned = <PlannedReminder>[];
  final apparatusNames = {for (final item in apparatus) item.id: item.name};

  if (preferences.returns) {
    for (final checkout in checkouts) {
      final due = checkout.dueAt;
      if (!checkout.isOpen || due == null) continue;
      final name = apparatusNames[checkout.apparatusId] ?? 'Apparatus';
      final who = checkout.person.isEmpty ? '' : ' from ${checkout.person}';
      planned.add(
        PlannedReminder(
          key: 'return:${checkout.id}',
          at: due,
          title: '$name is due back$who',
          body:
              '${formatQuantity(checkout.outstanding)} pcs · checked out '
              '${_date(checkout.checkedOutAt)}',
          channel: AlertChannel.apparatus,
          payload: 'apparatus:${checkout.apparatusId}',
        ),
      );
    }
  }

  if (preferences.service) {
    for (final service in services) {
      final due = service.dueAt;
      if (!service.isOpen || due == null) continue;
      final name = apparatusNames[service.apparatusId] ?? 'Apparatus';
      final task = service.displayTitle.toLowerCase();
      final dueDay = atHour(due);
      final early = dueDay.subtract(Duration(days: preferences.serviceDays));
      planned
        ..add(
          PlannedReminder(
            key: 'service-soon:${service.id}',
            at: early,
            title: '$name · $task in ${preferences.serviceDays} days',
            body: 'Due ${_date(due)}',
            channel: AlertChannel.apparatus,
            payload: 'apparatus:${service.apparatusId}',
          ),
        )
        ..add(
          PlannedReminder(
            key: 'service-due:${service.id}',
            at: dueDay,
            title: '$name · $task due today',
            body: 'Open Lab Wizard to record it when done',
            channel: AlertChannel.apparatus,
            payload: 'apparatus:${service.apparatusId}',
          ),
        );
    }
  }

  if (preferences.expiry) {
    for (final item in chemicals) {
      final expiry = item.expiryDate;
      if (expiry == null) continue;
      final day = atHour(expiry);
      planned
        ..add(
          PlannedReminder(
            key: 'expiry-soon:${item.id}',
            at: day.subtract(Duration(days: preferences.expiryDays)),
            title: '${item.name} expires in ${preferences.expiryDays} days',
            body: 'Expiry date ${_date(expiry)}',
            channel: AlertChannel.expiry,
            payload: 'chemical:${item.id}',
          ),
        )
        ..add(
          PlannedReminder(
            key: 'expiry-day:${item.id}',
            at: day,
            title: '${item.name} expires today',
            body: 'Check the bottle before the next use',
            channel: AlertChannel.expiry,
            payload: 'chemical:${item.id}',
          ),
        );
    }
  }

  final future = planned.where((reminder) => reminder.at.isAfter(reference))
    .toList()
    ..sort((a, b) => a.at.compareTo(b.at));
  final result = future.take(limit).toList();

  if (preferences.weeklySummary) {
    result.add(
      PlannedReminder(
        key: 'weekly-summary',
        at: nextWeeklySlot(
          weekday: preferences.summaryWeekday,
          hour: preferences.summaryHour,
          now: reference,
        ),
        title: 'Your weekly lab summary is ready',
        body: 'Open Lab Wizard for stock, expiry and apparatus highlights',
        channel: AlertChannel.summary,
        payload: 'summary',
        weekly: true,
      ),
    );
  }
  return result;
}

/// Next occurrence of [weekday] at [hour] strictly after [now].
DateTime nextWeeklySlot({
  required int weekday,
  required int hour,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  var candidate = DateTime(
    reference.year,
    reference.month,
    reference.day,
    hour,
  );
  while (candidate.weekday != weekday || !candidate.isAfter(reference)) {
    candidate = DateTime(
      candidate.year,
      candidate.month,
      candidate.day + 1,
      hour,
    );
  }
  return candidate;
}

/// Plain-language digest used by the weekly summary screen and the
/// notification body preview (NOTIFY-04).
String weeklySummaryText({
  required List<AppAlert> alerts,
  required Iterable<ConsumptionLog> logs,
  required int chemicalCount,
  required int apparatusCount,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final weekAgo = reference.subtract(const Duration(days: 7));
  final recent = logs.where((log) => log.loggedAt.isAfter(weekAgo)).toList();
  final used = recent
      .where((log) => log.action == InventoryAction.consume)
      .length;
  final restocked = recent
      .where((log) => log.action == InventoryAction.restock)
      .length;
  final damaged = recent
      .where((log) => log.action == InventoryAction.breakage)
      .length;
  int count(AlertKind kind) => alerts.where((a) => a.kind == kind).length;
  final lines = <String>[
    '$chemicalCount chemicals and $apparatusCount apparatus on the shelves.',
    'This week: $used uses, $restocked restocks, $damaged damage entries.',
    if (count(AlertKind.empty) + count(AlertKind.lowStock) > 0)
      '${count(AlertKind.empty)} out of stock, ${count(AlertKind.lowStock)} running low.',
    if (count(AlertKind.expired) + count(AlertKind.expiringSoon) > 0)
      '${count(AlertKind.expired)} expired, ${count(AlertKind.expiringSoon)} expiring soon.',
    if (count(AlertKind.overdueReturn) > 0)
      '${count(AlertKind.overdueReturn)} overdue return${count(AlertKind.overdueReturn) == 1 ? '' : 's'}.',
    if (count(AlertKind.serviceOverdue) + count(AlertKind.serviceDue) > 0)
      '${count(AlertKind.serviceOverdue)} service tasks overdue, ${count(AlertKind.serviceDue)} due soon.',
    if (alerts.isEmpty) 'Nothing needs attention. Nice.',
  ];
  return lines.join('\n');
}
