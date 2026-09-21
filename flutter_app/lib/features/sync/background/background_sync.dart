import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' show DartPluginRegistrant, IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:supabase_flutter/supabase_flutter.dart'
    show FlutterAuthClientOptions, Supabase;
import 'package:workmanager/workmanager.dart';

import '../../../core/config/app_config.dart';
import '../../../core/database/local_database.dart';
import '../../inventory/data/inventory_repository.dart';
import '../data/incremental_sync.dart';

/// Background sync (SYNC-03).
///
/// Two Android WorkManager jobs keep the device current while the app is
/// not being used:
///
/// * a periodic job (every 1–24 hours, user's choice) that sends queued
///   changes and downloads what changed on the server;
/// * a one-off "flush" job, scheduled when the app goes to the background
///   with queued changes, that runs as soon as the network is back.
///
/// A WorkManager job runs in its own isolate. If the app's main isolate is
/// still alive (the app is open or was recently used), the job hands the
/// work to it through [BackgroundSyncBridge] instead of doing it itself:
/// the main isolate holds the live Supabase session, and two isolates
/// refreshing the same session would sign the user out (refresh tokens
/// are single use). Only when nobody answers does the job start its own
/// Supabase client from the persisted session.

/// Task names handed to WorkManager.
abstract final class BackgroundSyncTasks {
  static const periodicUnique = 'lab-wizard-periodic-sync';
  static const periodic = 'lab_wizard.periodic_sync';
  static const flushUnique = 'lab-wizard-outbox-flush';
  static const flush = 'lab_wizard.outbox_flush';

  static String label(String task) =>
      task == flush ? 'send queued changes' : 'periodic sync';
}

/// User-facing settings for the background job.
class BackgroundSyncPreferences {
  const BackgroundSyncPreferences({
    this.enabled = true,
    this.unmeteredOnly = false,
    this.everyHours = 1,
  });

  final bool enabled;

  /// Wi-Fi (unmetered) only; mobile data is skipped.
  final bool unmeteredOnly;

  /// Periodic frequency. WorkManager never runs more often than every 15
  /// minutes and treats the value as a minimum.
  final int everyHours;

  static const hourOptions = [1, 3, 6, 12, 24];

  BackgroundSyncPreferences copyWith({
    bool? enabled,
    bool? unmeteredOnly,
    int? everyHours,
  }) => BackgroundSyncPreferences(
    enabled: enabled ?? this.enabled,
    unmeteredOnly: unmeteredOnly ?? this.unmeteredOnly,
    everyHours: everyHours ?? this.everyHours,
  );

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'unmetered_only': unmeteredOnly,
    'every_hours': everyHours,
  };

  String encode() => jsonEncode(toMap());

  static BackgroundSyncPreferences decode(String? source) {
    const defaults = BackgroundSyncPreferences();
    if (source == null || source.isEmpty) return defaults;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return defaults;
      final hours = decoded['every_hours'];
      return BackgroundSyncPreferences(
        enabled: decoded['enabled'] is bool
            ? decoded['enabled'] as bool
            : defaults.enabled,
        unmeteredOnly: decoded['unmetered_only'] is bool
            ? decoded['unmetered_only'] as bool
            : defaults.unmeteredOnly,
        everyHours: hours is num && hourOptions.contains(hours.round())
            ? hours.round()
            : defaults.everyHours,
      );
    } on FormatException {
      return defaults;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is BackgroundSyncPreferences &&
      other.enabled == enabled &&
      other.unmeteredOnly == unmeteredOnly &&
      other.everyHours == everyHours;

  @override
  int get hashCode => Object.hash(enabled, unmeteredOnly, everyHours);
}

/// Registers and cancels the platform jobs. Tests use [RecordingScheduler].
abstract class BackgroundScheduler {
  /// Makes sure the periodic job exists with the given settings.
  Future<void> ensurePeriodic(BackgroundSyncPreferences preferences);

  /// Runs the outbox flush once, as soon as the constraints allow.
  Future<void> scheduleFlush(BackgroundSyncPreferences preferences);

  Future<void> cancelAll();
}

/// WorkManager-backed scheduler. Every call is guarded: where the plugin is
/// unavailable (tests, desktop) the app simply has no background sync.
class WorkmanagerScheduler implements BackgroundScheduler {
  WorkmanagerScheduler({Workmanager? workmanager})
    : _workmanager = workmanager ?? Workmanager();

  final Workmanager _workmanager;
  Future<void>? _initializing;

  Future<void> _initialize() => _initializing ??= _workmanager.initialize(
    backgroundSyncDispatcher,
    isInDebugMode: false,
  );

  Constraints _constraints(BackgroundSyncPreferences preferences) =>
      Constraints(
        networkType: preferences.unmeteredOnly
            ? NetworkType.unmetered
            : NetworkType.connected,
        requiresBatteryNotLow: true,
      );

  @override
  Future<void> ensurePeriodic(BackgroundSyncPreferences preferences) =>
      _guard(() async {
        await _initialize();
        // `update` keeps the current schedule and only applies the new
        // frequency and constraints, so calling this on every start does
        // not push the next run further away.
        await _workmanager.registerPeriodicTask(
          BackgroundSyncTasks.periodicUnique,
          BackgroundSyncTasks.periodic,
          frequency: Duration(hours: preferences.everyHours),
          constraints: _constraints(preferences),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
          backoffPolicy: BackoffPolicy.exponential,
          backoffPolicyDelay: const Duration(minutes: 15),
        );
      });

  @override
  Future<void> scheduleFlush(BackgroundSyncPreferences preferences) =>
      _guard(() async {
        await _initialize();
        await _workmanager.registerOneOffTask(
          BackgroundSyncTasks.flushUnique,
          BackgroundSyncTasks.flush,
          constraints: _constraints(preferences),
          existingWorkPolicy: ExistingWorkPolicy.replace,
          backoffPolicy: BackoffPolicy.exponential,
          backoffPolicyDelay: const Duration(minutes: 2),
        );
      });

  @override
  Future<void> cancelAll() => _guard(() async {
    await _initialize();
    await _workmanager.cancelByUniqueName(BackgroundSyncTasks.periodicUnique);
    await _workmanager.cancelByUniqueName(BackgroundSyncTasks.flushUnique);
  });

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('background sync scheduling unavailable: $error');
    }
  }
}

/// In-memory scheduler for tests.
class RecordingScheduler implements BackgroundScheduler {
  final periodic = <BackgroundSyncPreferences>[];
  final flushes = <BackgroundSyncPreferences>[];
  int cancels = 0;

  @override
  Future<void> ensurePeriodic(BackgroundSyncPreferences preferences) async =>
      periodic.add(preferences);

  @override
  Future<void> scheduleFlush(BackgroundSyncPreferences preferences) async =>
      flushes.add(preferences);

  @override
  Future<void> cancelAll() async => cancels++;
}

/// A request from the background isolate to the main isolate.
class BackgroundSyncRequest {
  const BackgroundSyncRequest({required this.task, required this.reply});

  final String task;
  final SendPort reply;

  static const _taskKey = 'task';
  static const _replyKey = 'reply';

  Map<String, Object> toMessage() => {_taskKey: task, _replyKey: reply};

  static BackgroundSyncRequest? fromMessage(Object? message) {
    if (message is! Map) return null;
    final task = message[_taskKey];
    final reply = message[_replyKey];
    if (task is! String || reply is! SendPort) return null;
    return BackgroundSyncRequest(task: task, reply: reply);
  }
}

/// Hands background work to the main isolate when it is alive.
///
/// The main isolate registers a port under [portName]. A background isolate
/// looks the port up, sends a [BackgroundSyncRequest] and waits for
/// [ack] followed by the result. No ack within [ackTimeout] means the
/// registration is stale (the isolate died without cleaning up), and the
/// caller does the work itself.
class BackgroundSyncBridge {
  const BackgroundSyncBridge();

  static const portName = 'lab_wizard.background_sync';
  static const ack = '__ack__';
  static const ackTimeout = Duration(seconds: 10);
  static const resultTimeout = Duration(minutes: 8);

  /// Main isolate: starts answering requests. Returns a handle that stops
  /// answering and removes the registration.
  BackgroundSyncListener listen(Future<String> Function(String task) handler) =>
      BackgroundSyncListener._(handler);

  /// Background isolate: asks the main isolate to run [task]. Returns null
  /// when no live main isolate answered.
  Future<String?> delegate(String task) async {
    final target = IsolateNameServer.lookupPortByName(portName);
    if (target == null) return null;
    final replies = ReceivePort();
    final queue = StreamIterator<Object?>(replies);
    try {
      target.send(
        BackgroundSyncRequest(task: task, reply: replies.sendPort).toMessage(),
      );
      final acked = await queue.moveNext().timeout(
        ackTimeout,
        onTimeout: () => false,
      );
      if (!acked || queue.current != ack) return null;
      final answered = await queue.moveNext().timeout(
        resultTimeout,
        onTimeout: () => false,
      );
      return answered ? queue.current?.toString() : 'timed out';
    } finally {
      await queue.cancel();
      replies.close();
    }
  }
}

/// Active registration of the main isolate; see [BackgroundSyncBridge].
class BackgroundSyncListener {
  BackgroundSyncListener._(this._handler) {
    _subscription = _port.listen(_onMessage);
    register();
  }

  final Future<String> Function(String task) _handler;
  final _port = ReceivePort();
  late final StreamSubscription<Object?> _subscription;

  /// (Re)publishes the port. Safe to call repeatedly.
  void register() {
    IsolateNameServer.removePortNameMapping(BackgroundSyncBridge.portName);
    IsolateNameServer.registerPortWithName(
      _port.sendPort,
      BackgroundSyncBridge.portName,
    );
  }

  /// Withdraws the port so a background job does not wait on an isolate
  /// that is about to go away. [register] undoes this.
  void unregister() {
    IsolateNameServer.removePortNameMapping(BackgroundSyncBridge.portName);
  }

  Future<void> _onMessage(Object? message) async {
    final request = BackgroundSyncRequest.fromMessage(message);
    if (request == null) return;
    request.reply.send(BackgroundSyncBridge.ack);
    String result;
    try {
      result = await _handler(request.task);
    } catch (_) {
      result = 'failed';
    }
    request.reply.send(result);
  }

  Future<void> dispose() async {
    unregister();
    await _subscription.cancel();
    _port.close();
  }
}

/// What the last background run did; stored in `sync_meta` by whichever
/// isolate ran it and read by the UI.
class BackgroundSyncStatus {
  const BackgroundSyncStatus({
    this.lastRunAt,
    this.lastResult,
    this.lastError,
    this.lastTask,
  });

  final DateTime? lastRunAt;
  final String? lastResult;
  final String? lastError;
  final String? lastTask;

  bool get failed => lastResult == 'failed';

  static const lastRunKey = 'background_last_run_at';
  static const lastResultKey = 'background_last_result';
  static const lastErrorKey = 'background_last_error';
  static const lastTaskKey = 'background_last_task';

  static Future<BackgroundSyncStatus> read(
    LocalDatabase local,
    String userId,
  ) async {
    final meta = await local.allMeta(userId);
    final error = meta[lastErrorKey] ?? '';
    return BackgroundSyncStatus(
      lastRunAt: DateTime.tryParse(meta[lastRunKey] ?? ''),
      lastResult: meta[lastResultKey],
      lastError: error.isEmpty ? null : error,
      lastTask: meta[lastTaskKey],
    );
  }
}

/// One background run. The actual work is injected so the same bookkeeping
/// serves the main isolate (which syncs through its controller) and the
/// standalone background isolate (which syncs through a repository).
class BackgroundSyncJob {
  BackgroundSyncJob({
    required this.local,
    required this.userId,
    required this.work,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LocalDatabase local;
  final String userId;

  /// Performs the sync for [task] and returns a one-line summary. Throwing
  /// records a failure.
  final Future<String> Function(String task) work;
  final DateTime Function() _clock;

  /// Runs the task and records when it ran and how it went.
  Future<String> run(String task) async {
    final startedAt = _clock();
    String result;
    String error = '';
    try {
      result = await work(task);
    } catch (failure) {
      result = 'failed';
      error = failure.toString();
    }
    await local.setMeta(
      userId,
      BackgroundSyncStatus.lastTaskKey,
      BackgroundSyncTasks.label(task),
    );
    await local.setMeta(
      userId,
      BackgroundSyncStatus.lastRunKey,
      startedAt.toIso8601String(),
    );
    await local.setMeta(userId, BackgroundSyncStatus.lastResultKey, result);
    await local.setMeta(userId, BackgroundSyncStatus.lastErrorKey, error);
    return result;
  }

  /// One line describing a run. A flush that leaves changes waiting counts
  /// as a failure so the status card says so.
  static String summarize({
    required String task,
    required int sent,
    required int failed,
    required int waiting,
    SyncReport? report,
  }) {
    final parts = <String>[
      if (sent > 0) '$sent change${sent == 1 ? '' : 's'} sent',
      if (failed > 0) '$failed need${failed == 1 ? 's' : ''} attention',
    ];
    if (task == BackgroundSyncTasks.flush) {
      if (waiting > 0) {
        throw StateError(
          '$waiting change${waiting == 1 ? '' : 's'} still waiting',
        );
      }
      return parts.isEmpty ? 'nothing to send' : parts.join(' · ');
    }
    parts.add(switch (report) {
      null => 'downloaded',
      SyncReport(mode: SyncMode.incremental, fetched: 0, removed: 0) =>
        'no new changes',
      SyncReport(mode: SyncMode.incremental) =>
        '${report.fetched} updated, ${report.removed} removed',
      _ => 'full download, ${report.fetched} rows',
    });
    return parts.join(' · ');
  }

  /// Standalone work: send the outbox, then (periodic task only) download
  /// changes.
  static Future<String> Function(String task) repositoryWork(
    InventoryRepository repository,
    LocalDatabase local,
    String userId,
  ) => (task) async {
    final before = (await local.pendingOperations(userId)).length;
    await repository.syncPending(userId);
    final remaining = await local.pendingOperations(userId);
    final failed = remaining.where((operation) => operation.isFailed).length;
    SyncReport? report;
    if (task != BackgroundSyncTasks.flush) {
      report = (await repository.refresh(userId)).syncReport;
    }
    return summarize(
      task: task,
      sent: before - remaining.length,
      failed: failed,
      waiting: remaining.length - failed,
      report: report,
    );
  };
}

/// Entry point WorkManager calls in a fresh background isolate.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      final result = await runBackgroundSyncTask(task);
      // A failed run asks WorkManager to retry with backoff; anything else
      // (done, nothing to do, handed to the app) is complete.
      return result != 'failed';
    } catch (error) {
      debugPrint('background sync failed: $error');
      return false;
    }
  });
}

bool _supabaseReady = false;

/// Runs [task]: through the main isolate when it is alive, otherwise with a
/// Supabase client of its own built from the persisted session. Returns
/// the result line, or null when there was nothing to do.
Future<String?> runBackgroundSyncTask(
  String task, {
  BackgroundSyncBridge bridge = const BackgroundSyncBridge(),
}) async {
  final delegated = await bridge.delegate(task);
  if (delegated != null) return delegated;
  if (!AppConfig.hasSupabase) return null;
  if (!_supabaseReady) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
    _supabaseReady = true;
  }
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return null;
  final local = LocalDatabase();
  try {
    final repository = InventoryRepository(local: local, remote: client);
    final job = BackgroundSyncJob(
      local: local,
      userId: user.id,
      work: BackgroundSyncJob.repositoryWork(repository, local, user.id),
    );
    return await job.run(task);
  } finally {
    await local.close();
  }
}
