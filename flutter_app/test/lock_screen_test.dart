import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_wizard/app/providers.dart';
import 'package:lab_wizard/core/theme/app_theme.dart';
import 'package:lab_wizard/features/security/app_lock_providers.dart';
import 'package:lab_wizard/features/security/domain/app_lock.dart';
import 'package:lab_wizard/features/security/presentation/lock_screen.dart';
import 'package:lab_wizard/features/settings/presentation/app_lock_card.dart';
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

/// A store that already holds an enabled 4-digit PIN "2468" for u1.
MemorySecureStore _lockedStore({bool biometrics = true}) {
  final store = MemorySecureStore();
  final hash = PinHash.create('2468', iterations: 200);
  store.values[AppLockController.pinKey('u1')] = jsonEncode(hash.toJson());
  store.values[AppLockController.settingsKey('u1')] = jsonEncode(
    AppLockSettings(enabled: true, biometrics: biometrics).toJson(),
  );
  return store;
}

Future<
  ({
    ProviderContainer container,
    _FakeAuth auth,
    _TestLock lock,
    _FakeGate gate,
  })
>
_pumpApp(
  WidgetTester tester, {
  required MemorySecureStore store,
  _FakeGate? gate,
  Widget home = const Scaffold(body: Text('shelf content')),
  double height = 900,
}) async {
  tester.view.physicalSize = Size(420, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theGate = gate ?? _FakeGate();
  late _FakeAuth auth;
  late _TestLock lock;
  final container = ProviderContainer(
    overrides: [
      secureStoreProvider.overrideWithValue(store),
      biometricGateProvider.overrideWithValue(theGate),
      authProvider.overrideWith(() => auth = _FakeAuth()),
      appLockProvider.overrideWith(() => lock = _TestLock()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => LockGate(child: child!),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container: container, auth: auth, lock: lock, gate: theGate);
}

/// Sends a lifecycle message the way the platform does, so the binding
/// generates the intermediate states and notifies observers.
Future<void> _lifecycle(WidgetTester tester, String state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    const StringCodec().encodeMessage('AppLifecycleState.$state'),
    (_) {},
  );
}

Future<void> _type(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.byKey(Key('lock-key-$digit')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no lock configured: the app shows straight away', (
    tester,
  ) async {
    await _pumpApp(tester, store: MemorySecureStore());
    expect(find.byKey(const Key('lock-screen')), findsNothing);
    expect(find.byKey(const Key('lock-loading')), findsNothing);
    expect(find.text('shelf content'), findsOneWidget);
  });

  testWidgets(
    'starts locked, rejects a wrong PIN and opens with the right one',
    (tester) async {
      final h = await _pumpApp(tester, store: _lockedStore(biometrics: false));
      expect(find.byKey(const Key('lock-screen')), findsOneWidget);
      expect(find.text('Enter your 4-digit PIN'), findsOneWidget);
      expect(find.byKey(const Key('lock-biometric')), findsNothing);
      // The shelf is still mounted (state preserved) but not reachable.
      expect(find.text('shelf content'), findsOneWidget);
      final blockers = tester.widgetList<IgnorePointer>(
        find.ancestor(
          of: find.text('shelf content'),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(blockers.any((blocker) => blocker.ignoring), isTrue);

      await _type(tester, '111');
      await tester.tap(find.byKey(const Key('lock-backspace')));
      await tester.pump();
      await _type(tester, '19');
      expect(find.byKey(const Key('lock-error')), findsOneWidget);
      expect(find.textContaining('Wrong PIN'), findsOneWidget);
      expect(h.container.read(appLockProvider).throttle.failures, 1);

      await _type(tester, '2468');
      expect(find.byKey(const Key('lock-screen')), findsNothing);
      expect(h.container.read(appLockProvider).locked, isFalse);
    },
  );

  testWidgets('locks again after a background trip and shows the cool-down', (
    tester,
  ) async {
    final h = await _pumpApp(tester, store: _lockedStore(biometrics: false));
    await _type(tester, '2468');
    expect(find.byKey(const Key('lock-screen')), findsNothing);

    await _lifecycle(tester, 'paused');
    h.lock.now = h.lock.now.add(const Duration(seconds: 5));
    await _lifecycle(tester, 'resumed');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lock-screen')), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await _type(tester, '0000');
    }
    expect(find.textContaining('1 more try'), findsOneWidget);
    await _type(tester, '0000');
    expect(find.textContaining('Try again in 30 s'), findsOneWidget);
    // Keys are disabled while throttled.
    final key = tester.widget<OutlinedButton>(
      find.byKey(const Key('lock-key-2')),
    );
    expect(key.onPressed, isNull);

    h.lock.now = h.lock.now.add(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lock-error')), findsNothing);
    await _type(tester, '2468');
    expect(find.byKey(const Key('lock-screen')), findsNothing);
  });

  testWidgets('biometric prompt runs on show and the button retries', (
    tester,
  ) async {
    final gate = _FakeGate(available: true, result: false);
    final h = await _pumpApp(tester, store: _lockedStore(), gate: gate);
    expect(find.byKey(const Key('lock-screen')), findsOneWidget);
    expect(gate.prompts, 1, reason: 'prompted automatically once');
    expect(find.byKey(const Key('lock-biometric')), findsOneWidget);

    gate.result = true;
    await tester.tap(find.byKey(const Key('lock-biometric')));
    await tester.pumpAndSettle();
    expect(gate.prompts, 2);
    expect(find.byKey(const Key('lock-screen')), findsNothing);
    expect(h.container.read(appLockProvider).locked, isFalse);
  });

  testWidgets('forgot PIN signs out after an inline confirmation', (
    tester,
  ) async {
    final store = _lockedStore(biometrics: false);
    final h = await _pumpApp(tester, store: store);
    await tester.tap(find.byKey(const Key('lock-forgot')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lock-forgot-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('lock-forgot-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lock-forgot-confirm')), findsNothing);
    expect(h.auth.signOuts, 0);

    await tester.tap(find.byKey(const Key('lock-forgot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lock-forgot-confirm')));
    await tester.pumpAndSettle();
    expect(h.auth.signOuts, 1);
    expect(find.byKey(const Key('lock-screen')), findsNothing);
    expect(store.values.containsKey(AppLockController.pinKey('u1')), isFalse);
  });

  testWidgets('settings card sets up, changes and removes the PIN', (
    tester,
  ) async {
    final store = MemorySecureStore();
    final h = await _pumpApp(
      tester,
      store: store,
      gate: _FakeGate(available: true),
      home: const Scaffold(body: SingleChildScrollView(child: AppLockCard())),
      height: 1600,
    );
    expect(find.text('Off'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lock-enabled')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-new')), '2468');
    await tester.enterText(find.byKey(const Key('pin-confirm')), '2469');
    await tester.tap(find.byKey(const Key('pin-save')));
    await tester.pumpAndSettle();
    expect(find.text('The PINs do not match.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('pin-confirm')), '2468');
    await tester.tap(find.byKey(const Key('pin-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pin-save')), findsNothing);
    var state = h.container.read(appLockProvider);
    expect(state.enabled, isTrue);
    expect(state.locked, isFalse);
    expect(find.textContaining('4-digit PIN'), findsOneWidget);
    expect(find.byKey(const Key('lock-biometrics')), findsOneWidget);

    // Timeout and biometrics preferences persist.
    await tester.tap(find.byKey(const Key('lock-timeout')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('after 5 minutes').last);
    await tester.pumpAndSettle();
    expect(h.container.read(appLockProvider).timeout, LockTimeout.fiveMinutes);
    await tester.tap(find.byKey(const Key('lock-biometrics')));
    await tester.pumpAndSettle();
    expect(h.container.read(appLockProvider).biometrics, isFalse);
    final saved = AppLockSettings.fromJson(
      jsonDecode(store.values[AppLockController.settingsKey('u1')]!)
          as Map<String, dynamic>,
    );
    expect(saved.timeout, LockTimeout.fiveMinutes);
    expect(saved.biometrics, isFalse);

    // Change PIN: wrong current PIN is refused.
    await tester.tap(find.byKey(const Key('lock-change-pin')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-current')), '0000');
    await tester.enterText(find.byKey(const Key('pin-new')), '1357');
    await tester.enterText(find.byKey(const Key('pin-confirm')), '1357');
    await tester.tap(find.byKey(const Key('pin-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pin-error')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('pin-current')), '2468');
    await tester.tap(find.byKey(const Key('pin-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pin-save')), findsNothing);
    h.lock.lockNow();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lock-screen')), findsOneWidget);
    await _type(tester, '1357');
    expect(find.byKey(const Key('lock-screen')), findsNothing);

    // Lock now button locks immediately.
    await tester.tap(find.byKey(const Key('lock-now')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lock-screen')), findsOneWidget);
    await _type(tester, '1357');

    // Turning off asks for the PIN.
    await tester.tap(find.byKey(const Key('lock-enabled')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-current')), '1357');
    await tester.tap(find.byKey(const Key('pin-save')));
    await tester.pumpAndSettle();
    state = h.container.read(appLockProvider);
    expect(state.enabled, isFalse);
    expect(find.text('Off'), findsOneWidget);
    expect(store.values.containsKey(AppLockController.pinKey('u1')), isFalse);
  });
}
