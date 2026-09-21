import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/database/local_database.dart';
import '../features/inventory/data/inventory_repository.dart';
import '../features/inventory/domain/models.dart';

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  return AppConfig.hasSupabase ? Supabase.instance.client : null;
});

final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  final database = LocalDatabase();
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(
    local: ref.watch(localDatabaseProvider),
    remote: ref.watch(supabaseClientProvider),
  );
});

enum AuthPhase {
  setupRequired,
  signedOut,
  signingIn,
  signedIn,
  awaitingVerification,
}

class AuthState {
  const AuthState({required this.phase, this.user, this.error});

  final AuthPhase phase;
  final User? user;
  final String? error;

  bool get isBusy => phase == AuthPhase.signingIn;

  AuthState copyWith({AuthPhase? phase, User? user, String? error}) =>
      AuthState(
        phase: phase ?? this.phase,
        user: user ?? this.user,
        error: error,
      );
}

final authProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  StreamSubscription<dynamic>? _subscription;

  @override
  AuthState build() {
    final client = ref.watch(supabaseClientProvider);
    if (client == null) {
      return const AuthState(phase: AuthPhase.setupRequired);
    }
    final user = client.auth.currentUser;
    _subscription = client.auth.onAuthStateChange.listen((change) {
      final nextUser = change.session?.user;
      if (nextUser == null) {
        state = const AuthState(phase: AuthPhase.signedOut);
        ref.read(inventoryProvider.notifier).clearMemory();
      } else {
        state = AuthState(phase: AuthPhase.signedIn, user: nextUser);
      }
    });
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    return AuthState(
      phase: user == null ? AuthPhase.signedOut : AuthPhase.signedIn,
      user: user,
    );
  }

  Future<void> signIn(String email, String password) async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
    state = const AuthState(phase: AuthPhase.signingIn);
    try {
      final response = await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      state = AuthState(phase: AuthPhase.signedIn, user: response.user);
    } on AuthException catch (error) {
      state = AuthState(phase: AuthPhase.signedOut, error: error.message);
    } catch (_) {
      state = const AuthState(
        phase: AuthPhase.signedOut,
        error: 'Could not connect. Check your internet and try again.',
      );
    }
  }

  Future<void> signUp(String name, String email, String password) async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
    state = const AuthState(phase: AuthPhase.signingIn);
    try {
      final response = await client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'name': name.trim()},
      );
      if (response.session == null) {
        state = const AuthState(phase: AuthPhase.awaitingVerification);
      } else {
        state = AuthState(phase: AuthPhase.signedIn, user: response.user);
      }
    } on AuthException catch (error) {
      state = AuthState(phase: AuthPhase.signedOut, error: error.message);
    } catch (_) {
      state = const AuthState(
        phase: AuthPhase.signedOut,
        error: 'Could not create the account. Please try again.',
      );
    }
  }

  Future<void> signOut() async {
    final client = ref.read(supabaseClientProvider);
    final userId = state.user?.id;
    try {
      await client?.auth.signOut();
    } finally {
      if (userId != null) {
        await ref.read(localDatabaseProvider).clearUser(userId);
      }
      ref.read(inventoryProvider.notifier).clearMemory();
      state = const AuthState(phase: AuthPhase.signedOut);
    }
  }
}

/// How the chemical and apparatus shelves lay out their rows (UX-01).
enum InventoryDensity {
  /// Full notebook cards with stock bars and captions.
  detailed,

  /// One-line rows that keep quantity, status, and quick actions visible.
  compact,
}

class AppPreferences {
  const AppPreferences({
    this.themeMode = ThemeMode.system,
    this.reduceMotion = false,
    this.inventoryDensity = InventoryDensity.detailed,
  });

  final ThemeMode themeMode;
  final bool reduceMotion;
  final InventoryDensity inventoryDensity;

  AppPreferences copyWith({
    ThemeMode? themeMode,
    bool? reduceMotion,
    InventoryDensity? inventoryDensity,
  }) => AppPreferences(
    themeMode: themeMode ?? this.themeMode,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    inventoryDensity: inventoryDensity ?? this.inventoryDensity,
  );
}

final preferencesProvider =
    NotifierProvider<PreferencesController, AppPreferences>(
      PreferencesController.new,
    );

class PreferencesController extends Notifier<AppPreferences> {
  @override
  AppPreferences build() {
    unawaited(_restore());
    return const AppPreferences();
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final savedTheme = preferences.getString('theme');
    state = AppPreferences(
      themeMode: switch (savedTheme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      reduceMotion: preferences.getBool('reduce_motion') ?? false,
      inventoryDensity: preferences.getString('inventory_density') == 'compact'
          ? InventoryDensity.compact
          : InventoryDensity.detailed,
    );
  }

  Future<void> setTheme(ThemeMode value) async {
    state = state.copyWith(themeMode: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('theme', value.name);
  }

  Future<void> setReduceMotion(bool value) async {
    state = state.copyWith(reduceMotion: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('reduce_motion', value);
  }

  Future<void> setInventoryDensity(InventoryDensity value) async {
    state = state.copyWith(inventoryDensity: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('inventory_density', value.name);
  }
}

/// Values the add/action forms remember for the signed-in user on this
/// device (FORM-01). Nothing here leaves the phone.
class FormMemory {
  const FormMemory({
    this.lastUnit,
    this.lastCategory,
    this.lastThresholds = const {},
    this.lastActionAmounts = const {},
    this.prefillThreshold = true,
    this.prefillActionAmount = true,
  });

  final String? lastUnit;
  final String? lastCategory;

  /// Last low-stock level typed per item kind (key: `ItemKind.name`).
  final Map<String, double> lastThresholds;

  /// Last amount per kind and action (key: `chemical.consume`).
  final Map<String, double> lastActionAmounts;
  final bool prefillThreshold;
  final bool prefillActionAmount;

  static String amountKey(ItemKind kind, InventoryAction action) =>
      '${kind.name}.${action.name}';

  double? thresholdFor(ItemKind kind) =>
      prefillThreshold ? lastThresholds[kind.name] : null;

  double? amountFor(ItemKind kind, InventoryAction action) =>
      prefillActionAmount ? lastActionAmounts[amountKey(kind, action)] : null;

  bool get isEmpty =>
      lastUnit == null &&
      lastCategory == null &&
      lastThresholds.isEmpty &&
      lastActionAmounts.isEmpty;

  FormMemory copyWith({
    String? lastUnit,
    String? lastCategory,
    Map<String, double>? lastThresholds,
    Map<String, double>? lastActionAmounts,
    bool? prefillThreshold,
    bool? prefillActionAmount,
  }) => FormMemory(
    lastUnit: lastUnit ?? this.lastUnit,
    lastCategory: lastCategory ?? this.lastCategory,
    lastThresholds: lastThresholds ?? this.lastThresholds,
    lastActionAmounts: lastActionAmounts ?? this.lastActionAmounts,
    prefillThreshold: prefillThreshold ?? this.prefillThreshold,
    prefillActionAmount: prefillActionAmount ?? this.prefillActionAmount,
  );
}

final formMemoryProvider = NotifierProvider<FormMemoryController, FormMemory>(
  FormMemoryController.new,
);

class FormMemoryController extends Notifier<FormMemory> {
  String _prefix = 'form.anonymous.';

  @override
  FormMemory build() {
    final userId = ref.watch(authProvider.select((value) => value.user?.id));
    _prefix = 'form.${userId ?? 'anonymous'}.';
    unawaited(_restore(_prefix));
    return const FormMemory();
  }

  Future<void> _restore(String prefix) async {
    final preferences = await SharedPreferences.getInstance();
    if (prefix != _prefix) return;
    state = FormMemory(
      lastUnit: preferences.getString('${prefix}unit'),
      lastCategory: preferences.getString('${prefix}category'),
      lastThresholds: _readDoubles(preferences, '${prefix}threshold.'),
      lastActionAmounts: _readDoubles(preferences, '${prefix}amount.'),
      prefillThreshold:
          preferences.getBool('${prefix}prefill_threshold') ?? true,
      prefillActionAmount:
          preferences.getBool('${prefix}prefill_amount') ?? true,
    );
  }

  static Map<String, double> _readDoubles(
    SharedPreferences preferences,
    String prefix,
  ) => {
    for (final key in preferences.getKeys())
      if (key.startsWith(prefix) && preferences.getDouble(key) != null)
        key.substring(prefix.length): preferences.getDouble(key)!,
  };

  /// Remembers the choices made while adding an item.
  Future<void> rememberAdd({
    required ItemKind kind,
    String? unit,
    String? category,
    double? threshold,
  }) async {
    final thresholds = {...state.lastThresholds};
    if (threshold != null) thresholds[kind.name] = threshold;
    state = state.copyWith(
      lastUnit: unit,
      lastCategory: category,
      lastThresholds: thresholds,
    );
    final preferences = await SharedPreferences.getInstance();
    if (unit != null) await preferences.setString('${_prefix}unit', unit);
    if (category != null) {
      await preferences.setString('${_prefix}category', category);
    }
    if (threshold != null) {
      await preferences.setDouble(
        '${_prefix}threshold.${kind.name}',
        threshold,
      );
    }
  }

  /// Remembers the amount just recorded for [kind]/[action].
  Future<void> rememberAmount(
    ItemKind kind,
    InventoryAction action,
    double amount,
  ) async {
    final key = FormMemory.amountKey(kind, action);
    state = state.copyWith(
      lastActionAmounts: {...state.lastActionAmounts, key: amount},
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble('${_prefix}amount.$key', amount);
  }

  Future<void> setPrefillThreshold(bool value) async {
    state = state.copyWith(prefillThreshold: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('${_prefix}prefill_threshold', value);
  }

  Future<void> setPrefillActionAmount(bool value) async {
    state = state.copyWith(prefillActionAmount: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('${_prefix}prefill_amount', value);
  }

  /// Forgets remembered values but keeps the prefill switches.
  Future<void> forget() async {
    state = FormMemory(
      prefillThreshold: state.prefillThreshold,
      prefillActionAmount: state.prefillActionAmount,
    );
    final preferences = await SharedPreferences.getInstance();
    for (final key in preferences.getKeys().toList()) {
      if (key.startsWith(_prefix) && !key.contains('prefill_')) {
        await preferences.remove(key);
      }
    }
  }
}

class InventoryState {
  const InventoryState({
    this.chemicals = const [],
    this.apparatus = const [],
    this.logs = const [],
    this.outbox = const [],
    this.reversals = const [],
    this.checkouts = const [],
    this.services = const [],
    this.loading = false,
    this.refreshing = false,
    this.fromCache = false,
    this.error,
    this.lastUpdated,
    this.lastSyncedAt,
  });

  final List<Chemical> chemicals;
  final List<Apparatus> apparatus;
  final List<ConsumptionLog> logs;

  /// Changes queued on this device, oldest first (SYNC-01).
  final List<PendingOperation> outbox;

  /// Undone actions, newest first (UX-04).
  final List<InventoryReversal> reversals;

  /// Apparatus loans, newest first (GEAR-02).
  final List<ApparatusCheckout> checkouts;

  /// Maintenance and calibration tasks, open ones first (GEAR-03).
  final List<ApparatusService> services;
  final bool loading;
  final bool refreshing;
  final bool fromCache;
  final String? error;
  final DateTime? lastUpdated;

  /// Last time the server copy was fully downloaded on this device.
  final DateTime? lastSyncedAt;

  /// Every change still waiting on this device, including failed ones.
  int get pendingCount => outbox.length;

  /// Changes that stopped retrying and need the user to look at them.
  int get failedCount => outbox.where((operation) => operation.isFailed).length;

  int get attentionCount =>
      chemicals.where((item) => item.stockState != StockState.healthy).length +
      apparatus.where((item) => item.stockState != StockState.healthy).length;

  /// Open loans of one apparatus, newest first.
  List<ApparatusCheckout> openCheckoutsFor(String apparatusId) => [
    for (final checkout in checkouts)
      if (checkout.apparatusId == apparatusId && checkout.isOpen) checkout,
  ];

  /// Pieces of one apparatus currently lent out.
  double checkedOutCount(String apparatusId) =>
      openCheckoutsFor(apparatusId)
          .fold<double>(0, (sum, checkout) => sum + checkout.outstanding);

  /// Pieces of one apparatus that can still be lent.
  double availableCount(Apparatus item) {
    final left = item.quantity - checkedOutCount(item.id);
    return left < 0 ? 0 : left;
  }

  /// Loans past their due date, newest first.
  List<ApparatusCheckout> overdueCheckouts({DateTime? now}) => [
    for (final checkout in checkouts)
      if (checkout.isOverdue(now: now)) checkout,
  ];

  /// Tasks of one apparatus in display order (open first).
  List<ApparatusService> servicesFor(String apparatusId) => [
    for (final service in services)
      if (service.apparatusId == apparatusId) service,
  ];

  /// Open tasks of one apparatus, soonest due first.
  List<ApparatusService> openServicesFor(String apparatusId) => [
    for (final service in services)
      if (service.apparatusId == apparatusId && service.isOpen) service,
  ];

  /// Most urgent state among an apparatus' open tasks: `expired` when a
  /// task is overdue, `expiringSoon` when one is due within two weeks.
  ExpiryState serviceStateFor(String apparatusId, {DateTime? now}) {
    var worst = ExpiryState.none;
    for (final service in openServicesFor(apparatusId)) {
      final state = service.dueState(now: now);
      if (state.index > worst.index) worst = state;
    }
    return worst;
  }

  /// The overdue or soonest due-soon open task of one apparatus, or null
  /// when nothing needs attention.
  ApparatusService? urgentServiceFor(String apparatusId, {DateTime? now}) {
    ApparatusService? best;
    var bestState = ExpiryState.none;
    for (final service in openServicesFor(apparatusId)) {
      final state = service.dueState(now: now);
      if (state != ExpiryState.expired && state != ExpiryState.expiringSoon) {
        continue;
      }
      final better =
          best == null ||
          state.index > bestState.index ||
          (state == bestState &&
              service.dueAt != null &&
              best.dueAt != null &&
              service.dueAt!.isBefore(best.dueAt!));
      if (better) {
        best = service;
        bestState = state;
      }
    }
    return best;
  }

  /// Open tasks that are overdue or due soon, across all apparatus.
  List<ApparatusService> serviceAlerts({DateTime? now}) => [
    for (final service in services)
      if (service.dueState(now: now) == ExpiryState.expired ||
          service.dueState(now: now) == ExpiryState.expiringSoon)
        service,
  ];

  InventoryState copyWith({
    List<Chemical>? chemicals,
    List<Apparatus>? apparatus,
    List<ConsumptionLog>? logs,
    List<PendingOperation>? outbox,
    List<InventoryReversal>? reversals,
    List<ApparatusCheckout>? checkouts,
    List<ApparatusService>? services,
    bool? loading,
    bool? refreshing,
    bool? fromCache,
    String? error,
    DateTime? lastUpdated,
    DateTime? lastSyncedAt,
  }) => InventoryState(
    chemicals: chemicals ?? this.chemicals,
    apparatus: apparatus ?? this.apparatus,
    logs: logs ?? this.logs,
    outbox: outbox ?? this.outbox,
    reversals: reversals ?? this.reversals,
    checkouts: checkouts ?? this.checkouts,
    services: services ?? this.services,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    fromCache: fromCache ?? this.fromCache,
    error: error,
    lastUpdated: lastUpdated ?? this.lastUpdated,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
  );
}

/// Reports whether the device has any network at all. Used before actions
/// that must not be queued, such as deleting items. Unknown counts as online
/// so the server can give the final answer.
final isOnlineProvider = Provider<Future<bool> Function()>(
  (ref) => () async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((result) => result != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  },
);

final inventoryProvider = NotifierProvider<InventoryController, InventoryState>(
  InventoryController.new,
);

class InventoryController extends Notifier<InventoryState> {
  String? _activeUserId;

  InventoryRepository get _repository => ref.read(inventoryRepositoryProvider);

  @override
  InventoryState build() => const InventoryState();

  Future<void> bootstrap(String userId) async {
    if (_activeUserId == userId &&
        (state.loading || state.lastUpdated != null)) {
      return;
    }
    _activeUserId = userId;
    state = state.copyWith(loading: true);
    try {
      final cached = await _repository.loadCached(userId);
      if (_activeUserId != userId) return;
      _applySnapshot(cached, loading: true);
      await _repository.syncPending(userId);
      final fresh = await _repository.refresh(userId);
      if (_activeUserId != userId) return;
      _applySnapshot(fresh);
    } catch (_) {
      await _reloadOutbox(
        loading: false,
        error: 'Offline copy shown. Pull down to try syncing again.',
      );
    }
  }

  Future<void> refresh() async {
    final userId = _activeUserId;
    if (userId == null) return;
    state = state.copyWith(refreshing: true);
    try {
      await _repository.syncPending(userId);
      _applySnapshot(await _repository.refresh(userId));
    } catch (_) {
      await _reloadOutbox(
        error: 'Still offline — your saved copy is available.',
      );
    }
  }

  /// Retries one queued change, then refreshes when the server is reachable.
  Future<void> retryOperation(String operationId) async {
    final userId = _activeUserId;
    if (userId == null) return;
    state = state.copyWith(refreshing: true);
    try {
      await _repository.syncPending(userId, operationId: operationId);
      _applySnapshot(await _repository.refresh(userId));
    } catch (_) {
      await _reloadOutbox(
        error: 'Still offline — the change stays in the queue.',
      );
    }
  }

  /// Retries every queued change, including the ones marked as failed.
  Future<void> retryAll() async {
    final userId = _activeUserId;
    if (userId == null) return;
    state = state.copyWith(refreshing: true);
    try {
      await _repository.syncPending(userId, retryFailed: true);
      _applySnapshot(await _repository.refresh(userId));
    } catch (_) {
      await _reloadOutbox(
        error: 'Still offline — the changes stay in the queue.',
      );
    }
  }

  /// Removes a queued change from this device without sending it.
  Future<void> discardOperation(String operationId) async {
    final userId = _requireUser();
    final operation = state.outbox
        .where((entry) => entry.id == operationId)
        .firstOrNull;
    if (operation == null) return;
    await _repository.discardOperation(userId, operation);
    _applySnapshot(await _repository.loadCached(userId));
    unawaited(refresh());
  }

  Future<void> _reloadOutbox({bool? loading, required String error}) async {
    final userId = _activeUserId;
    if (userId == null) return;
    try {
      final cached = await _repository.loadCached(userId);
      state = state.copyWith(
        loading: loading ?? state.loading,
        refreshing: false,
        fromCache: true,
        outbox: cached.outbox,
        lastSyncedAt: cached.lastSyncedAt,
        error: error,
      );
    } catch (_) {
      state = state.copyWith(
        loading: loading ?? state.loading,
        refreshing: false,
        fromCache: true,
        error: error,
      );
    }
  }

  void _applySnapshot(InventorySnapshot snapshot, {bool loading = false}) {
    state = InventoryState(
      chemicals: snapshot.chemicals,
      apparatus: snapshot.apparatus,
      logs: snapshot.logs,
      outbox: snapshot.outbox,
      reversals: snapshot.reversals,
      checkouts: snapshot.checkouts,
      services: snapshot.services,
      loading: loading,
      fromCache: snapshot.fromCache,
      lastUpdated: DateTime.now(),
      lastSyncedAt: snapshot.lastSyncedAt ?? state.lastSyncedAt,
    );
  }

  Future<void> addChemical({
    required String name,
    required String formula,
    required String unit,
    required double quantity,
    required double threshold,
    required String notes,
    ChemicalDetails details = const ChemicalDetails(),
  }) async {
    final userId = _requireUser();
    final item = await _repository.addChemical(
      userId: userId,
      name: name,
      formula: formula,
      unit: unit,
      quantity: quantity,
      threshold: threshold,
      notes: notes,
      details: details,
    );
    final cached = await _repository.loadCached(userId);
    state = state.copyWith(
      chemicals: [
        item,
        ...state.chemicals.where((value) => value.id != item.id),
      ],
      outbox: cached.outbox,
    );
  }

  Future<void> addApparatus({
    required String name,
    required String category,
    required double quantity,
    required double threshold,
    required String notes,
    ApparatusDetails details = const ApparatusDetails(),
  }) async {
    final userId = _requireUser();
    final item = await _repository.addApparatus(
      userId: userId,
      name: name,
      category: category,
      quantity: quantity,
      threshold: threshold,
      notes: notes,
      details: details,
    );
    final cached = await _repository.loadCached(userId);
    state = state.copyWith(
      apparatus: [
        item,
        ...state.apparatus.where((value) => value.id != item.id),
      ],
      outbox: cached.outbox,
    );
  }

  Future<void> updateItem({
    required ItemKind type,
    required String id,
    required Map<String, dynamic> changes,
  }) async {
    final userId = _requireUser();
    final saved = await _repository.updateItem(
      userId: userId,
      type: type,
      id: id,
      changes: changes,
      itemName: _nameOf(type, id),
    );
    final cached = await _repository.loadCached(userId);
    state = state.copyWith(
      chemicals: type == ItemKind.chemical
          ? state.chemicals
                .map((item) => item.id == id ? Chemical.fromMap(saved) : item)
                .toList()
          : state.chemicals,
      apparatus: type == ItemKind.apparatus
          ? state.apparatus
                .map((item) => item.id == id ? Apparatus.fromMap(saved) : item)
                .toList()
          : state.apparatus,
      outbox: cached.outbox,
      fromCache: cached.pendingCount > 0,
    );
  }

  Future<ConsumptionLog> applyAction({
    required String itemId,
    required ItemKind itemType,
    required InventoryAction action,
    required double amount,
    required String note,
    required DateTime date,
  }) async {
    if (amount <= 0) throw ArgumentError('Amount must be greater than zero.');
    final userId = _requireUser();
    final current = itemType == ItemKind.chemical
        ? state.chemicals.firstWhere((item) => item.id == itemId).quantity
        : state.apparatus.firstWhere((item) => item.id == itemId).quantity;
    if (action != InventoryAction.restock && amount > current) {
      throw StateError('Only ${formatQuantity(current)} available.');
    }
    final log = await _repository.applyAction(
      userId: userId,
      itemId: itemId,
      itemType: itemType,
      action: action,
      amount: amount,
      previousQuantity: current,
      note: note,
      loggedAt: date,
      itemName: _nameOf(itemType, itemId),
      unit: _unitOf(itemType, itemId),
    );
    final nextQuantity = switch (action) {
      InventoryAction.restock => current + amount,
      InventoryAction.consume || InventoryAction.breakage => current - amount,
    };
    final cached = await _repository.loadCached(userId);
    state = state.copyWith(
      chemicals: itemType == ItemKind.chemical
          ? state.chemicals
                .map(
                  (item) => item.id == itemId
                      ? item.copyWith(quantity: nextQuantity)
                      : item,
                )
                .toList()
          : state.chemicals,
      apparatus: itemType == ItemKind.apparatus
          ? state.apparatus
                .map(
                  (item) => item.id == itemId
                      ? item.copyWith(quantity: nextQuantity)
                      : item,
                )
                .toList()
          : state.apparatus,
      logs: [log, ...state.logs.where((value) => value.id != log.id)],
      outbox: cached.outbox,
      fromCache: cached.pendingCount > 0,
    );
    return log;
  }

  /// Reverses a recorded action from the last [undoWindow] (UX-04).
  Future<UndoResult> undoAction(String logId, {String reason = ''}) async {
    final userId = _requireUser();
    final log = state.logs.where((entry) => entry.id == logId).firstOrNull;
    if (log == null) {
      throw StateError('This entry is no longer in the history.');
    }
    if (!isUndoable(log)) {
      throw StateError(
        'Only changes from the last ${undoWindow.inDays} days can be undone.',
      );
    }
    final current = log.itemType == ItemKind.chemical
        ? state.chemicals
              .where((item) => item.id == log.itemId)
              .firstOrNull
              ?.quantity
        : state.apparatus
              .where((item) => item.id == log.itemId)
              .firstOrNull
              ?.quantity;
    if (current == null) throw StateError('The item no longer exists.');
    final result = await _repository.undoAction(
      userId: userId,
      log: log,
      currentQuantity: current,
      reason: reason,
      itemName: _nameOf(log.itemType, log.itemId),
      unit: _unitOf(log.itemType, log.itemId),
    );
    final serverQuantity = result.item?['quantity'];
    final nextQuantity = serverQuantity is num
        ? serverQuantity.toDouble()
        : log.action == InventoryAction.restock
        ? (current - log.amount).clamp(0, double.infinity).toDouble()
        : current + log.amount;
    final cached = await _repository.loadCached(userId);
    state = state.copyWith(
      chemicals: log.itemType == ItemKind.chemical
          ? state.chemicals
                .map(
                  (item) => item.id == log.itemId
                      ? item.copyWith(quantity: nextQuantity)
                      : item,
                )
                .toList()
          : state.chemicals,
      apparatus: log.itemType == ItemKind.apparatus
          ? state.apparatus
                .map(
                  (item) => item.id == log.itemId
                      ? item.copyWith(quantity: nextQuantity)
                      : item,
                )
                .toList()
          : state.apparatus,
      logs: state.logs.where((entry) => entry.id != logId).toList(),
      reversals: cached.reversals,
      outbox: cached.outbox,
      fromCache: cached.pendingCount > 0,
    );
    if (result.alreadyUndone) unawaited(refresh());
    return result;
  }

  Future<void> deleteItem(ItemKind type, String id) async {
    final userId = _requireUser();
    await _repository.deleteItem(userId: userId, type: type, id: id);
    state = state.copyWith(
      chemicals: type == ItemKind.chemical
          ? state.chemicals.where((item) => item.id != id).toList()
          : state.chemicals,
      apparatus: type == ItemKind.apparatus
          ? state.apparatus.where((item) => item.id != id).toList()
          : state.apparatus,
      logs: state.logs.where((log) => log.itemId != id).toList(),
      reversals: state.reversals
          .where((reversal) => reversal.itemId != id)
          .toList(),
      checkouts: state.checkouts
          .where((checkout) => checkout.apparatusId != id)
          .toList(),
      services: state.services
          .where((service) => service.apparatusId != id)
          .toList(),
    );
  }

  /// Schedules maintenance or calibration for an apparatus (GEAR-03).
  Future<ApparatusService> scheduleService({
    required String apparatusId,
    required ServiceKind kind,
    required String title,
    required String note,
    DateTime? dueAt,
  }) async {
    final userId = _requireUser();
    final item = state.apparatus
        .where((entry) => entry.id == apparatusId)
        .firstOrNull;
    if (item == null) throw StateError('The apparatus no longer exists.');
    final service = await _repository.scheduleService(
      userId: userId,
      apparatusId: apparatusId,
      kind: kind,
      title: title,
      note: note,
      dueAt: dueAt,
      itemName: item.name,
    );
    final cached = await _repository.loadCached(userId);
    state = state.copyWith(
      services: InventoryRepository.sortedServices([
        service,
        ...state.services.where((entry) => entry.id != service.id),
      ]),
      outbox: cached.outbox,
      fromCache: cached.pendingCount > 0,
    );
    return service;
  }

  /// Marks a task done and optionally schedules the next one of the same
  /// kind (recurring maintenance / calibration intervals).
  Future<ApparatusService> completeService({
    required String serviceId,
    required DateTime completedAt,
    required String performedBy,
    required String result,
    required String note,
    DateTime? nextDueAt,
  }) async {
    final userId = _requireUser();
    final service = state.services
        .where((entry) => entry.id == serviceId)
        .firstOrNull;
    if (service == null) throw StateError('The task no longer exists.');
    if (service.isDone) throw StateError('This task is already completed.');
    if (completedAt.isAfter(DateTime.now().add(const Duration(days: 1)))) {
      throw ArgumentError('The completion date cannot be in the future.');
    }
    final updated = await _repository.completeService(
      userId: userId,
      service: service,
      completedAt: completedAt,
      performedBy: performedBy,
      result: result,
      note: note,
      itemName: _nameOf(ItemKind.apparatus, service.apparatusId),
    );
    var services = state.services
        .map((entry) => entry.id == updated.id ? updated : entry)
        .toList();
    if (nextDueAt != null) {
      final next = await _repository.scheduleService(
        userId: userId,
        apparatusId: service.apparatusId,
        kind: service.kind,
        title: service.title,
        note: '',
        dueAt: nextDueAt,
        itemName: _nameOf(ItemKind.apparatus, service.apparatusId),
      );
      services = [next, ...services];
    }
    final cached = await _repository.loadCached(userId);
    state = state.copyWith(
      services: InventoryRepository.sortedServices(services),
      outbox: cached.outbox,
      fromCache: cached.pendingCount > 0,
    );
    return updated;
  }

  /// Lends pieces of an apparatus to a person (GEAR-02).
  Future<ApparatusCheckout> checkoutApparatus({
    required String apparatusId,
    required double quantity,
    required String person,
    required String note,
    DateTime? dueAt,
  }) async {
    if (quantity <= 0) throw ArgumentError('Quantity must be at least 1.');
    if (quantity != quantity.roundToDouble()) {
      throw ArgumentError('Check out whole pieces.');
    }
    if (person.trim().isEmpty) throw ArgumentError('Who is taking it?');
    final userId = _requireUser();
    final item = state.apparatus
        .where((entry) => entry.id == apparatusId)
        .firstOrNull;
    if (item == null) throw StateError('The apparatus no longer exists.');
    final available = state.availableCount(item);
    if (quantity > available) {
      throw StateError(
        available <= 0
            ? 'Every piece is already checked out.'
            : 'Only ${formatQuantity(available)} available to check out.',
      );
    }
    final checkout = await _repository.checkoutApparatus(
      userId: userId,
      apparatusId: apparatusId,
      quantity: quantity,
      person: person,
      note: note,
      dueAt: dueAt,
      itemName: item.name,
    );
    final cached = await _repository.loadCached(userId);
    state = state.copyWith(
      checkouts: [
        checkout,
        ...state.checkouts.where((entry) => entry.id != checkout.id),
      ],
      outbox: cached.outbox,
      fromCache: cached.pendingCount > 0,
    );
    return checkout;
  }

  /// Returns pieces from a loan; the loan closes when everything is back.
  Future<ApparatusCheckout> returnApparatus({
    required String checkoutId,
    required double quantity,
    required String note,
  }) async {
    final userId = _requireUser();
    final checkout = state.checkouts
        .where((entry) => entry.id == checkoutId)
        .firstOrNull;
    if (checkout == null) throw StateError('The loan no longer exists.');
    if (!checkout.isOpen) throw StateError('This loan is already closed.');
    if (quantity <= 0) throw ArgumentError('Return at least 1 piece.');
    if (quantity != quantity.roundToDouble()) {
      throw ArgumentError('Return whole pieces.');
    }
    if (quantity > checkout.outstanding) {
      throw StateError(
        'Only ${formatQuantity(checkout.outstanding)} still out on this loan.',
      );
    }
    final updated = await _repository.returnApparatus(
      userId: userId,
      checkout: checkout,
      quantity: quantity,
      note: note,
      itemName: _nameOf(ItemKind.apparatus, checkout.apparatusId),
    );
    final cached = await _repository.loadCached(userId);
    state = state.copyWith(
      checkouts: state.checkouts
          .map((entry) => entry.id == updated.id ? updated : entry)
          .toList(),
      outbox: cached.outbox,
      fromCache: cached.pendingCount > 0,
    );
    return updated;
  }

  void clearMemory() {
    _activeUserId = null;
    state = const InventoryState();
  }

  String? _nameOf(ItemKind type, String id) => type == ItemKind.chemical
      ? state.chemicals.where((item) => item.id == id).firstOrNull?.name
      : state.apparatus.where((item) => item.id == id).firstOrNull?.name;

  String _unitOf(ItemKind type, String id) => type == ItemKind.chemical
      ? state.chemicals.where((item) => item.id == id).firstOrNull?.unit ?? ''
      : 'pcs';

  String _requireUser() {
    final userId = _activeUserId;
    if (userId == null) throw StateError('Please sign in first.');
    return userId;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
