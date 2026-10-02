import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/adaptive.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/titles.dart';
import 'prayer_catalog.dart';
import 'reader_screen.dart';
import 'siddur_providers.dart';

/// A siddur of the prayers for holidays and seasons (Hoshanot, Lulav,
/// Selichot, Chanukah candles…), gathered from the bundled siddurim: the
/// default one where it has them, otherwise another of the same nusach.
class SeasonsScreen extends ConsumerWidget {
  const SeasonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final date = ref.watch(readerDaytimeDateProvider);
    final picked = ref.watch(readerDateProvider);
    final day = ref.watch(dayContextProvider((date.abs(), Service.shacharit)));
    final night = ref.watch(dayContextProvider((date.abs(), Service.maariv)));
    final now = [
      for (final g in catalogGroups)
        for (final i in g.items)
          if (itemTime(i, day, night) != ItemTime.none) i,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Holidays & Seasons')),
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
          child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            if (now.isNotEmpty)
              AdaptiveSection(header: context.tr('Today'), children: [
                for (final i in now) _ItemTile(item: i, time: itemTime(i, day, night)),
              ]),
            for (final g in catalogGroups)
              AdaptiveSection(header: context.prayerTitle(s, g.en, g.he), children: [
                for (final i in g.items) _ItemTile(item: i, time: itemTime(i, day, night)),
              ]),
          ]),
        ),
      ]),
    );
  }
}

class _ItemTile extends ConsumerWidget {
  final CatalogItem item;
  final ItemTime time;
  const _ItemTile({required this.item, required this.time});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final found = ref.watch(prayerRefProvider(item.key));
    final r = found.value;
    // Not in any bundled siddur.
    if (found.hasValue && r == null && item.key != 'birkatHaChama') return const SizedBox.shrink();
    final defaultBook = ref.watch(defaultBookProvider).value;
    final book = r == null || r.book == defaultBook ? null : ref.watch(bookProvider(r.book)).value;
    final sub = [
      if (time == ItemTime.today) context.tr('Today'),
      if (time == ItemTime.tonight) context.tr('Tonight'),
      if (book != null) context.tr('From {book}', {'book': context.prayerTitle(s, book.title, book.heTitle)}),
    ];
    final title = PrayerTitleText(item.en, item.he, heStyle: const TextStyle(fontSize: 17));
    final subtitle = sub.isEmpty
        ? null
        : Text(sub.join(' · '), style: theme.textTheme.bodySmall?.copyWith(color: time == ItemTime.none ? null : colors.todayBar));
    final leading = Icon(time == ItemTime.none ? Icons.menu_book_outlined : Icons.today, color: time == ItemTime.none ? null : colors.todayBar);
    void open(SchemaNode n) => context.push(readerPath(r!.book, n.id));
    if (r == null && item.key == 'birkatHaChama') return ListTile(leading: leading, title: title, onTap: () => context.push('/pray/birkatHaChama'));
    if (r == null) return ListTile(leading: leading, title: title, enabled: false);

    // Sections with a part for each day (the Hoshanot) list the parts,
    // today's marked.
    final resolver = ref.watch(resolverProvider(r.book)).value;
    final parts = r.node.children;
    final daily = resolver != null && parts.length > 1 && parts.length <= 12 && parts.any((c) => resolver.sectionRuleFor(c) != null);
    if (!daily) return ListTile(leading: leading, title: title, subtitle: subtitle, onTap: () => open(r.node));
    final date = ref.watch(readerDaytimeDateProvider).abs();
    final todayParts = {
      for (final c in parts)
        if (sectionStatus(resolver, c, (svc) => ref.watch(dayContextProvider((date, svc)))).ap == Applicability.today) c,
    };
    return ExpansionTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      initiallyExpanded: time != ItemTime.none,
      childrenPadding: const EdgeInsetsDirectional.only(start: 16),
      children: [
        ListTile(
          dense: true,
          leading: const Icon(Icons.chrome_reader_mode_outlined, size: 20),
          title: Text(context.tr('Read all')),
          onTap: () => open(r.node),
        ),
        for (final c in parts)
          Builder(builder: (context) {
            final today = todayParts.contains(c);
            return ListTile(
              dense: true,
              leading: Icon(today ? Icons.today : Icons.circle, size: today ? 20 : 6, color: today ? colors.todayBar : theme.colorScheme.outline),
              title: PrayerTitleText(c.en, c.he,
                  enStyle: today ? const TextStyle(fontWeight: FontWeight.w700) : null,
                  heStyle: TextStyle(fontSize: 16, fontWeight: today ? FontWeight.w700 : null)),
              subtitle: today ? Text(context.tr('Today'), style: theme.textTheme.bodySmall?.copyWith(color: colors.todayBar)) : null,
              onTap: () => open(c),
            );
          }),
      ],
    );
  }
}
