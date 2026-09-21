import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/database/local_database.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/inventory/data/inventory_repository.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:lab_wizard/features/sync/domain/sync_conflict.dart';
import 'package:lab_wizard/features/sync/presentation/sync_center_screen.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Just enough of PostgREST to exercise conditional updates and RPC errors:
/// `eq`/`is` filters, PATCH/POST/DELETE, single-object responses and
/// scripted RPC functions.
class _FakePostgrest {
  final tables = <String, List<Map<String, dynamic>>>{
    'chemicals': [],
    'apparatus': [],
    'consumption_logs': [],
  };
  final requests = <http.Request>[];
  final rpc = <String, http.Response Function(Map<String, dynamic> params)>{};
  bool offline = false;

  http.Client get client => MockClient(_handle);

  Iterable<http.Request> get patches =>
      requests.where((request) => request.method == 'PATCH');

  Map<String, dynamic> row(String table, String id) =>
      tables[table]!.firstWhere((row) => row['id'] == id);

  Future<http.Response> _handle(http.Request request) async {
    if (offline) throw const SocketException('offline');
    requests.add(request);
    final segments = request.url.pathSegments;
    if (segments.length >= 4 && segments[2] == 'rpc') {
      final handler = rpc[segments[3]];
      if (handler == null) {
        return _error(
          404,
          'Could not find the function public.${segments[3]}',
          'PGRST202',
        );
      }
      return handler(jsonDecode(request.body) as Map<String, dynamic>);
    }
    final rows = tables.putIfAbsent(segments[2], () => []);
    final matched = rows
        .where((row) => _matches(row, request.url.queryParameters))
        .toList();
    switch (request.method) {
      case 'GET':
        break;
      case 'PATCH':
        final changes = jsonDecode(request.body) as Map<String, dynamic>;
        for (final row in matched) {
          row.addAll(changes);
        }
      case 'POST':
        final body = jsonDecode(request.body);
        for (final item in body is List ? body : [body]) {
          rows.add(Map<String, dynamic>.from(item as Map));
          matched.add(rows.last);
        }
      case 'DELETE':
        rows.removeWhere(matched.contains);
      default:
        return _error(405, 'Method not allowed', '405');
    }
    final accept = request.headers['Accept'] ?? '';
    if (accept.contains('object+json')) {
      if (matched.length != 1) {
        return http.Response(
          jsonEncode({
            'message': 'JSON object requested, multiple (or no) rows returned',
            'code': 'PGRST116',
            'details': 'Results contain ${matched.length} rows',
            'hint': null,
          }),
          406,
          headers: _json,
        );
      }
      return http.Response(jsonEncode(matched.single), 200, headers: _json);
    }
    return http.Response(jsonEncode(matched), 200, headers: _json);
  }

  static const _json = {'content-type': 'application/json; charset=utf-8'};

  static http.Response _error(int status, String message, String code) =>
      http.Response(
        jsonEncode({
          'message': message,
          'code': code,
          'details': null,
          'hint': null,
        }),
        status,
        headers: _json,
      );

  static bool _matches(Map<String, dynamic> row, Map<String, String> query) {
    for (final entry in query.entries) {
      if (entry.key == 'select' || entry.key == 'columns') continue;
      final value = entry.value;
      final dot = value.indexOf('.');
      final operator = value.substring(0, dot);
      final operand = value.substring(dot + 1);
      final actual = row[entry.key];
      switch (operator) {
        case 'eq':
          if (!_equal(actual, operand)) return false;
        case 'is':
          if (operand == 'null') {
            if (actual != null) return false;
          } else if (actual != (operand == 'true')) {
            return false;
          }
        default:
          throw UnsupportedError('operator $operator');
      }
    }
    return true;
  }

  static bool _equal(Object? actual, String operand) {
    if (actual == null) return false;
    if (actual is num) {
      final number = num.tryParse(operand);
      return number != null && number == actual;
    }
    return actual.toString() == operand;
  }
}

Map<String, dynamic> _acetone() => {
  'id': 'c1',
  'user_id': 'u1',
  'name': 'Acetone',
  'formula': 'C3H6O',
  'unit': 'mL',
  'quantity': 100,
  'initial_quantity': 100,
  'low_stock_threshold': 10,
  'notes': '',
  'qr_code': 'qr-c1',
  'created_at': '2026-01-01T00:00:00.000Z',
  'hazard_classes': ['GHS02'],
  'supplier': null,
};

class _FakeInventory extends InventoryController {
  _FakeInventory(this.seed);

  final InventoryState seed;
  final resolved = <(String, ConflictResolution)>[];
  final retried = <String>[];

  @override
  InventoryState build() => seed;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> retryOperation(String operationId) async {
    retried.add(operationId);
  }

  @override
  Future<void> resolveConflict(
    String operationId,
    ConflictResolution resolution,
  ) async {
    resolved.add((operationId, resolution));
  }
}

void main() {
  group('SYNC-04 conflict model', () {
    test('value comparison ignores representation differences', () {
      expect(valuesMatch(5, 5.0), isTrue);
      expect(valuesMatch('5', 5), isTrue);
      expect(valuesMatch(null, ''), isTrue);
      expect(valuesMatch(['a', 'b'], ['b', 'a']), isTrue);
      expect(valuesMatch(['a'], ['a', 'b']), isFalse);
      expect(valuesMatch('Acetone', 'acetone'), isFalse);
      expect(valuesMatch(null, 0), isFalse);
    });

    test('server errors that describe conflicts are recognised', () {
      final stock = conflictFromError(
        const PostgrestException(
          message: 'Insufficient stock: only 2.5 available',
          code: '22003',
        ),
        requested: 5,
        unit: 'mL',
        partialAllowed: true,
      )!;
      expect(stock.kind, ConflictKind.stock);
      expect(stock.available, 2.5);
      expect(stock.requested, 5);
      expect(stock.resolutions, [
        ConflictResolution.useAvailable,
        ConflictResolution.discard,
      ]);
      expect(stock.explanation, contains('only 2.5 mL left'));

      final undo = conflictFromError(
        StateError('Cannot undo: only 3 left of the 10 that was restocked.'),
      )!;
      expect(undo.kind, ConflictKind.stock);
      expect(undo.available, 3);
      expect(undo.requested, 10);
      expect(undo.resolutions, [ConflictResolution.discard]);

      final deleted = conflictFromError(
        const PostgrestException(
          message: 'Item not found or not owned by the current user',
          code: 'P0002',
        ),
      )!;
      expect(deleted.kind, ConflictKind.deleted);
      expect(deleted.resolutions, [ConflictResolution.discard]);

      expect(conflictFromError(const SocketException('offline')), isNull);
      expect(conflictFromError(StateError('permission denied')), isNull);
    });

    test('conflicts round-trip through JSON and explain themselves', () {
      final conflict = SyncConflict.changed(const [
        FieldConflict(
          field: 'low_stock_threshold',
          base: 10,
          local: 5,
          server: 20,
        ),
        FieldConflict(field: 'notes', base: '', local: 'Shelf B', server: null),
      ], at: DateTime(2026, 9, 21, 10));
      final restored = SyncConflict.decode(conflict.encode())!;
      expect(restored.kind, ConflictKind.changed);
      expect(restored.detectedAt, DateTime(2026, 9, 21, 10));
      expect(restored.fields, hasLength(2));
      expect(restored.fields.first.server, 20);
      expect(restored.summary, 'Changed on the server since you loaded it: '
          'low-stock level, notes.');
      expect(
        restored.explanation,
        contains('low-stock level is now 20 on the server (yours: 5)'),
      );
      expect(restored.resolutions, [
        ConflictResolution.useServer,
        ConflictResolution.keepMine,
        ConflictResolution.discard,
      ]);
      expect(SyncConflict.decode(null), isNull);
      expect(SyncConflict.decode('not json'), isNull);
      expect(
        ItemConflictException(
          SyncConflict.stock(available: 1, requested: 2, unit: 'g'),
        ).toString(),
        'Only 1 g available on the server.',
      );
    });
  });

  group('SYNC-04 storage and server round-trips', () {
    late Directory directory;

    setUpAll(sqfliteFfiInit);

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('lab-wizard-conflict');
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    LocalDatabase openLocal(String name) => LocalDatabase(
      factory: databaseFactoryFfi,
      path: p.join(directory.path, name),
    );

    SupabaseClient clientFor(_FakePostgrest server) {
      final client = SupabaseClient(
        'http://fake.local',
        'test-key',
        httpClient: server.client,
      );
      addTearDown(client.dispose);
      return client;
    }

    test('outbox keeps conflicts until a decision and migrates old files', () async {
      final path = p.join(directory.path, 'v3.db');
      // A pre-SYNC-04 file: schema version 3 without the conflict column.
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE cache_records (
                user_id TEXT NOT NULL, kind TEXT NOT NULL,
                record_id TEXT NOT NULL, body TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (user_id, kind, record_id)
              )
            ''');
            await db.execute('''
              CREATE TABLE outbox (
                id TEXT PRIMARY KEY, user_id TEXT NOT NULL,
                type TEXT NOT NULL, payload TEXT NOT NULL,
                created_at TEXT NOT NULL,
                attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT,
                status TEXT NOT NULL DEFAULT 'pending', label TEXT,
                last_attempt_at TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE sync_meta (
                user_id TEXT NOT NULL, key TEXT NOT NULL,
                value TEXT NOT NULL, PRIMARY KEY (user_id, key)
              )
            ''');
          },
        ),
      );
      await legacy.insert('outbox', {
        'id': 'op-1',
        'user_id': 'u1',
        'type': 'update_item',
        'payload': '{"id":"c1","item_type":"chemical","changes":{}}',
        'created_at': DateTime(2026, 9, 20).toIso8601String(),
      });
      await legacy.close();

      final local = LocalDatabase(factory: databaseFactoryFfi, path: path);
      addTearDown(local.close);
      var operation = (await local.pendingOperations('u1')).single;
      expect(operation.isConflict, isFalse);

      await local.markConflict(
        'op-1',
        SyncConflict.deleted(at: DateTime(2026, 9, 21)),
      );
      operation = (await local.pendingOperations('u1')).single;
      expect(operation.isFailed, isTrue);
      expect(operation.isConflict, isTrue);
      expect(operation.canRetry, isFalse);
      expect(operation.attempts, 1);
      expect(operation.lastError, 'Deleted on the server.');
      expect(operation.conflict!.kind, ConflictKind.deleted);

      await local.updatePayload('op-1', {'id': 'c1', 'force': true});
      await local.resetOperation('op-1');
      operation = (await local.pendingOperations('u1')).single;
      expect(operation.isFailed, isFalse);
      expect(operation.isConflict, isFalse);
      expect(operation.payload['force'], isTrue);

      await local.markConflict('op-1', SyncConflict.deleted());
      await local.markAttempt('op-1', 'boom', failed: true);
      operation = (await local.pendingOperations('u1')).single;
      expect(operation.isFailed, isTrue);
      expect(operation.isConflict, isFalse);
    });

    test('an edit only sends changed fields and guards them', () async {
      final server = _FakePostgrest()..tables['chemicals']!.add(_acetone());
      final local = openLocal('guard.db');
      addTearDown(local.close);
      await local.upsertRecord('u1', 'chemical', _acetone());
      final repository = InventoryRepository(
        local: local,
        remote: clientFor(server),
      );

      final saved = await repository.updateItem(
        userId: 'u1',
        type: ItemKind.chemical,
        id: 'c1',
        changes: {
          'name': 'Acetone',
          'formula': 'C3H6O',
          'unit': 'mL',
          'low_stock_threshold': 5.0,
          'notes': '',
        },
      );
      expect(saved['low_stock_threshold'], 5);
      final patch = server.patches.single;
      expect(jsonDecode(patch.body), {'low_stock_threshold': 5.0});
      expect(patch.url.queryParameters['id'], 'eq.c1');
      expect(patch.url.queryParameters['low_stock_threshold'], 'eq.10');
      expect(patch.url.queryParameters.containsKey('name'), isFalse);
      final cached = (await local.loadRecords('u1', 'chemical')).single;
      expect(cached['low_stock_threshold'], 5);

      // Nothing changed: no request at all.
      await repository.updateItem(
        userId: 'u1',
        type: ItemKind.chemical,
        id: 'c1',
        changes: {'name': 'Acetone', 'low_stock_threshold': 5},
      );
      expect(server.patches, hasLength(1));
    });

    test('a field changed on both sides is a conflict, not an overwrite', () async {
      final server = _FakePostgrest()..tables['chemicals']!.add(_acetone());
      final local = openLocal('clash.db');
      addTearDown(local.close);
      await local.upsertRecord('u1', 'chemical', _acetone());
      final repository = InventoryRepository(
        local: local,
        remote: clientFor(server),
      );
      // Someone else raised the threshold and renamed the item.
      server.row('chemicals', 'c1')
        ..['low_stock_threshold'] = 20
        ..['name'] = 'Acetone (HPLC)';

      // Only the notes changed here: no clash with the server's edits.
      final saved = await repository.updateItem(
        userId: 'u1',
        type: ItemKind.chemical,
        id: 'c1',
        changes: {'notes': 'Shelf B', 'low_stock_threshold': 10},
      );
      expect(saved['notes'], 'Shelf B');
      expect(saved['name'], 'Acetone (HPLC)');
      expect(saved['low_stock_threshold'], 20);

      // A stale copy on this device edits the threshold the server moved:
      // conflict, reported with both values, and nothing overwritten.
      await local.upsertRecord('u1', 'chemical', _acetone());
      await expectLater(
        repository.updateItem(
          userId: 'u1',
          type: ItemKind.chemical,
          id: 'c1',
          changes: {'low_stock_threshold': 5},
        ),
        throwsA(
          isA<ItemConflictException>().having(
            (error) => error.conflict.fields.single,
            'field',
            isA<FieldConflict>()
                .having((f) => f.field, 'field', 'low_stock_threshold')
                .having((f) => f.server, 'server', 20)
                .having((f) => f.local, 'local', 5),
          ),
        ),
      );
      expect(server.row('chemicals', 'c1')['low_stock_threshold'], 20);

      // The server already has what this device wants: not a conflict.
      await local.upsertRecord('u1', 'chemical', _acetone());
      final agreed = await repository.updateItem(
        userId: 'u1',
        type: ItemKind.chemical,
        id: 'c1',
        changes: {'low_stock_threshold': 20},
      );
      expect(agreed['low_stock_threshold'], 20);

      // Overwriting is an explicit choice.
      await local.upsertRecord('u1', 'chemical', _acetone());
      final forced = await repository.updateItem(
        userId: 'u1',
        type: ItemKind.chemical,
        id: 'c1',
        changes: {'low_stock_threshold': 5},
        force: true,
      );
      expect(forced['low_stock_threshold'], 5);
      expect(server.row('chemicals', 'c1')['low_stock_threshold'], 5);

      // Array columns are compared before writing.
      server.row('chemicals', 'c1')['hazard_classes'] = ['GHS02', 'GHS07'];
      await local.upsertRecord('u1', 'chemical', {
        ...server.row('chemicals', 'c1'),
        'hazard_classes': ['GHS02'],
      });
      await expectLater(
        repository.updateItem(
          userId: 'u1',
          type: ItemKind.chemical,
          id: 'c1',
          changes: {
            'hazard_classes': ['GHS02', 'GHS05'],
          },
        ),
        throwsA(
          isA<ItemConflictException>().having(
            (error) => error.conflict.fields.single.field,
            'field',
            'hazard_classes',
          ),
        ),
      );

      // A deleted item cannot take edits.
      server.tables['chemicals']!.clear();
      await expectLater(
        repository.updateItem(
          userId: 'u1',
          type: ItemKind.chemical,
          id: 'c1',
          changes: {'notes': 'gone'},
        ),
        throwsA(
          isA<ItemConflictException>().having(
            (error) => error.conflict.kind,
            'kind',
            ConflictKind.deleted,
          ),
        ),
      );
    });

    test('a queued edit that lost the race waits for a decision', () async {
      final server = _FakePostgrest()..tables['chemicals']!.add(_acetone());
      final local = openLocal('queued.db');
      addTearDown(local.close);
      await local.upsertRecord('u1', 'chemical', _acetone());
      final repository = InventoryRepository(
        local: local,
        remote: clientFor(server),
      );

      server.offline = true;
      await repository.updateItem(
        userId: 'u1',
        type: ItemKind.chemical,
        id: 'c1',
        changes: {'low_stock_threshold': 5, 'notes': 'Shelf B'},
      );
      var operation = (await local.pendingOperations('u1')).single;
      expect(operation.type, 'update_item');
      expect(operation.payload['previous'], {
        'low_stock_threshold': 10,
        'notes': '',
      });

      // Meanwhile the threshold moved on the server.
      server.row('chemicals', 'c1')['low_stock_threshold'] = 20;
      server.offline = false;
      await repository.syncPending('u1');
      operation = (await local.pendingOperations('u1')).single;
      expect(operation.isConflict, isTrue);
      expect(operation.conflict!.kind, ConflictKind.changed);
      expect(operation.conflict!.fields.single.field, 'low_stock_threshold');
      expect(server.row('chemicals', 'c1')['notes'], '');

      // "Retry all" leaves conflicts alone.
      final before = server.requests.length;
      await repository.syncPending('u1', retryFailed: true);
      expect(server.requests.length, before);

      // Keeping the server value still sends the rest of the edit.
      await repository.resolveConflict(
        'u1',
        operation,
        ConflictResolution.useServer,
      );
      expect(await local.pendingOperations('u1'), isEmpty);
      final row = server.row('chemicals', 'c1');
      expect(row['low_stock_threshold'], 20);
      expect(row['notes'], 'Shelf B');
      final cached = (await local.loadRecords('u1', 'chemical')).single;
      expect(cached['low_stock_threshold'], 20);
      expect(cached['notes'], 'Shelf B');

      // Overwriting is available too.
      server.offline = true;
      await repository.updateItem(
        userId: 'u1',
        type: ItemKind.chemical,
        id: 'c1',
        changes: {'low_stock_threshold': 5},
      );
      server.row('chemicals', 'c1')['low_stock_threshold'] = 30;
      server.offline = false;
      await repository.syncPending('u1');
      operation = (await local.pendingOperations('u1')).single;
      expect(operation.isConflict, isTrue);
      await repository.resolveConflict(
        'u1',
        operation,
        ConflictResolution.keepMine,
      );
      expect(await local.pendingOperations('u1'), isEmpty);
      expect(server.row('chemicals', 'c1')['low_stock_threshold'], 5);
    });

    test('a queued edit whose item was deleted is reported as such', () async {
      final server = _FakePostgrest()..tables['chemicals']!.add(_acetone());
      final local = openLocal('deleted.db');
      addTearDown(local.close);
      await local.upsertRecord('u1', 'chemical', _acetone());
      final repository = InventoryRepository(
        local: local,
        remote: clientFor(server),
      );
      server.offline = true;
      await repository.updateItem(
        userId: 'u1',
        type: ItemKind.chemical,
        id: 'c1',
        changes: {'notes': 'Shelf B'},
      );
      server.tables['chemicals']!.clear();
      server.offline = false;
      await repository.syncPending('u1');
      final operation = (await local.pendingOperations('u1')).single;
      expect(operation.conflict?.kind, ConflictKind.deleted);
      expect(operation.conflict!.resolutions, [ConflictResolution.discard]);
    });

    test('stale stock becomes a conflict that can apply what is left', () async {
      final server = _FakePostgrest()..tables['chemicals']!.add(_acetone());
      final local = openLocal('stock.db');
      addTearDown(local.close);
      await local.upsertRecord('u1', 'chemical', _acetone());
      final repository = InventoryRepository(
        local: local,
        remote: clientFor(server),
      );
      final rpcAmounts = <num>[];
      server.rpc['apply_inventory_action'] = (params) {
        final amount = params['p_amount'] as num;
        rpcAmounts.add(amount);
        final row = server.row('chemicals', 'c1');
        final quantity = row['quantity'] as num;
        if (quantity < amount) {
          return _FakePostgrest._error(
            400,
            'Insufficient stock: only $quantity available',
            '22003',
          );
        }
        row['quantity'] = quantity - amount;
        final log = {
          'id': 'server-log',
          'user_id': 'u1',
          'item_id': 'c1',
          'item_type': 'chemical',
          'action': params['p_action'],
          'amount': amount,
          'note': params['p_note'],
          'logged_at': params['p_logged_at'],
          'created_at': '2026-09-21T10:00:00.000Z',
          'operation_id': params['p_operation_id'],
        };
        return http.Response(
          jsonEncode({'item': row, 'log': log, 'duplicate': false}),
          200,
          headers: _FakePostgrest._json,
        );
      };

      server.offline = true;
      final log = await repository.applyAction(
        userId: 'u1',
        itemId: 'c1',
        itemType: ItemKind.chemical,
        action: InventoryAction.consume,
        amount: 60,
        previousQuantity: 100,
        note: '',
        loggedAt: DateTime(2026, 9, 21),
        itemName: 'Acetone',
        unit: 'mL',
      );
      // Someone else used most of it first.
      server.row('chemicals', 'c1')['quantity'] = 25;
      server.offline = false;
      await repository.syncPending('u1');
      var operation = (await local.pendingOperations('u1')).single;
      expect(operation.isConflict, isTrue);
      final conflict = operation.conflict!;
      expect(conflict.kind, ConflictKind.stock);
      expect(conflict.available, 25);
      expect(conflict.requested, 60);
      expect(conflict.unit, 'mL');
      expect(conflict.resolutions.first, ConflictResolution.useAvailable);
      expect(rpcAmounts, [60]);

      await repository.resolveConflict(
        'u1',
        operation,
        ConflictResolution.useAvailable,
      );
      expect(rpcAmounts, [60, 25]);
      expect(await local.pendingOperations('u1'), isEmpty);
      expect(server.row('chemicals', 'c1')['quantity'], 0);
      final cachedLog = (await local.loadRecords(
        'u1',
        'log',
      )).firstWhere((row) => row['id'] == log.id);
      expect(cachedLog['amount'], 25);
      final cached = (await local.loadRecords('u1', 'chemical')).single;
      // 100 cached − 60 optimistic + 35 given back = 75 until the next
      // refresh downloads the server's 0.
      expect(cached['quantity'], 75);
    });

    test('without the RPC, quantities are rebased instead of overwritten', () async {
      final server = _FakePostgrest()..tables['chemicals']!.add(_acetone());
      final local = openLocal('compat.db');
      addTearDown(local.close);
      await local.upsertRecord('u1', 'chemical', _acetone());
      final repository = InventoryRepository(
        local: local,
        remote: clientFor(server),
      );
      // No RPC installed: the client falls back to plain table writes.
      server.row('chemicals', 'c1')['quantity'] = 80;
      await repository.applyAction(
        userId: 'u1',
        itemId: 'c1',
        itemType: ItemKind.chemical,
        action: InventoryAction.consume,
        amount: 30,
        previousQuantity: 100,
        note: '',
        loggedAt: DateTime(2026, 9, 21),
      );
      // 80 − 30, not the precomputed 70.
      expect(server.row('chemicals', 'c1')['quantity'], 50);
      expect(server.tables['consumption_logs'], hasLength(1));

      server.row('chemicals', 'c1')['quantity'] = 10;
      await expectLater(
        repository.applyAction(
          userId: 'u1',
          itemId: 'c1',
          itemType: ItemKind.chemical,
          action: InventoryAction.consume,
          amount: 30,
          previousQuantity: 50,
          note: '',
          loggedAt: DateTime(2026, 9, 21),
          unit: 'mL',
        ),
        throwsA(
          isA<ItemConflictException>().having(
            (error) => error.conflict.available,
            'available',
            10,
          ),
        ),
      );
      expect(server.row('chemicals', 'c1')['quantity'], 10);
    });
  });

  group('SYNC-04 sync center', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('conflicts explain themselves and offer decisions', (
      tester,
    ) async {
      final now = DateTime.now();
      final seed = InventoryState(
        outbox: [
          PendingOperation(
            id: 'op-edit',
            userId: 'u1',
            type: 'update_item',
            payload: const {'id': 'c1', 'item_type': 'chemical'},
            createdAt: now.subtract(const Duration(minutes: 8)),
            attempts: 1,
            status: PendingStatus.failed,
            lastError: 'Changed on the server since you loaded it.',
            label: 'Update Acetone',
            conflict: SyncConflict.changed(const [
              FieldConflict(
                field: 'low_stock_threshold',
                base: 10,
                local: 5,
                server: 20,
              ),
            ]),
          ),
          PendingOperation(
            id: 'op-consume',
            userId: 'u1',
            type: 'inventory_action',
            payload: const {
              'item_id': 'c2',
              'action': 'consume',
              'amount': 60,
            },
            createdAt: now.subtract(const Duration(minutes: 6)),
            attempts: 1,
            status: PendingStatus.failed,
            label: 'Consume 60 mL of Ethanol',
            conflict: SyncConflict.stock(
              available: 25,
              requested: 60,
              unit: 'mL',
              partialAllowed: true,
            ),
          ),
          PendingOperation(
            id: 'op-gone',
            userId: 'u1',
            type: 'update_item',
            payload: const {'id': 'c3', 'item_type': 'chemical'},
            createdAt: now.subtract(const Duration(minutes: 5)),
            attempts: 1,
            status: PendingStatus.failed,
            label: 'Update Benzene',
            conflict: SyncConflict.deleted(),
          ),
        ],
      );
      late _FakeInventory fake;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryProvider.overrideWith(() => fake = _FakeInventory(seed)),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const SyncCenterScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('conflict'), findsNWidgets(3));
      expect(find.text('retry now'), findsNothing);
      expect(
        find.textContaining('low-stock level is now 20 on the server'),
        findsOneWidget,
      );
      expect(
        find.textContaining('only 25 mL left; this change needs 60 mL'),
        findsOneWidget,
      );
      expect(find.textContaining('deleted on the server'), findsOneWidget);
      expect(find.text('remove change'), findsOneWidget);

      await tester.tap(find.byKey(const Key('conflict-use-server-op-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conflict-keep-mine-op-edit')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('conflict-use-available-op-consume')),
      );
      await tester.tap(
        find.byKey(const Key('conflict-use-available-op-consume')),
      );
      await tester.pumpAndSettle();
      expect(fake.resolved, [
        ('op-edit', ConflictResolution.useServer),
        ('op-edit', ConflictResolution.keepMine),
        ('op-consume', ConflictResolution.useAvailable),
      ]);
      expect(fake.retried, isEmpty);
      expect(find.byKey(const Key('conflict-keep-mine-op-gone')), findsNothing);
    });
  });
}
