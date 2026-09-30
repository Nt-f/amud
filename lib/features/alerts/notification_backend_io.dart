import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'alerts.dart';
import 'notification_backend.dart';
import 'timer_backend.dart';

NotificationBackend createBackend() {
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) return _NativeBackend();
  return _DesktopTimerBackend();
}

const _channel = AndroidNotificationDetails(
  'zmanim',
  'Zmanim alerts',
  channelDescription: 'Reminders before or after halachic times',
  importance: Importance.high,
  priority: Priority.high,
  category: AndroidNotificationCategory.reminder,
);
const _details = NotificationDetails(
  android: _channel,
  iOS: DarwinNotificationDetails(interruptionLevel: InterruptionLevel.timeSensitive),
  macOS: DarwinNotificationDetails(),
);

/// OS-scheduled notifications (fire even when the app is closed).
class _NativeBackend implements NotificationBackend {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  @override
  int get maxPending => Platform.isIOS || Platform.isMacOS ? 60 : 120;

  @override
  bool get firesWhenClosed => true;

  @override
  Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ), onDidReceiveNotificationResponse: (_) => notificationTaps.value = DateTime.now());
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) notificationTaps.value = DateTime.now();
    _ready = true;
  }

  @override
  Future<bool> requestPermission({bool exact = false}) async {
    await init();
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission() ?? false;
      if (exact) await android?.requestExactAlarmsPermission();
      return granted;
    }
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, sound: true) ??
          false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, sound: true) ??
        false;
  }

  @override
  Future<void> replaceAll(List<PlannedNotification> plan, {bool exact = false}) async {
    await init();
    // Ids are stable per alert and day: scheduling an id again replaces
    // it, so only notifications no longer in the plan are cancelled.
    final keep = {for (final p in plan) p.id};
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id >= 1000 && !keep.contains(p.id)) await _plugin.cancel(p.id);
    }
    var mode = exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
    if (Platform.isAndroid && exact) {
      final can = await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.canScheduleExactNotifications();
      if (can != true) mode = AndroidScheduleMode.inexactAllowWhileIdle;
    }
    for (final p in plan) {
      try {
        await _plugin.zonedSchedule(
          p.id,
          p.title,
          p.body,
          tz.TZDateTime.from(p.fireAt, tz.UTC),
          _details,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          payload: p.alertId,
        );
      } catch (e) {
        debugPrint('schedule ${p.id} failed: $e');
      }
    }
  }

  @override
  Future<void> showNow(String title, String body) async {
    await init();
    await _plugin.show(999, title, body, _details);
  }
}

/// Linux/Windows: notifications fire while the app runs.
class _DesktopTimerBackend extends TimerNotificationBackend {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  @override
  Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(const InitializationSettings(
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
      ), onDidReceiveNotificationResponse: (_) => notificationTaps.value = DateTime.now());
    } catch (_) {}
    _ready = true;
  }

  @override
  Future<bool> requestPermission({bool exact = false}) async => true;

  @override
  Future<void> showScheduled(PlannedNotification p) async {
    await init();
    try {
      await _plugin.show(p.id, p.title, p.body, const NotificationDetails(linux: LinuxNotificationDetails()));
    } catch (e) {
      debugPrint('notify failed: $e');
    }
  }

  @override
  Future<void> showNow(String title, String body) async {
    await init();
    try {
      await _plugin.show(999, title, body, const NotificationDetails(linux: LinuxNotificationDetails()));
    } catch (e) {
      debugPrint('notify failed: $e');
    }
  }
}
