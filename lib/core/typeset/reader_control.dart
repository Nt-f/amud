import 'package:flutter/material.dart';

/// A tappable row inside the reader's text: a folded section, a collapsed
/// note, the chazzan's repetition.
///
/// Controls share one look that the text never takes: interface type
/// rather than the prayer font, an icon in a tinted disc, a fill and a
/// border, an affordance at the end. Folded content (something hidden
/// that could be shown) gets a dashed border, like a page edge torn off;
/// a control that opens in place gets a solid one. So at a glance the
/// page separates what is said from what can be tapped.
class ReaderControl extends StatelessWidget {
  final IconData icon;
  final Widget title;
  final Widget? subtitle;

  /// Shown at the end before the chevron (e.g. "Show"), or in its place.
  final Widget? trailing;

  /// Accent for the icon, border and text.
  final Color tone;
  final bool dashed;
  final bool open;
  final VoidCallback? onTap;

  /// Squares off the bottom corners when content hangs beneath it.
  final bool attachedBelow;

  /// Space kept clear of the text above and below.
  final double gap;

  const ReaderControl({
    super.key,
    required this.icon,
    required this.title,
    required this.tone,
    this.subtitle,
    this.trailing,
    this.dashed = false,
    this.open = false,
    this.onTap,
    this.attachedBelow = false,
    this.gap = 4,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = attachedBelow ? const BorderRadius.vertical(top: Radius.circular(14)) : BorderRadius.circular(14);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: tone.withValues(alpha: 0.14), shape: BoxShape.circle),
          child: Icon(icon, size: 17, color: tone),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DefaultTextStyle.merge(
            style: theme.textTheme.bodyMedium?.copyWith(color: tone, fontFamily: theme.textTheme.bodyMedium?.fontFamily),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              title,
              if (subtitle != null)
                DefaultTextStyle.merge(style: theme.textTheme.bodySmall?.copyWith(color: tone.withValues(alpha: 0.8)), child: subtitle!),
            ]),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), DefaultTextStyle.merge(style: theme.textTheme.labelMedium?.copyWith(color: tone), child: trailing!)],
        const SizedBox(width: 2),
        Icon(open ? Icons.expand_less : Icons.expand_more, size: 20, color: tone),
      ]),
    );
    return Padding(
      padding: EdgeInsets.only(top: gap, bottom: attachedBelow ? 0 : gap),
      child: Semantics(
        button: true,
        expanded: open,
        child: CustomPaint(
          foregroundPainter: dashed ? _DashedBorder(tone.withValues(alpha: 0.55), radius) : null,
          child: Material(
            color: tone.withValues(alpha: dashed ? 0.04 : 0.08),
            shape: dashed ? RoundedRectangleBorder(borderRadius: radius) : RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: tone.withValues(alpha: 0.35))),
            clipBehavior: Clip.antiAlias,
            child: InkWell(onTap: onTap, child: content),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  final Color color;
  final BorderRadius radius;
  _DashedBorder(this.color, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = radius.toRRect(Offset.zero & size).deflate(0.5);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const dash = 5.0, space = 4.0;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + space) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.radius != radius;
}
