import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/core/database/local_database.dart';
import 'package:lab_wizard/core/utils/errors.dart';
import 'package:lab_wizard/core/utils/time.dart';
import 'package:lab_wizard/features/inventory/data/inventory_repository.dart';
import 'package:lab_wizard/features/inventory/domain/models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _createLegacySchema(Database db) async {
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

void main() {
  late Directory directory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lab-wizard-test');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  LocalDatabase openLocal(String name) => LocalDatabase(
    factory: databaseFactoryFfi,
    path: p.join(directory.path, name),
  );

  group('local database', () {
    test('migrates a version 1 outbox and tracks status per change', () async {
      final path = p.join(directory.path, 'legacy.db');
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => _createLegacySchema(db),
        ),
      );
      await legacy.insert('outbox', {
        'id': 'op-1',
        'user_id': 'u1',
        'type': 'update_item',
        'payload': '{"id":"item-1","item_type":"chemical","changes":{}}',
        'created_at': DateTime(2026, 9, 20).toIso8601String(),
        'attempts': 2,
        'last_error': 'SocketException: offline',
      });
      await legacy.close();

      final local = LocalDatabase(factory: databaseFactoryFfi, path: path);
      final operations = await local.pendingOperations('u1');
      expect(operations.single.id, 'op-1');
      expect(operations.single.status, PendingStatus.pending);
      expect(operations.single.attempts, 2);
      expect(operations.single.description, 'Update item');

      await local.markAttempt('op-1', StateError('boom'), failed: true);
      expect(await local.failedCount('u1'), 1);
      expect(await local.pendingCount('u1'), 1);
      final failed = await local.pendingOperations(
        'u1',
        status: PendingStatus.failed,
      );
      expect(failed.single.attempts, 3);
      expect(failed.single.lastAttemptAt, isNotNull);
      expect(failed.single.lastError, contains('boom'));

      await local.resetOperation('op-1');
      expect(await local.failedCount('u1'), 0);

      await local.setMeta('u1', LocalDatabase.lastSyncKey, '2026-09-21T10:00');
      expect(
        await local.getMeta('u1', LocalDatabase.lastSyncKey),
        '2026-09-21T10:00',
      );
      expect(await local.getMeta('u2', LocalDatabase.lastSyncKey), isNull);

      await local.clearUser('u1');
      expect(await local.pendingCount('u1'), 0);
      expect(await local.getMeta('u1', LocalDatabase.lastSyncKey), isNull);
      await local.close();
    });
  });

  group('offline repository', () {
    test('queues labelled changes and discards them safely', () async {
      final local = openLocal('offline.db');
      addTearDown(local.close);
      final repository = InventoryRepository(local: local, remote: null);

      final chemical = await repository.addChemical(
        userId: 'u1',
        name: 'Acetone',
        formula: 'C3H6O',
        unit: 'mL',
        quantity: 100,
        threshold: 10,
        notes: '',
      );
      var snapshot = await repository.loadCached('u1');
      expect(snapshot.chemicals.single.quantity, 100);
      expect(snapshot.outbox.single.description, 'Add chemical Acetone');
      expect(snapshot.lastSyncedAt, isNull);

      final log = await repository.applyAction(
        userId: 'u1',
        itemId: chemical.id,
        itemType: ItemKind.chemical,
        action: InventoryAction.consume,
        amount: 10,
        previousQuantity: 100,
        note: 'titration',
        loggedAt: DateTime(2026, 9, 21),
        itemName: 'Acetone',
        unit: 'mL',
      );
      snapshot = await repository.loadCached('u1');
      expect(snapshot.chemicals.single.quantity, 90);
      expect(snapshot.logs.single.id, log.id);
      expect(snapshot.outbox, hasLength(2));
      expect(snapshot.outbox.last.description, 'Consume 10 mL of Acetone');
      expect(snapshot.outbox.last.itemId, chemical.id);
      expect(snapshot.pendingCount, 2);
      expect(snapshot.failedCount, 0);

      // Another user never sees these rows.
      expect((await repository.loadCached('u2')).chemicals, isEmpty);
      expect((await repository.loadCached('u2')).outbox, isEmpty);

      // Without a server there is nothing to replay.
      await repository.syncPending('u1');
      expect((await repository.loadCached('u1')).outbox, hasLength(2));

      // Discarding the action puts the offline copy back.
      await repository.discardOperation('u1', snapshot.outbox.last);
      snapshot = await repository.loadCached('u1');
      expect(snapshot.chemicals.single.quantity, 100);
      expect(snapshot.logs, isEmpty);
      expect(snapshot.outbox.single.type, 'add_chemical');

      // Discarding the add removes the item that never reached the server.
      await repository.discardOperation('u1', snapshot.outbox.single);
      snapshot = await repository.loadCached('u1');
      expect(snapshot.chemicals, isEmpty);
      expect(snapshot.outbox, isEmpty);
    });

    test('discarding an add also drops changes that depend on it', () async {
      final local = openLocal('cascade.db');
      addTearDown(local.close);
      final repository = InventoryRepository(local: local, remote: null);

      final item = await repository.addApparatus(
        userId: 'u1',
        name: 'Beaker 250 mL',
        category: 'glassware',
        quantity: 12,
        threshold: 2,
        notes: '',
      );
      await repository.applyAction(
        userId: 'u1',
        itemId: item.id,
        itemType: ItemKind.apparatus,
        action: InventoryAction.breakage,
        amount: 1,
        previousQuantity: 12,
        note: '',
        loggedAt: DateTime(2026, 9, 21),
        itemName: item.name,
      );
      await repository.updateItem(
        userId: 'u1',
        type: ItemKind.apparatus,
        id: item.id,
        changes: {'low_stock_threshold': 4},
        itemName: item.name,
      );
      var snapshot = await repository.loadCached('u1');
      expect(snapshot.outbox, hasLength(3));
      expect(
        snapshot.outbox[1].description,
        'Record damage of 1 pcs of Beaker 250 mL',
      );
      expect(snapshot.outbox[2].description, 'Update Beaker 250 mL');
      expect(snapshot.outbox[2].payload['previous'], {
        'low_stock_threshold': 2,
      });
      expect(snapshot.apparatus.single.lowStockThreshold, 4);

      // Discarding the edit restores the previous field value.
      await repository.discardOperation('u1', snapshot.outbox[2]);
      snapshot = await repository.loadCached('u1');
      expect(snapshot.apparatus.single.lowStockThreshold, 2);
      expect(snapshot.apparatus.single.quantity, 11);

      await repository.discardOperation('u1', snapshot.outbox.first);
      snapshot = await repository.loadCached('u1');
      expect(snapshot.apparatus, isEmpty);
      expect(snapshot.logs, isEmpty);
      expect(snapshot.outbox, isEmpty);
    });
  });

  group('undo (UX-04)', () {
    test('a queued action is cancelled instead of reversed', () async {
      final local = openLocal('undo-queued.db');
      addTearDown(local.close);
      final repository = InventoryRepository(local: local, remote: null);
      final chemical = await repository.addChemical(
        userId: 'u1',
        name: 'Ethanol',
        formula: 'C2H6O',
        unit: 'mL',
        quantity: 100,
        threshold: 10,
        notes: '',
      );
      final log = await repository.applyAction(
        userId: 'u1',
        itemId: chemical.id,
        itemType: ItemKind.chemical,
        action: InventoryAction.consume,
        amount: 25,
        previousQuantity: 100,
        note: '',
        loggedAt: DateTime(2026, 9, 21),
      );
      expect(log.operationId, isNotNull);

      final result = await repository.undoAction(
        userId: 'u1',
        log: log,
        currentQuantity: 75,
      );
      expect(result.cancelled, isTrue);
      expect(result.reversal, isNull);

      final snapshot = await repository.loadCached('u1');
      expect(snapshot.chemicals.single.quantity, 100);
      expect(snapshot.logs, isEmpty);
      expect(snapshot.reversals, isEmpty);
      expect(snapshot.outbox.single.type, 'add_chemical');
    });

    test('a synced action is undone offline and can be discarded', () async {
      final local = openLocal('undo-offline.db');
      addTearDown(local.close);
      final repository = InventoryRepository(local: local, remote: null);
      final chemical = Chemical(
        id: 'chem-1',
        name: 'Acetone',
        formula: 'C3H6O',
        unit: 'mL',
        quantity: 60,
        initialQuantity: 100,
        lowStockThreshold: 10,
        notes: '',
        qrCode: 'qr-1',
        createdAt: DateTime(2026, 1, 1),
      );
      final log = ConsumptionLog(
        id: 'log-1',
        itemId: chemical.id,
        itemType: ItemKind.chemical,
        action: InventoryAction.consume,
        amount: 40,
        note: 'spill',
        loggedAt: DateTime(2026, 9, 20, 12),
        createdAt: DateTime(2026, 9, 20, 12),
      );
      await local.upsertRecord('u1', 'chemical', chemical.toMap());
      await local.upsertRecord('u1', 'log', log.toMap());

      final result = await repository.undoAction(
        userId: 'u1',
        log: log,
        currentQuantity: 60,
        itemName: 'Acetone',
        unit: 'mL',
      );
      expect(result.cancelled, isFalse);
      expect(result.reversal, isNotNull);
      expect(result.reversal!.originalLogId, 'log-1');
      expect(result.reversal!.originalNote, 'spill');

      var snapshot = await repository.loadCached('u1');
      expect(snapshot.chemicals.single.quantity, 100);
      expect(snapshot.logs, isEmpty);
      expect(snapshot.reversals.single.action, InventoryAction.consume);
      expect(snapshot.reversals.single.amount, 40);
      expect(snapshot.outbox.single.type, 'undo_action');
      expect(
        snapshot.outbox.single.description,
        'Undo: Consume 40 mL of Acetone',
      );
      expect(snapshot.outbox.single.itemId, chemical.id);

      // Discarding the queued undo brings the entry and the quantity back.
      await repository.discardOperation('u1', snapshot.outbox.single);
      snapshot = await repository.loadCached('u1');
      expect(snapshot.chemicals.single.quantity, 60);
      expect(snapshot.logs.single.id, 'log-1');
      expect(snapshot.reversals, isEmpty);
      expect(snapshot.outbox, isEmpty);
    });

    test('a restock cannot be undone when the stock is already used', () async {
      final local = openLocal('undo-guard.db');
      addTearDown(local.close);
      final repository = InventoryRepository(local: local, remote: null);
      final log = ConsumptionLog(
        id: 'log-2',
        itemId: 'app-1',
        itemType: ItemKind.apparatus,
        action: InventoryAction.restock,
        amount: 10,
        note: '',
        loggedAt: DateTime(2026, 9, 20),
        createdAt: DateTime(2026, 9, 20),
      );
      await expectLater(
        repository.undoAction(userId: 'u1', log: log, currentQuantity: 4),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('only 4 left of the 10'),
          ),
        ),
      );
    });

    test('undo window is seven days', () {
      final now = DateTime(2026, 9, 21, 12);
      ConsumptionLog logAt(DateTime createdAt) => ConsumptionLog(
        id: 'x',
        itemId: 'i',
        itemType: ItemKind.chemical,
        action: InventoryAction.consume,
        amount: 1,
        note: '',
        loggedAt: createdAt,
        createdAt: createdAt,
      );
      expect(
        isUndoable(logAt(now.subtract(const Duration(days: 6))), now: now),
        isTrue,
      );
      expect(
        isUndoable(logAt(now.subtract(const Duration(days: 8))), now: now),
        isFalse,
      );
    });
  });

  group('checkouts (GEAR-02)', () {
    test('loans and returns queue offline and can be discarded', () async {
      final local = openLocal('checkouts.db');
      addTearDown(local.close);
      final repository = InventoryRepository(local: local, remote: null);

      final item = await repository.addApparatus(
        userId: 'u1',
        name: 'Multimeter',
        category: 'electronics',
        quantity: 3,
        threshold: 1,
        notes: '',
      );
      final due = DateTime(2026, 10, 1, 23, 59);
      final checkout = await repository.checkoutApparatus(
        userId: 'u1',
        apparatusId: item.id,
        quantity: 2,
        person: ' Aisha ',
        note: 'lab 4',
        dueAt: due,
        itemName: item.name,
      );
      expect(checkout.person, 'Aisha');
      expect(checkout.isOpen, isTrue);
      expect(checkout.outstanding, 2);
      expect(checkout.isOverdue(now: DateTime(2026, 9, 21)), isFalse);
      expect(checkout.isOverdue(now: DateTime(2026, 10, 2)), isTrue);

      var snapshot = await repository.loadCached('u1');
      expect(snapshot.checkouts.single.id, checkout.id);
      expect(snapshot.checkouts.single.dueAt, due);
      expect(snapshot.outbox, hasLength(2));
      final queued = snapshot.outbox.last;
      expect(queued.type, 'checkout_apparatus');
      expect(queued.description, 'Check out Multimeter to Aisha');
      expect(queued.itemId, item.id);
      expect(queued.payload['id'], checkout.id);
      expect(queued.payload['user_id'], 'u1');
      expect(queued.payload['operation_id'], isNotNull);
      // Apparatus stock itself is untouched by a loan.
      expect(snapshot.apparatus.single.quantity, 3);

      // A partial return keeps the loan open.
      final partial = await repository.returnApparatus(
        userId: 'u1',
        checkout: checkout,
        quantity: 1,
        note: 'one probe missing',
        itemName: item.name,
      );
      expect(partial.isOpen, isTrue);
      expect(partial.outstanding, 1);
      expect(partial.returnedAt, isNull);
      expect(partial.returnNote, 'one probe missing');
      snapshot = await repository.loadCached('u1');
      expect(snapshot.checkouts.single.returnedQuantity, 1);
      expect(snapshot.outbox, hasLength(3));
      expect(snapshot.outbox.last.type, 'return_apparatus');
      expect(snapshot.outbox.last.description, 'Return 1 × Multimeter');
      expect(snapshot.outbox.last.payload['previous'], {
        'returned_quantity': 0,
        'returned_at': null,
        'return_note': '',
      });

      // Returning the rest closes the loan.
      final closed = await repository.returnApparatus(
        userId: 'u1',
        checkout: partial,
        quantity: 1,
        note: '',
        itemName: item.name,
      );
      expect(closed.isOpen, isFalse);
      expect(closed.returnedAt, isNotNull);
      expect(closed.outstanding, 0);
      snapshot = await repository.loadCached('u1');
      expect(snapshot.checkouts.single.isOpen, isFalse);
      expect(snapshot.outbox, hasLength(4));

      // Discarding the last return reopens the loan with one piece out.
      await repository.discardOperation('u1', snapshot.outbox.last);
      snapshot = await repository.loadCached('u1');
      expect(snapshot.checkouts.single.isOpen, isTrue);
      expect(snapshot.checkouts.single.outstanding, 1);
      expect(snapshot.outbox, hasLength(3));

      // Discarding the checkout drops the loan and its queued return.
      await repository.discardOperation('u1', snapshot.outbox[1]);
      snapshot = await repository.loadCached('u1');
      expect(snapshot.checkouts, isEmpty);
      expect(snapshot.outbox.single.type, 'add_apparatus');
    });

    test('a loan on an unsynced apparatus disappears with it', () async {
      final local = openLocal('checkout-cascade.db');
      addTearDown(local.close);
      final repository = InventoryRepository(local: local, remote: null);

      final item = await repository.addApparatus(
        userId: 'u1',
        name: 'Hot plate',
        category: 'heating',
        quantity: 1,
        threshold: 0,
        notes: '',
      );
      await repository.checkoutApparatus(
        userId: 'u1',
        apparatusId: item.id,
        quantity: 1,
        person: 'Bilal',
        note: '',
        itemName: item.name,
      );
      var snapshot = await repository.loadCached('u1');
      expect(snapshot.checkouts, hasLength(1));
      expect(snapshot.outbox, hasLength(2));

      await repository.discardOperation('u1', snapshot.outbox.first);
      snapshot = await repository.loadCached('u1');
      expect(snapshot.apparatus, isEmpty);
      expect(snapshot.checkouts, isEmpty);
      expect(snapshot.outbox, isEmpty);
      // Other users never see the loan either.
      expect((await repository.loadCached('u2')).checkouts, isEmpty);
    });

    test('checkout rows round-trip through the cache format', () {
      final checkout = ApparatusCheckout(
        id: 'c1',
        apparatusId: 'a1',
        quantity: 2,
        returnedQuantity: 1,
        person: 'Sara',
        note: 'bench 2',
        returnNote: 'scratched',
        checkedOutAt: DateTime(2026, 9, 20, 10, 30),
        dueAt: DateTime(2026, 9, 27, 23, 59),
        operationId: 'op-1',
      );
      final map = checkout.toMap();
      expect(map['checked_out_at'], endsWith('Z'));
      expect(map['returned_at'], isNull);
      final parsed = ApparatusCheckout.fromMap(map);
      expect(parsed.checkedOutAt, checkout.checkedOutAt);
      expect(parsed.dueAt, checkout.dueAt);
      expect(parsed.outstanding, 1);
      expect(parsed.isOpen, isTrue);
      expect(parsed.operationId, 'op-1');
      expect(parsed.copyWith(returnedQuantity: 2).isOpen, isFalse);
      expect(
        parsed.copyWith(returnedAt: DateTime(2026, 9, 21)).isOpen,
        isFalse,
      );
      expect(
        ApparatusCheckout.fromMap({
          'id': 'c2',
          'apparatus_id': 'a1',
          'quantity': '3',
          'returned_quantity': null,
          'checked_out_at': null,
        }).outstanding,
        3,
      );
    });
  });

  group('services (GEAR-03)', () {
    test('tasks are scheduled and completed offline with rollback', () async {
      final local = openLocal('services.db');
      addTearDown(local.close);
      final repository = InventoryRepository(local: local, remote: null);

      final item = await repository.addApparatus(
        userId: 'u1',
        name: 'pH meter',
        category: 'electronics',
        quantity: 1,
        threshold: 0,
        notes: '',
      );
      final due = DateTime(2026, 9, 30, 23, 59);
      final task = await repository.scheduleService(
        userId: 'u1',
        apparatusId: item.id,
        kind: ServiceKind.calibration,
        title: ' Buffer check ',
        note: 'pH 4 / 7 / 10',
        dueAt: due,
        itemName: item.name,
      );
      expect(task.title, 'Buffer check');
      expect(task.isOpen, isTrue);
      expect(task.dueState(now: DateTime(2026, 9, 21)), ExpiryState.expiringSoon);
      expect(task.dueState(now: DateTime(2026, 8, 1)), ExpiryState.ok);
      expect(task.dueState(now: DateTime(2026, 10, 2)), ExpiryState.expired);
      expect(task.isOverdue(now: DateTime(2026, 10, 2)), isTrue);

      var snapshot = await repository.loadCached('u1');
      expect(snapshot.services.single.id, task.id);
      expect(snapshot.services.single.dueAt, due);
      expect(snapshot.outbox, hasLength(2));
      expect(snapshot.outbox.last.type, 'schedule_service');
      expect(
        snapshot.outbox.last.description,
        'Schedule calibration for pH meter',
      );
      expect(snapshot.outbox.last.itemId, item.id);
      expect(snapshot.outbox.last.payload['user_id'], 'u1');
      expect(snapshot.outbox.last.payload['kind'], 'calibration');

      final done = await repository.completeService(
        userId: 'u1',
        service: task,
        completedAt: DateTime(2026, 9, 22, 10),
        performedBy: 'Sara',
        result: 'pass',
        note: 'slope 98%',
        itemName: item.name,
      );
      expect(done.isDone, isTrue);
      expect(done.performedBy, 'Sara');
      expect(done.result, 'pass');
      expect(done.note, 'pH 4 / 7 / 10 · slope 98%');
      expect(done.dueState(now: DateTime(2026, 10, 2)), ExpiryState.none);
      snapshot = await repository.loadCached('u1');
      expect(snapshot.services.single.isDone, isTrue);
      expect(snapshot.outbox, hasLength(3));
      expect(snapshot.outbox.last.type, 'complete_service');
      expect(
        snapshot.outbox.last.description,
        'Complete calibration of pH meter',
      );
      expect(snapshot.outbox.last.payload['previous'], {
        'completed_at': null,
        'performed_by': '',
        'result': '',
        'note': 'pH 4 / 7 / 10',
      });

      // Discarding the completion reopens the task with its old note.
      await repository.discardOperation('u1', snapshot.outbox.last);
      snapshot = await repository.loadCached('u1');
      expect(snapshot.services.single.isOpen, isTrue);
      expect(snapshot.services.single.note, 'pH 4 / 7 / 10');
      expect(snapshot.services.single.performedBy, '');

      // Discarding the schedule removes the task entirely.
      await repository.discardOperation('u1', snapshot.outbox.last);
      snapshot = await repository.loadCached('u1');
      expect(snapshot.services, isEmpty);
      expect(snapshot.outbox.single.type, 'add_apparatus');
    });

    test('open tasks sort by due date ahead of completed ones', () {
      ApparatusService task(
        String id, {
        DateTime? due,
        DateTime? done,
        DateTime? created,
      }) => ApparatusService(
        id: id,
        apparatusId: 'a1',
        kind: ServiceKind.maintenance,
        createdAt: created ?? DateTime(2026, 1, 1),
        dueAt: due,
        completedAt: done,
      );
      final sorted = InventoryRepository.sortedServices([
        task('done-old', done: DateTime(2026, 5, 1)),
        task('undated', created: DateTime(2026, 3, 1)),
        task('later', due: DateTime(2026, 12, 1)),
        task('done-new', done: DateTime(2026, 8, 1)),
        task('soon', due: DateTime(2026, 10, 1)),
      ]);
      expect(sorted.map((t) => t.id), [
        'soon',
        'later',
        'undated',
        'done-new',
        'done-old',
      ]);
      final map = task('x', due: DateTime(2026, 10, 1, 23, 59)).toMap();
      expect(map['kind'], 'maintenance');
      expect(map['due_at'], endsWith('Z'));
      final parsed = ApparatusService.fromMap(map);
      expect(parsed.dueAt, DateTime(2026, 10, 1, 23, 59));
      expect(parsed.displayTitle, 'Maintenance');
      expect(ServiceKind.parse('calibration'), ServiceKind.calibration);
      expect(ServiceKind.parse('anything'), ServiceKind.maintenance);
    });
  });

  group('sync center copy', () {
    test('relative times read like a notebook note', () {
      final now = DateTime(2026, 9, 21, 12);
      expect(relativeTime(now, now: now), 'just now');
      expect(
        relativeTime(now.subtract(const Duration(minutes: 5)), now: now),
        '5 min ago',
      );
      expect(
        relativeTime(now.subtract(const Duration(hours: 3)), now: now),
        '3 h ago',
      );
      expect(
        relativeTime(now.subtract(const Duration(hours: 30)), now: now),
        'yesterday',
      );
      expect(
        relativeTime(now.subtract(const Duration(days: 3)), now: now),
        '3 days ago',
      );
      expect(
        relativeTime(now.subtract(const Duration(days: 30)), now: now),
        '22 Aug',
      );
    });

    test('errors are explained without stack noise', () {
      expect(
        friendlyErrorMessage('SocketException: Failed host lookup'),
        contains('offline'),
      );
      expect(
        friendlyErrorMessage('PostgrestException: Insufficient stock: only 2'),
        contains('less stock'),
      );
      expect(
        friendlyErrorMessage('StateError: Item not found or not owned'),
        contains('no longer exists'),
      );
      expect(
        friendlyErrorMessage(''),
        'Something went wrong. Please try again.',
      );
    });
  });
}
