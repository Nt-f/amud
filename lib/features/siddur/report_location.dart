import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectionStatus;
import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';

import 'reader_typography.dart' show normalizeHebrewWords;

// Where a text report's selection is: the lines of corpus/siddur it was
// read from, not just the page it was read on. A page like Weekday Shacharit
// splices in Musaf for Rosh Chodesh, Hallel and the rest; the file says
// which. The lines are the build's (the report says which build it is).

/// The reader's rows that hold part of the selection now (see
/// [RowSelectionProbe]).
class SelectedRows {
  final _on = <_RowSelectionProbeState>{};

  /// Indexes of the rows with selected text, in order.
  List<int> get indexes => ({for (final s in _on) s.widget.index}.toList()..sort());

  /// The first row with selected text, and how far into its text (in
  /// characters) the selection starts.
  ({int row, int offset})? get start {
    final first = _on.fold<_RowSelectionProbeState?>(
        null, (a, s) => a == null || s.widget.index < a.widget.index ? s : a);
    if (first == null) return null;
    final r = first._notifier.registered ? first._notifier.selection.range : null;
    return (row: first.widget.index, offset: r == null ? 0 : (r.startOffset < r.endOffset ? r.startOffset : r.endOffset));
  }
}

/// Which of a row's [lines] holds the character at [offset] of the row's
/// text, taking the row as a linear block sets it: the lines' Hebrew, then
/// their English. An estimate (the reader's labels aren't counted), used
/// only to choose between places the selected words occur.
int? lineAt(List<SegmentItem> lines, int offset) {
  if (lines.isEmpty) return null;
  int len(ResolvedSegment? s) => s == null ? 0 : stripHtml(s.segment.html).length;
  var at = 0;
  for (final (i, l) in lines.indexed) {
    at += len(l.he);
    if (offset < at) return i;
  }
  for (final (i, l) in lines.indexed) {
    at += len(l.tr);
    if (offset < at) return i;
  }
  return lines.length - 1;
}

/// Keeps [rows] told whether this row holds part of the selection.
class RowSelectionProbe extends StatefulWidget {
  final int index;
  final SelectedRows rows;
  final Widget child;
  const RowSelectionProbe({super.key, required this.index, required this.rows, required this.child});

  @override
  State<RowSelectionProbe> createState() => _RowSelectionProbeState();
}

class _RowSelectionProbeState extends State<RowSelectionProbe> {
  // Each row owns its notifier: the list can build one index twice while it
  // scrolls to a key point.
  final _notifier = SelectionListenerNotifier();

  @override
  void initState() {
    super.initState();
    _notifier.addListener(_changed);
  }

  void _changed() {
    if (_notifier.registered && _notifier.selection.status == SelectionStatus.uncollapsed) {
      widget.rows._on.add(this);
    } else {
      widget.rows._on.remove(this);
    }
  }

  @override
  void didUpdateWidget(RowSelectionProbe old) {
    super.didUpdateWidget(old);
    if (old.rows != widget.rows) {
      old.rows._on.remove(this);
      _changed();
    }
  }

  @override
  void dispose() {
    widget.rows._on.remove(this);
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectionListener(selectionNotifier: _notifier, child: widget.child);
}

/// The lines a selection covers: Hebrew segments and English ones.
class SelectionSpot {
  final List<SegmentItem> he;
  final List<SegmentItem> en;

  /// Found by the selected words. Otherwise every line of the selected rows
  /// (the words weren't found as shown: a label inside them, a rewritten
  /// spelling).
  final bool exact;

  /// The words occur in more than one place among the candidates.
  final bool ambiguous;

  /// The leaves the lines are in, in reading order.
  final List<SchemaNode> leaves;
  const SelectionSpot(this.he, this.en, this.leaves, {required this.exact, this.ambiguous = false});
}

/// The segments in [items], in reading order.
List<SegmentItem> segmentsIn(Iterable<RenderItem> items) => [
      for (final it in items)
        ...switch (it) {
          SegmentItem s => [s],
          ExcludedGroupItem g => g.items,
          _ => const <SegmentItem>[],
        },
    ];

/// The sections [items] title (a heading row, a section not said today).
List<SchemaNode> sectionsIn(Iterable<RenderItem> items) => [
      for (final it in items)
        if (switch (it) {
          HeadingItem h => h.node,
          InsertedSectionItem s => s.node,
          CollapsedSectionItem s => s.node,
          _ => null,
        }
            case final SchemaNode n)
          n,
    ];

String _heLetters(String s) => normalizeHebrewWords(stripHtml(s)).replaceAll(' ', '');
String _enLetters(String s) => stripHtml(s).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// A side's text as said today (what the reader shows), and as written.
List<String> _variants(ResolvedSegment? s, String Function(String) letters) {
  if (s == null) return const ['', ''];
  final said = s.runs.where((r) => r.applicability != Applicability.notToday).map((r) => r.html).join();
  return [letters(said), letters(s.segment.html)];
}

/// Which of [candidates] (in reading order) hold [selected].
///
/// Each language is matched by its letters alone (no vowels, punctuation or
/// spaces, the divine name in one form), so a selection that runs from one
/// line into the next, or starts mid-word, is found. Where it isn't found,
/// lines sharing a run of words with it; then, unless [exactOnly], all of
/// them. Null when there is nothing to go on.
///
/// Words found in several places (one word, in a row that holds a whole
/// section) are told apart by [near], the candidate the selection starts in
/// as far as the reader can tell (see [lineAt]).
SelectionSpot? locateSelection(List<SegmentItem> candidates, String selected, {bool exactOnly = false, int? near}) {
  if (candidates.isEmpty) return null;
  final heSel = _heLetters(selected);
  final enSel = _enLetters(selected);
  var exact = false;
  var ambiguous = false;
  List<int> side(String sel, ResolvedSegment? Function(SegmentItem) of, String Function(String) letters) {
    if (sel.length < 2) return const [];
    final texts = [for (final c in candidates) _variants(of(c), letters)];
    for (final v in [0, 1]) {
      final found = _shortestRuns([for (final t in texts) t[v]], sel, near);
      if (found != null) {
        exact = true;
        ambiguous = ambiguous || found.ambiguous;
        return found.indexes;
      }
    }
    if (exactOnly) return const [];
    final shared = [
      for (final (i, t) in texts.indexed)
        if (_sharesWords(t[0], sel) || _sharesWords(t[1], sel)) i,
    ];
    if (shared.isNotEmpty) exact = true;
    return shared;
  }

  var he = side(heSel, (c) => c.he, _heLetters);
  var en = side(enSel, (c) => c.tr, _enLetters);
  if (he.isEmpty && en.isEmpty) {
    if (exactOnly) return null;
    exact = false;
    he = [for (final (i, c) in candidates.indexed) if (c.he != null) i];
    en = [for (final (i, c) in candidates.indexed) if (c.he == null && c.tr != null) i];
  }
  final seen = <String>{};
  final leaves = [
    for (final i in ({...he, ...en}.toList()..sort()))
      if (seen.add(candidates[i].node.id)) candidates[i].node,
  ];
  return SelectionSpot([for (final i in he) candidates[i]], [for (final i in en) candidates[i]], leaves,
      exact: exact, ambiguous: ambiguous);
}

/// The fewest consecutive lines whose text holds [sel], and only the lines
/// the match touches; null if none do. More than one place: the one nearest
/// [near], else [ambiguous] and the lines of each.
({List<int> indexes, bool ambiguous})? _shortestRuns(List<String> texts, String sel, int? near) {
  final found = <List<int>>[];
  var fewest = 1 << 30;
  for (var a = 0; a < texts.length; a++) {
    if (texts[a].isEmpty) continue;
    final text = StringBuffer();
    final starts = <int>[];
    for (var b = a; b < texts.length; b++) {
      starts.add(text.length);
      text.write(texts[b]);
      final s = text.toString();
      final at = s.indexOf(sel);
      if (at >= 0) {
        final touched = [
          for (var k = a; k <= b; k++)
            if (texts[k].isNotEmpty && starts[k - a] < at + sel.length && starts[k - a] + texts[k].length > at) k,
        ];
        if (touched.length < fewest) {
          fewest = touched.length;
          found.clear();
        }
        if (touched.length == fewest && !found.any((f) => f.first == touched.first)) found.add(touched);
        break;
      }
      // Lines past here can't need line a.
      if (s.length - texts[a].length >= sel.length) break;
    }
  }
  if (found.isEmpty) return null;
  if (found.length > 1 && near != null) {
    int distance(List<int> f) => near < f.first ? f.first - near : (near > f.last ? near - f.last : 0);
    final best = found.map(distance).reduce((a, b) => a < b ? a : b);
    final nearest = found.where((f) => distance(f) == best).toList();
    if (nearest.length == 1) return (indexes: nearest.single, ambiguous: false);
  }
  return (indexes: ({for (final f in found) ...f}.toList()..sort()), ambiguous: found.length > 1);
}

const _shingle = 8;

/// Shares a run of [_shingle] letters with [sel] (a selection with a label
/// or a rewritten word inside it).
bool _sharesWords(String text, String sel) {
  if (text.length < _shingle || sel.length < _shingle) return false;
  final grams = {for (var i = 0; i + _shingle <= sel.length; i++) sel.substring(i, i + _shingle)};
  for (var i = 0; i + _shingle <= text.length; i++) {
    if (grams.contains(text.substring(i, i + _shingle))) return true;
  }
  return false;
}

/// Refs in order, runs of numbers joined: 1, 2, 3, 5 → "1–3, 5".
String _refs(Iterable<String> refs) {
  final out = <String>[];
  final list = refs.toSet().toList();
  for (var i = 0; i < list.length; i++) {
    final n = int.tryParse(list[i]);
    var j = i;
    while (n != null && j + 1 < list.length && int.tryParse(list[j + 1]) == n + (j + 1 - i)) {
      j++;
    }
    out.add(j > i ? '${list[i]}–${list[j]}' : list[i]);
    i = j;
  }
  return out.join(', ');
}

/// Line numbers in order, runs joined: 331, 332, 333, 340 → ["331-333", "340"].
List<String> _lines(Iterable<int> lines) {
  final list = lines.toSet().toList()..sort();
  final out = <String>[];
  for (var i = 0; i < list.length; i++) {
    var j = i;
    while (j + 1 < list.length && list[j + 1] == list[j] + 1) {
      j++;
    }
    out.add(_span(list[i], list[j]));
    i = j;
  }
  return out;
}

String _span(int a, int b) => a == b ? '$a' : '$a-$b';

/// What a report names: a chunk file or a section, and its lines.
typedef _Place = ({String head, List<String> lines});

/// Each chunk file with the lines selected in it:
/// "corpus/siddur/ashkenaz/13_….json" and ["331-332"], or the leaf's path
/// line when only its title was selected; where the words weren't found,
/// "near" and the span of lines the rows hold. Null unless every line is
/// Amud's own text with its place known (not another version the reader
/// was set to, nor a corpus built without lines).
List<_Place>? _files(SelectionSpot spot, Corpus? corpus) {
  if (corpus == null) return null;
  final byFile = <String, Set<int>>{};
  for (final node in spot.leaves) {
    final leaf = corpus.leaf(node.id);
    if (leaf?.file == null || leaf?.line == null) return null;
    final lines = byFile.putIfAbsent(leaf!.file!, () => {});
    final shown = [
      for (final s in spot.he) if (s.node == node && s.he != null) s.he!.segment,
      for (final s in spot.en) if (s.node == node && s.tr != null) s.tr!.segment,
    ];
    for (final seg in shown) {
      if (seg.line == null) return null;
      for (var n = seg.line!; n <= (seg.lastLine ?? seg.line!); n++) {
        lines.add(n);
      }
    }
    // Selected in its title, not its lines.
    if (shown.isEmpty) lines.add(leaf.line!);
  }
  return [
    for (final MapEntry(key: file, value: lines) in byFile.entries)
      spot.exact
          ? (head: 'corpus/siddur/${corpus.nusach}/$file', lines: _lines(lines))
          : (head: 'near corpus/siddur/${corpus.nusach}/$file', lines: [_span(lines.reduce(min), lines.reduce(max))]),
  ];
}

/// Each leaf with its refs: "Festivals/Rosh Chodesh/…/Sanctity of the Day he 1–2"
/// (or "title"), for a book without lines to point to.
List<String> _sections(SelectionSpot spot) => [
      for (final leaf in spot.leaves)
        [
          leaf.id,
          if (!spot.exact) 'near',
          if (spot.he.any((s) => s.node == leaf))
            'he ${_refs([for (final s in spot.he) if (s.node == leaf && s.he != null) s.he!.segment.ref])}',
          if (spot.en.any((s) => s.node == leaf))
            'en ${_refs([for (final s in spot.en) if (s.node == leaf && s.tr != null) s.tr!.segment.ref])}',
          // Selected in its title, not its lines.
          if (!spot.he.any((s) => s.node == leaf) && !spot.en.any((s) => s.node == leaf)) 'title',
        ].join(' '),
    ];

String _two(int n) => n.toString().padLeft(2, '0');

/// The report's location: the lines of corpus/siddur the selection is in
/// (from [corpus]; else the book and each section's refs), the page read,
/// and the day it was read for with what that day is. Kept to [max]
/// characters (the Worker cuts what's longer), dropping files or sections
/// from the end, then the first file's last lines, so the day survives.
///
/// [date] is the Hebrew day the section is said on (Maariv's is the next
/// one), [civil] the civil date it was read on, if that isn't [date]'s.
String reportLocation({
  required String book,
  required String page,
  required SelectionSpot? spot,
  Corpus? corpus,
  required HDate date,
  DateTime? civil,
  required List<String> dayLabels,
  bool chosenDate = false,
  int max = 300,
}) {
  final g = civil ?? date.greg();
  final day = [
    '${chosenDate ? 'chosen date ' : ''}$date (${g.year}-${_two(g.month)}-${_two(g.day)})',
    if (dayLabels.isNotEmpty) dayLabels.join(', '),
  ].join(': ');
  if (spot == null) return _fit('$book › page $page (section not found) · $day', max);
  final files = _files(spot, corpus);
  final places = files ?? [for (final s in _sections(spot)) (head: s, lines: const <String>[])];
  String show(_Place p, int keep) => p.lines.isEmpty
      ? p.head
      : '${p.head}:${p.lines.take(keep).join(',')}${keep < p.lines.length ? ',…' : ''}';
  // [keep]: how many of the first place's runs of lines are shown.
  String build(int shown, [int? keep]) => [
        '${files == null ? '$book › ' : ''}'
            '${[for (final (i, p) in places.take(shown).indexed) show(p, i == 0 ? keep ?? p.lines.length : p.lines.length)].join('; ')}'
            '${shown < places.length ? '; +${places.length - shown} more' : ''}',
        'page $page',
        day,
      ].join(' · ');
  for (var shown = places.length; shown > 1; shown--) {
    if (build(shown).length <= max) return build(shown);
  }
  for (var keep = places.first.lines.length; keep > 1; keep--) {
    if (build(1, keep).length <= max) return build(1, keep);
  }
  return _fit(build(1, 1), max);
}

String _fit(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}…';
