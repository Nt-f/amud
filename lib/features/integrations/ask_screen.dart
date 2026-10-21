import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adaptive.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../home/today.dart';
import '../zmanim/zman_catalog.dart';
import 'assistant.dart';
import 'widget_snapshot.dart';

/// The answer to a spoken request ("Hey Google, when is sunset in Amud?"):
/// opened by an App Action with the topic, or with the user's own words.
class AskScreen extends ConsumerWidget {
  final String? topic;
  final String? query;
  const AskScreen({super.key, this.topic, this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final snap = ref.watch(todaySnapshotProvider);
    final resolver = ref.watch(zmanResolverProvider);
    final entry = activeWidgetEntry(buildWidgetTimeline(settings, resolver, snap.now, days: 8), snap.now);
    final en = settings.uiLanguage == UiLanguage.en;
    final loc = snap.location;

    String when(String key) {
      final t = snap.zmanim[key];
      return t == null ? '—' : formatTime(t, loc, hour12: settings.hour12);
    }

    (String, String) answer(AskTopic t) => switch (t) {
          AskTopic.nextZman => ('${entry?['nextZman'] ?? ''}', '${entry?['nextZmanTime'] ?? ''}'),
          AskTopic.date => (context.tr('Hebrew date'), '${entry?[en ? 'dateLabel' : 'hebrewDate'] ?? ''}'),
          AskTopic.parsha => (context.tr('Parsha'), '${entry?['parsha'] ?? ''}'),
          AskTopic.omer => (
              context.tr('Omer'),
              (entry?['omer'] as int? ?? 0) > 0
                  ? context.tr('Day {n} of the Omer', {'n': entry!['omer']})
                  : context.tr('No Omer count today'),
            ),
          AskTopic.candles => (
              context.tr('Candle lighting'),
              (entry?['candleLighting'] as String? ?? '').isEmpty
                  ? context.tr('No candle lighting soon')
                  : '${entry!['candleLighting']}',
            ),
          AskTopic.sunrise => (resolver.label('sunrise'), when('sunrise')),
          AskTopic.sunset => (resolver.label('sunset'), when('sunset')),
        };

    final picked = AskTopic.values.where((t) => t.name == topic).firstOrNull ?? matchAskTopic(query ?? '');
    final topics = picked == null ? AskTopic.values : [picked];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(picked == null ? context.tr('Today at a glance') : context.tr('Ask Amud'))),
      body: ListView(
        padding: pagePadding(context, const EdgeInsets.all(16)),
        children: [
          if ((query ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('“$query”', style: theme.textTheme.bodyMedium)),
          for (final t in topics)
            Semantics(
              liveRegion: true,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(answer(t).$1, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(answer(t).$2, style: theme.textTheme.headlineMedium),
                  ]),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(settings.location.name, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
