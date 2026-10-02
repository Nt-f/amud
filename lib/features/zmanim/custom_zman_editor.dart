import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adaptive.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import 'zman_catalog.dart';
import '../../core/l10n.dart';

Future<void> showCustomZmanEditor(BuildContext context, WidgetRef ref, {CustomZman? existing}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _CustomZmanEditor(existing: existing),
    );

class _CustomZmanEditor extends ConsumerStatefulWidget {
  final CustomZman? existing;
  const _CustomZmanEditor({this.existing});

  @override
  ConsumerState<_CustomZmanEditor> createState() => _CustomZmanEditorState();
}

class _CustomZmanEditorState extends ConsumerState<_CustomZmanEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late CustomZmanKind kind = widget.existing?.kind ?? CustomZmanKind.offset;
  late double value = widget.existing?.value ?? 7.5;
  late bool rising = widget.existing?.rising ?? false;
  late String baseKey = widget.existing?.baseKey ?? 'sunset';
  late double minutes = widget.existing?.minutes ?? -13.5;
  late String system = widget.existing?.system ?? 'gra';

  CustomZman get draft => CustomZman(
        id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: _name.text.trim().isEmpty ? 'Custom zman' : _name.text.trim(),
        kind: kind,
        value: value,
        rising: rising,
        baseKey: baseKey,
        minutes: minutes,
        system: system,
      );

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final z = ref.watch(zmanimProvider(today));
    final loc = ref.watch(locationProvider);
    final hour12 = ref.watch(settingsProvider.select((s) => s.hour12));
    final preview = draft.compute(z);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.existing == null ? 'New custom zman' : 'Edit custom zman', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: InputDecoration(labelText: context.tr('Name')), onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
            ChoiceBar<CustomZmanKind>(
              options: [
                (CustomZmanKind.offset, context.tr('Offset'), null),
                (CustomZmanKind.degrees, context.tr('Sun angle'), null),
                (CustomZmanKind.shaahZmanit, context.term('Shaot'), null),
              ],
              selected: kind,
              onChanged: (v) => setState(() => kind = v),
            ),
            const SizedBox(height: 12),
            ...switch (kind) {
              CustomZmanKind.offset => [
                  DropdownButtonFormField<String>(
                    initialValue: baseKey,
                    decoration: InputDecoration(labelText: context.tr('Relative to')),
                    items: [for (final d in builtInZmanim) DropdownMenuItem(value: d.key, child: Text(d.en))],
                    onChanged: (v) => setState(() => baseKey = v!),
                  ),
                  Text(context.tr(minutes < 0 ? 'Minutes: {n} (before)' : 'Minutes: {n} (after)', {'n': minutes.toStringAsFixed(1)})),
                  Slider.adaptive(value: minutes, min: -180, max: 180, divisions: 720, onChanged: (v) => setState(() => minutes = v)),
                ],
              CustomZmanKind.degrees => [
                  Text(context.tr('Sun {deg}° below the horizon', {'deg': value.toStringAsFixed(2)})),
                  Slider.adaptive(value: value.clamp(-2, 26), min: -2, max: 26, divisions: 1120, onChanged: (v) => setState(() => value = v)),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(rising ? 'Morning (before sunrise)' : 'Evening (after sunset)'),
                    value: rising,
                    onChanged: (v) => setState(() => rising = v),
                  ),
                ],
              CustomZmanKind.shaahZmanit => [
                  Text('${value.toStringAsFixed(2)} shaos zmaniyos into the day'),
                  Slider.adaptive(value: value.clamp(0, 12), min: 0, max: 12, divisions: 48, onChanged: (v) => setState(() => value = v)),
                  DropdownButtonFormField<String>(
                    initialValue: system,
                    decoration: InputDecoration(labelText: context.tr('Day defined by')),
                    items: const [
                      DropdownMenuItem(value: 'gra', child: Text('GRA (sunrise–sunset)')),
                      DropdownMenuItem(value: 'mga', child: Text('MGA (72 min)')),
                      DropdownMenuItem(value: 'deg16_1', child: Text('16.1° dawn–nightfall')),
                      DropdownMenuItem(value: 'baalHatanya', child: Text('Baal HaTanya (1.583°)')),
                    ],
                    onChanged: (v) => setState(() => system = v!),
                  ),
                ],
            },
            const SizedBox(height: 8),
            Text(context.tr('Today: {time}', {'time': formatTime(preview, loc, hour12: hour12, seconds: true)}), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                ref.read(customZmanimProvider.notifier).upsert(draft);
                Navigator.pop(context);
              },
              child: Text(context.tr('Save')),
            ),
          ]),
        ),
      ),
    );
  }
}
