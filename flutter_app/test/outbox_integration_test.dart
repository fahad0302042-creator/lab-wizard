import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lab_wizard/core/database/local_database.dart';
import 'package:lab_wizard/features/inventory/data/inventory_repository.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_postgrest.dart';

/// TEST-04: the offline outbox end to end against an in-memory PostgREST —
/// add, update and action queued offline and flushed later, a retry after a
/// server error, idempotent replay of an action whose first response was
/// lost, and per-user isolation of the queue and the offline copy.
Map<String, dynamic> _acetone({String userId = 'u1', String id = 'c1'}) => {
  'id': id,
  'user_id': userId,
  'name': 'Acetone',
  'formula': 'C3H6O',
  'unit': 'mL',
  'quantity': 100,
  'initial_quantity': 100,
  'low_stock_threshold': 10,
  'notes': '',
  'qr_code': 'qr-$id',
  'created_at': '2026-01-01T00:00:00.000Z',
  'hazard_classes': <String>[],
  'supplier': null,
};

/// The real `apply_inventory_action` function is idempotent on
/// `operation_id`; the fake mirrors that so the replay test means something.
void _installActionRpc(FakePostgrest server, {bool Function()? dropReply}) {
  final applied = <String, Map<String, dynamic>>{};
  server.rpc['apply_inventory_action'] = (params) {
    final operationId = params['p_operation_id'] as String;
    final row = server.row('chemicals', params['p_item_id'] as String);
    final existing = applied[operationId];
    if (existing != null) {
      return http.Response(
        jsonEncode({'item': row, 'log': existing, 'duplicate': true}),
        200,
        headers: FakePostgrest.json,
      );
    }
    final amount = params['p_amount'] as num;
    final quantity = row['quantity'] as num;
    if (params['p_action'] == 'consume' && quantity < amount) {
      return FakePostgrest.error(
        400,
        'Insufficient stock: only $quantity available',
        '22003',
      );
    }
    row['quantity'] = params['p_action'] == 'restock'
        ? quantity + amount
        : quantity - amount;
    final log = {
      'id': 'log-$operationId',
      'user_id': row['user_id'],
      'item_id': row['id'],
      'item_type': 'chemical',
      'action': params['p_action'],
      'amount': amount,
      'note': params['p_note'],
      'logged_at': params['p_logged_at'],
      'created_at': '2026-09-21T10:00:00.000Z',
      'operation_id': operationId,
    };
    applied[operationId] = log;
    server.tables['consumption_logs']!.add(log);
    if (dropReply != null && dropReply()) {
      // The server did the work but the phone never heard back.
      throw const SocketException('connection reset');
    }
    return http.Response(
      jsonEncode({'item': row, 'log': log, 'duplicate': false}),
      200,
      headers: FakePostgrest.json,
    );
  };
}

void main() {
  late Directory directory;

  setUpAll(() => sqfliteFfiInit());
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lab-wizard-outbox');
  });
  tearDown(() => directory.delete(recursive: true));

  LocalDatabase openLocal(String name) => LocalDatabase(
    factory: databaseFactoryFfi,
    path: p.join(directory.path, name),
  );

  SupabaseClient clientFor(FakePostgrest server) {
    final client = SupabaseClient(
      'http://fake.local',
      'test-key',
      httpClient: server.client,
    );
    addTearDown(client.dispose);
    return client;
  }

  group('TEST-04 outbox integration', () {
    test('add, update and action queue offline and flush in order', () async {
      final server = FakePostgrest();
      _installActionRpc(server);
      final local = openLocal('flow.db');
      addTearDown(local.close);
      final repository = InventoryRepository(
        local: local,
        remote: clientFor(server),
      );

      server.offline = true;
      final added = await repository.addChemical(
        userId: 'u1',
        name: 'Ethanol',
        formula: 'C2H5OH',
        unit: 'mL',
        quantity: 500,
        threshold: 50,
        notes: 'queued while offline',
      );
      await repository.updateItem(
        userId: 'u1',
        type: ItemKind.chemical,
        id: added.id,
        changes: {'low_stock_threshold': 75},
      );
      await repository.applyAction(
        userId: 'u1',
        itemId: added.id,
        itemType: ItemKind.chemical,
        action: InventoryAction.consume,
        amount: 120,
        previousQuantity: 500,
        note: 'practical',
        loggedAt: DateTime.utc(2026, 9, 21, 9),
      );
      final queued = await local.pendingOperations('u1');
      expect(queued.map((op) => op.type), [
        'add_chemical',
        'update_item',
        'inventory_action',
      ]);
      expect(server.tables['chemicals'], isEmpty);
      // The offline copy already shows the outcome.
      final cached = (await local.loadRecords('u1', 'chemical')).single;
      expect(cached['quantity'], 380);
      expect(cached['low_stock_threshold'], 75);

      server.offline = false;
      await repository.syncPending('u1');
      expect(await local.pendingOperations('u1'), isEmpty);
      final row = server.row('chemicals', added.id);
      expect(row['name'], 'Ethanol');
      expect(row['low_stock_threshold'], 75);
      expect(row['quantity'], 380);
      expect(server.tables['consumption_logs'], hasLength(1));
      expect(
        server.requests
            .where((r) => r.method != 'GET')
            .map((r) => r.method)
            .toList(),
        ['POST', 'PATCH', 'POST'],
        reason: 'insert, conditional update, RPC — in queue order',
      );
    });

    test('a server error marks one change failed; retry sends it', () async {
      final server = FakePostgrest()..tables['chemicals']!.add(_acetone());
      final local = openLocal('retry.db');
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
      await repository.addChemical(
        userId: 'u1',
        name: 'Toluene',
        formula: 'C7H8',
        unit: 'mL',
        quantity: 10,
        threshold: 1,
        notes: '',
      );
      server.offline = false;

      // The first flush hits a permission problem on the update only.
      var deny = true;
      server.beforeRequest = (request) => deny && request.method == 'PATCH'
          ? FakePostgrest.error(403, 'permission denied for table', '42501')
          : null;
      await repository.syncPending('u1');
      var pending = await local.pendingOperations('u1');
      expect(pending, hasLength(1), reason: 'the add went through');
      expect(pending.single.type, 'update_item');
      expect(pending.single.status, PendingStatus.failed);
      expect(pending.single.attempts, 1);
      expect(pending.single.lastError, contains('permission denied'));
      expect(server.tables['chemicals'], hasLength(2));

      // A plain flush leaves failed changes alone; retry sends them.
      await repository.syncPending('u1');
      expect((await local.pendingOperations('u1')).single.attempts, 1);
      deny = false;
      await repository.syncPending('u1', retryFailed: true);
      expect(await local.pendingOperations('u1'), isEmpty);
      expect(server.row('chemicals', 'c1')['notes'], 'Shelf B');
    });

    test('an action whose reply was lost is not applied twice', () async {
      final server = FakePostgrest()..tables['chemicals']!.add(_acetone());
      var drop = true;
      _installActionRpc(server, dropReply: () => drop);
      final local = openLocal('idempotent.db');
      addTearDown(local.close);
      await local.upsertRecord('u1', 'chemical', _acetone());
      final repository = InventoryRepository(
        local: local,
        remote: clientFor(server),
      );

      server.offline = true;
      await repository.applyAction(
        userId: 'u1',
        itemId: 'c1',
        itemType: ItemKind.chemical,
        action: InventoryAction.consume,
        amount: 30,
        previousQuantity: 100,
        note: '',
        loggedAt: DateTime.utc(2026, 9, 21, 9),
      );
      server.offline = false;

      // First attempt: the server applies it, the phone sees a network
      // error and keeps the change pending.
      await repository.syncPending('u1');
      expect(server.row('chemicals', 'c1')['quantity'], 70);
      var pending = await local.pendingOperations('u1');
      expect(pending, hasLength(1));
      expect(pending.single.status, PendingStatus.pending);

      // Second attempt: same operation id, the server answers "duplicate"
      // and nothing moves again.
      drop = false;
      await repository.syncPending('u1');
      expect(await local.pendingOperations('u1'), isEmpty);
      expect(server.row('chemicals', 'c1')['quantity'], 70);
      expect(server.tables['consumption_logs'], hasLength(1));
      final cached = (await local.loadRecords('u1', 'chemical')).single;
      expect(cached['quantity'], 70);
    });

    test('queues and offline copies are per user', () async {
      final server = FakePostgrest()
        ..tables['chemicals']!.add(_acetone())
        ..tables['chemicals']!.add(_acetone(userId: 'u2', id: 'c2'));
      final local = openLocal('users.db');
      addTearDown(local.close);
      await local.upsertRecord('u1', 'chemical', _acetone());
      await local.upsertRecord('u2', 'chemical', _acetone(userId: 'u2', id: 'c2'));
      final repository = InventoryRepository(
        local: local,
        remote: clientFor(server),
      );

      server.offline = true;
      await repository.updateItem(
        userId: 'u1',
        type: ItemKind.chemical,
        id: 'c1',
        changes: {'notes': 'from u1'},
      );
      await repository.updateItem(
        userId: 'u2',
        type: ItemKind.chemical,
        id: 'c2',
        changes: {'notes': 'from u2'},
      );
      expect(await local.pendingOperations('u1'), hasLength(1));
      expect(await local.pendingOperations('u2'), hasLength(1));
      expect((await local.loadRecords('u1', 'chemical')).single['id'], 'c1');
      expect((await local.loadRecords('u2', 'chemical')).single['id'], 'c2');

      // Flushing u1 sends u1's change only.
      server.offline = false;
      await repository.syncPending('u1');
      expect(await local.pendingOperations('u1'), isEmpty);
      expect(await local.pendingOperations('u2'), hasLength(1));
      expect(server.row('chemicals', 'c1')['notes'], 'from u1');
      expect(server.row('chemicals', 'c2')['notes'], '');

      // Clearing u2 (sign-out / deletion) leaves u1's copy alone.
      await local.clearUser('u2');
      expect(await local.pendingOperations('u2'), isEmpty);
      expect(await local.loadRecords('u2', 'chemical'), isEmpty);
      expect(await local.loadRecords('u1', 'chemical'), hasLength(1));
    });
  });
}
