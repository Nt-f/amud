import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/adaptive.dart';
import '../../core/l10n.dart';
import 'update_service.dart';

Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

String _size(int? bytes) => bytes == null ? '' : ' (${(bytes / 1048576).toStringAsFixed(1)} MB)';

String _installHint() => switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Open the downloaded APK to install it over this version. '
          'Android may ask you to allow installs from your browser the first time.',
      TargetPlatform.windows => 'Unzip the download and replace your current Siddur folder with it, then run siddur.exe.',
      _ => 'Download the new version from the release page.',
    };

/// Current version, the latest release and how to install it.
class UpdateScreen extends ConsumerStatefulWidget {
  const UpdateScreen({super.key});

  @override
  ConsumerState<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends ConsumerState<UpdateScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the page (e.g. from the notification) refreshes the check.
    Future.microtask(() => ref.read(updateProvider.notifier).check());
  }

  @override
  Widget build(BuildContext context) {
    final u = ref.watch(updateProvider);
    final n = ref.read(updateProvider.notifier);
    final theme = Theme.of(context);
    final info = u.available;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('App updates'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(info == null ? Icons.verified_outlined : Icons.system_update, color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    u.checking
                        ? context.tr('Checking for updates…')
                        : info == null
                            ? context.tr('Siddur is up to date')
                            : context.tr('Version {v} is available', {'v': info.version}),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (u.checking) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator.adaptive(strokeWidth: 2)),
              ]),
              const SizedBox(height: 8),
              Text(context.tr('Installed: {v}', {'v': u.currentVersion.isEmpty ? '—' : u.currentVersion}), style: theme.textTheme.bodySmall),
              if (u.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(context.tr("Couldn't check for updates: {e}", {'e': u.error}),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                ),
              if (info != null) ...[
                const SizedBox(height: 16),
                if (info.downloadUrl != null)
                  FilledButton.icon(
                    onPressed: () => _open(info.downloadUrl!),
                    icon: const Icon(Icons.download),
                    label: Text('${context.tr('Download')}${_size(info.downloadSize)}'),
                  ),
                const SizedBox(height: 8),
                Row(children: [
                  TextButton(onPressed: () => _open(info.pageUrl), child: Text(context.tr('Release page'))),
                  const Spacer(),
                  if (u.skipped != info.version)
                    TextButton(onPressed: () => n.skip(info.version), child: Text(context.tr('Skip this version'))),
                ]),
                Text(context.tr(_installHint()), style: theme.textTheme.bodySmall),
              ],
            ]),
          ),
        ),
        if (info != null && info.notes.isNotEmpty) ...[
          const SheetLabel("What's new"),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: SelectableText(info.notes))),
        ],
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          title: Text(context.tr('Check for updates automatically')),
          subtitle: Text(context.tr('Once a day; you get a notification when a new version is out')),
          value: u.autoCheck,
          onChanged: n.setAutoCheck,
        ),
        OutlinedButton.icon(
          onPressed: u.checking ? null : n.check,
          icon: const Icon(Icons.refresh),
          label: Text(context.tr('Check now')),
        ),
      ]),
    );
  }
}

/// A slim banner on the home screen while an update is waiting.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(updateProvider.select((u) => u.pending));
    if (info == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer,
      child: InkWell(
        onTap: () => context.push('/update'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(children: [
            Icon(Icons.system_update, size: 20, color: theme.colorScheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(context.tr('Version {v} is available', {'v': info.version}),
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
            ),
            TextButton(onPressed: () => context.push('/update'), child: Text(context.tr('Update'))),
            IconButton(
              tooltip: context.tr('Skip this version'),
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => ref.read(updateProvider.notifier).skip(info.version),
            ),
          ]),
        ),
      ),
    );
  }
}
