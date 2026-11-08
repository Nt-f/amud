import 'package:flutter/material.dart';

/// Gestures drawn as a mark at the words themselves rather than labelled
/// above the line: touching the shel yad or the shel rosh.
const inlineGestures = {'touch_tefillin_yad', 'touch_tefillin_rosh'};

/// The mark for [gesture] at the words where one touches the tefillin: a
/// small bayit with its shin, and beneath it יד or ראש, always in Hebrew,
/// in the instruction colour. Sized from the prayer text's [fontSize].
///
/// The first [word] goes inside the same widget, beside the mark and on the
/// line's baseline: a line can break on either side of an inline widget, so
/// only this keeps the mark from ending a line with its word on the next.
WidgetSpan tefillinMarkSpan(String gesture,
    {required double fontSize, required Color color, String? captionFont, List<InlineSpan> word = const []}) {
  final rosh = gesture == 'touch_tefillin_rosh';
  return WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    // The paragraph lays an inline widget out unscaled and scales it with
    // the text, so inside it nothing scales again.
    child: MediaQuery.withNoTextScaling(child: Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.rtl,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.only(end: fontSize * 0.12),
          child: _TefillinMark(rosh: rosh, fontSize: fontSize, color: color, captionFont: captionFont),
        ),
        if (word.isNotEmpty) Text.rich(TextSpan(children: word), textDirection: TextDirection.rtl, softWrap: false),
      ],
    )),
  );
}

/// [html] split for [tefillinMarkSpan]: its leading space, its first word
/// (with any tags around it), and the rest.
(String, String, String) splitFirstWord(String html) {
  final m = RegExp(r'^(\s*)((?:<[^>]*>)*[^\s<]+(?:<\/[^>]*>)*)([\s\S]*)$').firstMatch(html);
  return m == null ? ('', '', html) : (m[1]!, m[2]!, m[3]!);
}

class _TefillinMark extends StatelessWidget {
  final bool rosh;
  final double fontSize;
  final Color color;
  final String? captionFont;
  const _TefillinMark({required this.rosh, required this.fontSize, required this.color, this.captionFont});

  @override
  Widget build(BuildContext context) {
    // Unscaled: the paragraph scales the whole mark with the text.
    final icon = fontSize * 0.65;
    return Semantics(
      label: rosh ? 'Touch the shel rosh' : 'Touch the shel yad',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(size: Size(icon, icon * 15.5 / 16), painter: _BayitPainter(color)),
          SizedBox(height: icon * 0.06),
          Text(
            rosh ? 'ראש' : 'יד',
            textDirection: TextDirection.rtl,
            style: TextStyle(fontFamily: captionFont, fontSize: fontSize * 0.43, height: 1, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

/// The bayit on its titura with the shin on its face, from the design's
/// 24-unit drawing (viewBox 4 2.5 16 15.5).
class _BayitPainter extends CustomPainter {
  final Color color;
  _BayitPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 16;
    canvas.scale(k);
    canvas.translate(-4, -2.5);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(RRect.fromLTRBR(7, 4, 17, 14, const Radius.circular(1.4)), p);
    canvas.drawRect(const Rect.fromLTRB(6, 14, 18, 16.4), p);
    final shin = Path()
      ..moveTo(9.6, 7.2)
      ..lineTo(9.6, 10.5)
      ..arcToPoint(const Offset(14.4, 10.5), radius: const Radius.circular(2.4), clockwise: false)
      ..lineTo(14.4, 7.2)
      ..moveTo(12, 7.2)
      ..lineTo(12, 11.6);
    canvas.drawPath(shin, p);
  }

  @override
  bool shouldRepaint(_BayitPainter old) => old.color != color;
}
