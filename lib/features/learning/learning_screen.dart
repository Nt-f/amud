import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';

final _learnDateProvider = StateProvider<PlainDate?>((ref) => null);

/// Every daily learning schedule from the Hebcal learning port.
class LearningScreen extends ConsumerWidget {
  const LearningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(civilTodayProvider);
    final date = ref.watch(_learnDateProvider) ?? today;
    final hd = HDate.fromAbs(date.abs);
    final s = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final entries = <(String, String, Event?)>[];
    for (final e in learningScheduleTitles.entries) {
      Event? ev;
      try {
        ev = DailyLearning.lookup(e.key, hd, s.location.il);
      } catch (_) {}
      entries.add((e.key, e.value, ev));
    }
    entries.sort((a, b) {
      final ia = s.learningSchedules.indexOf(a.$1);
      final ib = s.learningSchedules.indexOf(b.$1);
      return (ia < 0 ? 999 : ia).compareTo(ib < 0 ? 999 : ib);
    });
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Daily learning'))),
      body: ListView(children: [
        Row(children: [
          IconButton(onPressed: () => ref.read(_learnDateProvider.notifier).state = date.addDays(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Column(children: [
              Text(formatPlainDate(date), style: theme.textTheme.titleMedium),
              Text(hd.render(context.hebcalLocale), style: theme.textTheme.bodySmall),
            ]),
          ),
          IconButton(onPressed: () => ref.read(_learnDateProvider.notifier).state = date.addDays(1), icon: const Icon(Icons.chevron_right)),
        ]),
        for (final (key, title, ev) in entries)
          ListTile(
            leading: Icon(s.learningSchedules.contains(key) ? Icons.star : Icons.star_border, color: theme.colorScheme.primary),
            title: Text(title),
            subtitle: ev == null
                ? const Text('—')
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(ev.render(context.hebcalLocale), style: theme.textTheme.bodyLarge),
                    Text(ev.render('he'), textDirection: TextDirection.rtl, style: TextStyle(fontFamily: s.hebrewFont, fontSize: 16)),
                  ]),
            trailing: ev?.url() == null
                ? null
                : IconButton(icon: const Icon(Icons.open_in_new), onPressed: () => launchUrl(Uri.parse(ev!.url()!))),
            onLongPress: () => ref.read(settingsProvider.notifier).update((x) {
              final l = [...x.learningSchedules];
              l.contains(key) ? l.remove(key) : l.add(key);
              return x.copyWith(learningSchedules: l);
            }),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(context.tr('Long-press to star a schedule. Links open the text on Sefaria.'), style: theme.textTheme.bodySmall),
        ),
      ]),
    );
  }
}
