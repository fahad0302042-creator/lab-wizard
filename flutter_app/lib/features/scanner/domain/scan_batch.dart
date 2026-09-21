import 'scan_resolver.dart';

/// What happened to a code that was added to a [ScanBatch].
enum ScanBatchOutcome { added, duplicate, unknown }

/// One recognised item inside a batch, with how often its label was read.
class ScanBatchEntry {
  const ScanBatchEntry({
    required this.match,
    required this.count,
    required this.firstAt,
    required this.lastAt,
  });

  final ScanMatch match;
  final int count;
  final DateTime firstAt;
  final DateTime lastAt;

  String get key => '${match.kind.name}:${match.id}';

  ScanBatchEntry _again(DateTime at) =>
      ScanBatchEntry(match: match, count: count + 1, firstAt: firstAt, lastAt: at);
}

/// A continuous scanning session (SCAN-02): labels are collected without
/// leaving the camera, the same label is counted instead of listed twice, and
/// codes that match nothing are kept for the summary.
class ScanBatch {
  const ScanBatch({
    this.entries = const [],
    this.unknown = const {},
    this.startedAt,
  });

  /// Recognised items in the order they were first scanned.
  final List<ScanBatchEntry> entries;

  /// Unrecognised payloads and how often each was read.
  final Map<String, int> unknown;

  final DateTime? startedAt;

  bool get isEmpty => entries.isEmpty && unknown.isEmpty;
  bool get isNotEmpty => !isEmpty;

  int get itemCount => entries.length;
  int get unknownCount => unknown.values.fold(0, (sum, count) => sum + count);
  int get scanCount =>
      entries.fold(0, (sum, entry) => sum + entry.count) + unknownCount;

  /// Number of labels read more than once.
  int get duplicateCount =>
      entries.fold(0, (sum, entry) => sum + entry.count - 1) +
      unknown.values.fold(0, (sum, count) => sum + count - 1);

  /// Adds one camera read. [match] is null when nothing carries the code.
  (ScanBatch, ScanBatchOutcome) add(
    String raw,
    ScanMatch? match, {
    required DateTime at,
  }) {
    final started = startedAt ?? at;
    if (match == null) {
      final code = raw.trim();
      return (
        ScanBatch(
          entries: entries,
          unknown: {...unknown, code: (unknown[code] ?? 0) + 1},
          startedAt: started,
        ),
        ScanBatchOutcome.unknown,
      );
    }
    final key = '${match.kind.name}:${match.id}';
    final index = entries.indexWhere((entry) => entry.key == key);
    if (index >= 0) {
      final updated = [...entries];
      updated[index] = entries[index]._again(at);
      return (
        ScanBatch(entries: updated, unknown: unknown, startedAt: started),
        ScanBatchOutcome.duplicate,
      );
    }
    return (
      ScanBatch(
        entries: [
          ...entries,
          ScanBatchEntry(match: match, count: 1, firstAt: at, lastAt: at),
        ],
        unknown: unknown,
        startedAt: started,
      ),
      ScanBatchOutcome.added,
    );
  }

  /// Short status line such as "3 items · 5 scans · 1 unknown".
  String get summaryLine {
    final parts = [
      '$itemCount item${itemCount == 1 ? '' : 's'}',
      '$scanCount scan${scanCount == 1 ? '' : 's'}',
      if (unknown.isNotEmpty) '$unknownCount unknown',
    ];
    return parts.join(' · ');
  }
}
