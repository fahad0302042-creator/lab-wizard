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

    await Future.wait([
      local.replaceRecords(userId, 'chemical', chemicalMaps),
      local.replaceRecords(userId, 'apparatus', apparatusMaps),
      local.replaceRecords(userId, 'log', logMaps),
    ]);

    return InventorySnapshot(
      chemicals: chemicalMaps.map(Chemical.fromMap).toList(),
      apparatus: apparatusMaps.map(Apparatus.fromMap).toList(),
      logs: logMaps.map(ConsumptionLog.fromMap).toList(),
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

  Future<void> deleteItem({
    required String userId,
    required ItemKind type,
    required String id,
  }) async {
    final table = type == ItemKind.chemical ? 'chemicals' : 'apparatus';
    if (remote == null) {
      throw StateError('Deleting items requires a connection.');
    }
    await remote!
        .from('consumption_logs')
        .delete()
        .eq('item_id', id)
        .eq('item_type', type.name);
    await remote!.from(table).delete().eq('id', id);
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

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
