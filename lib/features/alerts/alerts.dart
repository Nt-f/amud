import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/providers.dart';
import '../../core/settings.dart';
import '../zmanim/zman_catalog.dart';
import 'notification_backend.dart';
import 'timer_backend.dart';

/// A user-configured notification tied to a zman.
class ZmanAlert {
  final String id;
  final String title;
  final String zmanKey;

  /// Minutes relative to the zman: negative = before ("pre-notify"),
  /// positive = after ("post-notify").
  final int offsetMinutes;

  /// Condition expression (see DayContext.variableDocs) evaluated against
  /// the civil day of the zman, e.g. `!shabbat && !yomTov`, `erevShabbat`,
  /// `omer`, `dow in [1, 4]`.
  final String when;
  final bool enabled;

  const ZmanAlert({
    required this.id,
    required this.title,
    required this.zmanKey,
    this.offsetMinutes = 0,
    this.when = 'true',
    this.enabled = true,
  });

  ZmanAlert copyWith({String? title, String? zmanKey, int? offsetMinutes, String? when, bool? enabled}) => ZmanAlert(
        id: id,
        title: title ?? this.title,
        zmanKey: zmanKey ?? this.zmanKey,
        offsetMinutes: offsetMinutes ?? this.offsetMinutes,
        when: when ?? this.when,
        enabled: enabled ?? this.enabled,
      );

  String describeOffset() {
    if (offsetMinutes == 0) return 'at the time';
    final m = offsetMinutes.abs();
    return '$m min ${offsetMinutes < 0 ? 'before' : 'after'}';
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'zmanKey': zmanKey,
        'offsetMinutes': offsetMinutes,
        'when': when,
        'enabled': enabled,
      };

  factory ZmanAlert.fromJson(Map<String, Object?> j) => ZmanAlert(
        id: j['id'] as String,
        title: j['title'] as String,
        zmanKey: j['zmanKey'] as String,
        offsetMinutes: (j['offsetMinutes'] as num?)?.toInt() ?? 0,
        when: (j['when'] as String?) ?? 'true',
        enabled: j['enabled'] != false,
      );
}

/// A concrete notification instance.
class PlannedNotification {
  final int id;
  final DateTime fireAt;
  final String title;
  final String body;
  final String alertId;
  const PlannedNotification(this.id, this.fireAt, this.title, this.body, this.alertId);
}

/// Pure planning logic: expands alerts into notifications for the coming
/// days. iOS allows at most 64 pending notifications, so the plan is
/// capped and refreshed whenever the app starts or resumes.
List<PlannedNotification> planNotifications({
  required List<ZmanAlert> alerts,
  required Location location,
  required ZmanResolver zmanim,
  required AppSettings settings,
  required DateTime now,
  int days = 8,
  int max = 60,
}) {
  final out = <PlannedNotification>[];
  final local = tz.TZDateTime.from(now, location.tzLocation);
  final start = PlainDate(local.year, local.month, local.day);
  for (var d = 0; d < days; d++) {
    final date = start.addDays(d);
    final z = Zmanim(location, date, settings.useElevation);
    final ctx = DayContext(HDate.fromAbs(date.abs), il: settings.location.il, service: Service.other, minhagim: settings.minhagim);
    for (final a in alerts) {
      if (!a.enabled) continue;
      bool ok;
      try {
        ok = Condition.parse(a.when.trim().isEmpty ? 'true' : a.when).eval(ctx.env);
      } catch (_) {
        ok = false;
      }
      if (!ok) continue;
      final t = zmanim.compute(a.zmanKey, z);
      if (t == null) continue;
      final fire = t.add(Duration(minutes: a.offsetMinutes));
      if (!fire.isAfter(now)) continue;
      final timeStr = _fmt(tz.TZDateTime.from(t, location.tzLocation), settings.hour12 ?? location.getCountryCode() == 'US');
      final name = zmanim.name(a.zmanKey);
      final body = a.offsetMinutes == 0
          ? '$name now ($timeStr)'
          : a.offsetMinutes < 0
              ? '$name in ${-a.offsetMinutes} min ($timeStr)'
              : '$name was ${a.offsetMinutes} min ago ($timeStr)';
      out.add(PlannedNotification(notificationId(a.id, date), fire, a.title, body, a.id));
    }
  }
  out.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  // Two alerts that would say the same thing at the same minute are one
  // notification.
  final seen = <String>{};
  final unique = [
    for (final p in out)
      if (seen.add('${p.fireAt.millisecondsSinceEpoch ~/ 60000}|${p.title}|${p.body}')) p,
  ];
  return unique.take(max).toList();
}

/// A stable id per alert and day, so re-planning replaces a scheduled
/// notification instead of adding a second copy (ids below 1000 are
/// reserved for test notifications).
int notificationId(String alertId, PlainDate date) {
  var h = 0x811c9dc5;
  for (final c in '$alertId@${date.abs}'.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return 1000 + h % 0x7ffff000;
}

String _fmt(DateTime t, bool h12) {
  final m = t.minute.toString().padLeft(2, '0');
  if (!h12) return '${t.hour.toString().padLeft(2, '0')}:$m';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

class AlertsNotifier extends Notifier<List<ZmanAlert>> {
  @override
  List<ZmanAlert> build() =>
      ref.watch(storageProvider).readJson(
          'alerts', (j) => [for (final e in (j as List).cast<Map>()) ZmanAlert.fromJson(e.cast<String, Object?>())]) ??
      const [];

  void _save(List<ZmanAlert> list) {
    state = list;
    ref.read(storageProvider).writeJson('alerts', [for (final a in list) a.toJson()]);
  }

  void upsert(ZmanAlert a) {
    final i = state.indexWhere((e) => e.id == a.id);
    _save(i < 0 ? [...state, a] : [...state]..[i] = a);
  }

  void remove(String id) => _save(state.where((e) => e.id != id).toList());
}

final alertsProvider = NotifierProvider<AlertsNotifier, List<ZmanAlert>>(AlertsNotifier.new);

final notificationBackendProvider = Provider<NotificationBackend>((ref) => createNotificationBackend());

/// Keeps the platform's pending notifications in sync with alerts,
/// location and settings.
class AlertScheduler {
  final Ref ref;
  AlertScheduler(this.ref);

  Future<int>? _running;
  bool _again = false;

  /// Re-plans notifications. Calls made while a pass is running are
  /// coalesced into one follow-up pass, so passes never interleave.
  Future<int> reschedule() async {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    try {
      int n;
      do {
        _again = false;
        _running = _pass();
        n = await _running!;
      } while (_again);
      return n;
    } finally {
      _running = null;
    }
  }

  Future<int> _pass() async {
    final backend = ref.read(notificationBackendProvider);
    await backend.init();
    if (backend is TimerNotificationBackend) backend.onPlanExhausted = reschedule;
    final settings = ref.read(settingsProvider);
    final plan = planNotifications(
      alerts: ref.read(alertsProvider),
      location: ref.read(locationProvider),
      zmanim: ref.read(zmanResolverProvider),
      settings: settings,
      now: DateTime.now(),
      max: backend.maxPending,
    );
    try {
      await backend.replaceAll(plan, exact: settings.exactAlarms);
    } catch (e, st) {
      debugPrint('Notification scheduling failed: $e\n$st');
    }
    return plan.length;
  }
}

final alertSchedulerProvider = Provider<AlertScheduler>((ref) {
  final s = AlertScheduler(ref);
  // Long-running sessions (desktop, an open browser tab) plan ahead again
  // as days pass.
  final timer = Timer.periodic(const Duration(hours: 6), (_) => s.reschedule());
  ref.onDispose(timer.cancel);
  // Re-plan whenever inputs change.
  ref.listen(alertsProvider, (_, _) => s.reschedule());
  ref.listen(customZmanimProvider, (_, _) => s.reschedule());
  ref.listen(settingsProvider.select((x) => (x.location, x.useElevation, x.exactAlarms, x.minhagim)), (_, _) => s.reschedule());
  return s;
});
