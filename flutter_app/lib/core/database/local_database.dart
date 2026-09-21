import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../features/inventory/domain/models.dart';

/// Per-user SQLite cache plus the outbox of changes waiting for the server.
///
/// Schema history:
/// 1. `cache_records` and `outbox`.
/// 2. Outbox `status`, `label`, and `last_attempt_at` columns and the
///    `sync_meta` table used by the sync center (SYNC-01).
/// 3. Index on `cache_records (user_id, kind)` for incremental upserts and
///    per-kind loads (SYNC-02). Cursors live in `sync_meta`.
class LocalDatabase {
  LocalDatabase({this._factory, this._path});

  static const schemaVersion = 3;
  static const lastSyncKey = 'last_sync_at';

  final DatabaseFactory? _factory;
  final String? _path;
  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final factory = _factory ?? databaseFactory;
    final path =
        _path ??
        p.join(await factory.getDatabasesPath(), 'lab_wizard_offline.db');
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, _) async {
          await _createVersion1(db);
          await _upgradeToVersion2(db);
          await _upgradeToVersion3(db);
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) await _upgradeToVersion2(db);
          if (oldVersion < 3) await _upgradeToVersion3(db);
        },
      ),
    );
  }

  static Future<void> _createVersion1(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE cache_records (
        user_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        record_id TEXT NOT NULL,
        body TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (user_id, kind, record_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE outbox (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX outbox_user_created ON outbox(user_id, created_at)',
    );
  }

  static Future<void> _upgradeToVersion2(DatabaseExecutor db) async {
    await db.execute(
      "ALTER TABLE outbox ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'",
    );
    await db.execute('ALTER TABLE outbox ADD COLUMN label TEXT');
    await db.execute('ALTER TABLE outbox ADD COLUMN last_attempt_at TEXT');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_meta (
        user_id TEXT NOT NULL,
        key TEXT NOT NULL,
        value TEXT NOT NULL,
        PRIMARY KEY (user_id, key)
      )
    ''');
  }

  static Future<void> _upgradeToVersion3(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS cache_records_user_kind '
      'ON cache_records(user_id, kind)',
    );
  }

  Future<List<Map<String, dynamic>>> loadRecords(
    String userId,
    String kind,
  ) async {
    final db = await database;
    final rows = await db.query(
      'cache_records',
      columns: ['body'],
      where: 'user_id = ? AND kind = ?',
      whereArgs: [userId, kind],
    );
    return rows
        .map(
          (row) => jsonDecode(row['body']! as String) as Map<String, dynamic>,
        )
        .toList(growable: false);
  }

  Future<void> replaceRecords(
    String userId,
    String kind,
    Iterable<Map<String, dynamic>> records,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'cache_records',
        where: 'user_id = ? AND kind = ?',
        whereArgs: [userId, kind],
      );
      final batch = txn.batch();
      final now = DateTime.now().toIso8601String();
      for (final record in records) {
        batch.insert('cache_records', {
          'user_id': userId,
          'kind': kind,
          'record_id': record['id'] as String,
          'body': jsonEncode(record),
          'updated_at': now,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> upsertRecord(
    String userId,
    String kind,
    Map<String, dynamic> record,
  ) async {
    final db = await database;
    await db.insert('cache_records', {
      'user_id': userId,
      'kind': kind,
      'record_id': record['id'] as String,
      'body': jsonEncode(record),
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Inserts or replaces many records of one kind in a single transaction
  /// (incremental sync pages).
  Future<void> upsertRecords(
    String userId,
    String kind,
    Iterable<Map<String, dynamic>> records,
  ) async {
    if (records.isEmpty) return;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final record in records) {
      batch.insert('cache_records', {
        'user_id': userId,
        'kind': kind,
        'record_id': record['id'] as String,
        'body': jsonEncode(record),
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Removes the given records of one kind; returns how many existed.
  Future<int> deleteRecords(
    String userId,
    String kind,
    Iterable<String> ids,
  ) async {
    final list = ids.toList();
    if (list.isEmpty) return 0;
    final db = await database;
    var removed = 0;
    for (var start = 0; start < list.length; start += 200) {
      final chunk = list.sublist(
        start,
        start + 200 > list.length ? list.length : start + 200,
      );
      final marks = List.filled(chunk.length, '?').join(', ');
      removed += await db.delete(
        'cache_records',
        where: 'user_id = ? AND kind = ? AND record_id IN ($marks)',
        whereArgs: [userId, kind, ...chunk],
      );
    }
    return removed;
  }

  /// Number of cached records of one kind.
  Future<int> recordCount(String userId, String kind) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM cache_records '
      'WHERE user_id = ? AND kind = ?',
      [userId, kind],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Every sync bookkeeping entry for the user (cursors, last full sync).
  Future<Map<String, String>> allMeta(String userId) async {
    final db = await database;
    final rows = await db.query(
      'sync_meta',
      columns: ['key', 'value'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return {
      for (final row in rows) row['key']! as String: row['value']! as String,
    };
  }

  /// Drops the sync bookkeeping so the next refresh downloads everything.
  Future<void> clearSyncMeta(String userId, {String? prefix}) async {
    final db = await database;
    await db.delete(
      'sync_meta',
      where: prefix == null ? 'user_id = ?' : 'user_id = ? AND key LIKE ?',
      whereArgs: prefix == null ? [userId] : [userId, '$prefix%'],
    );
  }

  Future<void> deleteRecord(String userId, String kind, String id) async {
    final db = await database;
    await db.delete(
      'cache_records',
      where: 'user_id = ? AND kind = ? AND record_id = ?',
      whereArgs: [userId, kind, id],
    );
  }

  /// Removes every cached record of [kind] for which [test] returns true.
  Future<int> deleteRecordsWhere(
    String userId,
    String kind,
    bool Function(Map<String, dynamic> record) test,
  ) async {
    final records = await loadRecords(userId, kind);
    var removed = 0;
    for (final record in records) {
      if (!test(record)) continue;
      await deleteRecord(userId, kind, record['id'] as String);
      removed++;
    }
    return removed;
  }

  Future<void> enqueue(PendingOperation operation) async {
    final db = await database;
    await db.insert(
      'outbox',
      operation.toDatabase(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Queued changes in the order they must be replayed.
  Future<List<PendingOperation>> pendingOperations(
    String userId, {
    PendingStatus? status,
  }) async {
    final db = await database;
    final rows = await db.query(
      'outbox',
      where: status == null ? 'user_id = ?' : 'user_id = ? AND status = ?',
      whereArgs: status == null ? [userId] : [userId, status.name],
      orderBy: 'created_at ASC',
    );
    return rows.map(PendingOperation.fromDatabase).toList(growable: false);
  }

  Future<PendingOperation?> operationById(String id) async {
    final db = await database;
    final rows = await db.query('outbox', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : PendingOperation.fromDatabase(rows.first);
  }

  /// Records an attempt. Connectivity problems keep the change `pending` so
  /// it retries automatically; other errors mark it `failed` until the user
  /// retries or discards it.
  Future<void> markAttempt(
    String id,
    Object error, {
    bool failed = false,
  }) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE outbox SET attempts = attempts + 1, last_error = ?, '
      'last_attempt_at = ?, status = ? WHERE id = ?',
      [
        error.toString(),
        DateTime.now().toIso8601String(),
        failed ? PendingStatus.failed.name : PendingStatus.pending.name,
        id,
      ],
    );
  }

  /// Puts a failed change back in the automatic retry queue.
  Future<void> resetOperation(String id) async {
    final db = await database;
    await db.update(
      'outbox',
      {'status': PendingStatus.pending.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> completeOperation(String id) async {
    final db = await database;
    await db.delete('outbox', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> pendingCount(String userId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM outbox WHERE user_id = ?',
      [userId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> failedCount(String userId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM outbox WHERE user_id = ? AND status = ?',
      [userId, PendingStatus.failed.name],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> setMeta(String userId, String key, String value) async {
    final db = await database;
    await db.insert('sync_meta', {
      'user_id': userId,
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getMeta(String userId, String key) async {
    final db = await database;
    final rows = await db.query(
      'sync_meta',
      columns: ['value'],
      where: 'user_id = ? AND key = ?',
      whereArgs: [userId, key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> clearUser(String userId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'cache_records',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      await txn.delete('outbox', where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('sync_meta', where: 'user_id = ?', whereArgs: [userId]);
    });
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
