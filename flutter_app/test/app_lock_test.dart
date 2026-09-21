import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/features/security/app_lock_providers.dart';
import 'package:lab_wizard/features/security/domain/app_lock.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

final _userJson = {
  'id': 'u1',
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': 'ali@example.org',
  'app_metadata': {'provider': 'email'},
  'user_metadata': {},
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
};

class _FakeAuth extends AuthController {
  var signOuts = 0;

  @override
  AuthState build() =>
      AuthState(phase: AuthPhase.signedIn, user: User.fromJson(_userJson));

  @override
  Future<void> signOut({bool everywhere = false}) async {
    signOuts++;
    state = const AuthState(phase: AuthPhase.signedOut);
  }

  /// Simulates an auth change (the setter itself is protected).
  void become(AuthState next) => state = next;
}

class _FakeGate implements BiometricGate {
  _FakeGate({this.available = false, this.result = false});

  bool available;
  bool result;
  var prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return result;
  }
}

class _TestLock extends AppLockController {
  DateTime now = DateTime(2026, 9, 21, 10);

  @override
  DateTime get clock => now;

  @override
  int get pinIterations => 200;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

({ProviderContainer container, _FakeAuth auth, _TestLock lock}) _harness(
  MemorySecureStore store,
  _FakeGate gate,
) {
  late _FakeAuth auth;
  late _TestLock lock;
  final container = ProviderContainer(
    overrides: [
      secureStoreProvider.overrideWithValue(store),
      biometricGateProvider.overrideWithValue(gate),
      authProvider.overrideWith(() => auth = _FakeAuth()),
      appLockProvider.overrideWith(() => lock = _TestLock()),
    ],
  );
  addTearDown(container.dispose);
  container.read(appLockProvider);
  return (container: container, auth: auth, lock: lock);
}

void main() {
  group('PBKDF2 / PinHash', () {
    test('matches the reference vectors', () {
      final p = utf8.encode('password');
      final s = utf8.encode('salt');
      expect(
        _hex(pbkdf2Sha256(p, s, 1)),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
      expect(
        _hex(pbkdf2Sha256(p, s, 2)),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
      expect(
        _hex(pbkdf2Sha256(p, s, 4096)),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });

    test('hashes with a random salt, verifies and round-trips JSON', () {
      final a = PinHash.create('2468', iterations: 200, random: Random(1));
      final b = PinHash.create('2468', iterations: 200, random: Random(2));
      expect(a.salt, isNot(equals(b.salt)));
      expect(a.hash, isNot(equals(b.hash)));
      expect(a.verify('2468'), isTrue);
      expect(b.verify('2468'), isTrue);
      expect(a.verify('2469'), isFalse);
      expect(a.verify(''), isFalse);
      final json = jsonEncode(a.toJson());
      expect(json, isNot(contains('2468')));
      final restored = PinHash.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      expect(restored.verify('2468'), isTrue);
      expect(restored.length, 4);
      expect(restored.iterations, 200);
    });

    test('deterministic salt reproduces a known hash', () {
      final salt = List<int>.generate(16, (i) => i);
      expect(
        _hex(pbkdf2Sha256(utf8.encode('2468'), salt, 200)),
        '3d28803a62737e37593fc5bc6565d62276d48b766801cb128e25bdc54aec2f74',
      );
    });

    test('constant-time compare', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    });
  });

  group('validation, settings and throttle', () {
    test('validatePin', () {
      expect(validatePin('2468'), isNull);
      expect(validatePin('24681357'), isNull);
      expect(validatePin('123'), contains('4 to 8 digits'));
      expect(validatePin('123456789'), contains('4 to 8 digits'));
      expect(validatePin('12a4'), 'Digits only.');
      expect(validatePin('1111'), contains('same digit'));
    });

    test('settings JSON and timeout parsing', () {
      const settings = AppLockSettings(
        enabled: true,
        biometrics: false,
        timeout: LockTimeout.fiveMinutes,
      );
      final restored = AppLockSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );
      expect(restored.enabled, isTrue);
      expect(restored.biometrics, isFalse);
      expect(restored.timeout, LockTimeout.fiveMinutes);
      expect(LockTimeout.parse('nonsense'), LockTimeout.immediately);
      expect(LockTimeout.parse(null), LockTimeout.immediately);
      expect(const AppLockSettings().biometrics, isTrue);
    });

    test('throttle starts after five failures and doubles up to a cap', () {
      final now = DateTime(2026, 9, 21, 10);
      var throttle = LockThrottle.none;
      for (var i = 1; i <= 4; i++) {
        throttle = throttle.afterFailure(now);
        expect(throttle.failures, i);
        expect(throttle.isThrottled(now), isFalse);
      }
      throttle = throttle.afterFailure(now);
      expect(throttle.remaining(now), const Duration(seconds: 30));
      throttle = throttle.afterFailure(now);
      expect(throttle.remaining(now), const Duration(seconds: 60));
      for (var i = 0; i < 6; i++) {
        throttle = throttle.afterFailure(now);
      }
      expect(throttle.remaining(now), lockMaxCooldown);
      expect(
        throttle.remaining(now.add(const Duration(minutes: 11))),
        Duration.zero,
      );
      final restored = LockThrottle.fromJson(
        jsonDecode(jsonEncode(throttle.toJson())) as Map<String, dynamic>,
      );
      expect(restored.failures, throttle.failures);
      expect(restored.lockedUntil, throttle.lockedUntil!.toUtc());
      expect(cooldownLabel(const Duration(seconds: 28)), 'Try again in 28 s');
      expect(cooldownLabel(const Duration(seconds: 90)), 'Try again in 2 min');
    });
  });

  group('AppLockController', () {
    test('enable, lock, wrong and right PIN', () async {
      final store = MemorySecureStore();
      final h = _harness(store, _FakeGate());
      await _settle();
      var state = h.container.read(appLockProvider);
      expect(state.ready, isTrue);
      expect(state.enabled, isFalse);

      expect(await h.lock.enable('1111'), contains('same digit'));
      expect(await h.lock.enable('2468'), isNull);
      state = h.container.read(appLockProvider);
      expect(state.enabled, isTrue);
      expect(state.pinLength, 4);
      expect(state.locked, isFalse, reason: 'just set up, not locked');
      expect(store.values.keys, contains('app_lock.u1.pin'));
      expect(store.values['app_lock.u1.pin'], isNot(contains('2468')));

      h.lock.lockNow();
      expect(h.container.read(appLockProvider).locked, isTrue);
      expect(await h.lock.unlockWithPin('0000'), PinAttempt.wrong);
      expect(h.container.read(appLockProvider).throttle.failures, 1);
      expect(h.container.read(appLockProvider).locked, isTrue);
      expect(await h.lock.unlockWithPin('2468'), PinAttempt.accepted);
      state = h.container.read(appLockProvider);
      expect(state.locked, isFalse);
      expect(state.throttle.failures, 0);
      expect(store.values.containsKey('app_lock.u1.throttle'), isFalse);
    });

    test('five wrong PINs start a cool-down that survives a restart', () async {
      final store = MemorySecureStore();
      final h = _harness(store, _FakeGate());
      await _settle();
      await h.lock.enable('2468');
      h.lock.lockNow();
      for (var i = 0; i < 4; i++) {
        expect(await h.lock.unlockWithPin('9999'), PinAttempt.wrong);
      }
      expect(await h.lock.unlockWithPin('9999'), PinAttempt.throttled);
      expect(
        h.container.read(appLockProvider).throttle.remaining(h.lock.now),
        const Duration(seconds: 30),
      );
      // Even the right PIN waits out the cool-down.
      expect(await h.lock.unlockWithPin('2468'), PinAttempt.throttled);
      expect(h.container.read(appLockProvider).locked, isTrue);

      // A fresh controller (app restart) reads the persisted cool-down.
      final again = _harness(store, _FakeGate());
      await _settle();
      final restored = again.container.read(appLockProvider);
      expect(restored.enabled, isTrue);
      expect(restored.locked, isTrue, reason: 'starts locked after restart');
      expect(restored.throttle.failures, 5);
      expect(await again.lock.unlockWithPin('2468'), PinAttempt.throttled);

      again.lock.now = again.lock.now.add(const Duration(seconds: 31));
      expect(await again.lock.unlockWithPin('2468'), PinAttempt.accepted);
      expect(again.container.read(appLockProvider).throttle.failures, 0);
    });

    test('background timeout', () async {
      final h = _harness(MemorySecureStore(), _FakeGate());
      await _settle();
      await h.lock.enable('2468');
      expect(
        h.container.read(appLockProvider).timeout,
        LockTimeout.immediately,
      );

      h.lock.onBackground();
      h.lock.now = h.lock.now.add(const Duration(seconds: 2));
      h.lock.onForeground();
      expect(h.container.read(appLockProvider).locked, isTrue);
      await h.lock.unlockWithPin('2468');

      await h.lock.setTimeout(LockTimeout.fiveMinutes);
      h.lock.onBackground();
      h.lock.now = h.lock.now.add(const Duration(minutes: 2));
      h.lock.onForeground();
      expect(h.container.read(appLockProvider).locked, isFalse);

      h.lock.onBackground();
      h.lock.now = h.lock.now.add(const Duration(minutes: 6));
      h.lock.onForeground();
      expect(h.container.read(appLockProvider).locked, isTrue);

      // Foreground without a preceding background trip changes nothing.
      await h.lock.unlockWithPin('2468');
      h.lock.now = h.lock.now.add(const Duration(hours: 1));
      h.lock.onForeground();
      expect(h.container.read(appLockProvider).locked, isFalse);
    });

    test('biometrics unlock when available and switched on', () async {
      final gate = _FakeGate(available: true, result: true);
      final h = _harness(MemorySecureStore(), gate);
      await _settle();
      expect(await h.lock.unlockWithBiometrics(), isFalse, reason: 'no lock');
      await h.lock.enable('2468');
      expect(h.container.read(appLockProvider).canUseBiometrics, isTrue);
      h.lock.lockNow();
      expect(await h.lock.unlockWithBiometrics(), isTrue);
      expect(gate.prompts, 1);
      expect(h.container.read(appLockProvider).locked, isFalse);

      await h.lock.setBiometrics(false);
      h.lock.lockNow();
      expect(await h.lock.unlockWithBiometrics(), isFalse);
      expect(gate.prompts, 1, reason: 'not prompted when switched off');
      expect(h.container.read(appLockProvider).locked, isTrue);

      gate.result = false;
      await h.lock.setBiometrics(true);
      expect(await h.lock.unlockWithBiometrics(), isFalse);
      expect(h.container.read(appLockProvider).locked, isTrue);
    });

    test('disable and change PIN need the current PIN', () async {
      final store = MemorySecureStore();
      final h = _harness(store, _FakeGate());
      await _settle();
      await h.lock.enable('2468');

      expect(
        await h.lock.changePin(current: '0000', next: '1357'),
        'Wrong PIN.',
      );
      expect(
        await h.lock.changePin(current: '2468', next: '12'),
        contains('4 to 8 digits'),
      );
      expect(await h.lock.changePin(current: '2468', next: '135790'), isNull);
      expect(h.container.read(appLockProvider).pinLength, 6);
      h.lock.lockNow();
      expect(await h.lock.unlockWithPin('2468'), PinAttempt.wrong);
      expect(await h.lock.unlockWithPin('135790'), PinAttempt.accepted);

      expect(await h.lock.disable('2468'), 'Wrong PIN.');
      expect(h.container.read(appLockProvider).enabled, isTrue);
      expect(await h.lock.disable('135790'), isNull);
      final state = h.container.read(appLockProvider);
      expect(state.enabled, isFalse);
      expect(state.pinLength, 0);
      expect(store.values.containsKey('app_lock.u1.pin'), isFalse);
      expect(await h.lock.unlockWithPin('anything'), PinAttempt.accepted);
    });

    test('forgot PIN removes the lock and signs out', () async {
      final store = MemorySecureStore();
      final h = _harness(store, _FakeGate());
      await _settle();
      await h.lock.enable('2468');
      h.lock.lockNow();
      await h.lock.forgetPinAndSignOut();
      await _settle();
      expect(h.auth.signOuts, 1);
      expect(
        store.values.keys.where((k) => k.startsWith('app_lock.u1')),
        isEmpty,
      );
      final state = h.container.read(appLockProvider);
      expect(state.enabled, isFalse);
      expect(state.locked, isFalse);
    });

    test('an ordinary sign-out keeps the PIN for the next sign-in', () async {
      final store = MemorySecureStore();
      final h = _harness(store, _FakeGate());
      await _settle();
      await h.lock.enable('2468');
      h.auth.become(const AuthState(phase: AuthPhase.signedOut));
      await _settle();
      expect(h.container.read(appLockProvider).enabled, isFalse);
      expect(store.values.containsKey('app_lock.u1.pin'), isTrue);

      // Signing in again interactively: lock configured but not shown yet.
      h.auth.become(
        AuthState(phase: AuthPhase.signedIn, user: User.fromJson(_userJson)),
      );
      await _settle();
      final state = h.container.read(appLockProvider);
      expect(state.enabled, isTrue);
      expect(state.locked, isFalse);
    });

    test('accounts keep separate locks', () async {
      final store = MemorySecureStore();
      final h = _harness(store, _FakeGate());
      await _settle();
      await h.lock.enable('2468');
      h.auth.become(
        AuthState(
          phase: AuthPhase.signedIn,
          user: User.fromJson({..._userJson, 'id': 'u2'}),
        ),
      );
      await _settle();
      expect(h.container.read(appLockProvider).enabled, isFalse);
      expect(store.values.containsKey('app_lock.u1.pin'), isTrue);
      expect(store.values.containsKey('app_lock.u2.pin'), isFalse);
    });
  });
}
