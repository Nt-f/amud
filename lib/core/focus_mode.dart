import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// For reading screens with focus mode ([focusModeProvider]): it lasts
/// while readers are open, so it survives moving to the next section
/// (which swaps one reader for another), and ends when the last one closes.
mixin FocusModeReader<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  static int _open = 0;
  late final StateController<bool> focusMode;

  @override
  void initState() {
    super.initState();
    _open++;
    focusMode = ref.read(focusModeProvider.notifier);
  }

  @override
  void dispose() {
    _open--;
    // Providers can't change while the tree is being torn down.
    scheduleMicrotask(() {
      if (_open == 0) focusMode.state = false;
    });
    super.dispose();
  }

  void toggleFocusMode() => focusMode.state = !focusMode.state;
}

/// Calls [onDoubleTap] on a double tap anywhere in [child], found from raw
/// pointer events so single taps on rows aren't delayed and scrolling isn't
/// disturbed.
class DoubleTapListener extends StatefulWidget {
  final VoidCallback onDoubleTap;
  final Widget child;
  const DoubleTapListener({super.key, required this.onDoubleTap, required this.child});

  @override
  State<DoubleTapListener> createState() => _DoubleTapListenerState();
}

class _DoubleTapListenerState extends State<DoubleTapListener> {
  Offset? _downAt;
  Duration? _downTime;
  (Offset, Duration)? _lastTap;

  void _up(PointerUpEvent e) {
    final down = _downAt, downTime = _downTime;
    _downAt = null;
    if (down == null || downTime == null) return;
    final isTap = (e.position - down).distance < kTouchSlop && e.timeStamp - downTime < kLongPressTimeout;
    if (!isTap) {
      _lastTap = null;
      return;
    }
    final last = _lastTap;
    if (last != null && e.timeStamp - last.$2 < kDoubleTapTimeout && (e.position - last.$1).distance < kDoubleTapSlop) {
      _lastTap = null;
      widget.onDoubleTap();
    } else {
      _lastTap = (e.position, e.timeStamp);
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (e) {
          _downAt = e.position;
          _downTime = e.timeStamp;
        },
        onPointerUp: _up,
        onPointerCancel: (_) => _downAt = null,
        child: widget.child,
      );
}

/// A reader's top bars, which slide up out of view in focus mode.
class FocusModeBars extends ConsumerWidget {
  final Widget child;
  const FocusModeBars({super.key, required this.child});

  static const slide = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context, WidgetRef ref) => ClipRect(
        child: AnimatedAlign(
          duration: slide,
          curve: Curves.easeInOutCubic,
          alignment: Alignment.bottomCenter,
          heightFactor: ref.watch(focusModeProvider) ? 0 : 1,
          child: child,
        ),
      );
}

/// The text below [FocusModeBars], kept clear of the status bar once the
/// bars are gone.
class FocusModeBody extends ConsumerWidget {
  final Widget child;
  const FocusModeBody({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) => AnimatedPadding(
        duration: FocusModeBars.slide,
        curve: Curves.easeInOutCubic,
        padding: EdgeInsets.only(top: ref.watch(focusModeProvider) ? MediaQuery.paddingOf(context).top : 0),
        child: child,
      );
}
