import 'dart:async';

import 'package:flutter/gestures.dart';
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
import '../../core/split_row.dart';
import '../../core/theme.dart';
import 'reader_grouping.dart';
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
      conciseNotes: s.showNotes && s.conciseNotes,
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

  /// Opened from a Home shortcut, above the tabs: back returns to Home
  /// rather than the Siddur tab.
  final bool standalone;
  const ReaderScreen({super.key, required this.book, required this.nodeId, this.standalone = false});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _expanded = <String>{};
  final _expandedGroups = <String>{};

  /// Chazarah groups / notes the user toggled away from their default.
  final _toggledChazarah = <String>{};
  final _toggledNotes = <String>{};

  final _selection = GlobalKey<SelectionAreaState>();
  late final StateController<bool> _focus;

  /// Readers alive, so focus mode survives "Next" (which swaps readers)
  /// but ends once the last one closes.
  static int _open = 0;

  @override
  void initState() {
    super.initState();
    _open++;
    _focus = ref.read(focusModeProvider.notifier);
  }

  @override
  void dispose() {
    _open--;
    // Providers can't change while the tree is being torn down.
    scheduleMicrotask(() {
      if (_open == 0) _focus.state = false;
    });
    super.dispose();
  }

  // Double-tap detection from raw pointer events, so single taps on rows
  // aren't delayed and scrolling isn't disturbed.
  Offset? _downAt;
  Duration? _downTime;
  (Offset, Duration)? _lastTap;

  void _pointerDown(PointerDownEvent e) {
    _downAt = e.position;
    _downTime = e.timeStamp;
  }

  void _pointerUp(PointerUpEvent e) {
    final down = _downAt, downTime = _downTime;
    _downAt = null;
    if (down == null || downTime == null) return;
    final isTap = (e.position - down).distance < kTouchSlop && e.timeStamp - downTime < kLongPressTimeout;
    if (!isTap) {
      _lastTap = null;
      return;
    }
    final last = _lastTap;
    if (last != null && e.timeStamp - last.$2 < kDoubleTapTimeout && (e.position - last.$1).distance < kDoubleTapSlop) {
      _lastTap = null;
      _focus.state = !_focus.state;
      // Double-tap also selects a word; drop it once the gesture is done.
      Timer.run(() {
        final region = _selection.currentState?.selectableRegion;
        region?.clearSelection();
        region?.hideToolbar();
      });
    } else {
      _lastTap = (e.position, e.timeStamp);
    }
  }

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
    final focus = ref.watch(focusModeProvider);
    const slide = Duration(milliseconds: 250);

    final bar = AppBar(
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
    );

    return Scaffold(
      body: Column(children: [
        // Focus mode: the bars slide up out of view; the text keeps clear
        // of the status bar.
        ClipRect(
          child: AnimatedAlign(
            duration: slide,
            curve: Curves.easeInOutCubic,
            alignment: Alignment.bottomCenter,
            heightFactor: focus ? 0 : 1,
            child: Column(mainAxisSize: MainAxisSize.min, children: [bar, _DayBanner(date: date, picked: picked != null)]),
          ),
        ),
        Expanded(
          child: AnimatedPadding(
            duration: slide,
            curve: Curves.easeInOutCubic,
            padding: EdgeInsets.only(top: focus ? MediaQuery.paddingOf(context).top : 0),
            child: Listener(
              onPointerDown: _pointerDown,
              onPointerUp: _pointerUp,
              onPointerCancel: (_) => _downAt = null,
              child: items.when(
                loading: adaptiveProgress,
                error: (e, st) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
                data: (list) => _list(context, list, node),
              ),
            ),
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
    // Opened directly on the repetition (e.g. Kedushah): show it as is.
    final groupChazarah = node == null || !isChazarahNode(node);
    var i = 0;
    while (i < list.length) {
      final it = list[i];
      // The line an instruction introduces, past any note placed above it.
      var n = i + 1;
      while (n < list.length && list[n] is DynamicItem) {
        n++;
      }
      final next = n < list.length ? list[n] : null;
      if (it is SegmentItem && isRedundantRubric(it, next is SegmentItem ? next : null, s)) {
        i++;
        continue;
      }
      // Kiddush / Kadesh: one card rather than a run of separate rows.
      final unit = _unitLeafOf(it);
      if (unit != null) {
        final segs = <SegmentItem>[];
        while (i < list.length && _unitLeafOf(list[i]) == unit) {
          final x = list[i];
          if (x is SegmentItem) segs.add(x);
          if (x is ExcludedGroupItem) segs.addAll(x.items);
          i++;
        }
        rows.add((c) => _UnitCard(node: unit, items: segs, layout: layout));
        continue;
      }
      if (groupChazarah && _isChazarah(it)) {
        final group = <RenderItem>[];
        while (i < list.length && _isChazarah(list[i])) {
          group.add(list[i]);
          i++;
        }
        final key = group.first.key;
        final open = s.collapseChazarah == _toggledChazarah.contains(key);
        final titles = <String>[
          for (final g in group)
            if (g is HeadingItem && g.level > 0 || g is CollapsedSectionItem)
              context.uiLanguage == UiLanguage.en
                  ? context.term((g is HeadingItem ? g.node : (g as CollapsedSectionItem).node).en)
                  : (g is HeadingItem ? g.node : (g as CollapsedSectionItem).node).he,
        ];
        if (titles.isEmpty && group.any((g) => g is SegmentItem && isChazarahSegment(g))) titles.add(context.tr('Modim DeRabbanan'));
        rows.add((c) => _ChazarahHeader(
              title: titles.toSet().join(' · '),
              open: open,
              onTap: () => setState(() => _toggledChazarah.contains(key) ? _toggledChazarah.remove(key) : _toggledChazarah.add(key)),
            ));
        if (open) {
          for (final g in group) {
            for (final w in _rowsFor(context, g, layout)) {
              rows.add((c) => _ChazarahBody(child: w(c)));
            }
          }
        }
        continue;
      }
      rows.addAll(_rowsFor(context, it, layout));
      i++;
    }
    return SelectionArea(
      key: _selection,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(wide ? 48 : 16, 8, wide ? 48 : 16, 96),
        itemCount: rows.length + 1,
        itemBuilder: (c, i) => i == rows.length ? _nextSection(c, node) : rows[i](c),
      ),
    );
  }

  /// The row(s) for one render item, with expanded groups and collapsible
  /// notes.
  List<Widget Function(BuildContext)> _rowsFor(BuildContext context, RenderItem it, TextLayout layout) {
    final s = ref.read(settingsProvider);
    switch (it) {
      case ExcludedGroupItem g when _expandedGroups.contains(g.key):
        return [for (final si in g.items) (c) => _SegmentView(item: si, layout: layout)];
      case SegmentItem si when si.kind == SegmentKind.note && s.collapseNotes:
        final open = _toggledNotes.contains(si.key);
        void toggle() => setState(() => open ? _toggledNotes.remove(si.key) : _toggledNotes.add(si.key));
        return [(c) => _NoteRow(item: si, open: open, onTap: toggle, child: open ? _SegmentView(item: si, layout: layout) : null)];
      default:
        return [(c) => _item(c, it, layout)];
    }
  }

  static SchemaNode? _unitLeafOf(RenderItem it) {
    final n = switch (it) {
      SegmentItem s => s.node,
      ExcludedGroupItem g => g.items.first.node,
      _ => null,
    };
    return n != null && isUnitNode(n) ? n : null;
  }

  static bool _isChazarah(RenderItem it) => switch (it) {
        HeadingItem h => h.level > 0 && isChazarahNode(h.node),
        CollapsedSectionItem c => isChazarahNode(c.node),
        SegmentItem s => isChazarahNode(s.node) || isChazarahSegment(s),
        ExcludedGroupItem g => g.items.every((i) => isChazarahNode(i.node)),
        _ => false,
      };

  Widget _nextSection(BuildContext context, SchemaNode? node) {
    if (node == null || node.parent == null) return const SizedBox.shrink();
    final siblings = node.parent!.children;
    final i = siblings.indexOf(node);
    if (i < 0 || i + 1 >= siblings.length) return const SizedBox.shrink();
    final next = siblings[i + 1];
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: FilledButton.tonalIcon(
        // Replaces this page in the browser history too, so back returns
        // to the library rather than the previous section.
        onPressed: () => Router.neglect(context, () => context.pushReplacement(readerPath(widget.book, next.id, standalone: widget.standalone))),
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
          child: SplitRow(gap: 12, children: [
            context.uiLanguage == UiLanguage.en
                ? Text(context.term(h.node.en),
                    style: theme.textTheme.titleMedium?.copyWith(fontSize: size * 0.72, color: theme.colorScheme.primary, fontWeight: FontWeight.w600))
                : const SizedBox.shrink(),
            if (h.applicability == Applicability.today && s.highlightToday && h.labelEn != null)
              _TodayChip(conditionLabel(context, s, h.labelEn, h.labelHe)),
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
            Expanded(
              child: SplitRow(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Text(context.tr('Added today: {label}', {'label': context.term(ins.labelEn)}), style: theme.textTheme.labelLarge),
                Text(ins.labelHe, textDirection: TextDirection.rtl, style: TextStyle(fontFamily: s.hebrewFont, fontSize: 16)),
              ]),
            ),
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

String readerPath(String book, String nodeId, {bool standalone = false}) => standalone
    ? '/read/${Uri.encodeComponent(book)}?node=${Uri.encodeQueryComponent(nodeId)}'
    : '/siddur/book/${Uri.encodeComponent(book)}/read?node=${Uri.encodeQueryComponent(nodeId)}';

/// A section of the default siddur by shortcut key (`shacharit`, `omer`,
/// …), opened standalone from Home.
class SectionReaderScreen extends ConsumerWidget {
  final String section;
  const SectionReaderScreen({super.key, required this.section});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(defaultBookProvider).value;
    final root = book == null ? null : ref.watch(bookIndexProvider(book)).value;
    if (book == null || root == null) return Scaffold(appBar: AppBar(), body: adaptiveProgress());
    final shabbat = ref.watch(dayContextProvider((ref.watch(readerDaytimeDateProvider).abs(), Service.shacharit)))['shabbat'];
    final id = findSection(root, section, shabbat: shabbat);
    if (id == null) return Scaffold(appBar: AppBar(), body: Center(child: Text(context.tr('Not found in this siddur'))));
    return ReaderScreen(key: ValueKey(id), book: book, nodeId: id, standalone: true);
  }
}

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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: colors.chipToday, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.today, size: 11),
        const SizedBox(width: 3),
        Flexible(
          child: Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(height: 1.2), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
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
              child: SplitRow(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                  if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, style: theme.textTheme.bodySmall),
                ]),
                if (he != null) Text(he!, textDirection: TextDirection.rtl, style: TextStyle(fontFamily: hebFont, color: theme.colorScheme.outline)),
              ]),
            ),
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
          Expanded(child: Text(context.tr("Tonight's count · day {n}", {'n': data['day']}), style: theme.textTheme.titleSmall)),
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

  /// Tighter spacing, inside a card such as Kiddush.
  final bool compact;
  const _SegmentView({required this.item, required this.layout, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final heSize = 22.0 * s.textScale;
    final enSize = 16.0 * s.textScale;
    // Only the words said get the "today" treatment; a note about today
    // reads as a note.
    final today = item.applicability == Applicability.today && s.highlightToday && item.kind == SegmentKind.prayer;
    final excluded = item.excluded;
    // One of several alternative lines not said today: crossed out beside
    // the one that is, rather than labelled.
    final strike = excluded && item.option;

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
    if (strike) {
      heBase = heBase.copyWith(decoration: TextDecoration.lineThrough, decorationColor: colors.excluded);
      enBase = enBase.copyWith(decoration: TextDecoration.lineThrough, decorationColor: colors.excluded);
    }

    void footnote(String note) => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (c) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: SelectableText(note))),
        );

    Widget text(ResolvedSegment seg, TextStyle base, bool rtl, {InlineSpan? lead}) {
      String marks(String h) => seg.segment.hebrew ? hebrewMarks(h, teamim: s.showTeamim, nikud: s.showNikud) : h;
      if (seg.segment.hebrew) {
        final all = seg.runs.map((r) => marks(r.html)).join();
        base = base.copyWith(fontFamily: hebrewFamilyFor(s.hebrewFont, teamim: hasTeamim(all), nikud: hasNikud(all)));
      }
      final html = SefariaHtml(base, instructionStyle: TextStyle(color: colors.instruction, fontStyle: FontStyle.italic), onFootnote: footnote);
      final spans = <InlineSpan>[?lead];
      var inOptions = false;
      for (final r in seg.runs) {
        // Each labelled option ("לר"ח: …", "לפסח: …") starts its own line so
        // the choices are easy to tell apart.
        final optionStart = r.option && r.marker;
        if (optionStart || (inOptions && !r.option)) spans.add(const TextSpan(text: '\n'));
        if (r.marker) inOptions = r.option;
        if (!r.option && !r.marker) inOptions = false;
        var st = base;
        if (r.marker) {
          st = base.copyWith(fontSize: (base.fontSize ?? 16) * 0.72, color: colors.marker, fontWeight: FontWeight.w600);
          if (r.applicability == Applicability.notToday) st = st.copyWith(color: colors.excluded);
        } else if (r.applicability == Applicability.today && s.highlightToday) {
          // Inside a highlighted line the chosen option needs to stand out
          // from the highlight itself.
          st = r.option
              ? base.copyWith(backgroundColor: colors.todayBar.withValues(alpha: 0.3), fontWeight: FontWeight.w600)
              : base.copyWith(backgroundColor: colors.todayFill);
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
    // "Said only on…" labels sit inline at the start of the text instead
    // of on a line of their own.
    InlineSpan? lead;
    if (today || (excluded && !strike && item.labelEn != null)) {
      final l = conditionLabel(context, s, item.labelEn, item.labelHe);
      lead = WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: today
              ? _TodayChip(item.labelEn == null && item.labelHe == null ? context.tr('Today') : l)
              : Text(context.tr('Not today · {label}', {'label': l}), style: theme.textTheme.labelSmall?.copyWith(color: colors.excluded)),
        ),
      );
    }
    final heW = he == null ? null : text(he, heBase, he.segment.hebrew, lead: lead);
    final trW = tr == null ? null : text(tr, enBase, tr.segment.hebrew, lead: he == null ? lead : null);
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

    final content = body;
    if (!today) return Padding(padding: EdgeInsets.symmetric(vertical: compact ? 3 : 5), child: content);
    return Container(
      margin: EdgeInsets.symmetric(vertical: compact ? 2 : 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: colors.todayFill, borderRadius: BorderRadius.circular(10)),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(10, 4, 10, 4), child: content)),
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

/// The row standing for a run of the chazzan's repetition: a distinct
/// color, faded, and tappable to show or hide it.
class _ChazarahHeader extends StatelessWidget {
  final String title;
  final bool open;
  final VoidCallback onTap;
  const _ChazarahHeader({required this.title, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final label = context.term('Chazarat HaShatz');
    return Padding(
      padding: EdgeInsets.only(top: 6, bottom: open ? 0 : 6),
      child: Opacity(
        opacity: open ? 1 : 0.75,
        child: Material(
          color: colors.chazarahFill,
          borderRadius: open ? const BorderRadius.vertical(top: Radius.circular(12)) : BorderRadius.circular(12),
          child: InkWell(
            borderRadius: open ? const BorderRadius.vertical(top: Radius.circular(12)) : BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Icon(Icons.record_voice_over_outlined, size: 18, color: colors.chazarah),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (title.isNotEmpty) TextSpan(text: ' · $title'),
                    ]),
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.chazarah),
                  ),
                ),
                Text(context.tr(open ? 'Hide' : 'Show'), style: theme.textTheme.labelMedium?.copyWith(color: colors.chazarah)),
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: colors.chazarah),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// One expanded row of the repetition, tinted and faded.
class _ChazarahBody extends StatelessWidget {
  final Widget child;
  const _ChazarahBody({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = SiddurColors.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 10, end: 6),
      decoration: BoxDecoration(
        color: colors.chazarahFill,
        border: BorderDirectional(start: BorderSide(color: colors.chazarah, width: 3)),
      ),
      child: Opacity(opacity: 0.72, child: child),
    );
  }
}

/// A halachic note shown as one line until tapped.
class _NoteRow extends ConsumerWidget {
  final SegmentItem item;
  final bool open;
  final VoidCallback onTap;
  final Widget? child;
  const _NoteRow({required this.item, required this.open, required this.onTap, this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final hebFont = ref.watch(settingsProvider.select((s) => s.hebrewFont));
    final seg = item.tr ?? item.he;
    final excerpt = seg == null ? '' : stripHtml(seg.segment.html).replaceAll(RegExp(r'\s+'), ' ').trim();
    final rtl = seg?.segment.hebrew ?? false;
    final header = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          Icon(Icons.menu_book_outlined, size: 16, color: colors.note),
          const SizedBox(width: 8),
          Text(context.tr('Halachic note'), style: theme.textTheme.labelMedium?.copyWith(color: colors.note, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(
            child: open
                ? const SizedBox.shrink()
                : Text(excerpt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.note.withValues(alpha: 0.8), fontFamily: rtl ? hebFont : null)),
          ),
          Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: colors.note),
        ]),
      ),
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.note.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        if (child != null) Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 6), child: child),
      ]),
    );
  }
}

/// Kiddush / Kadesh as a single card: the blessings in order, with the
/// parts said only on some nights labelled inline rather than folded away.
class _UnitCard extends ConsumerWidget {
  final SchemaNode node;
  final List<SegmentItem> items;
  final TextLayout layout;
  const _UnitCard({required this.node, required this.items, required this.layout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = ref.watch(settingsProvider);
    // Leading title lines ("הגדה של פסח", "קדש") repeat the heading.
    var start = 0;
    while (start < items.length && items[start].kind == SegmentKind.speaker) {
      start++;
    }
    final body = items.sublist(start);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.wine_bar_outlined, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: SplitRow(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Text(context.term(node.en),
                  style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
              Text(node.he,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontFamily: s.hebrewFont, fontSize: 18, color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
        const Divider(height: 16),
        for (var i = 0; i < body.length; i++)
          if (!isRedundantRubric(body[i], i + 1 < body.length ? body[i + 1] : null, s))
            _SegmentView(item: body[i], layout: layout, compact: true),
      ]),
    );
  }
}
