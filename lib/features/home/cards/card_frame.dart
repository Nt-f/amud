import 'package:flutter/material.dart';

import '../../../core/adaptive.dart';
import '../../../core/l10n.dart';
import '../../../core/split_row.dart';

/// Shared chrome for dashboard cards.
class CardFrame extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget child;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? accent;
  const CardFrame({super.key, this.title, this.icon, required this.child, this.onTap, this.trailing, this.accent});

  /// Space between the card's edge and its heading and [child].
  static const padding = 16.0;

  static TextStyle? _nameStyle(ThemeData theme) =>
      theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, letterSpacing: 0.3);

  /// Whether a [trailing] [width] wide goes beside [title] and its icon in
  /// a card [cardWidth] wide, rather than under them.
  static bool fitsBesideTitle(BuildContext context, String title, double width, {required double cardWidth}) =>
      // The icon and its space, the name, SplitRow's gap.
      18 + 8 + textWidth(context, context.tr(title), _nameStyle(Theme.of(context))) + 8 + width <= cardWidth - 2 * padding;

  /// The icon and name, and [trailing] at the other edge. Where they don't
  /// fit on one line, [trailing] goes under the name instead of cutting it
  /// short.
  Widget _heading(BuildContext context) {
    final theme = Theme.of(context);
    // Two lines, so a compact card on a narrow phone keeps its whole name
    // ("Shabbat & Yom Tov").
    final name = Text(context.tr(title!), style: _nameStyle(theme), maxLines: 2, overflow: TextOverflow.ellipsis);
    final lead = [if (icon != null) ...[Icon(icon, size: 18, color: theme.colorScheme.primary), const SizedBox(width: 8)]];
    if (trailing == null) return Row(children: [...lead, Expanded(child: name)]);
    return SplitRow(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [...lead, Flexible(child: name)]),
      trailing!,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      color: accent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(padding),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _heading(context),
              ),
            child,
          ]),
        ),
      ),
    );
  }
}
