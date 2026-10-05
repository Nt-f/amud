import 'package:flutter/material.dart';

/// Settles the scroll view in [child] on a verse when the reader stops
/// scrolling: near the end of the verse at the top, the next one moves up
/// to the top; just past its start, it comes back into view. Mid-verse it
/// stays put, so a long verse is never skipped.
class VerseSnap extends StatefulWidget {
  /// One key per verse, in order, on the verse's outermost widget.
  final List<GlobalKey> verses;
  final bool enabled;
  final Widget child;
  const VerseSnap({super.key, required this.verses, required this.child, this.enabled = true});

  @override
  State<VerseSnap> createState() => _VerseSnapState();
}

class _VerseSnapState extends State<VerseSnap> {
  /// Room left above a verse settled at the top.
  static const _inset = 8.0;

  bool _onEnd(ScrollEndNotification n) {
    if (widget.enabled && n.depth == 0) WidgetsBinding.instance.addPostFrameCallback((_) => _snap());
    return false;
  }

  void _snap() {
    if (!mounted) return;
    final built = [
      for (final k in widget.verses)
        if (k.currentContext?.findRenderObject() case final RenderBox b when b.attached) b,
    ];
    final first = widget.verses.map((k) => k.currentContext).nonNulls.firstOrNull;
    final scrollable = first == null ? null : Scrollable.maybeOf(first);
    final viewport = scrollable?.context.findRenderObject();
    if (scrollable == null || viewport is! RenderBox || built.isEmpty) return;
    final pos = scrollable.position;
    if (pos.isScrollingNotifier.value) return;
    final line = viewport.localToGlobal(Offset.zero).dy + _inset;
    final screen = viewport.size.height;
    // The verse at the top, the first that isn't scrolled off entirely.
    final i = built.indexWhere((b) => b.localToGlobal(Offset.zero).dy + b.size.height > line);
    if (i < 0) return;
    final top = built[i].localToGlobal(Offset.zero).dy - line;
    final height = built[i].size.height;
    final bottom = top + height;
    double? delta;
    if (top > 0) {
      // Stopped between verses: the gap is a margin, a few pixels.
      if (top < 24) delta = top;
    } else if (bottom < screen * 0.3 && bottom < height * 0.5) {
      if (i + 1 < built.length) delta = built[i + 1].localToGlobal(Offset.zero).dy - line;
    } else if (-top < screen * 0.15 && -top < height * 0.5) {
      delta = top;
    }
    if (delta == null) return;
    final to = (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((to - pos.pixels).abs() > 0.5) pos.animateTo(to, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollEndNotification>(onNotification: _onEnd, child: widget.child);
}
