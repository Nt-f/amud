import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/titles.dart';
import 'prayer_catalog.dart';
import 'reader_screen.dart';
import 'today_plan.dart';

/// Prayers that go with a section, by topic (whatever the day), for
/// the links under it.
final _related = <(RegExp, List<String>)>[
  (RegExp(r'birkat ha.?mazon|birchat ha.?mazon|birchas ha.?mazon|grace after|post meal', caseSensitive: false), ['meeinShalosh', 'brachot']),
  (RegExp(r'birkat hanehenin|blessings on (?:foods|enjoyments|pleasures)|before eating|berakha acharona', caseSensitive: false), ['birkat', 'meeinShalosh']),
  (RegExp(r'kiddush|shabbat evening|shabbos in the home|zemir', caseSensitive: false), ['birkat']),
  (RegExp(r'candle lighting', caseSensitive: false), ['kabbalatShabbat', 'kiddushShabbat']),
  (RegExp(r'kabbal[ae][ts] shabb', caseSensitive: false), ['candles', 'kiddushShabbat']),
  (RegExp(r'havdal', caseSensitive: false), ['kiddushLevana']),
  (RegExp(r'hosha|lulav|hallel', caseSensitive: false), ['lulav', 'hallel', 'hoshanot']),
  (RegExp(r'sukk|ushpiz', caseSensitive: false), ['sukkah', 'ushpizin', 'lulav']),
  (RegExp(r'chanuk|hanuk', caseSensitive: false), ['hallel']),
  (RegExp(r'selich|selih|avinu malk', caseSensitive: false), ['avinuMalkeinu', 'selichot']),
  (RegExp(r'levana|new moon', caseSensitive: false), ['havdalah']),
];

/// Prayers found outside the siddur's text (a screen of the app).
const _routes = {
  'meeinShalosh': ("Me'ein Shalosh", 'מעין שלוש', '/meein-shalosh'),
};

/// Links under a section of the reader: what comes next in today's
/// davening (Hallel after the Amidah on Rosh Chodesh, the day's Hoshana
/// after Musaf), what else is said today with it, prayers that go with it,
/// and the full order of the day. Outside today's davening, the next
/// section of the siddur.
class RelatedPrayers extends ConsumerWidget {
  final String book;
  final SchemaNode node;
  final bool standalone;
  const RelatedPrayers({super.key, required this.book, required this.node, required this.standalone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final date = ref.watch(readerDaytimeDateProvider).abs();
    final plan = ref.watch(todayPlanProvider(date)).value;
    final day = ref.watch(dayContextProvider((date, Service.shacharit)));
    final night = ref.watch(dayContextProvider((date, Service.maariv)));
    final theme = Theme.of(context);

    PrayerRef? next;
    String? nextService;
    final also = <PlanEntry>[];
    var inPlan = false;
    if (plan != null) {
      final entries = plan.entries;
      final at = locateInPlan(plan, book, node);
      PlanEntry? last;
      inPlan = at.covered.isNotEmpty || at.within != null;
      if (at.covered.isNotEmpty) {
        last = at.covered.last;
        // Read straight through, the service leaves out what comes from
        // elsewhere (the Lulav blessing, the day's Hoshana): link to it.
        final svc = plan.serviceOf(at.covered.first);
        if (at.covered.length > 1 && svc != null) also.addAll(svc.entries.where((e) => e.extra && !at.covered.contains(e)));
      } else if (at.within != null) {
        // A part of a section: its next part, then the next section.
        final siblings = node.parent?.children ?? const <SchemaNode>[];
        final i = siblings.indexOf(node);
        if (i >= 0 && i + 1 < siblings.length && siblings[i + 1].id.startsWith('${at.within!.node.id}/')) {
          next = PrayerRef(book, siblings[i + 1]);
        } else {
          last = at.within;
        }
      }
      if (last != null) {
        final i = entries.indexOf(last);
        final after = entries.skip(i + 1).where((e) => !at.covered.contains(e) && !also.contains(e));
        if (after.isNotEmpty) {
          next = after.first.ref;
          final from = plan.serviceOf(last), to = plan.serviceOf(after.first);
          if (to != null && to != from) nextService = context.prayerTitle(s, to.en, to.he);
        }
      }
    }
    // Outside today's davening: the next section of this siddur.
    if (!inPlan) {
      final siblings = node.parent?.children ?? const <SchemaNode>[];
      final i = siblings.indexOf(node);
      if (i >= 0 && i + 1 < siblings.length) next = PrayerRef(book, siblings[i + 1]);
    }

    // Prayers that go with this one, when they're said today (or aren't
    // tied to a day).
    bool relevant(String k) {
      final item = catalogItem(k);
      return _routes.containsKey(k) || (item != null && (item.when == null || itemTime(item, day, night) != ItemTime.none));
    }

    final related = <String>{
      for (final (re, keys) in _related)
        if (re.hasMatch(node.id))
          for (final k in keys)
            if (relevant(k)) k,
    };
    final links = <Widget>[];
    for (final k in related) {
      final route = _routes[k];
      if (route != null) {
        links.add(_chip(context, context.prayerTitle(s, route.$1, route.$2), () => context.push(route.$3)));
        continue;
      }
      final r = ref.watch(prayerRefProvider(k)).value;
      final item = catalogItem(k)!;
      if (r == null || (r.book == book && (r.node == node || r.id.startsWith('${node.id}/') || node.id.startsWith('${r.id}/')))) continue;
      if (also.any((e) => e.book == r.book && e.node == r.node) || (next != null && next.book == r.book && next.node == r.node)) continue;
      links.add(_chip(context, context.prayerTitle(s, item.en, item.he), () => context.push(readerPath(r.book, r.id, standalone: standalone))));
    }

    String title(SchemaNode n) => context.prayerTitle(s, n.en, n.he);
    final nextRef = next;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (nextRef != null)
          FilledButton.tonalIcon(
            // Replaces this page in the browser history too, so back returns
            // to where the reading started rather than the previous section.
            onPressed: () => Router.neglect(context, () => context.pushReplacement(readerPath(nextRef.book, nextRef.id, standalone: standalone))),
            icon: const Icon(Icons.arrow_forward),
            label: Text(
              nextService == null
                  ? context.tr('Next: {title}', {'title': title(nextRef.node)})
                  : context.tr('Next: {title}', {'title': '$nextService · ${title(nextRef.node)}'}),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (also.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(context.tr('Also today'), style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in also)
              _chip(context, e.added ? context.prayerTitle(s, e.addedEn ?? e.node.en, e.addedHe ?? e.node.he) : title(e.node),
                  () => context.push(readerPath(e.book, e.node.id, standalone: standalone))),
          ]),
        ],
        if (links.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(context.tr('Related prayers'), style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: links),
        ],
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => context.push('/today'),
          icon: const Icon(Icons.format_list_numbered),
          label: Text(context.tr("Today's davening")),
        ),
      ]),
    );
  }

  Widget _chip(BuildContext context, String label, VoidCallback onTap) =>
      ActionChip(avatar: const Icon(Icons.north_east, size: 16), label: Text(label), onPressed: onTap);
}
