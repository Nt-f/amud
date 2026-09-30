import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'notification_backend.dart';
import 'timer_backend.dart';

NotificationBackend createBackend() => _WebBackend();

/// Browser Notification API; fires only while the tab is open.
class _WebBackend extends TimerNotificationBackend {
  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission({bool exact = false}) async {
    final result = await web.Notification.requestPermission().toDart;
    return result.toDart == 'granted';
  }

  @override
  Future<void> showNow(String title, String body) async {
    if (web.Notification.permission != 'granted') return;
    web.Notification(title, web.NotificationOptions(body: body));
  }
}
