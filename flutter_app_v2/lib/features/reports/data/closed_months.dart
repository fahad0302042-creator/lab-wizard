import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../inventory/domain/models.dart';
import '../domain/monthly_report.dart';

/// Months that have been signed off, with the numbers frozen at that moment.
///
/// Once a report is printed and filed, editing an old entry must not quietly
/// change the sheet on the wall. Closing a month keeps a copy of what was
/// reported; the app then shows that copy instead of recalculating.
///
/// Stored on the device, not the database: this is a bookkeeping promise about
/// what was handed in, not a fact about the chemicals, and it deliberately
/// survives a reinstall only as long as the phone does.
class ClosedMonth {
  const ClosedMonth({
    required this.monthKey,
    required this.closedAt,
    required this.reports,
    required this.events,
    required this.lowStock,
  });

  /// `yyyy-MM`.
  final String monthKey;
  final DateTime closedAt;

  /// One entry per shelf, exactly as shown when it was closed.
  final Map<String, List<ClosedRow>> reports;

  /// The summary numbers that sat above the table, frozen with it.
  final Map<String, int> events;
  final Map<String, int> lowStock;

  Map<String, dynamic> toJson() => {
    'month': monthKey,
    'closed_at': closedAt.toIso8601String(),
    'reports': {
      for (final entry in reports.entries)
        entry.key: entry.value.map((row) => row.toJson()).toList(),
    },
    'events': events,
    'low_stock': lowStock,
  };

  factory ClosedMonth.fromJson(Map<String, dynamic> json) => ClosedMonth(
    monthKey: json['month'] as String,
    closedAt:
        DateTime.tryParse(json['closed_at'] as String? ?? '') ??
        DateTime.now(),
    reports: {
      for (final entry in (json['reports'] as Map).entries)
        entry.key as String: (entry.value as List)
            .map(
              (row) => ClosedRow.fromJson(
                Map<String, dynamic>.from(row as Map),
              ),
            )
            .toList(),
    },
    events: {
      for (final entry in ((json['events'] ?? const {}) as Map).entries)
        entry.key as String: entry.value as int,
    },
    lowStock: {
      for (final entry in ((json['low_stock'] ?? const {}) as Map).entries)
        entry.key as String: entry.value as int,
    },
  );

  static String keyFor(DateTime month) =>
      DateFormat('yyyy-MM').format(month);
}

/// A frozen copy of one row. Deliberately plain numbers and strings so it reads
/// the same way it did on the day it was closed.
class ClosedRow {
  const ClosedRow({
    required this.name,
    required this.subtitle,
    required this.unit,
    required this.weHave,
    required this.added,
    required this.nowHave,
    required this.used,
    required this.left,
  });

  final String name;
  final String subtitle;
  final String unit;
  final double weHave;
  final double added;
  final double nowHave;
  final double used;
  final double left;

  factory ClosedRow.fromReport(ReportRow row) => ClosedRow(
    name: row.name,
    subtitle: row.subtitle,
    unit: row.unit,
    weHave: row.weHave,
    added: row.added,
    nowHave: row.nowHave,
    used: row.used,
    left: row.left,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'subtitle': subtitle,
    'unit': unit,
    'we_have': weHave,
    'added': added,
    'now_have': nowHave,
    'used': used,
    'left': left,
  };

  factory ClosedRow.fromJson(Map<String, dynamic> json) => ClosedRow(
    name: json['name'] as String? ?? '',
    subtitle: json['subtitle'] as String? ?? '',
    unit: json['unit'] as String? ?? '',
    weHave: (json['we_have'] as num?)?.toDouble() ?? 0,
    added: (json['added'] as num?)?.toDouble() ?? 0,
    nowHave: (json['now_have'] as num?)?.toDouble() ?? 0,
    used: (json['used'] as num?)?.toDouble() ?? 0,
    left: (json['left'] as num?)?.toDouble() ?? 0,
  );
}

final closedMonthsProvider =
    NotifierProvider<ClosedMonthsController, Map<String, ClosedMonth>>(
      ClosedMonthsController.new,
    );

class ClosedMonthsController extends Notifier<Map<String, ClosedMonth>> {
  static const _storageKey = 'closed_months';
  late Future<void> _ready;
  bool _restoreFailed = false;

  @override
  Map<String, ClosedMonth> build() {
    _ready = Future.microtask(_restore);
    return const {};
  }

  Future<void> _restore() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      state = {
        for (final entry in decoded.entries)
          entry.key: ClosedMonth.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          ),
      };
    } catch (_) {
      // Do not overwrite unreadable saved reports with an empty collection.
      _restoreFailed = true;
    }
  }

  Future<void> _persist(Map<String, ClosedMonth> next) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _storageKey,
      jsonEncode({
        for (final entry in next.entries) entry.key: entry.value.toJson(),
      }),
    );
    if (!saved) throw StateError('Could not save closed reports');
  }

  Future<ClosedMonth?> closedFor(DateTime month) async {
    await _ready;
    if (_restoreFailed) throw StateError('Saved reports could not be read');
    return state[ClosedMonth.keyFor(month)];
  }

  bool isClosed(DateTime month) =>
      state.containsKey(ClosedMonth.keyFor(month));

  Future<void> close(List<MonthlyReport> reports, DateTime month) async {
    await _ready;
    if (_restoreFailed) throw StateError('Saved reports could not be read');
    if (state.containsKey(ClosedMonth.keyFor(month))) {
      throw StateError('This month is already closed');
    }
    final closed = ClosedMonth(
      monthKey: ClosedMonth.keyFor(month),
      closedAt: DateTime.now(),
      reports: {
        for (final report in reports)
          report.kind.name: report.rows.map(ClosedRow.fromReport).toList(),
      },
      events: {for (final report in reports) report.kind.name: report.events},
      lowStock: {
        for (final report in reports) report.kind.name: report.lowStockCount,
      },
    );
    final next = {...state, closed.monthKey: closed};
    await _persist(next);
    state = next;
  }

  Future<void> reopen(DateTime month) async {
    await _ready;
    if (_restoreFailed) throw StateError('Saved reports could not be read');
    final key = ClosedMonth.keyFor(month);
    final next = {...state}..remove(key);
    await _persist(next);
    state = next;
  }
}

/// Rebuilds the report from a frozen copy, so a closed month shows exactly what
/// was signed off even if the underlying logs have since been corrected.
MonthlyReport frozenReport(ClosedMonth closed, ItemKind kind, DateTime month) {
  final rows = (closed.reports[kind.name] ?? const <ClosedRow>[]).map(
    (row) => ReportRow(
      id: row.name,
      name: row.name,
      subtitle: row.subtitle,
      unit: row.unit,
      weHave: row.weHave,
      added: row.added,
      nowHave: row.nowHave,
      used: row.used,
      left: row.left,
    ),
  ).toList();
  return MonthlyReport(
    kind: kind,
    month: month,
    rows: rows,
    events: closed.events[kind.name] ?? 0,
    lowStockCount: closed.lowStock[kind.name] ?? 0,
  );
}
