import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../zmanim/zman_catalog.dart';
import 'alert_editor.dart';
import 'alerts.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);
    final names = ref.watch(zmanResolverProvider);
    final backend = ref.watch(notificationBackendProvider);
    final s = ref.watch(settingsProvider);
    final plan = planNotifications(
      alerts: alerts,
      location: ref.watch(locationProvider),
      zmanim: names,
      settings: s,
      now: DateTime.now(),
      days: 3,
      max: 8,
    );
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Zman alerts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAlertEditor(context, ref),
        icon: const Icon(Icons.add_alert),
        label: const Text('New alert'),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        if (!backend.firesWhenClosed)
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('On this platform alerts fire while the app is open.', style: theme.textTheme.bodySmall),
            ),
          ),
        if (alerts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text('No alerts yet. Tap a zman on the Zmanim page or “New alert”.', textAlign: TextAlign.center),
          ),
        for (final a in alerts)
          Dismissible(
            key: ValueKey(a.id),
            background: Container(color: theme.colorScheme.errorContainer),
            onDismissed: (_) => ref.read(alertsProvider.notifier).remove(a.id),
            child: SwitchListTile.adaptive(
              value: a.enabled,
              onChanged: (v) => ref.read(alertsProvider.notifier).upsert(a.copyWith(enabled: v)),
              title: Text(a.title),
              subtitle: Text('${a.describeOffset()} ${names.name(a.zmanKey)}${a.when == 'true' ? '' : ' · when ${a.when}'}'),
              secondary: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => showAlertEditor(context, ref, existing: a)),
            ),
          ),
        if (plan.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text('Coming up', style: theme.textTheme.titleSmall),
          ),
          for (final p in plan)
            ListTile(
              dense: true,
              leading: const Icon(Icons.schedule),
              title: Text(p.title),
              subtitle: Text(p.body),
              trailing: Text(formatTime(p.fireAt, ref.watch(locationProvider), hour12: s.hour12)),
            ),
        ],
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () async {
              final n = await ref.read(alertSchedulerProvider).reschedule();
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scheduled $n notifications')));
            },
            icon: const Icon(Icons.sync),
            label: const Text('Reschedule now'),
          ),
        ),
      ]),
    );
  }
}
