import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tilt_source.dart';

/// The live phone attitude.
///
/// One stream for the whole app. Vessels all watch this single source, so a
/// screen full of rows costs one sensor subscription and one platform channel,
/// not one per row — each row's painter still repaints, but the sensor work,
/// the Kotlin filter and the channel traffic are paid once.
///
/// Riverpod keeps the provider alive while anything is listening and disposes
/// it when the last vessel goes away, which stops the sensor with it.
final tiltSourceProvider = Provider<TiltSource>((ref) {
  final source = TiltSource();
  ref.onDispose(source.dispose);
  return source;
});

/// The latest reading as a value. Starts flat and unsupported until the
/// platform answers, so nothing has to null-check a sensor that may not exist.
final tiltProvider = StreamProvider<TiltReading>((ref) {
  return ref.watch(tiltSourceProvider).stream;
});
