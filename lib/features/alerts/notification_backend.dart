import 'dart:async';


import 'alerts.dart';
import 'notification_backend_stub.dart'
    if (dart.library.io) 'notification_backend_io.dart'
    if (dart.library.js_interop) 'notification_backend_web.dart';

/// Platform notification scheduling.
abstract class NotificationBackend {
  /// Maximum pending notifications this platform tolerates.
  int get maxPending;

  /// Whether notifications fire while the app is closed.
  bool get firesWhenClosed;

  Future<void> init();

  /// Asks the user for permission. Returns true if granted.
  Future<bool> requestPermission({bool exact = false});

  /// Cancels previously scheduled notifications and schedules [plan].
  Future<void> replaceAll(List<PlannedNotification> plan, {bool exact = false});

  /// Shows a notification now; tapping it opens [route].
  Future<void> showNow(String title, String body, {String route = '/zmanim', int id = 999});
}

NotificationBackend createNotificationBackend() => createBackend();

/// Routes of tapped notifications (zman alerts open Zmanim, update
/// notices open the update page); the app navigates to each.
final notificationTaps = StreamController<String>.broadcast();

/// The route a notification payload stands for.
String routeForPayload(String? payload) => payload != null && payload.startsWith('/') ? payload : '/zmanim';
