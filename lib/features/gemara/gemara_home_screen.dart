import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hebcal/hebcal.dart';

import '../../core/adaptive.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import 'daf_video.dart';
import 'gemara_data.dart';
import 'gemara_perakim.dart';
import 'gemara_settings_sheet.dart';
import 'gemara_user.dart';
import '../integrations/prayer_links.dart' show shareTorahLink;
import '../torah/torah_screen.dart' show kitzurTarget;
import 'study_book.dart';

/// The study reader's address: a unit of a book, optionally at a passage,
/// with a day's portion ([from]–[to], 0-based passages) marked.
String studyPath(String book, String unit, {int? segment, int? from, int? to}) => Uri(path: '/torah/read', queryParameters: {
      'b': book,
      'u': unit,
      if (segment != null && segment > 0) 's': '$segment',
      if (from != null) 'from': '$from',
      if (to != null) 'to': '$to',
    }).toString();

/// Where a daily learning schedule's reading for [date] opens in the app
/// (Daf Yomi, Mishnah Yomi, Kitzur Yomi, with the day's portion marked), or
/// null for schedules the app doesn't have.
String? learningPath(String key, PlainDate date, Event? ev) {
  switch (key) {
    case 'dafYomi':
      final p = dafYomiPlace(date);
      return p == null ? null : studyPath(p.book, p.unit);
    case 'mishnaYomi':
      final p = mishnahYomiPlace(date);
      return p == null ? null : studyPath(p.book, p.unit, from: p.from, to: p.to);
    case 'kitzurShulchanAruch':
      final t = ev is KitzurShulchanAruchEvent ? kitzurTarget(ev) : null;
      return t == null ? null : studyPath(kitzurId, '${t.siman}', from: t.from - 1, to: t.to == null ? null : t.to! - 1);
  }
  return null;
}

/// Today's Daf Yomi as a place in the app, or null on a day it has none.
DafPlace? dafYomiToday(PlainDate date) => switch (dafYomiPlace(date)) {
      final p? => DafPlace(p.book, p.unit),
      null => null,
    };

/// "50b", or "נ:" in a Hebrew interface.
String shortAmud(BuildContext context, String amud) {
  if (context.uiLanguage == UiLanguage.en) return amud;
  final n = amudNumber(amud)!;
  return '${gematriya((n + 1) ~/ 2)}${n.isOdd ? '.' : ':'}';
}

/// "Berakhot 2a", "berakhot 2b", "ברכות ב", "bava metzia 59" → a place.
DafPlace? parseDafQuery(String q) {
  final m = RegExp(r'^\s*(.+?)\s+(\d+)\s*([ab.:])?\s*$', caseSensitive: false).firstMatch(q);
  if (m == null) return null;
  final name = m.group(1)!.trim();
  final t = tractateNamed(name) ?? tractates.where((x) => x.he == name).firstOrNull;
  if (t == null) return null;
  final side = switch (m.group(3)) { 'b' || 'B' || ':' => 'b', _ => 'a' };
  final amud = '${m.group(2)}$side';
  return t.contains(amud) ? DafPlace(t.sefaria, amud) : null;
}

StudyKind? _kindOf(String book) => studyBook(book)?.kind;

/// Copies a link to [route] in the Torah tab.
class _CopyLink extends StatelessWidget {
  final String route;
  const _CopyLink(this.route);

  @override
  Widget build(BuildContext context) =>
      IconButton(tooltip: context.tr('Copy link'), icon: const Icon(Icons.link), onPressed: () => _copyLink(context, route));
}

Future<void> _copyLink(BuildContext context, String route) async {
  await Clipboard.setData(ClipboardData(text: shareTorahLink(route).toString()));
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Link copied'))));
}

/// Units of a book complete, as the book counts them: dafim for a tractate
/// (both amudim done), perakim for a masechta.
int completedOf(GemaraMarks marks, StudyBook b) =>
    b.kind == StudyKind.bavli ? marks.completedDafim(b.id, b.units) : b.units.where((u) => marks.isComplete(b.id, u)).length;

int totalOf(StudyBook b) => b.kind == StudyKind.bavli ? tractateNamed(b.id)!.dafCount : b.units.length;

/// The Gemara or Mishnah home: resume, today's portion, a download banner,
/// the books by seder with how much of each is complete, bookmarks and
/// recent pages.
class StudyHomeScreen extends ConsumerStatefulWidget {
  final StudyKind kind;
  const StudyHomeScreen({super.key, required this.kind});

  @override
  ConsumerState<StudyHomeScreen> createState() => _StudyHomeScreenState();
}

class _StudyHomeScreenState extends ConsumerState<StudyHomeScreen> {
  /// The seder shown; null for all of them.
  String? _seder;

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final bavli = kind == StudyKind.bavli;
    final marks = ref.watch(gemaraMarksProvider);
    final date = ref.watch(todayProvider);
    final today = bavli ? dafYomiPlace(date) : mishnahYomiPlace(date);
    final theme = Theme.of(context);
    final en = context.uiLanguage == UiLanguage.en;
    final books = booksOf(kind);
    final mine = [for (final h in marks.history) if (_kindOf(h.tractate) == kind) h];
    final bookmarks = [for (final b in marks.bookmarks) if (_kindOf(b.tractate) == kind) b];
    String title(String book, String unit) => studyBook(book)!.unitTitle(context, unit);
    final seders = <String, List<StudyBook>>{};
    for (final b in books) {
      (seders[b.seder] ??= []).add(b);
    }
    String sederName(String seder) => en ? context.tr('Seder {name}', {'name': context.term(seder)}) : 'סדר ${seders[seder]!.first.sederHe}';
    final shown = _seder == null ? seders.keys.toList() : [_seder!];
    final heading = bavli ? context.tr('Gemara') : context.tr('Mishnah');
    return Scaffold(
      appBar: AppBar(
        title: Text(heading),
        // On a narrow phone the link, then Go to a page, wait in a menu.
        actions: fitBarActions(context, heading, spare: bavli ? const [1, 0] : const [0], [
          if (bavli) BarTool(tooltip: context.tr('Go to a page'), icon: const Icon(Icons.search), onPressed: () => _goTo(context)),
          BarTool(
              tooltip: context.tr('Copy link'),
              icon: const Icon(Icons.link),
              onPressed: () => _copyLink(context, bavli ? '/torah/gemara' : '/torah/mishnah')),
          BarTool(tooltip: context.tr('Text settings'), icon: const Icon(Icons.text_fields), onPressed: () => showGemaraSettings(context, kind: kind)),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 32), children: [
        StudyDownloadPanel(books: books, label: bavli ? context.tr('Download all of Shas') : context.tr('Download all of the Mishnah')),
        // Side by side where each fits on one line, otherwise one above the
        // other, so a narrow phone never cuts the place short.
        LayoutBuilder(builder: (context, c) {
          final shortcuts = [
            if (mine.firstOrNull case final r?)
              _Shortcut(
                icon: Icons.play_circle_outline,
                label: context.tr('Continue'),
                place: title(r.tractate, r.amud),
                onTap: () => context.push(studyPath(r.tractate, r.amud, segment: r.segment)),
              ),
            if (today != null)
              _Shortcut(
                icon: Icons.today,
                label: bavli ? context.tr('Daf Yomi') : context.tr('Mishnah Yomi'),
                place: title(today.book, today.unit),
                done: marks.isComplete(today.book, today.unit),
                onTap: () => context.push(studyPath(today.book, today.unit, from: today.from, to: today.to)),
                trailing: bavli && dafOfAmud(today.unit) != null ? DafVideoButton(tractate: today.book, daf: dafOfAmud(today.unit)!) : null,
              ),
          ];
          if (shortcuts.length == 2 && shortcuts.every((s) => s.width(context) <= (c.maxWidth - 8) / 2)) {
            return Row(children: [Expanded(child: shortcuts[0]), const SizedBox(width: 8), Expanded(child: shortcuts[1])]);
          }
          return Column(children: [
            for (final (i, s) in shortcuts.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 8), child: s),
          ]);
        }),
        const SizedBox(height: 12),
        // Seder filter.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: ChoiceChip(label: Text(context.tr('All')), selected: _seder == null, onSelected: (_) => setState(() => _seder = null)),
            ),
            for (final seder in seders.keys)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ChoiceChip(
                  label: Text(en ? context.term(seder) : seders[seder]!.first.sederHe),
                  selected: _seder == seder,
                  onSelected: (_) => setState(() => _seder = seder),
                ),
              ),
          ]),
        ),
        for (final seder in shown) ...[
          _Heading(sederName(seder)),
          LayoutBuilder(builder: (context, c) {
            final columns = (c.maxWidth / 170).floor().clamp(2, 6);
            final w = (c.maxWidth - 8 * (columns - 1)) / columns;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in seders[seder]!) SizedBox(width: w, child: _BookCard(book: b)),
            ]);
          }),
        ],
        if (bookmarks.isNotEmpty) ...[
          _Heading(context.tr('Bookmarks')),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final b in bookmarks)
              ActionChip(
                avatar: const Icon(Icons.bookmark, size: 18),
                label: Text(title(b.tractate, b.amud)),
                onPressed: () => context.push(studyPath(b.tractate, b.amud, segment: b.segment)),
              ),
          ]),
        ],
        if (mine.length > 1) ...[
          _Heading(context.tr('Recent')),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final h in mine.skip(1).take(8))
              ActionChip(label: Text(title(h.tractate, h.amud)), onPressed: () => context.push(studyPath(h.tractate, h.amud, segment: h.segment))),
          ]),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
              bavli
                  ? context.tr('A daf counts as complete when you mark it at the end of the amud.')
                  : context.tr('A perek counts as complete when you mark it at its end.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        ),
      ]),
    );
  }

  Future<void> _goTo(BuildContext context) async {
    final controller = TextEditingController();
    final place = await showDialog<DafPlace>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setState) {
        final p = parseDafQuery(controller.text);
        return AlertDialog(
          title: Text(context.tr('Go to a page')),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: context.tr('e.g. Berakhot 2a')),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (p != null) Navigator.pop(context, p);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('Cancel'))),
            FilledButton(onPressed: p == null ? null : () => Navigator.pop(context, p), child: Text(context.tr('Open'))),
          ],
        );
      }),
    );
    controller.dispose();
    if (place != null && context.mounted) context.push(studyPath(place.tractate, place.amud));
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

/// A banner to save books for offline reading, like the Torah tab's: one
/// big button with the rough size, progress while it runs, gone once
/// everything is saved.
class StudyDownloadPanel extends ConsumerWidget {
  final List<StudyBook> books;
  final String label;
  const StudyDownloadPanel({super.key, required this.books, required this.label});

  /// Rough saved size per unit (gzipped), for the estimate.
  static int _bytesPer(StudyKind kind) => switch (kind) {
        StudyKind.bavli => 14 * 1024,
        StudyKind.mishnah => 8 * 1024,
        StudyKind.kitzur => 5 * 1024,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = [for (final b in books) b.id].join('|');
    final saved = ref.watch(savedUnitsProvider(key));
    final progress = ref.watch(bookDownloadProvider(key));
    final total = books.fold<int>(0, (n, b) => n + b.units.length);
    if (saved >= total && progress == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final missing = total - saved;
    final estimate = books.isEmpty ? 0 : missing * _bytesPer(books.first.kind);
    final Widget body;
    if (progress != null) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(context.tr('Downloading from Sefaria… {done} of {total}', {'done': progress.$1, 'total': progress.$2}),
                style: theme.textTheme.titleSmall),
          ),
          IconButton(
            tooltip: context.tr('Cancel'),
            icon: const Icon(Icons.close),
            onPressed: () => ref.read(bookDownloadProvider(key).notifier).cancel(),
          ),
        ]),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: progress.$2 == 0 ? null : progress.$1 / progress.$2),
      ]);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20)),
          icon: const Icon(Icons.download),
          label: Text('$label · ≈ ${_size(estimate)}', textAlign: TextAlign.center),
          onPressed: () => ref.read(bookDownloadProvider(key).notifier).start(),
        ),
        const SizedBox(height: 6),
        Text(
          saved > 0
              ? context.tr('{n} of {total} saved. Downloads from Sefaria once, then works offline.', {'n': saved, 'total': total})
              : context.tr('Downloads from Sefaria once, then works offline.'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
      ]);
    }
    return Card(
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(padding: const EdgeInsets.all(14), child: body),
    );
  }

  static String _size(int bytes) =>
      bytes < 1024 * 1024 ? '${(bytes / 1024).ceil()} KB' : '${(bytes / (1024 * 1024)).toStringAsFixed(bytes < 100 * 1024 * 1024 ? 1 : 0)} MB';
}

/// Continue / today's portion.
class _Shortcut extends StatelessWidget {
  final IconData icon;
  final String label;
  final String place;
  final bool done;
  final VoidCallback onTap;

  /// Beside the place, inside the card (Daf Yomi's video).
  final Widget? trailing;
  const _Shortcut({required this.icon, required this.label, required this.place, required this.onTap, this.done = false, this.trailing});

  /// How wide it is with the label and the place each on one line.
  double width(BuildContext context) {
    final theme = Theme.of(context);
    final text = math.max(textWidth(context, label, theme.textTheme.labelMedium), textWidth(context, place, theme.textTheme.titleMedium));
    return 12 + 24 + 10 + text + (trailing == null ? 0 : 40) + 12 + 2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(done ? Icons.check_circle : icon, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)),
                Text(place, style: theme.textTheme.titleMedium),
              ]),
            ),
            ?trailing,
          ]),
        ),
      ),
    );
  }
}

/// A book: its Hebrew name large, its English, and how much is done.
class _BookCard extends ConsumerWidget {
  final StudyBook book;
  const _BookCard({required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = book;
    final theme = Theme.of(context);
    final marks = ref.watch(gemaraMarksProvider);
    final done = completedOf(marks, b);
    final total = totalOf(b);
    final saved = ref.watch(savedUnitsProvider(b.id));
    final downloading = ref.watch(bookDownloadProvider(b.id)) != null;
    final en = context.uiLanguage == UiLanguage.en;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/torah/${b.kind == StudyKind.bavli ? 'gemara' : 'mishnah'}/${Uri.encodeComponent(b.id)}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(b.he,
                    textDirection: TextDirection.rtl,
                    textAlign: en ? TextAlign.start : TextAlign.right,
                    style: TextStyle(fontFamily: 'FrankRuehlCLM', fontSize: 22, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface)),
              ),
              if (downloading)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              else if (saved > 0)
                Icon(saved >= b.units.length ? Icons.offline_pin : Icons.offline_pin_outlined, size: 16, color: theme.colorScheme.outline),
            ]),
            if (en) Text(context.term(b.en), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: done / total, minHeight: 4)),
            const SizedBox(height: 3),
            Text(
              b.kind == StudyKind.bavli
                  ? context.tr('{done} of {n} dafim', {'done': done, 'n': total})
                  : context.tr('{done} of {n} perakim', {'done': done, 'n': total}),
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A book's units: for a tractate, its dafim under their perakim (each daf
/// a tile with its two amudim and a video mark); for a masechta, its
/// perakim. A check marks a unit completed, a dot a bookmark, a ring today's
/// portion.
class StudyBookScreen extends ConsumerWidget {
  final String book;
  const StudyBookScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = studyBook(book);
    if (b == null) return Scaffold(appBar: AppBar(), body: Center(child: Text(context.tr('No such page.'))));
    final theme = Theme.of(context);
    final marks = ref.watch(gemaraMarksProvider);
    final en = context.uiLanguage == UiLanguage.en;
    final done = completedOf(marks, b);
    final total = totalOf(b);
    final date = ref.watch(todayProvider);
    final today = b.kind == StudyKind.bavli ? dafYomiPlace(date) : mishnahYomiPlace(date);
    final progressLabel = b.kind == StudyKind.bavli
        ? context.tr('{done} of {n} dafim', {'done': done, 'n': total})
        : context.tr('{done} of {n} perakim', {'done': done, 'n': total});
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(b.name(context)),
          Text(progressLabel, style: theme.textTheme.bodySmall),
        ]),
        actions: [_CopyLink('/torah/${b.kind == StudyKind.bavli ? 'gemara' : 'mishnah'}/${Uri.encodeComponent(b.id)}')],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 32), children: [
        ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: done / total, minHeight: 5)),
        const SizedBox(height: 10),
        StudyDownloadPanel(books: [b], label: context.tr('Download {book}', {'book': b.name(context)})),
        if (b.kind == StudyKind.bavli)
          ..._tractate(context, ref, b, today, en)
        else
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final u in b.units)
              _UnitTile(
                book: b,
                unit: u,
                label: en ? u : gematriya(int.parse(u)),
                today: today != null && today.book == b.id && today.unit == u,
              ),
          ]),
        if (ref.watch(savedUnitsProvider(b.id)) > 0)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(context.tr('Remove the saved copy')),
              onPressed: () => deleteBook(ref, b.id),
            ),
          ),
      ]),
    );
  }

  List<Widget> _tractate(BuildContext context, WidgetRef ref, StudyBook b, YomiPlace? today, bool en) {
    final theme = Theme.of(context);
    final t = tractateNamed(b.id)!;
    final perakim = ref.watch(perakimProvider(b.id)).value ?? const <Perek>[];
    final firstDaf = (t.firstNumber + 1) ~/ 2;
    final lastDaf = (t.lastNumber + 1) ~/ 2;
    // Dafim per perek. A daf where one perek ends and the next begins is
    // listed once, under the perek that starts first; the header gives each
    // perek's exact range.
    final seen = <int>{};
    final groups = perakim.isEmpty
        ? [(null as Perek?, [for (var d = firstDaf; d <= lastDaf; d++) d])]
        : [
            for (final p in perakim)
              (p, [for (var d = (p.startNumber + 1) ~/ 2; d <= (p.endNumber + 1) ~/ 2; d++) if (seen.add(d)) d]),
          ];
    return [
      for (final (perek, dafim) in groups) ...[
        if (perek != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
            // Number, transliteration and range at the start; the Hebrew
            // name on its own at the other edge, so the scripts don't touch.
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(en ? context.tr('Chapter {n}', {'n': perek.number}) : 'פרק ${gematriya(perek.number)}',
                      style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
                  Text(
                    [
                      if (en && perek.en.isNotEmpty) context.term(perek.en),
                      '${shortAmud(context, perek.startAmud)}–${shortAmud(context, perek.endAmud)}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              Text(perek.he,
                  textDirection: TextDirection.rtl, style: TextStyle(fontFamily: 'FrankRuehlCLM', fontSize: 18, color: theme.colorScheme.onSurface)),
            ]),
          )
        else
          const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final d in dafim) _DafTile(tractate: t, daf: d, today: today),
        ]),
      ],
    ];
  }
}

/// A Mishnah perek.
class _UnitTile extends ConsumerWidget {
  final StudyBook book;
  final String unit;
  final String label;
  final bool today;
  const _UnitTile({required this.book, required this.unit, required this.label, required this.today});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final marks = ref.watch(gemaraMarksProvider);
    final done = marks.isComplete(book.id, unit);
    final bookmarked = marks.isBookmarked(DafPlace(book.id, unit));
    final he = context.uiLanguage != UiLanguage.en;
    return InkWell(
      onTap: () => context.push(studyPath(book.id, unit)),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: 64,
        height: 52,
        decoration: BoxDecoration(
          color: done ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: today ? theme.colorScheme.primary : theme.colorScheme.outlineVariant, width: today ? 2 : 1),
        ),
        child: Stack(alignment: Alignment.center, children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(he ? 'פרק' : context.tr('Perek'),
                style: theme.textTheme.labelSmall?.copyWith(color: done ? theme.colorScheme.onPrimary : theme.colorScheme.outline)),
            Text(label,
                style: (he ? const TextStyle(fontFamily: 'FrankRuehlCLM', fontSize: 17) : theme.textTheme.titleMedium)
                    ?.copyWith(fontWeight: FontWeight.w700, color: done ? theme.colorScheme.onPrimary : null)),
          ]),
          if (done) Positioned(top: 3, right: 4, child: Icon(Icons.check, size: 13, color: theme.colorScheme.onPrimary)),
          if (bookmarked)
            Positioned(
              top: 4,
              left: 5,
              child: Container(width: 6, height: 6, decoration: BoxDecoration(color: theme.colorScheme.tertiary, shape: BoxShape.circle)),
            ),
        ]),
      ),
    );
  }
}

class _DafTile extends ConsumerWidget {
  final Tractate tractate;
  final int daf;
  final YomiPlace? today;
  const _DafTile({required this.tractate, required this.daf, required this.today});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tractate;
    final theme = Theme.of(context);
    final marks = ref.watch(gemaraMarksProvider);
    final he = context.uiLanguage != UiLanguage.en;
    final isToday = today != null && today!.book == t.sefaria && today!.unit == '${daf}a';
    Widget side(String s) {
      final amud = '$daf$s';
      if (!t.contains(amud)) return const Expanded(child: SizedBox(height: 26));
      final done = marks.isComplete(t.sefaria, amud);
      final bookmarked = marks.isBookmarked(DafPlace(t.sefaria, amud));
      return Expanded(
        child: InkWell(
          onTap: () => context.push(studyPath(t.sefaria, amud)),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 26,
            margin: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              color: done ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Stack(alignment: Alignment.center, children: [
              done
                  ? Icon(Icons.check, size: 15, color: theme.colorScheme.onPrimary)
                  : Text(he ? (s == 'a' ? '.' : ':') : s, style: theme.textTheme.labelMedium),
              if (bookmarked)
                Positioned(
                  top: 2,
                  right: 3,
                  child: Container(width: 5, height: 5, decoration: BoxDecoration(color: theme.colorScheme.tertiary, shape: BoxShape.circle)),
                ),
            ]),
          ),
        ),
      );
    }

    return Container(
      width: 72,
      padding: const EdgeInsets.fromLTRB(3, 3, 3, 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: isToday ? theme.colorScheme.primary : theme.colorScheme.outlineVariant, width: isToday ? 2 : 1),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(he ? gematriya(daf) : '$daf',
              style: (he ? const TextStyle(fontFamily: 'FrankRuehlCLM', fontSize: 16) : theme.textTheme.labelLarge)
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: 3),
          _VideoMark(tractate: t, daf: daf),
        ]),
        // Amud a on the right in a Hebrew interface, as in the book.
        Row(textDirection: he ? TextDirection.rtl : TextDirection.ltr, children: [side('a'), side('b')]),
      ]),
    );
  }
}

/// The video shiur for a daf (see [DafVideoScreen]). For a daf that has none
/// yet (not in [dafVideoIndex]) it is dimmed and says so when tapped.
class _VideoMark extends StatelessWidget {
  final Tractate tractate;
  final int daf;
  const _VideoMark({required this.tractate, required this.daf});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Fetches the list the first time a tile shows (once a run).
    dafVideoIndex.load();
    return ValueListenableBuilder(
      valueListenable: dafVideoIndex,
      builder: (context, _, _) {
        final ready = dafVideoUri(tractate.sefaria, daf) != null && dafVideoIndex.has(tractate.sefaria, daf);
        return InkResponse(
          radius: 14,
          onTap: ready
              ? () => context.push(dafVideoPath(tractate.sefaria, '$daf'))
              : () => ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(context.tr('Video shiurim are coming soon.')))),
          child: Icon(Icons.movie_outlined,
              size: 15, color: ready ? theme.colorScheme.primary : theme.colorScheme.outline.withValues(alpha: 0.7)),
        );
      },
    );
  }
}

/// The daf of a Bavli amud ("50b" → 50); null for a unit that isn't one.
int? dafOfAmud(String amud) => int.tryParse(RegExp(r'^(\d+)[ab]$').firstMatch(amud)?[1] ?? '');

/// A button beside a way into a daf or a Kitzur Yomi (on Home, in the
/// Gemara and the Kitzur, the reader's bar) that plays its video shiur.
/// Dimmed for one without a video yet, saying so when tapped, unless
/// [onlyWhenReady]; absent where videos are off.
class DafVideoButton extends StatelessWidget {
  /// The tractate (or the Kitzur) as Sefaria names it.
  final String tractate;
  final int? daf;

  /// For the Kitzur: the siman, and the se'if the day's portion starts at
  /// (null for the first day with a video in the siman).
  final int? siman;
  final int? seif;

  /// Hidden, rather than dimmed, until there's a video (on a crowded bar).
  final bool onlyWhenReady;
  const DafVideoButton({super.key, required this.tractate, required int this.daf, this.onlyWhenReady = false})
      : siman = null,
        seif = null;
  const DafVideoButton.kitzur({super.key, required int this.siman, this.seif, this.onlyWhenReady = false})
      : tractate = kitzurId,
        daf = null;

  /// The video's unit when it's published, else null.
  String? get readyUnit => switch (_unit) {
        final u? when dafVideoIndex.hasUnit(tractate, u) => u,
        _ => null,
      };

  String? get _unit => switch ((daf, siman, seif)) {
        (final d?, _, _) => '$d',
        (_, final s?, final e?) => kitzurVideoUnit(s, e),
        (_, final s?, null) => dafVideoIndex.kitzurIn(s),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    if (dafVideoBase.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    dafVideoIndex.load();
    return ValueListenableBuilder(
      valueListenable: dafVideoIndex,
      builder: (context, _, _) {
        final unit = _unit;
        final ready = unit != null && dafVideoIndex.hasUnit(tractate, unit);
        if (!ready && onlyWhenReady) return const SizedBox.shrink();
        return IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: context.tr(ready ? 'Watch the shiur' : 'Video shiurim are coming soon.'),
          icon: Icon(Icons.movie_outlined, color: ready ? theme.colorScheme.primary : theme.colorScheme.outline.withValues(alpha: 0.7)),
          onPressed: ready
              ? () => context.push(dafVideoPath(tractate, unit))
              : () => ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(context.tr('Video shiurim are coming soon.')))),
        );
      },
    );
  }
}
