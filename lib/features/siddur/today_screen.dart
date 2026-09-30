import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/adaptive.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/titles.dart';
import 'reader_screen.dart';
import 'siddur_providers.dart';
import 'today_plan.dart';

IconData serviceIcon(String key) => switch (key) {
      'shacharit' => Icons.wb_sunny_outlined,
      'musaf' => Icons.brightness_5_outlined,
      'mincha' => Icons.light_mode_outlined,
      'shabbatEve' => Icons.local_fire_department_outlined,
      'maariv' => Icons.nights_stay_outlined,
      _ => Icons.bedtime_outlined,
    };

/// The whole day's davening in order, section by section, with what's
/// added and what's left out today.
class TodayDaveningScreen extends ConsumerWidget {
  const TodayDaveningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(readerDaytimeDateProvider);
    final picked = ref.watch(readerDateProvider);
    final plan = ref.watch(todayPlanProvider(date.abs()));
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr("Today's davening")),
        actions: [
          IconButton(
            tooltip: context.tr('Date'),
            icon: Badge(isLabelVisible: picked != null, child: const Icon(Icons.event)),
            onPressed: () => pickReaderDate(context, ref, date),
          ),
        ],
      ),
      body: Column(children: [
        DayBanner(date: date, picked: picked != null),
        Expanded(
          child: plan.when(
            loading: adaptiveProgress,
            error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
            data: (p) => p == null
                ? Center(child: Text(context.tr('Not found in this siddur')))
                : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                    if (p.needsMachzor)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            leading: const Icon(Icons.info_outline),
                            title: Text(context.tr('The bundled siddurim have no machzor for Rosh Hashana and Yom Kippur. The order below is the regular Shabbat and Yom Tov one.')),
                          ),
                        ),
                      ),
                    for (final svc in p.services) _ServiceCard(plan: p, service: svc),
                  ]),
          ),
        ),
      ]),
    );
  }
}

class _ServiceCard extends ConsumerWidget {
  final TodayPlan plan;
  final PlanService service;
  const _ServiceCard({required this.plan, required this.service});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final whole = service.whole;
    // Reading straight through only helps when the service has parts.
    final canReadAll = whole != null && service.entries.length > 1;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              Icon(serviceIcon(service.key), size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                  Text(context.prayerTitle(s, service.en, service.he),
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700, fontFamily: context.prayerTitleIsHebrew(s) ? s.hebrewFont : null)),
                  if (service.tonight)
                    Text(context.tr('Tonight'), style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)),
                ]),
              ),
              if (canReadAll)
                TextButton(
                  onPressed: () => context.push(readerPath(whole.book, whole.id, standalone: true)),
                  child: Text(context.tr('Read all')),
                ),
            ]),
          ),
          for (final e in service.entries) _EntryTile(plan: plan, entry: e, own: service.key == 'shabbatEve' || service.key == 'night'),
          if (service.skipped.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                context.tr('Not said today: {list}', {'list': service.skipped.map((n) => context.prayerTitle(s, n.en, n.he)).join(' · ')}),
                style: theme.textTheme.bodySmall?.copyWith(color: colors.excluded),
              ),
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  final TodayPlan plan;
  final PlanEntry entry;

  /// In a group of its own (candles, bedtime), where "added today" says
  /// nothing.
  final bool own;
  const _EntryTile({required this.plan, required this.entry, this.own = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final otherBook = entry.book == plan.book ? null : ref.watch(bookProvider(entry.book)).value;
    final added = entry.added && !own;
    final notes = [
      if (added) context.tr('Added today: {label}', {'label': context.prayerTitle(s, entry.addedEn ?? '', entry.addedHe ?? '')}),
      if (otherBook != null) context.tr('From {book}', {'book': context.prayerTitle(s, otherBook.title, otherBook.heTitle)}),
    ];
    return InkWell(
      onTap: () => context.push(readerPath(entry.book, entry.node.id, standalone: true)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Row(children: [
          SizedBox(
            width: 22,
            child: added
                ? Icon(Icons.add_circle, size: 16, color: colors.todayBar)
                : Icon(Icons.circle, size: 6, color: theme.colorScheme.outline),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              PrayerTitleText(entry.node.en, entry.node.he, enStyle: theme.textTheme.bodyLarge, heStyle: const TextStyle(fontSize: 18)),
              if (notes.isNotEmpty)
                Text(notes.join(' · '), style: theme.textTheme.bodySmall?.copyWith(color: added ? colors.todayBar : null)),
            ]),
          ),
          Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.outline),
        ]),
      ),
    );
  }
}
