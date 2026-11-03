import 'package:collection/collection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/local_database.dart';
import '../domain/models.dart';

class InventorySnapshot {
  const InventorySnapshot({
    required this.chemicals,
    required this.apparatus,
    required this.logs,
    required this.pendingCount,
    required this.fromCache,
  });

  final List<Chemical> chemicals;
  final List<Apparatus> apparatus;
  final List<ConsumptionLog> logs;
  final int pendingCount;
  final bool fromCache;
}

class InventoryRepository {
  InventoryRepository({required this.local, required this.remote});

  final LocalDatabase local;
  final SupabaseClient? remote;
  final Uuid _uuid = const Uuid();
  bool? _atomicRpcAvailable;

  Future<InventorySnapshot> loadCached(String userId) async {
    final results = await Future.wait([
      local.loadRecords(userId, 'chemical'),
      local.loadRecords(userId, 'apparatus'),
      local.loadRecords(userId, 'log'),
      local.pendingCount(userId),
    ]);
    return InventorySnapshot(
      chemicals: (results[0] as List<Map<String, dynamic>>)
          .map(Chemical.fromMap)
          .toList(),
      apparatus: (results[1] as List<Map<String, dynamic>>)
          .map(Apparatus.fromMap)
          .toList(),
      logs: (results[2] as List<Map<String, dynamic>>)
          .map(ConsumptionLog.fromMap)
          .toList(),
      pendingCount: results[3] as int,
      fromCache: true,
    );
  }

  Future<InventorySnapshot> refresh(String userId) async {
    final client = remote;
    if (client == null) return loadCached(userId);

    final responses = await Future.wait<dynamic>([
      client.from('chemicals').select().order('created_at', ascending: false),
      client.from('apparatus').select().order('created_at', ascending: false),
      client
          .from('consumption_logs')
          .select()
          .order('logged_at', ascending: false),
    ]);

    final chemicalMaps = _mapList(responses[0]);
    final apparatusMaps = _mapList(responses[1]);
    final logMaps = _mapList(responses[2]);

    // Anything with an operation still in the outbox is newer than the server
    // copy, so the local row wins. Without this, a pull-to-refresh after a
    // failed upload quietly reverts the user's own changes.
    final pending = await local.pendingOperations(userId);
    final protectedChemicals = <String>{};
    final protectedApparatus = <String>{};
    final protectedLogs = <String>{};
    for (final operation in pending) {
      final payload = operation.payload;
      final itemId = payload['item_id'] ?? payload['id'];
      if (itemId is String) {
        if (payload['item_type'] == 'apparatus' ||
            operation.type == 'add_apparatus') {
          protectedApparatus.add(itemId);
        } else {
          protectedChemicals.add(itemId);
        }
      }
      final logId = payload['local_log_id'];
      if (logId is String) protectedLogs.add(logId);
    }

    Future<List<Map<String, dynamic>>> merged(
      String kind,
      List<Map<String, dynamic>> fromServer,
      Set<String> protected,
    ) async {
      if (protected.isEmpty) return fromServer;
      final cached = await local.loadRecords(userId, kind);
      final keep = cached
          .where((row) => protected.contains(row['id'] as String?))
          .toList();
      final keptIds = keep.map((row) => row['id']).toSet();
      return [
        ...keep,
        ...fromServer.where((row) => !keptIds.contains(row['id'])),
      ];
    }

    final chemicals = await merged(
      'chemical',
      chemicalMaps,
      protectedChemicals,
    );
    final apparatus = await merged(
      'apparatus',
      apparatusMaps,
      protectedApparatus,
    );
    final logs = await merged('log', logMaps, protectedLogs);

    await Future.wait([
      local.replaceRecords(userId, 'chemical', chemicals),
      local.replaceRecords(userId, 'apparatus', apparatus),
      local.replaceRecords(userId, 'log', logs),
    ]);

    return InventorySnapshot(
      chemicals: chemicals.map(Chemical.fromMap).toList(),
      apparatus: apparatus.map(Apparatus.fromMap).toList(),
      logs: logs.map(ConsumptionLog.fromMap).toList(),
      pendingCount: await local.pendingCount(userId),
      fromCache: false,
    );
  }

  Future<Chemical> addChemical({
    required String userId,
    required String name,
    required String formula,
    required String unit,
    required double quantity,
    required double threshold,
    required String notes,
  }) async {
    final now = DateTime.now();
    final chemical = Chemical(
      id: _uuid.v4(),
      name: name.trim(),
      formula: formula.trim(),
      unit: unit,
      quantity: quantity,
      initialQuantity: quantity,
      lowStockThreshold: threshold,
      notes: notes.trim(),
      qrCode: _uuid.v4(),
      createdAt: now,
    );
    final payload = {...chemical.toMap(), 'user_id': userId};
    try {
      final data = await remote!
          .from('chemicals')
          .insert(payload)
          .select()
          .single();
      final saved = Chemical.fromMap(data);
      await local.upsertRecord(userId, 'chemical', saved.toMap());
      return saved;
    } catch (error) {
      if (remote == null || _isConnectivityError(error)) {
        await local.upsertRecord(userId, 'chemical', chemical.toMap());
        await local.enqueue(
          PendingOperation(
            id: _uuid.v4(),
            userId: userId,
            type: 'add_chemical',
            payload: payload,
            createdAt: now,
          ),
        );
        return chemical;
      }
      rethrow;
    }
  }

  Future<Apparatus> addApparatus({
    required String userId,
    required String name,
    required String category,
    required double quantity,
    required double threshold,
    required String notes,
  }) async {
    final now = DateTime.now();
    final item = Apparatus(
      id: _uuid.v4(),
      name: name.trim(),
      category: category,
      quantity: quantity,
      initialQuantity: quantity,
      lowStockThreshold: threshold,
      notes: notes.trim(),
      createdAt: now,
    );
    final payload = {...item.toMap(), 'user_id': userId};
    try {
      final data = await remote!
          .from('apparatus')
          .insert(payload)
          .select()
          .single();
      final saved = Apparatus.fromMap(data);
      await local.upsertRecord(userId, 'apparatus', saved.toMap());
      return saved;
    } catch (error) {
      if (remote == null || _isConnectivityError(error)) {
        await local.upsertRecord(userId, 'apparatus', item.toMap());
        await local.enqueue(
          PendingOperation(
            id: _uuid.v4(),
            userId: userId,
            type: 'add_apparatus',
            payload: payload,
            createdAt: now,
          ),
        );
        return item;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateItem({
    required String userId,
    required ItemKind type,
    required String id,
    required Map<String, dynamic> changes,
  }) async {
    final table = type == ItemKind.chemical ? 'chemicals' : 'apparatus';
    try {
      final data = await remote!
          .from(table)
          .update(changes)
          .eq('id', id)
          .select()
          .single();
      final saved = Map<String, dynamic>.from(data);
      await local.upsertRecord(userId, type.name, saved);
      return saved;
    } catch (error) {
      if (remote != null && !_isConnectivityError(error)) rethrow;
      final records = await local.loadRecords(userId, type.name);
      final current = records.where((row) => row['id'] == id).firstOrNull;
      if (current == null) {
        throw StateError('The item is not available offline.');
      }
      final saved = <String, dynamic>{...current, ...changes, 'id': id};
      await local.upsertRecord(userId, type.name, saved);
      await local.enqueue(
        PendingOperation(
          id: _uuid.v4(),
          userId: userId,
          type: 'update_item',
          payload: {'id': id, 'item_type': type.name, 'changes': changes},
          createdAt: DateTime.now(),
        ),
      );
      return saved;
    }
  }

  Future<ConsumptionLog> applyAction({
    required String userId,
    required String itemId,
    required ItemKind itemType,
    required InventoryAction action,
    required double amount,
    required double previousQuantity,
    required String note,
    required DateTime loggedAt,
  }) async {
    final operationId = _uuid.v4();
    final newQuantity = _quantityAfter(previousQuantity, action, amount);
    final optimisticLog = ConsumptionLog(
      id: _uuid.v4(),
      itemId: itemId,
      itemType: itemType,
      action: action,
      amount: amount,
      note: note.trim(),
      loggedAt: localDayAtNoon(loggedAt),
      createdAt: DateTime.now(),
      operationId: operationId,
    );

    final payload = <String, dynamic>{
      'operation_id': operationId,
      'item_id': itemId,
      'item_type': itemType.name,
      'action': action.name,
      'amount': amount,
      'previous_quantity': previousQuantity,
      'new_quantity': newQuantity,
      'note': note.trim(),
      'logged_at': optimisticLog.loggedAt.toUtc().toIso8601String(),
      'local_log_id': optimisticLog.id,
    };

    try {
      if (remote == null) throw const _OfflineException();
      final result = await _applyRemoteAction(userId, payload);
      final logMap = result['log'];
      final itemMap = result['item'];
      final log = logMap is Map
          ? ConsumptionLog.fromMap(Map<String, dynamic>.from(logMap))
          : optimisticLog;
      if (itemMap is Map) {
        await local.upsertRecord(
          userId,
          itemType.name,
          Map<String, dynamic>.from(itemMap),
        );
      }
      await local.upsertRecord(userId, 'log', log.toMap());
      return log;
    } catch (error) {
      if (!_isConnectivityError(error) && error is! _OfflineException) rethrow;
      await _cacheOptimisticQuantity(
        userId: userId,
        itemType: itemType,
        itemId: itemId,
        newQuantity: newQuantity,
      );
      await local.upsertRecord(userId, 'log', optimisticLog.toMap());
      await local.enqueue(
        PendingOperation(
          id: operationId,
          userId: userId,
          type: 'inventory_action',
          payload: payload,
          createdAt: DateTime.now(),
        ),
      );
      return optimisticLog;
    }
  }

  Future<Map<String, dynamic>> _applyRemoteAction(
    String userId,
    Map<String, dynamic> payload,
  ) async {
    if (_atomicRpcAvailable != false) {
      try {
        final response = await remote!.rpc(
          'apply_inventory_action',
          params: {
            'p_operation_id': payload['operation_id'],
            'p_item_id': payload['item_id'],
            'p_item_type': payload['item_type'],
            'p_action': payload['action'],
            'p_amount': payload['amount'],
            'p_note': payload['note'],
            'p_logged_at': payload['logged_at'],
          },
        );
        _atomicRpcAvailable = true;
        return Map<String, dynamic>.from(response as Map);
      } on PostgrestException catch (error) {
        if (!_isMissingFunction(error)) rethrow;
        _atomicRpcAvailable = false;
      }
    }
    return _compatibilityAction(userId, payload);
  }

  Future<Map<String, dynamic>> _compatibilityAction(
    String userId,
    Map<String, dynamic> payload,
  ) async {
    final table = payload['item_type'] == 'chemical'
        ? 'chemicals'
        : 'apparatus';
    final itemId = payload['item_id'] as String;
    final previous = _asNum(payload['previous_quantity']);
    final updated = await remote!
        .from(table)
        .update({'quantity': payload['new_quantity']})
        .eq('id', itemId)
        .select()
        .single();
    try {
      final logPayload = {
        'id': payload['local_log_id'],
        'user_id': userId,
        'item_id': itemId,
        'item_type': payload['item_type'],
        'action': payload['action'],
        'amount': payload['amount'],
        'note': payload['note'],
        'logged_at': payload['logged_at'],
      };
      final log = await remote!
          .from('consumption_logs')
          .insert(logPayload)
          .select()
          .single();
      return {'item': updated, 'log': log};
    } catch (_) {
      // Best-effort compensation for deployments that have not installed the
      // additive transactional RPC yet.
      await remote!.from(table).update({'quantity': previous}).eq('id', itemId);
      rethrow;
    }
  }

  Future<void> _cacheOptimisticQuantity({
    required String userId,
    required ItemKind itemType,
    required String itemId,
    required double newQuantity,
  }) async {
    final rows = await local.loadRecords(userId, itemType.name);
    final current = rows.where((row) => row['id'] == itemId).firstOrNull;
    if (current == null) return;
    await local.upsertRecord(userId, itemType.name, {
      ...current,
      'quantity': newQuantity,
    });
  }

  /// Reverses a logged action: the quantity is restored and the log removed.
  /// Queued for later if the phone is offline, so undo works on a bad signal.
  Future<double> revertAction({
    required String userId,
    required ConsumptionLog log,
    required double currentQuantity,
  }) async {
    final restored = switch (log.action) {
      InventoryAction.restock => (currentQuantity - log.amount)
          .clamp(0, double.infinity)
          .toDouble(),
      InventoryAction.consume ||
      InventoryAction.breakage => currentQuantity + log.amount,
    };
    final table = log.itemType == ItemKind.chemical ? 'chemicals' : 'apparatus';

    try {
      if (remote == null) throw const _OfflineException();
      await remote!
          .from(table)
          .update({'quantity': restored})
          .eq('id', log.itemId);
      await remote!.from('consumption_logs').delete().eq('id', log.id);
    } catch (error) {
      if (!_isConnectivityError(error) && error is! _OfflineException) rethrow;
      await local.enqueue(
        PendingOperation(
          id: _uuid.v4(),
          userId: userId,
          type: 'undo_action',
          payload: {
            'log': log.toMap(),
            'restored_quantity': restored,
          },
          createdAt: DateTime.now(),
        ),
      );
    }

    final rows = await local.loadRecords(userId, log.itemType.name);
    final current = rows
        .where((row) => row['id'] == log.itemId)
        .firstOrNull;
    if (current != null) {
      await local.upsertRecord(userId, log.itemType.name, {
        ...current,
        'quantity': restored,
      });
    }
    await local.deleteRecord(userId, 'log', log.id);
    return restored;
  }

  /// Corrects an entry that was logged wrong, days later.
  ///
  /// Nothing is guessed at: the quantity is first wound back to what it was
  /// before the old entry, then wound forward by the corrected entry, so the
  /// shelf ends up exactly where it would have been had the entry been right
  /// the first time. The log keeps its id, so the report simply shows the
  /// corrected numbers.
  Future<double> correctAction({
    required String userId,
    required ConsumptionLog log,
    required InventoryAction action,
    required double amount,
    required String note,
    required DateTime loggedAt,
    required double currentQuantity,
  }) async {
    final corrected = quantityAfterCorrection(
      currentQuantity: currentQuantity,
      oldAction: log.action,
      oldAmount: log.amount,
      newAction: action,
      newAmount: amount,
    );
    final table = log.itemType == ItemKind.chemical ? 'chemicals' : 'apparatus';
    final fields = <String, dynamic>{
      'action': action.name,
      'amount': amount,
      'note': note.trim(),
      'logged_at': localDayAtNoon(loggedAt).toUtc().toIso8601String(),
    };

    try {
      if (remote == null) throw const _OfflineException();
      await remote!
          .from('consumption_logs')
          .update(fields)
          .eq('id', log.id);
      await remote!
          .from(table)
          .update({'quantity': corrected})
          .eq('id', log.itemId);
    } catch (error) {
      if (!_isConnectivityError(error) && error is! _OfflineException) rethrow;
      await local.enqueue(
        PendingOperation(
          id: _uuid.v4(),
          userId: userId,
          type: 'correct_action',
          payload: {
            'log_id': log.id,
            'item_id': log.itemId,
            'item_type': log.itemType.name,
            'fields': fields,
            'quantity': corrected,
          },
          createdAt: DateTime.now(),
        ),
      );
    }

    final rows = await local.loadRecords(userId, log.itemType.name);
    final current = rows.where((row) => row['id'] == log.itemId).firstOrNull;
    if (current != null) {
      await local.upsertRecord(userId, log.itemType.name, {
        ...current,
        'quantity': corrected,
      });
    }
    await local.upsertRecord(userId, 'log', {
      ...log.toMap(),
      ...fields,
    });
    return corrected;
  }

  Future<void> deleteItem({
    required String userId,
    required ItemKind type,
    required String id,
  }) async {
    final table = type == ItemKind.chemical ? 'chemicals' : 'apparatus';
    if (remote == null) {
      throw StateError('Deleting items requires a connection.');
    }
    await remote!.from(table).delete().eq('id', id);
    try {
      await remote!
          .from('consumption_logs')
          .delete()
          .eq('item_id', id)
          .eq('item_type', type.name);
    } catch (_) {
      // Orphaned log rows are harmless: they are filtered out by item id. An
      // item left behind after its history was deleted would not be.
    }
    await local.deleteRecord(userId, type.name, id);
  }

  Future<int> syncPending(String userId) async {
    if (remote == null) return local.pendingCount(userId);
    final operations = await local.pendingOperations(userId);
    for (final operation in operations) {
      try {
        if (operation.type == 'add_chemical') {
          await remote!.from('chemicals').upsert(operation.payload);
        } else if (operation.type == 'add_apparatus') {
          await remote!.from('apparatus').upsert(operation.payload);
        } else if (operation.type == 'inventory_action') {
          await _applyRemoteAction(userId, operation.payload);
        } else if (operation.type == 'correct_action') {
          final fields = Map<String, dynamic>.from(
            operation.payload['fields'] as Map,
          );
          final itemType = operation.payload['item_type'] as String;
          final table = itemType == 'apparatus' ? 'apparatus' : 'chemicals';
          await remote!
              .from('consumption_logs')
              .update(fields)
              .eq('id', operation.payload['log_id'] as String);
          await remote!
              .from(table)
              .update({'quantity': operation.payload['quantity']})
              .eq('id', operation.payload['item_id'] as String);
        } else if (operation.type == 'undo_action') {
          final logMap = Map<String, dynamic>.from(
            operation.payload['log'] as Map,
          );
          final log = ConsumptionLog.fromMap(logMap);
          final table = log.itemType == ItemKind.chemical
              ? 'chemicals'
              : 'apparatus';
          await remote!
              .from(table)
              .update({
                'quantity': operation.payload['restored_quantity'],
              })
              .eq('id', log.itemId);
          await remote!.from('consumption_logs').delete().eq('id', log.id);
        } else if (operation.type == 'update_item') {
          final table = operation.payload['item_type'] == 'chemical'
              ? 'chemicals'
              : 'apparatus';
          await remote!
              .from(table)
              .update(
                Map<String, dynamic>.from(operation.payload['changes'] as Map),
              )
              .eq('id', operation.payload['id']);
        } else {
          throw StateError('Unknown operation ${operation.type}');
        }
        await local.completeOperation(operation.id);
      } catch (error) {
        await local.markAttempt(operation.id, error);
        break;
      }
    }
    return local.pendingCount(userId);
  }

  static List<Map<String, dynamic>> _mapList(dynamic value) => (value as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  static double _quantityAfter(
    double current,
    InventoryAction action,
    double amount,
  ) => switch (action) {
    InventoryAction.consume ||
    InventoryAction.breakage => (current - amount).clamp(0, double.infinity),
    InventoryAction.restock => current + amount,
  };

  static double _asNum(Object? value) => (value as num).toDouble();

  static bool _isMissingFunction(PostgrestException error) =>
      error.code == 'PGRST202' ||
      error.message.toLowerCase().contains('function');

  static bool _isConnectivityError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('socket') ||
        message.contains('network') ||
        message.contains('connection') ||
        message.contains('timed out') ||
        message.contains('failed host lookup') ||
        message.contains('clientexception');
  }
}

class _OfflineException implements Exception {
  const _OfflineException();
}

