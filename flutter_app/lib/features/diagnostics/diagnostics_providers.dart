import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import 'domain/diagnostics.dart';

export 'domain/diagnostics.dart';

/// Opt-in flag; off until the person turns it on in settings.
const diagnosticsEnabledKey = 'diagnostics.enabled';

/// Stored reports (JSON list), newest first.
const diagnosticsReportsKey = 'diagnostics.reports';

class DiagnosticsState {
  const DiagnosticsState({
    this.enabled = false,
    this.ready = false,
    this.reports = const [],
  });

  final bool enabled;

  /// Preferences have been read; until then [enabled] is a placeholder.
  final bool ready;
  final List<DiagnosticReport> reports;

  DiagnosticsState copyWith({
    bool? enabled,
    bool? ready,
    List<DiagnosticReport>? reports,
  }) => DiagnosticsState(
    enabled: enabled ?? this.enabled,
    ready: ready ?? this.ready,
    reports: reports ?? this.reports,
  );
}

final diagnosticsProvider =
    NotifierProvider<DiagnosticsController, DiagnosticsState>(
      DiagnosticsController.new,
    );

/// Keeps the opt-in flag and the scrubbed reports on the phone (OBS-01).
///
/// Nothing is uploaded anywhere: sharing is a manual action from settings.
/// A remote sink can be added once a service and its privacy terms have
/// been chosen; the scrubbing and retention here apply to it as well.
class DiagnosticsController extends Notifier<DiagnosticsState> {
  /// Overridable clock for tests.
  DateTime get clock => DateTime.now();

  /// Overridable in tests; the real value comes from the CI build.
  String get appBuild => AppConfig.build;

  String get platform =>
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

  Future<void>? _loading;

  @override
  DiagnosticsState build() {
    _loading = _restore();
    return const DiagnosticsState();
  }

  Future<void> _restore() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!ref.mounted) return;
      final reports = pruneDiagnostics(
        decodeDiagnostics(preferences.getString(diagnosticsReportsKey)),
        clock,
      );
      state = DiagnosticsState(
        enabled: preferences.getBool(diagnosticsEnabledKey) ?? false,
        ready: true,
        reports: reports,
      );
    } catch (_) {
      if (ref.mounted) state = const DiagnosticsState(ready: true);
    }
  }

  Future<void> setEnabled(bool enabled) async {
    await _loading;
    if (!ref.mounted) return;
    state = state.copyWith(enabled: enabled);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(diagnosticsEnabledKey, enabled);
    } catch (_) {
      // The switch still works for this session.
    }
  }

  /// Words that must never appear in a stored report: everything a person
  /// typed about their lab, plus the account e-mail.
  List<String> _sensitiveWords() {
    final inventory = ref.read(inventoryProvider);
    final email = ref.read(authProvider).user?.email;
    return [
      if (email != null) email,
      for (final item in inventory.chemicals) ...[
        item.name,
        item.notes,
        ?item.supplier,
        ?item.casNumber,
        ?item.location,
        ?item.barcode,
      ],
      for (final item in inventory.apparatus) ...[
        item.name,
        item.notes,
        ?item.serialNumber,
        ?item.assignedTo,
        ?item.location,
      ],
      for (final log in inventory.logs) log.note,
    ];
  }

  /// Records an error if diagnostics are on. Safe to call from error
  /// handlers: it never throws.
  Future<void> record(
    Object error, {
    StackTrace? stack,
    DiagnosticKind kind = DiagnosticKind.handled,
    String context = '',
  }) async {
    try {
      await _loading;
      if (!ref.mounted || !state.enabled) return;
      final scrubber = DiagnosticsScrubber(_sensitiveWords());
      final now = clock;
      final report = DiagnosticReport(
        id: '${now.microsecondsSinceEpoch}',
        at: now,
        kind: kind,
        message: scrubber.scrub(error.toString()),
        stack: stack == null ? '' : scrubber.scrubStack(stack.toString()),
        context: scrubber.scrub(context),
        appBuild: appBuild,
        platform: platform,
      );
      final reports = pruneDiagnostics([report, ...state.reports], now);
      state = state.copyWith(reports: reports);
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        diagnosticsReportsKey,
        encodeDiagnostics(reports),
      );
    } catch (_) {
      // A failing crash reporter must never take the app down with it.
    }
  }

  /// Records a Flutter framework error (build/layout/paint/gesture).
  Future<void> recordFlutterError(FlutterErrorDetails details) => record(
    details.exceptionAsString(),
    stack: details.stack,
    kind: DiagnosticKind.flutter,
    context: details.context?.toDescription() ?? '',
  );

  Future<void> clear() async {
    await _loading;
    if (!ref.mounted) return;
    state = state.copyWith(reports: const []);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(diagnosticsReportsKey);
    } catch (_) {
      // Already gone from memory; the next successful write replaces it.
    }
  }

  /// Everything currently stored, as pretty JSON for sharing.
  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'app': 'Lab Wizard',
    'build': appBuild,
    'platform': platform,
    'exported_at': clock.toUtc().toIso8601String(),
    'retention_days': diagnosticsRetention.inDays,
    'reports': [for (final report in state.reports) report.toJson()],
  });
}

/// Routes framework and uncaught errors into the diagnostics store while
/// keeping Flutter's default console output. Call once at start-up.
void installDiagnosticsHooks(ProviderContainer container) {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousOnError?.call(details);
    unawaited(
      container.read(diagnosticsProvider.notifier).recordFlutterError(details),
    );
  };
  final previousDispatcherHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(
      container
          .read(diagnosticsProvider.notifier)
          .record(error, stack: stack, kind: DiagnosticKind.dart),
    );
    // Report handled: the app keeps running unless a previous handler said
    // otherwise (there is none by default).
    return previousDispatcherHandler?.call(error, stack) ?? true;
  };
}
