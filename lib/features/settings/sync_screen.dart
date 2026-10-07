import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adaptive.dart';
import '../../core/l10n.dart';
import '../../core/sync/sync_codec.dart';
import '../../core/sync/sync_service.dart';
import '../../core/sync/sync_transport.dart';

/// Settings → Advanced → Sync between devices.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final _worker = TextEditingController();
  final _code = TextEditingController();
  String? _message; // English; shown through tr()
  bool _working = false;
  bool? _workerOk;

  @override
  void dispose() {
    _worker.dispose();
    _code.dispose();
    super.dispose();
  }

  /// A failure in the reader's language. Server detail ("answered 500") keeps
  /// its number; the rest is a fixed sentence.
  String _errorText(BuildContext context, String e) {
    final status = RegExp(r'^The sync server answered (\d+)').firstMatch(e)?.group(1);
    if (status != null) return context.tr('The sync server answered {n}.', {'n': status});
    if (e.startsWith('Could not reach the sync server')) return context.tr('Could not reach the sync server.');
    return context.tr(e);
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => (_working = true, _message = null));
    try {
      await job();
    } on SyncTransportError catch (e) {
      _message = e.message;
    } catch (e) {
      _message = e.toString();
    }
    if (mounted) setState(() => _working = false);
  }

  String? get _customUrl => _worker.text.trim().isEmpty ? null : normalizeWorkerUrl(_worker.text);

  Future<void> _start() => _run(() async {
        if (_worker.text.trim().isNotEmpty && _customUrl == null) throw SyncTransportError('That is not a valid https address.');
        await ref.read(syncProvider.notifier).startNew(workerUrl: _customUrl);
      });

  Future<void> _join() => _run(() async {
        if (!await ref.read(syncProvider.notifier).join(_code.text)) throw SyncTransportError('That is not a pairing code.');
        _code.clear();
      });

  Future<void> _test() async {
    final url = _customUrl ?? (defaultSyncWorker.isEmpty ? null : defaultSyncWorker);
    if (url == null) {
      setState(() => _workerOk = false);
      return;
    }
    setState(() => (_working = true, _workerOk = null));
    final ok = await WorkerTransport.check(url);
    if (mounted) setState(() => (_working = false, _workerOk = ok));
  }

  Future<void> _leave({required bool deleteRemote}) async {
    final ok = await showAdaptiveConfirm(
      context,
      title: context.tr(deleteRemote ? 'Stop and delete from server?' : 'Stop syncing on this device?'),
      message: context.tr(deleteRemote
          ? 'Removes the synced copy from the server, so none of your devices will sync until you pair them again. Settings on each device stay.'
          : 'Your settings stay as they are. The other devices keep syncing.'),
      confirm: deleteRemote ? 'Delete' : 'Stop',
    );
    if (!ok || !mounted) return;
    await _run(() => ref.read(syncProvider.notifier).leave(deleteRemote: deleteRemote));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(syncProvider);
    final theme = Theme.of(context);
    Widget pad(Widget w) => Padding(padding: const EdgeInsets.all(16), child: w);
    final error = _message ?? s.error;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Sync between devices'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        pad(Text(
          context.tr('Keeps your reading and display settings the same on all your devices. It is end-to-end encrypted: the server only holds scrambled data it cannot read, and there is no account.'),
          style: theme.textTheme.bodyMedium,
        )),
        if (error != null)
          pad(Text(_errorText(context, error), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error))),
        if (s.enabled) ...[
          AdaptiveSection(header: context.tr('Status'), children: [
            ListTile(
              leading: s.busy || _working ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
              title: Text(s.busy ? context.tr('Syncing…') : context.tr('Sync now')),
              subtitle: Text(s.lastSynced == null
                  ? context.tr('Not synced yet')
                  : context.tr('Last synced {time}', {'time': MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(s.lastSynced!))})),
              onTap: s.busy ? null : () => ref.read(syncProvider.notifier).syncNow(),
            ),
          ]),
          AdaptiveSection(
            header: context.tr('Add another device'),
            footer: context.tr('Enter this code on your other device under Join. Anyone who has it can read your synced settings, so keep it private.'),
            children: [
              pad(SelectableText(s.pairingCode ?? '', style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(context.tr('Copy pairing code')),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: s.pairingCode ?? ''));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Copied'))));
                },
              ),
            ],
          ),
          AdaptiveSection(header: context.tr('Server'), children: [
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: Text(s.workerUrl ?? ''),
              subtitle: Text(s.workerUrl == defaultSyncWorker ? context.tr('Default server') : context.tr('Your own server')),
            ),
          ]),
          AdaptiveSection(children: [
            ListTile(leading: const Icon(Icons.link_off), title: Text(context.tr('Stop syncing on this device')), onTap: _working ? null : () => _leave(deleteRemote: false)),
            ListTile(
              leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              title: Text(context.tr('Stop and delete from server'), style: TextStyle(color: theme.colorScheme.error)),
              onTap: _working ? null : () => _leave(deleteRemote: true),
            ),
          ]),
        ] else ...[
          AdaptiveSection(header: context.tr('First device'), children: [
            ListTile(
              leading: const Icon(Icons.sync),
              title: Text(context.tr('Start syncing')),
              subtitle: Text(context.tr('Makes a pairing code to enter on your other devices')),
              trailing: _working ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
              onTap: _working ? null : _start,
            ),
          ]),
          AdaptiveSection(header: context.tr('Another device'), children: [
            pad(TextField(
              controller: _code,
              minLines: 1,
              maxLines: 3,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: context.tr('Pairing code'), hintText: 'amud1:…'),
            )),
            ListTile(
              leading: const Icon(Icons.login),
              title: Text(context.tr('Join')),
              onTap: _working ? null : _join,
            ),
          ]),
          AdaptiveSection(
            header: context.tr('Advanced'),
            footer: context.tr('Run your own server with the Cloudflare Worker in worker/sync (see its README) and enter its address here. Devices you pair take the address from the pairing code.'),
            children: [
              pad(TextField(
                controller: _worker,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() => _workerOk = null),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: context.tr('Your own server (optional)'),
                  hintText: 'https://amud-sync.example.workers.dev',
                  helperText: defaultSyncWorker.isEmpty ? context.tr('Required: no default server is set up yet') : null,
                ),
              )),
              ListTile(
                leading: Icon(_workerOk == null ? Icons.network_check : _workerOk! ? Icons.check_circle_outline : Icons.error_outline,
                    color: _workerOk == null ? null : _workerOk! ? Colors.green : theme.colorScheme.error),
                title: Text(_workerOk == null
                    ? context.tr('Test connection')
                    : _workerOk!
                        ? context.tr('Connected')
                        : context.tr('Not an Amud sync server')),
                onTap: _working ? null : _test,
              ),
            ],
          ),
        ],
        AdaptiveSection(header: context.tr('What syncs'), children: [
          pad(Text(
            context.tr('Syncs: text, language and display settings, minhagim, learning text settings, shiurim settings, personal dates, custom zmanim and rules. Stays on each device: location, reminders, fonts you added, and what you have shared about usage.'),
            style: theme.textTheme.bodySmall,
          )),
        ]),
      ]),
    );
  }
}
