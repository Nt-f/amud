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
