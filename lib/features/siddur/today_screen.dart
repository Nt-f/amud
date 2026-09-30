import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// A key point of the day's davening to jump to: the service's key
/// sections, matched by title (first match per service), with the label
/// shown on its chip.
const _keyPoints = [
  ('Pesukei DeZimra', 'פסוקי דזמרה', r'pesukei d.{0,2}zimr'),
  ('Shema', 'שמע', r'shema'),
  ('Musaf', 'מוסף', r'mus+af'),
  ('Shemoneh Esrei', 'שמונה עשרה', r'^(?!post)(?:the )?amid|shemoneh esre|^magen avot|^magein avos'),
  ('Hallel', 'הלל', r'^hallel'),
  ('Tachanun', 'תחנון', r'ta(?:c)?h(?:a)?n(?:u)?n'),
  ('Torah reading', 'קריאת התורה', r'torah reading|reading of the torah'),
  ('Aleinu', 'עלינו', r'^al[ei]nu'),
  ('Candle lighting', 'הדלקת נרות', r'candle'),
  ('Kabbalat Shabbat', 'קבלת שבת', r'kabbal'),
  ('Kiddush Levana', 'קידוש לבנה', r'kiddush levan|blessing of the (?:new )?moon|birkat ha.?levana'),
  ('Kiddush', 'קידוש', r'kiddush'),
  ('Havdalah', 'הבדלה', r'havdal'),
  ('Sefirat HaOmer', 'ספירת העומר', r'omer'),
];

/// A chip in the jump bar: a service, or a key point within one.
class _Jump {
  final String en;
  final String he;
  final bool service;
  final GlobalKey target;
  final GlobalKey chip = GlobalKey();
  _Jump(this.en, this.he, this.target, {this.service = false});
}

/// The whole day's davening in order, section by section, with what's
/// added and what's left out today. A bar under the title jumps to each
/// service and its key points (Shema, Shemoneh Esrei, Hallel…).
class TodayDaveningScreen extends ConsumerStatefulWidget {
  const TodayDaveningScreen({super.key});

  @override
  ConsumerState<TodayDaveningScreen> createState() => _TodayDaveningScreenState();
}

class _TodayDaveningScreenState extends ConsumerState<TodayDaveningScreen> {
  final _scroll = ScrollController();
  final _keys = <Object, GlobalKey>{};
  List<_Jump> _jumps = const [];
  TodayPlan? _plan;
  int _active = 0;
  bool _jumping = false;

  GlobalKey _keyFor(Object o) => _keys.putIfAbsent(o, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_track);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<_Jump> _jumpsFor(TodayPlan p) => [
        for (final svc in p.services) ...[
          _Jump(svc.en, svc.he, _keyFor(svc), service: true),
          ...() {
            final seen = <String>{};
            return [
              for (final e in svc.entries)
                // A section counts once, as the first key point it matches
                // ("Musaf Amidah" is Musaf, not Shemoneh Esrei).
                if (_keyPoints.where((k) => RegExp(k.$3, caseSensitive: false).hasMatch(e.node.en)).firstOrNull
                    case (final en, final he, _) when seen.add(en))
                  _Jump(en, he, _keyFor(e)),
            ];
          }(),
        ],
      ];

  double? _offsetOf(GlobalKey k) {
    final box = k.currentContext?.findRenderObject();
    if (box == null || !box.attached) return null;
    return RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
  }

  /// Marks the chip of the part at the top of the screen.
  void _track() {
    if (_jumping || _jumps.isEmpty) return;
    var active = 0;
    for (final (i, j) in _jumps.indexed) {
      final o = _offsetOf(j.target);
      if (o != null && o <= _scroll.offset + 24) active = i;
    }
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 1) {
      // At the bottom the last parts can't reach the top; mark the last one
      // that's on screen.
      for (final (i, j) in _jumps.indexed) {
        final o = _offsetOf(j.target);
        if (o != null && o >= _scroll.offset) active = i;
      }
    }
    if (active != _active) _setActive(active);
  }

  void _setActive(int i) {
    setState(() => _active = i);
    final chip = _jumps[i].chip.currentContext;
    if (chip != null) Scrollable.ensureVisible(chip, alignment: 0.5, duration: const Duration(milliseconds: 200));
  }

  Future<void> _jump(int i) async {
    final ctx = _jumps[i].target.currentContext;
    if (ctx == null) return;
    _setActive(i);
    _jumping = true;
    await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    _jumping = false;
  }

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(readerDaytimeDateProvider);
    final picked = ref.watch(readerDateProvider);
    final plan = ref.watch(todayPlanProvider(date.abs()));
    final s = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final p = plan.value;
    if (!identical(p, _plan)) {
      // Another day (or siddur): the old sections' keys are done with.
      _plan = p;
      _keys.clear();
      _active = 0;
      _jumps = p == null ? const [] : _jumpsFor(p);
    }
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
        bottom: _jumps.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: SizedBox(
                  height: 52,
                  // All chips are built (not lazily), so the bar can scroll
                  // any of them into view.
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: Row(children: [
                      for (final (i, j) in _jumps.indexed) ...[
                        if (j.service && i > 0) const SizedBox(height: 24, child: VerticalDivider(width: 17)),
                        Padding(
                          key: j.chip,
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            avatar: j.service
                                ? Icon(serviceIcon(_serviceKey(p!, j)), size: 16, color: i == _active ? theme.colorScheme.onSecondaryContainer : theme.colorScheme.primary)
                                : null,
                            label: Text(context.prayerTitle(s, j.en, j.he),
                                style: TextStyle(
                                  fontWeight: j.service ? FontWeight.w700 : null,
                                  fontFamily: context.prayerTitleIsHebrew(s) ? s.hebrewFont : null,
                                )),
                            selected: i == _active,
                            onSelected: (_) => _jump(i),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
      ),
      body: Column(children: [
        DayBanner(date: date, picked: picked != null),
        Expanded(
          child: plan.when(
            loading: adaptiveProgress,
            error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
            // Every section is built (not lazily) so the bar can jump to any.
            data: (p) => p == null
                ? Center(child: Text(context.tr('Not found in this siddur')))
                : SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                      for (final svc in p.services) _ServiceCard(key: _keyFor(svc), plan: p, service: svc, keyFor: _keyFor),
                    ]),
                  ),
          ),
        ),
      ]),
    );
  }

  String _serviceKey(TodayPlan p, _Jump j) => p.services.firstWhere((svc) => _keys[svc] == j.target, orElse: () => p.services.first).key;
}

class _ServiceCard extends ConsumerWidget {
  final TodayPlan plan;
  final PlanService service;

  /// The jump bar's key for an entry, so it can scroll to it.
  final GlobalKey Function(Object) keyFor;
  const _ServiceCard({super.key, required this.plan, required this.service, required this.keyFor});

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
          for (final e in service.entries) _EntryTile(key: keyFor(e), plan: plan, entry: e, own: service.key == 'shabbatEve' || service.key == 'night'),
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
  const _EntryTile({super.key, required this.plan, required this.entry, this.own = false});

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
