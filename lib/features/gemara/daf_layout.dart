/// Tzuras hadaf: the Vilna page layout, Gemara in the middle with Rashi on
/// the inner margin and Tosafot on the outer one.
///
/// The geometry follows daf-renderer (github.com/TalmudLab/daf-renderer,
/// MIT, Dan Jutan and Shaun Regenbaum), the reference implementation
/// talmud.dev also ports:
///
///  * a top band four commentary lines tall where Rashi and Tosafot each take
///    half the page, above the start of the Gemara;
///  * below it three columns: Rashi, Gemara, Tosafot;
///  * when a commentary runs out before the Gemara, the Gemara widens into
///    its column (the "stairs");
///  * when the Gemara runs out first, the commentaries continue beneath it at
///    half the page each, and whichever is longer takes the full width once
///    the other ends;
///  * when one commentary is too short to reach below the top band, it moves
///    down into its column and the other takes the whole top band.
///
/// Flutter has no CSS floats, so instead of floating spacers this engine
/// breaks lines itself: each text flows into a region whose horizontal extent
/// depends on the height. Measuring is injected ([DafMeasure]) so the engine
/// is pure and testable.
library;

import 'dart:math' as math;

enum DafColumn { main, inner, outer }

/// A word to place. [segment] is the Gemara segment it belongs to (for a
/// commentary word, the segment the comment is on); [comment] numbers the
/// comment within its commentary on the amud (-1 for the Gemara).
class DafWord {
  final String text;
  final bool bold;

  /// Font size relative to the column's (the large opening word of a
  /// chapter is bigger).
  final double scale;
  final int segment;
  final int comment;

  /// Position among the words of the same text (a Gemara segment, or a
  /// comment's part).
  final int position;
  const DafWord(this.text, {this.bold = false, this.scale = 1, required this.segment, this.comment = -1, this.position = 0});
}

typedef DafMeasure = double Function(DafWord word, DafColumn column);

class DafGeometryOptions {
  /// Share of the page width the Gemara column takes.
  final double mainShare;

  /// Gap between columns and between the top band's halves.
  final double gap;
  final double mainLineHeight;
  final double sideLineHeight;

  /// Space between words before justification, per column.
  final double mainSpace;
  final double sideSpace;

  /// Lines of commentary above the Gemara.
  final int topLines;
  const DafGeometryOptions({
    this.mainShare = 0.48,
    this.gap = 10,
    required this.mainLineHeight,
    required this.sideLineHeight,
    required this.mainSpace,
    required this.sideSpace,
    this.topLines = 4,
  });
}

class PlacedWord {
  final DafWord word;
  final DafColumn column;
  final double x;
  final double y;
  final double width;
  final double height;

  /// The font size to draw it at, where the layout chose one; else the
  /// column's.
  final double? size;

  /// On the printed page, the word as the print sets it, drawn just so
  /// (then [word] is the text's word it stands for).
  final DafGlyphs? glyphs;
  const PlacedWord(this.word, this.column, this.x, this.y, this.width, this.height, {this.size, this.glyphs});

  bool contains(double px, double py) => px >= x && px <= x + width && py >= y && py <= y + height;
}

enum DafLayoutCase { doubleWrap, stairs, doubleExtend }

class DafLayout {
  final double width;
  final double height;
  final List<PlacedWord> words;
  final DafLayoutCase layoutCase;

  /// Drawn but not part of the text: the printed page's running head, page
  /// number and catchwords.
  final List<DafGlyphs> extras;
  const DafLayout(this.width, this.height, this.words, this.layoutCase, {this.extras = const []});

  /// The word at a point, if any (a little slack between words).
  PlacedWord? hit(double x, double y) {
    for (final w in words) {
      if (w.contains(x, y)) return w;
    }
    PlacedWord? best;
    var bestD = 12.0;
    for (final w in words) {
      if (y < w.y || y > w.y + w.height) continue;
      final d = x < w.x ? w.x - x : x - (w.x + w.width);
      if (d < bestD) {
        bestD = d;
        best = w;
      }
    }
    return best;
  }
}

/// A horizontal extent available at some height, or null for none.
typedef Region = ({double left, double right})? Function(double top, double bottom);

class _Flowed {
  final List<PlacedWord> words;
  final double bottom;
  const _Flowed(this.words, this.bottom);
}

/// Greedy, justified, right-to-left line breaking of [words] into [region],
/// starting at [top]. A line whose region is empty is skipped (moves down).
_Flowed _flow(
  List<DafWord> words,
  DafColumn column,
  DafMeasure measure,
  double lineHeight,
  double space,
  double top,
  Region region,
) {
  final placed = <PlacedWord>[];
  var y = top;
  var i = 0;
  var guard = 0;
  while (i < words.length) {
    if (++guard > 20000) break;
    // Lines with a big word are taller.
    final h = lineHeight * math.max(1, words[i].scale);
    final r = region(y, y + h);
    if (r == null || r.right - r.left < 1) {
      y += lineHeight;
      continue;
    }
    final avail = r.right - r.left;
    final line = <(DafWord, double)>[];
    var used = 0.0;
    var lineH = h;
    while (i < words.length) {
      final w = measure(words[i], column);
      final need = line.isEmpty ? w : used + space + w;
      if (line.isNotEmpty && need > avail) break;
      line.add((words[i], w));
      used = need;
      lineH = math.max(lineH, lineHeight * words[i].scale);
      i++;
    }
    // Justify every line but the column's last.
    final last = i >= words.length;
    final extra = !last && line.length > 1 ? (avail - used) / (line.length - 1) : 0.0;
    var x = r.right;
    for (final (word, w) in line) {
      x -= w;
      placed.add(PlacedWord(word, column, x, y + (lineH - lineHeight * word.scale), w, lineHeight * word.scale));
      x -= space + extra;
    }
    y += lineH;
  }
  return _Flowed(placed, words.isEmpty ? top : y);
}

/// Lays out an amud. [innerOnRight]: on amud a the inner margin (Rashi) is
/// on the right, on amud b on the left.
DafLayout layoutDaf({
  required List<DafWord> main,
  required List<DafWord> inner,
  required List<DafWord> outer,
  required double width,
  required bool innerOnRight,
  required DafGeometryOptions options,
  required DafMeasure measure,
}) {
  final g = options.gap;
  final side = width * (1 - options.mainShare) / 2;
  final hasInner = inner.isNotEmpty;
  final hasOuter = outer.isNotEmpty;
  final topBand = hasInner || hasOuter ? options.topLines * options.sideLineHeight : 0.0;

  // Horizontal extents.
  final innerSide = innerOnRight ? (left: width - side + g / 2, right: width) : (left: 0.0, right: side - g / 2);
  final outerSide = innerOnRight ? (left: 0.0, right: side - g / 2) : (left: width - side + g / 2, right: width);
  final innerHalf = innerOnRight ? (left: width / 2 + g / 2, right: width) : (left: 0.0, right: width / 2 - g / 2);
  final outerHalf = innerOnRight ? (left: 0.0, right: width / 2 - g / 2) : (left: width / 2 + g / 2, right: width);
  final full = (left: 0.0, right: width);

  _Flowed flowSide(List<DafWord> words, DafColumn col, Region region) =>
      _flow(words, col, measure, options.sideLineHeight, options.sideSpace, 0, region);

  // A commentary's region above the Gemara's end. [topMode]: 'half' (normal),
  // 'full' (the other commentary is absent from the top band) or 'none'
  // (this one is too short for the top band and starts in its column).
  Region upper(({double left, double right}) half, ({double left, double right}) column, String topMode) => (t, b) {
        if (t < topBand) {
          return switch (topMode) {
            'half' => b <= topBand ? half : null,
            'full' => b <= topBand ? full : null,
            _ => null,
          };
        }
        return column;
      };

  // Pass 1: natural flow (columns all the way down) to find the exception.
  var innerTop = 'half';
  var outerTop = 'half';
  if (hasInner && !hasOuter) innerTop = 'full';
  if (hasOuter && !hasInner) outerTop = 'full';
  if (hasInner && hasOuter) {
    final ni = flowSide(inner, DafColumn.inner, upper(innerHalf, innerSide, 'half'));
    final no = flowSide(outer, DafColumn.outer, upper(outerHalf, outerSide, 'half'));
    final innerShort = ni.bottom <= topBand;
    final outerShort = no.bottom <= topBand;
    if (innerShort && !outerShort) {
      innerTop = 'none';
      outerTop = 'full';
    } else if (outerShort && !innerShort) {
      outerTop = 'none';
      innerTop = 'full';
    }
  }
  final innerNatural = flowSide(inner, DafColumn.inner, upper(innerHalf, innerSide, innerTop));
  final outerNatural = flowSide(outer, DafColumn.outer, upper(outerHalf, outerSide, outerTop));
  final innerEnd = hasInner ? innerNatural.bottom : 0.0;
  final outerEnd = hasOuter ? outerNatural.bottom : 0.0;

  // Pass 2: the Gemara, widening into a commentary's column once that
  // commentary has ended above the line.
  final centerLeft = side + g / 2;
  final centerRight = width - side - g / 2;
  final mainFlow = _flow(main, DafColumn.main, measure, options.mainLineHeight, options.mainSpace, topBand, (t, b) {
    var left = centerLeft;
    var right = centerRight;
    final innerGone = innerEnd <= t;
    final outerGone = outerEnd <= t;
    if (innerGone) innerOnRight ? right = width : left = 0;
    if (outerGone) innerOnRight ? left = 0 : right = width;
    return (left: left, right: right);
  });
  final mainEnd = main.isEmpty ? topBand : mainFlow.bottom;

  // Pass 3: the commentaries below the Gemara: half the page each while
  // both continue, the full width once one has ended.
  Region lower(({double left, double right}) half, ({double left, double right}) column, String topMode, double otherEnd) {
    final up = upper(half, column, topMode);
    return (t, b) {
      if (b <= mainEnd || t < topBand) return up(t, b);
      if (t < mainEnd) return null; // straddles the Gemara's last line
      return t < otherEnd ? half : full;
    };
  }

  _Flowed innerFlow;
  _Flowed outerFlow;
  if (!hasInner || !hasOuter) {
    innerFlow = flowSide(inner, DafColumn.inner, lower(innerHalf, innerSide, innerTop, 0));
    outerFlow = flowSide(outer, DafColumn.outer, lower(outerHalf, outerSide, outerTop, 0));
  } else {
    // Which ends first when both run at half width below the Gemara?
    final hi = flowSide(inner, DafColumn.inner, lower(innerHalf, innerSide, innerTop, double.infinity));
    final ho = flowSide(outer, DafColumn.outer, lower(outerHalf, outerSide, outerTop, double.infinity));
    if (hi.bottom <= ho.bottom) {
      innerFlow = hi;
      outerFlow = flowSide(outer, DafColumn.outer, lower(outerHalf, outerSide, outerTop, hi.bottom));
    } else {
      outerFlow = ho;
      innerFlow = flowSide(inner, DafColumn.inner, lower(innerHalf, innerSide, innerTop, ho.bottom));
    }
  }

  final minComm = math.min(hasInner ? innerEnd : 0.0, hasOuter ? outerEnd : 0.0);
  final maxComm = math.max(innerEnd, outerEnd);
  final layoutCase = mainEnd <= minComm
      ? DafLayoutCase.doubleWrap
      : mainEnd < maxComm
          ? DafLayoutCase.stairs
          : DafLayoutCase.doubleExtend;

  return DafLayout(
    width,
    [mainEnd, innerFlow.bottom, outerFlow.bottom].reduce(math.max),
    [...mainFlow.words, ...innerFlow.words, ...outerFlow.words],
    layoutCase,
  );
}

// ------------------------------------------------------------------ printed

/// A word as the Romm Vilna page prints it: its letters in square type or
/// Rashi script, the left end of their advance at [left] on the baseline
/// [base], [sx] and [sy] pixels to the em across and up (the font size is
/// [sy]; a word squeezed or widened to its printed width has [sx] ≠ [sy]).
/// [big]: a section's big opening word.
class DafGlyphs {
  final String text;
  final bool rashi;
  final double left;
  final double base;
  final double sx;
  final double sy;
  final bool big;
  const DafGlyphs(this.text, {required this.rashi, required this.left, required this.base, required this.sx, required this.sy, this.big = false});
}

/// One word of a [DafPrint]: [column] and [index] are the text's word it
/// stands for, as [dafWords] numbers them; a column but index -1 for a word
/// of the print the text lacks; no column for the running head, page number
/// and catchwords.
class DafPrintWord {
  final DafColumn? column;
  final int index;
  final DafGlyphs glyphs;
  const DafPrintWord(this.column, this.index, this.glyphs);
}

/// Every word of an amud's Gemara, Rashi and Tosafot where the Romm Vilna
/// page prints it, read off its scan by tool/daf/svg.py (in the scan's
/// pixels). [frame] is the printed body's extent; [words] how many words
/// each column had in the text it was made from.
class DafPrint {
  final double left;
  final double top;
  final double right;
  final double bottom;
  final List<DafPrintWord> words;
  final Map<DafColumn, int> counts;

  /// Rashi script's letters are drawn this much (in em) heavier than the
  /// font's, as heavy as the print's.
  final double weight;
  const DafPrint({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.words,
    required this.counts,
    this.weight = 0,
  });

  static const _columns = {'m': DafColumn.main, 'i': DafColumn.inner, 'o': DafColumn.outer};
  static const _ids = {DafColumn.main: 'main', DafColumn.inner: 'inner', DafColumn.outer: 'outer'};

  /// Whether its words are numbered as these texts' are (else it is still
  /// drawn, but tapping a word can't say which it is).
  bool fits({required int main, required int inner, required int outer}) =>
      counts[DafColumn.main] == main && counts[DafColumn.inner] == inner && counts[DafColumn.outer] == outer;

  factory DafPrint.fromJson(Map<String, Object?> j) {
    final frame = [for (final v in j['frame'] as List) (v as num).toDouble()];
    final counts = (j['words'] as Map? ?? const {}).cast<String, Object?>();
    double d(Object? v) => (v as num).toDouble();
    return DafPrint(
      left: frame[0],
      top: frame[1],
      right: frame[2],
      bottom: frame[3],
      weight: (j['weight'] as num?)?.toDouble() ?? 0,
      counts: {for (final MapEntry(key: c, value: id) in _ids.entries) c: (counts[id] as num?)?.toInt() ?? -1},
      words: [
        for (final w in j['placed'] as List)
          if (w case [final String c, final num k, final num font, final String text, final l, final b, final sx, final sy, ...final rest])
            DafPrintWord(
              _columns[c],
              k.toInt(),
              DafGlyphs(text, rashi: font == 1, left: d(l), base: d(b), sx: d(sx), sy: d(sy), big: rest.isNotEmpty && rest.first == 1),
            ),
      ],
    );
  }
}

/// The amud as the Vilna page prints it ([print]), scaled to [width]: every
/// word where the print has it, linked to the text's word it stands for
/// ([main], [inner], [outer], numbered as [dafWords] numbers them). A word
/// of the print the text lacks takes the passage of the word before it in
/// its column; with text numbered otherwise ([DafPrint.fits]) no word is
/// linked. [advance] gives a word's advance in em, in square type or Rashi
/// script.
DafLayout layoutPrint({
  required List<DafWord> main,
  required List<DafWord> inner,
  required List<DafWord> outer,
  required DafPrint print,
  required double width,
  required double Function(String text, bool rashi) advance,
}) {
  final s = width / (print.right - print.left);
  final linked = print.fits(main: main.length, inner: inner.length, outer: outer.length);
  final texts = {DafColumn.main: main, DafColumn.inner: inner, DafColumn.outer: outer};
  final last = <DafColumn, DafWord>{};
  final placed = <PlacedWord>[];
  final extras = <DafGlyphs>[];
  for (final w in print.words) {
    final g = w.glyphs;
    final glyphs = DafGlyphs(
      g.text,
      rashi: g.rashi,
      left: (g.left - print.left) * s,
      base: (g.base - print.top) * s,
      sx: g.sx * s,
      sy: g.sy * s,
      big: g.big,
    );
    final column = w.column;
    if (column == null) {
      extras.add(glyphs);
      continue;
    }
    final text = texts[column]!;
    final own = linked && w.index >= 0 && w.index < text.length ? text[w.index] : null;
    final before = last[column];
    final word = own ?? DafWord(g.text, segment: before?.segment ?? 0, comment: before?.comment ?? -1, position: -1);
    if (own != null) last[column] = own;
    // Its box: the advance across, the letters' body and a little above
    // and below.
    final w0 = advance(g.text, g.rashi) * glyphs.sx;
    placed.add(PlacedWord(word, column, glyphs.left, glyphs.base - 0.95 * glyphs.sy, w0, 1.25 * glyphs.sy, glyphs: glyphs));
  }
  return DafLayout(width, (print.bottom - print.top) * s, placed, DafLayoutCase.doubleWrap, extras: extras);
}

// ------------------------------------------------------------------ input

final _tag = RegExp(r'<(/?)([a-zA-Z]+)[^>]*>');

/// Words of a Sefaria HTML string, with `<b>`/`<strong>` as bold and `<big>` as a
/// larger word. Footnotes and other markup are dropped.
List<DafWord> wordsOfHtml(String html, {required int segment, int comment = -1, bool bold = false, double bigScale = 1.7}) {
  final out = <DafWord>[];
  var depthBold = 0;
  var depthBig = 0;
  var skip = 0;
  void text(String t) {
    if (skip > 0) return;
    for (final w in t.replaceAll('&nbsp;', ' ').replaceAll('&thinsp;', ' ').split(RegExp(r'\s+'))) {
      if (w.isEmpty) continue;
      out.add(DafWord(w,
          bold: bold || depthBold > 0, scale: depthBig > 0 ? bigScale : 1, segment: segment, comment: comment, position: out.length));
    }
  }

  var i = 0;
  for (final m in _tag.allMatches(html)) {
    text(html.substring(i, m.start));
    i = m.end;
    final closing = m.group(1) == '/';
    final name = m.group(2)!.toLowerCase();
    final d = closing ? -1 : 1;
    if (name == 'b' || name == 'strong') depthBold = math.max(0, depthBold + d);
    if (name == 'big') depthBig = math.max(0, depthBig + d);
    // Sefaria footnotes: <sup class="footnote-marker">1</sup><i class="footnote">…</i>
    if (name == 'sup' || (name == 'i' && (closing ? skip > 0 : m.group(0)!.contains('footnote')))) {
      skip = math.max(0, skip + d);
    }
  }
  text(html.substring(i));
  return out;
}
