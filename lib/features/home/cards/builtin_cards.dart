import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hebcal/hebcal.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/adaptive.dart';
import '../../../core/format.dart';
import '../../../core/l10n.dart';
import '../../gemara/gemara_home_screen.dart' show DafVideoButton, dafOfAmud, learningPath;
import '../../gemara/study_book.dart' show dafYomiPlace;
import '../../../core/providers.dart';
import '../../../core/settings.dart';
import '../../../core/split_row.dart';
import '../../../core/theme.dart';
import '../../../core/titles.dart';
import '../../alerts/alerts.dart';
import '../../calendar/calendar_screen.dart';
import '../../integrations/omer_badge.dart';
import '../../js_cards/js_card.dart';
import '../../minyan/minyan.dart';
import '../../siddur/siddur_providers.dart';
import '../../siddur/today_summary.dart';
import '../../siddur/day_guide_screen.dart';
import '../../zmanim/zman_catalog.dart';
import '../card_registry.dart';
import '../today.dart';
import '../../torah/shnayim_mikra_screen.dart';
import '../../torah/torah_screen.dart' show kitzurTarget;
import 'card_frame.dart';

void registerBuiltInCards(CardRegistry r) {
  r
    ..register(CardType(type: 'prepareTomorrow', title: 'Prepare for tomorrow', description: 'Tomorrow’s prayer changes, previews and printing', icon: Icons.nights_stay_outlined, defaultSpan: 2, build: (c, ref, cfg) => const PrepareTomorrowCard()))
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
      type: 'calendar',
      title: 'Calendar',
      description: 'Month view with Hebrew dates, holidays and times',
      icon: Icons.calendar_month_outlined,
      defaultSpan: 2,
      build: (c, ref, cfg) => const _CalendarCard(),
    ))
    ..register(CardType(
      type: 'omer',
      title: 'Sefirat HaOmer',
      description: 'Tonight\'s count with sefira (only during the Omer)',
      icon: Icons.filter_7,
      defaultSpan: 2,
      visible: (ref, _) => omerCountTonight(ref.watch(todaySnapshotProvider)) > 0,
      shownWhen: (_) => 'Only during the Omer',
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
          decoration: InputDecoration(labelText: c.tr('Title')),
          onChanged: (v) => onChanged(cfg.copyWith(settings: {...cfg.settings, 'title': v})),
        ),
        TextFormField(
          initialValue: cfg.setting<String>('text', ''),
          decoration: InputDecoration(labelText: c.tr('Text')),
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
    final p = upcomingParsha(hd, s.location.il, context.hebcalLocale);
    final parsha = p.thisWeek
        ? p.name
        : context.tr('{parsha} · Shabbat {date}',
            {'parsha': p.name, 'date': formatPlainDate(p.shabbat.plainDate(), weekday: false, year: false)});
    final holidays = getHolidaysOnDate(hd, s.location.il).where((e) => !e.hasFlag(Flags.yomKippurKatan) && !e.hasFlag(Flags.behab));
    return CardFrame(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SplitRow(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(formatPlainDate(t.civil), style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(hd.render(context.hebcalLocale), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          ]),
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
        const SizedBox(height: 4),
        const ShnayimMikraLine(),
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
          ? Text(context.tr('No upcoming zmanim'))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(names.label(next.$1), style: theme.textTheme.titleMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              // Shrinks rather than breaking the time in a compact card.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(formatTime(next.$2, t.location, hour12: s.hour12),
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Text(context.tr('in {time}', {'time': formatCountdown(next.$2.difference(t.now))}), style: theme.textTheme.bodyMedium),
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
      title: '${context.tr('Zmanim')} · ${t.location.getShortName() ?? ''}',
      icon: Icons.wb_twilight,
      onTap: () => context.go('/zmanim'),
      child: Column(children: [
        for (final k in keys)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(
                child: Text(names.label(k),
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
      Text(context.tr('Choose zmanim (none selected = defaults for your opinion setting)')),
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
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(formatTime(e.eventTime, t.location, hour12: s.hour12),
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    Text(formatPlainDate(e.getDate().plainDate()), style: theme.textTheme.bodySmall),
                  ]),
                ),
            ]),
    );
  }
}

class _CalendarCard extends ConsumerWidget {
  const _CalendarCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) => CardFrame(
        title: 'Calendar',
        icon: Icons.calendar_month_outlined,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => resetCalendar(ref),
            child: Text(context.tr('Today')),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: context.tr('Open'),
            icon: const Icon(Icons.open_in_full, size: 18),
            onPressed: () => context.push('/calendar'),
          ),
        ]),
        child: const CalendarView(compact: true),
      );
}

/// Tonight's Omer count (after sunset the halachic date has already
/// advanced); 0 outside the Omer.
int omerCountTonight(TodaySnapshot t) => !t.halachic.isSameDate(t.hdate) ? omerDay(t.halachic) : t.omerTonight;

/// The blessing over the count, as in the siddur.
const omerBlessing = 'בָּרוּךְ אַתָּה יְהֹוָה אֱלֹהֵֽינוּ מֶֽלֶךְ הָעוֹלָם אֲשֶׁר קִדְּשָֽׁנוּ בְּמִצְוֹתָיו וְצִוָּֽנוּ עַל סְפִירַת הָעֹֽמֶר';

/// Tonight's counting formula in Hebrew; Chabad counts "בָּעֹמֶר".
String omerCountHe(OmerEvent ev, {required bool chabad}) {
  final he = ev.getTodayIs('he');
  return chabad ? he.replaceFirst(RegExp(r'לָעֽוֹמֶר$'), 'בָּעֽוֹמֶר') : he;
}

/// The sefira in English letters ("Tiferet sheb'Malkhut"), in the reader's
/// spelling, including the word joined to "sheb'".
String sefiraTranslit(OmerEvent ev, String Function(String) term) => ev
    .sefira(OmerLang.translit)
    .replaceAllMapped(RegExp(r"^(\S+)( sheb'| shebi)(\S+)$"), (m) => '${term(m[1]!)}${m[2]}${term(m[3]!)}');

/// Once each Omer, for someone without the nightly reminder: offers to turn
/// it on (and asks for notifications) before the count opens.
Future<void> offerOmerReminder(BuildContext context, WidgetRef ref) async {
  final year = ref.read(todaySnapshotProvider).halachic.getFullYear();
  if (ref.read(settingsProvider).omerReminder || ref.read(omerReminderAskedProvider) == year) return;
  ref.read(omerReminderAskedProvider.notifier).mark(year);
  final on = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.notifications_active_outlined),
      title: Text(c.tr('Remind you to count?')),
      content: Text(c.tr('A reminder at nightfall each night of the Omer, so no day is missed. Not on Shabbat or Yom Tov.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.tr('Not now'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(c.tr('Turn on'))),
      ],
    ),
  );
  if (on != true || !await ref.read(notificationBackendProvider).requestPermission()) return;
  ref.read(settingsProvider.notifier).update((x) => x.copyWith(omerReminder: true));
}

/// Shown only during the Omer, in a standout color: the blessing and
/// tonight's count front and center, the sefira under them.
class _OmerCard extends ConsumerWidget {
  const _OmerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todaySnapshotProvider);
    final hebFont = ref.watch(settingsProvider.select((s) => s.hebrewFont));
    final chabad = ref.watch(defaultBookProvider).value?.contains('Chabad') ?? false;
    final theme = Theme.of(context);
    final day = omerCountTonight(t);
    final counted = ref.watch(omerCountedProvider) == t.halachic.abs();
    if (day == 0) return const SizedBox.shrink();
    final ev = OmerEvent(t.hdate.next(), day);
    final on = theme.colorScheme.onTertiaryContainer;
    final hebrew = TextStyle(fontFamily: hebFont, color: on, height: 1.45);
    return Card(
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.tertiaryContainer,
      child: InkWell(
        onTap: () async {
          await offerOmerReminder(context, ref);
          if (context.mounted) context.push('/pray/omer');
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(context.tr('Sefirat HaOmer · tonight'),
                    style: theme.textTheme.labelLarge?.copyWith(color: on, fontWeight: FontWeight.w700)),
              ),
              Text('$day', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: on)),
              if (t.afterSunset)
                IconButton(
                    tooltip: context.tr(counted ? 'Counted tonight' : 'Mark Omer counted'),
                    icon: Icon(counted ? Icons.check_circle : Icons.check_circle_outline, color: on),
                    onPressed: counted ? null : () => ref.read(omerCountedProvider.notifier).mark(t.halachic.abs()))
              else
                const SizedBox(width: 8),
            ]),
            const SizedBox(height: 6),
            Text(omerBlessing, textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: hebrew.copyWith(fontSize: 16)),
            const SizedBox(height: 6),
            Text(omerCountHe(ev, chabad: chabad),
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: hebrew.copyWith(fontSize: 21, fontWeight: FontWeight.w700)),
            if (context.uiLanguage == UiLanguage.en)
              Text(ev.getTodayIs('en'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: on)),
            const SizedBox(height: 8),
            Text(
                context.uiLanguage == UiLanguage.en
                    ? '${ev.sefira(OmerLang.he)} · ${sefiraTranslit(ev, AppText.of(context).term)}'
                    : ev.sefira(OmerLang.he),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: on.withValues(alpha: 0.8), fontFamily: hebFont)),
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
      // Pushed, so the learning screen has a way back to Home.
      onTap: () => context.push('/learning'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final name in schedules)
          Builder(builder: (context) {
            Event? ev;
            try {
              ev = DailyLearning.lookup(name, t.hdate, il);
            } catch (_) {}
            if (ev == null) return const SizedBox.shrink();
            final url = ev.url();
            // The app's own reader where it has the text; Sefaria otherwise.
            final inApp = learningPath(name, t.civil, ev);
            final entry = InkWell(
              onTap: inApp != null
                  ? () => context.push(inApp)
                  : url == null
                      ? null
                      : () => launchUrl(Uri.parse(url)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tr(learningScheduleTitles[name] ?? name), style: theme.textTheme.labelSmall),
                  Text(ev.render(context.hebcalLocale), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ]),
              ),
            );
            // Daf Yomi's and Kitzur Yomi's video shiur, beside them.
            final video = switch (name) {
              'dafYomi' => switch (dafYomiPlace(t.civil)) {
                  final daf? when dafOfAmud(daf.unit) != null => DafVideoButton(tractate: daf.book, daf: dafOfAmud(daf.unit)!),
                  _ => null,
                },
              'kitzurShulchanAruch' => switch (ev is KitzurShulchanAruchEvent ? kitzurTarget(ev) : null) {
                  final k? => DafVideoButton.kitzur(siman: k.siman, seif: k.from),
                  null => null,
                },
              _ => null,
            };
            if (video == null) return entry;
            // Beside the name where both fit; on a narrow card, under it.
            return SplitRow(crossAxisAlignment: CrossAxisAlignment.center, children: [entry, video]);
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
            title: Text(context.tr(e.value)),
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
      onTap: () => context.push('/calendar'),
      child: Column(children: [
        for (final e in events)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              // Some holidays have two emoji (🕎1️⃣): shrunk to one line.
              SizedBox(
                width: 32,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(e.getEmoji(), style: const TextStyle(fontSize: 18)),
                ),
              ),
              Expanded(
                child: SplitRow(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Text(e.render(context.hebcalLocale), style: theme.textTheme.bodyMedium),
                  Text('${context.tr('in {n}d', {'n': e.date.deltaDays(t.hdate)})} · ${formatPlainDate(e.date.plainDate(), weekday: false, year: false)}',
                      style: theme.textTheme.bodySmall),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Shortcuts into the siddur, grouped by when they're said. They open
/// above the tabs, so back returns Home.
class _QuickPrayersCard extends ConsumerWidget {
  const _QuickPrayersCard();

  static const _groups = [
    ('Davening', [
      ('Shacharit', 'שחרית', Icons.wb_sunny_outlined, '/pray/shacharit'),
      ('Mincha', 'מנחה', Icons.light_mode_outlined, '/pray/mincha'),
      ('Maariv', 'ערבית', Icons.nights_stay_outlined, '/pray/maariv'),
    ]),
    ('After meals', [
      ('Birkat HaMazon', 'ברכת המזון', Icons.restaurant, '/pray/birkat'),
      ("Me'ein Shalosh", 'מעין שלוש', Icons.bakery_dining, '/meein-shalosh'),
    ]),
    ('More', [
      ('Tefillat HaDerech', 'תפילת הדרך', Icons.directions_car_outlined, '/pray/derech'),
      ('Bedtime Shema', 'קריאת שמע על המיטה', Icons.bedtime_outlined, '/pray/bedtime'),
    ]),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = ref.watch(settingsProvider);
    return CardFrame(
      title: 'Quick prayers',
      icon: Icons.bolt,
      child: LayoutBuilder(builder: (context, c) {
        final label = theme.textTheme.bodyMedium?.copyWith(fontFamily: context.prayerTitleIsHebrew(s) ? s.hebrewFont : null);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, (heading, items)) in _groups.indexed) ...[
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10, bottom: 2),
              child: Text(context.tr(heading), style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)),
            ),
            Builder(builder: (context) {
              // As many columns as show every name whole on one line at this
              // width and text size (Shacharit, Mincha and Maariv share a row
              // when there's room).
              final names = [for (final (en, he, _, _) in items) context.prayerTitle(s, en, he)];
              final widest = names.fold(0.0, (w, n) => math.max(w, textWidth(context, n, label)));
              var cols = math.min(3, items.length);
              while (cols > 1 && (c.maxWidth - 8 * (cols - 1)) / cols - 26 < widest) {
                cols--;
              }
              final w = (c.maxWidth - 8 * (cols - 1)) / cols;
              return Wrap(spacing: 8, children: [
                for (final (en, he, icon, path) in items)
                  SizedBox(
                    width: w,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => context.push(path),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(children: [
                          Icon(icon, size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(context.prayerTitle(s, en, he), style: label)),
                        ]),
                      ),
                    ),
                  ),
              ]);
            }),
          ],
        ]);
      }),
    );
  }
}

/// Encodes a card config for sharing (used by the JS editor's export).
String exportCard(CardConfig c) => base64Url.encode(utf8.encode(jsonEncode(c.toJson())));
