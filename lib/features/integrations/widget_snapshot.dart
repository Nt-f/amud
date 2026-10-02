import 'package:hebcal/hebcal.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/day_start.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../home/today.dart';
import '../zmanim/zman_catalog.dart';

/// Portable, versioned data consumed by WidgetKit, Android and the watches.
/// Entries change at calendar/zman boundaries, so native surfaces can advance
/// even when Flutter is not running. An expired timeline is never shown as live.
Map<String, Object?> buildWidgetTimeline(
  AppSettings settings,
  ZmanResolver resolver,
  DateTime now, {
  int days = 8,
}) {
  final loc = settings.location.toLocation();
  final local = tz.TZDateTime.from(now, loc.tzLocation);
  final first = PlainDate(local.year, local.month, local.day);
  final untilDate = first.addDays(days);
  final until = tz.TZDateTime(
    loc.tzLocation,
    untilDate.year,
    untilDate.month,
    untilDate.day,
  );
  final keys = builtInZmanim
      .where((z) => z.defaultFor.contains(settings.opinion))
      .map((z) => z.key)
      .toList();
  final times = <(String, DateTime)>[];
  final boundaries = <int>{now.millisecondsSinceEpoch};
  for (var d = 0; d <= days; d++) {
    final date = first.addDays(d);
    final z = Zmanim(loc, date, settings.useElevation);
    // The day turns over at dawn (see dayAt), or at midnight where there's
    // none.
    final dayStart = dawnFor(z, settings.opinion) ??
        tz.TZDateTime(loc.tzLocation, date.year, date.month, date.day);
    if (dayStart.isAfter(now) && dayStart.isBefore(until)) {
      boundaries.add(dayStart.millisecondsSinceEpoch);
    }
    for (final key in keys) {
      final time = resolver.compute(key, z);
      if (time == null || !time.isAfter(now)) continue;
      times.add((key, time));
      if (time.isBefore(until)) boundaries.add(time.millisecondsSinceEpoch);
    }
    final sunset = z.sunset();
    if (sunset != null && sunset.isAfter(now) && sunset.isBefore(until)) {
      boundaries.add(sunset.millisecondsSinceEpoch);
    }
  }
  times.sort((a, b) => a.$2.compareTo(b.$2));
  final candles =
      calendar(
            CalOptions(
              start: HDate.fromAbs(first.abs),
              end: HDate.fromAbs(first.addDays(days + 10).abs),
              location: loc,
              il: settings.location.il,
              candlelighting: true,
              candleLightingMins: settings.candleLightingMins,
              havdalahMins: settings.havdalahMins,
              useElevation: settings.useElevation,
              noHolidays: true,
            ),
          )
          .whereType<TimedEvent>()
          .where((e) => e.hasFlag(Flags.lightCandles))
          .toList()
        ..sort((a, b) => a.eventTime.compareTo(b.eventTime));
  for (final event in candles) {
    if (event.eventTime.isAfter(now) && event.eventTime.isBefore(until)) {
      boundaries.add(event.eventTime.millisecondsSinceEpoch);
    }
  }
  final ordered = boundaries.toList()..sort();
  return {
    'version': 1,
    'generatedAt': now.millisecondsSinceEpoch,
    'validUntil': until.millisecondsSinceEpoch,
    'location': settings.location.name,
    'tzid': settings.location.tzid,
    'entries': [
      for (final stamp in ordered)
        (() {
          final instant = DateTime.fromMillisecondsSinceEpoch(
            stamp,
            isUtc: true,
          );
          final date = Zmanim.makeSunsetAwareHDate(
            loc,
            instant,
            settings.useElevation,
          );
          final prayerDay = dayAt(instant, loc, useElevation: settings.useElevation, opinion: settings.opinion).abs;
          final next = times.where((z) => z.$2.isAfter(instant)).firstOrNull;
          final candle = candles
              .where((e) => e.eventTime.isAfter(instant))
              .firstOrNull;
          final en = settings.uiLanguage == UiLanguage.en;
          return <String, Object?>{
            'at': stamp,
            'prayerDay': prayerDay,
            'hebrewDate': date.renderGematriya(true),
            'dateLabel': date.render(en ? 'en' : 'he-x-NoNikud'),
            'parsha': upcomingParsha(
              date,
              settings.location.il,
              en ? 'en' : 'he-x-NoNikud',
            ).name,
            'omer': omerDay(date),
            'nextZman': next == null
                ? ''
                : (en ? resolver.name(next.$1) : resolver.nameHe(next.$1)),
            'nextZmanAt': next?.$2.millisecondsSinceEpoch,
            'nextZmanTime': next == null
                ? ''
                : formatTime(next.$2, loc, hour12: settings.hour12),
            'candleLightingAt': candle?.eventTime.millisecondsSinceEpoch,
            'candleLighting': candle == null
                ? ''
                : '${candle.getDate().render(en ? 'en' : 'he-x-NoNikud')} · ${formatTime(candle.eventTime, loc, hour12: settings.hour12)}',
          };
        })(),
    ],
  };
}

Map<String, Object?>? activeWidgetEntry(
  Map<String, Object?> timeline,
  DateTime now,
) {
  final stamp = now.millisecondsSinceEpoch;
  if ((timeline['validUntil'] as num).toInt() <= stamp) return null;
  Map<String, Object?>? found;
  for (final value in timeline['entries'] as List) {
    final entry = (value as Map).cast<String, Object?>();
    if ((entry['at'] as num).toInt() > stamp) break;
    found = entry;
  }
  return found;
}
