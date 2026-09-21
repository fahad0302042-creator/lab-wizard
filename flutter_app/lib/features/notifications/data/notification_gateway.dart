import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/alerts.dart';

/// Thin seam over the platform notification plugin so the coordinator and
/// the tests never touch platform channels directly (NOTIFY-01).
abstract class NotificationGateway {
  /// Prepares the plugin. Safe to call repeatedly.
  Future<void> initialize();

  /// Asks the OS for permission (Android 13+). True when notifications may
  /// be shown.
  Future<bool> requestPermission();

  /// Whether the OS currently allows this app to notify.
  Future<bool> areEnabled();

  /// Shows a notification right now.
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required AlertChannel channel,
    String? payload,
  });

  /// Schedules a notification for later (or weekly when
  /// [PlannedReminder.weekly] is set).
  Future<void> schedule(PlannedReminder reminder);

  /// Drops every scheduled-but-not-yet-shown notification.
  Future<void> cancelPending();

  /// Ids of notifications waiting to fire.
  Future<Set<int>> pendingIds();

  /// Opens the system notification settings for the app.
  Future<void> openSettings();

  /// Payloads of notifications the user tapped (including the one that
  /// launched the app).
  Stream<String> get taps;
}

/// `flutter_local_notifications` implementation. Scheduled times are handed
/// over as UTC instants so no device time-zone lookup is needed; the weekly
/// summary therefore repeats at a fixed UTC offset until the next launch
/// re-plans it.
class LocalNotificationGateway implements NotificationGateway {
  LocalNotificationGateway({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<String>.broadcast();
  Future<void>? _initializing;

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) _taps.add(payload);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if ((launch?.didNotificationLaunchApp ?? false) &&
        payload != null &&
        payload.isNotEmpty) {
      _taps.add(payload);
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> requestPermission() async {
    await initialize();
    final android = _android;
    if (android == null) return true;
    return await android.requestNotificationsPermission() ?? true;
  }

  @override
  Future<bool> areEnabled() async {
    await initialize();
    final android = _android;
    if (android == null) return true;
    return await android.areNotificationsEnabled() ?? true;
  }

  NotificationDetails _details(AlertChannel channel, String body) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel == AlertChannel.summary
              ? Importance.defaultImportance
              : Importance.high,
          priority: channel == AlertChannel.summary
              ? Priority.defaultPriority
              : Priority.high,
          styleInformation: BigTextStyleInformation(body),
        ),
      );

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required AlertChannel channel,
    String? payload,
  }) async {
    await initialize();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _details(channel, body),
      payload: payload,
    );
  }

  @override
  Future<void> schedule(PlannedReminder reminder) async {
    await initialize();
    await _plugin.zonedSchedule(
      id: reminder.id,
      scheduledDate: tz.TZDateTime.from(reminder.at.toUtc(), tz.UTC),
      notificationDetails: _details(reminder.channel, reminder.body),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: reminder.title,
      body: reminder.body,
      payload: reminder.payload,
      matchDateTimeComponents: reminder.weekly
          ? DateTimeComponents.dayOfWeekAndTime
          : null,
    );
  }

  @override
  Future<void> cancelPending() async {
    await initialize();
    await _plugin.cancelAllPendingNotifications();
  }

  @override
  Future<Set<int>> pendingIds() async {
    await initialize();
    final pending = await _plugin.pendingNotificationRequests();
    return {for (final request in pending) request.id};
  }

  @override
  Future<void> openSettings() async {
    await initialize();
    await _plugin.openAppNotificationSettings();
  }
}

/// In-memory gateway for tests and for platforms without notifications.
class RecordingNotificationGateway implements NotificationGateway {
  RecordingNotificationGateway({this.permission = true, this.failWith});

  bool permission;
  Object? failWith;
  int initializeCalls = 0;
  int permissionRequests = 0;
  int settingsOpened = 0;
  final shown = <({int id, String title, String body, String? payload})>[];
  final scheduled = <PlannedReminder>[];
  final _taps = StreamController<String>.broadcast();

  void tap(String payload) => _taps.add(payload);

  void _maybeFail() {
    final error = failWith;
    if (error != null) throw error;
  }

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<void> initialize() async {
    initializeCalls++;
    _maybeFail();
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    _maybeFail();
    return permission;
  }

  @override
  Future<bool> areEnabled() async => permission;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required AlertChannel channel,
    String? payload,
  }) async {
    _maybeFail();
    shown.add((id: id, title: title, body: body, payload: payload));
  }

  @override
  Future<void> schedule(PlannedReminder reminder) async {
    _maybeFail();
    scheduled.add(reminder);
  }

  @override
  Future<void> cancelPending() async => scheduled.clear();

  @override
  Future<Set<int>> pendingIds() async => {
    for (final reminder in scheduled) reminder.id,
  };

  @override
  Future<void> openSettings() async => settingsOpened++;
}
