import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics.dart';
import 'hebrew_text.dart';
import 'l10n.dart';

// --- Matching -----------------------------------------------------------------

final _marks = RegExp(r'[֑-ׇ]');
final _apostrophes = RegExp('[\'’‘`׳״"]');
final _punct = RegExp(r'''[^\p{L}\p{N}]+''', unicode: true);

/// Lower case, without nikud, te'amim, apostrophes ("Ma'ariv" → "maariv",
/// "ק״ש" → "קש") or other punctuation, words separated by single spaces.
String searchFold(String s) => s.replaceAll(_marks, '').replaceAll(_apostrophes, '').toLowerCase().replaceAll(_punct, ' ').trim();

/// A rough consonant key of each word, the same for a Hebrew word and the
/// ways people spell it in English letters, so transliterations match each
/// other and the Hebrew: Shacharit / Shacharis / שחרית, Birkat / Birchas /
/// ברכת, Hataras / Hatarat / התרת, Tefillah / Tefila / תפלה / תפילה.
String searchKey(String s) => searchFold(s).split(' ').map(_keyWord).join(' ');

/// Consonant classes: b/v/w and ב (and ו starting a word); ch/kh/k/c/q/h
/// and ח כ ק ה; s/t/th and ס ש(ׂ) ת ט; tz/ts/z and צ ז; p/f/ph and פ.
/// Vowels, y, א, ע and vowel letters (י, a ו inside a word, a final ה) go.
String _keyWord(String w) {
  if (w.isEmpty) return w;
  final hebrew = RegExp('[א-ת]').hasMatch(w);
  var s = hebrew ? _hebrewKey(w) : _latinKey(w);
  // Double letters (Shabbos / Shabos, Sukkot / Sukot).
  s = s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
  return s;
}

String _latinKey(String w) => w
    // A final h after a vowel is silent: Tefillah, Chanukah, Torah.
    .replaceAll(RegExp(r'([aeiou])h$'), r'$1')
    .replaceAll('sch', 'š')
    .replaceAll('sh', 'š')
    .replaceAll('tz', 'z')
    .replaceAll('ts', 'z')
    .replaceAll('ch', 'h')
    .replaceAll('kh', 'h')
    .replaceAll('ck', 'h')
    .replaceAll('ph', 'p')
    .replaceAll('th', 't')
    .replaceAll(RegExp('[kqc]'), 'h')
    .replaceAll('s', 't')
    .replaceAll('f', 'p')
    .replaceAll(RegExp('[vw]'), 'b')
    .replaceAll(RegExp('[aeiouy]'), '');

String _hebrewKey(String w) {
  final out = StringBuffer();
  for (var i = 0; i < w.length; i++) {
    final c = w[i];
    final last = i == w.length - 1;
    out.write(switch (c) {
      'ב' => 'b',
      // A consonant only at the start of a word or doubled.
      'ו' => i == 0 || (i + 1 < w.length && w[i + 1] == 'ו') ? 'b' : '',
      'ג' => 'g',
      'ד' => 'd',
      'ה' => last ? '' : 'h',
      'ח' || 'כ' || 'ך' || 'ק' => 'h',
      'ז' || 'צ' || 'ץ' => 'z',
      'ט' || 'ת' || 'ס' => 't',
      'ש' => 'š',
      'ל' => 'l',
      'מ' || 'ם' => 'm',
      'נ' || 'ן' => 'n',
      'פ' || 'ף' => 'p',
      'ר' => 'r',
      'א' || 'ע' || 'י' => '',
      _ => RegExp('[a-z0-9]').hasMatch(c) ? c : '',
    });
  }
  return out.toString();
}

/// Kept for callers that only need Latin transliterations matched.
String searchSkeleton(String s) => searchKey(s);

/// Texts prepared once for matching many queries against (a search index).
class SearchTarget {
  final List<String> folded;
  final String _all;
  final List<String> _words;
  final List<String> _keys;

  factory SearchTarget(Iterable<String?> texts) {
    final folded = [
      for (final t in texts)
        if (t != null && t.isNotEmpty) searchFold(t),
    ].where((f) => f.isNotEmpty).toList();
    final words = [for (final f in folded) ...f.split(' ')];
    return SearchTarget._(folded, folded.join(' | '), words, [for (final w in words) _keyWord(w)]);
  }

  SearchTarget._(this.folded, this._all, this._words, this._keys);
}

/// Whether [a] and [b] are at most one edit apart (a letter added, dropped,
/// changed or two swapped).
bool _oneEdit(String a, String b) {
  if (a == b) return true;
  if ((a.length - b.length).abs() > 1) return false;
  var i = 0;
  while (i < a.length && i < b.length && a[i] == b[i]) {
    i++;
  }
  if (a.length == b.length) {
    if (a.substring(i + 1) == b.substring(i + 1)) return true;
    return i + 1 < a.length && a[i] == b[i + 1] && a[i + 1] == b[i] && a.substring(i + 2) == b.substring(i + 2);
  }
  final (long, short) = a.length > b.length ? (a, b) : (b, a);
  return long.substring(i + 1) == short.substring(i);
}

/// What the user typed, prepared for matching.
class SearchQuery {
  final String raw;
  final List<String> _words;
  final List<String> _k;
  final List<RegExp> _starts;

  factory SearchQuery(String raw) {
    final words = searchFold(raw).split(' ').where((w) => w.isNotEmpty).toList();
    return SearchQuery._(raw, words, [for (final w in words) _keyWord(w)],
        [for (final w in words) RegExp('(?:^|[ |])${RegExp.escape(w)}')]);
  }

  SearchQuery._(this.raw, this._words, this._k, this._starts);

  bool get isEmpty => _words.isEmpty;

  /// How well [texts] match: 0 (starts with the query), 1 (each word starts
  /// a word), 2 (each word appears somewhere), 3 (a transliteration or the
  /// Hebrew it stands for), 4 (one typo in a longer word); null when they
  /// don't. Every word typed must match; the score is the loosest needed.
  int? score(Iterable<String?> texts) => scoreTarget(SearchTarget(texts));

  int? scoreTarget(SearchTarget t) {
    if (isEmpty) return 0;
    if (t.folded.isEmpty) return null;
    final phrase = _words.join(' ');
    if (t.folded.any((f) => f.startsWith(phrase))) return 0;
    var worst = 1;
    for (var i = 0; i < _words.length; i++) {
      final level = _wordLevel(i, t);
      if (level == null) return null;
      if (level > worst) worst = level;
    }
    return worst;
  }

  int? _wordLevel(int i, SearchTarget t) {
    final w = _words[i];
    if (_starts[i].hasMatch(t._all)) return 1;
    if (t._all.contains(w)) return 2;
    // A key needs enough consonants to mean something ("a" or "sh" alone
    // would match everything), and must start a word's key: "minyan" (mn)
    // shouldn't turn up inside "Zmanim" (zmnm). Two consonants are too few
    // to go on: then the whole word must match.
    final k = _k[i];
    // ("al" → "l", for על, has to be a whole word.)
    if ((k.length >= 2 || w.length >= 2 && k.isNotEmpty) && t._keys.any((x) => k.length < 3 ? x == k : x.startsWith(k))) return 3;
    // A typo, in a word long enough to be sure what was meant. (Not in
    // the consonant keys: one letter there joins unrelated words, like
    // "bentching" and "blessing".)
    if (w.length >= 5) {
      for (final x in t._words) {
        if (x.length < 4) continue;
        if (_oneEdit(w, x) || (x.length > w.length && _oneEdit(w, x.substring(0, w.length)))) return 4;
      }
    }
    return null;
  }

  bool matches(Iterable<String?> texts) => score(texts) != null;

  /// Where the query's first word appears in [text] (nikud and te'amim
  /// ignored), as an index into [text] itself, for showing a snippet; -1
  /// if it doesn't.
  int indexIn(String text) {
    if (isEmpty) return -1;
    // The text without marks, and where each of its characters came from.
    final plain = StringBuffer();
    final from = <int>[];
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (isHebrewMark(c)) continue;
      plain.write(c == '׀' ? ' ' : c);
      from.add(i);
    }
    final at = plain.toString().toLowerCase().indexOf(_words.first);
    return at < 0 || at >= from.length ? -1 : from[at];
  }
}

/// The search text of each page, so it survives switching tabs.
final pageSearchProvider = StateProvider.family<String, String>((ref, page) => '');

// --- In-place filtering -------------------------------------------------------

/// Filters the [AdaptiveSection]s below it (Settings): rows whose title and
/// subtitle don't match [query] are hidden, and sections with none left.
class ListFilter extends InheritedWidget {
  final SearchQuery query;
  const ListFilter({super.key, required this.query, required super.child});

  static SearchQuery? of(BuildContext context) {
    final q = context.dependOnInheritedWidgetOfExactType<ListFilter>()?.query;
    return q == null || q.isEmpty ? null : q;
  }

  @override
  bool updateShouldNotify(ListFilter old) => old.query.raw != query.raw;
}

// --- Widgets --------------------------------------------------------------------

/// The search bar at the top of a page, bound to [pageSearchProvider].
class PageSearchBar extends ConsumerStatefulWidget {
  final String page;
  final String hint;
  const PageSearchBar({super.key, required this.page, required this.hint});

  /// Height to reserve under an app bar.
  static const height = 64.0;

  @override
  ConsumerState<PageSearchBar> createState() => _PageSearchBarState();
}

class _PageSearchBarState extends ConsumerState<PageSearchBar> {
  late final _controller = TextEditingController(text: ref.read(pageSearchProvider(widget.page)));

  Timer? _logTimer;

  @override
  void dispose() {
    _logTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Logs that a search was made once typing pauses (its length, never
  /// the text).
  void _log(String v) {
    _logTimer?.cancel();
    if (v.trim().length < 2) return;
    _logTimer = Timer(const Duration(seconds: 2), () => analytics.event('search', {'length': v.trim().length, 'page': widget.page}));
  }

  @override
  Widget build(BuildContext context) {
    // Set from elsewhere (a search handed over from Home).
    ref.listen(pageSearchProvider(widget.page), (_, v) {
      if (v != _controller.text) _controller.text = v;
    });
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: SearchBar(
        controller: _controller,
        hintText: widget.hint,
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(theme.colorScheme.surfaceContainerHigh),
        constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
        leading: const Icon(Icons.search),
        trailing: [
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: context.tr('Clear'),
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                ref.read(pageSearchProvider(widget.page).notifier).state = '';
              },
            ),
        ],
        onChanged: (v) {
          setState(() {});
          ref.read(pageSearchProvider(widget.page).notifier).state = v;
          _log(v);
        },
      ),
    );
  }
}

/// A search result: where it leads and how it's shown.
class SearchHit {
  final IconData icon;
  final String title;
  final String? subtitle;

  /// The title is Hebrew (for the font and direction).
  final bool hebrewTitle;
  final int score;
  final void Function(BuildContext context) open;

  /// What analytics records for this hit instead of [title], for titles
  /// that carry what the user typed.
  final String? logAs;
  const SearchHit({required this.icon, required this.title, this.subtitle, this.hebrewTitle = false, this.score = 0, required this.open, this.logAs});
}

/// Results under headings, best first within each group.
class SearchResults extends StatelessWidget {
  final List<(String heading, List<SearchHit> hits)> groups;
  final String? hebrewFont;

  /// Shown when nothing matched.
  final String query;
  const SearchResults({super.key, required this.groups, required this.query, this.hebrewFont});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = [for (final g in groups) if (g.$2.isNotEmpty) g];
    if (shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(context.tr('Nothing found for “{q}”', {'q': query}),
            textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (heading, hits) in shown) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(heading, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
        ),
        for (final h in (hits.toList()..sort((a, b) => a.score.compareTo(b.score))))
          ListTile(
            leading: Icon(h.icon),
            title: Text(h.title,
                textDirection: h.hebrewTitle ? TextDirection.rtl : null,
                style: h.hebrewTitle ? TextStyle(fontFamily: hebrewFont, fontSize: 17) : null),
            subtitle: h.subtitle == null ? null : Text(h.subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () {
              analytics.event('search_result', {'group': heading, 'title': h.logAs ?? h.title});
              h.open(context);
            },
          ),
      ],
    ]);
  }
}
