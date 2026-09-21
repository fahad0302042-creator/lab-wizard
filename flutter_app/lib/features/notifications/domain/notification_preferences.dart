import 'dart:convert';

/// What the user wants to be told about, and when (NOTIFY-01). Stored on the
/// device only; the web app is not involved.
class NotificationPreferences {
  const NotificationPreferences({
    this.enabled = false,
    this.lowStock = true,
    this.expiry = true,
    this.expiryDays = 30,
    this.returns = true,
    this.service = true,
    this.serviceDays = 14,
    this.syncProblems = true,
    this.weeklySummary = false,
    this.summaryWeekday = DateTime.monday,
    this.summaryHour = 9,
    this.reminderHour = 9,
  });

  /// Master switch. Nothing is shown or scheduled while this is off.
  final bool enabled;

  /// Low and empty stock (NOTIFY-02).
  final bool lowStock;

  /// Expired and soon-expiring chemicals (NOTIFY-02).
  final bool expiry;

  /// How many days before the expiry date the warning starts.
  final int expiryDays;

  /// Loans past their due date (NOTIFY-03).
  final bool returns;

  /// Maintenance / calibration due or overdue (NOTIFY-03).
  final bool service;

  /// How many days before a task is due the warning starts.
  final int serviceDays;

  /// Changes that failed to sync (NOTIFY-04).
  final bool syncProblems;

  /// One digest per week (NOTIFY-04).
  final bool weeklySummary;

  /// 1 = Monday … 7 = Sunday, matching [DateTime.weekday].
  final int summaryWeekday;

  /// Hour of the day (0–23) for the weekly summary.
  final int summaryHour;

  /// Hour of the day (0–23) at which date-based reminders fire.
  final int reminderHour;

  static const expiryDayOptions = [7, 14, 30, 60, 90];
  static const serviceDayOptions = [3, 7, 14, 30];
  static const hourOptions = [7, 8, 9, 10, 12, 14, 17, 18, 20];

  /// Whether any individual alert kind is switched on.
  bool get anyKind =>
      lowStock || expiry || returns || service || syncProblems || weeklySummary;

  NotificationPreferences copyWith({
    bool? enabled,
    bool? lowStock,
    bool? expiry,
    int? expiryDays,
    bool? returns,
    bool? service,
    int? serviceDays,
    bool? syncProblems,
    bool? weeklySummary,
    int? summaryWeekday,
    int? summaryHour,
    int? reminderHour,
  }) => NotificationPreferences(
    enabled: enabled ?? this.enabled,
    lowStock: lowStock ?? this.lowStock,
    expiry: expiry ?? this.expiry,
    expiryDays: expiryDays ?? this.expiryDays,
    returns: returns ?? this.returns,
    service: service ?? this.service,
    serviceDays: serviceDays ?? this.serviceDays,
    syncProblems: syncProblems ?? this.syncProblems,
    weeklySummary: weeklySummary ?? this.weeklySummary,
    summaryWeekday: summaryWeekday ?? this.summaryWeekday,
    summaryHour: summaryHour ?? this.summaryHour,
    reminderHour: reminderHour ?? this.reminderHour,
  );

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'low_stock': lowStock,
    'expiry': expiry,
    'expiry_days': expiryDays,
    'returns': returns,
    'service': service,
    'service_days': serviceDays,
    'sync_problems': syncProblems,
    'weekly_summary': weeklySummary,
    'summary_weekday': summaryWeekday,
    'summary_hour': summaryHour,
    'reminder_hour': reminderHour,
  };

  factory NotificationPreferences.fromMap(Map<String, dynamic> map) {
    const defaults = NotificationPreferences();
    bool flag(String key, bool fallback) =>
        map[key] is bool ? map[key] as bool : fallback;
    int number(String key, int fallback, {int min = 0, int max = 365}) {
      final value = map[key];
      if (value is! num) return fallback;
      final rounded = value.round();
      return rounded < min || rounded > max ? fallback : rounded;
    }

    return NotificationPreferences(
      enabled: flag('enabled', defaults.enabled),
      lowStock: flag('low_stock', defaults.lowStock),
      expiry: flag('expiry', defaults.expiry),
      expiryDays: number('expiry_days', defaults.expiryDays, min: 1),
      returns: flag('returns', defaults.returns),
      service: flag('service', defaults.service),
      serviceDays: number('service_days', defaults.serviceDays, min: 1),
      syncProblems: flag('sync_problems', defaults.syncProblems),
      weeklySummary: flag('weekly_summary', defaults.weeklySummary),
      summaryWeekday: number(
        'summary_weekday',
        defaults.summaryWeekday,
        min: DateTime.monday,
        max: DateTime.sunday,
      ),
      summaryHour: number('summary_hour', defaults.summaryHour, max: 23),
      reminderHour: number('reminder_hour', defaults.reminderHour, max: 23),
    );
  }

  String encode() => jsonEncode(toMap());

  static NotificationPreferences decode(String? source) {
    if (source == null || source.isEmpty)
      return const NotificationPreferences();
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map) {
        return NotificationPreferences.fromMap(
          Map<String, dynamic>.from(decoded),
        );
      }
    } on FormatException {
      // Corrupt preference blob: fall back to defaults below.
    }
    return const NotificationPreferences();
  }
}

/// Short weekday names indexed by [DateTime.weekday].
const weekdayNames = {
  DateTime.monday: 'Monday',
  DateTime.tuesday: 'Tuesday',
  DateTime.wednesday: 'Wednesday',
  DateTime.thursday: 'Thursday',
  DateTime.friday: 'Friday',
  DateTime.saturday: 'Saturday',
  DateTime.sunday: 'Sunday',
};

/// "9:00" style label for an hour of the day.
String hourLabel(int hour) => '${hour.toString().padLeft(2, '0')}:00';
