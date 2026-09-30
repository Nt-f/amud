import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A title with something at the other edge — typically English at the
/// start and Hebrew at the end. When everything fits on one line the first
/// child sits at the start and the rest at the end, like
/// `Row([Expanded(first), ...rest])`. When it doesn't, the children wrap onto
/// further lines (the later ones still end-aligned) instead of squeezing the
/// first child into a sliver, which breaks words mid-letter on narrow phones.
///
/// Children size themselves (no Expanded/Flexible); a child wider than the
/// row is given the full width and wraps its own text.
class SplitRow extends MultiChildRenderObjectWidget {
  final double gap;
  final double runGap;
  final CrossAxisAlignment crossAxisAlignment;
  const SplitRow({
    super.key,
    this.gap = 8,
    this.runGap = 2,
    this.crossAxisAlignment = CrossAxisAlignment.end,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderSplitRow(gap, runGap, crossAxisAlignment, Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderSplitRow renderObject) => renderObject
    ..gap = gap
    ..runGap = runGap
    ..crossAxisAlignment = crossAxisAlignment
    ..textDirection = Directionality.of(context);
}

class _SplitParentData extends ContainerBoxParentData<RenderBox> {}

class RenderSplitRow extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _SplitParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _SplitParentData> {
  RenderSplitRow(this._gap, this._runGap, this._align, this._textDirection);

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  double _runGap;
  set runGap(double v) {
    if (v == _runGap) return;
    _runGap = v;
    markNeedsLayout();
  }

  CrossAxisAlignment _align;
  set crossAxisAlignment(CrossAxisAlignment v) {
    if (v == _align) return;
    _align = v;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection v) {
    if (v == _textDirection) return;
    _textDirection = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SplitParentData) child.parentData = _SplitParentData();
  }

  List<RenderBox> get _children => [for (var c = firstChild; c != null; c = childAfter(c)) c];

  /// Greedy line breaking over the children's widths.
  List<List<int>> _lines(List<double> widths, double max) {
    final lines = <List<int>>[];
    var used = 0.0;
    for (var i = 0; i < widths.length; i++) {
      if (lines.isEmpty || used + _gap + widths[i] > max) {
        lines.add([i]);
        used = widths[i];
      } else {
        lines.last.add(i);
        used += _gap + widths[i];
      }
    }
    return lines;
  }

  @override
  void performLayout() {
    final kids = _children;
    final max = constraints.maxWidth;
    for (final c in kids) {
      c.layout(BoxConstraints(maxWidth: max), parentUsesSize: true);
    }
    final rtl = _textDirection == TextDirection.rtl;
    double place(double x, double w) => rtl ? max - x - w : x;
    var y = 0.0;
    var widest = 0.0;
    for (final line in _lines([for (final c in kids) c.size.width], max)) {
      final h = line.map((i) => kids[i].size.height).reduce(math.max);
      // The first child hugs the start; everything after it on the line
      // is packed against the end.
      final head = line.first == 0 ? [0] : const <int>[];
      final tail = line.where((i) => i != 0).toList();
      var x = 0.0;
      for (final i in head) {
        _put(kids[i], place(x, kids[i].size.width), y, h);
        x += kids[i].size.width + _gap;
      }
      var end = max;
      for (final i in tail.reversed) {
        end -= kids[i].size.width;
        _put(kids[i], place(end, kids[i].size.width), y, h);
        end -= _gap;
      }
      widest = math.max(widest, line.map((i) => kids[i].size.width).fold(0.0, (a, b) => a + b) + _gap * (line.length - 1));
      y += h + _runGap;
    }
    if (kids.isNotEmpty) y -= _runGap;
    size = constraints.constrain(Size(max.isFinite ? max : widest, y));
  }

  void _put(RenderBox c, double x, double y, double lineHeight) {
    final dy = switch (_align) {
      CrossAxisAlignment.start || CrossAxisAlignment.stretch || CrossAxisAlignment.baseline => 0.0,
      CrossAxisAlignment.center => (lineHeight - c.size.height) / 2,
      CrossAxisAlignment.end => lineHeight - c.size.height,
    };
    (c.parentData! as _SplitParentData).offset = Offset(x, y + dy);
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _children.fold(0.0, (a, c) => math.max(a, c.getMinIntrinsicWidth(height)));

  @override
  double computeMaxIntrinsicWidth(double height) {
    final kids = _children;
    if (kids.isEmpty) return 0;
    return kids.fold(0.0, (a, c) => a + c.getMaxIntrinsicWidth(height)) + _gap * (kids.length - 1);
  }

  double _intrinsicHeight(double width) {
    final kids = _children;
    if (kids.isEmpty) return 0;
    final lines = _lines([for (final c in kids) math.min(c.getMaxIntrinsicWidth(double.infinity), width)], width);
    return lines.fold(0.0, (a, l) => a + l.map((i) => kids[i].getMinIntrinsicHeight(width)).reduce(math.max)) +
        _runGap * (lines.length - 1);
  }

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}
