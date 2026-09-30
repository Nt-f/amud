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
      TargetPlatform.android => 'Android asks you to confirm the update. Your settings and data are kept.',
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
    Future.microtask(() {
      final n = ref.read(updateProvider.notifier);
      n.check();
      n.loadInstalledNotes();
      n.markSeen();
    });
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
                  child: Text(context.tr("Couldn't check for updates: {e}", {'e': context.tr(u.error!)}),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                ),
              if (info != null) ...[
                const SizedBox(height: 16),
                if (u.downloading != null) ...[
                  LinearProgressIndicator(value: u.downloading! > 0 ? u.downloading : null),
                  const SizedBox(height: 6),
                  Text(context.tr('Downloading… {p}%', {'p': '${(u.downloading! * 100).round()}'}), style: theme.textTheme.bodySmall),
                ] else if (u.needsPermission) ...[
                  Text(context.tr('Allow Siddur to install apps, then come back here to finish the update.'),
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: n.downloadAndInstall,
                    icon: const Icon(Icons.settings),
                    label: Text(context.tr('Allow and install')),
                  ),
                ] else if (info.downloadUrl != null)
                  FilledButton.icon(
                    onPressed: installsInApp ? n.downloadAndInstall : () => _open(info.downloadUrl!),
                    icon: Icon(installsInApp ? Icons.system_update : Icons.download),
                    label: Text('${context.tr(installsInApp ? 'Update now' : 'Download')}${_size(info.downloadSize)}'),
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
          SheetLabel(context.tr("What's new in {v}", {'v': info.version})),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: ReleaseNotes(info.notes))),
        ],
        if ((u.installedNotes ?? '').isNotEmpty) ...[
          SheetLabel(context.tr("What's new in {v}", {'v': u.currentVersion})),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: ReleaseNotes(u.installedNotes!))),
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
    final updated = ref.watch(updateProvider.select((u) => u.justUpdated ? u.currentVersion : null));
    if (info == null && updated == null) return const SizedBox.shrink();
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
              child: Text(
                  info != null
                      ? context.tr('Version {v} is available', {'v': info.version})
                      : context.tr('Updated to {v}', {'v': updated!}),
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
            ),
            TextButton(onPressed: () => context.push('/update'), child: Text(context.tr(info != null ? 'Update' : "What's new"))),
            IconButton(
              tooltip: context.tr(info != null ? 'Skip this version' : 'Dismiss'),
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => info != null
                  ? ref.read(updateProvider.notifier).skip(info.version)
                  : ref.read(updateProvider.notifier).markSeen(),
            ),
          ]),
        ),
      ),
    );
  }
}

/// GitHub release notes (Markdown) shown as headings, bullets and
/// paragraphs, without links or emphasis markup.
class ReleaseNotes extends StatelessWidget {
  final String markdown;
  const ReleaseNotes(this.markdown, {super.key});

  static String _inline(String t) => t
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'\*\*|__|`'), '')
      .replaceAllMapped(RegExp(r'(^|\s)[*_]([^*_]+)[*_]'), (m) => '${m[1]}${m[2]}')
      .trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[];
    for (final raw in markdown.split(RegExp(r'\r?\n'))) {
      final line = raw.trimRight();
      if (line.trim().isEmpty || RegExp(r'^\s*(-{3,}|\*{3,})\s*$').hasMatch(line)) continue;
      final heading = RegExp(r'^#{1,6}\s+(.*)').firstMatch(line);
      final bullet = RegExp(r'^(\s*)[-*+]\s+(.*)').firstMatch(line);
      if (heading != null) {
        children.add(Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 12, bottom: 4),
          child: Text(_inline(heading[1]!), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ));
      } else if (bullet != null) {
        final indent = bullet[1]!.length >= 2 ? 16.0 : 0.0;
        children.add(Padding(
          padding: EdgeInsetsDirectional.only(start: indent, top: 2, bottom: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('•  '),
            Expanded(child: Text(_inline(bullet[2]!))),
          ]),
        ));
      } else {
        children.add(Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(_inline(line))));
      }
    }
    return SelectionArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
  }
}
