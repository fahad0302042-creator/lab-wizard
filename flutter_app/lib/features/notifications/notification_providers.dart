import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import '../../core/utils/errors.dart';
import 'data/notification_gateway.dart';
import 'domain/alerts.dart';
import 'domain/notification_preferences.dart';

export 'data/notification_gateway.dart';
export 'domain/alerts.dart';
export 'domain/notification_preferences.dart';

/// Platform gateway; tests override this with [RecordingNotificationGateway].
final notificationGatewayProvider = Provider<NotificationGateway>(
  (ref) => LocalNotificationGateway(),
);

/// Persisted notification preferences (NOTIFY-01).
final notificationPreferencesProvider =
    NotifierProvider<NotificationPreferencesController, NotificationPreferences>(
      NotificationPreferencesController.new,
    );

class NotificationPreferencesController
    extends Notifier<NotificationPreferences> {
  static const storageKey = 'notification_preferences';

  @override
  NotificationPreferences build() {
    unawaited(_restore());
    return const NotificationPreferences();
  }

  Future<void> _restore() async {
    final store = await SharedPreferences.getInstance();
    final saved = store.getString(storageKey);
    if (saved != null) state = NotificationPreferences.decode(saved);
  }

  Future<void> update(
    NotificationPreferences Function(NotificationPreferences current) change,
  ) async {
    state = change(state);
    final store = await SharedPreferences.getInstance();
    await store.setString(storageKey, state.encode());
  }
}

/// Everything that currently needs attention, most urgent first. Kind
/// switches decide what is included; the master switch only controls
/// system notifications, so the in-app list keeps working without it.
final alertsProvider = Provider<List<AppAlert>>((ref) {
  final inventory = ref.watch(inventoryProvider);
  final preferences = ref.watch(notificationPreferencesProvider);
  return buildAlerts(
    preferences: preferences,
    chemicals: inventory.chemicals,
    apparatus: inventory.apparatus,
    checkouts: inventory.checkouts,
    services: inventory.services,
    outbox: inventory.outbox,
  );
});

/// What the coordinator last did, for the settings card.
class NotificationStatus {
  const NotificationStatus({
    this.permissionGranted,
    this.lastDispatchAt,
    this.scheduledCount = 0,
    this.shownCount = 0,
    this.lastError,
    this.busy = false,
    this.pendingTap,
  });

  /// Null until the OS has been asked.
  final bool? permissionGranted;
  final DateTime? lastDispatchAt;
  final int scheduledCount;
  final int shownCount;
  final String? lastError;
  final bool busy;

  /// Payload of a tapped notification waiting for the UI to open it.
  final String? pendingTap;

  bool get blocked => permissionGranted == false;

  NotificationStatus copyWith({
    bool? permissionGranted,
    DateTime? lastDispatchAt,
    int? scheduledCount,
    int? shownCount,
    String? lastError,
    bool clearError = false,
    bool? busy,
    String? pendingTap,
    bool clearTap = false,
  }) => NotificationStatus(
    permissionGranted: permissionGranted ?? this.permissionGranted,
    lastDispatchAt: lastDispatchAt ?? this.lastDispatchAt,
    scheduledCount: scheduledCount ?? this.scheduledCount,
    shownCount: shownCount ?? this.shownCount,
    lastError: clearError ? null : lastError ?? this.lastError,
    busy: busy ?? this.busy,
    pendingTap: clearTap ? null : pendingTap ?? this.pendingTap,
  );
}

final notificationCoordinatorProvider =
    NotifierProvider<NotificationCoordinator, NotificationStatus>(
      NotificationCoordinator.new,
    );

/// Turns alerts and due dates into system notifications (NOTIFY-02/03/04).
///
/// * Alerts are shown at most once per day per subject (a persisted
///   `id → date` map), so a nightly open does not re-fire everything.
/// * More than three new alerts at once collapse into one digest.
/// * Future reminders are re-planned from scratch after every data change:
///   cancel the pending ones, schedule the new plan.
class NotificationCoordinator extends Notifier<NotificationStatus> {
  static const notifiedKey = 'notification_shown_dates';
  static const digestId = 1;
  static const testId = 2;
  static const debounce = Duration(seconds: 2);

  Timer? _timer;
  StreamSubscription<String>? _tapSubscription;

  /// Overridable clock for tests.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  @override
  NotificationStatus build() {
    ref.onDispose(() {
      _timer?.cancel();
      unawaited(_tapSubscription?.cancel());
    });
    ref.listen(alertsProvider, (_, _) => _scheduleDispatch());
    ref.listen(notificationPreferencesProvider, (previous, next) {
      if (previous?.enabled == true && !next.enabled) {
        unawaited(_disable());
      } else {
        _scheduleDispatch();
      }
    });
    ref.listen(
      inventoryProvider.select(
        (inventory) => (
          inventory.loading,
          inventory.lastUpdated,
          inventory.checkouts.length,
          inventory.services.length,
        ),
      ),
      (_, _) => _scheduleDispatch(),
    );
    ref.listen(authProvider.select((auth) => auth.phase), (_, phase) {
      if (phase == AuthPhase.signedOut) unawaited(_disable(keepPrefs: true));
    });
    final gateway = ref.read(notificationGatewayProvider);
    _tapSubscription = gateway.taps.listen(
      (payload) => state = state.copyWith(pendingTap: payload),
    );
    return const NotificationStatus();
  }

  /// Kicks off the first dispatch once the user is signed in; the listeners
  /// set up in [build] handle everything after that.
  void start() => _scheduleDispatch();

  /// The UI has handled the tapped notification.
  void consumeTap() => state = state.copyWith(clearTap: true);

  void _scheduleDispatch() {
    if (!ref.read(notificationPreferencesProvider).enabled) return;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(dispatch()));
  }

  /// Asks the OS for permission and turns the master switch on when
  /// granted. Returns whether notifications are allowed.
  Future<bool> enable() async {
    final gateway = ref.read(notificationGatewayProvider);
    state = state.copyWith(busy: true, clearError: true);
    try {
      final granted = await gateway.requestPermission();
      state = state.copyWith(permissionGranted: granted, busy: false);
      await ref
          .read(notificationPreferencesProvider.notifier)
          .update((current) => current.copyWith(enabled: granted));
      if (granted) await dispatch(force: true);
      return granted;
    } catch (error) {
      state = state.copyWith(
        busy: false,
        lastError: _describe(error),
      );
      return false;
    }
  }

  /// Re-checks the OS permission (e.g. after the user comes back from the
  /// system settings page).
  Future<void> refreshPermission() async {
    try {
      final granted = await ref.read(notificationGatewayProvider).areEnabled();
      state = state.copyWith(permissionGranted: granted);
    } catch (_) {
      // Platform without notifications; leave the status untouched.
    }
  }

  Future<void> openSystemSettings() async {
    try {
      await ref.read(notificationGatewayProvider).openSettings();
    } catch (error) {
      state = state.copyWith(lastError: _describe(error));
    }
  }

  /// Shows one notification immediately so the user can check the sound
  /// and channel settings.
  Future<void> sendTest() async {
    final gateway = ref.read(notificationGatewayProvider);
    try {
      await gateway.show(
        id: testId,
        title: 'Lab Wizard notifications work',
        body: 'You will hear from us about stock, expiry and apparatus.',
        channel: AlertChannel.stock,
        payload: 'alerts',
      );
      state = state.copyWith(clearError: true);
    } catch (error) {
      state = state.copyWith(lastError: _describe(error));
    }
  }

  /// Shows new alerts and re-plans reminders. Skipped while the master
  /// switch is off or the inventory is still loading.
  Future<void> dispatch({bool force = false}) async {
    final preferences = ref.read(notificationPreferencesProvider);
    if (!preferences.enabled) return;
    final inventory = ref.read(inventoryProvider);
    if (inventory.loading && !force) return;
    final gateway = ref.read(notificationGatewayProvider);
    state = state.copyWith(busy: true);
    try {
      await gateway.initialize();
      final shown = await _showNewAlerts(
        ref.read(alertsProvider),
        gateway,
        force: force,
      );
      final reminders = planReminders(
        preferences: preferences,
        chemicals: inventory.chemicals,
        apparatus: inventory.apparatus,
        checkouts: inventory.checkouts,
        services: inventory.services,
        now: now(),
      );
      await gateway.cancelPending();
      for (final reminder in reminders) {
        await gateway.schedule(reminder);
      }
      state = state.copyWith(
        busy: false,
        lastDispatchAt: now(),
        scheduledCount: reminders.length,
        shownCount: shown,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        busy: false,
        lastError: _describe(error),
      );
    }
  }

  Future<int> _showNewAlerts(
    List<AppAlert> alerts,
    NotificationGateway gateway, {
    required bool force,
  }) async {
    final store = await SharedPreferences.getInstance();
    final history = _readHistory(store);
    final today = _dayKey(now());
    final fresh = alerts
        .where((alert) => force || history[alert.id] != today)
        .toList();
    if (fresh.isEmpty) return 0;
    if (fresh.length > 3) {
      final urgent = fresh.where((alert) => alert.kind.urgent).length;
      await gateway.show(
        id: digestId,
        title: '${fresh.length} things need attention',
        body: [
          if (urgent > 0) '$urgent urgent',
          ...fresh.take(3).map((alert) => alert.title),
        ].join(' · '),
        channel: AlertChannel.stock,
        payload: 'alerts',
      );
    } else {
      for (final alert in fresh) {
        await gateway.show(
          id: notificationIdFor(alert.id),
          title: alert.title,
          body: alert.body,
          channel: alert.kind.channel,
          payload: alert.payload,
        );
      }
    }
    final next = <String, String>{
      for (final alert in alerts) alert.id: history[alert.id] ?? today,
    };
    for (final alert in fresh) {
      next[alert.id] = today;
    }
    await store.setString(notifiedKey, jsonEncode(next));
    return fresh.length;
  }

  Map<String, String> _readHistory(SharedPreferences store) {
    final raw = store.getString(notifiedKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final entry in decoded.entries)
            entry.key.toString(): entry.value.toString(),
        };
      }
    } catch (_) {
      // Corrupt history just means alerts may repeat once.
    }
    return {};
  }

  static String _describe(Object error) {
    if (error is MissingPluginException ||
        error.toString().contains('MissingPluginException')) {
      return 'Notifications are not available in this build of the app.';
    }
    return friendlyErrorMessage(error);
  }

  static String _dayKey(DateTime time) =>
      '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';

  Future<void> _disable({bool keepPrefs = false}) async {
    _timer?.cancel();
    try {
      final gateway = ref.read(notificationGatewayProvider);
      if (keepPrefs && !ref.read(notificationPreferencesProvider).enabled) {
        return;
      }
      await gateway.cancelPending();
      state = state.copyWith(scheduledCount: 0, clearError: true);
    } catch (error) {
      state = state.copyWith(lastError: _describe(error));
    }
  }
}
