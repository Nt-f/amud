import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'theme.dart';

/// How far through a day's portion the reader has scrolled: 0 with its
/// start at [line] (where the reader opens it), 1 with its end at the
/// bottom of the view. [start], [end] and [line] are fractions of the
/// view's height from its top (negative above it). A portion shorter than
/// the view counts how much of it has come into view.
double portionProgress(double start, double end, {double line = 0}) {
  final length = end - start;
  if (length <= 0) return start < 1 ? 1 : 0;
  final travel = length - (1 - line);
  if (travel <= 0) return ((1 - start) / length).clamp(0.0, 1.0);
  return ((line - start) / travel).clamp(0.0, 1.0);
}

/// Follows a [ScrollablePositionedList] through a day's portion. Items on
/// screen give their own place; those off it are placed by their heights
/// when last seen (the average for any not seen yet).
class PortionTracker {
  final _heights = <int, double>{};

  /// 0–1 through items [first] to [last] (see [portionProgress]); null
  /// before the list is laid out.
  double? progress(Iterable<ItemPosition> shown, int first, int last, {double line = 0}) {
    if (shown.isEmpty || last < first) return null;
    final at = {for (final p in shown) p.index: p};
    for (final p in shown) {
      _heights[p.index] = p.itemTrailingEdge - p.itemLeadingEdge;
    }
    final average = _heights.values.reduce((a, b) => a + b) / _heights.length;
    double height(int i) => _heights[i] ?? average;
    final top = at.keys.reduce(math.min), bottom = at.keys.reduce(math.max);
    double leading(int i) {
      if (at[i] case final p?) return p.itemLeadingEdge;
      var y = i < top ? at[top]!.itemLeadingEdge : at[bottom]!.itemTrailingEdge;
      if (i < top) {
        for (var j = i; j < top; j++) {
          y -= height(j);
        }
      } else {
        for (var j = bottom + 1; j < i; j++) {
          y += height(j);
        }
      }
      return y;
    }

    return portionProgress(leading(first), leading(last) + height(last), line: line);
  }
}

/// A thin bar along the top of a reader that fills as the day's portion is
/// read. Null [progress] hides it.
class PortionProgressBar extends StatelessWidget {
  final ValueListenable<double?> progress;
  const PortionProgressBar({super.key, required this.progress});

  static const height = 3.0;

  @override
  Widget build(BuildContext context) {
    final colors = SiddurColors.of(context);
    return IgnorePointer(
      child: ValueListenableBuilder(
        valueListenable: progress,
        builder: (context, value, _) => value == null
            ? const SizedBox.shrink()
            : TweenAnimationBuilder<double>(
                tween: Tween(end: value),
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                builder: (context, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: height,
                  color: colors.todayBar,
                  backgroundColor: colors.todayFill,
                ),
              ),
      ),
    );
  }
}

/// Marks a passage of the day's portion with a thin bar in the margin
/// beside it, joined to the next passage's across the [gap] under it, so
/// the portion reads as one stretch.
class PortionMark extends StatelessWidget {
  final bool first;
  final bool last;

  /// The space under the passage, which the bar crosses unless it's the
  /// last.
  final double gap;
  final Widget child;
  const PortionMark({super.key, required this.first, required this.last, required this.gap, required this.child});

  @override
  Widget build(BuildContext context) {
    const end = Radius.circular(1.5);
    return Stack(clipBehavior: Clip.none, children: [
      child,
      PositionedDirectional(
        start: -6,
        width: 3,
        top: 0,
        bottom: last ? gap : 0,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: SiddurColors.of(context).todayBar,
              borderRadius: BorderRadius.vertical(top: first ? end : Radius.zero, bottom: last ? end : Radius.zero),
            ),
          ),
        ),
      ),
    ]);
  }
}
