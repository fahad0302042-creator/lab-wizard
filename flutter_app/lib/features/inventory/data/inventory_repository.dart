import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/local_database.dart';
import '../../sync/data/incremental_sync.dart';
import '../../sync/domain/sync_conflict.dart';
import '../domain/models.dart';

class InventorySnapshot {
  const InventorySnapshot({
    required this.chemicals,
    required this.apparatus,
    required this.logs,
    required this.outbox,
    required this.fromCache,
    this.reversals = const [],
    this.checkouts = const [],
    this.services = const [],
    this.lastSyncedAt,
    this.syncReport,
  });

  final List<Chemical> chemicals;
  final List<Apparatus> apparatus;
  final List<ConsumptionLog> logs;
  final List<PendingOperation> outbox;

  /// Undone actions, newest first (UX-04).
  final List<InventoryReversal> reversals;

  /// Apparatus loans, newest first (GEAR-02).
  final List<ApparatusCheckout> checkouts;

  /// Maintenance and calibration tasks, soonest due first (GEAR-03).
  final List<ApparatusService> services;
  final bool fromCache;
  final DateTime? lastSyncedAt;

  /// How the last download went (SYNC-02); null for cached snapshots.
  final SyncReport? syncReport;

  int get pendingCount => outbox.length;
  int get failedCount => outbox.where((operation) => operation.isFailed).length;
}

class InventoryRepository {
  InventoryRepository({required this.local, required this.remote});

  final LocalDatabase local;
  final SupabaseClient? remote;
  final Uuid _uuid = const Uuid();
  bool? _atomicRpcAvailable;
  bool? _undoRpcAvailable;
  bool? _reversalsTableAvailable;
  bool? _checkoutsTableAvailable;
  bool? _servicesTableAvailable;
  SupabaseSyncSource? _source;
  IncrementalSync? _sync;

  /// Replaces the server-backed download engine (tests).
  IncrementalSync? syncOverride;

  /// Whether the last server round-trip found the `apparatus_checkouts`
  /// table (null until the first refresh).
  bool? get checkoutsAvailable => _checkoutsTableAvailable;

  Future<InventorySnapshot> loadCached(String userId) => _load(userId);

  Future<InventorySnapshot> _load(
    String userId, {
    bool fromCache = true,
    DateTime? syncedAt,
    SyncReport? syncReport,
  }) async {
    final results = await Future.wait<dynamic>([
      local.loadRecords(userId, 'chemical'),
      local.loadRecords(userId, 'apparatus'),
      local.loadRecords(userId, 'log'),
      local.pendingOperations(userId),
      lastSyncedAt(userId),
      local.loadRecords(userId, 'reversal'),
      local.loadRecords(userId, 'checkout'),
      local.loadRecords(userId, 'service'),
    ]);
    return InventorySnapshot(
      chemicals: sortedChemicals(
        (results[0] as List<Map<String, dynamic>>).map(Chemical.fromMap),
      ),
      apparatus: sortedApparatus(
        (results[1] as List<Map<String, dynamic>>).map(Apparatus.fromMap),
      ),
      logs: sortedLogs(
        (results[2] as List<Map<String, dynamic>>).map(ConsumptionLog.fromMap),
      ),
      outbox: results[3] as List<PendingOperation>,
      fromCache: fromCache,
      lastSyncedAt: syncedAt ?? results[4] as DateTime?,
      syncReport: syncReport,
      reversals: _sortedReversals(
        (results[5] as List<Map<String, dynamic>>).map(
          InventoryReversal.fromMap,
        ),
      ),
      checkouts: _sortedCheckouts(
        (results[6] as List<Map<String, dynamic>>).map(
          ApparatusCheckout.fromMap,
        ),
      ),
      services: sortedServices(
        (results[7] as List<Map<String, dynamic>>).map(
          ApparatusService.fromMap,
        ),
      ),
    );
  }

  /// Newest first, the order the shelves expect regardless of how the rows
  /// reached the offline copy.
  static List<Chemical> sortedChemicals(Iterable<Chemical> items) =>
      items.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  static List<Apparatus> sortedApparatus(Iterable<Apparatus> items) =>
      items.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Most recent activity first.
  static List<ConsumptionLog> sortedLogs(Iterable<ConsumptionLog> logs) =>
      logs.toList()..sort((a, b) {
        final byLogged = b.loggedAt.compareTo(a.loggedAt);
        return byLogged != 0 ? byLogged : b.createdAt.compareTo(a.createdAt);
      });

  /// Open tasks first (soonest due, undated last), then completed tasks
  /// newest first.
  static List<ApparatusService> sortedServices(
    Iterable<ApparatusService> services,
  ) => services.toList()
    ..sort((a, b) {
      if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
      if (a.isOpen) {
        final dueA = a.dueAt;
        final dueB = b.dueAt;
        if (dueA == null && dueB == null) {
          return b.createdAt.compareTo(a.createdAt);
        }
        if (dueA == null) return 1;
        if (dueB == null) return -1;
        return dueA.compareTo(dueB);
      }
      return (b.completedAt ?? b.createdAt).compareTo(
        a.completedAt ?? a.createdAt,
      );
    });

  static List<InventoryReversal> _sortedReversals(
    Iterable<InventoryReversal> reversals,
  ) => reversals.toList()..sort((a, b) => b.reversedAt.compareTo(a.reversedAt));

  static List<ApparatusCheckout> _sortedCheckouts(
    Iterable<ApparatusCheckout> checkouts,
  ) =>
      checkouts.toList()
        ..sort((a, b) => b.checkedOutAt.compareTo(a.checkedOutAt));

  Future<DateTime?> lastSyncedAt(String userId) async => DateTime.tryParse(
    await local.getMeta(userId, LocalDatabase.lastSyncKey) ?? '',
  );

  /// Downloads server changes into the offline copy and returns the fresh
  /// snapshot (SYNC-02). Incremental when the server has migration 007,
  /// otherwise a paged full download; [full] forces a complete download and
  /// re-checks optional tables.
  Future<InventorySnapshot> refresh(String userId, {bool full = false}) async {
    final engine = _engine;
    if (engine == null) return loadCached(userId);
    if (full) _source?.recheck();

    bool include(bool? available) => full || available != false;
    final tables = <String>[
      'chemicals',
      'apparatus',
      'consumption_logs',
      if (include(_reversalsTableAvailable)) 'inventory_reversals',
      if (include(_checkoutsTableAvailable)) 'apparatus_checkouts',
      if (include(_servicesTableAvailable)) 'apparatus_services',
    ];
    final queuedIds = <String>{
      for (final operation in await local.pendingOperations(userId))
        if (operation.payload['id'] is String)
          operation.payload['id'] as String,
    };
    final report = await engine.run(
      userId,
      tables: tables,
      full: full,
      keepLocal: (kind, record) =>
          record['local_only'] == true || queuedIds.contains(record['id']),
    );
    bool? availability(String table, bool? previous) => tables.contains(table)
        ? !report.missingTables.contains(table)
        : previous;
    _reversalsTableAvailable = availability(
      'inventory_reversals',
      _reversalsTableAvailable,
    );
    _checkoutsTableAvailable = availability(
      'apparatus_checkouts',
      _checkoutsTableAvailable,
    );
    _servicesTableAvailable = availability(
      'apparatus_services',
      _servicesTableAvailable,
    );

    final syncedAt = DateTime.now();
    await local.setMeta(
      userId,
      LocalDatabase.lastSyncKey,
      syncedAt.toIso8601String(),
    );
    return _load(
      userId,
      fromCache: false,
      syncedAt: syncedAt,
      syncReport: report,
    );
  }

  IncrementalSync? get _engine {
    final override = syncOverride;
    if (override != null) return override;
    final client = remote;
    if (client == null) return null;
    return _sync ??= IncrementalSync(
      local: local,
      source: _source ??= SupabaseSyncSource(client),
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
    ChemicalDetails details = const ChemicalDetails(),
    String? organizationId,
    String? labId,
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
      supplier: details.supplier?.trim(),
      casNumber: details.casNumber?.trim(),
      concentration: details.concentration?.trim(),
      location: details.location?.trim(),
      expiryDate: details.expiryDate,
      hazardClasses: parseHazardList(details.hazardClasses),
      organizationId: organizationId,
      labId: labId,
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
            label: 'Add chemical ${chemical.name}',
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
    ApparatusDetails details = const ApparatusDetails(),
    String? organizationId,
    String? labId,
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
      serialNumber: details.serialNumber?.trim(),
      condition: details.condition?.trim().toLowerCase(),
      assignedTo: details.assignedTo?.trim(),
      location: details.location?.trim(),
      purchaseDate: details.purchaseDate,
      warrantyUntil: details.warrantyUntil,
      organizationId: organizationId,
      labId: labId,
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
            label: 'Add apparatus ${item.name}',
          ),
        );
        return item;
      }
      rethrow;
    }
  }

  /// Saves an edit (SYNC-04 aware).
  ///
  /// Only the fields that differ from the copy this device last saw are
  /// sent, and the server applies them only while those fields still hold
  /// the last-seen values. An edit made elsewhere in the meantime therefore
  /// surfaces as an [ItemConflictException] instead of being overwritten;
  /// [force] sends the edit regardless. Offline, the change is queued with
  /// the same base values so the replay gets the same protection.
  Future<Map<String, dynamic>> updateItem({
    required String userId,
    required ItemKind type,
    required String id,
    required Map<String, dynamic> changes,
    String? itemName,
    bool force = false,
  }) async {
    final table = type == ItemKind.chemical ? 'chemicals' : 'apparatus';
    final records = await local.loadRecords(userId, type.name);
    final current = records.where((row) => row['id'] == id).firstOrNull;
    final effective = current == null
        ? Map<String, dynamic>.from(changes)
        : changedFields(changes, current);
    if (effective.isEmpty && current != null) return current;
    final previous = <String, dynamic>{
      for (final key in effective.keys)
        if (current != null && current.containsKey(key)) key: current[key],
    };
    try {
      if (remote == null) throw const _OfflineException();
      final saved = await _updateWithBase(
        table: table,
        id: id,
        changes: effective,
        previous: previous,
        force: force,
      );
      await local.upsertRecord(userId, type.name, saved);
      return saved;
    } catch (error) {
      if (error is! _OfflineException && !_isConnectivityError(error)) rethrow;
      if (current == null) {
        throw StateError('The item is not available offline.');
      }
      final saved = <String, dynamic>{...current, ...effective, 'id': id};
      await local.upsertRecord(userId, type.name, saved);
      await local.enqueue(
        PendingOperation(
          id: _uuid.v4(),
          userId: userId,
          type: 'update_item',
          payload: {
            'id': id,
            'item_type': type.name,
            'changes': effective,
            'previous': previous,
            if (force) 'force': true,
          },
          createdAt: DateTime.now(),
          label: 'Update ${itemName ?? current['name'] ?? 'item'}',
        ),
      );
      return saved;
    }
  }

  /// The subset of [changes] that differs from [current].
  static Map<String, dynamic> changedFields(
    Map<String, dynamic> changes,
    Map<String, dynamic> current,
  ) => {
    for (final entry in changes.entries)
      if (!current.containsKey(entry.key) ||
          !valuesMatch(current[entry.key], entry.value))
        entry.key: entry.value,
  };

  /// Conditional update: writes [changes] only while every field still
  /// holds its [previous] value on the server (compare-and-set through
  /// PostgREST filters, no server changes needed). Returns the saved row.
  ///
  /// Throws [ItemConflictException] when the row is gone or when a changed
  /// field was changed on the server too. Fields the server already has at
  /// the wanted value do not count as conflicts.
  Future<Map<String, dynamic>> _updateWithBase({
    required String table,
    required String id,
    required Map<String, dynamic> changes,
    required Map<String, dynamic> previous,
    bool force = false,
  }) async {
    Future<Map<String, dynamic>?> fetch() async {
      final row = await remote!.from(table).select().eq('id', id).maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row);
    }

    Future<Map<String, dynamic>> plainUpdate() async {
      final rows = await remote!
          .from(table)
          .update(changes)
          .eq('id', id)
          .select();
      if (rows.isEmpty) throw ItemConflictException(SyncConflict.deleted());
      return Map<String, dynamic>.from(rows.first);
    }

    if (changes.isEmpty) {
      final row = await fetch();
      if (row == null) throw ItemConflictException(SyncConflict.deleted());
      return row;
    }
    final guards = {
      for (final entry in previous.entries)
        if (changes.containsKey(entry.key)) entry.key: entry.value,
    };
    if (force || guards.isEmpty) return plainUpdate();

    // Array columns (hazard classes) cannot be compared reliably through a
    // filter, so they are checked against a fresh copy before writing.
    final unguarded = guards.entries
        .where((entry) => entry.value is List || entry.value is Map)
        .map((entry) => entry.key)
        .toList();
    if (unguarded.isNotEmpty) {
      final row = await fetch();
      if (row == null) throw ItemConflictException(SyncConflict.deleted());
      final clashes = _clashes(changes, guards, row, only: unguarded);
      if (clashes.isNotEmpty) {
        throw ItemConflictException(SyncConflict.changed(clashes));
      }
    }

    var query = remote!.from(table).update(changes).eq('id', id);
    for (final entry in guards.entries) {
      final value = entry.value;
      if (value == null) {
        query = query.isFilter(entry.key, null);
      } else if (value is num || value is String || value is bool) {
        query = query.eq(entry.key, value);
      }
    }
    final rows = await query.select();
    if (rows.isNotEmpty) return Map<String, dynamic>.from(rows.first);

    // Nothing matched: either the row is gone, a guarded field moved, or a
    // filter was stricter than the data (e.g. '' versus null, 5 versus
    // 5.0 in text).
    final row = await fetch();
    if (row == null) throw ItemConflictException(SyncConflict.deleted());
    final clashes = _clashes(changes, guards, row);
    if (clashes.isNotEmpty) {
      throw ItemConflictException(SyncConflict.changed(clashes));
    }
    final alreadyApplied = changes.entries.every(
      (entry) => valuesMatch(row[entry.key], entry.value),
    );
    return alreadyApplied ? row : plainUpdate();
  }

  /// Fields whose server value differs from both the base this device edited
  /// from and the value it wants to write.
  static List<FieldConflict> _clashes(
    Map<String, dynamic> changes,
    Map<String, dynamic> guards,
    Map<String, dynamic> server, {
    List<String>? only,
  }) => [
    for (final entry in guards.entries)
      if ((only == null || only.contains(entry.key)) &&
          !valuesMatch(server[entry.key], entry.value) &&
          !valuesMatch(server[entry.key], changes[entry.key]))
        FieldConflict(
          field: entry.key,
          base: entry.value,
          local: changes[entry.key],
          server: server[entry.key],
        ),
  ];

  Future<ConsumptionLog> applyAction({
    required String userId,
    required String itemId,
    required ItemKind itemType,
    required InventoryAction action,
    required double amount,
    required double previousQuantity,
    required String note,
    required DateTime loggedAt,
    String? itemName,
    String? unit,
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
      'unit': unit ?? (itemType == ItemKind.apparatus ? 'pcs' : ''),
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
      await _shiftCachedQuantity(
        userId: userId,
        itemType: itemType,
        itemId: itemId,
        delta: newQuantity - previousQuantity,
      );
      await local.upsertRecord(userId, 'log', optimisticLog.toMap());
      await local.enqueue(
        PendingOperation(
          id: operationId,
          userId: userId,
          type: 'inventory_action',
          payload: payload,
          createdAt: DateTime.now(),
          label: actionLabel(
            action,
            amount,
            unit ?? (itemType == ItemKind.apparatus ? 'pcs' : ''),
            itemName,
          ),
        ),
      );
      return optimisticLog;
    }
  }

  /// "Consume 50 mL of Acetone" style summary used for outbox labels.
  static String actionLabel(
    InventoryAction action,
    double amount,
    String unit,
    String? itemName,
  ) {
    final verb = switch (action) {
      InventoryAction.consume => 'Consume',
      InventoryAction.restock => 'Restock',
      InventoryAction.breakage => 'Record damage of',
    };
    final quantity = '${formatQuantity(amount)}${unit.isEmpty ? '' : ' $unit'}';
    return itemName == null || itemName.isEmpty
        ? '$verb $quantity'
        : '$verb $quantity of $itemName';
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
    var previous = _asNum(payload['previous_quantity']);
    // Only write the precomputed quantity while the server still has the
    // quantity it was computed from; otherwise re-apply the delta on top of
    // the server's value like the RPC does (SYNC-04).
    final guarded = await remote!
        .from(table)
        .update({'quantity': payload['new_quantity']})
        .eq('id', itemId)
        .eq('quantity', previous)
        .select();
    Map<String, dynamic> updated;
    if (guarded.isNotEmpty) {
      updated = Map<String, dynamic>.from(guarded.first);
    } else {
      final row = await remote!
          .from(table)
          .select('quantity')
          .eq('id', itemId)
          .maybeSingle();
      if (row == null) throw ItemConflictException(SyncConflict.deleted());
      previous = _asNum(row['quantity']);
      final amount = _asNum(payload['amount']);
      final action = InventoryAction.values.firstWhere(
        (value) => value.name == payload['action'],
        orElse: () => InventoryAction.consume,
      );
      if (action != InventoryAction.restock && previous < amount) {
        throw ItemConflictException(
          SyncConflict.stock(
            available: previous,
            requested: amount,
            unit: payload['unit'] as String?,
            partialAllowed: true,
          ),
        );
      }
      updated = Map<String, dynamic>.from(
        await remote!
            .from(table)
            .update({'quantity': _quantityAfter(previous, action, amount)})
            .eq('id', itemId)
            .select()
            .single(),
      );
    }
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

  /// Moves the cached quantity by [delta] without touching the server, so
  /// offline changes (and their reversal) show immediately.
  Future<void> _shiftCachedQuantity({
    required String userId,
    required ItemKind itemType,
    required String itemId,
    required double delta,
  }) async {
    final rows = await local.loadRecords(userId, itemType.name);
    final current = rows.where((row) => row['id'] == itemId).firstOrNull;
    if (current == null) return;
    final quantity = _asNum(current['quantity'] ?? 0) + delta;
    await local.upsertRecord(userId, itemType.name, {
      ...current,
      'quantity': quantity < 0 ? 0 : quantity,
    });
  }

  /// Reverses a recorded action (UX-04).
  ///
  /// * A change that is still queued on this device is simply cancelled.
  /// * Otherwise the quantity is restored and the log entry removed, exactly
  ///   like the web app's undo, and a reversal record keeps the history
  ///   honest. Offline, the undo is queued and replayed idempotently.
  Future<UndoResult> undoAction({
    required String userId,
    required ConsumptionLog log,
    required double currentQuantity,
    String reason = '',
    String? itemName,
    String? unit,
  }) async {
    final queued = log.operationId == null
        ? null
        : await local.operationById(log.operationId!);
    if (queued != null && queued.type == 'inventory_action') {
      await discardOperation(userId, queued);
      return const UndoResult(cancelled: true);
    }
    if (log.action == InventoryAction.restock && currentQuantity < log.amount) {
      throw StateError(
        'Cannot undo: only ${formatQuantity(currentQuantity)} left of the '
        '${formatQuantity(log.amount)} that was restocked.',
      );
    }
    final delta = log.action == InventoryAction.restock
        ? -log.amount
        : log.amount;
    final operationId = _uuid.v4();
    final now = DateTime.now();
    final payload = <String, dynamic>{
      'operation_id': operationId,
      'log_id': log.id,
      'log': log.toMap(),
      'item_id': log.itemId,
      'item_type': log.itemType.name,
      'action': log.action.name,
      'amount': log.amount,
      'reason': reason.trim(),
      'previous_quantity': currentQuantity,
      'new_quantity': currentQuantity + delta,
    };
    final optimistic = InventoryReversal(
      id: operationId,
      itemId: log.itemId,
      itemType: log.itemType,
      action: log.action,
      amount: log.amount,
      reversedAt: now,
      originalLogId: log.id,
      originalLoggedAt: log.loggedAt,
      originalNote: log.note,
      reason: reason.trim(),
      operationId: operationId,
    );

    try {
      if (remote == null) throw const _OfflineException();
      final result = await _undoRemote(userId, payload);
      await local.deleteRecord(userId, 'log', log.id);
      final itemMap = result['item'];
      if (itemMap is Map) {
        await local.upsertRecord(
          userId,
          log.itemType.name,
          Map<String, dynamic>.from(itemMap),
        );
      }
      final reversalMap = result['reversal'];
      final reversal = reversalMap is Map
          ? InventoryReversal.fromMap(Map<String, dynamic>.from(reversalMap))
          : null;
      if (reversal != null) {
        await local.upsertRecord(userId, 'reversal', reversal.toMap());
      }
      return UndoResult(
        reversal: reversal,
        item: itemMap is Map ? Map<String, dynamic>.from(itemMap) : null,
        alreadyUndone: result['missing'] == true,
      );
    } catch (error) {
      if (!_isConnectivityError(error) && error is! _OfflineException) rethrow;
      await _shiftCachedQuantity(
        userId: userId,
        itemType: log.itemType,
        itemId: log.itemId,
        delta: delta,
      );
      await local.deleteRecord(userId, 'log', log.id);
      await local.upsertRecord(userId, 'reversal', optimistic.toMap());
      await local.enqueue(
        PendingOperation(
          id: operationId,
          userId: userId,
          type: 'undo_action',
          payload: payload,
          createdAt: now,
          label:
              'Undo: ${actionLabel(log.action, log.amount, unit ?? (log.itemType == ItemKind.apparatus ? 'pcs' : ''), itemName)}',
        ),
      );
      return UndoResult(reversal: optimistic);
    }
  }

  Future<Map<String, dynamic>> _undoRemote(
    String userId,
    Map<String, dynamic> payload,
  ) async {
    if (_undoRpcAvailable != false) {
      try {
        final response = await remote!.rpc(
          'undo_inventory_action',
          params: {
            'p_operation_id': payload['operation_id'],
            'p_log_id': payload['log_id'],
            'p_reason': payload['reason'] ?? '',
          },
        );
        _undoRpcAvailable = true;
        return Map<String, dynamic>.from(response as Map);
      } on PostgrestException catch (error) {
        if (!_isMissingFunction(error)) rethrow;
        _undoRpcAvailable = false;
      }
    }
    return _compatibilityUndo(userId, payload);
  }

  /// Web-parity undo for deployments without the additive migration: restore
  /// the quantity and delete the entry. The reversal record stays local.
  Future<Map<String, dynamic>> _compatibilityUndo(
    String userId,
    Map<String, dynamic> payload,
  ) async {
    final table = payload['item_type'] == 'chemical'
        ? 'chemicals'
        : 'apparatus';
    final itemId = payload['item_id'] as String;
    final logId = payload['log_id'] as String;
    final existing = await remote!
        .from('consumption_logs')
        .select('id')
        .eq('id', logId)
        .maybeSingle();
    if (existing == null) {
      return {
        'item': null,
        'reversal': null,
        'duplicate': true,
        'missing': true,
      };
    }
    final current = await remote!
        .from(table)
        .select('quantity')
        .eq('id', itemId)
        .single();
    final quantity = _asNum(current['quantity']);
    final amount = _asNum(payload['amount']);
    final restock = payload['action'] == 'restock';
    if (restock && quantity < amount) {
      throw StateError(
        'Cannot undo: only ${formatQuantity(quantity)} left of the '
        '${formatQuantity(amount)} that was restocked.',
      );
    }
    final updated = await remote!
        .from(table)
        .update({'quantity': restock ? quantity - amount : quantity + amount})
        .eq('id', itemId)
        .select()
        .single();
    await remote!.from('consumption_logs').delete().eq('id', logId);
    final log = payload['log'];
    final reversal = InventoryReversal(
      id: payload['operation_id'] as String,
      itemId: itemId,
      itemType: payload['item_type'] == 'apparatus'
          ? ItemKind.apparatus
          : ItemKind.chemical,
      action: InventoryAction.values.firstWhere(
        (value) => value.name == payload['action'],
        orElse: () => InventoryAction.consume,
      ),
      amount: amount,
      reversedAt: DateTime.now(),
      originalLogId: logId,
      originalLoggedAt: log is Map
          ? DateTime.tryParse(log['logged_at']?.toString() ?? '')
          : null,
      originalNote: log is Map ? (log['note']?.toString() ?? '') : '',
      reason: payload['reason']?.toString() ?? '',
      operationId: payload['operation_id'] as String,
      localOnly: true,
    );
    return {'item': updated, 'reversal': reversal.toMap(), 'duplicate': false};
  }

  /// Lends [quantity] pieces of an apparatus (GEAR-02). Works offline: the
  /// loan is cached and queued as `checkout_apparatus`.
  Future<ApparatusCheckout> checkoutApparatus({
    required String userId,
    required String apparatusId,
    required double quantity,
    required String person,
    required String note,
    DateTime? dueAt,
    String? itemName,
  }) async {
    final now = DateTime.now();
    final checkout = ApparatusCheckout(
      id: _uuid.v4(),
      apparatusId: apparatusId,
      quantity: quantity,
      person: person.trim(),
      note: note.trim(),
      checkedOutAt: now,
      dueAt: dueAt,
      operationId: _uuid.v4(),
    );
    final payload = {...checkout.toMap(), 'user_id': userId};
    try {
      if (remote == null) throw const _OfflineException();
      final data = await remote!
          .from('apparatus_checkouts')
          .insert(payload)
          .select()
          .single();
      final saved = ApparatusCheckout.fromMap(data);
      _checkoutsTableAvailable = true;
      await local.upsertRecord(userId, 'checkout', saved.toMap());
      return saved;
    } on PostgrestException catch (error) {
      if (_isMissingRelation(error)) {
        _checkoutsTableAvailable = false;
        throw StateError(checkoutsMigrationHint);
      }
      rethrow;
    } catch (error) {
      if (error is _OfflineException || _isConnectivityError(error)) {
        await local.upsertRecord(userId, 'checkout', checkout.toMap());
        await local.enqueue(
          PendingOperation(
            id: _uuid.v4(),
            userId: userId,
            type: 'checkout_apparatus',
            payload: payload,
            createdAt: now,
            label: 'Check out ${itemName ?? 'apparatus'} to ${checkout.person}'
                .trim(),
          ),
        );
        return checkout;
      }
      rethrow;
    }
  }

  /// Returns [quantity] pieces of a loan. The loan closes when everything is
  /// back. Works offline through the `return_apparatus` queue entry.
  Future<ApparatusCheckout> returnApparatus({
    required String userId,
    required ApparatusCheckout checkout,
    required double quantity,
    required String note,
    String? itemName,
  }) async {
    final now = DateTime.now();
    final returned = (checkout.returnedQuantity + quantity) > checkout.quantity
        ? checkout.quantity
        : checkout.returnedQuantity + quantity;
    final complete = returned >= checkout.quantity;
    final combinedNote = [
      if (checkout.returnNote.isNotEmpty) checkout.returnNote,
      if (note.trim().isNotEmpty) note.trim(),
    ].join(' · ');
    final changes = <String, dynamic>{
      'returned_quantity': returned,
      'returned_at': complete ? now.toUtc().toIso8601String() : null,
      'return_note': combinedNote,
    };
    final updated = checkout.copyWith(
      returnedQuantity: returned,
      returnNote: combinedNote,
      returnedAt: complete ? now : null,
      clearReturnedAt: !complete,
    );
    try {
      if (remote == null) throw const _OfflineException();
      final data = await remote!
          .from('apparatus_checkouts')
          .update(changes)
          .eq('id', checkout.id)
          .select()
          .single();
      final saved = ApparatusCheckout.fromMap(data);
      await local.upsertRecord(userId, 'checkout', saved.toMap());
      return saved;
    } on PostgrestException catch (error) {
      if (_isMissingRelation(error)) {
        _checkoutsTableAvailable = false;
        throw StateError(checkoutsMigrationHint);
      }
      rethrow;
    } catch (error) {
      if (error is _OfflineException || _isConnectivityError(error)) {
        await local.upsertRecord(userId, 'checkout', updated.toMap());
        await local.enqueue(
          PendingOperation(
            id: _uuid.v4(),
            userId: userId,
            type: 'return_apparatus',
            payload: {
              'id': checkout.id,
              'apparatus_id': checkout.apparatusId,
              'changes': changes,
              'previous': {
                'returned_quantity': checkout.returnedQuantity,
                'returned_at': checkout.returnedAt?.toUtc().toIso8601String(),
                'return_note': checkout.returnNote,
              },
            },
            createdAt: now,
            label:
                'Return ${formatQuantity(quantity)} × '
                '${itemName ?? 'apparatus'}',
          ),
        );
        return updated;
      }
      rethrow;
    }
  }

  /// Schedules a maintenance or calibration task (GEAR-03). Works offline
  /// through the `schedule_service` queue entry.
  Future<ApparatusService> scheduleService({
    required String userId,
    required String apparatusId,
    required ServiceKind kind,
    required String title,
    required String note,
    DateTime? dueAt,
    String? itemName,
  }) async {
    final now = DateTime.now();
    final service = ApparatusService(
      id: _uuid.v4(),
      apparatusId: apparatusId,
      kind: kind,
      title: title.trim(),
      note: note.trim(),
      dueAt: dueAt,
      createdAt: now,
      operationId: _uuid.v4(),
    );
    final payload = {...service.toMap(), 'user_id': userId};
    try {
      if (remote == null) throw const _OfflineException();
      final data = await remote!
          .from('apparatus_services')
          .insert(payload)
          .select()
          .single();
      final saved = ApparatusService.fromMap(data);
      _servicesTableAvailable = true;
      await local.upsertRecord(userId, 'service', saved.toMap());
      return saved;
    } on PostgrestException catch (error) {
      if (_isMissingRelation(error)) {
        _servicesTableAvailable = false;
        throw StateError(servicesMigrationHint);
      }
      rethrow;
    } catch (error) {
      if (error is _OfflineException || _isConnectivityError(error)) {
        await local.upsertRecord(userId, 'service', service.toMap());
        await local.enqueue(
          PendingOperation(
            id: _uuid.v4(),
            userId: userId,
            type: 'schedule_service',
            payload: payload,
            createdAt: now,
            label:
                'Schedule ${kind.label.toLowerCase()} for '
                '${itemName ?? 'apparatus'}',
          ),
        );
        return service;
      }
      rethrow;
    }
  }

  /// Marks a task as done. Works offline through the `complete_service`
  /// queue entry, which remembers the previous values for discard.
  Future<ApparatusService> completeService({
    required String userId,
    required ApparatusService service,
    required DateTime completedAt,
    required String performedBy,
    required String result,
    required String note,
    String? itemName,
  }) async {
    final combinedNote = [
      if (service.note.isNotEmpty) service.note,
      if (note.trim().isNotEmpty && note.trim() != service.note) note.trim(),
    ].join(' · ');
    final changes = <String, dynamic>{
      'completed_at': completedAt.toUtc().toIso8601String(),
      'performed_by': performedBy.trim(),
      'result': result.trim(),
      'note': combinedNote,
    };
    final updated = service.copyWith(
      completedAt: completedAt,
      performedBy: performedBy.trim(),
      result: result.trim(),
      note: combinedNote,
    );
    try {
      if (remote == null) throw const _OfflineException();
      final data = await remote!
          .from('apparatus_services')
          .update(changes)
          .eq('id', service.id)
          .select()
          .single();
      final saved = ApparatusService.fromMap(data);
      await local.upsertRecord(userId, 'service', saved.toMap());
      return saved;
    } on PostgrestException catch (error) {
      if (_isMissingRelation(error)) {
        _servicesTableAvailable = false;
        throw StateError(servicesMigrationHint);
      }
      rethrow;
    } catch (error) {
      if (error is _OfflineException || _isConnectivityError(error)) {
        await local.upsertRecord(userId, 'service', updated.toMap());
        await local.enqueue(
          PendingOperation(
            id: _uuid.v4(),
            userId: userId,
            type: 'complete_service',
            payload: {
              'id': service.id,
              'apparatus_id': service.apparatusId,
              'changes': changes,
              'previous': {
                'completed_at': service.completedAt?.toUtc().toIso8601String(),
                'performed_by': service.performedBy,
                'result': service.result,
                'note': service.note,
              },
            },
            createdAt: DateTime.now(),
            label:
                'Complete ${service.kind.label.toLowerCase()} of '
                '${itemName ?? 'apparatus'}',
          ),
        );
        return updated;
      }
      rethrow;
    }
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
    await local.deleteRecordsWhere(
      userId,
      'log',
      (record) => record['item_id'] == id,
    );
    await local.deleteRecordsWhere(
      userId,
      'reversal',
      (record) => record['item_id'] == id,
    );
    await local.deleteRecordsWhere(
      userId,
      'checkout',
      (record) => record['apparatus_id'] == id,
    );
    await local.deleteRecordsWhere(
      userId,
      'service',
      (record) => record['apparatus_id'] == id,
    );
  }

  /// Replays queued changes in order.
  ///
  /// Connectivity errors stop the run and keep the change `pending`; any
  /// other error marks the change `failed` and moves on, because a failed
  /// change on one item must not block unrelated items. Failed changes are
  /// only retried when the user asks for it ([retryFailed] or a specific
  /// [operationId]).
  Future<void> syncPending(
    String userId, {
    String? operationId,
    bool retryFailed = false,
  }) async {
    if (remote == null) return;
    var operations = await local.pendingOperations(userId);
    if (operationId != null) {
      operations = operations
          .where((operation) => operation.id == operationId)
          .toList();
    } else if (!retryFailed) {
      operations = operations
          .where((operation) => !operation.isFailed)
          .toList();
    } else {
      // "Retry all" never re-sends conflicts; they wait for a decision.
      operations = operations
          .where((operation) => !operation.isConflict)
          .toList();
    }
    for (final operation in operations) {
      try {
        await _replay(userId, operation);
        await local.completeOperation(operation.id);
      } catch (error) {
        final offline = _isConnectivityError(error);
        final conflict = offline ? null : conflictFor(operation, error);
        if (conflict != null) {
          await local.markConflict(operation.id, conflict);
        } else {
          await local.markAttempt(operation.id, error, failed: !offline);
        }
        if (offline) break;
      }
    }
  }

  /// Interprets a replay error as a conflict when the server said so
  /// (SYNC-04): stale stock, a deleted item, or an edit that lost a race.
  static SyncConflict? conflictFor(PendingOperation operation, Object error) {
    final payload = operation.payload;
    return switch (operation.type) {
      'inventory_action' => conflictFromError(
        error,
        requested: _asNum(payload['amount']),
        unit: payload['unit'] as String?,
        partialAllowed: payload['action'] != InventoryAction.restock.name,
      ),
      'undo_action' => conflictFromError(
        error,
        requested: _asNum(payload['amount']),
        unit: payload['unit'] as String?,
      ),
      'update_item' => conflictFromError(error),
      _ => error is ItemConflictException ? error.conflict : null,
    };
  }

  /// Applies the user's decision about a conflicting change and replays it
  /// straight away (SYNC-04).
  Future<void> resolveConflict(
    String userId,
    PendingOperation operation,
    ConflictResolution resolution,
  ) async {
    final conflict = operation.conflict;
    if (conflict == null) return;
    final payload = Map<String, dynamic>.from(operation.payload);
    switch (resolution) {
      case ConflictResolution.discard:
        await discardOperation(userId, operation);
        return;
      case ConflictResolution.keepMine:
        if (operation.type != 'update_item') {
          throw StateError('Only edits can overwrite the server.');
        }
        payload['force'] = true;
      case ConflictResolution.useServer:
        if (operation.type != 'update_item') {
          throw StateError('Only edits can take the server values.');
        }
        final changes = Map<String, dynamic>.from(payload['changes'] as Map);
        final previous = Map<String, dynamic>.from(
          (payload['previous'] as Map?) ?? const {},
        );
        final kind = payload['item_type'] == ItemKind.apparatus.name
            ? ItemKind.apparatus.name
            : ItemKind.chemical.name;
        final rows = await local.loadRecords(userId, kind);
        final cached = rows
            .where((row) => row['id'] == payload['id'])
            .firstOrNull;
        for (final field in conflict.fields) {
          changes.remove(field.field);
          previous.remove(field.field);
          if (cached != null) cached[field.field] = field.server;
        }
        if (cached != null) await local.upsertRecord(userId, kind, cached);
        if (changes.isEmpty) {
          await local.completeOperation(operation.id);
          return;
        }
        payload['changes'] = changes;
        payload['previous'] = previous;
      case ConflictResolution.useAvailable:
        final available = conflict.available;
        if (operation.type != 'inventory_action' ||
            available == null ||
            available <= 0) {
          throw StateError('This change cannot be applied partially.');
        }
        final original = _asNum(payload['amount']);
        final itemType = payload['item_type'] == ItemKind.apparatus.name
            ? ItemKind.apparatus
            : ItemKind.chemical;
        payload['amount'] = available;
        payload['new_quantity'] = _quantityAfter(
          _asNum(payload['previous_quantity']),
          InventoryAction.values.firstWhere(
            (value) => value.name == payload['action'],
            orElse: () => InventoryAction.consume,
          ),
          available,
        );
        // Keep the optimistic copy honest: give back what will not be used.
        await _shiftCachedQuantity(
          userId: userId,
          itemType: itemType,
          itemId: payload['item_id'] as String,
          delta: original - available,
        );
        final logId = payload['local_log_id'] as String?;
        if (logId != null) {
          final logs = await local.loadRecords(userId, 'log');
          final log = logs.where((row) => row['id'] == logId).firstOrNull;
          if (log != null) {
            await local.upsertRecord(userId, 'log', {
              ...log,
              'amount': available,
            });
          }
        }
    }
    await local.updatePayload(operation.id, payload);
    await local.resetOperation(operation.id);
    await syncPending(userId, operationId: operation.id);
  }

  Future<void> _replay(String userId, PendingOperation operation) async {
    switch (operation.type) {
      case 'add_chemical':
        await remote!.from('chemicals').upsert(operation.payload);
      case 'add_apparatus':
        await remote!.from('apparatus').upsert(operation.payload);
      case 'inventory_action':
        await _applyRemoteAction(userId, operation.payload);
      case 'undo_action':
        final result = await _undoRemote(userId, operation.payload);
        final reversalMap = result['reversal'];
        if (reversalMap is Map) {
          await local.upsertRecord(
            userId,
            'reversal',
            Map<String, dynamic>.from(reversalMap),
          );
        }
      case 'update_item':
        final payload = operation.payload;
        final kind = payload['item_type'] == ItemKind.apparatus.name
            ? ItemKind.apparatus
            : ItemKind.chemical;
        final changes = Map<String, dynamic>.from(payload['changes'] as Map);
        final previous = Map<String, dynamic>.from(
          (payload['previous'] as Map?) ?? const {},
        );
        // Older queue entries carried every form field; only send the ones
        // that were actually edited so unrelated server changes survive.
        final effective = previous.isEmpty
            ? changes
            : changedFields(changes, previous);
        final saved = await _updateWithBase(
          table: kind == ItemKind.chemical ? 'chemicals' : 'apparatus',
          id: payload['id'] as String,
          changes: effective,
          previous: previous,
          force: payload['force'] == true,
        );
        await local.upsertRecord(userId, kind.name, saved);
      case 'checkout_apparatus':
        await remote!.from('apparatus_checkouts').upsert(operation.payload);
      case 'return_apparatus':
        await remote!
            .from('apparatus_checkouts')
            .update(
              Map<String, dynamic>.from(operation.payload['changes'] as Map),
            )
            .eq('id', operation.payload['id']);
      case 'schedule_service':
        await remote!.from('apparatus_services').upsert(operation.payload);
      case 'complete_service':
        await remote!
            .from('apparatus_services')
            .update(
              Map<String, dynamic>.from(operation.payload['changes'] as Map),
            )
            .eq('id', operation.payload['id']);
      default:
        throw StateError('Unknown operation ${operation.type}');
    }
  }

  /// Drops a queued change from this device. The offline copy is only
  /// corrected when it still carries the change, i.e. when no successful
  /// server sync happened after the change was queued.
  Future<void> discardOperation(
    String userId,
    PendingOperation operation,
  ) async {
    final syncedAt = await lastSyncedAt(userId);
    final cacheStillOptimistic =
        syncedAt == null || !syncedAt.isAfter(operation.createdAt);
    final payload = operation.payload;
    switch (operation.type) {
      case 'add_chemical' || 'add_apparatus':
        final id = payload['id'] as String;
        final kind = operation.type == 'add_chemical'
            ? 'chemical'
            : 'apparatus';
        await local.deleteRecord(userId, kind, id);
        await local.deleteRecordsWhere(
          userId,
          'log',
          (record) => record['item_id'] == id,
        );
        await local.deleteRecordsWhere(
          userId,
          'checkout',
          (record) => record['apparatus_id'] == id,
        );
        await local.deleteRecordsWhere(
          userId,
          'service',
          (record) => record['apparatus_id'] == id,
        );
        // Changes to an item that never reached the server can never apply.
        for (final other in await local.pendingOperations(userId)) {
          if (other.id != operation.id && other.itemId == id) {
            await local.completeOperation(other.id);
          }
        }
      case 'inventory_action':
        final logId = payload['local_log_id'] as String?;
        if (logId != null) await local.deleteRecord(userId, 'log', logId);
        if (cacheStillOptimistic) {
          await _shiftCachedQuantity(
            userId: userId,
            itemType: payload['item_type'] == 'apparatus'
                ? ItemKind.apparatus
                : ItemKind.chemical,
            itemId: payload['item_id'] as String,
            delta:
                _asNum(payload['previous_quantity']) -
                _asNum(payload['new_quantity']),
          );
        }
      case 'undo_action':
        await local.deleteRecord(
          userId,
          'reversal',
          payload['operation_id'] as String,
        );
        if (cacheStillOptimistic) {
          final log = payload['log'];
          if (log is Map) {
            await local.upsertRecord(
              userId,
              'log',
              Map<String, dynamic>.from(log),
            );
          }
          await _shiftCachedQuantity(
            userId: userId,
            itemType: payload['item_type'] == 'apparatus'
                ? ItemKind.apparatus
                : ItemKind.chemical,
            itemId: payload['item_id'] as String,
            delta:
                _asNum(payload['previous_quantity']) -
                _asNum(payload['new_quantity']),
          );
        }
      case 'update_item':
        final previous = payload['previous'];
        if (cacheStillOptimistic && previous is Map && previous.isNotEmpty) {
          final kind = payload['item_type'] == 'apparatus'
              ? 'apparatus'
              : 'chemical';
          final rows = await local.loadRecords(userId, kind);
          final current = rows
              .where((row) => row['id'] == payload['id'])
              .firstOrNull;
          if (current != null) {
            await local.upsertRecord(userId, kind, {
              ...current,
              ...Map<String, dynamic>.from(previous),
            });
          }
        }
      case 'checkout_apparatus':
        await local.deleteRecord(userId, 'checkout', payload['id'] as String);
        // A return queued for a loan that never reached the server is moot.
        for (final other in await local.pendingOperations(userId)) {
          if (other.id != operation.id &&
              other.type == 'return_apparatus' &&
              other.payload['id'] == payload['id']) {
            await local.completeOperation(other.id);
          }
        }
      case 'return_apparatus' || 'complete_service':
        final kind = operation.type == 'return_apparatus'
            ? 'checkout'
            : 'service';
        final previous = payload['previous'];
        if (previous is Map) {
          final rows = await local.loadRecords(userId, kind);
          final current = rows
              .where((row) => row['id'] == payload['id'])
              .firstOrNull;
          if (current != null) {
            await local.upsertRecord(userId, kind, {
              ...current,
              ...Map<String, dynamic>.from(previous),
            });
          }
        }
      case 'schedule_service':
        await local.deleteRecord(userId, 'service', payload['id'] as String);
        for (final other in await local.pendingOperations(userId)) {
          if (other.id != operation.id &&
              other.type == 'complete_service' &&
              other.payload['id'] == payload['id']) {
            await local.completeOperation(other.id);
          }
        }
      default:
        break;
    }
    await local.completeOperation(operation.id);
  }

  static double _quantityAfter(
    double current,
    InventoryAction action,
    double amount,
  ) => switch (action) {
    InventoryAction.consume ||
    InventoryAction.breakage => (current - amount).clamp(0, double.infinity),
    InventoryAction.restock => current + amount,
  };

  static double _asNum(Object? value) => switch (value) {
    num n => n.toDouble(),
    String s => double.tryParse(s) ?? 0,
    _ => 0,
  };

  static bool _isMissingFunction(PostgrestException error) =>
      error.code == 'PGRST202' ||
      error.message.toLowerCase().contains('function');

  static bool _isMissingRelation(PostgrestException error) =>
      error.code == 'PGRST205' ||
      error.code == '42P01' ||
      error.message.toLowerCase().contains('does not exist') ||
      error.message.toLowerCase().contains('schema cache');

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

/// Shown when the `apparatus_checkouts` table has not been created yet.
const checkoutsMigrationHint =
    'Checkouts need the database update in '
    'flutter_app/supabase/005_apparatus_checkouts.sql. Run it, then try '
    'again.';

/// Shown when the `apparatus_services` table has not been created yet.
const servicesMigrationHint =
    'Maintenance and calibration need the database update in '
    'flutter_app/supabase/006_apparatus_maintenance.sql. Run it, then try '
    'again.';

/// Outcome of [InventoryRepository.undoAction].
class UndoResult {
  const UndoResult({
    this.reversal,
    this.item,
    this.cancelled = false,
    this.alreadyUndone = false,
  });

  /// The reversal record, when the change had already reached the server.
  final InventoryReversal? reversal;

  /// Fresh item row returned by the server, when available.
  final Map<String, dynamic>? item;

  /// True when the change was still queued on this device and was cancelled.
  final bool cancelled;

  /// True when the entry had already been undone elsewhere (e.g. on the web).
  final bool alreadyUndone;
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
