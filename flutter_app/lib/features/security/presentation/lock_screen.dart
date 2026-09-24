import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../app_lock_providers.dart';
import '../domain/app_lock.dart';

/// Sits above the root navigator (MaterialApp.builder) so the lock covers
/// dialogs and sheets too. Tracks the app lifecycle for the timeout and hides
/// the app from pointer, focus and screen readers while locked.
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(appLockProvider.notifier);
    switch (state) {
      // `inactive` also fires for the biometric prompt and the notification
      // shade, so only a real background trip starts the timer.
      case AppLifecycleState.paused:
        lock.onBackground();
      case AppLifecycleState.resumed:
        lock.onForeground();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(
      authProvider.select((auth) => auth.phase == AuthPhase.signedIn),
    );
    final lock = ref.watch(appLockProvider);
    final covered = signedIn && (lock.locked || !lock.ready);
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: covered,
          child: ExcludeSemantics(
            excluding: covered,
            child: IgnorePointer(ignoring: covered, child: widget.child),
          ),
        ),
        if (covered)
          Positioned.fill(
            child: lock.ready
                ? const LockScreen()
                : ColoredBox(
                    key: const Key('lock-loading'),
                    color: context.paperColor,
                  ),
          ),
      ],
    );
  }
}

/// PIN keypad with an optional biometric shortcut and the "Forgot PIN"
/// escape hatch (signs out; the account password gets the person back in).
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _entry = '';
  String? _error;
  bool _checking = false;
  bool _forgotOpen = false;
  bool _promptedBiometrics = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoPrompt();
      if (_throttled) _startTicker();
    });
  }

  DateTime get _now => ref.read(appLockProvider.notifier).clock;

  bool get _throttled => ref.read(appLockProvider).throttle.isThrottled(_now);

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _autoPrompt() {
    if (!mounted || _promptedBiometrics) return;
    if (!ref.read(appLockProvider).canUseBiometrics) return;
    _promptedBiometrics = true;
    unawaited(_biometrics());
  }

  Future<void> _biometrics() async {
    if (_checking) return;
    setState(() => _checking = true);
    await ref.read(appLockProvider.notifier).unlockWithBiometrics();
    if (mounted) setState(() => _checking = false);
  }

  /// Counts the cool-down down once a second and clears it when over.
  void _startTicker() {
    _ticker?.cancel();
    _error = cooldownLabel(ref.read(appLockProvider).throttle.remaining(_now));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = ref.read(appLockProvider).throttle.remaining(_now);
      if (remaining == Duration.zero) {
        _ticker?.cancel();
        _ticker = null;
        setState(() => _error = null);
        return;
      }
      // Only repaint when the visible number changes.
      final label = cooldownLabel(remaining);
      if (label != _error) setState(() => _error = label);
    });
  }

  Future<void> _submit() async {
    if (_checking) return;
    final pin = _entry;
    setState(() {
      _checking = true;
      _error = null;
    });
    final result = await ref.read(appLockProvider.notifier).unlockWithPin(pin);
    if (!mounted) return;
    final lock = ref.read(appLockProvider);
    setState(() {
      _checking = false;
      _entry = '';
      switch (result) {
        case PinAttempt.accepted:
          _error = null;
        case PinAttempt.wrong:
          final left = lockMaxFailures - lock.throttle.failures;
          _error = left > 0 && left <= 2
              ? 'Wrong PIN. $left more ${left == 1 ? 'try' : 'tries'} '
                    'before a pause.'
              : 'Wrong PIN.';
          unawaited(HapticFeedback.vibrate());
        case PinAttempt.throttled:
          unawaited(HapticFeedback.vibrate());
          _startTicker();
      }
    });
  }

  void _tap(String digit) {
    final lock = ref.read(appLockProvider);
    if (_checking || _throttled) return;
    if (_entry.length >= lock.pinLength) return;
    setState(() {
      _entry += digit;
      _error = null;
    });
    if (_entry.length == lock.pinLength) unawaited(_submit());
  }

  void _backspace() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final throttled = lock.throttle.isThrottled(_now);
    final muted = context.mutedInkColor;
    final width = MediaQuery.sizeOf(context).width;
    final keypadWidth = width.clamp(240.0, 360.0).toDouble();
    return Scaffold(
      key: const Key('lock-screen'),
      backgroundColor: context.paperColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: keypadWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 40,
                    color: context.marginRedColor,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Lab Wizard is locked',
                    style: TextStyle(
                      fontFamily: 'Kalam',
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enter your ${lock.pinLength}-digit PIN',
                    style: TextStyle(color: muted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Semantics(
                    label:
                        '${_entry.length} of ${lock.pinLength} digits entered',
                    liveRegion: true,
                    child: _PinDots(
                      count: _entry.length,
                      total: lock.pinLength,
                    ),
                  ),
                  ConstrainedBox(
                    // Reserves a line so the keypad does not jump; grows
                    // with large text instead of clipping (A11Y-02).
                    constraints: const BoxConstraints(minHeight: 36),
                    child: Center(
                      child: _error == null
                          ? null
                          : Text(
                              _error!,
                              key: const Key('lock-error'),
                              style: TextStyle(
                                color: context.marginRedColor,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                    ),
                  ),
                  _Keypad(
                    enabled: !_checking && !throttled,
                    onDigit: _tap,
                    onBackspace: _backspace,
                    onBiometrics: lock.canUseBiometrics ? _biometrics : null,
                  ),
                  const SizedBox(height: 16),
                  if (!_forgotOpen)
                    TextButton(
                      key: const Key('lock-forgot'),
                      onPressed: () => setState(() => _forgotOpen = true),
                      child: const Text('Forgot PIN?'),
                    )
                  else ...[
                    Text(
                      'Signing out removes the lock on this phone. You will '
                      'need your account password to sign in again; nothing '
                      'in your account is changed.',
                      style: TextStyle(color: muted, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        OutlinedButton(
                          key: const Key('lock-forgot-cancel'),
                          onPressed: () => setState(() => _forgotOpen = false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          key: const Key('lock-forgot-confirm'),
                          onPressed: () => unawaited(
                            ref
                                .read(appLockProvider.notifier)
                                .forgetPinAndSignOut(),
                          ),
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({required this.count, required this.total});

  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: context.motion(const Duration(milliseconds: 120)),
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < count ? context.inkColor : Colors.transparent,
              border: Border.all(color: context.inkColor, width: 1.5),
            ),
          ),
      ],
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometrics,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometrics;

  @override
  Widget build(BuildContext context) {
    Widget key(Widget child, VoidCallback? onTap, {Key? widgetKey}) {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: SizedBox(
          height: 64,
          child: OutlinedButton(
            key: widgetKey,
            onPressed: enabled ? onTap : null,
            style: OutlinedButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              foregroundColor: context.inkColor,
              textStyle: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: child,
          ),
        ),
      );
    }

    Widget digit(String value) => Expanded(
      child: key(
        Text(value),
        () => onDigit(value),
        widgetKey: Key('lock-key-$value'),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(children: [for (final value in row) digit(value)]),
        Row(
          children: [
            Expanded(
              child: onBiometrics == null
                  ? const SizedBox.shrink()
                  : key(
                      const Icon(
                        Icons.fingerprint,
                        size: 30,
                        semanticLabel:
                            'Unlock with fingerprint, face or screen lock',
                      ),
                      onBiometrics,
                      widgetKey: const Key('lock-biometric'),
                    ),
            ),
            digit('0'),
            Expanded(
              child: key(
                const Icon(
                  Icons.backspace_outlined,
                  size: 26,
                  semanticLabel: 'Delete last digit',
                ),
                onBackspace,
                widgetKey: const Key('lock-backspace'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
