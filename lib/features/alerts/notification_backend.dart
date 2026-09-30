import 'package:flutter/foundation.dart';

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

  Future<void> showNow(String title, String body);
}

NotificationBackend createNotificationBackend() => createBackend();

/// Set when the user taps a zman notification; the app opens Zmanim.
final notificationTaps = ValueNotifier<DateTime?>(null);
