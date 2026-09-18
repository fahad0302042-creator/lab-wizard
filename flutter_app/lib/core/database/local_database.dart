import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../features/inventory/domain/models.dart';

class LocalDatabase {
  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final root = await getDatabasesPath();
    return openDatabase(
      p.join(root, 'lab_wizard_offline.db'),
      version: 1,
      onCreate: (db, _) async {
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
      },
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

  Future<void> deleteRecord(String userId, String kind, String id) async {
    final db = await database;
    await db.delete(
      'cache_records',
      where: 'user_id = ? AND kind = ? AND record_id = ?',
      whereArgs: [userId, kind, id],
    );
  }

  Future<void> enqueue(PendingOperation operation) async {
    final db = await database;
    await db.insert(
      'outbox',
      operation.toDatabase(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<PendingOperation>> pendingOperations(String userId) async {
    final db = await database;
    final rows = await db.query(
      'outbox',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC',
    );
    return rows.map(PendingOperation.fromDatabase).toList(growable: false);
  }

  Future<void> markAttempt(String id, Object error) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE id = ?',
      [error.toString(), id],
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

  Future<void> clearUser(String userId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'cache_records',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      await txn.delete('outbox', where: 'user_id = ?', whereArgs: [userId]);
    });
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
