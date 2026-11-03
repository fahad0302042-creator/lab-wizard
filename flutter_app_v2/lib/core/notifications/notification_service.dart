import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Phone notifications, kept in one place.
///
/// The only thing the app sends today is a low-stock warning — and only when a
/// shelf crosses its own order level. An item with no level set never warns,
/// because "no level" means "nobody has said what low means yet", not "empty".
///
/// Failing to show a notification must never fail the action that caused it,
/// so every call here swallows its errors and reports success only when the
/// notification actually went out.
class NotificationService {
  NotificationService();

  static const _channelId = 'low_stock';
  static const _channelName = 'Low stock';
  static const _channelDescription =
      'Tells you when a reagent or apparatus reaches its order level.';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _channelCreated = false;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<void> init() async {
    if (!isSupported || _ready) return;
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (error) {
      debugPrint('notifications unavailable: $error');
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android {
    if (!_ready) return null;
    return _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
  }

  /// Asks the phone for permission. Android 13 and later show a dialog; older
  /// versions grant it silently. Returns whether notifications may be posted.
  Future<bool> requestPermission() async {
    await init();
    final android = _android;
    if (android == null) return false;
    try {
      final granted = await android.requestNotificationsPermission();
      return granted ?? true;
    } catch (error) {
      debugPrint('notification permission failed: $error');
      return false;
    }
  }

  Future<void> _ensureChannel() async {
    if (_channelCreated) return;
    final android = _android;
    if (android == null) return;
    try {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.defaultImportance,
        ),
      );
      _channelCreated = true;
    } catch (error) {
      debugPrint('notification channel failed: $error');
    }
  }

  /// Posts one notification. [tag] keeps related notices from stacking up: a
  /// second warning about the same item replaces the first.
  Future<bool> show({
    required String title,
    required String body,
    required int id,
  }) async {
    await init();
    if (_android == null) return false;
    await _ensureChannel();
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
      return true;
    } catch (error) {
      debugPrint('notification failed: $error');
      return false;
    }
  }
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);
