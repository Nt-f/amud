import 'package:flutter/material.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/settings.dart';
import '../../core/typeset/typeset.dart';

/// The page style in use: [LinearStyle.off] unless the reader asked for the
/// linear page and the text is bilingual. The facing columns need a wide
/// page; a narrow one sets the English below instead.
LinearStyle linearPageStyle(AppSettings s, {required bool wide}) {
  if (s.linearStyle == LinearStyle.off || !(s.layout == TextLayout.interleaved || s.layout == TextLayout.sideBySide)) return LinearStyle.off;
  return s.linearStyle == LinearStyle.facing && !wide ? LinearStyle.below : s.linearStyle;
}

/// A line the linear page sets with its translation: plain said text in
/// both languages, with nothing about it that needs a row of its own.
bool linearLine(SegmentItem x) =>
    x.kind == SegmentKind.prayer &&
    !x.excluded &&
    x.he != null &&
    x.tr != null &&
    x.applicability == Applicability.always &&
    x.role == null &&
    x.select == null &&
    x.fold == null &&
    x.align == null &&
    !x.option &&
    !x.chazarah;

/// A run of lines ends at a full stop once it is this long, and whatever
/// they end in once it is [_hardLength] long or [_hardLines] lines.
const _softLength = 140;
const _hardLength = 360;
const _hardLines = 5;

final _stop = RegExp(r'[:.?!׃]\s*$');

/// The lines from [start] that the linear page sets together (see
/// [LinearBlock]): consecutive lines of one section, up to a sentence's
/// end once they've some length. Empty when [start] isn't such a line;
/// [also] lets the caller turn away lines it sets another way.
List<SegmentItem> linearRun(List<RenderItem> list, int start, {bool Function(SegmentItem)? also}) {
  final run = <SegmentItem>[];
  var length = 0;
  for (var i = start; i < list.length; i++) {
    final it = list[i];
    if (it is! SegmentItem || !linearLine(it) || (also != null && !also(it))) break;
    if (run.isNotEmpty && it.node != run.first.node) break;
    run.add(it);
    final he = it.he!.segment.plain.trim();
    length += he.length;
    if (run.length >= _hardLines || length >= _hardLength || (length >= _softLength && _stop.hasMatch(he))) break;
  }
  return run;
}

/// Several Hebrew lines above a rule, their English beneath it: how a
/// printed linear siddur sets a thought that runs over more than one line.
class LinearBlock extends StatelessWidget {
  final List<SegmentItem> lines;
  final Widget Function(SegmentItem) hebrew;
  final Widget Function(SegmentItem) english;
  const LinearBlock({super.key, required this.lines, required this.hebrew, required this.english});

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.outline;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final l in lines) hebrew(l),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(height: 0.8, color: ink.withValues(alpha: 0.55)),
      ),
      for (final l in lines) english(l),
    ]);
  }
}

/// The break between two blocks of the linear page.
class LinearDivider extends StatelessWidget {
  final double height;
  const LinearDivider({super.key, required this.height});

  @override
  Widget build(BuildContext context) => SectionOrnament(small: true, height: height);
}

/// The English and the Hebrew of one line side by side with a hairline
/// between them, drawn under the columns rather than measured beside them
/// (a paragraph can't be asked its height from a row of intrinsic height).
class LinearColumns extends StatelessWidget {
  final Widget english;
  final Widget hebrew;
  final double gap;
  const LinearColumns({super.key, required this.english, required this.hebrew, this.gap = 18});

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.outline;
    // Hebrew is always on the right, as in print, whichever way the app reads.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(children: [
        Positioned.fill(child: Align(child: Container(width: 0.8, color: ink.withValues(alpha: 0.55)))),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Padding(padding: EdgeInsets.only(right: gap), child: english)),
          Expanded(child: Padding(padding: EdgeInsets.only(left: gap), child: hebrew)),
        ]),
      ]),
    );
  }
}
