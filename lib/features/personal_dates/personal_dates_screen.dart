import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';

import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../alerts/alerts.dart';
import 'personal_dates.dart';

String personalDateLabel(PersonalDateKind kind) => switch (kind) {
  PersonalDateKind.yahrzeit => 'Yahrzeit',
  PersonalDateKind.birthday => 'Hebrew birthday',
  PersonalDateKind.barMitzvah => 'Bar mitzvah parsha',
};

class PersonalDatesScreen extends ConsumerWidget {
  const PersonalDatesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dates = ref.watch(personalDatesProvider);
    final today = ref.watch(halachicTodayProvider);
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Personal Hebrew dates'))),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref),
        child: const Icon(Icons.add),
      ),
      body: dates.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.tr(
                    'Add a yahrzeit, Hebrew birthday or bar mitzvah parsha. Dates stay on this device.',
                  ),
                ),
              ),
            )
          : ListView(
              children: [
                for (final date in dates)
                  ListTile(
                    leading: Icon(
                      date.kind == PersonalDateKind.yahrzeit
                          ? Icons.local_fire_department_outlined
                          : Icons.cake_outlined,
                    ),
                    title: Text(date.name),
                    subtitle: Text(() {
                      final next = date.nextOccurrence(today);
                      final parsha = next == null
                          ? null
                          : date.parsha(next, settings.location.il);
                      return '${context.tr(personalDateLabel(date.kind))} · ${next?.render('en') ?? '—'}${parsha == null ? '' : '\n$parsha'}';
                    }()),
                    onTap: () => _edit(context, ref, date),
                    trailing: IconButton(
                      tooltip: context.tr('Delete'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final remove = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: Text(context.tr('Delete personal date?')),
                            content: Text(date.name),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: Text(context.tr('Cancel')),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: Text(context.tr('Delete')),
                              ),
                            ],
                          ),
                        );
                        if (remove == true) {
                          ref
                              .read(personalDatesProvider.notifier)
                              .remove(date.id);
                        }
                      },
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    PersonalDate? existing,
  ]) async {
    final name = TextEditingController(text: existing?.name ?? '');
    var kind = existing?.kind ?? PersonalDateKind.yahrzeit;
    HDate date = existing?.date ?? ref.read(halachicTodayProvider);
    final year = TextEditingController(text: '${date.getFullYear()}');
    final day = TextEditingController(text: '${date.getDate()}');
    var month = date.getMonth();
    var reminder = existing?.reminder ?? true;
    var evening = existing?.eveningBefore ?? true;
    String? error;
    final saved = await showDialog<PersonalDate>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            context.tr(
              existing == null ? 'Add personal date' : 'Edit personal date',
            ),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: InputDecoration(labelText: context.tr('Name')),
                  ),
                  DropdownButtonFormField<PersonalDateKind>(
                    initialValue: kind,
                    items: [
                      for (final k in PersonalDateKind.values)
                        DropdownMenuItem(
                          value: k,
                          child: Text(context.tr(personalDateLabel(k))),
                        ),
                    ],
                    onChanged: (v) => update(() => kind = v!),
                  ),
                  Text(
                    context.tr(
                      kind == PersonalDateKind.yahrzeit
                          ? 'Enter the original Hebrew date of death.'
                          : 'Enter the original Hebrew birth date.',
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: year,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: context.tr('Hebrew year'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: day,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: context.tr('Day'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<int>(
                    key: ValueKey(month),
                    initialValue: month,
                    items: [
                      for (var m = 1; m <= 13; m++)
                        DropdownMenuItem(
                          value: m,
                          child: Text(
                            m == 12
                                ? 'Adar / Adar I'
                                : HDate(1, m, 5784).getMonthName(),
                          ),
                        ),
                    ],
                    onChanged: (v) => month = v!,
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final selected = await showDatePicker(
                        context: ctx,
                        initialDate: date.greg(),
                        firstDate: DateTime(1800),
                        lastDate: DateTime(2200),
                      );
                      if (selected != null) {
                        update(() {
                          date = HDate.fromDate(selected);
                          year.text = '${date.getFullYear()}';
                          day.text = '${date.getDate()}';
                          month = date.getMonth();
                        });
                      }
                    },
                    child: Text(context.tr('Convert a civil date')),
                  ),
                  Text(
                    context.tr(
                      'For a birth or death after sunset, use the following Hebrew day.',
                    ),
                  ),
                  SwitchListTile.adaptive(
                    title: Text(context.tr('Yearly reminder')),
                    value: reminder,
                    onChanged: (v) => update(() => reminder = v),
                  ),
                  SwitchListTile.adaptive(
                    title: Text(context.tr('At sunset the evening before')),
                    subtitle: Text(context.tr('Otherwise at 9 AM on the date')),
                    value: evening,
                    onChanged: (v) => update(() => evening = v),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.tr('Cancel')),
            ),
            FilledButton(
              onPressed: () {
                final y = int.tryParse(year.text), d = int.tryParse(day.text);
                if (name.text.trim().isEmpty ||
                    y == null ||
                    y < 5500 ||
                    y > 6200 ||
                    d == null ||
                    d < 1 ||
                    month > monthsInYear(y) ||
                    d > daysInMonth(month, y)) {
                  update(
                    () => error = context.tr(
                      'Enter a name and a valid Hebrew date.',
                    ),
                  );
                  return;
                }
                Navigator.pop(
                  ctx,
                  PersonalDate(
                    id:
                        existing?.id ??
                        DateTime.now().microsecondsSinceEpoch.toString(),
                    name: name.text.trim(),
                    kind: kind,
                    date: HDate(d, month, y),
                    reminder: reminder,
                    eveningBefore: evening,
                  ),
                );
              },
              child: Text(context.tr('Save')),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    year.dispose();
    day.dispose();
    if (saved == null) return;
    if (saved.reminder) {
      await ref
          .read(notificationBackendProvider)
          .requestPermission(exact: ref.read(settingsProvider).exactAlarms);
    }
    ref.read(personalDatesProvider.notifier).upsert(saved);
  }
}
