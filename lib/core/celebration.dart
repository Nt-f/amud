import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A short burst of color over the screen when learning is finished:
/// confetti for the day's portion (a yomi), fireworks for a whole perek.
/// Drawn on the overlay, so it never blocks the page; taps pass through.
/// Skipped when the system asks for reduced motion.
enum Celebration { confetti, fireworks }

void celebrate(BuildContext context, Celebration kind) {
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => IgnorePointer(
      child: _CelebrationView(kind: kind, onDone: () => entry.remove()),
    ),
  );
  overlay.insert(entry);
}

const _colors = [
  Color(0xFFE53935),
  Color(0xFFFFB300),
  Color(0xFF43A047),
  Color(0xFF1E88E5),
  Color(0xFF8E24AA),
  Color(0xFF00ACC1),
  Color(0xFFF4511E),
];

class _CelebrationView extends StatefulWidget {
  final Celebration kind;
  final VoidCallback onDone;
  const _CelebrationView({required this.kind, required this.onDone});

  @override
  State<_CelebrationView> createState() => _CelebrationViewState();
}

class _CelebrationViewState extends State<_CelebrationView> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: widget.kind == Celebration.confetti ? const Duration(milliseconds: 2600) : const Duration(milliseconds: 3600),
  )
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    })
    ..forward();
  final _seed = math.Random().nextInt(1 << 30);

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: widget.kind == Celebration.confetti ? _Confetti(_t.value, _seed) : _Fireworks(_t.value, _seed),
        ),
      );
}

/// Pieces fall from above the top edge, swaying and turning.
class _Confetti extends CustomPainter {
  final double t;
  final int seed;
  _Confetti(this.t, this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed);
    final paint = Paint();
    const pieces = 110;
    for (var i = 0; i < pieces; i++) {
      final x0 = r.nextDouble() * size.width;
      final delay = r.nextDouble() * 0.35;
      final speed = 0.7 + r.nextDouble() * 0.6;
      final sway = 18 + r.nextDouble() * 30;
      final spin = (r.nextDouble() - 0.5) * 14;
      final w = 5 + r.nextDouble() * 5;
      final h = w * (0.4 + r.nextDouble() * 0.5);
      final color = _colors[r.nextInt(_colors.length)];
      final p = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final y = -20 + p * speed * (size.height + 60);
      final x = x0 + math.sin(p * 9 + i) * sway;
      final fade = p > 0.85 ? (1 - p) / 0.15 : 1.0;
      paint.color = color.withValues(alpha: fade.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(spin * p);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: w, height: h), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Confetti old) => old.t != t;
}

/// A few rockets burst one after another, their sparks falling and fading.
class _Fireworks extends CustomPainter {
  final double t;
  final int seed;
  _Fireworks(this.t, this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed);
    final paint = Paint()..strokeCap = StrokeCap.round;
    const bursts = 6;
    for (var b = 0; b < bursts; b++) {
      final start = b * 0.12 + r.nextDouble() * 0.05;
      final center = Offset(size.width * (0.15 + r.nextDouble() * 0.7), size.height * (0.15 + r.nextDouble() * 0.35));
      final color = _colors[r.nextInt(_colors.length)];
      final radius = math.min(size.width, size.height) * (0.18 + r.nextDouble() * 0.12);
      const sparks = 46;
      final angles = [for (var s = 0; s < sparks; s++) s * 2 * math.pi / sparks + r.nextDouble() * 0.12];
      final rise = 0.12;
      final p = (t - start) / 0.5;
      if (p <= 0 || p >= 1 + rise) continue;
      if (p < rise) {
        // The rocket climbing to its burst point.
        final q = p / rise;
        final pos = Offset(center.dx, size.height + (center.dy - size.height) * q);
        paint
          ..color = color
          ..strokeWidth = 3;
        canvas.drawLine(pos, pos + const Offset(0, 14), paint);
        continue;
      }
      final q = ((p - rise) / 1).clamp(0.0, 1.0);
      final ease = 1 - math.pow(1 - q, 3).toDouble();
      final fade = (1 - q).clamp(0.0, 1.0);
      for (final a in angles) {
        final d = radius * ease;
        final pos = center + Offset(math.cos(a) * d, math.sin(a) * d + 60 * q * q);
        final tail = center + Offset(math.cos(a) * d * 0.82, math.sin(a) * d * 0.82 + 60 * q * q);
        paint
          ..color = color.withValues(alpha: fade)
          ..strokeWidth = 2.6;
        canvas.drawLine(tail, pos, paint);
      }
      // A soft flash at the burst.
      if (q < 0.25) {
        paint
          ..color = Colors.white.withValues(alpha: (0.25 - q) * 2)
          ..strokeWidth = 0;
        canvas.drawCircle(center, 18 * (1 - q * 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Fireworks old) => old.t != t;
}
