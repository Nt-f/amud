import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/providers.dart';
import '../../core/settings.dart';
import '../zmanim/zman_catalog.dart';

/// A snapshot of "today" shared by home cards and exposed to JS cards.
class TodaySnapshot {
  final DateTime now;
  final PlainDate civil;
  final HDate hdate;
  final HDate halachic;
  final Location location;
  final DayContext day;
  final List<HolidayEvent> holidays;
  final String? parsha;
  final String? parshaHe;
  final int omerTonight;
  final Map<String, DateTime?> zmanim;
  final Map<String, String> learning;
  final Map<String, String> learningHe;

  TodaySnapshot({
    required this.now,
    required this.civil,
    required this.hdate,
    required this.halachic,
    required this.location,
    required this.day,
    required this.holidays,
    required this.parsha,
    required this.parshaHe,
    required this.omerTonight,
    required this.zmanim,
    required this.learning,
    required this.learningHe,
  });

  tz.TZDateTime local(DateTime t) => tz.TZDateTime.from(t, location.tzLocation);

  /// The next upcoming zman among [keys].
  (String, DateTime)? nextZman(Iterable<String> keys) {
    (String, DateTime)? best;
    for (final k in keys) {
      final t = zmanim[k];
      if (t == null || !t.isAfter(now)) continue;
      if (best == null || t.isBefore(best.$2)) best = (k, t);
    }
    return best;
  }

  /// JSON passed to JS cards as `ctx`.
  Map<String, Object?> toJsContext(ZmanResolver names) {
    String hm(DateTime? t) {
      if (t == null) return '';
      final l = local(t);
      return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    }

    return {
      'now': now.toUtc().toIso8601String(),
      'gregorian': civil.toString(),
      'hebrewDate': {
        'day': hdate.getDate(),
        'month': hdate.getMonth(),
        'monthName': hdate.getMonthName(),
        'year': hdate.getFullYear(),
        'en': hdate.render('en'),
        'he': hdate.renderGematriya(true),
        'heNikud': hdate.renderGematriya(),
      },
      'afterSunset': !halachic.isSameDate(hdate),
      'location': {
        'name': location.getName(),
        'latitude': location.latitude,
        'longitude': location.longitude,
        'elevation': location.elevation,
        'tzid': location.getTzid(),
        'il': location.getIsrael(),
      },
      'day': day.env,
      'holidays': [for (final h in holidays) {'en': h.render('en'), 'he': h.render('he-x-NoNikud'), 'emoji': h.getEmoji()}],
      'parsha': {'en': parsha, 'he': parshaHe},
      'omerTonight': omerTonight,
      'zmanim': {
        for (final e in zmanim.entries)
          e.key: {'time': hm(e.value), 'iso': e.value?.toUtc().toIso8601String(), 'name': names.name(e.key), 'he': names.nameHe(e.key)},
      },
      'learning': learning,
      'learningHe': learningHe,
    };
  }
}

final todaySnapshotProvider = Provider<TodaySnapshot>((ref) {
  final now = ref.watch(nowProvider).value ?? DateTime.now();
  final civil = ref.watch(civilTodayProvider);
  final settings = ref.watch(settingsProvider);
  final loc = ref.watch(locationProvider);
  final halachic = ref.watch(halachicTodayProvider);
  final hd = HDate.fromAbs(civil.abs);
  final z = ref.watch(zmanimProvider(civil));
  final resolver = ref.watch(zmanResolverProvider);
  final zmanim = <String, DateTime?>{
    for (final (k, _) in resolver.allKeys) k: resolver.compute(k, z),
  };
  final il = settings.location.il;
  final shabbat = hd.onOrAfter(6);
  final p = getSedra(shabbat.getFullYear(), il).lookup(shabbat);
  final learning = <String, String>{};
  final learningHe = <String, String>{};
  for (final name in settings.learningSchedules) {
    try {
      final ev = DailyLearning.lookup(name, hd, il);
      if (ev != null) {
        learning[name] = ev.render('en');
        learningHe[name] = ev.render('he');
      }
    } catch (_) {}
  }
  return TodaySnapshot(
    now: now,
    civil: civil,
    hdate: hd,
    halachic: halachic,
    location: loc,
    day: DayContext(hd, il: il, service: Service.other, minhagim: settings.minhagim),
    holidays: getHolidaysOnDate(hd, il).where((e) => !e.hasFlag(Flags.yomKippurKatan) && !e.hasFlag(Flags.behab)).toList(),
    parsha: p.chag ? p.parsha.first : renderParshaName(p.parsha, 'en'),
    parshaHe: p.chag ? Locale.gettext(p.parsha.first, 'he') : renderParshaName(p.parsha, 'he'),
    omerTonight: omerDay(hd.next()),
    zmanim: zmanim,
    learning: learning,
    learningHe: learningHe,
  );
});
