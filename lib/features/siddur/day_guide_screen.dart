import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../home/cards/card_frame.dart';
import 'day_explanations.dart';
import 'today_summary.dart';
import 'today_plan.dart';
import 'reader_screen.dart';
import 'siddur_print.dart';
import 'prayer_insights.dart';

void openDayGuide(BuildContext context, HDate date) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DayGuideScreen(initialDate: date),
      ),
    );

class DayGuideScreen extends ConsumerStatefulWidget {
  final HDate initialDate;
  const DayGuideScreen({super.key, required this.initialDate});
  @override
  ConsumerState<DayGuideScreen> createState() => _DayGuideScreenState();
}

class _DayGuideScreenState extends ConsumerState<DayGuideScreen> {
  late HDate date = widget.initialDate;
  Future<void> _sectionReason(
    String book,
    SchemaNode node,
    Service fallback,
  ) async {
    try {
      final resolver = await ref.read(resolverProvider(book).future);
      final decisions =
          <
            ({
              String title,
              String label,
              DayContext day,
              String when,
              Applicability ap,
            })
          >[];
      for (final part in [...node.ancestors, node, ...node.descendants]) {
        final rule = resolver.sectionRuleFor(part);
        if (rule == null || rule.when == 'true') continue;
        final day = ref.read(
          dayContextProvider((
            date.abs(),
            SiddurResolver.serviceFor(part, fallback),
          )),
        );
        final unknown = <String>{};
        final applies = rule.condition.eval(day.env, unknown);
        decisions.add((
          title: part.en,
          label: rule.labelEn,
          day: day,
          when: rule.when,
          ap: unknown.isNotEmpty
              ? Applicability.unknown
              : applies
              ? Applicability.today
              : Applicability.notToday,
        ));
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('Why today?')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$book / ${node.id}'),
                  if (decisions.isEmpty)
                    Text(
                      context.tr(
                        'This section has no date condition. Individual lines may have their own instructions.',
                      ),
                    ),
                  for (final decision in decisions) ...[
                    const SizedBox(height: 12),
                    Text(
                      decision.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (decision.label.isNotEmpty) Text(decision.label),
                    Text(
                      context.tr(switch (decision.ap) {
                        Applicability.today => 'Included for this date',
                        Applicability.notToday => 'Omitted for this date',
                        _ => 'Depends on circumstances not known to Amud',
                      }),
                    ),
                    Text(
                      '${decision.day.hdate.render('en')} · ${decision.day.service.name}',
                    ),
                    for (final fact in conditionFacts(
                      decision.when,
                      decision.day,
                    ))
                      Text(fact),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    context.tr(
                      'Uses the rules for this siddur, including your custom rules.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('Close')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('Unable to load the explanation. Please try again.'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(dayContextProvider((date.abs(), Service.shacharit)));
    final mincha = ref.watch(dayContextProvider((date.abs(), Service.mincha)));
    final night = ref.watch(dayContextProvider((date.abs(), Service.maariv)));
    final changes = summarizeDay(day, mincha, night);
    final plan = ref.watch(todayPlanProvider(date.abs()));
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Siddur for a date')),
        actions: [
          IconButton(
            tooltip: context.tr('Choose date'),
            icon: const Icon(Icons.event),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date.greg(),
                firstDate: DateTime(1900),
                lastDate: DateTime(2239),
              );
              if (picked != null && mounted) {
                setState(() => date = HDate.fromDate(picked));
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            date.render('en'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(date.greg().toIso8601String().substring(0, 10)),
          Text('${day.il ? 'Israel' : 'Diaspora'} · ${day.labels.join(' · ')}'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => openSiddurPrint(context, date),
            icon: const Icon(Icons.print),
            label: Text(context.tr('Print siddur / Save PDF')),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('Why today?'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final change in changes)
            ExpansionTile(
              title: Text(context.term(change.en)),
              subtitle: change.detail == null ? null : Text(change.detail!),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr(explainDayChange(change, day, mincha, night))),
              ],
            ),
          const SizedBox(height: 16),
          Text(
            context.tr('Prayers for this date'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(context.tr('Evening prayers belong to the next Hebrew date.')),
          plan.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) =>
                Text(context.tr('Unable to load prayers. Please try again.')),
            data: (p) => p == null
                ? Text(context.tr('No prayers available.'))
                : Column(
                    children: [
                      if (p.needsMachzor)
                        Text(
                          context.tr(
                            'This day requires a machzor; the bundled siddur does not contain the complete service.',
                          ),
                        ),
                      for (final service in p.services)
                        ExpansionTile(
                          title: Text(context.term(service.en)),
                          subtitle: service.tonight
                              ? Text(night.hdate.render('en'))
                              : null,
                          children: [
                            for (final entry in service.entries)
                              ListTile(
                                title: Text(context.term(entry.node.en)),
                                subtitle: Text(entry.book),
                                trailing: IconButton(
                                  tooltip: context.tr('Why today?'),
                                  icon: const Icon(Icons.help_outline),
                                  onPressed: () => _sectionReason(
                                    entry.book,
                                    entry.node,
                                    service.tonight
                                        ? Service.maariv
                                        : Service.shacharit,
                                  ),
                                ),
                                onTap: () {
                                  ref.read(readerDateProvider.notifier).state =
                                      date;
                                  context.push(
                                    readerPath(
                                      entry.book,
                                      entry.node.id,
                                      standalone: true,
                                    ),
                                  );
                                },
                              ),
                            for (final skipped in service.skipped)
                              ListTile(
                                leading: const Icon(
                                  Icons.remove_circle_outline,
                                ),
                                title: Text(context.term(skipped.en)),
                                subtitle: Text(
                                  context.tr('Omitted for this date'),
                                ),
                                trailing: const Icon(Icons.help_outline),
                                onTap: () => _sectionReason(
                                  service.whole?.book ?? p.book,
                                  skipped,
                                  service.tonight
                                      ? Service.maariv
                                      : Service.shacharit,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class PrepareTomorrowCard extends ConsumerWidget {
  const PrepareTomorrowCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The actual upcoming civil day, independent of a reader's preview date.
    final date = HDate.fromAbs(ref.watch(todayProvider).abs + 1);
    final day = ref.watch(dayContextProvider((date.abs(), Service.shacharit)));
    final previous = date.abs() - 1;
    final previousNames = summarizeDay(
      ref.watch(dayContextProvider((previous, Service.shacharit))),
      ref.watch(dayContextProvider((previous, Service.mincha))),
      ref.watch(dayContextProvider((previous, Service.maariv))),
    ).map((c) => c.en).toSet();
    final changes =
        summarizeDay(
              day,
              ref.watch(dayContextProvider((date.abs(), Service.mincha))),
              ref.watch(dayContextProvider((date.abs(), Service.maariv))),
            )
            .where(
              (c) => c.kind != ChangeKind.info || !previousNames.contains(c.en),
            )
            .toList();
    return CardFrame(
      title: 'Prepare for tomorrow',
      icon: Icons.nights_stay_outlined,
      onTap: () => openDayGuide(context, date),
      trailing: const Icon(Icons.chevron_right),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(date.render('en')),
          for (final change in changes.take(5)) Text(context.term(change.en)),
          if (changes.isEmpty)
            Text(context.tr('No special additions or omissions.')),
          if (changes.length > 5) Text(context.tr('Tap to see all changes.')),
          Text(context.tr('Preview prayers and print ahead.')),
        ],
      ),
    );
  }
}
