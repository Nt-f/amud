import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hebcal/hebcal.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/adaptive.dart';
import '../../core/focus_mode.dart';
import '../../core/fonts.dart';
import '../../core/format.dart';
import '../../core/hebrew_text.dart';
import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../home/card_registry.dart';
import '../home/cards/card_frame.dart';
import '../home/today.dart';
import '../settings/font_gallery_screen.dart';
import 'shnayim_mikra.dart';
import 'torah_library.dart';
import 'torah_settings.dart';
import 'verse_snap.dart';

String _day(BuildContext context, int aliyah) =>
    context.tr(const ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Shabbat'][aliyah - 1]);

/// This week's reading and today's aliyah, from the Torah tab or the
/// calendar's date.
({ParshaReading reading, HDate shabbat, int aliyah})? _thisWeek(WidgetRef ref) =>
    shnayimMikraWeek(ref.watch(todaySnapshotProvider).hdate, ref.watch(settingsProvider.select((s) => s.location.il)));

/// Today's Shnayim Mikra, for the Torah tab.
class ShnayimMikraTile extends ConsumerWidget {
  const ShnayimMikraTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = _thisWeek(ref);
    final progress = ref.watch(shnayimMikraProgressProvider);
    final theme = Theme.of(context);
    final on = theme.colorScheme.onPrimaryContainer;
    String? subtitle;
    var doneToday = false;
    if (week != null) {
      final name = week.reading.parsha.join('-');
      final year = progress[week.shabbat.getFullYear()] ?? const {};
      final done = [for (var n = 1; n <= 7; n++) if (year.contains(ShnayimMikraProgress.entry(name, n))) n].length;
      doneToday = year.contains(ShnayimMikraProgress.entry(name, week.aliyah));
      subtitle = '${renderParshaName(week.reading.parsha, context.hebcalLocale)} · '
          '${context.tr('Aliyah {n}', {'n': week.aliyah})} · ${_day(context, week.aliyah)}\n'
          '${context.tr('{n} of 7 this week', {'n': done})}';
    }
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: ListTile(
        leading: Icon(doneToday ? Icons.check_circle : Icons.auto_stories, color: on),
        title: Text(context.tr('Shnayim Mikra'), style: theme.textTheme.titleMedium?.copyWith(color: on, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle ?? context.tr('No reading today'), style: TextStyle(color: on)),
        isThreeLine: subtitle != null,
        trailing: IconButton(
          tooltip: context.tr('Your year'),
          icon: Icon(Icons.grid_view, color: on),
          onPressed: () => context.push('/torah/shnayim-mikra/progress'),
        ),
        onTap: week == null ? null : () => context.push('/torah/shnayim-mikra'),
      ),
    );
  }
}

/// A parsha an aliyah at a time: each verse twice and its Targum Onkelos,
/// laid out like the siddur. Opens on this week's parsha and today's
/// aliyah, or on [parsha] of [year] (from the year's chart).
class ShnayimMikraScreen extends ConsumerStatefulWidget {
  final String? parsha;
  final int? year;
  const ShnayimMikraScreen({super.key, this.parsha, this.year});

  @override
  ConsumerState<ShnayimMikraScreen> createState() => _ShnayimMikraScreenState();
}

class _ShnayimMikraScreenState extends ConsumerState<ShnayimMikraScreen> with FocusModeReader {
  int? _aliyah;
  final _verseKeys = <GlobalKey>[];

  List<GlobalKey> _keys(int n) {
    while (_verseKeys.length < n) {
      _verseKeys.add(GlobalKey());
    }
    return _verseKeys.sublist(0, n);
  }

  @override
  Widget build(BuildContext context) {
    final week = _thisWeek(ref);
    final reading = widget.parsha == null ? week?.reading : ParshaReading.of(widget.parsha!.split('-'));
    final theme = Theme.of(context);
    if (reading == null) {
      return Scaffold(appBar: AppBar(title: Text(context.tr('Shnayim Mikra'))), body: Center(child: Text(context.tr('No reading today'))));
    }
    final name = reading.parsha.join('-');
    final year = widget.year ?? week?.shabbat.getFullYear() ?? ref.watch(todaySnapshotProvider).hdate.getFullYear();
    // The same parsha opened from another year's chart isn't this week's.
    final isThisWeek = week != null && week.reading.parsha.join('-') == name && week.shabbat.getFullYear() == year;
    final today = isThisWeek ? week.aliyah : null;
    final aliyah = _aliyah ?? today ?? 1;
    final progress = ref.watch(shnayimMikraProgressProvider);
    bool done(int n) => progress[year]?.contains(ShnayimMikraProgress.entry(name, n)) ?? false;
    final text = ref.watch(shnayimMikraProvider(name));

    final bar = AppBar(
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.tr('Shnayim Mikra')),
        Text(renderParshaName(reading.parsha, context.hebcalLocale), style: theme.textTheme.bodySmall),
      ]),
      actions: [
        IconButton(
          tooltip: context.tr('Your year'),
          icon: const Icon(Icons.grid_view),
          onPressed: () => context.push('/torah/shnayim-mikra/progress?year=$year'),
        ),
        IconButton(tooltip: context.tr('Text settings'), icon: const Icon(Icons.text_fields), onPressed: () => _showSettings(context)),
      ],
    );

    final body = switch (text) {
      AsyncData(:final value) => _Aliyah(
          key: ValueKey(aliyah),
          text: value,
          range: reading.aliyot[aliyah - 1],
          keys: _keys(value.verses.length),
          today: aliyah == today,
          footer: Column(children: [
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              icon: Icon(done(aliyah) ? Icons.check_circle : Icons.check_circle_outline),
              label: Text(done(aliyah) ? context.tr('Aliyah {n} done', {'n': aliyah}) : context.tr('Mark aliyah {n} done', {'n': aliyah})),
              onPressed: () {
                final wasDone = done(aliyah);
                ref.read(shnayimMikraProgressProvider.notifier).toggle(year, name, aliyah);
                // On to the next aliyah, as you would in the book.
                if (!wasDone && aliyah < 7) setState(() => _aliyah = aliyah + 1);
              },
            ),
            const SizedBox(height: 16),
            Text(
                value.enCredit.isEmpty
                    ? context.tr('Text and Targum Onkelos from Sefaria.')
                    : context.tr('Text and Targum Onkelos from Sefaria. English: {credit}.', {'credit': value.enCredit}),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ]),
        ),
      AsyncError() => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(context.tr('Download failed. Check your connection and try again.'), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: () {
                    ref.invalidate(chumashBookProvider);
                    ref.invalidate(shnayimMikraProvider(name));
                  },
                  child: Text(context.tr('Retry'))),
              TextButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: Text(context.tr('Open on Sefaria')),
                onPressed: () => launchUrl(Uri.parse('https://www.sefaria.org/${sefariaRange(reading)}')),
              ),
            ]),
          ),
        ),
      _ => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(context.tr('Downloading the Chumash from Sefaria, once. After this it works offline.'), textAlign: TextAlign.center),
            ),
          ]),
        ),
    };

    return Scaffold(
      body: Column(children: [
        FocusModeBars(child: bar),
        // The seven aliyot by day: today's and the finished ones marked.
        FocusModeBars(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(children: [
              for (var n = 1; n <= 7; n++)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    avatar: done(n) ? const Icon(Icons.check, size: 16) : (n == today ? const Icon(Icons.today, size: 16) : null),
                    label: Text('$n · ${_day(context, n)}'),
                    selected: n == aliyah,
                    onSelected: (_) => setState(() => _aliyah = n),
                  ),
                ),
            ]),
          ),
        ),
        Expanded(child: FocusModeBody(child: DoubleTapListener(onDoubleTap: toggleFocusMode, child: body))),
      ]),
    );
  }
}

/// One aliyah's verses, in the siddur's layout and type settings.
class _Aliyah extends ConsumerWidget {
  final MikraText text;
  final (Verse, Verse) range;
  final List<GlobalKey> keys;

  /// Today's aliyah, highlighted as the siddur marks what's said today.
  final bool today;
  final Widget footer;
  const _Aliyah({super.key, required this.text, required this.range, required this.keys, required this.today, required this.footer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(mikraStyleProvider);
    final sm = ref.watch(shnayimMikraSettingsProvider);
    final snap = ref.watch(torahSettingsProvider.select((t) => t.snapToVerse));
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    int key(Verse v) => v.chapter * 1000 + v.verse;
    final verses = [for (final v in text.verses) if (key(v.at) >= key(range.$1) && key(v.at) <= key(range.$2)) v];
    final width = MediaQuery.sizeOf(context).width;
    final layout = switch (s.layout) {
      TextLayout.sideBySide when width > 700 => TextLayout.sideBySide,
      TextLayout.hebrewOnly => TextLayout.hebrewOnly,
      _ => TextLayout.interleaved,
    };
    final heStyle = TextStyle(
        fontFamily: hebrewFamilyFor(s.hebrewFont, teamim: s.showTeamim, nikud: s.showNikud),
        fontSize: 22 * s.textScale,
        height: 1.7,
        color: theme.colorScheme.onSurface);
    // Onkelos has nikud but no te'amim.
    final targumStyle = heStyle.copyWith(
        fontFamily: hebrewFamilyFor(s.hebrewFont, teamim: false, nikud: s.showNikud),
        fontSize: 19 * s.textScale,
        color: theme.colorScheme.onSurfaceVariant);
    final enStyle = TextStyle(fontFamily: s.latinFont, fontSize: 17 * s.textScale, height: 1.5, color: theme.colorScheme.onSurface);
    final mark = TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 14 * s.textScale);
    String marks(String he) => hebrewMarks(he, teamim: s.showTeamim, nikud: s.showNikud);

    Widget verse(MikraVerse v, GlobalKey k) {
      final number = '${gematriya(v.at.chapter)}:${gematriya(v.at.verse)} ';
      final he = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < (sm.repeatVerse ? 2 : 1); i++)
          Text.rich(TextSpan(children: [TextSpan(text: number, style: mark), TextSpan(text: marks(v.he))]),
              textDirection: TextDirection.rtl, style: heStyle),
        if (sm.showTargum && v.targum.isNotEmpty)
          Text.rich(TextSpan(children: [TextSpan(text: 'ת״א ', style: mark), TextSpan(text: hebrewMarks(v.targum, teamim: false, nikud: s.showNikud))]),
              textDirection: TextDirection.rtl, style: targumStyle),
      ]);
      final en = layout == TextLayout.hebrewOnly || v.en.isEmpty
          ? null
          : Text.rich(TextSpan(children: [TextSpan(text: '${v.at.chapter}:${v.at.verse} ', style: mark), TextSpan(text: v.en)]),
              textDirection: TextDirection.ltr, style: enStyle);
      return Container(
        key: k,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: today && s.highlightToday
            ? BoxDecoration(
                color: colors.todayFill,
                borderRadius: BorderRadius.circular(10),
                border: BorderDirectional(start: BorderSide(color: colors.todayBar, width: 3)),
              )
            : null,
        child: en == null
            ? he
            : layout == TextLayout.sideBySide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: en), const SizedBox(width: 24), Expanded(child: he)])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [he, const SizedBox(height: 6), en]),
      );
    }

    final verseKeys = keys.sublist(0, verses.length);
    return VerseSnap(
      verses: verseKeys,
      enabled: snap,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.paddingOf(context).bottom),
        itemCount: verses.length + 1,
        itemBuilder: (context, i) => i < verses.length ? verse(verses[i], verseKeys[i]) : footer,
      ),
    );
  }
}

/// Shnayim Mikra's options. Its text style is the siddur's until "Same
/// text style as the siddur" is turned off; then it has its own.
Future<void> _showSettings(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _Settings(),
    );

class _Settings extends ConsumerWidget {
  const _Settings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final siddur = ref.watch(settingsProvider);
    final sm = ref.watch(shnayimMikraSettingsProvider);
    final smn = ref.read(shnayimMikraSettingsProvider.notifier);
    final style = ref.watch(mikraStyleProvider);
    final snap = ref.watch(torahSettingsProvider.select((t) => t.snapToVerse));
    final userFonts = ref.watch(fontsProvider);
    final theme = Theme.of(context);
    void own(ShnayimMikraSettings Function(ShnayimMikraSettings) f) => smn.update(f);
    Widget toggle(String title, bool value, ValueChanged<bool> onChanged, {String? subtitle}) => SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(context.tr(title)),
        subtitle: subtitle == null ? null : Text(context.tr(subtitle)),
        value: value,
        onChanged: onChanged);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
          Text(context.tr('Shnayim Mikra'), style: theme.textTheme.titleLarge),
          toggle('Show each verse twice', sm.repeatVerse, (v) => own((x) => x.copyWith(repeatVerse: v)),
              subtitle: 'Off to read the verse twice yourself'),
          toggle('Show Targum Onkelos', sm.showTargum, (v) => own((x) => x.copyWith(showTargum: v))),
          toggle('Snap to each verse', snap, (v) => ref.read(torahSettingsProvider.notifier).update((x) => x.copyWith(snapToVerse: v)),
              subtitle: 'When you stop scrolling near the end of a verse, the next one moves to the top.'),
          SheetLabel(context.tr('Text')),
          toggle('Same text style as the siddur', !sm.ownStyle,
              (v) => own((x) => v ? x.copyWith(ownStyle: false) : x.startOwnStyle(siddur)),
              subtitle: sm.ownStyle
                  ? 'Changes here are for Shnayim Mikra only.'
                  : 'Turn off to choose a font and layout for Shnayim Mikra only. Your siddur stays as it is.'),
          if (!sm.ownStyle)
            Text('${fontLabel(style.hebrewFont, userFonts)} · ${_layoutLabel(context, style.layout)}', style: theme.textTheme.bodySmall)
          else ...[
            Row(children: [
              const Icon(Icons.text_decrease, size: 18),
              Expanded(
                child: Slider.adaptive(
                  value: style.textScale,
                  min: 0.7,
                  max: 2.2,
                  divisions: 30,
                  label: '${(style.textScale * 100).round()}%',
                  onChanged: (v) => own((x) => x.copyWith(textScale: v)),
                ),
              ),
              const Icon(Icons.text_increase, size: 18),
            ]),
            ChoiceBar<TextLayout>(
              options: [
                (TextLayout.hebrewOnly, context.tr('Hebrew'), Icons.format_textdirection_r_to_l),
                (TextLayout.interleaved, context.tr('Bilingual'), Icons.view_stream),
                (TextLayout.sideBySide, context.tr('Side by side'), Icons.view_column),
              ],
              selected: style.layout == TextLayout.translationOnly ? TextLayout.interleaved : style.layout,
              onChanged: (v) => own((x) => x.copyWith(layout: v)),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.font_download_outlined),
              title: Text(context.tr('Hebrew font')),
              subtitle: Text(fontLabel(style.hebrewFont, userFonts)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
                  builder: (_) => FontGalleryScreen(
                        selectedFont: mikraStyleProvider.select((x) => x.hebrewFont),
                        chooseFont: (ref, family) => ref.read(shnayimMikraSettingsProvider.notifier).update((x) => x.copyWith(hebrewFont: family)),
                      ))),
            ),
            SheetLabel(context.tr('English font')),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (family, label) in latinFontChoices)
                ChoiceChip(
                  label: Text(family == null ? context.tr(label) : label, style: TextStyle(fontFamily: family)),
                  selected: style.latinFont == family,
                  onSelected: (_) => own((x) => x.copyWith(latinFont: () => family)),
                ),
            ]),
            toggle("Show te'amim (trop)", style.showTeamim, (v) => own((x) => x.copyWith(showTeamim: v))),
            toggle('Show nikud (vowels)', style.showNikud, (v) => own((x) => x.copyWith(showNikud: v))),
            toggle("Highlight today's aliyah", style.highlightToday, (v) => own((x) => x.copyWith(highlightToday: v))),
          ],
          SheetLabel(context.tr('Offline')),
          const _OfflineStatus(),
        ]),
      ),
    );
  }
}

String _layoutLabel(BuildContext context, TextLayout l) => context.tr(switch (l) {
      TextLayout.hebrewOnly => 'Hebrew',
      TextLayout.sideBySide => 'Side by side',
      _ => 'Bilingual',
    });

/// Whether the Chumash is downloaded, with a button to download it now.
class _OfflineStatus extends ConsumerWidget {
  const _OfflineStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(chumashDownloadProvider);
    final theme = Theme.of(context);
    if (d.have.length == 5) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.offline_pin, color: theme.colorScheme.primary),
        title: Text(context.tr('Available offline · {size}', {'size': formatBytes(d.bytes)})),
        subtitle: Text(context.tr('All five books, with Onkelos and English.')),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.download),
      title: Text(context.tr(d.busy ? 'Downloading… {n} of 5 books' : 'Download the Chumash for offline use', {'n': d.have.length})),
      subtitle: Text(context.tr(d.failed ? 'Download failed. Check your connection and try again.' : 'Downloads from Sefaria once, then works offline.')),
      trailing: d.busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
      onTap: d.busy ? null : () => ref.read(chumashDownloadProvider.notifier).downloadAll().catchError((_) {}),
    );
  }
}

/// The year at a glance: every parsha's seven aliyot, filled in as they're
/// done. Tap a square to check it off or clear it, or a parsha to read it.
class ShnayimMikraProgressScreen extends ConsumerStatefulWidget {
  final int? year;
  const ShnayimMikraProgressScreen({super.key, this.year});

  @override
  ConsumerState<ShnayimMikraProgressScreen> createState() => _ProgressState();
}

class _ProgressState extends ConsumerState<ShnayimMikraProgressScreen> {
  int? _year;

  @override
  Widget build(BuildContext context) {
    final week = _thisWeek(ref);
    final il = ref.watch(settingsProvider.select((s) => s.location.il));
    final year = _year ?? widget.year ?? week?.shabbat.getFullYear() ?? ref.watch(todaySnapshotProvider).hdate.getFullYear();
    final done = ref.watch(shnayimMikraProgressProvider)[year] ?? const {};
    final progress = ref.read(shnayimMikraProgressProvider.notifier);
    final parshiyot = parshiyotOfYear(year, il);
    final theme = Theme.of(context);
    final heUi = context.uiLanguage != UiLanguage.en;
    var aliyot = 0, whole = 0;
    for (final (r, _) in parshiyot) {
      final n = [for (var a = 1; a <= 7; a++) if (done.contains(ShnayimMikraProgress.entry(r.parsha.join('-'), a))) a].length;
      aliyot += n;
      if (n == 7) whole++;
    }
    final thisWeek = week != null && week.shabbat.getFullYear() == year ? week.reading.parsha.join('-') : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Shnayim Mikra · {year}', {'year': heUi ? gematriya(year % 1000) : '$year'})),
        actions: [
          IconButton(tooltip: context.tr('Previous'), icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _year = year - 1)),
          IconButton(tooltip: context.tr('Next'), icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _year = year + 1)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 32), children: [
        Card(
          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(context.tr('{done} of {total} aliyot · {whole} of {parshiyot} parshiyot',
                  {'done': aliyot, 'total': parshiyot.length * 7, 'whole': whole, 'parshiyot': parshiyot.length}),
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: parshiyot.isEmpty ? 0 : aliyot / (parshiyot.length * 7)),
              const SizedBox(height: 6),
              Text(context.tr('Tap a square to check it off, or a parsha to read it.'), style: theme.textTheme.bodySmall),
            ]),
          ),
        ),
        for (final (r, shabbat) in parshiyot)
          _ParshaRow(
            reading: r,
            shabbat: shabbat,
            current: r.parsha.join('-') == thisWeek,
            done: (a) => done.contains(ShnayimMikraProgress.entry(r.parsha.join('-'), a)),
            onToggle: (a) => progress.toggle(year, r.parsha.join('-'), a),
            onOpen: () => context.push(Uri(path: '/torah/shnayim-mikra', queryParameters: {'parsha': r.parsha.join('-'), 'year': '$year'}).toString()),
          ),
      ]),
    );
  }
}

class _ParshaRow extends StatelessWidget {
  final ParshaReading reading;
  final HDate shabbat;
  final bool current;
  final bool Function(int aliyah) done;
  final void Function(int aliyah) onToggle;
  final VoidCallback onOpen;
  const _ParshaRow(
      {required this.reading, required this.shabbat, required this.current, required this.done, required this.onToggle, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(renderParshaName(reading.parsha, context.hebcalLocale),
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: current ? FontWeight.w700 : null), overflow: TextOverflow.ellipsis),
              Text(formatPlainDate(shabbat.plainDate(), weekday: false, year: false),
                  style: theme.textTheme.bodySmall?.copyWith(color: c.outline)),
            ]),
          ),
          for (var a = 1; a <= 7; a++)
            Semantics(
              label: context.tr('Aliyah {n}', {'n': a}),
              checked: done(a),
              child: InkWell(
                onTap: () => onToggle(a),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: done(a) ? c.primary : c.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                    border: current ? Border.all(color: c.primary) : null,
                  ),
                  child: done(a) ? Icon(Icons.check, size: 16, color: c.onPrimary) : null,
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// The Home card: this week's parsha, today's aliyah and the week so far,
/// with a button to check today's off.
void registerShnayimMikraCard(CardRegistry r) => r.register(CardType(
      type: 'shnayimMikra',
      title: 'Shnayim Mikra',
      description: "This week's parsha, an aliyah a day, and your progress",
      icon: Icons.auto_stories,
      defaultSpan: 2,
      build: (c, ref, cfg) => const _ShnayimMikraCard(),
    ));

class _ShnayimMikraCard extends ConsumerWidget {
  const _ShnayimMikraCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = _thisWeek(ref);
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    if (week == null) {
      return CardFrame(title: context.tr('Shnayim Mikra'), icon: Icons.auto_stories, child: Text(context.tr('No reading today')));
    }
    final name = week.reading.parsha.join('-');
    final year = week.shabbat.getFullYear();
    final done = ref.watch(shnayimMikraProgressProvider)[year] ?? const {};
    bool isDone(int a) => done.contains(ShnayimMikraProgress.entry(name, a));
    return CardFrame(
      title: context.tr('Shnayim Mikra'),
      icon: Icons.auto_stories,
      onTap: () => context.push('/torah/shnayim-mikra'),
      trailing: IconButton(
        tooltip: context.tr(isDone(week.aliyah) ? 'Aliyah {n} done' : 'Mark aliyah {n} done', {'n': week.aliyah}),
        icon: Icon(isDone(week.aliyah) ? Icons.check_circle : Icons.check_circle_outline, color: c.primary),
        onPressed: () => ref.read(shnayimMikraProgressProvider.notifier).toggle(year, name, week.aliyah),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(renderParshaName(week.reading.parsha, context.hebcalLocale), style: theme.textTheme.titleMedium),
        Text('${context.tr('Aliyah {n}', {'n': week.aliyah})} · ${_day(context, week.aliyah)}', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 10),
        // The week: one square per aliyah, filled when done, today's ringed.
        Row(children: [
          for (var a = 1; a <= 7; a++)
            Container(
              width: 20,
              height: 20,
              margin: const EdgeInsetsDirectional.only(end: 4),
              decoration: BoxDecoration(
                color: isDone(a) ? c.primary : c.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
                border: a == week.aliyah ? Border.all(color: c.primary, width: 2) : null,
              ),
              child: isDone(a) ? Icon(Icons.check, size: 14, color: c.onPrimary) : null,
            ),
          const SizedBox(width: 6),
          Text(context.tr('{n} of 7 this week', {'n': [for (var a = 1; a <= 7; a++) if (isDone(a)) a].length}),
              style: theme.textTheme.bodySmall?.copyWith(color: c.outline)),
        ]),
      ]),
    );
  }
}
