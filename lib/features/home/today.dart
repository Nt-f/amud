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

  /// Past sunset: the Hebrew date has advanced but the civil day hasn't.
  bool get afterSunset => !halachic.isSameDate(hdate);

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
      'afterSunset': afterSunset,
      'halachicDate': {
        'day': halachic.getDate(),
        'month': halachic.getMonth(),
        'monthName': halachic.getMonthName(),
        'year': halachic.getFullYear(),
        'en': halachic.render('en'),
        'he': halachic.renderGematriya(true),
      },
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

/// The next weekly parsha from [hd], in [locale]: this coming Shabbat's,
/// or, when that Shabbat reads for a holiday instead (Shabbat Chol
/// HaMoed, Shemini Atzeret), the first regular parsha after it, with the
/// Shabbat it's read on. The holiday itself shows among the day's holidays.
({String name, HDate shabbat, bool thisWeek}) upcomingParsha(HDate hd, bool il, String locale) {
  final first = hd.onOrAfter(6);
  var shabbat = first;
  for (var i = 0; i < 8; i++) {
    final p = getSedra(shabbat.getFullYear(), il).lookup(shabbat);
    if (!p.chag && p.parsha.isNotEmpty) return (name: renderParshaName(p.parsha, locale), shabbat: shabbat, thisWeek: i == 0);
    shabbat = shabbat.addDays(7);
  }
  final p = getSedra(first.getFullYear(), il).lookup(first);
  return (name: Locale.gettext(p.parsha.first, locale), shabbat: first, thisWeek: true);
}

final todaySnapshotProvider = Provider<TodaySnapshot>((ref) {
  final now = ref.watch(nowProvider).value ?? DateTime.now();
  final civil = ref.watch(todayProvider);
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
    parsha: upcomingParsha(hd, il, 'en').name,
    parshaHe: upcomingParsha(hd, il, 'he').name,
    omerTonight: omerDay(hd.next()),
    zmanim: zmanim,
    learning: learning,
    learningHe: learningHe,
  );
});
