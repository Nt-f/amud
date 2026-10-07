import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Brand colors from the Amud logo.
const amudInk = Color(0xFF172A5C);
const _paper = Color(0xFFF8F3EA);
const _fan = Color(0xFFA9C0EE);
const _fanDeep = Color(0xFF6F8CC0);

/// Plays the Amud launch animation over [child] once per app start: the
/// podium lines fly in, the pages fan open and the wordmark rises, then it
/// fades into the app. A tap anywhere skips straight to the fade.
/// With reduced motion the finished logo shows, still, for 1.2 seconds.
/// On the web the page's own copy of the animation already played while the
/// app loaded, so it's skipped there.
class LaunchAnimation extends StatefulWidget {
  final Widget child;
  const LaunchAnimation({super.key, required this.child});

  static bool _played = false;

  /// Lets a test play it again in the same run.
  @visibleForTesting
  static void resetForTest() => _played = false;

  @override
  State<LaunchAnimation> createState() => _LaunchAnimationState();
}

class _LaunchAnimationState extends State<LaunchAnimation> with TickerProviderStateMixin {
  // The podium is built (lines land by 1.27 s) and the siddur opens on it
  // while it settles (0.95–1.8 s), the wordmark rises (1.75–2.35 s), and it
  // all holds a moment before fading into the app.
  static const _length = Duration(milliseconds: 3100);
  // Both keep their length when the system asks for reduced motion
  // (AnimationController would otherwise run them 20 times faster, so the
  // logo only blinked); reduced motion is handled here instead.
  late final AnimationController _c = AnimationController(vsync: this, duration: _length, animationBehavior: AnimationBehavior.preserve);
  late final AnimationController _fade =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 400), animationBehavior: AnimationBehavior.preserve);

  /// How long the finished logo shows, still, with reduced motion (the same
  /// as the web page's splash).
  static const _stillLength = Duration(milliseconds: 1200);
  bool _show = !kIsWeb && !LaunchAnimation._played;

  @override
  void initState() {
    super.initState();
    LaunchAnimation._played = true;
    // Start once the first frame is on screen, plus a beat: the app's first
    // frames are slow, and a clock started earlier would spend the podium
    // stage behind the native launch screen.
    if (_show) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!mounted || _finishing) return;
        if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
          _c.value = 1;
          await Future<void>.delayed(_stillLength);
          await _finish();
        } else {
          _c.forward().whenComplete(_finish);
        }
      });
    }
  }

  bool _finishing = false;

  Future<void> _finish() async {
    if (!mounted || !_show || _finishing) return;
    _finishing = true;
    _c.stop();
    await _fade.forward();
    if (mounted) setState(() => _show = false);
  }

  @override
  void dispose() {
    _c.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return widget.child;
    return Stack(children: [
      widget.child,
      Positioned.fill(
        child: FadeTransition(
          opacity: ReverseAnimation(_fade),
          // Nothing reaches the app until the animation is done; a tap
          // only skips it.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _finish,
            child: AbsorbPointer(
              child: ColoredBox(
                color: amudInk,
                child: Semantics(
                  label: 'Amud',
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) {
                      final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
                      final t = still ? _length.inMilliseconds / 1000 : _c.value * _length.inMilliseconds / 1000;
                      final word = _segment(t, 1.75, .6, Curves.easeOut);
                      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        CustomPaint(size: const Size.square(240), painter: _MarkPainter(t)),
                        const SizedBox(height: 20),
                        Opacity(
                          opacity: word,
                          child: Transform.translate(
                            offset: Offset(0, 10 * (1 - word)),
                            child: const Text('amud',
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                  fontFamily: 'Fraunces',
                                  fontFamilyFallback: ['Georgia', 'serif'],
                                  fontWeight: FontWeight.w600,
                                  fontSize: 56,
                                  letterSpacing: -1.5,
                                  color: _paper,
                                  decoration: TextDecoration.none,
                                )),
                          ),
                        ),
                      ]);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Progress 0–1 of a step starting at [start] seconds lasting [length].
double _segment(double t, double start, double length, Curve curve) => curve.transform(((t - start) / length).clamp(0.0, 1.0));

// The mark, in the design's SVG coordinates (viewBox 16 20 168 168).
final _left = Path()
  ..moveTo(97, 92)
  ..cubicTo(84, 80, 62, 75, 44, 76)
  ..lineTo(40, 30)
  ..cubicTo(62, 29, 84, 36, 97, 50)
  ..close();
final _right = Path()
  ..moveTo(103, 92)
  ..cubicTo(116, 80, 138, 75, 156, 76)
  ..lineTo(160, 30)
  ..cubicTo(138, 29, 116, 36, 103, 50)
  ..close();

/// Podium lines with where each is thrown in from (dx, dy, degrees).
const _lines = [
  (Offset(50, 106), Offset(150, 106), Offset(-160, -130), -80.0),
  (Offset(64, 119), Offset(136, 119), Offset(150, -150), 65.0),
  (Offset(82, 133), Offset(82, 172), Offset(-170, 90), 120.0),
  (Offset(100, 133), Offset(100, 180), Offset(20, 210), -150.0),
  (Offset(118, 133), Offset(118, 172), Offset(170, 110), 95.0),
];

const _throwCurve = Cubic(.18, 1.35, .4, 1);
const _openCurve = Cubic(.2, .8, .3, 1);

class _MarkPainter extends CustomPainter {
  final double t;
  _MarkPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 168);
    canvas.translate(-16, -20);

    // Pages: back layers first, each unfolding from the spine.
    for (final (color, angle, delay) in [(_fanDeep, 14.0, 1.2), (_fan, 7.0, 1.08), (_paper, 0.0, .95)]) {
      final p = _segment(t, delay, .6, _openCurve);
      if (p <= 0) continue;
      final paint = Paint()..color = color.withValues(alpha: p);
      for (final (path, pivot, sign) in [(_left, const Offset(97, 92), -1.0), (_right, const Offset(103, 92), 1.0)]) {
        canvas.save();
        canvas.translate(pivot.dx, pivot.dy);
        canvas.rotate(sign * angle * 3.14159265 / 180);
        canvas.scale(p, 1);
        canvas.translate(-pivot.dx, -pivot.dy);
        canvas.drawPath(path, paint);
        canvas.restore();
      }
    }

    // Lines: thrown in, spinning and shrinking into place.
    for (final (i, (a, b, from, degrees)) in _lines.indexed) {
      final start = i * .08;
      final raw = ((t - start) / .95).clamp(0.0, 1.0);
      if (raw <= 0) continue;
      final p = _throwCurve.transform(raw);
      final opacity = (raw / .18).clamp(0.0, 1.0);
      final center = (a + b) / 2;
      canvas.save();
      canvas.translate(center.dx + from.dx * (1 - p), center.dy + from.dy * (1 - p));
      canvas.rotate(degrees * (1 - p) * 3.14159265 / 180);
      final scale = 1 + .5 * (1 - p);
      canvas.scale(scale);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = _paper.withValues(alpha: opacity)
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.t != t;
}
