import 'package:intl/intl.dart';

import 'models.dart';

/// What happened to an apparatus at one point in time (GEAR-04).
enum ApparatusEventKind {
  consume('used'),
  restock('restocked'),
  breakage('damaged'),
  undo('undone'),
  checkout('checked out'),
  returned('returned'),
  scheduled('scheduled'),
  completed('completed');

  const ApparatusEventKind(this.label);

  final String label;
}

/// One line of the unified apparatus timeline: stock changes, undo notes,
/// loans, returns and maintenance / calibration tasks in one order.
class ApparatusEvent {
  const ApparatusEvent({
    required this.kind,
    required this.time,
    required this.title,
    required this.sourceId,
    this.detail = '',
    this.person = '',
  });

  final ApparatusEventKind kind;
  final DateTime time;
  final String title;
  final String detail;
  final String person;

  /// Id of the log, reversal, checkout or service the event came from.
  final String sourceId;

  /// Stable key such as `checkout-c1` or `completed-s2`.
  String get key => '${kind.name}-$sourceId';
}

/// Builds the timeline of one apparatus, newest first. Partial returns are
/// folded into the loan they belong to; a loan appears once when it starts
/// and once more when it is closed.
List<ApparatusEvent> buildApparatusHistory({
  required String apparatusId,
  Iterable<ConsumptionLog> logs = const [],
  Iterable<InventoryReversal> reversals = const [],
  Iterable<ApparatusCheckout> checkouts = const [],
  Iterable<ApparatusService> services = const [],
}) {
  final events = <ApparatusEvent>[
    for (final log in logs)
      if (log.itemId == apparatusId && log.itemType == ItemKind.apparatus)
        ApparatusEvent(
          kind: switch (log.action) {
            InventoryAction.consume => ApparatusEventKind.consume,
            InventoryAction.restock => ApparatusEventKind.restock,
            InventoryAction.breakage => ApparatusEventKind.breakage,
          },
          time: log.loggedAt,
          title: '${_verb(log.action)} ${formatQuantity(log.amount)} pcs',
          detail: log.note,
          sourceId: log.id,
        ),
    for (final reversal in reversals)
      if (reversal.itemId == apparatusId &&
          reversal.itemType == ItemKind.apparatus)
        ApparatusEvent(
          kind: ApparatusEventKind.undo,
          time: reversal.reversedAt,
          title:
              'Undid ${_verb(reversal.action).toLowerCase()} '
              '${formatQuantity(reversal.amount)} pcs',
          detail: [
            if (reversal.originalNote.isNotEmpty) reversal.originalNote,
            if (reversal.reason.isNotEmpty) reversal.reason,
          ].join(' · '),
          sourceId: reversal.id,
        ),
    for (final checkout in checkouts)
      if (checkout.apparatusId == apparatusId) ...[
        ApparatusEvent(
          kind: ApparatusEventKind.checkout,
          time: checkout.checkedOutAt,
          title:
              'Checked out ${formatQuantity(checkout.quantity)} pcs'
              '${checkout.person.isEmpty ? '' : ' to ${checkout.person}'}',
          detail: [
            if (checkout.dueAt != null)
              'due ${DateFormat('d MMM yyyy').format(checkout.dueAt!)}',
            if (checkout.note.isNotEmpty) checkout.note,
          ].join(' · '),
          person: checkout.person,
          sourceId: checkout.id,
        ),
        if (checkout.returnedAt != null)
          ApparatusEvent(
            kind: ApparatusEventKind.returned,
            time: checkout.returnedAt!,
            title:
                'Returned ${formatQuantity(checkout.returnedQuantity)} pcs'
                '${checkout.person.isEmpty ? '' : ' from ${checkout.person}'}',
            detail: [
              if (checkout.dueAt != null &&
                  checkout.returnedAt!.isAfter(checkout.dueAt!))
                'late',
              if (checkout.returnNote.isNotEmpty) checkout.returnNote,
            ].join(' · '),
            person: checkout.person,
            sourceId: checkout.id,
          ),
      ],
    for (final service in services)
      if (service.apparatusId == apparatusId) ...[
        ApparatusEvent(
          kind: ApparatusEventKind.scheduled,
          time: service.createdAt,
          title: 'Scheduled ${service.displayTitle.toLowerCase()}',
          detail: [
            if (service.title.isNotEmpty) service.kind.label.toLowerCase(),
            if (service.dueAt != null)
              'due ${DateFormat('d MMM yyyy').format(service.dueAt!)}',
            if (service.isOpen && service.note.isNotEmpty) service.note,
          ].join(' · '),
          sourceId: service.id,
        ),
        if (service.completedAt != null)
          ApparatusEvent(
            kind: ApparatusEventKind.completed,
            time: service.completedAt!,
            title:
                '${service.displayTitle} done'
                '${service.result.isEmpty ? '' : ' · ${service.result}'}',
            detail: [
              if (service.title.isNotEmpty) service.kind.label.toLowerCase(),
              if (service.performedBy.isNotEmpty) 'by ${service.performedBy}',
              if (service.dueAt != null &&
                  service.completedAt!.isAfter(service.dueAt!))
                'late',
              if (service.note.isNotEmpty) service.note,
            ].join(' · '),
            person: service.performedBy,
            sourceId: service.id,
          ),
      ],
  ]..sort((a, b) => b.time.compareTo(a.time));
  return events;
}

String _verb(InventoryAction action) => switch (action) {
  InventoryAction.consume => 'Used',
  InventoryAction.restock => 'Restocked',
  InventoryAction.breakage => 'Damaged',
};

/// Totals shown above the timeline and in the shared report.
class ApparatusHistorySummary {
  const ApparatusHistorySummary({
    required this.events,
    required this.damaged,
    required this.loans,
    required this.openLoans,
    required this.lateReturns,
    required this.completedTasks,
    required this.openTasks,
    this.lastCalibration,
    this.lastMaintenance,
    this.nextDue,
  });

  factory ApparatusHistorySummary.of(
    List<ApparatusEvent> events, {
    required Iterable<ApparatusCheckout> checkouts,
    required Iterable<ApparatusService> services,
    required String apparatusId,
  }) {
    final loans = checkouts.where((c) => c.apparatusId == apparatusId);
    final tasks = services.where((s) => s.apparatusId == apparatusId);
    DateTime? lastOf(ServiceKind kind) {
      DateTime? last;
      for (final task in tasks) {
        final done = task.completedAt;
        if (task.kind != kind || done == null) continue;
        if (last == null || done.isAfter(last)) last = done;
      }
      return last;
    }

    DateTime? nextDue;
    for (final task in tasks) {
      final due = task.dueAt;
      if (!task.isOpen || due == null) continue;
      if (nextDue == null || due.isBefore(nextDue)) nextDue = due;
    }
    return ApparatusHistorySummary(
      events: events.length,
      damaged: events
          .where((e) => e.kind == ApparatusEventKind.breakage)
          .length,
      loans: loans.length,
      openLoans: loans.where((c) => c.isOpen).length,
      lateReturns: loans
          .where(
            (c) =>
                c.returnedAt != null &&
                c.dueAt != null &&
                c.returnedAt!.isAfter(c.dueAt!),
          )
          .length,
      completedTasks: tasks.where((t) => t.isDone).length,
      openTasks: tasks.where((t) => t.isOpen).length,
      lastCalibration: lastOf(ServiceKind.calibration),
      lastMaintenance: lastOf(ServiceKind.maintenance),
      nextDue: nextDue,
    );
  }

  final int events;
  final int damaged;
  final int loans;
  final int openLoans;
  final int lateReturns;
  final int completedTasks;
  final int openTasks;
  final DateTime? lastCalibration;
  final DateTime? lastMaintenance;
  final DateTime? nextDue;
}

/// Plain-text report of the whole timeline, safe to share as a file. Plain
/// text (not CSV) so nothing can be interpreted as a formula.
String buildApparatusHistoryReport({
  required Apparatus item,
  required List<ApparatusEvent> events,
  required ApparatusHistorySummary summary,
  DateTime? now,
}) {
  final stamp = DateFormat('yyyy-MM-dd HH:mm');
  final date = DateFormat('yyyy-MM-dd');
  final buffer = StringBuffer()
    ..writeln('Lab Wizard — apparatus history')
    ..writeln('Item: ${item.name}')
    ..writeln('Category: ${item.category}')
    ..writeln('In stock: ${formatQuantity(item.quantity)} pcs');
  final serial = item.serialNumber;
  if (serial != null && serial.isNotEmpty) buffer.writeln('Serial: $serial');
  final condition = item.condition;
  if (condition != null && condition.isNotEmpty) {
    buffer.writeln('Condition: $condition');
  }
  buffer
    ..writeln('Generated: ${stamp.format(now ?? DateTime.now())}')
    ..writeln()
    ..writeln('Summary')
    ..writeln('- events: ${summary.events}')
    ..writeln('- damage entries: ${summary.damaged}')
    ..writeln(
      '- loans: ${summary.loans} (${summary.openLoans} open, '
      '${summary.lateReturns} returned late)',
    )
    ..writeln(
      '- tasks: ${summary.completedTasks} completed, ${summary.openTasks} open',
    );
  final lastCalibration = summary.lastCalibration;
  if (lastCalibration != null) {
    buffer.writeln('- last calibration: ${date.format(lastCalibration)}');
  }
  final lastMaintenance = summary.lastMaintenance;
  if (lastMaintenance != null) {
    buffer.writeln('- last maintenance: ${date.format(lastMaintenance)}');
  }
  final nextDue = summary.nextDue;
  if (nextDue != null) buffer.writeln('- next due: ${date.format(nextDue)}');
  buffer
    ..writeln()
    ..writeln('Timeline (newest first)');
  if (events.isEmpty) buffer.writeln('- no activity yet');
  for (final event in events) {
    buffer.writeln(
      '- ${stamp.format(event.time)} | ${event.kind.label} | ${event.title}'
      '${event.detail.isEmpty ? '' : ' | ${event.detail}'}',
    );
  }
  return buffer.toString();
}
