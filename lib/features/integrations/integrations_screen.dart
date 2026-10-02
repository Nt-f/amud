import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../alerts/alerts.dart';
import 'platform_runtime.dart';
import 'prayer_links.dart';
import 'shortcut_preferences.dart';
import 'web_integrations.dart';

class IntegrationsScreen extends ConsumerStatefulWidget {
  const IntegrationsScreen({super.key});
  @override
  ConsumerState<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends ConsumerState<IntegrationsScreen> {
  bool _push = false, _available = false, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (kIsWeb) _loadPush();
  }

  Future<void> _loadPush() async {
    final available = await webPushAvailable(),
        enabled = await webPushEnabled();
    if (mounted) {
      setState(() {
        _available = available;
        _push = enabled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(shortcutPreferencesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Widgets, shortcuts & voice'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            context.tr('Home-screen widgets'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            context.tr(
              'Add the Amud widget from your device’s widget gallery. It shows the Hebrew date, parsha, next zman, Omer and candle lighting for your saved location. Open Amud regularly to refresh its eight-day timeline.',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('Icon shortcuts'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            context.tr(
              'Choose up to four prayers for the icon menu. All five are available through links and voice actions.',
            ),
          ),
          for (final prayer in prayerShortcuts.entries)
            CheckboxListTile(
              title: Text(prayer.value),
              value: selected.contains(prayer.key),
              onChanged: (v) => ref
                  .read(shortcutPreferencesProvider.notifier)
                  .set(
                    v == true
                        ? [
                            ...(selected.length >= 4
                                ? selected.skip(1)
                                : selected),
                            prayer.key,
                          ]
                        : selected.where((p) => p != prayer.key).toList(),
                  ),
            ),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            for (final prayer in prayerShortcuts.entries)
              ListTile(
                title: Text('Pin ${prayer.value} to Home'),
                leading: const Icon(Icons.push_pin_outlined),
                onTap: () async {
                  try {
                    await integrationChannel.invokeMethod<void>('pinPrayer', {
                      'key': prayer.key,
                      'title': prayer.value,
                    });
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
              ),
          const SizedBox(height: 16),
          Text(
            context.tr('Voice assistants'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            context.tr(
              'On Apple devices, add “Open prayer” from Amud in Shortcuts, or ask Siri to open a prayer in Amud. On supported Android devices, ask the assistant to open Mincha in Amud. Availability depends on your assistant and language.',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('Prayer links'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final prayer in prayerShortcuts.entries)
            ListTile(
              title: Text(prayer.value),
              subtitle: Text(sharePrayerLink(prayer.key).toString()),
              trailing: const Icon(Icons.copy),
              onTap: () async {
                await Clipboard.setData(
                  ClipboardData(text: sharePrayerLink(prayer.key).toString()),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.tr('Link copied'))),
                  );
                }
              },
            ),
          Text(
            context.tr('Paired watches'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            context.tr(
              'The watch companion shows the next zman and Omer, with Tefillat HaDerech, Birkat HaMazon and bedtime Shema from your chosen siddur. Open the phone app after changing your location or text versions to sync.',
            ),
          ),
          if (kIsWeb) ...[
            const SizedBox(height: 16),
            Text(
              context.tr('Web reminders'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              context.tr(
                'Web push sends your subscription and reminder schedule to this Amud server so reminders can arrive while the app is closed. Reopen the app regularly to renew the schedule.',
              ),
            ),
            SwitchListTile.adaptive(
              title: Text(context.tr('Reminders while the web app is closed')),
              value: _push,
              subtitle: !_available
                  ? Text(
                      context.tr(
                        'Web push is not configured on this server or supported by this browser.',
                      ),
                    )
                  : null,
              onChanged: !_available || _busy
                  ? null
                  : (v) async {
                      setState(() {
                        _busy = true;
                        _error = null;
                      });
                      try {
                        if (v) {
                          final ok = await enableWebPush();
                          if (!ok) {
                            throw StateError(
                              'Web push permission was not granted.',
                            );
                          }
                        } else {
                          await disableWebPush();
                        }
                        await ref.read(alertSchedulerProvider).reschedule();
                        await _loadPush();
                      } catch (e) {
                        if (mounted) setState(() => _error = '$e');
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            TextButton(
              onPressed: () => context.push('/alerts'),
              child: Text(context.tr('Manage reminders')),
            ),
          ],
        ],
      ),
    );
  }
}
