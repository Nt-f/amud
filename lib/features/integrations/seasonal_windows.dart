import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hebcal/hebcal.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
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

List<PlannedNotification> planSeasonalReminders(
  AppSettings settings,
  DateTime now, {
  int days = 8,
}) {
  if (!settings.levanaReminder && !settings.hachamaReminder) return const [];
  final loc = settings.location.toLocation();
  // Start with the saved location’s civil day, even after sunset. Tonight’s
  // tzeit may still be ahead; its Hebrew date is derived separately below.
  final date = HDate.fromDate(tz.TZDateTime.from(now, loc.tzLocation));
  final out = <PlannedNotification>[];
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
            'Kiddush Levana',
            'The Kiddush Levana window is open tonight.',
            'season:levana',
            route: '/pray/kiddushLevana',
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
            'Birkat HaChama',
            'The blessing of the sun is said this morning.',
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
      visible: (ref, cfg) => !cfg.setting<bool>('onlyWhenOpen', true) || levanaOpen(ref),
      shownWhen: (cfg) => cfg.setting<bool>('onlyWhenOpen', true) ? 'Only while the window is open' : null,
      editor: (c, ref, cfg, onChanged) => SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(c.tr('Only while the window is open')),
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

/// Whether Kiddush Levana may be said now.
bool levanaOpen(WidgetRef ref) {
  final s = ref.watch(settingsProvider);
  final now = ref.watch(nowProvider).value ?? DateTime.now();
  final window = levanaWindow(ref.watch(halachicTodayProvider), s.minhagim.kiddushLevana3Days);
  return !now.isBefore(window.start) && now.isBefore(window.end);
}

class _LevanaCard extends ConsumerWidget {
  const _LevanaCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final date = ref.watch(halachicTodayProvider);
    final window = levanaWindow(date, s.minhagim.kiddushLevana3Days);
    final loc = ref.watch(locationProvider);
    final open = !now.isBefore(window.start) && now.isBefore(window.end);
    return CardFrame(
      title: 'Kiddush Levana window',
      icon: Icons.nights_stay_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
              open ? 'Window open · recite at night' : 'Window closed',
            ),
          ),
          Text(
            '${HDate.fromDate(tz.TZDateTime.from(window.start, loc.tzLocation)).render('en')} · ${formatTime(window.start, loc, hour12: s.hour12)}',
          ),
          Text(
            'Until ${HDate.fromDate(tz.TZDateTime.from(window.end, loc.tzLocation)).render('en')} · ${formatTime(window.end, loc, hour12: s.hour12)}',
          ),
          Text(
            context.tr(
              s.minhagim.kiddushLevana3Days
                  ? 'From 3 days after the molad; until halfway between molads.'
                  : 'From 7 days after the molad; until halfway between molads.',
            ),
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
          Text(next?.getDate().render('en') ?? '—'),
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
