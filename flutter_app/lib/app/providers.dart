import 'dart:async';

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

class AppPreferences {
  const AppPreferences({
    this.themeMode = ThemeMode.system,
    this.reduceMotion = false,
  });

  final ThemeMode themeMode;
  final bool reduceMotion;

  AppPreferences copyWith({ThemeMode? themeMode, bool? reduceMotion}) =>
      AppPreferences(
        themeMode: themeMode ?? this.themeMode,
        reduceMotion: reduceMotion ?? this.reduceMotion,
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
}

class InventoryState {
  const InventoryState({
    this.chemicals = const [],
    this.apparatus = const [],
    this.logs = const [],
    this.loading = false,
    this.refreshing = false,
    this.fromCache = false,
    this.pendingCount = 0,
    this.error,
    this.lastUpdated,
  });

  final List<Chemical> chemicals;
  final List<Apparatus> apparatus;
  final List<ConsumptionLog> logs;
  final bool loading;
  final bool refreshing;
  final bool fromCache;
  final int pendingCount;
  final String? error;
  final DateTime? lastUpdated;

  int get attentionCount =>
      chemicals.where((item) => item.stockState != StockState.healthy).length +
      apparatus.where((item) => item.stockState != StockState.healthy).length;

  InventoryState copyWith({
    List<Chemical>? chemicals,
    List<Apparatus>? apparatus,
    List<ConsumptionLog>? logs,
    bool? loading,
    bool? refreshing,
    bool? fromCache,
    int? pendingCount,
    String? error,
    DateTime? lastUpdated,
  }) => InventoryState(
    chemicals: chemicals ?? this.chemicals,
    apparatus: apparatus ?? this.apparatus,
    logs: logs ?? this.logs,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    fromCache: fromCache ?? this.fromCache,
    pendingCount: pendingCount ?? this.pendingCount,
    error: error,
    lastUpdated: lastUpdated ?? this.lastUpdated,
  );
}

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
      state = state.copyWith(
        loading: false,
        refreshing: false,
        fromCache: true,
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
      state = state.copyWith(
        refreshing: false,
        fromCache: true,
        error: 'Still offline — your saved copy is available.',
      );
    }
  }

  void _applySnapshot(InventorySnapshot snapshot, {bool loading = false}) {
    state = InventoryState(
      chemicals: snapshot.chemicals,
      apparatus: snapshot.apparatus,
      logs: snapshot.logs,
      loading: loading,
      fromCache: snapshot.fromCache,
      pendingCount: snapshot.pendingCount,
      lastUpdated: DateTime.now(),
    );
  }

  Future<void> addChemical({
    required String name,
    required String formula,
    required String unit,
    required double quantity,
    required double threshold,
    required String notes,
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
    );
    final cached = await _repository.loadCached(userId);
    state = state.copyWith(
      chemicals: [
        item,
        ...state.chemicals.where((value) => value.id != item.id),
      ],
      pendingCount: cached.pendingCount,
    );
  }

  Future<void> addApparatus({
    required String name,
    required String category,
    required double quantity,
    required double threshold,
    required String notes,
  }) async {
    final userId = _requireUser();
    final item = await _repository.addApparatus(
      userId: userId,
      name: name,
      category: category,
      quantity: quantity,
      threshold: threshold,
      notes: notes,
    );
    final cached = await _repository.loadCached(userId);
    state = state.copyWith(
      apparatus: [
        item,
        ...state.apparatus.where((value) => value.id != item.id),
      ],
      pendingCount: cached.pendingCount,
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
      pendingCount: cached.pendingCount,
      fromCache: cached.pendingCount > 0,
    );
  }

  Future<void> applyAction({
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
      pendingCount: cached.pendingCount,
      fromCache: cached.pendingCount > 0,
    );
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
    );
  }

  void clearMemory() {
    _activeUserId = null;
    state = const InventoryState();
  }

  String _requireUser() {
    final userId = _activeUserId;
    if (userId == null) throw StateError('Please sign in first.');
    return userId;
  }
}
