import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adaptive.dart';
import '../../core/l10n.dart';
import '../../core/settings.dart';

/// The typesetting switches (see core/typeset), shared by every reader's
/// text settings: one choice for the whole app.
class TypesettingOptions extends ConsumerWidget {
  const TypesettingOptions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SheetLabel(context.tr('Typesetting')),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(context.tr('Print-style typesetting')),
        subtitle: Text(context.tr('Sizes that follow the prayer, a large opening word, ornaments between sections')),
        value: s.typesetting,
        onChanged: (v) => n.update((x) => x.copyWith(typesetting: v)),
      ),
      if (s.typesetting) ...[
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('Justify text')),
          subtitle: Text(context.tr('Even edges on both sides; lines that would gape are left ragged')),
          value: s.justifyText,
          onChanged: (v) => n.update((x) => x.copyWith(justifyText: v)),
        ),
        Text(context.tr('Size contrast'), style: theme.textTheme.bodyLarge),
        Row(children: [
          Text(context.tr('Uniform'), style: theme.textTheme.bodySmall),
          Expanded(
            child: Slider.adaptive(
              value: s.typeContrast,
              divisions: 10,
              onChanged: (v) => n.update((x) => x.copyWith(typeContrast: v)),
            ),
          ),
          Text(context.tr('Pronounced'), style: theme.textTheme.bodySmall),
        ]),
      ],
    ]);
  }
}
