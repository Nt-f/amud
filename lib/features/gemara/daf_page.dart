import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'daf_layout.dart';
import 'gemara_data.dart';

/// The printed page of an amud (tzuras hadaf), laid out to the available
/// width. Tapping a word reports it, with its segment and, for Rashi and
/// Tosafot, which comment it is in.
class DafPage extends StatefulWidget {
  final DafText text;

  /// The selected Gemara segment, marked with its Rashi and Tosafot.
  final int? selected;

  /// Rashi and Tosafot comments marked more strongly than the rest of the
  /// passage's: the one tapped, or those quoting a tapped Gemara word.
  final Set<(DafColumn, int)> markedComments;

  /// Word-level marking in the selected segment (word-by-word tooltips):
  /// positions of Gemara words marked strongly (the tapped word) and lightly
  /// (the rest of its phrase). When set, the segment is not shaded as a
  /// whole, and of Rashi and Tosafot only a tapped comment is.
  final ({Set<int> strong, Set<int> light})? wordMarks;

  /// Segment → highlight color, from the reader's own marks.
  final Map<int, Color> highlights;
  /// A tap on the page: the word under it (null on empty space) and where,
  /// in global coordinates, so a tooltip can be placed over it.
  final void Function(PlacedWord? word, Offset global)? onTapWord;

  /// Press and hold on a word (reader mode starts from its passage).
  final void Function(PlacedWord word)? onHoldWord;

  /// The layout, whenever it changes (to find where a passage is).
  final void Function(DafLayout layout)? onLayout;
  final String mainFont;
  final String sideFont;

  /// Font size of the Gemara relative to the default for this width.
  final double scale;
  const DafPage({
    super.key,
    required this.text,
    this.selected,
    this.markedComments = const {},
    this.wordMarks,
    this.highlights = const {},
    this.onTapWord,
    this.onHoldWord,
    this.onLayout,
    this.mainFont = 'FrankRuehlCLM',
    this.sideFont = 'NotoRashiHebrew',
    this.scale = 1,
  });

  @override
  State<DafPage> createState() => _DafPageState();
}

/// The words of an amud for the layout: the Gemara (Vilna text) and the
/// margins' commentaries (see [DafText.margin]) with their opening words in
/// bold.
({List<DafWord> main, List<DafWord> inner, List<DafWord> outer}) dafWords(DafText t) {
  final main = <DafWord>[];
  for (var i = 0; i < t.length; i++) {
    main.addAll(wordsOfHtml(t.vilnaAt(i), segment: i));
  }
  List<DafWord> side({required bool inner}) => [
        for (final (n, c) in t.margin(inner: inner).indexed) ...[
          if (c.comment.split.$1.isNotEmpty) ...wordsOfHtml(c.comment.split.$1, segment: c.segment, comment: n, bold: true),
          ...wordsOfHtml(c.comment.split.$2, segment: c.segment, comment: n),
        ],
      ];

  return (main: main, inner: side(inner: true), outer: side(inner: false));
}

class _DafPageState extends State<DafPage> {
  DafLayout? _layout;
  ui.Picture? _picture;
  Object? _key;

  @override
  void dispose() {
    _picture?.dispose();
    super.dispose();
  }

  void _build(double width, Color ink, Color accent) {
    final key = (widget.text, width, widget.scale, widget.mainFont, widget.sideFont, ink, accent);
    if (key == _key) return;
    _key = key;
    final mainSize = width * 0.0235 * widget.scale;
    final sideSize = width * 0.0158 * widget.scale;
    TextStyle style(DafColumn c, DafWord w) => TextStyle(
          fontFamily: c == DafColumn.main ? widget.mainFont : widget.sideFont,
          fontSize: (c == DafColumn.main ? mainSize : sideSize) * w.scale,
          fontWeight: w.bold ? FontWeight.w700 : FontWeight.w400,
          color: w.scale > 1 ? accent : ink,
          height: 1,
        );
    final painters = <String, TextPainter>{};
    TextPainter painter(DafWord w, DafColumn c) => painters.putIfAbsent('${c.index}|${w.bold}|${w.scale}|${w.text}', () {
          return TextPainter(text: TextSpan(text: w.text, style: style(c, w)), textDirection: TextDirection.rtl)..layout();
        });
    final words = dafWords(widget.text);
    final layout = layoutDaf(
      main: words.main,
      inner: words.inner,
      outer: words.outer,
      width: width,
      innerOnRight: widget.text.amud.endsWith('a'),
      options: DafGeometryOptions(
        gap: width * 0.018,
        mainLineHeight: mainSize * 1.32,
        sideLineHeight: sideSize * 1.38,
        mainSpace: mainSize * 0.3,
        sideSpace: sideSize * 0.3,
      ),
      measure: (w, c) => painter(w, c).width,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final p in layout.words) {
      final tp = painter(p.word, p.column);
      // Center the glyphs vertically in the line box.
      tp.paint(canvas, Offset(p.x, p.y + (p.height - tp.height) / 2));
    }
    for (final tp in painters.values) {
      tp.dispose();
    }
    _picture?.dispose();
    _picture = recorder.endRecording();
    _layout = layout;
    final report = widget.onLayout;
    if (report != null) WidgetsBinding.instance.addPostFrameCallback((_) => report(layout));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth;
      _build(width, theme.colorScheme.onSurface, theme.colorScheme.primary);
      final layout = _layout!;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => widget.onTapWord?.call(layout.hit(d.localPosition.dx, d.localPosition.dy), d.globalPosition),
        onLongPressStart: (d) {
          final w = layout.hit(d.localPosition.dx, d.localPosition.dy);
          if (w != null) widget.onHoldWord?.call(w);
        },
        child: CustomPaint(
          size: Size(width, layout.height),
          painter: _DafPainter(
            layout: layout,
            picture: _picture!,
            selected: widget.selected,
            markedComments: widget.markedComments,
            wordMarks: widget.wordMarks,
            highlights: widget.highlights,
            colors: dafMarkColors(theme),
          ),
        ),
      );
    });
  }
}

/// Marker colors for a selected passage: one per column, so the Gemara,
/// Rashi and Tosafot of a passage are told apart at a glance.
({Color main, Color inner, Color outer}) dafMarkColors(ThemeData theme) {
  final dark = theme.brightness == Brightness.dark;
  return (
    main: theme.colorScheme.primary.withValues(alpha: dark ? 0.42 : 0.26),
    inner: (dark ? const Color(0xFFFFB300) : const Color(0xFFFFA000)).withValues(alpha: dark ? 0.38 : 0.32),
    outer: (dark ? const Color(0xFF26C6DA) : const Color(0xFF00ACC1)).withValues(alpha: dark ? 0.36 : 0.28),
  );
}

class _DafPainter extends CustomPainter {
  final DafLayout layout;
  final ui.Picture picture;
  final int? selected;
  final Set<(DafColumn, int)> markedComments;
  final ({Set<int> strong, Set<int> light})? wordMarks;
  final Map<int, Color> highlights;
  final ({Color main, Color inner, Color outer}) colors;
  _DafPainter({
    required this.layout,
    required this.picture,
    required this.selected,
    required this.markedComments,
    required this.wordMarks,
    required this.highlights,
    required this.colors,
  });

  Color strong(Color c) => c.withValues(alpha: (c.a * 1.8).clamp(0, 0.75));

  Color? _fill(PlacedWord w) {
    final seg = w.word.segment;
    final marks = wordMarks;
    if (marks != null && seg == selected) {
      if (w.column == DafColumn.main) {
        if (marks.strong.contains(w.word.position)) return strong(colors.main);
        if (marks.light.contains(w.word.position)) return colors.main;
        return highlights[seg];
      }
      final tapped = markedComments.contains((w.column, w.word.comment));
      return tapped ? strong(w.column == DafColumn.inner ? colors.inner : colors.outer) : null;
    }
    if (seg == selected) {
      final base = switch (w.column) {
        DafColumn.main => colors.main,
        DafColumn.inner => colors.inner,
        DafColumn.outer => colors.outer,
      };
      // The comment that was tapped stands out from its neighbors.
      final tapped = markedComments.contains((w.column, w.word.comment));
      return tapped ? strong(base) : base;
    }
    return w.column == DafColumn.main ? highlights[seg] : null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // One marker band per run of marked words on a line, not a blob per
    // word, so the passage reads as one stroke.
    final paint = Paint();
    Rect? band;
    Color? bandColor;
    PlacedWord? prev;
    void flush() {
      if (band != null) {
        paint.color = bandColor!;
        canvas.drawRRect(RRect.fromRectAndRadius(band!.inflate(1.5), const Radius.circular(3)), paint);
      }
      band = null;
      bandColor = null;
    }

    for (final w in layout.words) {
      final fill = _fill(w);
      final sameLine = prev != null && prev.column == w.column && (prev.y - w.y).abs() < 0.5;
      if (fill == null || fill != bandColor || !sameLine) flush();
      if (fill != null) {
        final r = Rect.fromLTWH(w.x, w.y, w.width, w.height);
        band = band == null ? r : band!.expandToInclude(r);
        bandColor = fill;
      }
      prev = w;
    }
    flush();
    canvas.drawPicture(picture);
  }

  @override
  bool shouldRepaint(_DafPainter old) =>
      old.picture != picture ||
      old.selected != selected ||
      old.markedComments != markedComments ||
      old.wordMarks != wordMarks ||
      old.highlights != highlights ||
      old.colors != colors;
}
