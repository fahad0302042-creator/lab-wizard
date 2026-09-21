import 'package:intl/intl.dart';

/// Presets offered by the report screen (REPORT-01).
enum ReportRangeKind {
  last7('7 days'),
  last30('30 days'),
  month('month'),
  custom('custom');

  const ReportRangeKind(this.label);

  final String label;
}

/// An inclusive range of local calendar days.
///
/// Everything is decided on local dates, never on instants: a log stamped
/// 23:59 on the last day belongs to the range and one stamped 00:00 the day
/// after does not, regardless of the device's zone or daylight-saving shifts.
class ReportRange {
  ReportRange._({
    required this.kind,
    required DateTime start,
    required DateTime end,
  }) : start = _dateOnly(start),
       end = _dateOnly(end);

  /// Today and the [days] - 1 days before it.
  factory ReportRange.lastDays(int days, {DateTime? today}) {
    assert(days >= 1, 'a range needs at least one day');
    final last = _dateOnly(today ?? DateTime.now());
    return ReportRange._(
      kind: days == 7
          ? ReportRangeKind.last7
          : days == 30
          ? ReportRangeKind.last30
          : ReportRangeKind.custom,
      start: _addDays(last, 1 - days),
      end: last,
    );
  }

  /// One calendar month.
  factory ReportRange.month(int year, int month) {
    final first = DateTime(year, month);
    return ReportRange._(
      kind: ReportRangeKind.month,
      start: first,
      end: DateTime(year, month + 1, 0),
    );
  }

  /// Any two dates, in either order; times are ignored.
  factory ReportRange.custom(DateTime a, DateTime b) {
    final first = _dateOnly(a);
    final second = _dateOnly(b);
    final reversed = second.isBefore(first);
    return ReportRange._(
      kind: ReportRangeKind.custom,
      start: reversed ? second : first,
      end: reversed ? first : second,
    );
  }

  final ReportRangeKind kind;

  /// First day, local midnight.
  final DateTime start;

  /// Last day (inclusive), local midnight.
  final DateTime end;

  /// Local midnight after the last day; handy for "before" comparisons.
  DateTime get endExclusive => _addDays(end, 1);

  /// Number of calendar days, daylight-saving safe.
  int get dayCount =>
      DateTime.utc(
        end.year,
        end.month,
        end.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
      1;

  /// Whether [time] (any zone) falls on one of the range's local days.
  bool contains(DateTime time) {
    final day = _dateOnly(time.toLocal());
    return !day.isBefore(start) && !day.isAfter(end);
  }

  /// Local calendar days of the range, first to last.
  Iterable<DateTime> get days sync* {
    for (var index = 0; index < dayCount; index++) {
      yield _addDays(start, index);
    }
  }

  /// The range of equal length that ends the day before this one starts; a
  /// calendar month compares with the previous calendar month.
  ReportRange get previous {
    if (kind == ReportRangeKind.month) {
      return ReportRange.month(start.year, start.month - 1);
    }
    final previousEnd = _addDays(start, -1);
    return ReportRange._(
      kind: kind,
      start: _addDays(previousEnd, 1 - dayCount),
      end: previousEnd,
    );
  }

  /// The following calendar month, or null for non-month ranges.
  ReportRange? get nextMonth => kind == ReportRangeKind.month
      ? ReportRange.month(start.year, start.month + 1)
      : null;

  /// True when the range is the calendar month that contains [today].
  bool isCurrentMonth({DateTime? today}) {
    final now = today ?? DateTime.now();
    return kind == ReportRangeKind.month &&
        start.year == now.year &&
        start.month == now.month;
  }

  /// Short human label: "last 7 days", "September 2026", "3 – 21 Sep 2026".
  String get label {
    switch (kind) {
      case ReportRangeKind.last7:
        return 'last 7 days';
      case ReportRangeKind.last30:
        return 'last 30 days';
      case ReportRangeKind.month:
        return DateFormat('MMMM yyyy').format(start);
      case ReportRangeKind.custom:
        if (start == end) return DateFormat('d MMM yyyy').format(start);
        if (start.year == end.year && start.month == end.month) {
          return '${start.day} – ${DateFormat('d MMM yyyy').format(end)}';
        }
        if (start.year == end.year) {
          return '${DateFormat('d MMM').format(start)} – '
              '${DateFormat('d MMM yyyy').format(end)}';
        }
        return '${DateFormat('d MMM yyyy').format(start)} – '
            '${DateFormat('d MMM yyyy').format(end)}';
    }
  }

  /// Exact dates for subtitles and file names: "15 Sep – 21 Sep 2026".
  String get dates =>
      '${DateFormat('d MMM').format(start)} – '
      '${DateFormat('d MMM yyyy').format(end)}';

  /// File-name friendly form such as `2026-09-15_2026-09-21`.
  String get fileStem =>
      '${DateFormat('yyyy-MM-dd').format(start)}_'
      '${DateFormat('yyyy-MM-dd').format(end)}';

  @override
  bool operator ==(Object other) =>
      other is ReportRange &&
      other.kind == kind &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);

  @override
  String toString() => 'ReportRange(${kind.name}, $fileStem)';

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// Calendar arithmetic that survives daylight-saving days (adding a
  /// Duration of 24 h would land on 23:00 or 01:00).
  static DateTime _addDays(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day + days);
}

/// One bar of the activity chart: a day, or a run of days for long ranges.
class ReportBucket {
  const ReportBucket({
    required this.start,
    required this.end,
    required this.count,
  });

  /// First local day of the bucket.
  final DateTime start;

  /// Last local day of the bucket (inclusive).
  final DateTime end;

  final int count;

  bool get isSingleDay => start == end;

  /// Axis label: the day of month for daily buckets, "15 Sep" otherwise.
  String get label =>
      isSingleDay ? '${start.day}' : DateFormat('d MMM').format(start);
}

/// Groups timestamps into chart buckets: one per day up to [dailyLimit] days,
/// otherwise runs of seven days counted from the range start.
List<ReportBucket> bucketize(
  ReportRange range,
  Iterable<DateTime> times, {
  int dailyLimit = 62,
}) {
  final span = range.dayCount <= dailyLimit ? 1 : 7;
  final bucketCount = (range.dayCount + span - 1) ~/ span;
  final counts = List<int>.filled(bucketCount, 0);
  final startUtc = DateTime.utc(
    range.start.year,
    range.start.month,
    range.start.day,
  );
  for (final time in times) {
    if (!range.contains(time)) continue;
    final local = time.toLocal();
    final offset = DateTime.utc(
      local.year,
      local.month,
      local.day,
    ).difference(startUtc).inDays;
    counts[offset ~/ span]++;
  }
  return [
    for (var index = 0; index < bucketCount; index++)
      ReportBucket(
        start: ReportRange._addDays(range.start, index * span),
        end: index == bucketCount - 1
            ? range.end
            : ReportRange._addDays(range.start, index * span + span - 1),
        count: counts[index],
      ),
  ];
}

/// Spoken summary of the activity chart for screen readers (A11Y-01): the
/// total, the busiest bucket and how many buckets were empty.
String activityChartSummary(List<ReportBucket> buckets) {
  if (buckets.isEmpty) return 'Activity chart: nothing to show';
  final total = buckets.fold<int>(0, (sum, bucket) => sum + bucket.count);
  if (total == 0) return 'Activity chart: no activity in this range';
  var busiest = buckets.first;
  for (final bucket in buckets) {
    if (bucket.count > busiest.count) busiest = bucket;
  }
  final when = busiest.isSingleDay
      ? DateFormat('d MMMM').format(busiest.start)
      : 'the week of ${DateFormat('d MMMM').format(busiest.start)}';
  final quiet = buckets.where((bucket) => bucket.count == 0).length;
  final unit = buckets.first.isSingleDay ? 'day' : 'week';
  return 'Activity chart: $total action${total == 1 ? '' : 's'} over '
      '${buckets.length} $unit${buckets.length == 1 ? '' : 's'}; '
      'busiest $when with ${busiest.count}'
      '${quiet == 0 ? '' : '; $quiet $unit${quiet == 1 ? '' : 's'} with none'}';
}
