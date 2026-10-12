import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A short burst of fireworks over the whole screen, for finishing
/// something worth marking (an aliyah). Skipped when the device asks for
/// less motion.
void showFireworks(BuildContext context) {
  if (MediaQuery.disableAnimationsOf(context)) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  HapticFeedback.mediumImpact();
  late final OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _Fireworks(onDone: () => entry.remove()));
  overlay.insert(entry);
}

class _Burst {
  final Offset at; // fraction of the screen
  final double start; // fraction of the whole show
  final Color color;
  final int sparks;
  const _Burst(this.at, this.start, this.color, this.sparks);
}

class _Fireworks extends StatefulWidget {
  final VoidCallback onDone;
  const _Fireworks({required this.onDone});

  @override
  State<_Fireworks> createState() => _FireworksState();
}

class _FireworksState extends State<_Fireworks> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    })
    ..forward();
  late final List<_Burst> _bursts = () {
    final r = math.Random();
    const colors = [Color(0xFFFFC857), Color(0xFFFF6B6B), Color(0xFF6EC1E4), Color(0xFF7BD389), Color(0xFFC3A6F2), Color(0xFFFFFFFF)];
    return [
      for (var i = 0; i < 7; i++)
        _Burst(Offset(0.15 + r.nextDouble() * 0.7, 0.15 + r.nextDouble() * 0.4), i * 0.1 + r.nextDouble() * 0.05,
            colors[r.nextInt(colors.length)], 22 + r.nextInt(10)),
    ];
  }();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedBuilder(animation: _c, builder: (_, _) => CustomPaint(size: Size.infinite, painter: _Painter(_bursts, _c.value))),
        ),
      );
}

class _Painter extends CustomPainter {
  final List<_Burst> bursts;
  final double t;
  _Painter(this.bursts, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    const life = 0.45; // of the show, per burst
    for (final b in bursts) {
      final p = (t - b.start) / life;
      if (p <= 0 || p >= 1) continue;
      final eased = 1 - math.pow(1 - p, 3).toDouble();
      final center = Offset(b.at.dx * size.width, b.at.dy * size.height);
      final reach = size.shortestSide * 0.28;
      final paint = Paint()
        ..color = b.color.withValues(alpha: (1 - p) * 0.95)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3 * (1 - p) + 1;
      for (var i = 0; i < b.sparks; i++) {
        final a = i / b.sparks * math.pi * 2;
        final d = reach * eased * (0.75 + 0.25 * ((i * 7) % 3) / 2);
        // Sparks fall a little as they fade.
        final from = center + Offset(math.cos(a), math.sin(a)) * (d * 0.8) + Offset(0, 30 * p * p);
        final to = center + Offset(math.cos(a), math.sin(a)) * d + Offset(0, 30 * p * p);
        canvas.drawLine(from, to, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Painter old) => old.t != t;
}
