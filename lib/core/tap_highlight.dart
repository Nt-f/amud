import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n.dart';
import 'settings.dart';
import 'theme.dart';

/// Ids of the lines and verses the reader has tapped to mark. Shared by the
/// siddur reader and Shnayim Mikra, so a tap looks the same in both.
final tapHighlightsProvider = StateProvider<Set<String>>((_) => const {});

/// The colors on offer for marking text (ARGB); 0 is the theme's own.
const highlightChoices = <int>[0, 0xFFFFC857, 0xFF7BD389, 0xFF6EC1E4, 0xFFF29BC0, 0xFFC3A6F2];

/// The fill behind a marked line: the reader's chosen color, or the theme's.
Color tapHighlightFill(BuildContext context, AppSettings s) =>
    s.highlightColor == 0 ? SiddurColors.of(context).todayFill : Color(s.highlightColor).withValues(alpha: 0.35);

/// Tap a line to mark it; tap again to clear.
class TapHighlight extends ConsumerWidget {
  final String id;
  final Widget child;
  final BorderRadius radius;
  const TapHighlight({super.key, required this.id, required this.child, this.radius = const BorderRadius.all(Radius.circular(10))});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(tapHighlightsProvider.select((x) => x.contains(id)));
    final fill = tapHighlightFill(context, ref.watch(settingsProvider));
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        final n = ref.read(tapHighlightsProvider.notifier);
        n.state = on ? ({...n.state}..remove(id)) : {...n.state, id};
      },
      child: DecoratedBox(
        decoration: BoxDecoration(color: on ? fill : null, borderRadius: radius),
        child: child,
      ),
    );
  }
}

/// A row of swatches for the highlight color.
class HighlightColorPicker extends ConsumerWidget {
  const HighlightColorPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(context.tr('Highlight color'), style: theme.textTheme.bodyLarge),
      const SizedBox(height: 4),
      Text(context.tr('Tap a line or verse to mark it.'), style: theme.textTheme.bodySmall),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 8, children: [
        for (final c in highlightChoices)
          Semantics(
            button: true,
            selected: s.highlightColor == c,
            label: c == 0 ? context.tr('Default') : null,
            child: GestureDetector(
              onTap: () => ref.read(settingsProvider.notifier).update((x) => x.copyWith(highlightColor: c)),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c == 0 ? SiddurColors.of(context).todayFill : Color(c).withValues(alpha: 0.5),
                  border: Border.all(
                      color: s.highlightColor == c ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                      width: s.highlightColor == c ? 3 : 1),
                ),
                child: c == 0 ? Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.onSurfaceVariant) : null,
              ),
            ),
          ),
      ]),
    ]);
  }
}
