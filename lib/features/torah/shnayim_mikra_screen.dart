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
import '../../core/typeset/typeset.dart';
import '../home/today.dart';
import '../settings/font_gallery_screen.dart';
import 'shnayim_mikra.dart';
import 'torah_library.dart';
import 'torah_settings.dart';

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
      child: ListTile(
        leading: Icon(doneToday ? Icons.check_circle : Icons.auto_stories, color: theme.colorScheme.primary),
        title: Text(context.tr('Shnayim Mikra')),
        subtitle: Text(subtitle ?? context.tr('No reading today')),
        isThreeLine: subtitle != null,
        trailing: IconButton(
          tooltip: context.tr('Your year'),
          icon: const Icon(Icons.grid_view),
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
        _ModeMenu(),
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
          book: reading.book,
          range: reading.aliyot[aliyah - 1],
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
            if (ref.watch(shnayimMikraSettingsProvider.select((x) => x.needsRashi)))
              Text(
                  switch (ref.watch(rashiBookProvider(reading.book)).value?.enCredit) {
                    final credit? when credit.isNotEmpty => context.tr('Rashi from Sefaria. English: {credit}.', {'credit': credit}),
                    _ => context.tr('Rashi from Sefaria.'),
                  },
                  textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
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

/// The verses read before the next part, by [MikraMode]: each verse, each
/// of the Torah's paragraphs, or the whole aliyah. Books kept before
/// paragraphs were have none marked, so they're read a verse at a time.
List<List<MikraVerse>> mikraUnits(List<MikraVerse> verses, MikraMode mode) {
  final paragraphs = verses.any((v) => v.para.isNotEmpty);
  switch (mode) {
    case MikraMode.aliyah when verses.isNotEmpty:
      return [verses];
    case MikraMode.paragraph when paragraphs:
      final units = <List<MikraVerse>>[];
      var unit = <MikraVerse>[];
      for (final v in verses) {
        unit.add(v);
        if (v.para.isNotEmpty) {
          units.add(unit);
          unit = [];
        }
      }
      return [...units, if (unit.isNotEmpty) unit];
    default:
      return [for (final v in verses) [v]];
  }
}

/// A verse's text with its ketiv and keri as a Chumash prints them: the
/// keri (Sefaria's [brackets]) read as the text, the ketiv ((parentheses))
/// small and light beside it.
List<InlineSpan> mikraSpans(String text, TextStyle ketiv) {
  final spans = <InlineSpan>[];
  var at = 0;
  for (final m in RegExp(r'\(([^)]*)\)|\[([^\]]*)\]').allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    spans.add(m[1] != null ? TextSpan(text: m[1], style: ketiv) : TextSpan(text: m[2]));
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}

/// One aliyah, read by [MikraMode], in the siddur's layout and type
/// settings and set as the siddur sets its text.
class _Aliyah extends ConsumerWidget {
  final MikraText text;

  /// The book of the Torah, 1 = Bereshit, for Rashi.
  final int book;
  final (Verse, Verse) range;
  final Widget footer;
  const _Aliyah({super.key, required this.text, required this.book, required this.range, required this.footer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(mikraStyleProvider);
    final sm = ref.watch(shnayimMikraSettingsProvider);
    final rashi = sm.needsRashi ? ref.watch(rashiBookProvider(book)) : null;
    final theme = Theme.of(context);
    int key(Verse v) => v.chapter * 1000 + v.verse;
    final verses = [for (final v in text.verses) if (key(v.at) >= key(range.$1) && key(v.at) <= key(range.$2)) v];
    final width = MediaQuery.sizeOf(context).width;
    final layout = switch (s.layout) {
      TextLayout.sideBySide when width > 700 => TextLayout.sideBySide,
      TextLayout.hebrewOnly => TextLayout.hebrewOnly,
      _ => TextLayout.interleaved,
    };
    // The siddur's typesetting, at Shnayim Mikra's sizes.
    final ts = TypeScale.of(ref.watch(settingsProvider), hebrewSize: 22 * s.textScale, latinSize: 17 * s.textScale);
    final heStyle = TextStyle(
        fontFamily: hebrewFamilyFor(s.hebrewFont, teamim: s.showTeamim, nikud: s.showNikud),
        fontSize: 22 * s.textScale,
        height: ts.leading(ParagraphRole.body, hebrew: true, marks: s.showTeamim),
        color: theme.colorScheme.onSurface);
    // Onkelos has nikud but no te'amim.
    final targumStyle = heStyle.copyWith(
        fontFamily: hebrewFamilyFor(s.hebrewFont, teamim: false, nikud: s.showNikud),
        fontSize: 19 * s.textScale,
        height: ts.leading(ParagraphRole.body, hebrew: true),
        color: theme.colorScheme.onSurfaceVariant);
    // Rashi in Rashi script, or in the Hebrew font without te'amim.
    final rashiStyle = heStyle.copyWith(
        fontFamily: sm.rashiScript ? 'NotoRashiHebrew' : hebrewFamilyFor(s.hebrewFont, teamim: false, nikud: sm.rashiNikud),
        fontSize: 17 * s.textScale,
        height: 1.6,
        color: theme.colorScheme.onSurfaceVariant);
    final enStyle = TextStyle(
        fontFamily: s.latinFont, fontSize: 17 * s.textScale, height: ts.leading(ParagraphRole.body, hebrew: false), color: theme.colorScheme.onSurface);
    final rashiEnStyle = enStyle.copyWith(fontSize: 15 * s.textScale, color: theme.colorScheme.onSurfaceVariant);
    final mark = TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 14 * s.textScale);
    final ketiv = TextStyle(color: theme.colorScheme.outline, fontSize: 15 * s.textScale);
    final single = sm.mode == MikraMode.verse || mikraUnits(verses, sm.mode).every((u) => u.length == 1);

    Widget paragraph(List<InlineSpan> spans, TextStyle style, TextDirection dir) => ts.print
        ? TypesetParagraph(text: TextSpan(style: style, children: spans), textDirection: dir, em: style.fontSize!, align: ts.align(ParagraphRole.body))
        : Text.rich(TextSpan(children: spans), textDirection: dir, style: style);
    Widget stack(Iterable<Widget> ws, {double gap = 4}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, w) in ws.indexed) i == 0 ? w : Padding(padding: EdgeInsets.only(top: gap), child: w),
        ]);

    // A verse's number: chapter and verse where a chapter starts or a
    // passage opens, the verse alone within one.
    String number(Verse v, bool first, {required bool hebrew}) => hebrew
        ? (first || v.verse == 1 ? '${gematriya(v.chapter)}:${gematriya(v.verse)} ' : '${gematriya(v.verse)} ')
        : (first || v.verse == 1 ? '${v.chapter}:${v.verse} ' : '${v.verse} ');

    /// [unit]'s verses as running text, a paragraph for each of the
    /// Torah's paragraphs in it.
    Widget running(List<MikraVerse> unit, String Function(MikraVerse) of, TextStyle style,
        {required bool hebrew, String? label, bool kriKtiv = false}) {
      final paragraphs = <List<InlineSpan>>[];
      var spans = <InlineSpan>[if (label != null) TextSpan(text: label, style: mark)];
      for (final (i, v) in unit.indexed) {
        final t = of(v);
        if (t.isEmpty) continue;
        spans
          ..add(TextSpan(text: number(v.at, i == 0, hebrew: hebrew), style: mark))
          ..addAll(kriKtiv ? mikraSpans(t, ketiv) : [TextSpan(text: t)])
          ..add(const TextSpan(text: ' '));
        if (v.para.isNotEmpty && i < unit.length - 1) {
          paragraphs.add(spans);
          spans = [];
        }
      }
      if (spans.isNotEmpty) paragraphs.add(spans);
      return stack([for (final p in paragraphs) paragraph(p, style, hebrew ? TextDirection.rtl : TextDirection.ltr)], gap: ts.line * 0.3);
    }

    Widget? comments(List<MikraVerse> unit, {required bool hebrew, required bool labelled}) {
      final rows = <Widget>[];
      for (final v in unit) {
        final list = hebrew ? rashi?.value?.verses[v.at]?.he : rashi?.value?.verses[v.at]?.en;
        for (final (i, r) in (list ?? const <RashiComment>[]).indexed) {
          rows.add(paragraph([
            if (rows.isEmpty && labelled) TextSpan(text: hebrew ? 'רש״י ' : 'Rashi ', style: mark),
            // Which verse, where there are several.
            if (i == 0 && unit.length > 1) TextSpan(text: number(v.at, true, hebrew: hebrew), style: mark),
            if (r.dh.isNotEmpty)
              TextSpan(
                  text: '${hebrew ? hebrewMarks(r.dh, teamim: false, nikud: sm.rashiNikud) : r.dh} ',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: hebrew ? hebrewMarks(r.text, teamim: false, nikud: sm.rashiNikud) : r.text),
          ], hebrew ? rashiStyle : rashiEnStyle, hebrew ? TextDirection.rtl : TextDirection.ltr));
        }
      }
      return rows.isEmpty ? null : stack(rows);
    }

    Widget? part(MikraPart p, List<MikraVerse> unit) {
      // One verse at a time keeps its labels inline; longer passages are
      // headed instead (see [_partHeading]).
      final labelled = single;
      String marks(String he) => hebrewMarks(he, teamim: s.showTeamim, nikud: s.showNikud);
      return switch (p) {
        MikraPart.verse || MikraPart.verseAgain => running(unit, (v) => marks(v.he), heStyle, hebrew: true, kriKtiv: true),
        MikraPart.targum when unit.any((v) => v.targum.isNotEmpty) => running(
            unit, (v) => hebrewMarks(v.targum, teamim: false, nikud: s.showNikud), targumStyle,
            hebrew: true, label: labelled ? 'ת״א ' : null),
        MikraPart.rashi => comments(unit, hebrew: true, labelled: labelled),
        MikraPart.english when unit.any((v) => v.en.isNotEmpty) => running(unit, (v) => v.en, enStyle, hebrew: false),
        MikraPart.rashiEnglish => comments(unit, hebrew: false, labelled: labelled),
        _ => null,
      };
    }

    Widget unitView(List<MikraVerse> unit) {
      // The parts turned on, in the reader's order; English ones only where
      // the layout shows English.
      final parts = [
        for (final p in sm.order)
          if (sm.shows(p) && (!p.inEnglish || layout != TextLayout.hebrewOnly))
            if (part(p, unit) case final w?) (p, w),
      ];
      Iterable<Widget> headed(Iterable<(MikraPart, Widget)> ps) => [
            for (final (p, w) in ps)
              if (single) w else stack([_partHeading(context, p, ts), w], gap: ts.line * 0.25),
          ];
      final gap = single ? 4.0 : ts.line * 0.6;
      final english = [for (final x in parts) if (x.$1.inEnglish) x];
      final hebrew = [for (final x in parts) if (!x.$1.inEnglish) x];
      // Side by side: English on the left and Hebrew on the right, each in
      // the chosen order.
      return layout == TextLayout.sideBySide && english.isNotEmpty
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: stack(headed(english), gap: gap)),
              const SizedBox(width: 24),
              Expanded(child: stack(headed(hebrew), gap: gap)),
            ])
          : stack(headed(parts), gap: gap);
    }

    final units = mikraUnits(verses, sm.mode);
    // While Rashi downloads, or if he couldn't, the verses show without him.
    final rashiNote = switch (rashi) {
      AsyncLoading() => ListTile(
          dense: true,
          leading: const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          title: Text(context.tr('Downloading Rashi from Sefaria, once. After this it works offline.')),
        ),
      AsyncError() => ListTile(
          dense: true,
          leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
          title: Text(context.tr('Download failed. Check your connection and try again.')),
          trailing: TextButton(onPressed: () => ref.invalidate(rashiBookProvider(book)), child: Text(context.tr('Retry'))),
        ),
      _ => null,
    };
    final gutter = ts.gutter(width, min: 16, sideBySide: layout == TextLayout.sideBySide);
    return Column(children: [
      ?rashiNote,
      Expanded(
        child: ListView.builder(
          padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32 + MediaQuery.paddingOf(context).bottom),
          itemCount: units.length + 1,
          itemBuilder: (context, i) => i == units.length
              ? footer
              : Padding(
                  padding: EdgeInsets.only(bottom: single ? 14 : 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    // The Torah's paragraphs are set apart with an ornament.
                    if (!single && i > 0) SectionOrnament(small: true, height: ts.sectionGap),
                    unitView(units[i]),
                    if (!single) SizedBox(height: ts.line * 0.4),
                  ]),
                ),
        ),
      ),
    ]);
  }
}

/// What a part of a passage is, set between rules above it.
Widget _partHeading(BuildContext context, MikraPart p, TypeScale ts) {
  final color = Theme.of(context).colorScheme.outline;
  final he = context.uiLanguage != UiLanguage.en;
  final label = switch (p) {
    MikraPart.verse => he ? 'מקרא' : context.tr('Verse'),
    MikraPart.verseAgain => he ? 'מקרא · שנית' : context.tr('Verse again'),
    MikraPart.targum => he ? 'תרגום אונקלוס' : context.tr('Targum Onkelos'),
    MikraPart.rashi => he ? 'רש״י' : context.tr('Rashi'),
    MikraPart.english => context.tr('English'),
    MikraPart.rashiEnglish => context.tr('Rashi in English'),
  };
  return RuledLabel(color: color, child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, letterSpacing: 0.4)));
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
          SheetLabel(context.tr('Read')),
          ChoiceBar<MikraMode>(
            options: [for (final m in MikraMode.values) (m, context.tr(_modeLabel(m)), _modeIcon(m))],
            selected: sm.mode,
            onChanged: (v) => own((x) => x.copyWith(mode: v)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(context.tr(_modeHint(sm.mode)), style: theme.textTheme.bodySmall),
          ),
          SheetLabel(context.tr('What to read')),
          Row(children: [
            Expanded(child: Text(context.tr('Choose what to show. Drag to reorder.'), style: theme.textTheme.bodySmall)),
            TextButton(
                onPressed: () => own((x) => x.copyWith(order: MikraPart.values)),
                child: Text(context.tr('Reset'))),
          ]),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (a, b) => own((x) {
              final order = [...x.order];
              if (b > a) b--;
              order.insert(b, order.removeAt(a));
              return x.copyWith(order: order);
            }),
            children: [
              for (final (i, p) in sm.order.indexed)
                ListTile(
                  key: ValueKey(p),
                  contentPadding: EdgeInsets.zero,
                  leading: Checkbox(
                    value: sm.shows(p),
                    // The verse itself is always there.
                    onChanged: p == MikraPart.verse ? null : (v) => own((x) => x.withPart(p, v ?? false)),
                  ),
                  title: Text(context.tr(_partLabel(p))),
                  subtitle: switch (p) {
                    MikraPart.rashi || MikraPart.rashiEnglish when !sm.needsRashi => Text(context.tr('Downloads from Sefaria once.')),
                    _ when p.inEnglish && style.layout == TextLayout.hebrewOnly => Text(context.tr('Not shown in the Hebrew layout')),
                    _ => null,
                  },
                  trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                ),
            ],
          ),
          if (sm.showRashi)
            toggle('Rashi script', sm.rashiScript, (v) => own((x) => x.copyWith(rashiScript: v)),
                subtitle: 'Off to show Rashi in the Hebrew font'),
          if (sm.showRashi)
            toggle('Rashi with nikud', sm.rashiNikud, (v) => own((x) => x.copyWith(rashiNikud: v)),
                subtitle: 'Where Sefaria has Rashi with vowels'),
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
          ],
          SheetLabel(context.tr('Offline')),
          const _OfflineStatus(),
          if (sm.needsRashi || ref.watch(rashiDownloadProvider).have.isNotEmpty) const _RashiOfflineStatus(),
        ]),
      ),
    );
  }
}

String _modeLabel(MikraMode m) => switch (m) {
      MikraMode.verse => 'Verse by verse',
      MikraMode.paragraph => 'By paragraph',
      MikraMode.aliyah => 'Whole aliyah',
    };

IconData _modeIcon(MikraMode m) => switch (m) {
      MikraMode.verse => Icons.short_text,
      MikraMode.paragraph => Icons.subject,
      MikraMode.aliyah => Icons.article_outlined,
    };

String _modeHint(MikraMode m) => switch (m) {
      MikraMode.verse => 'Each verse, then again, then its Targum.',
      MikraMode.paragraph => "Each of the Torah's paragraphs, then again, then its Targum.",
      MikraMode.aliyah => 'The whole aliyah, then the whole aliyah again, then its Targum.',
    };

/// Switches how much is read at a time, from the reader's bar.
class _ModeMenu extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(shnayimMikraSettingsProvider.select((x) => x.mode));
    return PopupMenuButton<MikraMode>(
      tooltip: context.tr('Read'),
      icon: Icon(_modeIcon(mode)),
      initialValue: mode,
      onSelected: (m) => ref.read(shnayimMikraSettingsProvider.notifier).update((x) => x.copyWith(mode: m)),
      itemBuilder: (context) => [
        for (final m in MikraMode.values)
          CheckedPopupMenuItem(
            value: m,
            checked: m == mode,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr(_modeLabel(m))),
              subtitle: Text(context.tr(_modeHint(m))),
            ),
          ),
      ],
    );
  }
}

String _partLabel(MikraPart p) => switch (p) {
      MikraPart.verse => 'Verse',
      MikraPart.verseAgain => 'Verse again',
      MikraPart.targum => 'Targum Onkelos',
      MikraPart.rashi => 'Rashi',
      MikraPart.english => 'English',
      MikraPart.rashiEnglish => 'Rashi in English',
    };

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

/// Whether Rashi is downloaded, with a button to download him now.
class _RashiOfflineStatus extends ConsumerWidget {
  const _RashiOfflineStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(rashiDownloadProvider);
    final theme = Theme.of(context);
    if (d.have.length == 5) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.offline_pin, color: theme.colorScheme.primary),
        title: Text(context.tr('Rashi available offline · {size}', {'size': formatBytes(d.bytes)})),
        subtitle: Text(context.tr('Rashi on all five books, in Hebrew and English.')),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.download),
      title: Text(context.tr(d.busy ? 'Downloading Rashi… {n} of 5 books' : 'Download Rashi for offline use', {'n': d.have.length})),
      subtitle: Text(context.tr(d.failed ? 'Download failed. Check your connection and try again.' : 'Downloads from Sefaria once, then works offline.')),
      trailing: d.busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
      onTap: d.busy ? null : () => ref.read(rashiDownloadProvider.notifier).downloadAll().catchError((_) {}),
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

/// Today's Shnayim Mikra in the Home screen's date card: the aliyah, the
/// week so far, and a button to check today's off. Tap to read.
class ShnayimMikraLine extends ConsumerWidget {
  const ShnayimMikraLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = _thisWeek(ref);
    if (week == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final name = week.reading.parsha.join('-');
    final year = week.shabbat.getFullYear();
    final done = ref.watch(shnayimMikraProgressProvider)[year] ?? const {};
    bool isDone(int a) => done.contains(ShnayimMikraProgress.entry(name, a));
    return InkWell(
      onTap: () => context.push('/torah/shnayim-mikra'),
      borderRadius: BorderRadius.circular(8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${context.tr('Shnayim Mikra')} · ${context.tr('Aliyah {n}', {'n': week.aliyah})}', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            // The week: a dot per aliyah, filled when done.
            Row(children: [
              for (var a = 1; a <= 7; a++)
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsetsDirectional.only(end: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone(a) ? c.primary : c.surfaceContainerHighest,
                    border: Border.all(color: a <= week.aliyah ? c.primary.withValues(alpha: 0.5) : c.outlineVariant),
                  ),
                ),
            ]),
          ]),
        ),
        IconButton(
          tooltip: context.tr(isDone(week.aliyah) ? 'Aliyah {n} done' : 'Mark aliyah {n} done', {'n': week.aliyah}),
          icon: Icon(isDone(week.aliyah) ? Icons.check_circle : Icons.check_circle_outline, color: c.primary),
          onPressed: () => ref.read(shnayimMikraProgressProvider.notifier).toggle(year, name, week.aliyah),
        ),
      ]),
    );
  }
}
