import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/search.dart';
import '../../core/settings.dart';
import '../../core/titles.dart';
import '../home/today.dart';
import '../siddur/reader_screen.dart';
import '../siddur/siddur_providers.dart';
import '../tehillim/tehillim_data.dart' show Passage, Portion;
import '../tehillim/tehillim_reader.dart';
import '../torah/torah_library.dart';
import '../zmanim/zman_catalog.dart';
import 'prayer_names.dart';
import '../siddur/prayer_catalog.dart' show bookSearchOrder;

// --- Siddur -----------------------------------------------------------------

/// A titled section of a siddur, with the titles of the sections it's in.
class PrayerEntry {
  final String book;
  final SchemaNode node;
  final List<SchemaNode> path;

  /// Its titles and other names (see [prayerNamesFor]), ready to match.
  final SearchTarget target;

  /// The same prayer in another siddur has the same key: the name it's
  /// known by, else its Hebrew title, else its English one.
  final String key;
  PrayerEntry(this.book, this.node, this.path, this.target, this.key);

  factory PrayerEntry.of(String book, SchemaNode node, List<SchemaNode> path) {
    final names = prayerNamesFor(node.en, node.he);
    final he = searchFold(node.he);
    return PrayerEntry(book, node, path, SearchTarget([node.en, node.he, ...names.names]),
        names.key ?? (he.isNotEmpty ? 'he:$he' : 'en:${searchFold(node.en)}'));
  }
}

/// Search shows each prayer once, from your siddur or else the one the app
/// would fall back to; this shows every siddur's copy instead.
final searchAllSiddurimProvider = StateProvider<bool>((ref) => false);

/// Every titled section of every bundled siddur.
final prayerIndexProvider = FutureProvider<List<PrayerEntry>>((ref) async {
  final m = await ref.watch(manifestProvider.future);
  final out = <PrayerEntry>[];
  for (final b in m.books) {
    final root = await ref.watch(bookIndexProvider(b.title).future);
    void walk(SchemaNode n, List<SchemaNode> path) {
      for (final c in n.children) {
        if (c.en.trim().isNotEmpty || c.he.trim().isNotEmpty) out.add(PrayerEntry.of(b.title, c, path));
        walk(c, [...path, c]);
      }
    }

    walk(root, const []);
  }
  return out;
});

/// A chapter of Tehillim asked for by number: "Tehillim 23", "psalm 91",
/// "תהלים כג".
int? tehillimChapter(String query) {
  final m = RegExp(r'^\s*(?:tehill?im|psalms?|ps\.?|תהלים|תהילים)\s+(\S+)\s*$', caseSensitive: false).firstMatch(query);
  if (m == null) return null;
  final n = int.tryParse(m[1]!) ?? _hebrewNumber(m[1]!);
  return n != null && n >= 1 && n <= 150 ? n : null;
}

int? _hebrewNumber(String s) {
  const values = {
    'א': 1, 'ב': 2, 'ג': 3, 'ד': 4, 'ה': 5, 'ו': 6, 'ז': 7, 'ח': 8, 'ט': 9, //
    'י': 10, 'כ': 20, 'ך': 20, 'ל': 30, 'מ': 40, 'ם': 40, 'נ': 50, 'ן': 50, 'ס': 60, 'ע': 70, //
    'פ': 80, 'ף': 80, 'צ': 90, 'ץ': 90, 'ק': 100, 'ר': 200, 'ש': 300, 'ת': 400,
  };
  var n = 0;
  for (final ch in s.replaceAll(RegExp('[״׳"\']'), '').split('')) {
    final v = values[ch];
    if (v == null) return null;
    n += v;
  }
  return n == 0 ? null : n;
}

/// Prayers (your siddur first, then the others) and Tehillim by chapter.
/// [standalone] opens prayers above the tabs (from Home).
List<(String, List<SearchHit>)> siddurResults(BuildContext context, WidgetRef ref, SearchQuery q, {bool standalone = false}) {
  final s = ref.watch(settingsProvider);
  final index = ref.watch(prayerIndexProvider).valueOrNull ?? const [];
  final defaultBook = ref.watch(defaultBookProvider).valueOrNull;
  final manifest = ref.watch(manifestProvider).valueOrNull;
  final all = ref.watch(searchAllSiddurimProvider);
  final hebrew = context.prayerTitleIsHebrew(s);
  // Where the app looks for a prayer your siddur lacks, in order;
  // commentaries ("… on Siddur") last.
  final order = manifest == null || defaultBook == null ? const <String>[] : bookSearchOrder(manifest, defaultBook);
  int rank(String book) => switch (order.indexOf(book)) { -1 => order.length, final i => i };

  final found = <(PrayerEntry, int)>[];
  for (final e in index) {
    final score = q.scoreTarget(e.target);
    if (score != null) found.add((e, score));
  }
  // The same prayer in several siddurim: yours, or else the first siddur
  // the app would fall back to.
  final ownKeys = {for (final (e, _) in found) if (e.book == defaultBook) e.key};
  final fallback = <String, String>{};
  for (final (e, _) in found) {
    if (e.book == defaultBook || ownKeys.contains(e.key)) continue;
    final best = fallback[e.key];
    if (best == null || rank(e.book) < rank(best)) fallback[e.key] = e.book;
  }

  final mine = <SearchHit>[];
  final others = <SearchHit>[];
  final seen = <String>{};
  var hidden = 0;
  for (final (e, score) in found) {
    final own = e.book == defaultBook;
    if (!own) {
      final shown = all ? seen.add('${e.book}|${e.node.en}|${e.node.he}') : fallback[e.key] == e.book && seen.add('${e.key}|${e.node.en}');
      if (!shown) {
        hidden++;
        continue;
      }
    }
    final where = [for (final p in e.path) context.prayerTitle(s, p.en, p.he)];
    if (!own) where.insert(0, context.prayerTitle(s, e.book, e.book));
    (own ? mine : others).add(SearchHit(
      icon: Icons.menu_book_outlined,
      title: context.prayerTitle(s, e.node.en, e.node.he),
      hebrewTitle: hebrew,
      subtitle: where.isEmpty ? null : where.join(' › '),
      // Top-level sections before the lines inside them.
      score: score * 10 + e.path.length.clamp(0, 9),
      open: (c) => c.push(readerPath(e.book, e.node.id, standalone: standalone)),
    ));
  }
  if (hidden > 0 || all) {
    others.add(SearchHit(
      icon: all ? Icons.unfold_less : Icons.library_books_outlined,
      title: all ? context.tr('Show each prayer once') : context.tr('Show in every siddur ({n} more)', {'n': '$hidden'}),
      score: 1 << 30,
      logAs: all ? 'search_all_siddurim_off' : 'search_all_siddurim_on',
      open: (_) => ref.read(searchAllSiddurimProvider.notifier).state = !all,
    ));
  }
  final chapter = tehillimChapter(q.raw);
  return [
    if (chapter != null)
      (
        context.tr('Tehillim'),
        [
          SearchHit(
            icon: Icons.auto_stories_outlined,
            title: '${context.tr('Tehillim')} $chapter',
            subtitle: 'תהלים ${gematriya(chapter)}',
            open: (c) => c.go(tehillimReadPath(Portion('Tehillim $chapter', 'תהלים ${gematriya(chapter)}', [Passage(chapter)]))),
          ),
        ]
      ),
    (context.tr('In {book}', {'book': context.prayerTitle(s, defaultBook ?? '', defaultBook ?? '')}), mine.take(40).toList()),
    (context.tr('Other siddurim'), [...others.where((h) => h.score < 1 << 30).take(all ? 60 : 20), ...others.where((h) => h.score >= 1 << 30)]),
  ];
}

// --- Torah ------------------------------------------------------------------

/// A downloaded book's text, folded once for searching.
class _TorahText {
  final List<({int siman, int seif, String he, String en, String heFold, String enFold})> seifim;
  const _TorahText(this.seifim);
}

final _torahTextProvider = FutureProvider.family<_TorahText?, String>((ref, id) async {
  final book = await ref.watch(torahBookProvider(id).future);
  if (book == null) return null;
  final out = <({int siman, int seif, String he, String en, String heFold, String enFold})>[];
  for (var i = 0; i < book.length; i++) {
    final he = book.he[i];
    final en = i < book.en.length ? book.en[i] : const <String>[];
    for (var j = 0; j < he.length || j < en.length; j++) {
      final h = j < he.length ? he[j].replaceAll(RegExp(r'[֑-ׇ]'), '') : '';
      final e = j < en.length ? en[j] : '';
      out.add((siman: i + 1, seif: j + 1, he: h, en: e, heFold: searchFold(h), enFold: searchFold(e)));
    }
  }
  return _TorahText(out);
});

String _snippet(String text, int at, int length) {
  final start = (at - 40).clamp(0, text.length);
  final end = (at + length + 60).clamp(0, text.length);
  return '${start > 0 ? '…' : ''}${text.substring(start, end).trim()}${end < text.length ? '…' : ''}';
}

/// The Torah tab's books, the Kitzur's simanim by title and the text of
/// downloaded books. [only] limits it to one book (its own page).
List<(String, List<SearchHit>)> torahResults(BuildContext context, WidgetRef ref, SearchQuery q, {String? only}) {
  final heUi = context.uiLanguage != UiLanguage.en;
  final books = <SearchHit>[];
  final simanim = <SearchHit>[];
  final text = <SearchHit>[];
  for (final c in torahCategories) {
    for (final w in c.works) {
      if (only != null && w.id != only) continue;
      if (only == null) {
        final score = q.score([w.en, w.he, c.en, c.he]);
        if (score != null) {
          books.add(SearchHit(
            icon: w.available ? Icons.menu_book_outlined : Icons.construction,
            title: heUi ? w.he : context.term(w.en),
            subtitle: w.available ? (heUi ? c.he : context.term(c.en)) : context.tr('Work in progress'),
            score: score,
            open: (ctx) => ctx.go(w.available ? '/torah/${c.id}/${w.id}' : '/torah/${c.id}'),
          ));
        }
      }
      if (!w.available) continue;
      final book = ref.watch(torahBookProvider(w.id)).value;
      if (book == null) continue;
      for (var i = 0; i < book.length; i++) {
        final score = q.score([book.titlesEn[i], book.titlesHe[i], 'siman ${i + 1}', 'סימן ${gematriya(i + 1)}']);
        if (score == null) continue;
        simanim.add(SearchHit(
          icon: Icons.bookmark_outline,
          title: heUi || book.titlesEn[i].isEmpty ? book.titlesHe[i] : book.titlesEn[i],
          hebrewTitle: heUi || book.titlesEn[i].isEmpty,
          subtitle: '${heUi ? w.he : context.term(w.en)} · ${heUi ? 'סימן ${gematriya(i + 1)}' : '${context.tr('Siman')} ${i + 1}'}',
          score: score,
          open: (ctx) => ctx.push('/torah/${c.id}/${w.id}/read?siman=${i + 1}'),
        ));
      }
      // Full text: plain matches only (no transliteration guessing), and
      // not for one or two letters.
      final t = ref.watch(_torahTextProvider(w.id)).valueOrNull;
      final words = searchFold(q.raw);
      if (t == null || words.length < 3) continue;
      for (final s in t.seifim) {
        final inHe = s.heFold.contains(words);
        if (!inHe && !s.enFold.contains(words)) continue;
        final shown = inHe ? s.he : s.en;
        final at = q.indexIn(shown);
        text.add(SearchHit(
          icon: Icons.format_quote_outlined,
          title: at < 0 ? shown.substring(0, shown.length.clamp(0, 100)) : _snippet(shown, at, words.length),
          hebrewTitle: inHe,
          subtitle: '${heUi ? w.he : context.term(w.en)} ${s.siman}:${s.seif}',
          // The snippet is built around the words typed.
          logAs: '${w.id} ${s.siman}:${s.seif}',
          open: (ctx) => ctx.push('/torah/${c.id}/${w.id}/read?siman=${s.siman}&from=${s.seif}&to=${s.seif}'),
        ));
        if (text.length >= 50) break;
      }
    }
  }
  return [
    if (only == null) (context.tr('Books'), books),
    (context.tr('Simanim'), simanim.take(40).toList()),
    (context.tr('In the text'), text),
  ];
}

// --- Zmanim, pages, everything ---------------------------------------------------

/// Zmanim by name with today's time; opening one shows it on the Zmanim
/// page.
List<SearchHit> zmanimResults(BuildContext context, WidgetRef ref, SearchQuery q) {
  final t = ref.watch(todaySnapshotProvider);
  final s = ref.watch(settingsProvider);
  final names = ref.watch(zmanResolverProvider);
  final z = ref.watch(zmanimProvider(t.civil));
  return [
    for (final d in builtInZmanim)
      if (q.score([names.name(d.key), d.en, d.he, d.opinion]) case final score?)
        SearchHit(
          icon: Icons.schedule,
          title: names.name(d.key),
          subtitle: '${formatTime(d.compute(z), t.location, hour12: s.hour12)} · ${d.he}',
          score: score,
          open: (c) {
            ref.read(pageSearchProvider('zmanim').notifier).state = names.name(d.key);
            c.go('/zmanim');
          },
        ),
  ];
}

/// The app's own screens, with words to find them by.
const _pages = [
  ('Holidays & Seasons', 'חגים ועונות', Icons.event_note, '/siddur/seasons', ['hoshanot', 'selichot', 'chanukah', 'lulav', 'hakafot']),
  ('Tehillim', 'תהלים', Icons.auto_stories_outlined, '/siddur/tehillim', ['psalms']),
  ('Daily learning', 'לימוד יומי', Icons.school_outlined, '/learning', ['daf yomi', 'mishna', 'rambam']),
  ('Calendar', 'לוח שנה', Icons.calendar_month, '/calendar', ['luach', 'holidays', 'dates']),
  ('Zman alerts', 'התראות זמנים', Icons.notifications_active_outlined, '/alerts', ['reminders', 'notifications']),
  ('Location', 'מיקום', Icons.place_outlined, '/settings/location', ['city', 'gps']),
  ('Fonts', 'גופנים', Icons.font_download_outlined, '/settings/fonts', ['font', 'hebrew font']),
  ("Me'ein Shalosh", 'מעין שלוש', Icons.bakery_dining, '/meein-shalosh', ['al hamichya', 'bracha achrona']),
  ('Torah', 'תורה', Icons.local_library_outlined, '/torah', ['learning', 'kitzur', 'halacha']),
];

const _tabRoutes = {'/siddur', '/torah', '/zmanim', '/settings'};

List<SearchHit> pageResults(BuildContext context, SearchQuery q) => [
      for (final (en, he, icon, route, words) in _pages)
        if (q.score([en, context.tr(en), he, ...words]) case final score?)
          SearchHit(
            icon: icon,
            title: context.tr(en),
            score: score,
            // Pages inside a tab switch to it; the others open above.
            open: (c) => _tabRoutes.any(route.startsWith) ? c.go(route) : c.push(route),
          ),
    ];

/// Home's search: everything, with a way into Settings' own search.
class GlobalSearchResults extends ConsumerWidget {
  final SearchQuery query;
  const GlobalSearchResults({super.key, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hebFont = ref.watch(settingsProvider.select((s) => s.hebrewFont));
    return SearchResults(
      query: query.raw,
      hebrewFont: hebFont,
      groups: [
        (context.tr('Pages'), pageResults(context, query)),
        ...siddurResults(context, ref, query, standalone: true),
        (context.tr('Zmanim'), zmanimResults(context, ref, query)),
        ...torahResults(context, ref, query),
        (
          context.tr('Settings'),
          [
            SearchHit(
              icon: Icons.settings_outlined,
              title: context.tr('Search settings for “{q}”', {'q': query.raw}),
              logAs: 'search_settings',
              score: 99,
              open: (c) {
                ref.read(pageSearchProvider('settings').notifier).state = query.raw;
                c.go('/settings');
              },
            ),
          ]
        ),
      ],
    );
  }
}
