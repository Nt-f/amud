import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/l10n.dart';
import '../../core/adaptive.dart';
import '../../core/fonts.dart';
import '../../core/format.dart';
import '../../core/hebrew_text.dart';
import '../../core/html_text.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import 'reader_settings_sheet.dart';
import 'siddur_providers.dart';

typedef _ReaderKey = ({String book, String node, String expanded, int dateAbs});

final _resolvedProvider = FutureProvider.family<List<RenderItem>, _ReaderKey>((ref, k) async {
  final root = await ref.watch(bookIndexProvider(k.book).future);
  final node = root.find(k.node) ?? root;
  final versions = await ref.watch(versionSelectionProvider(k.book).future);
  final resolver = await ref.watch(resolverProvider(k.book).future);
  final s = ref.watch(settingsProvider);
  final daytime = HDate.fromAbs(k.dateAbs);
  final ctxs = <Service, DayContext>{};
  return resolver.resolve(
    node,
    versions,
    (svc) => ctxs.putIfAbsent(svc, () => DayContext.forService(daytime, svc, il: s.location.il, minhagim: s.minhagim)),
    options: ResolveOptions(
      excluded: s.excludedDisplay,
      showNotes: s.showNotes,
      showInstructions: s.showInstructions,
      showHebrew: s.showHebrewText,
      showTranslation: s.showTranslationText,
      notesHebrew: s.showHebrewNotes,
      notesTranslation: s.showEnglishNotes,
      forceExpanded: k.expanded.isEmpty ? const {} : k.expanded.split('|').toSet(),
    ),
  );
});

class ReaderScreen extends ConsumerStatefulWidget {
  final String book;
  final String nodeId;
  const ReaderScreen({super.key, required this.book, required this.nodeId});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _expanded = <String>{};
  final _expandedGroups = <String>{};

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(readerDaytimeDateProvider);
    final picked = ref.watch(readerDateProvider);
    final key = (book: widget.book, node: widget.nodeId, expanded: (_expanded.toList()..sort()).join('|'), dateAbs: date.abs());
    final items = ref.watch(_resolvedProvider(key));
    final rootAsync = ref.watch(bookIndexProvider(widget.book));
    final node = rootAsync.value?.find(widget.nodeId);
    final s = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final hebrewUi = context.uiLanguage != UiLanguage.en;

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(node == null ? context.term(widget.book) : (hebrewUi ? node.he : context.term(node.en)),
              overflow: TextOverflow.ellipsis, style: hebrewUi ? TextStyle(fontFamily: s.hebrewFont) : null),
          if (node != null && !hebrewUi)
            Text(node.he, style: theme.textTheme.bodySmall?.copyWith(fontFamily: s.hebrewFont), textDirection: TextDirection.rtl),
        ]),
        actions: [
          IconButton(
            tooltip: context.tr('Date'),
            icon: Badge(isLabelVisible: picked != null, child: const Icon(Icons.event)),
            onPressed: () => _pickDate(context, date),
          ),
          IconButton(
            tooltip: context.tr('Text settings'),
            icon: const Icon(Icons.text_fields),
            onPressed: () => showReaderSettings(context, widget.book),
          ),
        ],
      ),
      body: Column(children: [
        _DayBanner(date: date, picked: picked != null),
        Expanded(
          child: items.when(
            loading: adaptiveProgress,
            error: (e, st) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
            data: (list) => _list(context, list, node),
          ),
        ),
      ]),
    );
  }

  Future<void> _pickDate(BuildContext context, HDate current) async {
    final g = current.greg();
    final picked = await showDatePicker(
      context: context,
      initialDate: g,
      firstDate: DateTime(1900),
      lastDate: DateTime(2239),
      helpText: context.tr('Pray as of…'),
    );
    if (picked == null) return;
    ref.read(readerDateProvider.notifier).state = HDate.fromDate(picked);
  }

  Widget _list(BuildContext context, List<RenderItem> list, SchemaNode? node) {
    final s = ref.watch(settingsProvider);
    final wide = MediaQuery.sizeOf(context).width > 700;
    final layout = s.layout == TextLayout.sideBySide && !wide ? TextLayout.interleaved : s.layout;
    final rows = <Widget Function(BuildContext)>[];
    if (node != null && list.every((it) => it is HeadingItem)) {
      rows.add((c) => _CollapsedTile(
            icon: Icons.visibility_off_outlined,
            title: context.tr('Not said today'),
            subtitle: context.tr('Tap to show it anyway'),
            he: node.he,
            onTap: () => setState(() => _expanded.add(node.id)),
          ));
    }
    for (final it in list) {
      switch (it) {
        case ExcludedGroupItem g when _expandedGroups.contains(g.key):
          for (final si in g.items) {
            rows.add((c) => _SegmentView(item: si, layout: layout));
          }
        default:
          rows.add((c) => _item(c, it, layout));
      }
    }
    return SelectionArea(
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(wide ? 48 : 16, 8, wide ? 48 : 16, 96),
        itemCount: rows.length + 1,
        itemBuilder: (c, i) => i == rows.length ? _nextSection(c, node) : rows[i](c),
      ),
    );
  }

  Widget _nextSection(BuildContext context, SchemaNode? node) {
    if (node == null || node.parent == null) return const SizedBox.shrink();
    final siblings = node.parent!.children;
    final i = siblings.indexOf(node);
    if (i < 0 || i + 1 >= siblings.length) return const SizedBox.shrink();
    final next = siblings[i + 1];
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: FilledButton.tonalIcon(
        onPressed: () => context.pushReplacement(readerPath(widget.book, next.id)),
        icon: const Icon(Icons.arrow_forward),
        label: Text(context.tr('Next: {title}', {'title': context.term(next.en)})),
      ),
    );
  }

  Widget _item(BuildContext context, RenderItem it, TextLayout layout) {
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final s = ref.read(settingsProvider);
    switch (it) {
      case HeadingItem h:
        if (h.level == 0 && h.node.isLeaf) return const SizedBox(height: 4);
        final size = (24 - h.level * 3).clamp(15, 24).toDouble() * s.textScale;
        return Padding(
          padding: EdgeInsets.only(top: h.level == 0 ? 4 : 20, bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: context.uiLanguage == UiLanguage.en
                  ? Text(context.term(h.node.en),
                      style: theme.textTheme.titleMedium?.copyWith(fontSize: size * 0.72, color: theme.colorScheme.primary, fontWeight: FontWeight.w600))
                  : const SizedBox.shrink(),
            ),
            if (h.applicability == Applicability.today && s.highlightToday && h.labelEn != null)
              Flexible(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _TodayChip(conditionLabel(context, s, h.labelEn, h.labelHe)))),
            Text(h.node.he,
                textDirection: TextDirection.rtl,
                style: TextStyle(fontFamily: s.hebrewFont, fontSize: size, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
          ]),
        );
      case InsertedSectionItem ins:
        return Container(
          margin: const EdgeInsets.only(top: 20),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: colors.todayFill, borderRadius: BorderRadius.circular(12), border: Border.all(color: colors.todayBar)),
          child: Row(children: [
            Icon(Icons.add_circle, color: colors.todayBar, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(context.tr('Added today: {label}', {'label': context.term(ins.labelEn)}), style: theme.textTheme.labelLarge)),
            Text(ins.labelHe, textDirection: TextDirection.rtl, style: TextStyle(fontFamily: s.hebrewFont, fontSize: 16)),
          ]),
        );
      case CollapsedSectionItem c:
        return _CollapsedTile(
          icon: Icons.unfold_more,
          title: context.tr('{title} — not said today', {'title': context.term(c.node.en)}),
          subtitle: conditionLabel(context, s, c.labelEn, c.labelHe),
          he: c.node.he,
          onTap: () => setState(() => _expanded.add(c.node.id)),
        );
      case ExcludedGroupItem g:
        return _CollapsedTile(
          icon: Icons.unfold_more,
          title: context.tr('{n} lines not said today', {'n': g.items.length}),
          subtitle: {
            for (final i in g.items)
              if (i.labelEn != null || i.labelHe != null) conditionLabel(context, s, i.labelEn, i.labelHe),
          }.take(4).join(' · '),
          onTap: () => setState(() => _expandedGroups.add(g.key)),
        );
      case DynamicItem d when d.kind == 'omer':
        return _OmerBlock(d.data);
      case DynamicItem d:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 18, color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (s.showHebrewNotes)
                  Text('${d.data['he']}', textDirection: TextDirection.rtl, style: TextStyle(fontFamily: s.hebrewFont, fontSize: 16)),
                if (s.showEnglishNotes) Text('${d.data['en']}', style: theme.textTheme.bodySmall),
              ]),
            ),
          ]),
        );
      case SegmentItem si:
        return _SegmentView(item: si, layout: layout);
    }
  }
}

String readerPath(String book, String nodeId) =>
    '/siddur/book/${Uri.encodeComponent(book)}/read?node=${Uri.encodeQueryComponent(nodeId)}';

class _DayBanner extends ConsumerWidget {
  final HDate date;
  final bool picked;
  const _DayBanner({required this.date, required this.picked});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctx = ref.watch(dayContextProvider((date.abs(), Service.shacharit)));
    final theme = Theme.of(context);
    final labels = context.uiLanguage == UiLanguage.en ? ctx.labels.map(context.term).toList() : ctx.labelsHe;
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Expanded(
            child: Text(
              '${formatPlainDate(date.plainDate())} · ${date.render(context.hebcalLocale)}${labels.isEmpty ? '' : ' · ${labels.join(', ')}'}',
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (picked)
            TextButton(
              onPressed: () => ref.read(readerDateProvider.notifier).state = null,
              child: Text(context.tr('Today')),
            ),
        ]),
      ),
    );
  }
}

class _TodayChip extends StatelessWidget {
  final String label;
  const _TodayChip(this.label);

  @override
  Widget build(BuildContext context) {
    final colors = SiddurColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: colors.chipToday, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.today, size: 12),
        const SizedBox(width: 4),
        Flexible(child: Text(label, style: Theme.of(context).textTheme.labelSmall)),
      ]),
    );
  }
}

class _CollapsedTile extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? he;
  final VoidCallback onTap;
  const _CollapsedTile({required this.icon, required this.title, this.subtitle, this.he, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hebFont = ref.watch(settingsProvider.select((s) => s.hebrewFont));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: theme.colorScheme.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, style: theme.textTheme.bodySmall),
              ]),
            ),
            if (he != null) Text(he!, textDirection: TextDirection.rtl, style: TextStyle(fontFamily: hebFont, color: theme.colorScheme.outline)),
          ]),
        ),
      ),
    );
  }
}

class _OmerBlock extends ConsumerWidget {
  final Map<String, Object?> data;
  const _OmerBlock(this.data);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final colors = SiddurColors.of(context);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.todayFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.todayBar, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.today, color: colors.todayBar),
          const SizedBox(width: 8),
          Text(context.tr("Tonight's count · day {n}", {'n': data['day']}), style: theme.textTheme.titleSmall),
        ]),
        const SizedBox(height: 10),
        Text('${data['he']}',
            textDirection: TextDirection.rtl,
            style: TextStyle(fontFamily: s.hebrewFont, fontSize: 24 * s.textScale, height: 1.6, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('${data['sefiraHe']}', textDirection: TextDirection.rtl, style: TextStyle(fontFamily: s.hebrewFont, fontSize: 18 * s.textScale)),
        const SizedBox(height: 8),
        Text('${data['en']} — ${data['sefiraEn']} (${data['sefiraTranslit']})', style: theme.textTheme.bodyMedium),
      ]),
    );
  }
}

/// One segment row with today/not-today styling and inline conditional runs.
class _SegmentView extends ConsumerWidget {
  final SegmentItem item;
  final TextLayout layout;
  const _SegmentView({required this.item, required this.layout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final heSize = 22.0 * s.textScale;
    final enSize = 16.0 * s.textScale;
    final today = item.applicability == Applicability.today && s.highlightToday;
    final excluded = item.excluded;

    TextStyle heBase = TextStyle(fontFamily: s.hebrewFont, fontSize: heSize, height: 1.65, color: theme.colorScheme.onSurface);
    TextStyle enBase = TextStyle(fontFamily: s.latinFont, fontSize: enSize, height: 1.5, color: theme.colorScheme.onSurface);
    if (item.kind != SegmentKind.prayer) {
      heBase = heBase.copyWith(fontSize: heSize * 0.7, color: colors.instruction);
      enBase = enBase.copyWith(fontSize: enSize * 0.85, fontStyle: FontStyle.italic, color: colors.instruction);
    }
    if (item.kind == SegmentKind.speaker) {
      heBase = heBase.copyWith(fontWeight: FontWeight.w700);
      enBase = enBase.copyWith(fontWeight: FontWeight.w700, fontStyle: FontStyle.normal);
    }
    if (excluded) {
      heBase = heBase.copyWith(color: colors.excluded);
      enBase = enBase.copyWith(color: colors.excluded);
    }

    void footnote(String note) => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (c) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: SelectableText(note))),
        );

    Widget text(ResolvedSegment seg, TextStyle base, bool rtl) {
      String marks(String h) => seg.segment.hebrew ? hebrewMarks(h, teamim: s.showTeamim, nikud: s.showNikud) : h;
      if (seg.segment.hebrew) {
        final all = seg.runs.map((r) => marks(r.html)).join();
        base = base.copyWith(fontFamily: hebrewFamilyFor(s.hebrewFont, teamim: hasTeamim(all), nikud: hasNikud(all)));
      }
      final html = SefariaHtml(base, instructionStyle: TextStyle(color: colors.instruction, fontStyle: FontStyle.italic), onFootnote: footnote);
      final spans = <InlineSpan>[];
      for (final r in seg.runs) {
        var st = base;
        if (r.marker) {
          st = base.copyWith(fontSize: (base.fontSize ?? 16) * 0.72, color: colors.marker, fontWeight: FontWeight.w600);
        } else if (r.applicability == Applicability.today && s.highlightToday) {
          st = base.copyWith(backgroundColor: colors.todayFill);
        } else if (r.applicability == Applicability.notToday) {
          st = base.copyWith(color: colors.excluded, decoration: TextDecoration.lineThrough, decorationColor: colors.excluded);
        }
        spans.addAll(html.parse(marks(r.html), style: st));
      }
      return Text.rich(TextSpan(children: spans), textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, textAlign: TextAlign.start);
    }

    final he = item.he;
    final tr = item.tr;
    Widget body;
    // The resolver already applied the prayer-text and notes language choices.
    final heW = he == null ? null : text(he, heBase, he.segment.hebrew);
    final trW = tr == null ? null : text(tr, enBase, tr.segment.hebrew);
    if (layout == TextLayout.sideBySide && heW != null && trW != null) {
      body = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: trW),
        const SizedBox(width: 24),
        Expanded(child: heW),
      ]);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ?heW,
        if (heW != null && trW != null) const SizedBox(height: 4),
        ?trW,
      ]);
    }
    if (heW == null && trW == null) return const SizedBox.shrink();

    final label = today || (excluded && item.labelEn != null)
        ? Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              if (today)
                _TodayChip(item.labelEn == null && item.labelHe == null ? context.tr('Today') : conditionLabel(context, s, item.labelEn, item.labelHe))
              else
                Flexible(
                  child: Text(context.tr('Not today · {label}', {'label': conditionLabel(context, s, item.labelEn, item.labelHe)}),
                      style: theme.textTheme.labelSmall?.copyWith(color: colors.excluded)),
                ),
            ]),
          )
        : null;

    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [?label, body]);
    if (!today) return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: content);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: colors.todayFill, borderRadius: BorderRadius.circular(10)),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 8), child: content)),
          Container(width: 4, color: colors.todayBar),
        ]),
      ),
    );
  }
}

/// A "said only on…" condition label in the language(s) chosen for
/// instructions and notes.
String conditionLabel(BuildContext context, AppSettings s, String? en, String? he) {
  final e = en == null ? null : context.term(en);
  final parts = [
    if (s.showEnglishNotes && e != null) e,
    if (s.showHebrewNotes && he != null && he != en) he,
  ];
  return parts.isEmpty ? (e ?? he ?? '') : parts.join(' · ');
}
