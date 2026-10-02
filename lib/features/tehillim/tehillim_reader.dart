import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/adaptive.dart';
import '../../core/analytics.dart';
import '../../core/fonts.dart';
import '../../core/hebrew_text.dart';
import '../../core/html_text.dart';
import '../../core/l10n.dart';
import '../../core/text_report.dart';
import '../../core/page_swipe.dart';
import '../../core/settings.dart';
import '../../core/split_row.dart';
import '../../core/theme.dart';
import '../../core/typeset/typeset.dart';
import '../settings/font_gallery_screen.dart';
import '../settings/typesetting_options.dart';
import 'tehillim_data.dart';
import 'tehillim_progress.dart';

String tehillimReadPath(Portion p) => Uri(path: '/siddur/tehillim/read', queryParameters: {
      'p': p.encoded,
      'en': p.titleEn,
      'he': p.titleHe,
    }).toString();

/// Reads a [Portion] of Tehillim: Hebrew with te'amim, optional English,
/// verse numbers, per-chapter "read" marks and cycle progress.
class TehillimReaderScreen extends ConsumerStatefulWidget {
  final Portion portion;
  const TehillimReaderScreen({super.key, required this.portion});

  @override
  ConsumerState<TehillimReaderScreen> createState() => _TehillimReaderScreenState();
}

class _TehillimReaderScreenState extends ConsumerState<TehillimReaderScreen> {
  /// Text is selected: sideways drags move its handles, so swiping
  /// doesn't turn the page.
  bool _selected = false;
  String _selectedText = '';

  void _selectionChanged(SelectedContent? c) {
    _selectedText = c?.plainText ?? '';
    final selected = _selectedText.isNotEmpty;
    if (selected != _selected) setState(() => _selected = selected);
  }

  @override
  void initState() {
    super.initState();
    final first = widget.portion.passages.firstOrNull;
    if (first != null) Future.microtask(() => ref.read(tehillimProgressProvider.notifier).opened(first.chapter));
    analytics.event('text_open', _text);
  }

  final _opened = Stopwatch()..start();

  /// What's being read, for analytics.
  Map<String, Object?> get _text => {
        'reader': 'tehillim',
        'portion': widget.portion.titleEn,
        'chapters': widget.portion.rangeLabel,
        'count': widget.portion.passages.length,
      };

  @override
  void dispose() {
    analytics.event('text_read', {..._text, 'seconds': _opened.elapsed.inSeconds});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(tehillimProvider);
    final p = widget.portion;
    final hebrewUi = context.uiLanguage != UiLanguage.en;
    final single = p.passages.length == 1 && p.passages.first.whole ? p.passages.first.chapter : null;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(hebrewUi ? p.titleHe : context.term(p.titleEn), overflow: TextOverflow.ellipsis),
          Text('${context.tr('Tehillim')} ${p.rangeLabel}', style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [
          IconButton(
            tooltip: context.tr('Text settings'),
            icon: const Icon(Icons.text_fields),
            onPressed: () => showTehillimSettings(context),
          ),
        ],
      ),
      body: PageSwipe(
        onNext: _turn(single, 1),
        onPrevious: _turn(single, -1),
        child: data.when(
          loading: adaptiveProgress,
          error: (e, _) => Center(child: Text('$e')),
          data: (t) => _body(context, t),
        ),
      ),
    );
  }

  /// Swiping from a single psalm to the one [by] away, if there is one.
  VoidCallback? _turn(int? chapter, int by) {
    if (_selected || chapter == null || chapter + by < 1 || chapter + by > 150) return null;
    return () {
      analytics.event('page_swipe', {'reader': 'tehillim', 'way': by > 0 ? 'next' : 'previous'});
      Router.neglect(context, () => context.pushReplacement(tehillimReadPath(chapterPortion(chapter + by))));
    };
  }

  Widget _body(BuildContext context, Tehillim t) {
    final p = widget.portion;
    final s = ref.watch(settingsProvider);
    // Verses flow as a paragraph only when a single language is shown.
    final flow = !ref.watch(tehillimProgressProvider.select((x) => x.versePerLine)) && s.showHebrewText != s.showTranslationText;
    final wide = MediaQuery.sizeOf(context).width > 700;
    final rows = <Widget Function(BuildContext)>[];
    int? lastBook;
    int? lastChapter;
    for (final ps in p.passages) {
      final book = bookOf(ps.chapter);
      final newBook = book != lastBook;
      if (newBook) rows.add((c) => _BookHeader(book));
      lastBook = book;
      // Between psalms, an ornament (the book header already marks a
      // new book).
      final ornament = rows.isNotEmpty && !newBook;
      if (ps.chapter != lastChapter) rows.add((c) => _ChapterHeader(ps.chapter, ornament: ornament));
      lastChapter = ps.chapter;
      final letter = stanzaLetter(ps);
      if (letter.isNotEmpty) rows.add((c) => _StanzaHeader(letter));
      final to = (ps.to ?? t.verses(ps.chapter)).clamp(1, t.verses(ps.chapter));
      if (flow) {
        final (c, from) = (ps.chapter, ps.from);
        rows.add((ctx) => _Verse(
              chapter: c,
              verse: from,
              he: '',
              en: '',
              wide: wide,
              flow: [for (var v = from; v <= to; v++) (v, t.he[c - 1][v - 1], t.en[c - 1][v - 1])],
            ));
        continue;
      }
      for (var v = ps.from; v <= to; v++) {
        final (c, vv) = (ps.chapter, v);
        rows.add((ctx) => _Verse(chapter: c, verse: vv, he: t.he[c - 1][vv - 1], en: t.en[c - 1][vv - 1], wide: wide));
      }
    }
    rows.add((c) => _Footer(portion: p));
    final side = TypeScale.of(s, hebrewSize: 24 * s.textScale)
        .gutter(MediaQuery.sizeOf(context).width, min: wide ? 48 : 16, sideBySide: wide && s.layout == TextLayout.sideBySide);
    return SelectionArea(
      onSelectionChanged: _selectionChanged,
      contextMenuBuilder: (context, state) => textReportMenu(context, state,
          selectedText: _selectedText, location: 'Tehillim / ${p.titleEn} / ${p.rangeLabel}'),
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(side, 8, side, 96),
        itemCount: rows.length,
        itemBuilder: (c, i) => rows[i](c),
      ),
    );
  }
}

class _BookHeader extends StatelessWidget {
  final int book;
  const _BookHeader(this.book);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = bookPortion(book);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Row(children: [
        Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('${b.titleHe} · ${context.tr(b.titleEn)}', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.outline)),
        ),
        Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
      ]),
    );
  }
}

class _ChapterHeader extends ConsumerWidget {
  final int chapter;

  /// Set off from the psalm before it (print-style typesetting).
  final bool ornament;
  const _ChapterHeader(this.chapter, {this.ornament = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final read = ref.watch(tehillimProgressProvider.select((x) => x.read.contains(chapter)));
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final header = Padding(
      padding: EdgeInsets.only(top: s.typesetting && ornament ? 4 : 20, bottom: 6),
      child: Row(children: [
        IconButton(
          tooltip: context.tr(read ? 'Mark as unread' : 'Mark as read'),
          icon: Icon(read ? Icons.check_circle : Icons.radio_button_unchecked, color: read ? colors.todayBar : theme.colorScheme.outline),
          onPressed: () {
            final n = ref.read(tehillimProgressProvider.notifier);
            if (read) {
              n.unmark(chapter);
            } else if (n.markRead([chapter])) {
              _celebrate(context);
            }
          },
        ),
        Expanded(
          child: SplitRow(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text(context.tr('Psalm {n}', {'n': chapter}),
                style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
            Text('מזמור ${hebrewNumeral(chapter)}',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontFamily: s.hebrewFont, fontSize: 24 * s.textScale, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
          ]),
        ),
      ]),
    );
    if (!s.typesetting || !ornament) return header;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.only(top: 16), child: SectionOrnament(height: 24 * s.textScale, color: theme.colorScheme.outline)),
      header,
    ]);
  }
}

class _StanzaHeader extends ConsumerWidget {
  final String letter;
  const _StanzaHeader(this.letter);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Center(
        child: Text(letter,
            style: TextStyle(fontFamily: s.hebrewFont, fontSize: 30 * s.textScale, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
      ),
    );
  }
}

class _Verse extends ConsumerWidget {
  final int chapter;
  final int verse;
  final String he;
  final String en;
  final bool wide;

  /// Several verses rendered as one flowing paragraph: (number, he, en).
  final List<(int, String, String)>? flow;
  const _Verse({required this.chapter, required this.verse, required this.he, required this.en, required this.wide, this.flow});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final t = ref.watch(tehillimProgressProvider);
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final showHe = s.showHebrewText;
    final showEn = s.showTranslationText;

    final verses = flow ?? [(verse, he, en)];
    final ts = TypeScale.of(s, hebrewSize: 24 * s.textScale);
    // Plain setting: as before, a flowing paragraph justified, single
    // verses ragged. Print: the type scale decides, and each psalm opens
    // with a large first word.
    final align = ts.print ? ts.align(ParagraphRole.body) : (flow != null ? ParagraphAlign.justify : ParagraphAlign.start);
    final opens = ts.print && verses.first.$1 == 1;
    Widget paragraph(List<InlineSpan> spans, TextDirection dir, TextStyle base, ParagraphAlign align) => ts.print
        ? TypesetParagraph(text: TextSpan(children: spans), textDirection: dir, em: base.fontSize!, align: align)
        : Text.rich(TextSpan(children: spans),
            textDirection: dir, textAlign: align == ParagraphAlign.justify ? TextAlign.justify : TextAlign.start);
    Widget? heW;
    if (showHe) {
      final htmls = [for (final v in verses) hebrewMarks(prepareVerse(v.$2, ketiv: t.ketiv), teamim: s.showTeamim, nikud: s.showNikud)];
      final all = htmls.join();
      final teamim = hasTeamim(all);
      final base = TextStyle(
        fontFamily: hebrewFamilyFor(s.hebrewFont, teamim: teamim, nikud: hasNikud(all)),
        fontSize: 24 * s.textScale,
        height: ts.print ? ts.leading(ParagraphRole.body, hebrew: true, marks: teamim) : 1.75,
        color: theme.colorScheme.onSurface,
      );
      final parser = SefariaHtml(base);
      heW = paragraph([
        for (var i = 0; i < verses.length; i++) ...[
          if (t.verseNumbers)
            TextSpan(
              text: '${hebrewNumeral(verses[i].$1).replaceAll(RegExp('[׳״]'), '')} ',
              style: base.copyWith(fontSize: base.fontSize! * 0.6, color: colors.marker, fontWeight: FontWeight.w700),
            ),
          ...(i == 0 && opens
              ? enlargeOpening(parser.parse(htmls[i]), ts.openingWord, lineHeight: base.height!)
              : parser.parse(htmls[i])),
          if (i < verses.length - 1) TextSpan(text: ' ', style: base),
        ],
      ], TextDirection.rtl, base, align);
    }
    Widget? enW;
    if (showEn) {
      final base = TextStyle(
          fontFamily: s.latinFont, fontSize: 16 * s.textScale, height: ts.leading(ParagraphRole.body, hebrew: false), color: theme.colorScheme.onSurface);
      final parser = SefariaHtml(base);
      enW = paragraph([
        for (var i = 0; i < verses.length; i++) ...[
          if (t.verseNumbers)
            TextSpan(text: '${verses[i].$1} ', style: base.copyWith(fontSize: base.fontSize! * 0.75, color: colors.marker, fontWeight: FontWeight.w700)),
          ...parser.parse(verses[i].$3),
          if (i < verses.length - 1) TextSpan(text: ' ', style: base),
        ],
      ], TextDirection.ltr, base, ts.print ? align : ParagraphAlign.start);
    }
    final Widget body;
    if (heW != null && enW != null && s.layout == TextLayout.sideBySide && wide) {
      body = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: enW),
        const SizedBox(width: 24),
        Expanded(child: heW),
      ]);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ?heW,
        if (heW != null && enW != null) const SizedBox(height: 2),
        ?enW,
      ]);
    }
    return Padding(padding: EdgeInsets.symmetric(vertical: t.versePerLine || enW != null ? 5 : 1), child: body);
  }
}

class _Footer extends ConsumerWidget {
  final Portion portion;
  const _Footer({required this.portion});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(tehillimProgressProvider);
    final chapters = {for (final p in portion.passages) if (p.whole) p.chapter};
    final allRead = chapters.isNotEmpty && chapters.every(progress.read.contains);
    final single = portion.passages.length == 1 && portion.passages.first.whole ? portion.passages.first.chapter : null;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (chapters.isNotEmpty)
          FilledButton.icon(
            onPressed: allRead
                ? null
                : () {
                    if (ref.read(tehillimProgressProvider.notifier).markRead(chapters)) _celebrate(context);
                  },
            icon: Icon(allRead ? Icons.check : Icons.done_all),
            label: Text(context.tr(allRead ? 'Marked as read' : 'Mark all as read')),
          ),
        const SizedBox(height: 8),
        Text(
          context.tr('{n} of 150 chapters read this cycle', {'n': progress.read.length}) +
              (progress.completions > 0 ? ' · ${context.tr('{n} completions', {'n': progress.completions})}' : ''),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (single != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            if (single > 1)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Router.neglect(context, () => context.pushReplacement(tehillimReadPath(chapterPortion(single - 1)))),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(context.tr('Psalm {n}', {'n': single - 1})),
                ),
              ),
            if (single > 1 && single < 150) const SizedBox(width: 8),
            if (single < 150)
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => Router.neglect(context, () => context.pushReplacement(tehillimReadPath(chapterPortion(single + 1)))),
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(context.tr('Psalm {n}', {'n': single + 1})),
                ),
              ),
          ]),
        ],
      ]),
    );
  }
}

Portion chapterPortion(int c) => Portion('Psalm $c', 'מזמור ${hebrewNumeral(c)}', [Passage(c)]);

void _celebrate(BuildContext context) => showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.celebration, size: 40),
        title: Text(c.tr('Sefer Tehillim completed!')),
        content: Text(c.tr('All 150 chapters are read. A new cycle has begun.')),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(c.tr('Amen')))],
      ),
    );

/// Display options for Tehillim (shared text settings plus Tehillim ones).
Future<void> showTehillimSettings(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const _TehillimSettings(),
    );

class _TehillimSettings extends ConsumerWidget {
  const _TehillimSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final t = ref.watch(tehillimProgressProvider);
    final tn = ref.read(tehillimProgressProvider.notifier);
    final user = ref.watch(fontsProvider);
    final theme = Theme.of(context);
    Widget sw(String title, bool v, void Function(bool) f, [String? sub]) => SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr(title)),
          subtitle: sub == null ? null : Text(context.tr(sub)),
          value: v,
          onChanged: f,
        );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
          Text(context.tr('Text'), style: theme.textTheme.titleLarge),
          Row(children: [
            const Icon(Icons.text_decrease, size: 18),
            Expanded(
              child: Slider.adaptive(
                value: s.textScale,
                min: 0.7,
                max: 2.2,
                onChanged: (v) => n.update((x) => x.copyWith(textScale: v)),
              ),
            ),
            const Icon(Icons.text_increase, size: 18),
          ]),
          ChoiceBar<TextLayout>(
            options: [
              (TextLayout.hebrewOnly, context.tr('Hebrew'), null),
              (TextLayout.interleaved, context.tr('Bilingual'), null),
              (TextLayout.translationOnly, context.tr('English'), null),
            ],
            selected: s.layout == TextLayout.sideBySide ? TextLayout.interleaved : s.layout,
            onChanged: (v) => n.update((x) => x.copyWith(layout: v)),
          ),
          const TypesettingOptions(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.font_download_outlined),
            title: Text(context.tr('Hebrew font')),
            subtitle: Text(fontLabel(s.hebrewFont, user)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const FontGalleryScreen())),
          ),
          sw("Show te'amim (trop)", s.showTeamim, (v) => n.update((x) => x.copyWith(showTeamim: v))),
          sw('Show nikud (vowels)', s.showNikud, (v) => n.update((x) => x.copyWith(showNikud: v))),
          sw('Show ketiv', t.ketiv, (v) => tn.update((x) => x.copyWith(ketiv: v)), 'The written form beside the one that is read (qere)'),
          sw('Verse numbers', t.verseNumbers, (v) => tn.update((x) => x.copyWith(verseNumbers: v))),
          sw('One verse per line', t.versePerLine, (v) => tn.update((x) => x.copyWith(versePerLine: v))),
        ]),
      ),
    );
  }
}
