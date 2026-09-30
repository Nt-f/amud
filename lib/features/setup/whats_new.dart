import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/settings.dart';

/// A feature worth pointing out: taught in the setup walkthrough, and
/// announced once on Home to people who finished setup before it existed.
class Feature {
  /// Increases with each announced feature; compared with
  /// [AppSettings.seenFeatures].
  final int id;
  final IconData icon;
  final String title;
  final String body;
  const Feature(this.id, this.icon, this.title, this.body);
}

const features = [
  Feature(1, Icons.fullscreen, 'Focus mode', 'Double-tap the text while praying to hide the top and bottom bars. Double-tap again to bring them back.'),
];

int get latestFeature => features.last.id;

class FeatureTile extends StatelessWidget {
  final Feature feature;
  const FeatureTile(this.feature, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(feature.icon, color: theme.colorScheme.primary),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr(feature.title), style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(context.tr(feature.body), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    ]);
  }
}

/// Home card listing features added since this user last looked; hidden
/// once dismissed.
class WhatsNewBanner extends ConsumerWidget {
  const WhatsNewBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(settingsProvider.select((s) => s.setupDone ? s.seenFeatures : latestFeature));
    final unseen = [for (final f in features) if (f.id > seen) f];
    if (unseen.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr("What's new"), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            for (final f in unseen) Padding(padding: const EdgeInsets.only(top: 12, right: 8), child: FeatureTile(f)),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => ref.read(settingsProvider.notifier).update((x) => x.copyWith(seenFeatures: latestFeature)),
                child: Text(context.tr('Got it')),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
