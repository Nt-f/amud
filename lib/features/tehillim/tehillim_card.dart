import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import 'tehillim_data.dart';
import 'tehillim_progress.dart';
import 'tehillim_reader.dart';

/// Today's Tehillim portion and progress; opens the Tehillim screen.
class TehillimCard extends ConsumerWidget {
  const TehillimCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hd = ref.watch(readerDaytimeDateProvider);
    final today = monthlyPortion(hd);
    final read = ref.watch(tehillimProgressProvider.select((x) => x.read.length));
    final hebFont = ref.watch(settingsProvider.select((s) => s.hebrewFont));
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.zero,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/torah/tehillim'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Text('תהלים', style: TextStyle(fontFamily: hebFont, fontSize: 30, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tr('Tehillim'), style: theme.textTheme.titleMedium),
                  Text(
                    '${context.tr('Today')}: ${today.rangeLabel} · ${context.tr('{n} of 150 chapters read this cycle', {'n': read})}',
                    style: theme.textTheme.bodySmall,
                  ),
                ]),
              ),
              IconButton.filledTonal(
                tooltip: context.tr("Read today's Tehillim"),
                icon: const Icon(Icons.menu_book),
                onPressed: () => context.push(tehillimReadPath(today)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
