import 'dart:async';

import 'alerts.dart';
import 'notification_backend.dart';

/// Fallback used where OS-level scheduling isn't available (web, Linux,
/// Windows): fires notifications from in-process timers while the app
/// is running.
abstract class TimerNotificationBackend implements NotificationBackend {
  final _timers = <Timer>[];

  @override
  int get maxPending => 200;

  @override
  bool get firesWhenClosed => false;

  @override
  Future<void> replaceAll(List<PlannedNotification> plan, {bool exact = false}) async {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    final now = DateTime.now();
    for (final p in plan) {
      final delay = p.fireAt.difference(now);
      // Timers beyond ~24h are re-planned on the next refresh anyway.
      if (delay.isNegative || delay > const Duration(hours: 26)) continue;
      _timers.add(Timer(delay, () => showNow(p.title, p.body)));
    }
  }
}
