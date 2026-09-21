import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/database/local_database.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/data/inventory_repository.dart';
import 'package:lab_wizard/features/sync/data/incremental_sync.dart';
import 'package:lab_wizard/features/sync/presentation/sync_center_screen.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// In-memory stand-in for PostgREST with the same ordering and filter
/// semantics the real source relies on.
class _FakeSource implements SyncSource {
  _FakeSource() : incremental = true;

  bool incremental;
  final tables = <String, List<Map<String, dynamic>>>{};
  final tombstones = <Map<String, dynamic>>[];
  final missing = <String>{};
  int requests = 0;

  static int _compareIds(Object? a, Object? b) {
    if (a is num && b is num) return a.compareTo(b);
    return a.toString().compareTo(b.toString());
  }

  static int _compare(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
    String column,
  ) {
    final byTime = DateTime.parse(a[column] as String)
        .compareTo(DateTime.parse(b[column] as String));
    return byTime != 0 ? byTime : _compareIds(a['id'], b['id']);
  }

  List<Map<String, dynamic>> _after(
    Iterable<Map<String, dynamic>> rows,
    String column,
    DateTime? after,
    String? afterId,
  ) {
    if (after == null) return rows.toList();
    return rows.where((row) {
      final at = DateTime.parse(row[column] as String);
      if (afterId == null || afterId.isEmpty) return !at.isBefore(after);
      if (at.isAfter(after)) return true;
      if (!at.isAtSameMomentAs(after)) return false;
      final id = row['id'];
      final other = id is num ? num.parse(afterId) : afterId;
      return _compareIds(id, other) > 0;
    }).toList();
  }

  @override
  Future<bool> supportsIncremental() async => incremental;

  @override
  Future<List<Map<String, dynamic>>> changesSince(
    String table, {
    required int limit,
    DateTime? after,
    String? afterId,
  }) async {
    requests++;
    if (missing.contains(table)) throw SyncTableMissing(table);
    final rows = [...?tables[table]]
      ..sort((a, b) => _compare(a, b, 'updated_at'));
    return _after(rows, 'updated_at', after, afterId).take(limit).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> deletionsSince({
    required int limit,
    DateTime? after,
    String? afterId,
  }) async {
    requests++;
    final rows = [...tombstones]..sort((a, b) => _compare(a, b, 'deleted_at'));
    return _after(rows, 'deleted_at', after, afterId).take(limit).toList();
  }

  @override
  Future<Map<String, dynamic>?> latestDeletion() async {
    requests++;
    if (tombstones.isEmpty) return null;
    final rows = [...tombstones]..sort((a, b) => _compare(a, b, 'deleted_at'));
    return rows.last;
  }

  @override
  Future<List<Map<String, dynamic>>> page(
    String table, {
    required String orderBy,
    required int offset,
    required int limit,
  }) async {
    requests++;
    if (missing.contains(table)) throw SyncTableMissing(table);
    final rows = [...?tables[table]]
      ..sort((a, b) => -_compare(a, b, orderBy));
    if (offset >= rows.length) return const [];
    return rows.sublist(
      offset,
      offset + limit > rows.length ? rows.length : offset + limit,
    );
  }

  /// Deletes a row the way the server trigger would: gone + tombstone.
  void delete(String table, String id, DateTime at) {
    tables[table]!.removeWhere((row) => row['id'] == id);
    tombstones.add({
      'id': tombstones.length + 1,
      'user_id': 'u1',
      'table_name': table,
      'row_id': id,
      'deleted_at': at.toUtc().toIso8601String(),
    });
  }
}

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed);

  final InventoryState seed;
  int fullResyncs = 0;

  @override
  InventoryState build() => seed;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> fullResync() async {
    fullResyncs++;
  }
}

final _base = DateTime.utc(2026, 9, 1, 10);

String _iso(DateTime time) => time.toUtc().toIso8601String();

Map<String, dynamic> _chemical(
  String id, {
  String user = 'u1',
  Duration age = Duration.zero,
  double quantity = 10,
  DateTime? updated,
}) => {
  'id': id,
  'user_id': user,
  'name': 'Chem $id',
  'formula': '',
  'unit': 'g',
  'quantity': quantity,
  'initial_quantity': 10,
  'low_stock_threshold': 1,
  'notes': '',
  'qr_code': 'qr-$id',
  'created_at': _iso(_base.subtract(age)),
  'updated_at': _iso(updated ?? _base.subtract(age)),
};

void main() {
  late Directory directory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lab-wizard-sync');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  LocalDatabase openLocal(String name) => LocalDatabase(
    factory: databaseFactoryFfi,
    path: p.join(directory.path, name),
  );

  Future<List<String>> cachedIds(LocalDatabase local, String kind) async =>
      (await local.loadRecords(
        'u1',
        kind,
      )).map((row) => row['id'] as String).toList()..sort();

  group('SyncCursor', () {
    test('round-trips and rejects markers', () {
      final cursor = SyncCursor(at: _base, id: 'abc');
      expect(SyncCursor.decode(cursor.encode())?.id, 'abc');
      expect(SyncCursor.decode(cursor.encode())?.at, _base);
      expect(SyncCursor.decode(IncrementalSync.missingMarker), isNull);
      expect(SyncCursor.decode(null), isNull);
      expect(SyncCursor.decode('nonsense|x'), isNull);
    });
  });

  group('IncrementalSync', () {
    late LocalDatabase local;
    late _FakeSource source;
    late DateTime now;

    setUp(() async {
      local = openLocal('sync.db');
      source = _FakeSource();
      now = _base.add(const Duration(hours: 1));
      source.tables['chemicals'] = [
        for (var i = 0; i < 5; i++)
          _chemical('c$i', age: Duration(minutes: 5 - i)),
      ];
      source.tables['apparatus'] = [];
      source.tables['consumption_logs'] = [];
    });

    tearDown(() => local.close());

    IncrementalSync engine({int pageSize = 2}) => IncrementalSync(
      local: local,
      source: source,
      pageSize: pageSize,
      overlap: Duration.zero,
      clock: () => now,
    );

    test(
      'first run downloads everything in pages and stores cursors',
      () async {
        final report = await engine().run(
          'u1',
          tables: IncrementalSync.tableKinds.keys,
        );
        expect(report.mode, SyncMode.full);
        expect(report.fetched, 5);
        expect(report.pages, greaterThanOrEqualTo(3));
        expect(report.lastFullSyncAt, now);
        expect(await cachedIds(local, 'chemical'), [
          'c0',
          'c1',
          'c2',
          'c3',
          'c4',
        ]);
        final meta = await local.allMeta('u1');
        expect(meta[IncrementalSync.fullSyncKey], now.toIso8601String());
        expect(
          SyncCursor.decode(meta[IncrementalSync.cursorKey('chemical')])?.id,
          'c4',
        );
        // Empty tables get the epoch cursor so nothing depends on the clock.
        expect(
          SyncCursor.decode(meta[IncrementalSync.cursorKey('apparatus')])?.at,
          IncrementalSync.epoch,
        );
        expect(
          SyncCursor.decode(meta[IncrementalSync.deletionsCursorKey])?.at,
          IncrementalSync.epoch,
        );
      },
    );

    test('later runs fetch only changes and apply tombstones', () async {
      final sync = engine();
      await sync.run('u1', tables: IncrementalSync.tableKinds.keys);
      final requestsAfterFull = source.requests;

      now = now.add(const Duration(hours: 1));
      final rows = source.tables['chemicals']!;
      rows.firstWhere((row) => row['id'] == 'c1')
        ..['quantity'] = 3
        ..['updated_at'] = _iso(now.subtract(const Duration(minutes: 10)));
      rows.add(
        _chemical('c9', updated: now.subtract(const Duration(minutes: 5))),
      );
      source.delete(
        'chemicals',
        'c3',
        now.subtract(const Duration(minutes: 3)),
      );
      source.tables['apparatus']!.add({
        'id': 'a1',
        'user_id': 'u1',
        'name': 'Beaker',
        'category': 'glassware',
        'quantity': 2,
        'initial_quantity': 2,
        'low_stock_threshold': 1,
        'notes': '',
        'created_at': _iso(now),
        'updated_at': _iso(now),
      });

      final report = await sync.run(
        'u1',
        tables: IncrementalSync.tableKinds.keys,
      );
      expect(report.mode, SyncMode.incremental);
      expect(report.removed, 1);
      expect(report.fetched, greaterThanOrEqualTo(3));
      expect(report.fetched, lessThanOrEqualTo(4), reason: 'no full reload');
      expect(await cachedIds(local, 'chemical'), [
        'c0',
        'c1',
        'c2',
        'c4',
        'c9',
      ]);
      expect(await cachedIds(local, 'apparatus'), ['a1']);
      final cachedC1 = (await local.loadRecords(
        'u1',
        'chemical',
      )).firstWhere((row) => row['id'] == 'c1');
      expect(cachedC1['quantity'], 3);
      expect(source.requests - requestsAfterFull, lessThan(12));

      final meta = await local.allMeta('u1');
      expect(
        SyncCursor.decode(meta[IncrementalSync.cursorKey('chemical')])?.id,
        'c9',
      );
      expect(
        SyncCursor.decode(meta[IncrementalSync.deletionsCursorKey])?.id,
        '1',
      );

      // Nothing changed: a quiet run touches nothing.
      final quiet = await sync.run(
        'u1',
        tables: IncrementalSync.tableKinds.keys,
      );
      expect(quiet.removed, 0);
      expect(await cachedIds(local, 'chemical'), [
        'c0',
        'c1',
        'c2',
        'c4',
        'c9',
      ]);
    });

    test('keyset paging survives identical timestamps', () async {
      source.tables['chemicals'] = [
        for (var i = 0; i < 7; i++) _chemical('same-$i'),
      ];
      final report = await engine().run('u1', tables: const ['chemicals']);
      expect(report.fetched, 7);
      expect(await local.recordCount('u1', 'chemical'), 7);

      now = now.add(const Duration(minutes: 30));
      source.tables['chemicals']!.addAll([
        for (var i = 7; i < 10; i++) _chemical('same-$i', updated: now),
      ]);
      final next = await engine().run('u1', tables: const ['chemicals']);
      expect(next.mode, SyncMode.incremental);
      expect(await local.recordCount('u1', 'chemical'), 10);
    });

    test('forces a full download when the cursor is too old', () async {
      final sync = engine();
      await sync.run('u1', tables: const ['chemicals']);
      now = now.add(const Duration(days: 121));
      source.tables['chemicals']!.removeWhere((row) => row['id'] == 'c0');
      // No tombstone (pruned on the server): only a full download notices.
      final report = await sync.run('u1', tables: const ['chemicals']);
      expect(report.mode, SyncMode.full);
      expect(await cachedIds(local, 'chemical'), ['c1', 'c2', 'c3', 'c4']);
    });

    test('a full download keeps queued and device-only rows', () async {
      await local.upsertRecord('u1', 'chemical', _chemical('queued'));
      await local.upsertRecord('u1', 'chemical', _chemical('stale'));
      await local.upsertRecord('u1', 'reversal', {
        'id': 'r-local',
        'local_only': true,
      });
      source.tables['inventory_reversals'] = [];
      final report = await engine().run(
        'u1',
        tables: const ['chemicals', 'inventory_reversals'],
        full: true,
        keepLocal: (kind, record) =>
            record['local_only'] == true || record['id'] == 'queued',
      );
      expect(report.mode, SyncMode.full);
      expect(await cachedIds(local, 'chemical'), [
        'c0',
        'c1',
        'c2',
        'c3',
        'c4',
        'queued',
      ]);
      expect(await cachedIds(local, 'reversal'), ['r-local']);
    });

    test('legacy servers get paged full downloads every time', () async {
      source.incremental = false;
      final sync = engine();
      final first = await sync.run('u1', tables: const ['chemicals']);
      expect(first.mode, SyncMode.legacy);
      expect(first.incrementalAvailable, isFalse);
      expect(first.fetched, 5);
      expect(first.pages, 3);
      source.tables['chemicals']!.removeWhere((row) => row['id'] == 'c2');
      final second = await sync.run('u1', tables: const ['chemicals']);
      expect(second.mode, SyncMode.legacy);
      expect(await cachedIds(local, 'chemical'), ['c0', 'c1', 'c3', 'c4']);
      expect((await local.allMeta('u1'))[IncrementalSync.fullSyncKey], isNull);
    });

    test('missing optional tables are reported and retried later', () async {
      source.missing.add('apparatus_checkouts');
      final sync = engine();
      final first = await sync.run(
        'u1',
        tables: const ['chemicals', 'apparatus_checkouts'],
      );
      expect(first.missingTables, {'apparatus_checkouts'});
      final second = await sync.run(
        'u1',
        tables: const ['chemicals', 'apparatus_checkouts'],
      );
      expect(second.mode, SyncMode.incremental, reason: 'no forced full');
      expect(second.missingTables, {'apparatus_checkouts'});

      source.missing.clear();
      source.tables['apparatus_checkouts'] = [
        {
          'id': 'l1',
          'user_id': 'u1',
          'apparatus_id': 'a1',
          'quantity': 1,
          'checked_out_at': _iso(now),
          'updated_at': _iso(now),
        },
      ];
      final third = await sync.run(
        'u1',
        tables: const ['chemicals', 'apparatus_checkouts'],
      );
      expect(third.missingTables, isEmpty);
      expect(await cachedIds(local, 'checkout'), ['l1']);
    });

    test('rows of another user never enter the offline copy', () async {
      source.tables['chemicals']!.add(_chemical('intruder', user: 'u2'));
      await engine().run('u1', tables: const ['chemicals']);
      expect(await cachedIds(local, 'chemical'), [
        'c0',
        'c1',
        'c2',
        'c3',
        'c4',
      ]);
      expect(await local.loadRecords('u2', 'chemical'), isEmpty);
      expect(await local.allMeta('u2'), isEmpty);
    });
  });

  group('repository', () {
    test('refresh returns a sorted snapshot with the report', () async {
      final local = openLocal('repo.db');
      addTearDown(local.close);
      final source = _FakeSource();
      source.tables['chemicals'] = [
        _chemical('old', age: const Duration(days: 2)),
        _chemical('new'),
        _chemical('mid', age: const Duration(days: 1)),
      ];
      source.tables['apparatus'] = [];
      source.tables['consumption_logs'] = [
        {
          'id': 'log-1',
          'user_id': 'u1',
          'item_id': 'new',
          'item_type': 'chemical',
          'action': 'consume',
          'amount': 1,
          'note': '',
          'logged_at': _iso(_base.subtract(const Duration(hours: 2))),
          'created_at': _iso(_base.subtract(const Duration(hours: 2))),
          'updated_at': _iso(_base.subtract(const Duration(hours: 2))),
        },
        {
          'id': 'log-2',
          'user_id': 'u1',
          'item_id': 'new',
          'item_type': 'chemical',
          'action': 'restock',
          'amount': 1,
          'note': '',
          'logged_at': _iso(_base),
          'created_at': _iso(_base),
          'updated_at': _iso(_base),
        },
      ];
      source.missing.addAll(['inventory_reversals', 'apparatus_services']);
      source.tables['apparatus_checkouts'] = [];
      final repository = InventoryRepository(local: local, remote: null)
        ..syncOverride = IncrementalSync(
          local: local,
          source: source,
          overlap: Duration.zero,
        );

      final snapshot = await repository.refresh('u1');
      expect(snapshot.fromCache, isFalse);
      expect(snapshot.syncReport?.mode, SyncMode.full);
      expect(snapshot.lastSyncedAt, isNotNull);
      expect(snapshot.chemicals.map((c) => c.id), ['new', 'mid', 'old']);
      expect(snapshot.logs.map((l) => l.id), ['log-2', 'log-1']);
      expect(repository.checkoutsAvailable, isTrue);

      final again = await repository.refresh('u1');
      expect(again.syncReport?.mode, SyncMode.incremental);
      expect(again.chemicals.map((c) => c.id), ['new', 'mid', 'old']);

      final cached = await repository.loadCached('u1');
      expect(cached.fromCache, isTrue);
      expect(cached.chemicals.map((c) => c.id), ['new', 'mid', 'old']);

      final forced = await repository.refresh('u1', full: true);
      expect(forced.syncReport?.mode, SyncMode.full);
    });
  });

  group('sync center', () {
    testWidgets('shows the download mode and offers a full download', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _FakeInventory fake;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryProvider.overrideWith(
              () => fake = _FakeInventory(
                InventoryState(
                  lastSyncedAt: DateTime.now(),
                  syncReport: SyncReport(
                    mode: SyncMode.legacy,
                    finishedAt: DateTime.now(),
                    fetched: 42,
                    pages: 1,
                  ),
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const SyncCenterScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('full download'), findsOneWidget);
      expect(find.byKey(const Key('sync-legacy-hint')), findsOneWidget);
      expect(find.textContaining('42 rows'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('sync-full-resync')));
      await tester.tap(find.byKey(const Key('sync-full-resync')));
      await tester.pumpAndSettle();
      expect(fake.fullResyncs, 1);
    });
  });
}
