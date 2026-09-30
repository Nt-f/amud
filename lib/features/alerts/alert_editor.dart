import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/adaptive.dart';
import '../../core/settings.dart';
import '../zmanim/zman_catalog.dart';
import 'alerts.dart';

const _presets = <(String, String)>[
  ('Every day', 'true'),
  ('Weekdays (not Shabbat/Yom Tov)', '!shabbat && !yomTov'),
  ('Erev Shabbat', 'erevShabbat'),
  ('Shabbat & Yom Tov', 'shabbat || yomTov'),
  ('Fast days', 'fastDay'),
  ('During the Omer', 'omer'),
  ('Rosh Chodesh', 'roshChodesh'),
  ('Mondays & Thursdays', 'monThu'),
];

Future<void> showAlertEditor(BuildContext context, WidgetRef ref, {ZmanAlert? existing, String? zmanKey}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _AlertEditor(existing: existing, zmanKey: zmanKey),
    );

class _AlertEditor extends ConsumerStatefulWidget {
  final ZmanAlert? existing;
  final String? zmanKey;
  const _AlertEditor({this.existing, this.zmanKey});

  @override
  ConsumerState<_AlertEditor> createState() => _AlertEditorState();
}

class _AlertEditorState extends ConsumerState<_AlertEditor> {
  late String zmanKey = widget.existing?.zmanKey ?? widget.zmanKey ?? 'sofZmanShma';
  late int offset = widget.existing?.offsetMinutes ?? -15;
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _when = TextEditingController(text: widget.existing?.when ?? 'true');
  String? _whenError;

  @override
  Widget build(BuildContext context) {
    final names = ref.watch(zmanResolverProvider);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.existing == null ? 'New zman alert' : 'Edit alert', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: zmanKey,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Zman'),
              items: [for (final (k, n) in names.allKeys) DropdownMenuItem(value: k, child: Text(n, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => zmanKey = v!),
            ),
            const SizedBox(height: 12),
            Text(offset == 0 ? 'Notify at the zman' : 'Notify ${offset.abs()} min ${offset < 0 ? 'before' : 'after'}'),
            Slider.adaptive(
              value: offset.toDouble(),
              min: -120,
              max: 120,
              divisions: 240,
              label: '$offset',
              onChanged: (v) => setState(() => offset = v.round()),
            ),
            Wrap(spacing: 6, children: [
              for (final m in const [-60, -30, -15, -10, -5, 0, 5, 10, 30])
                ChoiceChip(label: Text(m == 0 ? 'At' : (m < 0 ? '${-m}m before' : '${m}m after')), selected: offset == m, onSelected: (_) => setState(() => offset = m)),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _title, decoration: InputDecoration(labelText: 'Title', hintText: names.name(zmanKey))),
            const SizedBox(height: 12),
            const SheetLabel('Only on'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (label, expr) in _presets)
                ChoiceChip(label: Text(label), selected: _when.text == expr, onSelected: (_) => setState(() => _when.text = expr)),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _when,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'Condition (advanced)',
                helperText: 'e.g. !shabbat && (roshChodesh || dow in [1, 4])',
                errorText: _whenError,
              ),
              onChanged: (_) => setState(() => _whenError = null),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                try {
                  Condition.parse(_when.text.trim().isEmpty ? 'true' : _when.text.trim());
                } catch (e) {
                  setState(() => _whenError = '$e');
                  return;
                }
                final backend = ref.read(notificationBackendProvider);
                await backend.requestPermission(exact: ref.read(settingsProvider).exactAlarms);
                final a = ZmanAlert(
                  id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                  title: _title.text.trim().isEmpty ? names.name(zmanKey) : _title.text.trim(),
                  zmanKey: zmanKey,
                  offsetMinutes: offset,
                  when: _when.text.trim().isEmpty ? 'true' : _when.text.trim(),
                  enabled: widget.existing?.enabled ?? true,
                );
                ref.read(alertsProvider.notifier).upsert(a);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save alert'),
            ),
          ]),
        ),
      ),
    );
  }
}
