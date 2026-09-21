import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/database/local_database.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/sync/background/background_sync.dart';
import 'package:lab_wizard/features/sync/background/background_sync_providers.dart';
import 'package:lab_wizard/features/sync/data/incremental_sync.dart';
import 'package:lab_wizard/features/sync/presentation/background_sync_card.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

final _now = DateTime(2026, 9, 21, 10);

final _user = User.fromJson(<String, dynamic>{
  'id': 'u1',
  'app_metadata': <String, dynamic>{},
  'user_metadata': <String, dynamic>{},
  'aud': 'authenticated',
  'created_at': '2026-01-01T00:00:00Z',
})!;

class _FakeAuth extends AuthController {
  _FakeAuth({this.signedIn = true});

  final bool signedIn;

  @override
  AuthState build() => signedIn
      ? AuthState(phase: AuthPhase.signedIn, user: _user)
      : const AuthState(phase: AuthPhase.signedOut);

  void signOutNow() => state = const AuthState(phase: AuthPhase.signedOut);
}

PendingOperation _operation(String id, {bool failed = false}) =>
    PendingOperation(
      id: id,
      userId: 'u1',
      type: 'inventory_action',
      payload: const {},
      createdAt: _now,
      status: failed ? PendingStatus.failed : PendingStatus.pending,
    );

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed);

  final InventoryState seed;
  int refreshes = 0;
  int bootstraps = 0;

  /// What a refresh leaves behind; defaults to "everything sent".
  InventoryState Function(InventoryState current)? afterRefresh;

  @override
  InventoryState build() => seed;

  /// Test hook: replaces the state the way a repository result would.
  void replaceState(InventoryState Function(InventoryState current) change) =>
      state = change(state);

  @override
  Future<void> bootstrap(String userId) async {
    bootstraps++;
    state = state.copyWith(lastUpdated: _now);
  }

  @override
  Future<void> refresh() async {
    refreshes++;
    state = state.copyWith(refreshing: true);
    await Future<void>.delayed(Duration.zero);
    final change = afterRefresh;
    state = change != null
        ? change(state)
        : state.copyWith(
            outbox: const [],
            refreshing: false,
            lastSyncedAt: _now,
            lastUpdated: _now,
            syncReport: SyncReport(
              mode: SyncMode.incremental,
              finishedAt: _now,
              fetched: 2,
              removed: 1,
            ),
          );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lab-wizard-bg');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  LocalDatabase openLocal() => LocalDatabase(
    factory: databaseFactoryFfi,
    path: p.join(directory.path, 'bg.db'),
  );

  group('preferences', () {
    test('round-trip through JSON', () {
      const preferences = BackgroundSyncPreferences(
        enabled: false,
        unmeteredOnly: true,
        everyHours: 6,
      );
      final restored = BackgroundSyncPreferences.decode(preferences.encode());
      expect(restored, preferences);
    });

    test('fall back to defaults for garbage or unknown values', () {
      expect(
        BackgroundSyncPreferences.decode('not json'),
        const BackgroundSyncPreferences(),
      );
      expect(BackgroundSyncPreferences.decode(null).enabled, isTrue);
      final odd = BackgroundSyncPreferences.decode(
        '{"enabled":"yes","every_hours":5,"unmetered_only":true}',
      );
      expect(odd.enabled, isTrue);
      expect(odd.everyHours, 1);
      expect(odd.unmeteredOnly, isTrue);
    });
  });

  group('summaries', () {
    test('describe what a periodic run did', () {
      expect(
        BackgroundSyncJob.summarize(
          task: BackgroundSyncTasks.periodic,
          sent: 2,
          failed: 0,
          waiting: 0,
          report: SyncReport(
            mode: SyncMode.incremental,
            finishedAt: _now,
            fetched: 3,
            removed: 1,
          ),
        ),
        '2 changes sent · 3 updated, 1 removed',
      );
      expect(
        BackgroundSyncJob.summarize(
          task: BackgroundSyncTasks.periodic,
          sent: 0,
          failed: 1,
          waiting: 0,
          report: SyncReport(mode: SyncMode.incremental, finishedAt: _now),
        ),
        '1 needs attention · no new changes',
      );
      expect(
        BackgroundSyncJob.summarize(
          task: BackgroundSyncTasks.periodic,
          sent: 0,
          failed: 0,
          waiting: 0,
          report: SyncReport(
            mode: SyncMode.full,
            finishedAt: _now,
            fetched: 40,
          ),
        ),
        'full download, 40 rows',
      );
    });

    test('a flush that leaves changes waiting counts as a failure', () {
      expect(
        BackgroundSyncJob.summarize(
          task: BackgroundSyncTasks.flush,
          sent: 0,
          failed: 0,
          waiting: 0,
        ),
        'nothing to send',
      );
      expect(
        BackgroundSyncJob.summarize(
          task: BackgroundSyncTasks.flush,
          sent: 1,
          failed: 0,
          waiting: 0,
        ),
        '1 change sent',
      );
      expect(
        () => BackgroundSyncJob.summarize(
          task: BackgroundSyncTasks.flush,
          sent: 1,
          failed: 0,
          waiting: 2,
        ),
        throwsStateError,
      );
    });
  });

  group('job bookkeeping', () {
    test('records when a run happened and how it went', () async {
      final local = openLocal();
      addTearDown(local.close);
      final job = BackgroundSyncJob(
        local: local,
        userId: 'u1',
        clock: () => _now,
        work: (task) async => 'all good',
      );
      expect(await job.run(BackgroundSyncTasks.periodic), 'all good');
      var status = await BackgroundSyncStatus.read(local, 'u1');
      expect(status.lastRunAt, _now);
      expect(status.lastResult, 'all good');
      expect(status.lastTask, 'periodic sync');
      expect(status.lastError, isNull);
      expect(status.failed, isFalse);

      final failing = BackgroundSyncJob(
        local: local,
        userId: 'u1',
        clock: () => _now.add(const Duration(hours: 1)),
        work: (task) async => throw StateError('server said no'),
      );
      expect(await failing.run(BackgroundSyncTasks.flush), 'failed');
      status = await BackgroundSyncStatus.read(local, 'u1');
      expect(status.failed, isTrue);
      expect(status.lastTask, 'send queued changes');
      expect(status.lastError, contains('server said no'));

      // Another user's status is separate.
      final other = await BackgroundSyncStatus.read(local, 'u2');
      expect(other.lastRunAt, isNull);
    });
  });

  group('coordinator', () {
    late RecordingScheduler scheduler;
    late StreamController<List<ConnectivityResult>> connectivity;
    late _FakeInventory inventory;
    late _FakeAuth auth;
    late LocalDatabase local;

    ProviderContainer makeContainer({
      InventoryState? seed,
      bool signedIn = true,
      BackgroundSyncBridge? bridge = const BackgroundSyncBridge(),
    }) {
      scheduler = RecordingScheduler();
      connectivity = StreamController<List<ConnectivityResult>>.broadcast();
      inventory = _FakeInventory(
        seed ??
            InventoryState(
              lastUpdated: _now,
              lastSyncedAt: _now.subtract(const Duration(hours: 3)),
            ),
      );
      auth = _FakeAuth(signedIn: signedIn);
      local = openLocal();
      final container = ProviderContainer(
        overrides: [
          backgroundSchedulerProvider.overrideWithValue(scheduler),
          connectivityChangesProvider.overrideWithValue(
            () => connectivity.stream,
          ),
          backgroundSyncBridgeProvider.overrideWithValue(bridge),
          inventoryProvider.overrideWith(() => inventory),
          authProvider.overrideWith(() => auth),
          localDatabaseProvider.overrideWithValue(local),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await connectivity.close();
        await local.close();
      });
      container.read(inventoryProvider);
      container.read(backgroundSyncCoordinatorProvider.notifier).now = () =>
          _now;
      return container;
    }

    test(
      'registers the periodic job on start and follows the settings',
      () async {
        final container = makeContainer();
        final coordinator = container.read(
          backgroundSyncCoordinatorProvider.notifier,
        );
        await coordinator.start();
        expect(scheduler.periodic, hasLength(1));
        expect(scheduler.periodic.single.everyHours, 1);
        expect(scheduler.cancels, 0);

        final preferences = container.read(
          backgroundSyncPreferencesProvider.notifier,
        );
        await preferences.update((current) => current.copyWith(enabled: false));
        await Future<void>.delayed(Duration.zero);
        expect(scheduler.cancels, 1);

        await preferences.update(
          (current) => current.copyWith(
            enabled: true,
            everyHours: 6,
            unmeteredOnly: true,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(scheduler.periodic, hasLength(2));
        expect(scheduler.periodic.last.everyHours, 6);
        expect(scheduler.periodic.last.unmeteredOnly, isTrue);

        // The saved settings survive a restart.
        final store = await SharedPreferences.getInstance();
        expect(
          BackgroundSyncPreferences.decode(
            store.getString(BackgroundSyncPreferencesController.storageKey),
          ).everyHours,
          6,
        );
      },
    );

    test('cancels the jobs when the user signs out', () async {
      final container = makeContainer();
      final coordinator = container.read(
        backgroundSyncCoordinatorProvider.notifier,
      );
      await coordinator.start();
      expect(scheduler.periodic, hasLength(1));
      auth.signOutNow();
      await Future<void>.delayed(Duration.zero);
      expect(scheduler.cancels, 1);
    });

    test('syncs on resume unless a download just happened', () async {
      final container = makeContainer();
      final coordinator = container.read(
        backgroundSyncCoordinatorProvider.notifier,
      );
      await coordinator.start();
      await coordinator.handleLifecycle(AppLifecycleState.resumed);
      expect(inventory.refreshes, 1);
      expect(
        container.read(backgroundSyncCoordinatorProvider).lastTrigger,
        'resume',
      );

      // The fake refresh set lastSyncedAt to now: the next resume is quiet.
      await coordinator.handleLifecycle(AppLifecycleState.resumed);
      expect(inventory.refreshes, 1);

      // ...unless something is queued.
      inventory.replaceState(
        (current) => current.copyWith(outbox: [_operation('a')]),
      );
      await coordinator.handleLifecycle(AppLifecycleState.resumed);
      expect(inventory.refreshes, 2);
    });

    test('does not sync before the inventory has loaded', () async {
      final container = makeContainer(seed: const InventoryState());
      final coordinator = container.read(
        backgroundSyncCoordinatorProvider.notifier,
      );
      await coordinator.start();
      expect(await coordinator.foregroundSync('resume'), isFalse);
      expect(inventory.refreshes, 0);
    });

    test('syncs when the connection comes back', () async {
      final container = makeContainer();
      final coordinator = container.read(
        backgroundSyncCoordinatorProvider.notifier,
      );
      await coordinator.start();
      connectivity.add([ConnectivityResult.wifi]);
      await Future<void>.delayed(Duration.zero);
      expect(inventory.refreshes, 0, reason: 'already online: nothing to do');
      connectivity.add([ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);
      connectivity.add([ConnectivityResult.mobile]);
      await Future<void>.delayed(Duration.zero);
      expect(inventory.refreshes, 1);
      expect(
        container.read(backgroundSyncCoordinatorProvider).lastTrigger,
        'connectivity',
      );
    });

    test(
      'schedules a flush when the app is left with queued changes',
      () async {
        final container = makeContainer();
        final coordinator = container.read(
          backgroundSyncCoordinatorProvider.notifier,
        );
        await coordinator.start();
        await coordinator.handleLifecycle(AppLifecycleState.paused);
        expect(scheduler.flushes, isEmpty, reason: 'nothing queued');

        inventory.replaceState(
          (current) => current.copyWith(
            outbox: [_operation('a'), _operation('b', failed: true)],
          ),
        );
        await coordinator.handleLifecycle(AppLifecycleState.paused);
        expect(scheduler.flushes, hasLength(1));

        // Only failed changes left: those wait for the user, not for a job.
        inventory.replaceState(
          (current) =>
              current.copyWith(outbox: [_operation('b', failed: true)]),
        );
        await coordinator.handleLifecycle(AppLifecycleState.paused);
        expect(scheduler.flushes, hasLength(1));

        // Background sync off: no jobs at all.
        await container
            .read(backgroundSyncPreferencesProvider.notifier)
            .update((current) => current.copyWith(enabled: false));
        inventory.replaceState(
          (current) => current.copyWith(outbox: [_operation('a')]),
        );
        await coordinator.handleLifecycle(AppLifecycleState.paused);
        expect(scheduler.flushes, hasLength(1));
      },
    );

    test('answers a background isolate over the bridge', () async {
      final container = makeContainer(
        seed: InventoryState(
          lastUpdated: _now,
          outbox: [_operation('a'), _operation('b')],
        ),
      );
      final coordinator = container.read(
        backgroundSyncCoordinatorProvider.notifier,
      );
      await coordinator.start();

      final result = await runBackgroundSyncTask(BackgroundSyncTasks.periodic);
      expect(result, '2 changes sent · 2 updated, 1 removed');
      expect(inventory.refreshes, 1);
      final status = container.read(backgroundSyncCoordinatorProvider).status;
      expect(status.lastTask, 'periodic sync');
      expect(status.lastResult, '2 changes sent · 2 updated, 1 removed');
      expect(status.lastRunAt, _now);
      expect(
        container.read(backgroundSyncCoordinatorProvider).lastTrigger,
        'background job',
      );
      expect((await BackgroundSyncStatus.read(local, 'u1')).failed, isFalse);
    });

    test('reports a flush that could not send everything', () async {
      final container = makeContainer(
        seed: InventoryState(lastUpdated: _now, outbox: [_operation('a')]),
      );
      inventory.afterRefresh = (current) => current.copyWith(
        refreshing: false,
        error: 'Still offline — your saved copy is available.',
      );
      final coordinator = container.read(
        backgroundSyncCoordinatorProvider.notifier,
      );
      await coordinator.start();
      expect(await runBackgroundSyncTask(BackgroundSyncTasks.flush), 'failed');
      final status = container.read(backgroundSyncCoordinatorProvider).status;
      expect(status.failed, isTrue);
      expect(status.lastError, contains('Still offline'));
    });

    test('tells a background isolate when nobody is signed in', () async {
      final container = makeContainer(signedIn: false);
      container.read(backgroundSyncCoordinatorProvider);
      expect(
        await runBackgroundSyncTask(BackgroundSyncTasks.periodic),
        'nobody signed in',
      );
      expect(scheduler.periodic, isEmpty);
    });

    test('bows out on its own when there is no app to talk to', () async {
      final container = makeContainer(bridge: null);
      container.read(backgroundSyncCoordinatorProvider);
      // No port registered and no Supabase configuration in tests.
      expect(await runBackgroundSyncTask(BackgroundSyncTasks.periodic), isNull);
    });
  });

  group('settings card', () {
    testWidgets('switches and frequency are saved', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backgroundSchedulerProvider.overrideWithValue(RecordingScheduler()),
            connectivityChangesProvider.overrideWithValue(
              () => const Stream.empty(),
            ),
            backgroundSyncBridgeProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: SingleChildScrollView(child: BackgroundSyncCard()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No background run yet.'), findsOneWidget);
      expect(find.textContaining('On · about every hour'), findsOneWidget);

      await tester.tap(find.byKey(const Key('background-sync-frequency')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('every 6 hours').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('On · about every 6 hours'), findsOneWidget);

      await tester.tap(find.byKey(const Key('background-sync-wifi-only')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('On · about every 6 hours on Wi-Fi'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('background-sync-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Off · only when the app is open'), findsOneWidget);
      expect(find.byKey(const Key('background-sync-frequency')), findsNothing);

      final store = await SharedPreferences.getInstance();
      final saved = BackgroundSyncPreferences.decode(
        store.getString(BackgroundSyncPreferencesController.storageKey),
      );
      expect(saved.enabled, isFalse);
      expect(saved.everyHours, 6);
      expect(saved.unmeteredOnly, isTrue);
    });
  });
}
