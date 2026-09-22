/// App lock model (SECURITY-01): PIN hashing, lock settings and the
/// wrong-attempt throttle. Pure Dart so it is unit-testable without plugins.
///
/// Honest scope: the lock only gates the app's screens on this phone. The
/// PIN never leaves the device, is stored as a salted PBKDF2 hash in the
/// platform secure storage, and neither the local SQLite copy nor the rows in
/// Supabase are encrypted by it.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Allowed PIN lengths.
const pinMinLength = 4;
const pinMaxLength = 8;

/// PBKDF2 rounds for new PINs on a phone. Stored with the hash so it can be
/// raised later without invalidating existing PINs.
const pinDefaultIterations = 30000;

/// Consecutive wrong PINs before a cool-down starts.
const lockMaxFailures = 5;

/// First cool-down; it doubles with every further wrong PIN.
const lockFirstCooldown = Duration(seconds: 30);

/// Longest cool-down.
const lockMaxCooldown = Duration(minutes: 10);

final _digits = RegExp(r'^\d+$');

/// Null when [pin] is acceptable, otherwise the reason it is not.
String? validatePin(String pin) {
  if (pin.length < pinMinLength || pin.length > pinMaxLength) {
    return 'Use $pinMinLength to $pinMaxLength digits.';
  }
  if (!_digits.hasMatch(pin)) return 'Digits only.';
  if (pin.split('').toSet().length == 1) {
    return 'Choose a PIN that is not all the same digit.';
  }
  return null;
}

/// PBKDF2-HMAC-SHA256 (RFC 8018) over [password] with [salt].
Uint8List pbkdf2Sha256(
  List<int> password,
  List<int> salt,
  int iterations, {
  int length = 32,
}) {
  if (iterations < 1) throw ArgumentError.value(iterations, 'iterations');
  final hmac = Hmac(sha256, password);
  final blocks = (length / 32).ceil();
  final out = <int>[];
  for (var block = 1; block <= blocks; block++) {
    var u = hmac.convert([
      ...salt,
      (block >> 24) & 0xff,
      (block >> 16) & 0xff,
      (block >> 8) & 0xff,
      block & 0xff,
    ]).bytes;
    final t = List<int>.of(u);
    for (var round = 1; round < iterations; round++) {
      u = hmac.convert(u).bytes;
      for (var i = 0; i < t.length; i++) {
        t[i] ^= u[i];
      }
    }
    out.addAll(t);
  }
  return Uint8List.fromList(out.sublist(0, length));
}

/// Constant-time byte comparison so a wrong PIN takes as long as a right one.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// A salted, stretched PIN hash. Only the hash is persisted; [length] lets
/// the lock screen submit automatically once enough digits were typed.
class PinHash {
  const PinHash({
    required this.salt,
    required this.hash,
    required this.iterations,
    required this.length,
  });

  factory PinHash.create(
    String pin, {
    int iterations = pinDefaultIterations,
    Random? random,
  }) {
    final rng = random ?? Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => rng.nextInt(256)),
    );
    return PinHash(
      salt: salt,
      hash: pbkdf2Sha256(utf8.encode(pin), salt, iterations),
      iterations: iterations,
      length: pin.length,
    );
  }

  factory PinHash.fromJson(Map<String, dynamic> json) => PinHash(
    salt: base64Decode(json['salt'] as String),
    hash: base64Decode(json['hash'] as String),
    iterations: json['iterations'] as int,
    length: json['length'] as int,
  );

  final Uint8List salt;
  final Uint8List hash;
  final int iterations;
  final int length;

  bool verify(String pin) => constantTimeEquals(
    hash,
    pbkdf2Sha256(utf8.encode(pin), salt, iterations, length: hash.length),
  );

  Map<String, dynamic> toJson() => {
    'salt': base64Encode(salt),
    'hash': base64Encode(hash),
    'iterations': iterations,
    'length': length,
  };
}

/// How long the app may stay in the background before it locks again.
enum LockTimeout {
  immediately(Duration.zero, 'Immediately'),
  oneMinute(Duration(minutes: 1), 'After 1 minute'),
  fiveMinutes(Duration(minutes: 5), 'After 5 minutes'),
  fifteenMinutes(Duration(minutes: 15), 'After 15 minutes');

  const LockTimeout(this.duration, this.label);

  final Duration duration;
  final String label;

  static LockTimeout parse(String? name) => LockTimeout.values.firstWhere(
    (value) => value.name == name,
    orElse: () => LockTimeout.immediately,
  );
}

/// Persisted preferences of the lock (the PIN hash is stored separately).
class AppLockSettings {
  const AppLockSettings({
    this.enabled = false,
    this.biometrics = true,
    this.timeout = LockTimeout.immediately,
  });

  factory AppLockSettings.fromJson(Map<String, dynamic> json) =>
      AppLockSettings(
        enabled: json['enabled'] == true,
        biometrics: json['biometrics'] != false,
        timeout: LockTimeout.parse(json['timeout'] as String?),
      );

  final bool enabled;

  /// Offer fingerprint/face/phone screen lock as an alternative to the PIN.
  final bool biometrics;
  final LockTimeout timeout;

  AppLockSettings copyWith({
    bool? enabled,
    bool? biometrics,
    LockTimeout? timeout,
  }) => AppLockSettings(
    enabled: enabled ?? this.enabled,
    biometrics: biometrics ?? this.biometrics,
    timeout: timeout ?? this.timeout,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'biometrics': biometrics,
    'timeout': timeout.name,
  };
}

/// Wrong-PIN bookkeeping. Persisted so restarting the app does not reset a
/// running cool-down.
class LockThrottle {
  const LockThrottle({this.failures = 0, this.lockedUntil});

  factory LockThrottle.fromJson(Map<String, dynamic> json) => LockThrottle(
    failures: (json['failures'] as num?)?.toInt() ?? 0,
    lockedUntil: DateTime.tryParse(json['lockedUntil'] as String? ?? ''),
  );

  static const none = LockThrottle();

  final int failures;
  final DateTime? lockedUntil;

  /// Time left in the cool-down, or zero when a PIN may be tried.
  Duration remaining(DateTime now) {
    final until = lockedUntil;
    if (until == null || !until.isAfter(now)) return Duration.zero;
    return until.difference(now);
  }

  bool isThrottled(DateTime now) => remaining(now) > Duration.zero;

  /// The state after one more wrong PIN at [now].
  LockThrottle afterFailure(DateTime now) {
    final count = failures + 1;
    if (count < lockMaxFailures) return LockThrottle(failures: count);
    final steps = count - lockMaxFailures;
    var cooldown = lockFirstCooldown;
    for (var i = 0; i < steps && cooldown < lockMaxCooldown; i++) {
      cooldown *= 2;
    }
    if (cooldown > lockMaxCooldown) cooldown = lockMaxCooldown;
    return LockThrottle(failures: count, lockedUntil: now.add(cooldown));
  }

  Map<String, dynamic> toJson() => {
    'failures': failures,
    'lockedUntil': lockedUntil?.toUtc().toIso8601String(),
  };
}

/// Words for a cool-down, e.g. "Try again in 28 s" or "in 2 min".
String cooldownLabel(Duration remaining) {
  if (remaining.inMinutes >= 1) {
    final minutes = (remaining.inSeconds / 60).ceil();
    return 'Try again in $minutes min';
  }
  return 'Try again in ${remaining.inSeconds.clamp(1, 59)} s';
}
