import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Swipe sideways across a reader to turn to the next or previous page
/// (section, siman, psalm), the way a book turns: toward the start of the
/// line, so a Hebrew interface turns the other way.
///
/// Swipes that start near either side of the screen are left alone: that's
/// the system's back gesture. Touch only, since a mouse drag selects text. Found from raw pointer events, like
/// [DoubleTapListener], so vertical scrolling and taps are untouched; the
/// text follows the finger a little so the swipe can be seen.
class PageSwipe extends StatefulWidget {
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final Widget child;
  const PageSwipe({super.key, this.onNext, this.onPrevious, required this.child});

  /// Width at each side of the screen kept for the back gesture.
  static const edge = 32.0;

  /// How far a swipe must go to turn the page.
  static const distance = 72.0;

  @override
  State<PageSwipe> createState() => _PageSwipeState();
}

class _PageSwipeState extends State<PageSwipe> with SingleTickerProviderStateMixin {
  late final AnimationController _settle;
  int? _pointer;
  Offset? _down;
  Duration? _downTime;
  double _shift = 0;
  double _from = 0;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))
      ..addListener(() => setState(() => _shift = _from * (1 - Curves.easeOut.transform(_settle.value))));
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  /// The callback for a swipe of [dx] (negative is leftward), if any.
  VoidCallback? _target(double dx) {
    final forward = _rtl ? dx > 0 : dx < 0;
    return forward ? widget.onNext : widget.onPrevious;
  }

  void _start(PointerDownEvent e) {
    if (_pointer != null) {
      // A second finger (pinch to zoom): not a swipe.
      _reset();
      return;
    }
    // Touch only: dragging with a mouse selects text.
    if (e.kind != PointerDeviceKind.touch && e.kind != PointerDeviceKind.stylus) return;
    final width = MediaQuery.sizeOf(context).width;
    final insets = MediaQuery.systemGestureInsetsOf(context);
    final x = e.position.dx;
    if (x < max(PageSwipe.edge, insets.left + 8) || x > width - max(PageSwipe.edge, insets.right + 8)) return;
    _pointer = e.pointer;
    _down = e.position;
    _downTime = e.timeStamp;
  }

  (double, double)? _delta(PointerEvent e) {
    final down = _down;
    if (e.pointer != _pointer || down == null) return null;
    final d = e.position - down;
    return (d.dx, d.dy);
  }

  /// Sideways enough to be a page turn rather than scrolling.
  static bool _sideways(double dx, double dy) => dx.abs() > 12 && dx.abs() > dy.abs() * 2;

  void _move(PointerMoveEvent e) {
    final d = _delta(e);
    if (d == null) return;
    final (dx, dy) = d;
    final shift = _sideways(dx, dy) && _target(dx) != null ? (dx * 0.3).clamp(-40.0, 40.0) : 0.0;
    if (shift != _shift) setState(() => _shift = shift);
  }

  void _end(PointerUpEvent e) {
    final d = _delta(e);
    final downTime = _downTime;
    _reset();
    if (d == null || downTime == null) return;
    final (dx, dy) = d;
    // Quick and sideways; a long hold first is selecting text.
    if (dx.abs() < PageSwipe.distance || !_sideways(dx, dy) || e.timeStamp - downTime > const Duration(milliseconds: 700)) return;
    _target(dx)?.call();
  }

  void _reset() {
    _pointer = null;
    _down = null;
    _downTime = null;
    if (_shift != 0) {
      _from = _shift;
      _settle.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _start,
        onPointerMove: _move,
        onPointerUp: _end,
        onPointerCancel: (_) => _reset(),
        child: Transform.translate(offset: Offset(_shift, 0), child: widget.child),
      );
}

/// Swipe sideways to move between the app's tabs: [onNext] and
/// [onPrevious] follow [PageSwipe]'s directions, which match the order of
/// the navigation bar in either interface direction.
///
/// Unlike [PageSwipe] it takes part in the gesture arena, so a slider or a
/// sideways list under the finger keeps the drag. Touch only, and swipes
/// from the screen edges are left for the system's back gesture.
class TabSwipe extends StatefulWidget {
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final Widget child;
  const TabSwipe({super.key, this.onNext, this.onPrevious, required this.child});

  @override
  State<TabSwipe> createState() => _TabSwipeState();
}

class _TabSwipeState extends State<TabSwipe> with SingleTickerProviderStateMixin {
  late final AnimationController _settle;
  bool _tracking = false;
  double _dx = 0;
  double _shift = 0;
  double _from = 0;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))
      ..addListener(() => setState(() => _shift = _from * (1 - Curves.easeOut.transform(_settle.value))));
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  VoidCallback? _target(double dx) {
    final forward = Directionality.of(context) == TextDirection.rtl ? dx > 0 : dx < 0;
    return forward ? widget.onNext : widget.onPrevious;
  }

  void _start(DragStartDetails d) {
    final width = MediaQuery.sizeOf(context).width;
    final insets = MediaQuery.systemGestureInsetsOf(context);
    final x = d.globalPosition.dx;
    _tracking = x >= max(PageSwipe.edge, insets.left + 8) && x <= width - max(PageSwipe.edge, insets.right + 8);
    _dx = 0;
  }

  void _update(DragUpdateDetails d) {
    if (!_tracking) return;
    _dx += d.delta.dx;
    final shift = _target(_dx) != null ? (_dx * 0.3).clamp(-40.0, 40.0) : 0.0;
    if (shift != _shift) setState(() => _shift = shift);
  }

  void _end(DragEndDetails d) {
    final dx = _dx, v = d.primaryVelocity ?? 0;
    final tracking = _tracking;
    _reset();
    if (!tracking) return;
    // Far enough, or a quick flick the same way.
    if (dx.abs() >= PageSwipe.distance || dx.abs() >= 24 && v.abs() > 800 && v.sign == dx.sign) {
      _target(dx)?.call();
    }
  }

  void _reset() {
    _tracking = false;
    _dx = 0;
    if (_shift != 0) {
      _from = _shift;
      _settle.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    // With nowhere to go, stay out of the arena altogether.
    final on = widget.onNext != null || widget.onPrevious != null;
    return GestureDetector(
      supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus},
      onHorizontalDragStart: on ? _start : null,
      onHorizontalDragUpdate: on ? _update : null,
      onHorizontalDragEnd: on ? _end : null,
      onHorizontalDragCancel: on ? _reset : null,
      child: Transform.translate(offset: Offset(_shift, 0), child: widget.child),
    );
  }
}
