import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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

  /// The daily nudge. Separate from [_channelId] so it can be silenced without
  /// silencing the immediate low-stock warnings.
  static const _reminderChannelId = 'low_stock_daily';
  static const _dailyId = 90001;

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
      tzdata.initializeTimeZones();
      // A fixed local location is enough for a daily reminder and needs no
      // extra plugin: the phone's own offset is read at scheduling time.
      tz.setLocalLocation(tz.getLocation('Etc/GMT'));
    } catch (error) {
      debugPrint('time zone setup failed: $error');
    }
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
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _reminderChannelId,
          'Daily check',
          description:
              'One quiet reminder a day when something is below its order '
              'level.',
          importance: Importance.low,
        ),
      );
      _channelCreated = true;
    } catch (error) {
      debugPrint('notification channel failed: $error');
    }
  }

  /// Schedules the daily check for [hour]:00 local time.
  ///
  /// Inexact on purpose: an exact alarm needs a special Android permission and
  /// a stock check is not worth waking the phone for. The time is computed in
  /// UTC from the device's current offset, which is right for the year round in
  /// places without daylight saving and drifts by an hour where there is one —
  /// acceptable for a reminder, and noted here rather than hidden.
  Future<bool> scheduleDailyReminder({
    required int hour,
    required String title,
    required String body,
  }) async {
    await init();
    if (_android == null) return false;
    await _ensureChannel();
    try {
      await _plugin.zonedSchedule(
        _dailyId,
        title,
        body,
        _nextInstanceOf(hour),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _reminderChannelId,
            'Daily check',
            channelDescription:
                'One quiet reminder a day when something is below its order '
                'level.',
            importance: Importance.low,
            priority: Priority.low,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'daily',
      );
      return true;
    } catch (error) {
      debugPrint('daily reminder failed: $error');
      return false;
    }
  }

  Future<void> cancelDailyReminder() async {
    await init();
    if (_android == null) return;
    try {
      await _plugin.cancel(_dailyId);
    } catch (error) {
      debugPrint('could not cancel daily reminder: $error');
    }
  }

  /// The next [hour]:00 on the phone's clock, expressed as the UTC instant it
  /// actually is. Building it from the device's local wall clock is what makes
  /// the reminder land at breakfast rather than at 9am UTC.
  tz.TZDateTime _nextInstanceOf(int hour) {
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, hour);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return tz.TZDateTime.from(next.toUtc(), tz.local);
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
