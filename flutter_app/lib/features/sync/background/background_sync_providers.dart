import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/providers.dart';
import 'background_sync.dart';

/// Persisted settings for SYNC-03.
final backgroundSyncPreferencesProvider =
    NotifierProvider<
      BackgroundSyncPreferencesController,
      BackgroundSyncPreferences
    >(BackgroundSyncPreferencesController.new);

class BackgroundSyncPreferencesController
    extends Notifier<BackgroundSyncPreferences> {
  static const storageKey = 'background_sync_preferences';

  Future<void>? _restored;

  /// Completes once the saved settings have been loaded, so scheduling
  /// never acts on the defaults by mistake.
  Future<void> get ready => _restored ??= _restore();

  @override
  BackgroundSyncPreferences build() {
    _restored ??= _restore();
    return const BackgroundSyncPreferences();
  }

  Future<void> _restore() async {
    try {
      final store = await SharedPreferences.getInstance();
      final saved = store.getString(storageKey);
      if (saved != null) state = BackgroundSyncPreferences.decode(saved);
    } catch (_) {
      // Keep the defaults when storage is unavailable.
    }
  }

  Future<void> update(
    BackgroundSyncPreferences Function(BackgroundSyncPreferences current)
    change,
  ) async {
    state = change(state);
    final store = await SharedPreferences.getInstance();
    await store.setString(storageKey, state.encode());
  }
}

/// Platform job scheduler; tests swap in a [RecordingScheduler].
final backgroundSchedulerProvider = Provider<BackgroundScheduler>(
  (ref) => WorkmanagerScheduler(),
);

/// Network change events; tests inject a controlled stream. Under
/// `flutter test` the plugin channel is absent, so the default is silent.
final connectivityChangesProvider =
    Provider<Stream<List<ConnectivityResult>> Function()>((ref) {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        return () => const Stream.empty();
      }
      return () => Connectivity().onConnectivityChanged;
    });

/// Whether the main isolate answers background isolates (off in tests
/// that do not want a live port).
final backgroundSyncBridgeProvider = Provider<BackgroundSyncBridge?>(
  (ref) => const BackgroundSyncBridge(),
);

class BackgroundSyncState {
  const BackgroundSyncState({
    this.status = const BackgroundSyncStatus(),
    this.lastTrigger,
    this.lastTriggeredAt,
  });

  /// Outcome of the most recent background run for the signed-in user.
  final BackgroundSyncStatus status;

  /// Why the last automatic foreground sync ran: `resume`, `connectivity`
  /// or `background job`.
  final String? lastTrigger;
  final DateTime? lastTriggeredAt;

  BackgroundSyncState copyWith({
    BackgroundSyncStatus? status,
    String? lastTrigger,
    DateTime? lastTriggeredAt,
  }) => BackgroundSyncState(
    status: status ?? this.status,
    lastTrigger: lastTrigger ?? this.lastTrigger,
    lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
  );
}

final backgroundSyncCoordinatorProvider =
    NotifierProvider<BackgroundSyncCoordinator, BackgroundSyncState>(
      BackgroundSyncCoordinator.new,
    );

/// Keeps the device in sync without the user asking (SYNC-03):
///
/// * registers or cancels the WorkManager jobs as the settings and the
///   sign-in state change;
/// * syncs when the app comes back to the foreground or the network
///   returns while it is open;
/// * schedules the one-off flush when the app goes to the background with
///   queued changes;
/// * answers background isolates through [BackgroundSyncBridge] so a job
///   that fires while the app process is alive runs on the live session.
class BackgroundSyncCoordinator extends Notifier<BackgroundSyncState>
    with WidgetsBindingObserver {
  /// A resume within this window of the last download does not sync again.
  static const resumeGap = Duration(minutes: 2);

  /// Overridable clock for tests.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  BackgroundSyncListener? _listener;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  bool _wasOffline = false;
  BackgroundSyncPreferences? _appliedPreferences;
  bool? _appliedSignedIn;

  BackgroundScheduler get _scheduler => ref.read(backgroundSchedulerProvider);

  @override
  BackgroundSyncState build() {
    WidgetsBinding.instance.addObserver(this);
    try {
      _listener = ref
          .read(backgroundSyncBridgeProvider)
          ?.listen(handleBackgroundRequest);
    } catch (_) {
      _listener = null; // No isolate name server here; jobs run standalone.
    }
    _listenToConnectivity();
    ref.listen(backgroundSyncPreferencesProvider, (_, next) {
      unawaited(_applySchedule(next));
    });
    ref.listen(authProvider.select((auth) => auth.phase), (_, phase) {
      if (phase == AuthPhase.signedIn || phase == AuthPhase.signedOut) {
        unawaited(_applySchedule(ref.read(backgroundSyncPreferencesProvider)));
      }
    });
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      unawaited(_connectivity?.cancel());
      unawaited(_listener?.dispose());
    });
    return const BackgroundSyncState();
  }

  /// Called once the user is signed in and the inventory is loading.
  Future<void> start() async {
    await ref.read(backgroundSyncPreferencesProvider.notifier).ready;
    await _applySchedule(ref.read(backgroundSyncPreferencesProvider));
    await refreshStatus();
  }

  /// Re-reads the last background run from the local database.
  Future<void> refreshStatus() async {
    final userId = _signedInUserId;
    if (userId == null) return;
    try {
      final status = await BackgroundSyncStatus.read(
        ref.read(localDatabaseProvider),
        userId,
      );
      state = state.copyWith(status: status);
    } catch (_) {
      // The card simply keeps the previous status.
    }
  }

  String? get _signedInUserId {
    final auth = ref.read(authProvider);
    return auth.phase == AuthPhase.signedIn ? auth.user?.id : null;
  }

  Future<void> _applySchedule(BackgroundSyncPreferences preferences) async {
    final signedIn = _signedInUserId != null;
    if (_appliedPreferences == preferences && _appliedSignedIn == signedIn) {
      return;
    }
    _appliedPreferences = preferences;
    _appliedSignedIn = signedIn;
    if (signedIn && preferences.enabled) {
      await _scheduler.ensurePeriodic(preferences);
    } else {
      await _scheduler.cancelAll();
    }
  }

  void _listenToConnectivity() {
    try {
      _connectivity = ref.read(connectivityChangesProvider)().listen((results) {
        final offline =
            results.isEmpty ||
            results.every((result) => result == ConnectivityResult.none);
        if (_wasOffline && !offline) unawaited(foregroundSync('connectivity'));
        _wasOffline = offline;
      }, onError: (Object _) {});
    } catch (_) {
      // No connectivity plugin here (tests, desktop): resume still syncs.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    unawaited(handleLifecycle(lifecycle));
  }

  @visibleForTesting
  Future<void> handleLifecycle(AppLifecycleState lifecycle) async {
    switch (lifecycle) {
      case AppLifecycleState.resumed:
        _listener?.register();
        await refreshStatus();
        await foregroundSync('resume');
      case AppLifecycleState.paused:
        await _scheduleFlushIfQueued();
      case AppLifecycleState.detached:
        _listener?.unregister();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  /// Syncs now if the app is signed in and idle. A `resume` shortly after
  /// a download is skipped unless something is queued. Returns whether a
  /// sync ran.
  Future<bool> foregroundSync(String reason) async {
    if (_signedInUserId == null) return false;
    final inventory = ref.read(inventoryProvider);
    if (inventory.loading || inventory.refreshing) return false;
    if (inventory.lastUpdated == null) return false;
    final syncedAt = inventory.lastSyncedAt;
    if (reason == 'resume' &&
        inventory.pendingCount == 0 &&
        syncedAt != null &&
        now().difference(syncedAt) < resumeGap) {
      return false;
    }
    state = state.copyWith(lastTrigger: reason, lastTriggeredAt: now());
    await ref.read(inventoryProvider.notifier).refresh();
    return true;
  }

  Future<void> _scheduleFlushIfQueued() async {
    final preferences = ref.read(backgroundSyncPreferencesProvider);
    if (!preferences.enabled || _signedInUserId == null) return;
    final inventory = ref.read(inventoryProvider);
    if (inventory.pendingCount - inventory.failedCount <= 0) return;
    await _scheduler.scheduleFlush(preferences);
  }

  /// Runs a background job's work on the live session and records the
  /// outcome the same way a standalone run would.
  Future<String> handleBackgroundRequest(String task) async {
    final userId = _signedInUserId;
    if (userId == null) return 'nobody signed in';
    final job = BackgroundSyncJob(
      local: ref.read(localDatabaseProvider),
      userId: userId,
      clock: now,
      work: _workOnLiveSession,
    );
    final result = await job.run(task);
    await refreshStatus();
    return result;
  }

  Future<String> _workOnLiveSession(String task) async {
    final controller = ref.read(inventoryProvider.notifier);
    var inventory = ref.read(inventoryProvider);
    if (inventory.loading || inventory.refreshing) {
      return 'skipped · a sync was already running';
    }
    final before = inventory.pendingCount;
    state = state.copyWith(
      lastTrigger: 'background job',
      lastTriggeredAt: now(),
    );
    if (inventory.lastUpdated == null) {
      final userId = _signedInUserId;
      if (userId == null) return 'nobody signed in';
      await controller.bootstrap(userId);
    } else {
      await controller.refresh();
    }
    inventory = ref.read(inventoryProvider);
    final error = inventory.error;
    if (error != null) throw StateError(error);
    final failed = inventory.failedCount;
    return BackgroundSyncJob.summarize(
      task: task,
      sent: before - inventory.pendingCount,
      failed: failed,
      waiting: inventory.pendingCount - failed,
      report: inventory.syncReport,
    );
  }
}
