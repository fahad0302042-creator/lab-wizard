import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/local_database.dart';

/// How the last download fetched the server data (SYNC-02).
enum SyncMode {
  /// Only rows changed since the cursor plus tombstones.
  incremental('incremental'),

  /// Every row, page by page, with cursors reset afterwards.
  full('full download'),

  /// Every row, page by page, on a server without migration 007
  /// (no `updated_at` / `deleted_rows`); nothing incremental is possible.
  legacy('full download (server has no change tracking)');

  const SyncMode(this.label);

  final String label;
}

/// Outcome of one download, shown in the sync center.
class SyncReport {
  const SyncReport({
    required this.mode,
    required this.finishedAt,
    this.fetched = 0,
    this.removed = 0,
    this.pages = 0,
    this.duration = Duration.zero,
    this.lastFullSyncAt,
    this.missingTables = const {},
  });

  final SyncMode mode;
  final DateTime finishedAt;

  /// Rows written to the offline copy.
  final int fetched;

  /// Rows deleted from the offline copy because of tombstones.
  final int removed;
  final int pages;
  final Duration duration;
  final DateTime? lastFullSyncAt;

  /// Optional tables the server does not have (earlier migrations missing).
  final Set<String> missingTables;

  bool get incrementalAvailable => mode != SyncMode.legacy;

  String get summary {
    final seconds = (duration.inMilliseconds / 1000).toStringAsFixed(1);
    return switch (mode) {
      SyncMode.incremental =>
        '$fetched changed, $removed removed · $pages page'
            '${pages == 1 ? '' : 's'} · ${seconds}s',
      SyncMode.full ||
      SyncMode.legacy => '$fetched rows · $pages page${pages == 1 ? '' : 's'} · ${seconds}s',
    };
  }
}

/// Position in a table ordered by `(updated_at, id)`. Stored per table so a
/// refresh can ask for "everything after this".
class SyncCursor {
  const SyncCursor({required this.at, required this.id});

  final DateTime at;
  final String id;

  String encode() => '${at.toUtc().toIso8601String()}|$id';

  static SyncCursor? decode(String? source) {
    if (source == null) return null;
    final split = source.indexOf('|');
    if (split <= 0) return null;
    final at = DateTime.tryParse(source.substring(0, split));
    if (at == null) return null;
    return SyncCursor(at: at, id: source.substring(split + 1));
  }
}

/// Thrown by a [SyncSource] when a table is not installed on the server.
class SyncTableMissing implements Exception {
  const SyncTableMissing(this.table);

  final String table;

  @override
  String toString() => 'SyncTableMissing($table)';
}

/// Server access needed by [IncrementalSync]; tests use an in-memory fake.
abstract class SyncSource {
  /// True when the server has migration 007 (`updated_at` columns and the
  /// `deleted_rows` table).
  Future<bool> supportsIncremental();

  /// Rows of [table] ordered by `(updated_at, id)` ascending.
  ///
  /// * [after] == null: from the beginning.
  /// * [after] set, [afterId] == null: `updated_at >= after` (inclusive, used
  ///   with an overlap window so late commits are never missed).
  /// * both set: strictly after the `(after, afterId)` tuple (keyset paging).
  Future<List<Map<String, dynamic>>> changesSince(
    String table, {
    required int limit,
    DateTime? after,
    String? afterId,
  });

  /// Tombstones ordered by `(deleted_at, id)` with the same semantics.
  Future<List<Map<String, dynamic>>> deletionsSince({
    required int limit,
    DateTime? after,
    String? afterId,
  });

  /// The newest tombstone, or null when there is none.
  Future<Map<String, dynamic>?> latestDeletion();

  /// Plain offset paging for servers without change tracking.
  Future<List<Map<String, dynamic>>> page(
    String table, {
    required String orderBy,
    required int offset,
    required int limit,
  });
}

/// Downloads server changes into the offline copy: incremental when the
/// server tracks changes, otherwise a paged full download. All cursors and
/// bookkeeping live in `sync_meta`, per user.
class IncrementalSync {
  IncrementalSync({
    required this.local,
    required this.source,
    this.pageSize = 500,
    this.overlap = const Duration(minutes: 2),
    this.maxCursorAge = const Duration(days: 120),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LocalDatabase local;
  final SyncSource source;

  /// Rows per request. Below the PostgREST default cap of 1000.
  final int pageSize;

  /// Re-fetch window before the cursor so a row committed just before the
  /// last cursor by a slow transaction is still picked up.
  final Duration overlap;

  /// Older cursors force a full download (tombstones are pruned after 180
  /// days on the server).
  final Duration maxCursorAge;
  final DateTime Function() _clock;

  /// Cursor value for a table that was empty (or a tombstone list that was
  /// empty) at full-download time: the next incremental run simply asks for
  /// everything, which is cheap for an empty table and independent of the
  /// device clock.
  static final epoch = DateTime.utc(1970);

  /// Cursor marker for an optional table the server does not have yet.
  static const missingMarker = 'missing';

  static const fullSyncKey = 'sync_full_at';
  static const modeKey = 'sync_mode';
  static const deletionsCursorKey = 'sync_cursor:deleted';

  static String cursorKey(String kind) => 'sync_cursor:$kind';

  /// Server table → local cache kind, for every table the app downloads.
  static const tableKinds = <String, String>{
    'chemicals': 'chemical',
    'apparatus': 'apparatus',
    'consumption_logs': 'log',
    'inventory_reversals': 'reversal',
    'apparatus_checkouts': 'checkout',
    'apparatus_services': 'service',
  };

  /// Column each table is ordered by in legacy mode (newest first is how the
  /// app used to download it).
  static const legacyOrder = <String, String>{
    'chemicals': 'created_at',
    'apparatus': 'created_at',
    'consumption_logs': 'logged_at',
    'inventory_reversals': 'reversed_at',
    'apparatus_checkouts': 'checked_out_at',
    'apparatus_services': 'created_at',
  };

  /// Downloads [tables] (server table names) for [userId].
  ///
  /// [keepLocal] decides which cached rows survive a full download even
  /// though the server does not have them (rows still queued in the outbox,
  /// device-only reversals).
  Future<SyncReport> run(
    String userId, {
    required Iterable<String> tables,
    bool full = false,
    bool Function(String kind, Map<String, dynamic> record)? keepLocal,
  }) async {
    final started = _clock();
    final watch = Stopwatch()..start();
    final missing = <String>{};
    final wanted = tables.where(tableKinds.containsKey).toList();

    if (!await source.supportsIncremental()) {
      final fetched = await _fullDownload(
        userId,
        wanted,
        missing,
        keepLocal: keepLocal,
        legacy: true,
      );
      await local.setMeta(userId, modeKey, SyncMode.legacy.name);
      return SyncReport(
        mode: SyncMode.legacy,
        finishedAt: _clock(),
        fetched: fetched.rows,
        pages: fetched.pages,
        duration: watch.elapsed,
        missingTables: missing,
      );
    }

    final lastFull = DateTime.tryParse(
      await local.getMeta(userId, fullSyncKey) ?? '',
    );
    final needsFull =
        full ||
        lastFull == null ||
        started.difference(lastFull) > maxCursorAge ||
        await _anyCursorMissing(userId, wanted);

    if (needsFull) {
      final fetched = await _fullDownload(
        userId,
        wanted,
        missing,
        keepLocal: keepLocal,
        legacy: false,
      );
      await local.setMeta(userId, fullSyncKey, started.toIso8601String());
      await local.setMeta(userId, modeKey, SyncMode.full.name);
      return SyncReport(
        mode: SyncMode.full,
        finishedAt: _clock(),
        fetched: fetched.rows,
        pages: fetched.pages,
        duration: watch.elapsed,
        lastFullSyncAt: started,
        missingTables: missing,
      );
    }

    var fetched = 0;
    var pages = 0;
    for (final table in wanted) {
      final kind = tableKinds[table]!;
      final cursor = SyncCursor.decode(
        await local.getMeta(userId, cursorKey(kind)),
      );
      try {
        final result = await _pullChanges(userId, table, kind, cursor);
        fetched += result.rows;
        pages += result.pages;
      } on SyncTableMissing {
        missing.add(table);
      }
    }
    final removed = await _applyDeletions(userId, wanted);
    await local.setMeta(userId, modeKey, SyncMode.incremental.name);
    return SyncReport(
      mode: SyncMode.incremental,
      finishedAt: _clock(),
      fetched: fetched,
      removed: removed.rows,
      pages: pages + removed.pages,
      duration: watch.elapsed,
      lastFullSyncAt: lastFull,
      missingTables: missing,
    );
  }

  Future<bool> _anyCursorMissing(String userId, List<String> tables) async {
    for (final table in tables) {
      final saved = await local.getMeta(userId, cursorKey(tableKinds[table]!));
      if (saved == null) return true;
    }
    return false;
  }

  /// Pages through everything and replaces each table's cache in one go.
  Future<({int rows, int pages})> _fullDownload(
    String userId,
    List<String> tables,
    Set<String> missing, {
    required bool legacy,
    bool Function(String kind, Map<String, dynamic> record)? keepLocal,
  }) async {
    var rows = 0;
    var pages = 0;
    for (final table in tables) {
      final kind = tableKinds[table]!;
      final downloaded = <Map<String, dynamic>>[];
      SyncCursor? last;
      try {
        if (legacy) {
          var offset = 0;
          while (true) {
            final page = _ownRows(
              userId,
              await source.page(
                table,
                orderBy: legacyOrder[table] ?? 'created_at',
                offset: offset,
                limit: pageSize,
              ),
            );
            pages++;
            downloaded.addAll(page);
            if (page.length < pageSize) break;
            offset += pageSize;
          }
        } else {
          while (true) {
            final page = _ownRows(
              userId,
              await source.changesSince(
                table,
                limit: pageSize,
                after: last?.at,
                afterId: last?.id,
              ),
            );
            pages++;
            downloaded.addAll(page);
            if (page.isEmpty) break;
            last = _cursorOf(page.last, 'updated_at');
            if (page.length < pageSize || last == null) break;
          }
        }
      } on SyncTableMissing {
        missing.add(table);
        if (!legacy) await local.setMeta(userId, cursorKey(kind), missingMarker);
        continue;
      }
      final serverIds = {for (final row in downloaded) row['id'] as String};
      final kept = keepLocal == null
          ? const <Map<String, dynamic>>[]
          : (await local.loadRecords(userId, kind)).where(
              (record) =>
                  !serverIds.contains(record['id']) &&
                  keepLocal(kind, record),
            );
      await local.replaceRecords(userId, kind, [...downloaded, ...kept]);
      rows += downloaded.length;
      if (!legacy) {
        await local.setMeta(
          userId,
          cursorKey(kind),
          (last ?? SyncCursor(at: epoch, id: '')).encode(),
        );
      }
    }
    if (!legacy) {
      // Deletions up to the newest tombstone are already reflected by the
      // download; later ones are picked up by the next incremental run.
      final newest = await source.latestDeletion();
      final cursor = newest == null ? null : _cursorOf(newest, 'deleted_at');
      await local.setMeta(
        userId,
        deletionsCursorKey,
        (cursor ?? SyncCursor(at: epoch, id: '')).encode(),
      );
    }
    return (rows: rows, pages: pages);
  }

  Future<({int rows, int pages})> _pullChanges(
    String userId,
    String table,
    String kind,
    SyncCursor? cursor,
  ) async {
    var rows = 0;
    var pages = 0;
    var last = cursor;
    var first = true;
    while (true) {
      final page = _ownRows(
        userId,
        await source.changesSince(
          table,
          limit: pageSize,
          after: first && last != null ? last.at.subtract(overlap) : last?.at,
          afterId: first ? null : last?.id,
        ),
      );
      first = false;
      pages++;
      if (page.isEmpty) break;
      await local.upsertRecords(userId, kind, page);
      rows += page.length;
      final next = _cursorOf(page.last, 'updated_at');
      if (next == null) break;
      last = next;
      if (page.length < pageSize) break;
    }
    if (last != null) {
      await local.setMeta(userId, cursorKey(kind), last.encode());
    }
    return (rows: rows, pages: pages);
  }

  Future<({int rows, int pages})> _applyDeletions(
    String userId,
    List<String> tables,
  ) async {
    var removed = 0;
    var pages = 0;
    var last = SyncCursor.decode(
      await local.getMeta(userId, deletionsCursorKey),
    );
    var first = true;
    final wantedKinds = {for (final table in tables) table: tableKinds[table]!};
    while (true) {
      final page = _ownRows(
        userId,
        await source.deletionsSince(
          limit: pageSize,
          after: first && last != null ? last.at.subtract(overlap) : last?.at,
          afterId: first ? null : last?.id,
        ),
      );
      first = false;
      pages++;
      if (page.isEmpty) break;
      final byKind = <String, List<String>>{};
      for (final tombstone in page) {
        final kind = wantedKinds[tombstone['table_name']];
        if (kind == null) continue;
        byKind.putIfAbsent(kind, () => []).add(tombstone['row_id'].toString());
      }
      for (final entry in byKind.entries) {
        removed += await local.deleteRecords(userId, entry.key, entry.value);
      }
      final next = _cursorOf(page.last, 'deleted_at');
      if (next == null) break;
      last = next;
      if (page.length < pageSize) break;
    }
    if (last != null) {
      await local.setMeta(userId, deletionsCursorKey, last.encode());
    }
    return (rows: removed, pages: pages);
  }

  /// Defensive per-user isolation: RLS already guarantees this, but a row
  /// for another account must never land in this user's offline copy.
  List<Map<String, dynamic>> _ownRows(
    String userId,
    List<Map<String, dynamic>> rows,
  ) => rows
      .where((row) => row['user_id'] == null || row['user_id'] == userId)
      .toList(growable: false);

  static SyncCursor? _cursorOf(Map<String, dynamic> row, String column) {
    final at = DateTime.tryParse(row[column]?.toString() ?? '');
    final id = row['id'];
    if (at == null || id == null) return null;
    return SyncCursor(at: at, id: id.toString());
  }
}

/// PostgREST-backed [SyncSource].
class SupabaseSyncSource implements SyncSource {
  SupabaseSyncSource(this.client);

  final SupabaseClient client;
  bool? _supported;

  @override
  Future<bool> supportsIncremental() async {
    if (_supported != null) return _supported!;
    try {
      await client.from('deleted_rows').select('id').limit(1);
      await client.from('chemicals').select('updated_at').limit(1);
      return _supported = true;
    } on PostgrestException catch (error) {
      if (isMissingRelationOrColumn(error)) return _supported = false;
      rethrow;
    }
  }

  /// Forgets the cached capability check (after a full resync request).
  void recheck() => _supported = null;

  @override
  Future<List<Map<String, dynamic>>> changesSince(
    String table, {
    required int limit,
    DateTime? after,
    String? afterId,
  }) => _guard(table, () async {
    var query = client.from(table).select();
    if (after != null) {
      final stamp = after.toUtc().toIso8601String();
      query = afterId == null || afterId.isEmpty
          ? query.gte('updated_at', stamp)
          : query.or(
              'updated_at.gt.$stamp,and(updated_at.eq.$stamp,id.gt.$afterId)',
            );
    }
    return _mapList(
      await query.order('updated_at', ascending: true).order('id').limit(limit),
    );
  });

  @override
  Future<List<Map<String, dynamic>>> deletionsSince({
    required int limit,
    DateTime? after,
    String? afterId,
  }) => _guard('deleted_rows', () async {
    var query = client.from('deleted_rows').select();
    if (after != null) {
      final stamp = after.toUtc().toIso8601String();
      query = afterId == null || afterId.isEmpty
          ? query.gte('deleted_at', stamp)
          : query.or(
              'deleted_at.gt.$stamp,and(deleted_at.eq.$stamp,id.gt.$afterId)',
            );
    }
    return _mapList(
      await query.order('deleted_at', ascending: true).order('id').limit(limit),
    );
  });

  @override
  Future<Map<String, dynamic>?> latestDeletion() => _guard(
    'deleted_rows',
    () async => _mapList(
      await client
          .from('deleted_rows')
          .select()
          .order('deleted_at', ascending: false)
          .order('id', ascending: false)
          .limit(1),
    ),
  ).then((rows) => rows.isEmpty ? null : rows.first);

  @override
  Future<List<Map<String, dynamic>>> page(
    String table, {
    required String orderBy,
    required int offset,
    required int limit,
  }) => _guard(
    table,
    () async => _mapList(
      await client
          .from(table)
          .select()
          .order(orderBy, ascending: false)
          .order('id')
          .range(offset, offset + limit - 1),
    ),
  );

  Future<List<Map<String, dynamic>>> _guard(
    String table,
    Future<List<Map<String, dynamic>>> Function() request,
  ) async {
    try {
      return await request();
    } on PostgrestException catch (error) {
      if (isMissingRelationOrColumn(error)) throw SyncTableMissing(table);
      rethrow;
    }
  }

  static List<Map<String, dynamic>> _mapList(Object? response) =>
      (response as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);

  /// Missing table (`42P01`, `PGRST205`) or missing column (`42703`,
  /// `PGRST204`) — both mean "migration not installed".
  static bool isMissingRelationOrColumn(PostgrestException error) {
    final message = error.message.toLowerCase();
    return error.code == 'PGRST205' ||
        error.code == 'PGRST204' ||
        error.code == '42P01' ||
        error.code == '42703' ||
        message.contains('does not exist') ||
        message.contains('schema cache');
  }
}
