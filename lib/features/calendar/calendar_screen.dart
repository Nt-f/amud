import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';

import '../../core/l10n.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';

final _monthProvider = StateProvider<(int, int)?>((ref) => null);
final _selectedProvider = StateProvider<PlainDate?>((ref) => null);

/// Full-screen calendar, opened from the Home calendar card.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: Text(context.tr('Calendar')), actions: [
          TextButton(onPressed: () => resetCalendar(ref), child: Text(context.tr('Today'))),
        ]),
        body: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 32), children: const [CalendarView()]),
      );
}

/// Returns the calendar to the current month and today.
void resetCalendar(WidgetRef ref) {
  ref.read(_monthProvider.notifier).state = null;
  ref.read(_selectedProvider.notifier).state = null;
}

/// Gregorian month grid annotated with Hebrew dates, holidays, parsha,
/// candle lighting and Omer (all from the Hebcal port), with the chosen
/// day's events below. Shared by the Home card and [CalendarScreen].
class CalendarView extends ConsumerWidget {
  /// Tighter cells for the Home card.
  final bool compact;
  const CalendarView({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(civilTodayProvider);
    final ym = ref.watch(_monthProvider) ?? (today.year, today.month);
    final selected = ref.watch(_selectedProvider) ?? today;
    final events = ref.watch(calendarMonthProvider(ym));
    final s = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final loc = ref.watch(locationProvider);

    final byAbs = <int, List<Event>>{};
    for (final e in events) {
      byAbs.putIfAbsent(e.getDate().abs(), () => []).add(e);
    }
    final first = PlainDate(ym.$1, ym.$2, 1);
    final days = daysInGregMonth(ym.$2, ym.$1);
    final lead = first.dayOfWeek;
    final h1 = HDate.fromAbs(first.abs);
    final h2 = HDate.fromAbs(first.abs + days - 1);
    final hebRange = h1.getMonth() == h2.getMonth()
        ? '${h1.getMonthName()} ${h1.getFullYear()}'
        : '${h1.getMonthName()}–${h2.getMonthName()} ${h2.getFullYear()}';
    void shift(int d) {
      var m = ym.$2 + d;
      var y = ym.$1;
      if (m < 1) {
        m = 12;
        y--;
      } else if (m > 12) {
        m = 1;
        y++;
      }
      ref.read(_monthProvider.notifier).state = (y, m);
    }

    final selEvents = byAbs[selected.abs] ?? const <Event>[];
    final selHd = HDate.fromAbs(selected.abs);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconButton(onPressed: () => shift(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Column(children: [
              Text(formatMonth(ym.$1, ym.$2), style: theme.textTheme.titleLarge),
              Text(hebRange, style: theme.textTheme.bodySmall),
            ]),
          ),
          IconButton(onPressed: () => shift(1), icon: const Icon(Icons.chevron_right)),
        ]),
        Row(children: [
          for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'Sh'])
            Expanded(child: Center(child: Text(d, style: theme.textTheme.labelSmall))),
        ]),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: compact ? 0.9 : 0.8,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox.shrink(),
            for (var d = 1; d <= days; d++)
              Builder(builder: (context) {
                final pd = PlainDate(ym.$1, ym.$2, d);
                final hd = HDate.fromAbs(pd.abs);
                final evs = byAbs[pd.abs] ?? const [];
                final holiday = evs.any((e) => e is HolidayEvent && !e.hasFlag(Flags.yomKippurKatan) && !e.hasFlag(Flags.behab));
                final chag = evs.any((e) => e.hasFlag(Flags.chag));
                final isSel = pd == selected;
                final isToday = pd == today;
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => ref.read(_selectedProvider.notifier).state = pd,
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSel ? theme.colorScheme.primaryContainer : (chag ? colors.todayFill : null),
                      borderRadius: BorderRadius.circular(10),
                      border: isToday ? Border.all(color: theme.colorScheme.primary, width: 1.5) : null,
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('$d', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: pd.dayOfWeek == 6 ? FontWeight.w700 : null)),
                      Text(gematriya(hd.getDate()).replaceAll(RegExp('[׳״]'), ''),
                          style: TextStyle(fontSize: 11, fontFamily: s.hebrewFont, color: theme.colorScheme.outline)),
                      if (holiday) Container(width: 5, height: 5, decoration: BoxDecoration(color: colors.todayBar, shape: BoxShape.circle)),
                    ]),
                  ),
                );
              }),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: compact ? 0 : null,
          color: compact ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5) : null,
          margin: compact ? EdgeInsets.zero : null,
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(formatPlainDate(selected), style: theme.textTheme.titleMedium),
              Text('${selHd.render(context.hebcalLocale)} · ${selHd.renderGematriya()}', style: theme.textTheme.bodyMedium),
              const Divider(),
              if (selEvents.isEmpty) Text(context.tr('No events')),
              for (final e in selEvents)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text(e.getEmoji() ?? '•', style: const TextStyle(fontSize: 18)),
                  title: Text(e is TimedEvent ? '${e.renderBrief(context.hebcalLocale)}: ${formatTime(e.eventTime, loc, hour12: s.hour12)}' : e.render(context.hebcalLocale)),
                  subtitle: Text(e.render('he-x-NoNikud'), textDirection: TextDirection.rtl),
                ),
            ]),
          ),
        ),
    ]);
  }
}
