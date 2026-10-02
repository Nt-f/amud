import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

/// How to set one paragraph at one width.
@immutable
class ParagraphFit {
  /// [TextAlign.justify] when the lines justify without gaping, otherwise
  /// [TextAlign.start].
  final TextAlign align;

  /// Added to every word space, in logical pixels (negative tightens).
  final double wordSpacing;

  /// Lines it sets in.
  final int lines;

  /// The widest extra space justification puts in a word gap, in ems.
  final double looseness;

  /// The last line's share of the column.
  final double lastLine;

  const ParagraphFit(this.align, {this.wordSpacing = 0, this.lines = 1, this.looseness = 0, this.lastLine = 1});

  static const plain = ParagraphFit(TextAlign.start);

  @override
  String toString() => 'ParagraphFit($align, ws: ${wordSpacing.toStringAsFixed(2)}, lines: $lines, '
      'loose: ${looseness.toStringAsFixed(2)}em, last: ${(lastLine * 100).round()}%)';
}

/// Sets paragraphs the way a compositor would, within what Flutter's line
/// breaker allows: it can't choose the breaks, but it can be offered a
/// slightly tighter or looser word space and the result judged.
///
/// - **Runts.** A last line of a word or two looks like a mistake. The
///   fitter tries tightening the word space a little (up to an eighth of
///   an em) to pull it back, or loosening it to push a companion down.
/// - **Gaping.** Justification in a narrow column can open rivers of
///   space. When the loosest line would gape, the fitter tries the same
///   spacing range for a better set of breaks, and if none is good enough
///   the paragraph is set ragged instead.
///
/// Results are cached by the paragraph's content, style and width, so a
/// scrolled-back row costs nothing.
class ParagraphFitter {
  ParagraphFitter._();

  /// Extra space a justified gap may take, in ems, before it reads as a
  /// hole. A Hebrew word space is about a quarter em; this lets it grow
  /// to roughly three times that.
  static const maxGap = 0.55;

  /// Gaps up to this much still justify if nothing better can be found;
  /// past it the paragraph is set ragged.
  static const tolerableGap = 0.85;

  /// A last line narrower than this share of the column is a runt.
  static const minLastLine = 0.2;

  /// Word-space adjustments tried, in ems: tighter first (it keeps more
  /// on fewer lines), then looser.
  static const _trials = [-0.04, -0.08, -0.12, 0.05, 0.1];

  // Insertion-ordered: the first key is the least recently used.
  static final _cache = <Object, ParagraphFit>{};
  static const _cacheSize = 800;

  /// For tests.
  static void clearCache() => _cache.clear();

  static ParagraphFit fit({
    required InlineSpan text,
    required double width,
    required TextDirection textDirection,
    required double em,
    TextStyle? style,
    TextScaler textScaler = TextScaler.noScaling,
    StrutStyle? strutStyle,
    TextHeightBehavior? textHeightBehavior,
    Locale? locale,
    bool justify = true,
    bool balance = true,
  }) {
    if (!width.isFinite || width <= 0 || (!justify && !balance)) return ParagraphFit.plain;
    final key = (
      _signature(text),
      text.toPlainText(includePlaceholders: true),
      (width * 4).round(),
      textDirection,
      em,
      style,
      textScaler,
      strutStyle,
      textHeightBehavior,
      locale,
      justify,
      balance,
    );
    final hit = _cache.remove(key);
    if (hit != null) return _cache[key] = hit;
    final result = _fit(text, width, textDirection, textScaler.scale(em), style, textScaler, strutStyle, textHeightBehavior, locale,
        justify: justify, balance: balance);
    _cache[key] = result;
    if (_cache.length > _cacheSize) _cache.remove(_cache.keys.first);
    return result;
  }

  static ParagraphFit _fit(InlineSpan text, double width, TextDirection dir, double em, TextStyle? style, TextScaler scaler,
      StrutStyle? strut, TextHeightBehavior? thb, Locale? locale,
      {required bool justify, required bool balance}) {
    final plain = text.toPlainText(includePlaceholders: true);
    // Inline widgets (a "Today" chip) can't be measured from here; they're
    // estimated, so the paragraph is still justified but its last line
    // isn't second-guessed.
    final placeholders = <PlaceholderDimensions>[];
    text.visitChildren((s) {
      if (s is PlaceholderSpan) {
        placeholders.add(PlaceholderDimensions(
            size: Size(em * 5, em), alignment: s.alignment, baseline: s.baseline, baselineOffset: s.alignment == ui.PlaceholderAlignment.baseline ? em * 0.8 : null));
      }
      return true;
    });
    final estimated = placeholders.isNotEmpty;

    _Measure measure(double ws) {
      final painter = TextPainter(
        text: TextSpan(style: ws == 0 ? style : (style ?? const TextStyle()).copyWith(wordSpacing: ws), children: [text]),
        textDirection: dir,
        textScaler: scaler,
        strutStyle: strut,
        textHeightBehavior: thb,
        locale: locale,
      );
      try {
        if (estimated) painter.setPlaceholderDimensions(placeholders);
        painter.layout(maxWidth: width);
        return _Measure.of(painter, plain, width, em, ws);
      } finally {
        painter.dispose();
      }
    }

    final natural = measure(0);
    if (natural.lines <= 1) return ParagraphFit(justify ? TextAlign.justify : TextAlign.start, lines: natural.lines);
    final runt = balance && !estimated && natural.lastLine < minLastLine;
    final gaping = justify && natural.looseness > maxGap;
    var best = natural;
    if (runt || gaping) {
      var bestScore = natural.badness(justify: justify, balance: balance && !estimated);
      for (final t in _trials) {
        final m = measure(t * em);
        // Loosening only helps if it keeps the line count: one more line
        // to fix a runt trades one blemish for a worse one.
        if (t > 0 && m.lines > natural.lines) continue;
        final score = m.badness(justify: justify, balance: balance && !estimated) + t.abs() * 60;
        if (score < bestScore) {
          best = m;
          bestScore = score;
        }
      }
    }
    final align = justify && best.looseness <= tolerableGap ? TextAlign.justify : TextAlign.start;
    return ParagraphFit(align, wordSpacing: best.wordSpacing, lines: best.lines, looseness: best.looseness, lastLine: best.lastLine);
  }

  /// Content and style of a span tree, skipping gesture recognizers (made
  /// fresh on every build, they'd defeat the cache).
  static int _signature(InlineSpan span) {
    var h = 0;
    span.visitChildren((s) {
      h = switch (s) {
        TextSpan t => Object.hash(h, t.text, t.style),
        PlaceholderSpan p => Object.hash(h, p.alignment, p.baseline, p.style),
        _ => Object.hash(h, s.runtimeType, s.style),
      };
      return true;
    });
    return h;
  }
}

/// One trial setting, measured.
class _Measure {
  final double wordSpacing;
  final int lines;
  final double lastLine;
  final double looseness;

  /// Per-line justification gaps (ems), for the badness sum.
  final List<double> gaps;

  _Measure(this.wordSpacing, this.lines, this.lastLine, this.looseness, this.gaps);

  static final _space = RegExp(r'[   ]');

  factory _Measure.of(TextPainter painter, String plain, double width, double em, double ws) {
    final metrics = painter.computeLineMetrics();
    final gaps = <double>[];
    for (final m in metrics.take(metrics.length - 1)) {
      // The line's text: probe its middle, then take the whole line.
      final pos = painter.getPositionForOffset(Offset(m.left + m.width / 2, m.baseline));
      final range = painter.getLineBoundary(pos);
      if (!range.isValid || range.isCollapsed) continue;
      final end = math.min(range.end, plain.length);
      // A forced break ends its line like a paragraph: it isn't justified.
      if (end < plain.length && plain[end] == '\n') continue;
      final words = plain.substring(range.start, end).trim();
      final spaces = _space.allMatches(words).length;
      if (spaces == 0) continue;
      gaps.add(math.max(0, width - m.width) / spaces / em);
    }
    final last = metrics.isEmpty ? 1.0 : metrics.last.width / width;
    return _Measure(ws, metrics.length, last, gaps.isEmpty ? 0 : gaps.reduce(math.max), gaps);
  }

  /// Knuth–Plass style demerits: each line's looseness cubed, so one
  /// gaping line costs more than several slightly loose ones, plus a
  /// flat cost for a runt.
  double badness({required bool justify, required bool balance}) {
    var b = 0.0;
    if (justify) {
      for (final g in gaps) {
        final r = g / ParagraphFitter.maxGap;
        b += 100 * r * r * r;
      }
    }
    if (balance && lines > 1 && lastLine < ParagraphFitter.minLastLine) b += 250;
    return b;
  }
}
