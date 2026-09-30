import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../zmanim/zman_catalog.dart';
import 'alert_editor.dart';
import 'alerts.dart';
import '../../core/l10n.dart';

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
      appBar: AppBar(title: Text(context.tr('Zman alerts'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAlertEditor(context, ref),
        icon: const Icon(Icons.add_alert),
        label: Text(context.tr('New alert')),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        if (!backend.firesWhenClosed)
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(context.tr('On this platform alerts fire while the app is open.'), style: theme.textTheme.bodySmall),
            ),
          ),
        if (alerts.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(context.tr('No alerts yet. Tap a zman on the Zmanim page or “New alert”.'), textAlign: TextAlign.center),
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
              subtitle: Text([
                context.tr(a.offsetMinutes == 0 ? 'At {zman}' : (a.offsetMinutes < 0 ? '{n} min before {zman}' : '{n} min after {zman}'),
                    {'n': a.offsetMinutes.abs(), 'zman': names.label(a.zmanKey)}),
                if (a.when != 'true') context.tr('when {condition}', {'condition': a.when}),
              ].join(' · ')),
              secondary: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => showAlertEditor(context, ref, existing: a)),
            ),
          ),
        if (plan.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(context.tr('Coming up'), style: theme.textTheme.titleSmall),
          ),
          for (final p in plan)
            ListTile(
              dense: true,
              leading: const Icon(Icons.schedule),
              title: Text(p.title),
              subtitle: Text(p.body),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatTime(p.fireAt, ref.watch(locationProvider), hour12: s.hour12),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
                Text(_day(p.fireAt, ref.watch(locationProvider)), style: theme.textTheme.bodySmall),
              ]),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: OutlinedButton.icon(
            onPressed: () async {
              await backend.requestPermission(exact: s.exactAlarms);
              await backend.showNow('Zman alerts', 'Notifications are working.');
            },
            icon: const Icon(Icons.notifications_outlined),
            label: Text(context.tr('Send a test notification')),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () async {
              final n = await ref.read(alertSchedulerProvider).reschedule();
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Scheduled {n} notifications', {'n': n}))));
            },
            icon: const Icon(Icons.sync),
            label: Text(context.tr('Reschedule now')),
          ),
        ),
      ]),
    );
  }
}

/// "Today", "Tomorrow" or a short weekday + date at the user's location.
String _day(DateTime t, Location loc) {
  final l = tz.TZDateTime.from(t, loc.tzLocation);
  final now = tz.TZDateTime.now(loc.tzLocation);
  final d = PlainDate(l.year, l.month, l.day).abs - PlainDate(now.year, now.month, now.day).abs;
  if (d == 0) return 'Today';
  if (d == 1) return 'Tomorrow';
  return formatPlainDate(PlainDate(l.year, l.month, l.day), weekday: true, year: false);
}
