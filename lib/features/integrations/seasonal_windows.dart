import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hebcal/hebcal.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../alerts/alerts.dart';
import '../home/card_registry.dart';
import '../home/cards/card_frame.dart';

({DateTime start, DateTime end}) levanaWindow(HDate date, bool threeDays) {
  final molad = Molad(date.getFullYear(), date.getMonth());
  return (
    start: threeDays
        ? molad.getTchilasZmanKidushLevana3Days()
        : molad.getTchilasZmanKidushLevana7Days(),
    end: molad.getSofZmanKidushLevanaBetweenMoldos(),
  );
}

/// The Kiddush Levana window open at [t], or else the next to open.
({DateTime start, DateTime end}) levanaWindowAt(DateTime t, Location loc, {required bool useElevation, required bool threeDays}) {
  final hd = Zmanim.makeSunsetAwareHDate(loc, t.toUtc(), useElevation);
  final window = levanaWindow(hd, threeDays);
  if (t.isBefore(window.end)) return window;
  // Past the middle of the month: next month's.
  return levanaWindow(HDate(1, hd.getMonth(), hd.getFullYear()).addDays(30), threeDays);
}

/// Whether [window] is open on the Motzei Shabbat ending the week of
/// [day], when Kiddush Levana is said: between nightfall and midnight.
bool levanaOpenMotzeiShabbat(({DateTime start, DateTime end}) window, PlainDate day, Location loc, {required bool useElevation}) {
  final saturday = day.addDays(6 - day.dayOfWeek);
  final nightfall = Zmanim(loc, saturday, useElevation).tzeit(8.5);
  final sunday = saturday.addDays(1);
  final midnight = tz.TZDateTime(loc.tzLocation, sunday.year, sunday.month, sunday.day);
  return nightfall != null && window.start.isBefore(midnight) && window.end.isAfter(nightfall);
}

enum LevanaPhase {
  open,

  /// Not open yet, but open by Motzei Shabbat: shown from the Thursday
  /// before.
  soon,
  closed,
}

/// Kiddush Levana at [now], on the civil day [today]: the window open now
/// or the next, and its phase.
({LevanaPhase phase, DateTime start, DateTime end}) levanaStatus(
  DateTime now,
  PlainDate today,
  Location loc, {
  required bool useElevation,
  required bool threeDays,
}) {
  final w = levanaWindowAt(now, loc, useElevation: useElevation, threeDays: threeDays);
  final phase = !now.isBefore(w.start)
      ? LevanaPhase.open
      : today.dayOfWeek >= 4 && levanaOpenMotzeiShabbat(w, today, loc, useElevation: useElevation)
          ? LevanaPhase.soon
          : LevanaPhase.closed;
  return (phase: phase, start: w.start, end: w.end);
}

/// [omerCounted]: the Hebrew date (abs) of the night the Omer was last
/// marked counted, so that night's reminder is dropped.
List<PlannedNotification> planSeasonalReminders(
  AppSettings settings,
  DateTime now, {
  int days = 8,
  int? omerCounted,
}) {
  if (!settings.levanaReminder && !settings.levanaHeadsUp && !settings.hachamaReminder && !settings.omerReminder) return const [];
  final loc = settings.location.toLocation();
  // Start with the saved location’s civil day, even after sunset. Tonight’s
  // tzeit may still be ahead; its Hebrew date is derived separately below.
  final date = HDate.fromDate(tz.TZDateTime.from(now, loc.tzLocation));
  final out = <PlannedNotification>[];
  final tr = AppText(lang: settings.uiLanguage, ashkenazi: settings.ashkenaziSpelling, child: const SizedBox()).tr;
  for (var d = 0; d < days; d++) {
    final hd = date.addDays(d);
    final civil = hd.plainDate();
    final z = Zmanim(loc, civil, settings.useElevation);
    if (settings.levanaReminder) {
      // Tonight belongs to the following Hebrew date, including month rollover.
      final window = levanaWindow(
        hd.next(),
        settings.minhagim.kiddushLevana3Days,
      );
      final fire = z.tzeit(8.5);
      if (fire != null &&
          fire.isAfter(now) &&
          !fire.isBefore(window.start) &&
          fire.isBefore(window.end)) {
        out.add(
          PlannedNotification(
            notificationId('season:levana', civil),
            fire,
            tr('Kiddush Levana'),
            tr('The Kiddush Levana window is open tonight.'),
            'season:levana',
            route: '/pray/kiddushLevana',
          ),
        );
      }
    }
    if (settings.levanaHeadsUp && hd.getDay() == 4) {
      // Thursday morning, when the window isn't open yet but will be by
      // Motzei Shabbat, when it's said.
      final fire = tz.TZDateTime(loc.tzLocation, civil.year, civil.month, civil.day, 9);
      final window = levanaWindowAt(fire, loc, useElevation: settings.useElevation, threeDays: settings.minhagim.kiddushLevana3Days);
      if (fire.isAfter(now) &&
          fire.isBefore(window.start) &&
          levanaOpenMotzeiShabbat(window, civil, loc, useElevation: settings.useElevation)) {
        final opens = tz.TZDateTime.from(window.start, loc.tzLocation);
        out.add(
          PlannedNotification(
            notificationId('season:levanaSoon', civil),
            fire,
            tr('Kiddush Levana'),
            tr('Opens {day} at {time}, in time for Motzei Shabbat.', {
              'day': tr(weekdayNames[opens.weekday % 7]),
              'time': formatTime(window.start, loc, hour12: settings.hour12),
            }),
            'season:levanaSoon',
            route: '/pray/kiddushLevana',
          ),
        );
      }
    }
    if (settings.omerReminder) {
      // Tonight's count. Not on Shabbat or Yom Tov, when it is counted in
      // shul and a phone shouldn't ring.
      final tonight = hd.next();
      final day = omerDay(tonight);
      final rest = tonight.getDay() == 6 ||
          getHolidaysOnDate(tonight, settings.location.il).any((e) => e.hasFlag(Flags.chag));
      final fire = z.tzeit(8.5);
      if (day > 0 && !rest && tonight.abs() != omerCounted && fire != null && fire.isAfter(now)) {
        out.add(
          PlannedNotification(
            notificationId('season:omer', civil),
            fire,
            tr('Sefirat HaOmer'),
            tr('Tonight is day {n} of the Omer.', {'n': day}),
            'season:omer',
            route: '/pray/omer',
          ),
        );
      }
    }
    if (settings.hachamaReminder &&
        getHolidaysOnDate(
          hd,
          settings.location.il,
        ).any((e) => e.getDesc() == 'Birkat Hachamah')) {
      final fire = z.sunrise();
      if (fire != null && fire.isAfter(now)) {
        out.add(
          PlannedNotification(
            notificationId('season:hachama', civil),
            fire,
            tr('Birkat HaChama'),
            tr('The blessing of the sun is said this morning.'),
            'season:hachama',
            route: '/pray/birkatHaChama',
          ),
        );
      }
    }
  }
  return out;
}

void registerSeasonalCards(CardRegistry registry) {
  registry.register(
    CardType(
      type: 'levanaWindow',
      title: 'Kiddush Levana window',
      description: 'Earliest and latest time for the moon blessing',
      icon: Icons.nights_stay_outlined,
      defaultSpan: 2,
      defaults: const {'onlyWhenOpen': true},
      visible: (ref, cfg) => !cfg.setting<bool>('onlyWhenOpen', true) || levanaStatusOf(ref).phase != LevanaPhase.closed,
      shownWhen: (cfg) => cfg.setting<bool>('onlyWhenOpen', true) ? 'While open, or opening by Motzei Shabbat' : null,
      editor: (c, ref, cfg, onChanged) => SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(c.tr('While open, or opening by Motzei Shabbat')),
        subtitle: Text(c.tr('Otherwise always shown, with the next window')),
        value: cfg.setting<bool>('onlyWhenOpen', true),
        onChanged: (v) => onChanged(cfg.copyWith(settings: {...cfg.settings, 'onlyWhenOpen': v})),
      ),
      build: (_, _, _) => const _LevanaCard(),
    ),
  );
  registry.register(
    CardType(
      type: 'hachamaWindow',
      title: 'Birkat HaChama',
      description: 'The next blessing of the sun',
      icon: Icons.wb_sunny_outlined,
      build: (_, _, _) => const _HachamaCard(),
    ),
  );
}

/// Kiddush Levana now, at the saved location.
({LevanaPhase phase, DateTime start, DateTime end}) levanaStatusOf(WidgetRef ref) {
  final s = ref.watch(settingsProvider);
  return levanaStatus(
    ref.watch(nowProvider).value ?? DateTime.now(),
    ref.watch(todayProvider),
    ref.watch(locationProvider),
    useElevation: s.useElevation,
    threeDays: s.minhagim.kiddushLevana3Days,
  );
}

/// Open: in the theme's color, with its end. Not open yet but open by
/// Motzei Shabbat (from the Thursday before): amber, saying so. Closed
/// (when the card is set to always show): plain, with the next window.
class _LevanaCard extends ConsumerWidget {
  const _LevanaCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final loc = ref.watch(locationProvider);
    final status = levanaStatusOf(ref);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = SiddurColors.of(context);
    final open = status.phase == LevanaPhase.open;
    final soon = status.phase == LevanaPhase.soon;
    final ink = open ? scheme.onPrimaryContainer : scheme.onSurface;
    String when(DateTime t) =>
        '${formatPlainDate(PlainDate.fromDateTime(tz.TZDateTime.from(t, loc.tzLocation)), year: false)} · ${formatTime(t, loc, hour12: s.hour12)}';
    return CardFrame(
      title: 'Kiddush Levana window',
      icon: Icons.nights_stay_outlined,
      accent: open ? scheme.primaryContainer : (soon ? colors.chipToday : null),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: open ? scheme.primary : null,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: open ? scheme.primary : (soon ? colors.todayBar : scheme.outlineVariant), width: 1.5),
        ),
        child: Text(
          context.tr(open ? 'Open now' : (soon ? 'Not open yet' : 'Closed')),
          style: theme.textTheme.labelMedium?.copyWith(
            color: open ? scheme.onPrimary : (soon ? scheme.onSurface : scheme.onSurfaceVariant),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            open ? context.tr('Until {when}', {'when': when(status.end)}) : context.tr('Opens {when}', {'when': when(status.start)}),
            style: theme.textTheme.titleMedium?.copyWith(color: ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            open
                ? context.tr('Said at night, with the moon in view')
                : soon
                    ? context.tr('It will be open on Motzei Shabbat, until {when}', {'when': when(status.end)})
                    : context.tr('Until {when}', {'when': when(status.end)}),
            style: theme.textTheme.bodyMedium?.copyWith(color: ink),
          ),
          const SizedBox(height: 6),
          Text(
            s.minhagim.kiddushLevana3Days
                ? context.tr('From 3 days after the molad; until halfway between molads.')
                : context.tr('From 7 days after the molad; until halfway between molads.'),
            style: theme.textTheme.bodySmall?.copyWith(color: ink.withValues(alpha: 0.75)),
          ),
          TextButton(
            onPressed: () => context.push('/pray/kiddushLevana'),
            child: Text(context.tr('Read')),
          ),
        ],
      ),
    );
  }
}

class _HachamaCard extends ConsumerWidget {
  const _HachamaCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(halachicTodayProvider);
    final il = ref.watch(settingsProvider.select((s) => s.location.il));
    HolidayEvent? next;
    for (var y = today.getFullYear(); y <= today.getFullYear() + 28; y++) {
      for (final event in getHolidaysForYearArray(y, il)) {
        if (event.getDesc() == 'Birkat Hachamah' &&
            event.getDate().abs() >= today.abs() &&
            (!il || !event.hasFlag(Flags.chulOnly))) {
          next = event;
        }
      }
      if (next != null) break;
    }
    return CardFrame(
      title: 'Birkat HaChama',
      icon: Icons.wb_sunny_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(next?.getDate().render(context.hebcalLocale) ?? '—'),
          Text(context.tr('Recited in the morning, once every 28 years.')),
          TextButton(
            onPressed: () => context.push('/pray/birkatHaChama'),
            child: Text(context.tr('Read')),
          ),
        ],
      ),
    );
  }
}
