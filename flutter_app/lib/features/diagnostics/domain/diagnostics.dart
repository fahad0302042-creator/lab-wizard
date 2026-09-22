import 'dart:convert';

/// Crash diagnostics (OBS-01) are opt-in, stay on the phone and are scrubbed
/// before they are stored, so a report can be shared without leaking what
/// is on the shelves or who uses the app.

/// Reports older than this are dropped when a new one arrives.
const diagnosticsRetention = Duration(days: 14);

/// Newest reports kept; older ones are dropped first.
const diagnosticsLimit = 30;

/// Stack traces are cut after this many lines; the top is what matters.
const diagnosticsStackLines = 40;

enum DiagnosticKind {
  /// A Flutter framework error (build, layout, paint, gesture).
  flutter('Flutter error'),

  /// An uncaught Dart error from an async task or isolate.
  dart('Uncaught error'),

  /// Something the app caught itself and chose to record.
  handled('Handled error');

  const DiagnosticKind(this.label);

  final String label;

  static DiagnosticKind parse(String? name) => DiagnosticKind.values.firstWhere(
    (value) => value.name == name,
    orElse: () => DiagnosticKind.handled,
  );
}

class DiagnosticReport {
  const DiagnosticReport({
    required this.id,
    required this.at,
    required this.kind,
    required this.message,
    required this.stack,
    required this.context,
    required this.appBuild,
    required this.platform,
  });

  factory DiagnosticReport.fromJson(Map<String, dynamic> json) =>
      DiagnosticReport(
        id: json['id'] as String,
        at: DateTime.parse(json['at'] as String),
        kind: DiagnosticKind.parse(json['kind'] as String?),
        message: json['message'] as String? ?? '',
        stack: json['stack'] as String? ?? '',
        context: json['context'] as String? ?? '',
        appBuild: json['app_build'] as String? ?? '',
        platform: json['platform'] as String? ?? '',
      );

  final String id;
  final DateTime at;
  final DiagnosticKind kind;

  /// Scrubbed error message.
  final String message;

  /// Scrubbed, truncated stack trace.
  final String stack;

  /// Where it happened ("while building InventoryScreen"), scrubbed.
  final String context;

  /// App build name (from the CI build) or "dev".
  final String appBuild;

  /// Operating system version only; no device identifiers.
  final String platform;

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.toUtc().toIso8601String(),
    'kind': kind.name,
    'message': message,
    'stack': stack,
    'context': context,
    'app_build': appBuild,
    'platform': platform,
  };

  /// First line of the message, for lists.
  String get headline {
    final line = message
        .split('\n')
        .firstWhere((part) => part.trim().isNotEmpty, orElse: () => kind.label);
    return line.length > 140 ? '${line.substring(0, 139)}…' : line;
  }
}

String encodeDiagnostics(List<DiagnosticReport> reports) =>
    jsonEncode([for (final report in reports) report.toJson()]);

List<DiagnosticReport> decodeDiagnostics(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final entry in decoded)
        if (entry is Map)
          DiagnosticReport.fromJson(Map<String, dynamic>.from(entry)),
    ];
  } catch (_) {
    return const [];
  }
}

/// Applies the retention policy: newest first, at most [diagnosticsLimit]
/// entries, nothing older than [diagnosticsRetention].
List<DiagnosticReport> pruneDiagnostics(
  Iterable<DiagnosticReport> reports,
  DateTime now,
) {
  final cutoff = now.subtract(diagnosticsRetention);
  final kept = reports.where((report) => report.at.isAfter(cutoff)).toList()
    ..sort((a, b) => b.at.compareTo(a.at));
  return kept.take(diagnosticsLimit).toList(growable: false);
}

/// Removes personal and inventory data from free text before it is stored.
///
/// [sensitive] holds the words that are known to be private on this phone:
/// item names, notes, suppliers, locations, people, codes, the account
/// e-mail. Each occurrence becomes `[redacted]`. On top of that, e-mail
/// addresses, bearer tokens / JWTs, URL query values, and long digit runs
/// (barcodes, phone numbers) are replaced by pattern. Package paths, class
/// names and line numbers are kept so a trace stays useful.
class DiagnosticsScrubber {
  DiagnosticsScrubber(Iterable<String> sensitive)
    : _sensitive = _prepare(sensitive);

  final List<RegExp> _sensitive;

  static final _email = RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+');
  static final _bearer = RegExp(r'Bearer\s+[A-Za-z0-9._~+/-]+=*');
  static final _jwt = RegExp(
    r'\b[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b',
  );
  static final _queryValue = RegExp(r'([?&][\w-]+=)[^&\s]+');
  static final _longDigits = RegExp(r'\b\d{8,}\b');

  static List<RegExp> _prepare(Iterable<String> words) {
    final unique = <String>{};
    for (final word in words) {
      final trimmed = word.trim();
      // One- or two-letter words would redact half the alphabet.
      if (trimmed.length >= 3) unique.add(trimmed);
    }
    final ordered = unique.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return [
      for (final word in ordered)
        RegExp(RegExp.escape(word), caseSensitive: false),
    ];
  }

  String scrub(String text) {
    var out = text;
    for (final pattern in _sensitive) {
      out = out.replaceAll(pattern, '[redacted]');
    }
    out = out.replaceAll(_bearer, 'Bearer [redacted]');
    out = out.replaceAll(_jwt, '[token]');
    out = out.replaceAll(_email, '[email]');
    out = out.replaceAllMapped(_queryValue, (m) => '${m[1]}[redacted]');
    out = out.replaceAll(_longDigits, '[digits]');
    return out;
  }

  /// Keeps the top of a stack trace and scrubs it.
  String scrubStack(String stack) {
    final lines = stack.split('\n');
    final kept = lines.take(diagnosticsStackLines).toList();
    if (lines.length > kept.length) {
      kept.add('… ${lines.length - kept.length} more frames');
    }
    return scrub(kept.join('\n'));
  }
}
