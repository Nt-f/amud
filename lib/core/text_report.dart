import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'l10n.dart';
import 'providers.dart';
import 'storage.dart';
import 'sync/sync_service.dart';

const _reporterKey = 'reporterId';

/// The random id reports are filed under: made once per install, kept
/// forever, never derived from or shared with anything else (not sync, not
/// the device, not an account).
String reporterId(Storage storage) {
  final saved = storage.readJson(_reporterKey, (j) => j as String);
  if (saved != null && RegExp(r'^[0-9a-f]{32}$').hasMatch(saved)) return saved;
  final r = Random.secure();
  final id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  storage.writeJson(_reporterKey, id);
  return id;
}

/// Where reports go: the sync Worker the user chose, else the default one.
/// Empty when there is none (the dialog then falls back to GitHub).
String reportWorkerUrl(Storage storage) {
  final cfg = storage.readJson(syncConfigKey, (j) => (j as Map).cast<String, Object?>());
  return (cfg?['url'] as String?) ?? defaultSyncWorker;
}

/// Posts a report to the Worker; throws on any failure.
Future<void> sendReport(
  String baseUrl,
  String uid,
  Map<String, String> fields, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final res = await c
      .post(
        Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/v1/report'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'uid': uid, ...fields, 'app': 'amud'}),
      )
      .timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
}

/// Extends the reader's native selection menu without replacing Copy/Select all.
Widget textReportMenu(
  BuildContext context,
  SelectableRegionState state, {
  required String selectedText,
  required String location,
  VoidCallback? onExplain,
}) => AdaptiveTextSelectionToolbar.buttonItems(
  anchors: state.contextMenuAnchors,
  buttonItems: [
    ...state.contextMenuButtonItems,
    if (onExplain != null && selectedText.trim().isNotEmpty)
      ContextMenuButtonItem(label: context.tr("Explain this line"), onPressed: () { state.hideToolbar(); onExplain(); }),
    if (selectedText.trim().isNotEmpty)
      ContextMenuButtonItem(
        label: context.tr('Report'),
        onPressed: () {
          state.hideToolbar();
          showDialog<void>(
            context: context,
            builder: (_) =>
                _TextReportDialog(text: selectedText, location: location),
          );
        },
      ),
  ],
);

class _TextReportDialog extends StatefulWidget {
  final String text;
  final String location;
  const _TextReportDialog({required this.text, required this.location});

  @override
  State<_TextReportDialog> createState() => _TextReportDialogState();
}

class _TextReportDialogState extends State<_TextReportDialog> {
  final _form = GlobalKey<FormState>();
  final _details = TextEditingController();
  final _correction = TextEditingController();
  String _type = 'Text error';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    _correction.dispose();
    super.dispose();
  }

  String get _body =>
      'Reading location: ${widget.location}\n'
      'Issue type: $_type\n\nSelected text:\n${widget.text}\n\n'
      'Issue details:\n${_details.text.trim()}\n\n'
      'Suggested correction:\n${_correction.text.trim()}';

  late final Storage _storage = ProviderScope.containerOf(context, listen: false).read(storageProvider);
  late final String _worker = reportWorkerUrl(_storage);

  Future<void> _openReport() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    if (_worker.isNotEmpty) {
      try {
        await sendReport(_worker, reporterId(_storage), {
          'location': widget.location,
          'type': _type,
          'text': widget.text,
          'details': _details.text.trim(),
          'correction': _correction.text.trim(),
        });
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final thanks = context.tr('Report sent. Thank you!');
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(content: Text(thanks)));
      } catch (_) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = context.tr('Could not send the report. Check your connection and try again.');
          });
        }
      }
      return;
    }
    try {
      final opened = await launchUrl(
        Uri.https('github.com', '/Nt-f/amud/issues/new', {
          'title': 'Text report: ${widget.location}',
          'body': _body,
        }),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (opened) {
        Navigator.pop(context);
      } else {
        setState(
          () => _error = context.tr(
            'Could not open GitHub. Copy the report and try again.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = context.tr(
            'Could not open GitHub. Copy the report and try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('Report a text issue')),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.location,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(child: Text(widget.text)),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: context.tr('Issue type'),
                ),
                items: [
                  for (final type in [
                    'Text error',
                    'Translation issue',
                    'Formatting issue',
                    'Wrong text for today',
                    'Other',
                  ])
                    DropdownMenuItem(
                      value: type,
                      child: Text(context.tr(type)),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _type = value!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _details,
                enabled: !_busy,
                minLines: 3,
                maxLines: 5,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: context.tr('What is the issue?'),
                  alignLabelWithHint: true,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? context.tr('Please describe the issue.')
                    : null,
              ),
              TextFormField(
                controller: _correction,
                enabled: !_busy,
                minLines: 1,
                maxLines: 3,
                maxLength: 1000,
                decoration: InputDecoration(
                  labelText: context.tr('Suggested correction (optional)'),
                ),
              ),
              Text(
                context.tr(
                  _worker.isEmpty
                      ? 'Opens GitHub with your report filled in. Review and submit it there. Reports are public.'
                      : 'Reports are tied to a permanent anonymous ID made on this device. It is not linked to your name, account, settings sync or anything else, and it lets us spot repeat or spam reports.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _body));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.tr('Report copied'))),
                      );
                    }
                  },
                  child: Text(context.tr('Copy report')),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: Text(context.tr('Cancel')),
      ),
      FilledButton(
        onPressed: _busy ? null : _openReport,
        child: Text(context.tr(_worker.isEmpty ? 'Continue to GitHub' : 'Send report')),
      ),
    ],
  );
}
