import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hebcal/hebcal.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/format.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/settings.dart';
import '../../../core/theme.dart';
import '../../js_cards/js_card.dart';
import '../../minyan/minyan.dart';
import '../../siddur/today_summary.dart';
import '../../zmanim/zman_catalog.dart';
import '../card_registry.dart';
import '../today.dart';
import 'card_frame.dart';

void registerBuiltInCards(CardRegistry r) {
  r
    ..register(CardType(
      type: 'hebrewDate',
      title: 'Hebrew date',
      description: 'Date, parsha and today\'s holidays',
      icon: Icons.calendar_month,
      defaultSpan: 2,
      build: (c, ref, cfg) => const _HebrewDateCard(),
    ))
    ..register(CardType(
      type: 'nextZman',
      title: 'Next zman',
      description: 'Countdown to the next halachic time',
      icon: Icons.timer_outlined,
      build: (c, ref, cfg) => _NextZmanCard(cfg),
      editor: (c, ref, cfg, onChanged) => _ZmanKeysEditor(cfg: cfg, onChanged: onChanged),
      defaults: const {'keys': <String>[]},
    ))
    ..register(CardType(
      type: 'zmanimList',
      title: 'Zmanim',
      description: 'Today\'s zmanim at a glance',
      icon: Icons.wb_twilight,
      defaultSpan: 2,
      build: (c, ref, cfg) => _ZmanimListCard(cfg),
      editor: (c, ref, cfg, onChanged) => _ZmanKeysEditor(cfg: cfg, onChanged: onChanged),
      defaults: const {'keys': <String>[]},
    ))
    ..register(CardType(
      type: 'candles',
      title: 'Shabbat & Yom Tov',
      description: 'Next candle lighting and havdalah',
      icon: Icons.local_fire_department_outlined,
      build: (c, ref, cfg) => const _CandlesCard(),
    ))
    ..register(CardType(
      type: 'omer',
      title: 'Sefirat HaOmer',
      description: 'Tonight\'s count with sefira (only during the Omer)',
      icon: Icons.filter_7,
      defaultSpan: 2,
      visible: (ref) => omerCountTonight(ref.watch(todaySnapshotProvider)) > 0,
      build: (c, ref, cfg) => const _OmerCard(),
    ))
    ..register(CardType(
      type: 'learning',
      title: 'Daily learning',
      description: 'Daf Yomi, Mishna Yomi, Rambam and more (Hebcal)',
      icon: Icons.menu_book_outlined,
      build: (c, ref, cfg) => _LearningCard(cfg),
      editor: (c, ref, cfg, onChanged) => _LearningEditor(cfg: cfg, onChanged: onChanged),
      defaults: const {'schedules': ['dafYomi']},
    ))
    ..register(CardType(
      type: 'todayInSiddur',
      title: 'Today in the siddur',
      description: 'What\'s added or skipped in today\'s prayers',
      icon: Icons.auto_awesome,
      defaultSpan: 2,
      build: (c, ref, cfg) => const TodayInSiddurCard(),
    ))
    ..register(CardType(
      type: 'upcoming',
      title: 'Upcoming',
      description: 'Holidays and special days ahead',
      icon: Icons.event_note,
      defaultSpan: 2,
      build: (c, ref, cfg) => _UpcomingCard(cfg),
      defaults: const {'count': 5},
    ))
    ..register(CardType(
      type: 'quickPrayers',
      title: 'Quick prayers',
      description: 'Shortcuts into the siddur',
      icon: Icons.bolt,
      defaultSpan: 2,
      build: (c, ref, cfg) => const _QuickPrayersCard(),
    ))
    ..register(CardType(
      type: 'note',
      title: 'Note',
      description: 'A text note or kavanah',
      icon: Icons.sticky_note_2_outlined,
      build: (c, ref, cfg) => CardFrame(
        title: cfg.setting<String>('title', 'Note'),
        icon: Icons.sticky_note_2_outlined,
        child: Text(cfg.setting<String>('text', 'Tap edit to write a note.'),
            style: Theme.of(c).textTheme.bodyLarge, textDirection: _dir(cfg.setting<String>('text', ''))),
      ),
      editor: (c, ref, cfg, onChanged) => Column(children: [
        TextFormField(
          initialValue: cfg.setting<String>('title', 'Note'),
          decoration: const InputDecoration(labelText: 'Title'),
          onChanged: (v) => onChanged(cfg.copyWith(settings: {...cfg.settings, 'title': v})),
        ),
        TextFormField(
          initialValue: cfg.setting<String>('text', ''),
          decoration: const InputDecoration(labelText: 'Text'),
          maxLines: 6,
          onChanged: (v) => onChanged(cfg.copyWith(settings: {...cfg.settings, 'text': v})),
        ),
      ]),
    ))
    ..register(CardType(
      type: 'minyan',
      title: 'Find a minyan',
      description: 'Search minyanim nearby on GoDaven',
      icon: Icons.groups_outlined,
      build: (c, ref, cfg) => const MinyanCard(),
    ))
    ..register(CardType(
      type: 'customJs',
      title: 'Custom JS card',
      description: 'Write your own card in JavaScript (sandboxed)',
      icon: Icons.code,
      defaultSpan: 1,
      defaults: const {'title': 'My card', 'script': sampleJsCard},
      build: (c, ref, cfg) => JsCard(cfg),
      editor: (c, ref, cfg, onChanged) => JsCardEditor(cfg: cfg, onChanged: onChanged),
    ));
}

TextDirection _dir(String s) =>
    RegExp('[֐-׿]').hasMatch(s) ? TextDirection.rtl : TextDirection.ltr;

class _HebrewDateCard extends ConsumerWidget {
  const _HebrewDateCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todaySnapshotProvider);
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final s = ref.watch(settingsProvider);
    // After sunset the Hebrew date is already tomorrow's.
    final hd = t.halachic;
    final parsha = parshaName(hd, s.location.il, context.hebcalLocale);
    final holidays = getHolidaysOnDate(hd, s.location.il).where((e) => !e.hasFlag(Flags.yomKippurKatan) && !e.hasFlag(Flags.behab));
    return CardFrame(
      onTap: () => context.go('/calendar'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(formatPlainDate(t.civil), style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(hd.render(context.hebcalLocale), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
            ]),
          ),
          Text(hd.renderGematriya(),
              textDirection: TextDirection.rtl,
              style: theme.textTheme.headlineSmall?.copyWith(fontFamily: s.hebrewFont, color: theme.colorScheme.primary)),
        ]),
        if (t.afterSunset)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(context.tr('After sunset · the day of {date} has ended', {'date': t.hdate.render(context.hebcalLocale)}),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary)),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.auto_stories, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(parsha, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
        ]),
        if (holidays.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final h in holidays)
              Chip(
                label: Text('${h.getEmoji()} ${h.render(context.hebcalLocale)}'),
                backgroundColor: colors.chipToday,
                visualDensity: VisualDensity.compact,
              ),
          ]),
        ],
      ]),
    );
  }
}

List<String> _keysFor(CardConfig cfg, AppSettings s) {
  final keys = (cfg.settings['keys'] as List?)?.cast<String>() ?? const [];
  if (keys.isNotEmpty) return keys;
  return [for (final z in builtInZmanim) if (z.defaultFor.contains(s.opinion)) z.key];
}

class _NextZmanCard extends ConsumerWidget {
  final CardConfig cfg;
  const _NextZmanCard(this.cfg);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todaySnapshotProvider);
    final s = ref.watch(settingsProvider);
    final names = ref.watch(zmanResolverProvider);
    final keys = _keysFor(cfg, s);
    var next = t.nextZman(keys);
    DateTime? tomorrowTime;
    if (next == null) {
      // After the last zman: show tomorrow's first.
      final z = ref.watch(zmanimProvider(t.civil.addDays(1)));
      for (final k in keys) {
        final v = names.compute(k, z);
        if (v != null && (tomorrowTime == null || v.isBefore(tomorrowTime))) {
          tomorrowTime = v;
          next = (k, v);
        }
      }
    }
    final theme = Theme.of(context);
    return CardFrame(
      title: 'Next zman',
      icon: Icons.timer_outlined,
      onTap: () => context.go('/zmanim'),
      child: next == null
          ? const Text('No upcoming zmanim')
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(names.name(next.$1), style: theme.textTheme.titleMedium, maxLines: 2),
              const SizedBox(height: 6),
              Text(formatTime(next.$2, t.location, hour12: s.hour12),
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('in ${formatCountdown(next.$2.difference(t.now))}', style: theme.textTheme.bodyMedium),
            ]),
    );
  }
}

class _ZmanimListCard extends ConsumerWidget {
  final CardConfig cfg;
  const _ZmanimListCard(this.cfg);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todaySnapshotProvider);
    final s = ref.watch(settingsProvider);
    final names = ref.watch(zmanResolverProvider);
    final keys = _keysFor(cfg, s);
    final theme = Theme.of(context);
    final next = t.nextZman(keys)?.$1;
    return CardFrame(
      title: 'Zmanim · ${t.location.getShortName() ?? ''}',
      icon: Icons.wb_twilight,
      onTap: () => context.go('/zmanim'),
      child: Column(children: [
        for (final k in keys)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(
                child: Text(names.name(k),
                    style: k == next
                        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.primary)
                        : (t.zmanim[k] != null && t.zmanim[k]!.isBefore(t.now)
                            ? theme.textTheme.bodyMedium?.copyWith(color: theme.disabledColor)
                            : theme.textTheme.bodyMedium)),
              ),
              Text(formatTime(t.zmanim[k], t.location, hour12: s.hour12),
                  style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
      ]),
    );
  }
}

class _ZmanKeysEditor extends ConsumerStatefulWidget {
  final CardConfig cfg;
  final ValueChanged<CardConfig> onChanged;
  const _ZmanKeysEditor({required this.cfg, required this.onChanged});

  @override
  ConsumerState<_ZmanKeysEditor> createState() => _ZmanKeysEditorState();
}

class _ZmanKeysEditorState extends ConsumerState<_ZmanKeysEditor> {
  late List<String> keys = (widget.cfg.settings['keys'] as List?)?.cast<String>().toList() ?? [];

  @override
  Widget build(BuildContext context) {
    final names = ref.watch(zmanResolverProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Choose zmanim (none selected = defaults for your opinion setting)'),
      for (final (k, name) in names.allKeys)
        CheckboxListTile.adaptive(
          dense: true,
          value: keys.contains(k),
          title: Text(name),
          onChanged: (v) {
            setState(() => v == true ? keys.add(k) : keys.remove(k));
            widget.onChanged(widget.cfg.copyWith(settings: {...widget.cfg.settings, 'keys': List.of(keys)}));
          },
        ),
    ]);
  }
}

class _CandlesCard extends ConsumerWidget {
  const _CandlesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todaySnapshotProvider);
    final s = ref.watch(settingsProvider);
    final events = calendar(CalOptions(
      start: t.hdate,
      end: t.hdate.addDays(10),
      location: t.location,
      il: s.location.il,
      candlelighting: true,
      candleLightingMins: s.candleLightingMins,
      havdalahMins: s.havdalahMins,
      noHolidays: true,
      useElevation: s.useElevation,
      hour12: s.hour12,
    )).whereType<TimedEvent>().where((e) => e.eventTime.isAfter(t.now.subtract(const Duration(hours: 1)))).take(2).toList();
    final theme = Theme.of(context);
    return CardFrame(
      title: 'Shabbat & Yom Tov',
      icon: Icons.local_fire_department_outlined,
      child: events.isEmpty
          ? const Text('—')
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final e in events)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${e.getEmoji() ?? ''} ${e.renderBrief(context.hebcalLocale)}', style: theme.textTheme.bodyMedium),
                    Text(formatTime(e.eventTime, t.location, hour12: s.hour12),
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    Text(formatPlainDate(e.getDate().plainDate()), style: theme.textTheme.bodySmall),
                  ]),
                ),
            ]),
    );
  }
}

/// Tonight's Omer count (after sunset the halachic date has already
/// advanced); 0 outside the Omer.
int omerCountTonight(TodaySnapshot t) => !t.halachic.isSameDate(t.hdate) ? omerDay(t.halachic) : t.omerTonight;

/// A slim strip in a standout color, shown only during the Omer.
class _OmerCard extends ConsumerWidget {
  const _OmerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todaySnapshotProvider);
    final hebFont = ref.watch(settingsProvider.select((s) => s.hebrewFont));
    final theme = Theme.of(context);
    final day = omerCountTonight(t);
    if (day == 0) return const SizedBox.shrink();
    final ev = OmerEvent(t.hdate.next(), day);
    final on = theme.colorScheme.onTertiaryContainer;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.tertiaryContainer,
      child: InkWell(
        onTap: () => context.go('/siddur?section=omer'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Text('$day', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: on)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr('Sefirat HaOmer · tonight'),
                    style: theme.textTheme.labelLarge?.copyWith(color: on, fontWeight: FontWeight.w700)),
                Text(ev.sefira(OmerLang.translit), style: theme.textTheme.bodySmall?.copyWith(color: on), overflow: TextOverflow.ellipsis),
              ]),
            ),
            Text(ev.sefira(OmerLang.he), textDirection: TextDirection.rtl, style: TextStyle(fontFamily: hebFont, fontSize: 17, color: on)),
          ]),
        ),
      ),
    );
  }
}

class _LearningCard extends ConsumerWidget {
  final CardConfig cfg;
  const _LearningCard(this.cfg);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todaySnapshotProvider);
    final il = ref.watch(settingsProvider.select((s) => s.location.il));
    final schedules = (cfg.settings['schedules'] as List?)?.cast<String>() ?? const ['dafYomi'];
    final theme = Theme.of(context);
    return CardFrame(
      title: 'Daily learning',
      icon: Icons.menu_book_outlined,
      onTap: () => context.go('/learning'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final name in schedules)
          Builder(builder: (context) {
            Event? ev;
            try {
              ev = DailyLearning.lookup(name, t.hdate, il);
            } catch (_) {}
            if (ev == null) return const SizedBox.shrink();
            final url = ev.url();
            return InkWell(
              onTap: url == null ? null : () => launchUrl(Uri.parse(url)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.term(learningScheduleTitles[name] ?? name), style: theme.textTheme.labelSmall),
                  Text(ev.render(context.hebcalLocale), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ]),
              ),
            );
          }),
      ]),
    );
  }
}

class _LearningEditor extends StatefulWidget {
  final CardConfig cfg;
  final ValueChanged<CardConfig> onChanged;
  const _LearningEditor({required this.cfg, required this.onChanged});

  @override
  State<_LearningEditor> createState() => _LearningEditorState();
}

class _LearningEditorState extends State<_LearningEditor> {
  late final List<String> sel = (widget.cfg.settings['schedules'] as List?)?.cast<String>().toList() ?? ['dafYomi'];

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final e in learningScheduleTitles.entries)
          CheckboxListTile.adaptive(
            dense: true,
            value: sel.contains(e.key),
            title: Text(e.value),
            onChanged: (v) {
              setState(() => v == true ? sel.add(e.key) : sel.remove(e.key));
              widget.onChanged(widget.cfg.copyWith(settings: {...widget.cfg.settings, 'schedules': List.of(sel)}));
            },
          ),
      ]);
}

class _UpcomingCard extends ConsumerWidget {
  final CardConfig cfg;
  const _UpcomingCard(this.cfg);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todaySnapshotProvider);
    final il = ref.watch(settingsProvider.select((s) => s.location.il));
    final count = cfg.setting<num>('count', 5).toInt();
    final events = <HolidayEvent>[];
    for (var d = 1; d < 120 && events.length < count; d++) {
      final hd = t.hdate.addDays(d);
      for (final e in getHolidaysOnDate(hd, il)) {
        if (e.hasFlag(Flags.yomKippurKatan) || e.hasFlag(Flags.behab)) continue;
        if (events.length < count) events.add(e);
      }
    }
    final theme = Theme.of(context);
    return CardFrame(
      title: 'Upcoming',
      icon: Icons.event_note,
      onTap: () => context.go('/calendar'),
      child: Column(children: [
        for (final e in events)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 32, child: Text(e.getEmoji(), style: const TextStyle(fontSize: 18))),
              Expanded(child: Text(e.render(context.hebcalLocale), style: theme.textTheme.bodyMedium)),
              Text('${e.date.deltaDays(t.hdate)}d · ${formatPlainDate(e.date.plainDate(), weekday: false).replaceFirst(RegExp(r', \d+$'), '')}',
                  style: theme.textTheme.bodySmall),
            ]),
          ),
      ]),
    );
  }
}

/// Compact list of shortcuts into the siddur; two columns when wide.
class _QuickPrayersCard extends ConsumerWidget {
  const _QuickPrayersCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const shortcuts = [
      ('Shacharit', Icons.wb_sunny_outlined, 'shacharit'),
      ('Mincha', Icons.light_mode_outlined, 'mincha'),
      ('Maariv', Icons.nights_stay_outlined, 'maariv'),
      ('Birkat HaMazon', Icons.restaurant, 'birkat'),
      ("Me'ein Shalosh", Icons.bakery_dining, null),
      ('Bedtime Shema', Icons.bedtime_outlined, 'bedtime'),
      ('Tefillat HaDerech', Icons.directions_car_outlined, 'derech'),
    ];
    final theme = Theme.of(context);
    return CardFrame(
      title: 'Quick prayers',
      icon: Icons.bolt,
      child: LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 280 ? 2 : 1;
        final w = (c.maxWidth - 8 * (cols - 1)) / cols;
        return Wrap(spacing: 8, children: [
          for (final (label, icon, key) in shortcuts)
            SizedBox(
              width: w,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => key == null ? context.push('/meein-shalosh') : context.go('/siddur?section=$key'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(children: [
                    Icon(icon, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(context.tr(label), style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ),
            ),
        ]);
      }),
    );
  }
}

/// Encodes a card config for sharing (used by the JS editor's export).
String exportCard(CardConfig c) => base64Url.encode(utf8.encode(jsonEncode(c.toJson())));
