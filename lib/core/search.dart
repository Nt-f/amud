import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics.dart';
import 'hebrew_text.dart';
import 'l10n.dart';

// --- Matching -----------------------------------------------------------------

final _marks = RegExp(r'[֑-ׇ]');
final _punct = RegExp(r'''[^\p{L}\p{N}]+''', unicode: true);

/// Lower case, without nikud, te'amim or punctuation, words separated by
/// single spaces.
String searchFold(String s) => s.replaceAll(_marks, '').toLowerCase().replaceAll(_punct, ' ').trim();

/// A rough consonant skeleton of each (Latin) word, so transliterations
/// match each other: Shacharit / Shacharis, Birkat / Birchas, Sukkot /
/// Sukkos, Tzitzit / Tsitsis.
String searchSkeleton(String s) => searchFold(s).split(' ').map(_skeletonWord).join(' ');

String _skeletonWord(String w) {
  var s = w
      .replaceAll('sh', 'š')
      .replaceAll('tz', 'z')
      .replaceAll('ts', 'z')
      .replaceAll('ch', 'h')
      .replaceAll('kh', 'h')
      .replaceAll('k', 'h')
      .replaceAll('s', 't')
      .replaceAll('w', 'v')
      .replaceAll(RegExp('[aeiouy]'), '');
  // Double letters (Shabbos / Shabos, Sukkot / Sukot).
  s = s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
  return s;
}

/// What the user typed, prepared for matching.
class SearchQuery {
  final String raw;
  final List<String> _words;
  final List<String> _skeletons;
  SearchQuery(this.raw)
      : _words = searchFold(raw).split(' ').where((w) => w.isNotEmpty).toList(),
        _skeletons = searchSkeleton(raw).split(' ').where((w) => w.isNotEmpty).toList();

  bool get isEmpty => _words.isEmpty;

  /// How well [texts] match: 0 (starts with the query) … 3 (a
  /// transliteration match); null when they don't. Every word typed must
  /// appear.
  int? score(Iterable<String?> texts) {
    if (isEmpty) return 0;
    final folded = [for (final t in texts) if (t != null && t.isNotEmpty) searchFold(t)];
    if (folded.isEmpty) return null;
    final all = folded.join(' | ');
    final phrase = _words.join(' ');
    if (folded.any((f) => f.startsWith(phrase))) return 0;
    if (_words.every((w) => RegExp('(^|[ |])${RegExp.escape(w)}').hasMatch(all))) return 1;
    if (_words.every(all.contains)) return 2;
    // The transliteration fallback needs enough consonants to mean
    // something ("a" or "sh" alone would match everything).
    if (_skeletons.join().length < 2 || _skeletons.length != _words.length) return null;
    // Each word's skeleton must start a word's skeleton: "minyan" (mn)
    // shouldn't turn up inside "Zmanim" (zmnm).
    final skel = [for (final f in folded) ...searchSkeleton(f).split(' ')];
    // Two consonants are too few to go on: then the whole word must match.
    if (_skeletons.every((w) => skel.any((t) => w.length < 3 ? t == w : t.startsWith(w)))) return 3;
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
