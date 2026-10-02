import 'dart:async';

import 'alerts.dart';
import 'notification_backend.dart';

/// Fallback used where OS-level scheduling isn't available (web, Linux,
/// Windows): fires notifications while the app is running.
///
/// Instead of one long timer per notification (which drift, and stop
/// counting while the device sleeps), a short ticker compares the wall
/// clock against the plan, so alerts fire on time after a sleep or a
/// throttled background tab.
abstract class TimerNotificationBackend implements NotificationBackend {
  List<PlannedNotification> _plan = const [];
  final _fired = <int>{};
  Timer? _ticker;

  /// Notifications more than this late (app was closed) are skipped.
  static const _grace = Duration(minutes: 10);

  @override
  int get maxPending => 200;

  @override
  bool get firesWhenClosed => false;

  /// Called by the ticker after the plan runs out, to plan further ahead.
  void Function()? onPlanExhausted;

  @override
  Future<void> replaceAll(List<PlannedNotification> plan, {bool exact = false}) async {
    _plan = List.of(plan);
    final now = DateTime.now();
    // Forget ids that are no longer upcoming (keeps the set small).
    _fired.removeWhere((id) => !_plan.any((p) => p.id == id));
    for (final p in _plan) {
      if (!p.fireAt.isAfter(now)) _fired.add(p.id);
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 15), (_) => _tick());
  }

  void _tick() {
    final now = DateTime.now();
    for (final p in _plan) {
      if (_fired.contains(p.id) || p.fireAt.isAfter(now)) continue;
      _fired.add(p.id);
      if (now.difference(p.fireAt) <= _grace) showScheduled(p);
    }
    if (_plan.isNotEmpty && _plan.every((p) => _fired.contains(p.id))) {
      _plan = const [];
      onPlanExhausted?.call();
    }
  }

  /// Shows a planned notification; platforms may tag it by id.
  Future<void> showScheduled(PlannedNotification p) => showNow(p.title, p.body, route: p.route);
}
