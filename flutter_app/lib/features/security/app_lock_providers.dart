import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../app/providers.dart';
import 'domain/app_lock.dart';

/// Minimal key-value contract over the platform secure storage so the lock
/// can be tested with an in-memory store.
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android Keystore / iOS Keychain backed store (flutter_secure_storage).
class KeystoreSecureStore implements SecureStore {
  KeystoreSecureStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on MissingPluginException {
      return null; // Not available in this runtime (e.g. tests).
    } on PlatformException {
      // A corrupted or reset keystore entry: treat as absent rather than
      // locking the person out of the app for good.
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on MissingPluginException {
      throw StateError('Secure storage is not available on this device.');
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on MissingPluginException {
      // Nothing was stored.
    } on PlatformException {
      // Already gone.
    }
  }
}

/// In-memory store for tests.
class MemorySecureStore implements SecureStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

final secureStoreProvider = Provider<SecureStore>((ref) {
  return KeystoreSecureStore();
});

/// Device authentication (fingerprint, face or the phone's screen lock).
abstract class BiometricGate {
  Future<bool> isAvailable();
  Future<bool> authenticate(String reason);
}

class LocalAuthGate implements BiometricGate {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false; // No plugin, no hardware or no screen lock set up.
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      // Cancelled, locked out or unsupported: the PIN keypad stays available.
      return false;
    }
  }
}

final biometricGateProvider = Provider<BiometricGate>((ref) {
  return LocalAuthGate();
});

/// Outcome of a PIN attempt.
enum PinAttempt { accepted, wrong, throttled }

class AppLockState {
  const AppLockState({
    this.ready = false,
    this.enabled = false,
    this.pinLength = 0,
    this.biometrics = true,
    this.biometricsAvailable = false,
    this.timeout = LockTimeout.immediately,
    this.locked = false,
    this.throttle = LockThrottle.none,
  });

  /// False until the stored settings for the signed-in account were read.
  final bool ready;
  final bool enabled;
  final int pinLength;
  final bool biometrics;
  final bool biometricsAvailable;
  final LockTimeout timeout;
  final bool locked;
  final LockThrottle throttle;

  bool get canUseBiometrics => enabled && biometrics && biometricsAvailable;

  AppLockState copyWith({
    bool? ready,
    bool? enabled,
    int? pinLength,
    bool? biometrics,
    bool? biometricsAvailable,
    LockTimeout? timeout,
    bool? locked,
    LockThrottle? throttle,
  }) => AppLockState(
    ready: ready ?? this.ready,
    enabled: enabled ?? this.enabled,
    pinLength: pinLength ?? this.pinLength,
    biometrics: biometrics ?? this.biometrics,
    biometricsAvailable: biometricsAvailable ?? this.biometricsAvailable,
    timeout: timeout ?? this.timeout,
    locked: locked ?? this.locked,
    throttle: throttle ?? this.throttle,
  );
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);

/// Owns the lock for the signed-in account on this phone (SECURITY-01).
///
/// Storage is keyed by user id, so two accounts on one phone keep separate
/// PINs and an ordinary sign-out keeps the lock for the next sign-in. Only
/// "Forgot PIN" (which signs out) and account deletion remove it.
class AppLockController extends Notifier<AppLockState> {
  String? _userId;
  PinHash? _pin;
  AppLockSettings _settings = const AppLockSettings();
  DateTime? _hiddenAt;
  int _generation = 0;

  /// Overridable clock for tests.
  DateTime get clock => DateTime.now();

  /// PBKDF2 rounds for new PINs; tests lower it.
  int get pinIterations => pinDefaultIterations;

  SecureStore get _store => ref.read(secureStoreProvider);

  static String settingsKey(String userId) => 'app_lock.$userId.settings';
  static String pinKey(String userId) => 'app_lock.$userId.pin';
  static String throttleKey(String userId) => 'app_lock.$userId.throttle';

  @override
  AppLockState build() {
    final initialUser = ref.read(authProvider).user?.id;
    ref.listen(authProvider.select((auth) => auth.user?.id), (previous, next) {
      if (next == _userId) return;
      // A sign-in typed moments ago should not be followed by the PIN
      // screen; a session restored at start-up should.
      unawaited(_switchUser(next, startLocked: previous != null));
    });
    unawaited(_switchUser(initialUser, startLocked: true));
    return const AppLockState();
  }

  Future<void> _switchUser(String? userId, {required bool startLocked}) async {
    final generation = ++_generation;
    _userId = userId;
    _hiddenAt = null;
    if (userId == null) {
      _pin = null;
      _settings = const AppLockSettings();
      if (ref.mounted) state = const AppLockState(ready: true);
      return;
    }
    PinHash? pin;
    var settings = const AppLockSettings();
    var throttle = LockThrottle.none;
    var biometricsAvailable = false;
    try {
      final rawPin = await _store.read(pinKey(userId));
      final rawSettings = await _store.read(settingsKey(userId));
      final rawThrottle = await _store.read(throttleKey(userId));
      if (rawPin != null) {
        pin = PinHash.fromJson(jsonDecode(rawPin) as Map<String, dynamic>);
      }
      if (rawSettings != null) {
        settings = AppLockSettings.fromJson(
          jsonDecode(rawSettings) as Map<String, dynamic>,
        );
      }
      if (rawThrottle != null) {
        throttle = LockThrottle.fromJson(
          jsonDecode(rawThrottle) as Map<String, dynamic>,
        );
      }
      biometricsAvailable = await ref.read(biometricGateProvider).isAvailable();
    } catch (_) {
      // Unreadable entries behave like an absent lock; the person can set a
      // new PIN from settings.
      pin = null;
    }
    if (!ref.mounted || generation != _generation) return;
    final enabled = settings.enabled && pin != null;
    _pin = pin;
    _settings = settings;
    state = AppLockState(
      ready: true,
      enabled: enabled,
      pinLength: pin?.length ?? 0,
      biometrics: settings.biometrics,
      biometricsAvailable: biometricsAvailable,
      timeout: settings.timeout,
      locked: enabled && startLocked,
      throttle: enabled ? throttle : LockThrottle.none,
    );
  }

  Future<void> _saveSettings(AppLockSettings settings) async {
    final userId = _userId;
    if (userId == null) return;
    _settings = settings;
    await _store.write(settingsKey(userId), jsonEncode(settings.toJson()));
  }

  Future<void> _saveThrottle(LockThrottle throttle) async {
    final userId = _userId;
    if (userId == null) return;
    if (throttle.failures == 0) {
      await _store.delete(throttleKey(userId));
    } else {
      await _store.write(throttleKey(userId), jsonEncode(throttle.toJson()));
    }
  }

  /// Turns the lock on with [pin]. Returns an error message, or null.
  Future<String?> enable(String pin) async {
    final userId = _userId;
    if (userId == null) return 'Sign in to set up the app lock.';
    final problem = validatePin(pin);
    if (problem != null) return problem;
    try {
      final hash = PinHash.create(pin, iterations: pinIterations);
      await _store.write(pinKey(userId), jsonEncode(hash.toJson()));
      await _saveSettings(_settings.copyWith(enabled: true));
      await _saveThrottle(LockThrottle.none);
      if (!ref.mounted) return null;
      _pin = hash;
      state = state.copyWith(
        enabled: true,
        pinLength: hash.length,
        locked: false,
        throttle: LockThrottle.none,
      );
      return null;
    } catch (error) {
      return _storageProblem(error);
    }
  }

  /// Checks [pin] against the stored hash and updates the throttle.
  Future<PinAttempt> _check(String pin) async {
    final hash = _pin;
    if (hash == null) return PinAttempt.wrong;
    final now = clock;
    if (state.throttle.isThrottled(now)) return PinAttempt.throttled;
    if (hash.verify(pin)) {
      if (state.throttle.failures > 0) {
        await _saveThrottle(LockThrottle.none);
        if (ref.mounted) state = state.copyWith(throttle: LockThrottle.none);
      }
      return PinAttempt.accepted;
    }
    final throttle = state.throttle.afterFailure(now);
    try {
      await _saveThrottle(throttle);
    } catch (_) {
      // Keep counting in memory even if the store is unavailable.
    }
    if (ref.mounted) state = state.copyWith(throttle: throttle);
    return throttle.isThrottled(now) ? PinAttempt.throttled : PinAttempt.wrong;
  }

  /// Unlocks the app when [pin] is right.
  Future<PinAttempt> unlockWithPin(String pin) async {
    if (!state.enabled) return PinAttempt.accepted;
    final result = await _check(pin);
    if (result == PinAttempt.accepted && ref.mounted) {
      state = state.copyWith(locked: false);
    }
    return result;
  }

  /// Unlocks through fingerprint, face or the phone's screen lock.
  Future<bool> unlockWithBiometrics() async {
    if (!state.canUseBiometrics) return false;
    final ok = await ref
        .read(biometricGateProvider)
        .authenticate('Unlock Lab Wizard');
    if (!ok || !ref.mounted) return ok;
    state = state.copyWith(locked: false, throttle: LockThrottle.none);
    try {
      await _saveThrottle(LockThrottle.none);
    } catch (_) {
      // A stale cool-down entry is harmless; it expires on its own.
    }
    return true;
  }

  /// Turns the lock off after confirming [pin]. Returns an error, or null.
  Future<String?> disable(String pin) async {
    final userId = _userId;
    if (userId == null || !state.enabled) return null;
    final result = await _check(pin);
    if (result != PinAttempt.accepted) return _attemptMessage(result);
    try {
      await _store.delete(pinKey(userId));
      await _saveSettings(_settings.copyWith(enabled: false));
      await _saveThrottle(LockThrottle.none);
    } catch (error) {
      return _storageProblem(error);
    }
    if (!ref.mounted) return null;
    _pin = null;
    state = state.copyWith(
      enabled: false,
      pinLength: 0,
      locked: false,
      throttle: LockThrottle.none,
    );
    return null;
  }

  /// Replaces the PIN after confirming the current one.
  Future<String?> changePin({
    required String current,
    required String next,
  }) async {
    final userId = _userId;
    if (userId == null || !state.enabled) return 'The app lock is off.';
    final problem = validatePin(next);
    if (problem != null) return problem;
    final result = await _check(current);
    if (result != PinAttempt.accepted) return _attemptMessage(result);
    try {
      final hash = PinHash.create(next, iterations: pinIterations);
      await _store.write(pinKey(userId), jsonEncode(hash.toJson()));
      if (!ref.mounted) return null;
      _pin = hash;
      state = state.copyWith(pinLength: hash.length);
      return null;
    } catch (error) {
      return _storageProblem(error);
    }
  }

  Future<void> setBiometrics(bool enabled) async {
    try {
      await _saveSettings(_settings.copyWith(biometrics: enabled));
    } catch (_) {
      // Preference could not be saved; keep the in-memory value anyway.
    }
    if (ref.mounted) state = state.copyWith(biometrics: enabled);
  }

  Future<void> setTimeout(LockTimeout timeout) async {
    try {
      await _saveSettings(_settings.copyWith(timeout: timeout));
    } catch (_) {
      // See setBiometrics.
    }
    if (ref.mounted) state = state.copyWith(timeout: timeout);
  }

  /// Locks straight away (settings button).
  void lockNow() {
    if (state.enabled) state = state.copyWith(locked: true);
  }

  /// The app went to the background.
  void onBackground() {
    _hiddenAt ??= clock;
  }

  /// The app came back; lock when it was away for at least the timeout.
  void onForeground() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    if (hiddenAt == null || !state.enabled || state.locked) return;
    if (clock.difference(hiddenAt) >= state.timeout.duration) {
      state = state.copyWith(locked: true);
    }
  }

  /// Removes every stored lock entry of [userId] (account deletion).
  Future<void> forget(String userId) async {
    try {
      await _store.delete(pinKey(userId));
      await _store.delete(settingsKey(userId));
      await _store.delete(throttleKey(userId));
    } catch (_) {
      // Best effort: entries of a deleted account are unreadable anyway.
    }
    if (userId == _userId && ref.mounted) {
      _pin = null;
      _settings = const AppLockSettings();
      state = const AppLockState(ready: true);
    }
  }

  /// "Forgot PIN": removes the lock and signs this phone out, so the account
  /// password is needed to get back in.
  Future<void> forgetPinAndSignOut() async {
    final userId = _userId;
    if (userId != null) await forget(userId);
    await ref.read(authProvider.notifier).signOut();
  }

  String _attemptMessage(PinAttempt result) => switch (result) {
    PinAttempt.accepted => '',
    PinAttempt.wrong => 'Wrong PIN.',
    PinAttempt.throttled => cooldownLabel(state.throttle.remaining(clock)),
  };

  String _storageProblem(Object error) => error is StateError
      ? error.message
      : 'Could not save the lock on this device.';
}
