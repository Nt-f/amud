import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'alerts.dart';
import 'notification_backend.dart';
import 'timer_backend.dart';

NotificationBackend createBackend() => _WebBackend();

/// Browser notifications; fire only while the app is open.
///
/// Shown through the service worker where there is one: installed PWAs
/// and mobile browsers reject `new Notification()`, and the worker handles
/// taps. Each alert is tagged with its id so two open windows show one
/// notification, not two.
class _WebBackend extends TimerNotificationBackend {
  bool _ready = false;

  @override
  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      web.window.navigator.serviceWorker.addEventListener(
        'message',
        ((web.MessageEvent e) {
          final data = e.data;
          if (data.isA<JSObject>() && (data as JSObject).getProperty<JSAny?>('type'.toJS).dartify() == 'notification-tap') {
            notificationTaps.value = DateTime.now();
          }
        }).toJS,
      );
    } catch (_) {}
  }

  @override
  Future<bool> requestPermission({bool exact = false}) async {
    final result = await web.Notification.requestPermission().toDart;
    return result.toDart == 'granted';
  }

  Future<void> _show(String title, String body, String tag) async {
    if (web.Notification.permission != 'granted') return;
    final options = web.NotificationOptions(body: body, tag: tag, icon: 'icons/Icon-192.png');
    try {
      final reg = await web.window.navigator.serviceWorker.getRegistration().toDart;
      if (reg != null) {
        await reg.showNotification(title, options).toDart;
        return;
      }
    } catch (_) {}
    try {
      final n = web.Notification(title, options);
      n.onclick = ((web.Event _) {
        notificationTaps.value = DateTime.now();
        n.close();
      }).toJS;
    } catch (_) {}
  }

  @override
  Future<void> showScheduled(PlannedNotification p) => _show(p.title, p.body, 'zman-${p.id}');

  @override
  Future<void> showNow(String title, String body) => _show(title, body, 'zman-test');
}
