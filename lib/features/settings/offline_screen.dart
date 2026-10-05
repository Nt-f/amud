import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adaptive.dart';
import '../../core/fonts.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../js_cards/js_card.dart';
import '../torah/torah_library.dart';
import '../voice/offline_voice.dart';
import '../voice/voice_model.dart';

/// Everything the app keeps for offline use in one place: what's built in,
/// what's downloaded and the room it takes, a button to download the texts
/// ahead of time (before a trip or Yom Tov), and a way to remove downloads.
class OfflineScreen extends ConsumerStatefulWidget {
  const OfflineScreen({super.key});

  @override
  ConsumerState<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends ConsumerState<OfflineScreen> {
  late final _voice = OfflineVoiceBackend(ref.read(storageProvider));
  bool _voiceReady = false;
  int _voiceBytes = 0;
  double? _voiceProgress;
  bool _voiceFailed = false;

  @override
  void initState() {
    super.initState();
    _checkVoice();
  }

  @override
  void dispose() {
    _voice.dispose();
    super.dispose();
  }

  Future<void> _checkVoice() async {
    try {
      final ready = await _voice.ready();
      final bytes = await _voice.size();
      if (mounted) {
        setState(() {
          _voiceReady = ready;
          _voiceBytes = bytes;
        });
      }
    } catch (_) {}
  }

  Future<void> _downloadVoice() async {
    setState(() {
      _voiceProgress = 0;
      _voiceFailed = false;
    });
    try {
      await _voice.install((p) {
        if (mounted) setState(() => _voiceProgress = p);
      });
    } catch (_) {
      if (mounted) setState(() => _voiceFailed = true);
    }
    if (mounted) setState(() => _voiceProgress = null);
    await _checkVoice();
  }

  Future<bool> _confirm(String title, String size) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('Remove {name}?', {'name': title})),
          content: Text(context.tr('This frees {size}. You can download it again later.', {'size': size})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr('Remove'))),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(storageProvider);
    final states = ref.watch(torahLibraryProvider);
    final library = ref.read(torahLibraryProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final userFonts = ref.watch(fontsProvider);
    final theme = Theme.of(context);
    final heUi = context.uiLanguage != UiLanguage.en;

    final works = [for (final c in torahCategories) ...c.availableWorks];
    int stored(TorahWork w) => switch (states[w.id]) { Downloaded(:final bytes) => bytes, _ => 0 };
    final missing = [for (final w in works) if (states[w.id] is! Downloaded) w];
    final downloading = works.any((w) => states[w.id] is Downloading);
    final fonts = [
      for (final k in storage.blobKeys)
        if (k.startsWith('font:')) (family: k.substring(5), bytes: storage.readBlob(k)?.length ?? 0),
    ];
    final cards = [for (final k in storage.jsonKeys) if (k.startsWith(savedCardPrefix)) k];
    final cardBytes = cards.fold<int>(0, (n, k) => n + (storage.readJson(k, (j) => utf8.encode(jsonEncode(j)).length) ?? 0));
    final total = works.fold<int>(0, (n, w) => n + stored(w)) + _voiceBytes + fonts.fold<int>(0, (n, f) => n + f.bytes) + cardBytes;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Offline & storage'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('Downloaded on this device: {size}', {'size': formatBytes(total)}), style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              [
                context.tr('The siddurim, fonts, zmanim and calendar are built in and always work offline.'),
                if (kIsWeb) context.tr('This web app is saved in your browser after your first visit.'),
              ].join(' '),
              style: theme.textTheme.bodySmall,
            ),
          ]),
        ),
        AdaptiveSection(header: context.tr('Texts'), children: [
          for (final w in works)
            ListTile(
              leading: Icon(states[w.id] is Downloaded ? Icons.offline_pin : Icons.menu_book_outlined,
                  color: states[w.id] is Downloaded ? theme.colorScheme.primary : null),
              title: Text(heUi ? w.he : w.en),
              subtitle: Text(switch (states[w.id]) {
                Downloaded(:final bytes) => context.tr('Downloaded · {size}', {'size': formatBytes(bytes)}),
                Downloading() => context.tr('Downloading…'),
                DownloadFailed() => context.tr('Download failed. Check your connection and try again.'),
                _ => context.tr('≈ {size} download', {'size': formatBytes(w.estimatedBytes)}),
              }),
              trailing: switch (states[w.id]) {
                Downloaded(:final bytes) => IconButton(
                    tooltip: context.tr('Remove'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await _confirm(heUi ? w.he : w.en, formatBytes(bytes))) await library.delete(w);
                    },
                  ),
                Downloading() => const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                _ => IconButton(tooltip: context.tr('Download'), icon: const Icon(Icons.download), onPressed: () => library.download(w)),
              },
            ),
          if (missing.isNotEmpty && !downloading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: FilledButton.icon(
                icon: const Icon(Icons.download_for_offline_outlined),
                label: Text(context.tr('Download all texts · ≈ {size}',
                    {'size': formatBytes(missing.fold<int>(0, (n, w) => n + w.estimatedBytes))})),
                onPressed: () => library.downloadAll(missing),
              ),
            ),
        ]),
        AdaptiveSection(header: context.tr('Voice commands'), children: [
          ListTile(
            leading: Icon(_voiceReady ? Icons.offline_pin : Icons.mic_none, color: _voiceReady ? theme.colorScheme.primary : null),
            title: Text(context.tr('Voice model')),
            subtitle: _voiceProgress != null
                ? LinearProgressIndicator(value: _voiceProgress)
                : Text(_voiceReady
                    ? context.tr('Downloaded · {size}', {'size': formatBytes(_voiceBytes)})
                    : _voiceBytes > 0
                        ? context.tr('{done} of {size} downloaded. Continue where it stopped.',
                            {'done': formatBytes(_voiceBytes), 'size': formatBytes(voiceModelBytes)})
                        : _voiceFailed
                            ? context.tr('Download failed. Check your connection and try again.')
                            : context.tr('≈ {size} download', {'size': formatBytes(voiceModelBytes)})),
            trailing: _voiceProgress != null
                ? null
                : _voiceReady
                    ? IconButton(
                        tooltip: context.tr('Remove'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await _confirm(context.tr('Voice model'), formatBytes(_voiceBytes))) {
                            await _voice.remove();
                            await _checkVoice();
                          }
                        },
                      )
                    : IconButton(tooltip: context.tr('Download'), icon: const Icon(Icons.download), onPressed: _downloadVoice),
          ),
        ]),
        if (fonts.isNotEmpty)
          AdaptiveSection(header: context.tr('Saved fonts'), children: [
            for (final f in fonts)
              ListTile(
                leading: const Icon(Icons.font_download_outlined),
                title: Text(fontLabel(f.family, userFonts)),
                subtitle: Text([
                  formatBytes(f.bytes),
                  if (settings.hebrewFont == f.family || settings.latinFont == f.family) context.tr('In use'),
                ].join(' · ')),
                // A font that's in use stays, so the text doesn't change.
                trailing: settings.hebrewFont == f.family || settings.latinFont == f.family
                    ? null
                    : IconButton(
                        tooltip: context.tr('Remove'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (userFonts.any((u) => u.family == f.family)) {
                            await ref.read(fontsProvider.notifier).remove(f.family);
                          } else {
                            await storage.deleteBlob('font:${f.family}');
                          }
                          setState(() {});
                        },
                      ),
              ),
          ]),
        if (cards.isNotEmpty)
          AdaptiveSection(header: context.tr('Custom cards'), children: [
            ListTile(
              leading: const Icon(Icons.widgets_outlined),
              title: Text(context.tr('Last results of {n} cards', {'n': cards.length})),
              subtitle: Text('${formatBytes(cardBytes)} · ${context.tr('Shown when a card is offline')}'),
              trailing: TextButton(
                onPressed: () async {
                  for (final k in cards) {
                    await storage.deleteJson(k);
                  }
                  setState(() {});
                },
                child: Text(context.tr('Clear')),
              ),
            ),
          ]),
      ]),
    );
  }
}
