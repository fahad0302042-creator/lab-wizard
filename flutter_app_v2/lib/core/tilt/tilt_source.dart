import 'dart:async';

import 'package:flutter/services.dart';

/// Phone attitude, in degrees, as the liquid vessel sees it.
///
/// There is no sensor API in Flutter's SDK, so this is a thin wrapper over the
/// platform channel in `MainActivity` / `TiltStreamHandler`. It is deliberately
/// the only place in the app that knows the channel exists: everything else
/// watches [tiltProvider] and treats the reading as a plain value.
class TiltReading {
  const TiltReading({
    this.roll = 0,
    this.pitch = 0,
    this.flat = true,
    this.supported = true,
  });

  /// Rotation about the phone's long axis, degrees.
  final double roll;

  /// Rotation about the phone's short axis, degrees.
  final double pitch;

  /// Near enough to horizontal that a reading would be noise. The vessel
  /// settles rather than jitters.
  final bool flat;

  /// False on a device with no usable sensor — and in unit tests, where the
  /// channel does not exist. Everything still works: drag substitutes.
  final bool supported;

  /// The amount to tip the liquid by, clamped so a full twist does not turn a
  /// jar upside down. Roll drives most of it because that is how a phone is
  /// naturally rolled while reading.
  double get tipDegrees => (-roll).clamp(-42.0, 42.0);

  TiltReading lerpedTo(TiltReading other, double t) => TiltReading(
    roll: roll + (other.roll - roll) * t,
    pitch: pitch + (other.pitch - pitch) * t,
    flat: other.flat,
    supported: other.supported,
  );
}

/// Broadcasts [TiltReading]s for as long as at least one listener cares.
///
/// `lab_wizard/tilt` is an [EventChannel]; the Kotlin side registers the sensor
/// on listen and releases it on cancel, so this never keeps the sensor awake
/// for a screen that is not visible.
class TiltSource {
  TiltSource() {
    _controller = StreamController<TiltReading>.broadcast(
      onListen: _subscribe,
      onCancel: _unsubscribe,
    );
  }

  static const _channel = EventChannel('lab_wizard/tilt');

  late final StreamController<TiltReading> _controller;
  StreamSubscription<dynamic>? _subscription;

  /// True once the platform has answered. Until then the vessel assumes flat,
  /// which is the same thing it shows on a device with no sensor.
  TiltReading latest = const TiltReading();

  Stream<TiltReading> get stream => _controller.stream;

  void _subscribe() {
    _subscription ??= _channel.receiveBroadcastStream().listen(
      (event) {
        final map = (event as Map?) ?? const {};
        final reading = TiltReading(
          roll: (map['roll'] as num?)?.toDouble() ?? 0,
          pitch: (map['pitch'] as num?)?.toDouble() ?? 0,
          flat: map['flat'] as bool? ?? true,
          supported: map['supported'] as bool? ?? true,
        );
        latest = reading;
        if (!_controller.isClosed) _controller.add(reading);
      },
      // A missing channel (tests, desktop, a build where MainActivity was not
      // regenerated) must never take the UI down with it.
      onError: (Object _) {
        latest = const TiltReading(supported: false);
        if (!_controller.isClosed) _controller.add(latest);
      },
      cancelOnError: false,
    );
  }

  void _unsubscribe() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    _unsubscribe();
    _controller.close();
  }
}
