import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The break between sections: two hairlines fading outward from a small
/// lozenge, the way a printed siddur marks where one prayer ends and the
/// next begins.
class SectionOrnament extends StatelessWidget {
  final Color? color;

  /// Total height, the ornament centered in it.
  final double height;

  /// Just the lozenge and dots, for a lighter break.
  final bool small;

  const SectionOrnament({super.key, this.color, this.height = 28, this.small = false});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.outline;
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _OrnamentPainter(c, small: small)),
      ),
    );
  }
}

class _OrnamentPainter extends CustomPainter {
  final Color color;
  final bool small;
  _OrnamentPainter(this.color, {required this.small});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final ink = Paint()..color = color.withValues(alpha: 0.75);
    // The lozenge.
    const r = 3.6;
    canvas.drawPath(
        Path()
          ..moveTo(cx, cy - r)
          ..lineTo(cx + r, cy)
          ..lineTo(cx, cy + r)
          ..lineTo(cx - r, cy)
          ..close(),
        ink);
    for (final dx in const [-11.0, 11.0]) {
      canvas.drawCircle(Offset(cx + dx, cy), 1.4, ink);
    }
    if (small) return;
    // Hairlines, solid near the center and fading toward the margins.
    final reach = math.min(size.width * 0.3, 160.0);
    for (final side in const [-1.0, 1.0]) {
      final from = Offset(cx + side * 20, cy), to = Offset(cx + side * (20 + reach), cy);
      // The gradient runs left to right; on the left the fade comes first.
      final fade = [color.withValues(alpha: 0.6), color.withValues(alpha: 0)];
      final line = Paint()
        ..strokeWidth = 0.8
        ..shader = LinearGradient(colors: side < 0 ? fade.reversed.toList() : fade).createShader(Rect.fromPoints(from, to));
      canvas.drawLine(from, to, line);
    }
  }

  @override
  bool shouldRepaint(_OrnamentPainter old) => old.color != color || old.small != small;
}

/// A printed frame, the way a siddur sets off a passage read from
/// elsewhere: a heavy outer rule and a fine inner one with a chain of
/// lozenges between them, a rosette in each corner and a hairline inside.
class OrnateFrame extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  const OrnateFrame({super.key, required this.child, required this.color, this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 16)});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _FramePainter(color),
      child: Padding(padding: const EdgeInsets.all(_FramePainter.band + _FramePainter.hairline + 2).add(padding), child: child),
    );
  }
}

class _FramePainter extends CustomPainter {
  final Color color;
  _FramePainter(this.color);

  /// The width of the band between the outer and inner rules.
  static const band = 10.0;

  /// Where the hairline sits inside the inner rule.
  static const hairline = 3.0;

  static Path _lozenge(Offset c, double rx, double ry) => Path()
    ..moveTo(c.dx, c.dy - ry)
    ..lineTo(c.dx + rx, c.dy)
    ..lineTo(c.dx, c.dy + ry)
    ..lineTo(c.dx - rx, c.dy)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    Paint rule(double width, double alpha) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color.withValues(alpha: alpha);
    final ink = Paint()..color = color.withValues(alpha: 0.8);
    final outer = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
    final inner = outer.deflate(band);
    canvas.drawRect(outer, rule(2, 0.75));
    canvas.drawRect(inner, rule(0.8, 0.6));
    canvas.drawRect(inner.deflate(hairline), rule(0.5, 0.35));

    // The chain: lozenges along the middle of the band, spaced evenly
    // between the corner squares, with a dot between each two.
    final mid = outer.deflate(band / 2);
    void chain(Offset from, Offset to, bool horizontal) {
      final length = (to - from).distance;
      const step = 11.0;
      final n = math.max(1, (length / step).floor());
      final d = (to - from) / n.toDouble();
      for (var i = 0; i < n; i++) {
        final c = from + d * (i + 0.5);
        canvas.drawPath(_lozenge(c, horizontal ? 3.2 : 2.2, horizontal ? 2.2 : 3.2), ink);
        if (i > 0) canvas.drawCircle(from + d * i.toDouble(), 0.9, ink);
      }
    }

    chain(Offset(outer.left + band, mid.top), Offset(outer.right - band, mid.top), true);
    chain(Offset(outer.left + band, mid.bottom), Offset(outer.right - band, mid.bottom), true);
    chain(Offset(mid.left, outer.top + band), Offset(mid.left, outer.bottom - band), false);
    chain(Offset(mid.right, outer.top + band), Offset(mid.right, outer.bottom - band), false);

    // A rosette in each corner square: a ruled square holding an open
    // lozenge with a dot at its heart.
    for (final c in [mid.topLeft, mid.topRight, mid.bottomLeft, mid.bottomRight]) {
      final square = Rect.fromCenter(center: c, width: band, height: band);
      canvas.drawRect(square, Paint()..color = color.withValues(alpha: 0.12));
      canvas.drawRect(square, rule(0.8, 0.6));
      canvas.drawPath(_lozenge(c, band / 2 - 1, band / 2 - 1), rule(0.9, 0.8));
      canvas.drawCircle(c, 1.5, ink);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.color != color;
}

/// A label set between rules, centered: for things the page tells the
/// reader rather than asks of them ("Added today: Ya'aleh VeYavo").
class RuledLabel extends StatelessWidget {
  final Widget child;
  final Color color;
  const RuledLabel({super.key, required this.child, required this.color});

  @override
  Widget build(BuildContext context) {
    // Equal rules either side, the label between them at its own width
    // (at most three quarters of the line), so it sits on the center.
    Widget rule() => Expanded(child: Container(height: 0.8, color: color.withValues(alpha: 0.45)));
    return LayoutBuilder(
      builder: (context, c) => Row(children: [
        rule(),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: c.maxWidth * 0.75),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: child),
        ),
        rule(),
      ]),
    );
  }
}
