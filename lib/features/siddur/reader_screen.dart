import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hebcal/hebcal.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/analytics.dart';
import '../../core/l10n.dart';
import '../../core/text_report.dart';
import '../../core/adaptive.dart';
import '../../core/focus_mode.dart';
import '../../core/fonts.dart';
import '../../core/format.dart';
import '../../core/hebrew_text.dart';
import '../../core/html_text.dart';
import '../../core/page_swipe.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/split_row.dart';
import '../../core/theme.dart';
import '../../core/titles.dart';
import '../../core/typeset/typeset.dart';
import 'reader_grouping.dart';
import 'reader_typography.dart';
import 'reading_marks.dart';
import 'prayer_catalog.dart';
import 'reader_jump.dart';
import '../integrations/prayer_links.dart';
import '../integrations/hachama_reader.dart';
import 'package:flutter/services.dart';
import 'reader_settings_sheet.dart';
import 'related_prayers.dart';
import 'siddur_providers.dart';
import 'today_plan.dart';
import 'day_guide_screen.dart';
import 'prayer_insights.dart';

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

class _ReaderScreenState extends ConsumerState<ReaderScreen> with FocusModeReader {
  final _expanded = <String>{};
  final _expandedGroups = <String>{};

  /// Chazarah groups / notes the user toggled away from their default.
  final _toggledChazarah = <String>{};
  final _toggledNotes = <String>{};

  final _selection = GlobalKey<SelectionAreaState>();

  /// Text is selected: sideways drags move its handles, so swiping
  /// doesn't turn the page.
  bool _selected = false;
  String _selectedText = '';

  void _selectionChanged(SelectedContent? c) {
    _selectedText = c?.plainText ?? '';
    final selected = _selectedText.isNotEmpty;
    if (selected != _selected) setState(() => _selected = selected);
  }

  /// Keys of the lines that open a section (see [normalizeOpeningBold]).
  Set<String> _openers = {};

  // The jump bar: the list scrolls by row index, and the row at the top
  // marks the current key point.
  final _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  final _offsetScroll = ScrollOffsetController();
  List<JumpPoint> _jumps = const [];
  int _active = 0;

  /// Scrolling to a chosen key point: the rows passed on the way don't
  /// change the mark.
  bool _jumping = false;

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_track);
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_track);
    super.dispose();
  }

  void _track() {
    if (_jumping) return;
    final visible = _positions.itemPositions.value.where((p) => p.itemTrailingEdge > 0.02);
    if (visible.isEmpty) return;
    final top = visible.map((p) => p.index).reduce((a, b) => a < b ? a : b);
    var active = 0;
    for (final (i, j) in _jumps.indexed) {
      if (j.row != null && j.row! <= top) active = i;
    }
    if (active != _active) setState(() => _active = active);
  }

  void _jump(JumpPoint p) {
    analytics.event('jump_bar', {'point': p.en, 'elsewhere': p.elsewhere != null, 'book': widget.book});
    final ref0 = p.elsewhere;
    if (ref0 != null) {
      context.push(readerPath(ref0.book, ref0.id, standalone: widget.standalone));
      return;
    }
    setState(() => _active = _jumps.indexOf(p));
    _jumping = true;
    _scroll
        .scrollTo(index: p.row!, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic)
        .whenComplete(() => _jumping = false);
  }

  /// Parts of today's service printed elsewhere (read straight through,
  /// the service leaves them out), for the jump bar.
  List<JumpPoint> _elsewhere(SchemaNode? node, int dateAbs) {
    final plan = ref.watch(todayPlanProvider(dateAbs)).valueOrNull;
    if (plan == null || node == null) return const [];
    final at = locateInPlan(plan, widget.book, node);
    if (at.covered.length < 2) return const [];
    final svc = plan.serviceOf(at.covered.first);
    if (svc == null) return const [];
    return [
      for (final e in svc.entries)
        if (e.extra && !at.covered.contains(e))
          JumpPoint(e.addedEn ?? e.node.en, e.addedHe ?? e.node.he, elsewhere: e.ref),
    ];
  }

  Future<void> _explainSelection(SchemaNode? node) async {
    try {
      await _loadSelectionInsight();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Unable to load the explanation. Please try again.'))));
    }
  }

  Future<void> _loadSelectionInsight() async {
    final date = ref.read(readerDaytimeDateProvider);
    final key = (book: widget.book, node: widget.nodeId, expanded: (_expanded.toList()..sort()).join('|'), dateAbs: date.abs());
    final selected = normalizeRubric(_selectedText);
    if (selected.isEmpty) return;
    final root = await ref.read(bookIndexProvider(widget.book).future);
    final versions = await ref.read(versionSelectionProvider(widget.book).future);
    final resolver = await ref.read(resolverProvider(widget.book).future);
    final settings = ref.read(settingsProvider);
    final items = resolver.resolve(root.find(key.node) ?? root, versions,
      (svc) => DayContext.forService(date, svc, il: settings.location.il, minhagim: settings.minhagim),
      options: const ResolveOptions(excluded: ExcludedDisplay.dim, showHebrew: true, showTranslation: true, showNotes: true),
    );
    final matches = <SegmentItem>[];
    for (final item in items) {
      final segments = switch (item) { SegmentItem s => [s], ExcludedGroupItem g => g.items, _ => <SegmentItem>[] };
      for (final segment in segments) {
        if ([segment.he, segment.tr].any((s) => s != null && normalizeRubric(s.segment.html).contains(selected))) { matches.add(segment); }
      }
    }
    if (!mounted) return;
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Select words within a single line to explain it.'))));
      return;
    }
    final match = matches.length == 1 ? matches.single : await showDialog<SegmentItem>(
      context: context, builder: (context) => AlertDialog(
        title: Text(context.tr('Choose the passage')),
        content: SizedBox(width: 520, height: 360, child: ListView(children: [
          for (final item in matches) ListTile(
            title: Text(item.node.en),
            subtitle: Text(item.he?.segment.plain ?? item.tr?.segment.plain ?? '', maxLines: 3, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.pop(context, item),
          ),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('Cancel')))],
      ),
    );
    if (match == null || !mounted) return;
    final service = SiddurResolver.serviceFor(match.node, Service.shacharit);
    final day = ref.read(dayContextProvider((date.abs(), service)));
    final rule = resolver.sectionRuleFor(match.node);
    if (mounted) {
      await showLineInsight(context, match, day, book: widget.book, sectionCondition: rule?.when, sources: [
      for (final list in [versions.hebrew, versions.translation])
        if (versions.pick(list, match.node.path).$1 != null) versions.pick(list, match.node.path).$1!,
    ]);
    }
  }

  void _doubleTap() {
    toggleFocusMode();
    // Double-tap also selects a word; drop it once the gesture is done.
    Timer.run(() {
      final region = _selection.currentState?.selectableRegion;
      region?.clearSelection();
      region?.hideToolbar();
    });
  }

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(readerDaytimeDateProvider);
    final picked = ref.watch(readerDateProvider);
    final key = (book: widget.book, node: widget.nodeId, expanded: (_expanded.toList()..sort()).join('|'), dateAbs: date.abs());
    final items = ref.watch(_resolvedProvider(key));
    final rootAsync = ref.watch(bookIndexProvider(widget.book));
    final node = rootAsync.valueOrNull?.find(widget.nodeId);
    final s = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    final bar = AppBar(
        title: Builder(builder: (context) {
          final heTitle = context.prayerTitleIsHebrew(s);
          final sub = node == null ? null : context.prayerSubtitle(s, node.en, node.he);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(node == null ? context.term(widget.book) : context.prayerTitle(s, node.en, node.he),
                overflow: TextOverflow.ellipsis, style: node != null && heTitle ? TextStyle(fontFamily: s.hebrewFont) : null),
            if (sub != null)
              Text(sub,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(fontFamily: heTitle ? null : s.hebrewFont),
                  textDirection: heTitle ? null : TextDirection.rtl),
          ]);
        }),
        actions: [
          IconButton(tooltip: context.tr("Why today?"), icon: const Icon(Icons.help_outline), onPressed: () => openDayGuide(context, date)),
          IconButton(
            tooltip: context.tr('Copy prayer link'), icon: const Icon(Icons.link),
            onPressed: () async {
              final link = Uri.https('amud.page', '/app/read/${widget.book}', {'node': widget.nodeId});
              await Clipboard.setData(ClipboardData(text: link.toString()));
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Link copied'))));
            },
          ),
          IconButton(
            tooltip: context.tr('Date'),
            icon: Badge(isLabelVisible: picked != null, child: const Icon(Icons.event)),
            onPressed: () => pickReaderDate(context, ref, date),
          ),
          IconButton(
            tooltip: context.tr('Text settings'),
            icon: const Icon(Icons.text_fields),
            onPressed: () => showReaderSettings(context, widget.book),
          ),
        ],
    );

    final loaded = items.valueOrNull;
    final built = loaded == null ? null : _rows(context, loaded, node);
    // Key points of this prayer, in order, then its parts printed
    // elsewhere; shown when there's somewhere to go.
    _jumps = built == null ? const [] : [...built.jumps, ..._elsewhere(node, date.abs())];
    if (_active >= _jumps.length) _active = 0;
    final showJumps = _jumps.length >= 2;
    if (node != null) {
      final he = ref.watch(versionOrderProvider((widget.book, 'he'))).valueOrNull;
      final en = s.showTranslationText ? ref.watch(versionOrderProvider((widget.book, 'en'))).valueOrNull : const <String>[];
      if (he != null && en != null) {
        readingText({
          'book': widget.book,
          'section': node.en,
          'section_id': node.id,
          'hebrew_version': s.showHebrewText ? he.firstOrNull : null,
          'translation_version': en.firstOrNull,
          'layout': s.layout.name,
          'day': ref.watch(dayContextProvider((date.abs(), Service.shacharit))).labels.join(', '),
          'other_date': picked != null,
        });
      }
    }
    final around = node == null ? null : prayerNeighbors(ref, widget.book, node);
    VoidCallback? turnTo(PrayerRef? r, String way) => r == null || _selected
        ? null
        : () {
            analytics.event('page_swipe', {'reader': 'siddur', 'way': way});
            Router.neglect(context, () => context.pushReplacement(readerPath(r.book, r.id, standalone: widget.standalone)));
          };

    return CallbackShortcuts(
      bindings: {
        for (var i = 0; i < 9; i++)
          SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i)): () { if (i < _jumps.length && _scroll.isAttached) _jump(_jumps[i]); },
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _pageOffset(1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _pageOffset(-1),
        const SingleActivator(LogicalKeyboardKey.escape): () { if (focusMode.state) toggleFocusMode(); },
      },
      child: Focus(autofocus: true, child: Scaffold(
      body: Column(children: [
        // Focus mode: the bars slide up out of view; the text keeps clear
        // of the status bar.
        FocusModeBars(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            bar,
            if (showJumps) ReaderJumpBar(points: _jumps, active: _active, onTap: _jump),
            DayBanner(date: date, picked: picked != null),
          ]),
        ),
        Expanded(
          child: FocusModeBody(
            child: DoubleTapListener(
              onDoubleTap: _doubleTap,
              child: PageSwipe(
                onNext: turnTo(around?.next, 'next'),
                onPrevious: turnTo(around?.prev, 'previous'),
                child: items.when(
                  loading: adaptiveProgress,
                  error: (e, st) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
                  data: (_) => _listView(context, built!.rows, node),
                ),
              ),
            ),
          ),
        ),
      ]),
    )),
    );
  }

  void _pageOffset(int direction) {
    if (!_scroll.isAttached) return;
    _offsetScroll.animateScroll(offset: direction * MediaQuery.sizeOf(context).height * 0.8,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  Widget _listView(BuildContext context, List<Widget Function(BuildContext)> rows, SchemaNode? node) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width > 700;
    final s = ref.watch(settingsProvider);
    // Printed pages keep a readable measure: on a wide window the column
    // stays centered rather than running the lines out to the edges.
    final side = TypeScale.of(s).gutter(width, min: wide ? 48 : 16, sideBySide: wide && s.layout == TextLayout.sideBySide);
    return SelectionArea(
      key: _selection,
      onSelectionChanged: _selectionChanged,
      contextMenuBuilder: (context, state) => textReportMenu(context, state,
          selectedText: _selectedText, location: '${widget.book} / ${node?.en ?? widget.nodeId} (${widget.nodeId})',
          onExplain: () => _explainSelection(node)),
      child: ScrollablePositionedList.builder(
        itemScrollController: _scroll,
        itemPositionsListener: _positions,
        scrollOffsetController: _offsetScroll,
        padding: EdgeInsets.fromLTRB(side, 8, side, 96),
        itemCount: rows.length + 1,
        itemBuilder: (c, i) => i == rows.length
            ? (node == null ? const SizedBox.shrink() : RelatedPrayers(book: widget.book, node: node, standalone: widget.standalone))
            : rows[i](c),
      ),
    );
  }

  /// The list's rows, and the key points among its headings (see
  /// [keyPoints]) with the row each starts at.
  ({List<Widget Function(BuildContext)> rows, List<JumpPoint> jumps}) _rows(BuildContext context, List<RenderItem> list, SchemaNode? node) {
    final s = ref.watch(settingsProvider);
    final wide = MediaQuery.sizeOf(context).width > 700;
    final layout = s.layout == TextLayout.sideBySide && !wide ? TextLayout.interleaved : s.layout;
    final rows = <Widget Function(BuildContext)>[];
    final jumps = <JumpPoint>[];
    final seen = <String>{};
    if (node != null && list.every((it) => it is HeadingItem)) {
      rows.add((c) => _CollapsedTile(
            icon: Icons.visibility_off_outlined,
            title: context.tr('Not said today'),
            subtitle: context.tr('Tap to show it anyway'),
            he: context.titleFormsFor(ref.read(settingsProvider)).he ? node.he : null,
            onTap: () => setState(() => _expanded.add(node.id)),
          ));
    }
    // The first prayer line of each section starts in bold, whichever
    // version it comes from.
    _openers = {};
    final started = <String>{};
    for (final it in list) {
      final segs = switch (it) {
        SegmentItem s => [s],
        ExcludedGroupItem g => g.items,
        _ => const <SegmentItem>[],
      };
      for (final si in segs) {
        // A verse before the prayer proper ("אדני שפתי תפתח") leaves the
        // opening to the line after it.
        if (si.kind == SegmentKind.prayer && !si.excluded && !isPreamble(si) && started.add(si.node.id)) _openers.add(si.key);
      }
    }
    // Rubrics before a centered line are centered with it ("center:"
    // keys), past any further rubrics in between.
    final ts = TypeScale.of(s);
    final flat = [
      for (final it in list)
        ...switch (it) {
          SegmentItem x => [x],
          ExcludedGroupItem g => g.items,
          _ => const <SegmentItem>[],
        },
    ];
    bool rubric(SegmentItem x) => x.kind == SegmentKind.instruction || x.kind == SegmentKind.speaker;
    for (var k = 0; k < flat.length; k++) {
      if (!rubric(flat[k])) continue;
      var n = k + 1;
      while (n < flat.length && rubric(flat[n])) {
        n++;
      }
      if (n < flat.length && flat[n].kind == SegmentKind.prayer && ts.align(paragraphRole(flat[n], opening: false)) == ParagraphAlign.center) {
        _openers.add('center:${flat[k].key}');
      }
    }
    // A responsive "oreo" (Yotzer's Kedushah: קדוש… / והאופנים… / ברוך
    // כבוד…) is centered as a whole, the line between the verses too.
    if (ts.print) {
      for (var k = 0; k < list.length; k++) {
        for (final x in _togetherRun(list, k) ?? const <SegmentItem>[]) {
          _openers.add('center:${x.key}');
        }
      }
    }
    // Who says a line is shown where it changes ("role:" keys).
    String? lastRole;
    for (final it in list) {
      if (it is! SegmentItem || it.kind != SegmentKind.prayer || it.excluded) continue;
      if (it.role != lastRole && it.role != null) _openers.add('role:${it.key}');
      lastRole = it.role;
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
        rows.add((c) => _UnitCard(node: unit, items: segs, layout: layout, openers: _openers));
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
              context.prayerTitle(s, (g is HeadingItem ? g.node : (g as CollapsedSectionItem).node).en,
                  (g is HeadingItem ? g.node : (g as CollapsedSectionItem).node).he),
        ];
        if (titles.isEmpty && group.any((g) => g is SegmentItem && isChazarahSegment(g))) titles.add(context.tr('Modim DeRabbanan'));
        // Birkas Kohanim printed inside the Amidah, or not said today.
        if (titles.isEmpty &&
            group.any((g) => g is SegmentItem && g.chazarah || g is ExcludedGroupItem && g.items.any((i) => i.chazarah))) {
          titles.add(context.prayerTitle(s, 'Birkat Kohanim', 'ברכת כהנים'));
        }
        rows.add((c) => _ChazarahHeader(
              title: titles.toSet().join(' · '),
              open: open,
              gap: s.typesetting ? TypeScale.of(s).controlGap : 6,
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
      // A sub-section titled like the section it's in (Birchas Hamazon
      // inside Birchas Hamazon) would repeat the heading right above it.
      if (it is HeadingItem && i > 0 && _repeatsParent(it, list[i - 1])) {
        i++;
        continue;
      }
      // A heading (or an addition for today) that's one of the service's
      // key points, the first of its kind.
      final title = switch (it) {
        HeadingItem h when h.level > 0 || !h.node.isLeaf => h.node.en,
        InsertedSectionItem ins => ins.labelEn,
        _ => null,
      };
      final point = title == null ? null : keyPointFor(title);
      if (point != null && seen.add(point.$1)) jumps.add(JumpPoint(point.$1, point.$2, row: rows.length));
      rows.addAll(_rowsFor(context, it, layout));
      i++;
    }
    return (rows: rows, jumps: jumps);
  }

  /// The row(s) for one render item, with expanded groups and collapsible
  /// notes.
  List<Widget Function(BuildContext)> _rowsFor(BuildContext context, RenderItem it, TextLayout layout) {
    final s = ref.read(settingsProvider);
    switch (it) {
      case ExcludedGroupItem g when _expandedGroups.contains(g.key):
        return [for (final si in g.items) (c) => _SegmentView(item: si, layout: layout, opening: _openers.contains(si.key), roleStart: _openers.contains('role:${si.key}'), centered: _openers.contains('center:${si.key}'))];
      case SegmentItem si when si.kind == SegmentKind.note && s.collapseNotes:
        final open = _toggledNotes.contains(si.key);
        void toggle() => setState(() => open ? _toggledNotes.remove(si.key) : _toggledNotes.add(si.key));
        return [(c) => _NoteRow(item: si, open: open, onTap: toggle, child: open ? _SegmentView(item: si, layout: layout, opening: _openers.contains(si.key), roleStart: _openers.contains('role:${si.key}'), centered: _openers.contains('center:${si.key}')) : null)];
      default:
        return [(c) => _item(c, it, layout)];
    }
  }

  static String _plain(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static bool _repeatsParent(HeadingItem h, RenderItem prev) =>
      prev is HeadingItem &&
      prev.level < h.level &&
      h.labelEn == null &&
      _plain(h.node.en).isNotEmpty &&
      _plain(h.node.en) == _plain(prev.node.en);

  /// The lines from [start] to the last of a run said "together with the
  /// chazzan", with whatever sits between (the "oreo": קדוש… / והאופנים… /
  /// ברוך כבוד…); null unless there are at least two such lines.
  static List<SegmentItem>? _togetherRun(List<RenderItem> list, int start) {
    bool plain(RenderItem it) =>
        it is SegmentItem && it.kind == SegmentKind.prayer && !it.excluded && it.applicability == Applicability.always;
    final first = list[start];
    if (!plain(first) || (first as SegmentItem).role != 'together') return null;
    var last = start;
    var together = 1;
    for (var j = start + 1; j < list.length; j++) {
      final it = list[j];
      if (!plain(it) || (it as SegmentItem).node != first.node) break;
      if (it.role == 'together') {
        last = j;
        together++;
      } else if (it.role != null) {
        break;
      }
    }
    if (together < 2) return null;
    return [for (var j = start; j <= last; j++) list[j] as SegmentItem];
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
        SegmentItem s => isChazarahNode(s.node) || s.chazarah || isChazarahSegment(s),
        ExcludedGroupItem g => g.items.every((i) => isChazarahNode(i.node) || i.chazarah),
        _ => false,
      };

  Widget _item(BuildContext context, RenderItem it, TextLayout layout) {
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final s = ref.read(settingsProvider);
    switch (it) {
      case HeadingItem h:
        if (h.level == 0 && h.node.isLeaf) return const SizedBox(height: 4);
        if (s.typesetting) return _PrintHeading(h);
        final size = (24 - h.level * 3).clamp(15, 24).toDouble() * s.textScale;
        return Padding(
          padding: EdgeInsets.only(top: h.level == 0 ? 4 : 20, bottom: 6),
          child: Builder(builder: (context) {
            final f = context.titleFormsFor(s);
            // An untitled Hebrew node repeats the English title.
            final showHe = f.he && (h.node.he != h.node.en || !f.en);
            return SplitRow(gap: 12, children: [
              f.en
                  ? Text(context.term(h.node.en),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontSize: size * (showHe ? 0.72 : 0.85), color: theme.colorScheme.primary, fontWeight: FontWeight.w600))
                  : const SizedBox.shrink(),
              if (h.applicability == Applicability.today && s.highlightToday && h.labelEn != null)
                _TodayChip(conditionLabel(context, s, h.labelEn, h.labelHe)),
              if (showHe)
                Text(h.node.he,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontFamily: s.hebrewFont, fontSize: size, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
            ]);
          }),
        );
      case InsertedSectionItem ins when s.typesetting:
        // Something the page tells the reader, not a control: set as a
        // rubric between rules.
        final ts = TypeScale.of(s);
        return Padding(
          padding: EdgeInsets.only(top: ts.sectionGap * 0.6, bottom: ts.line * 0.15),
          child: RuledLabel(
            color: colors.todayBar,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(context.tr('Added today: {label}', {'label': context.prayerTitle(s, ins.labelEn, ins.labelHe)}),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(color: colors.todayBar, letterSpacing: 0.6, fontWeight: FontWeight.w700)),
                if (!context.prayerTitleIsHebrew(s) && context.prayerSubtitle(s, ins.labelEn, ins.labelHe) != null)
                  Text(ins.labelHe,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: s.hebrewFont, fontSize: 16 * s.textScale, color: colors.todayBar)),
            ]),
          ),
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
                Text(context.tr('Added today: {label}', {'label': context.prayerTitle(s, ins.labelEn, ins.labelHe)}), style: theme.textTheme.labelLarge),
                if (!context.prayerTitleIsHebrew(s) && context.prayerSubtitle(s, ins.labelEn, ins.labelHe) != null)
                  Text(ins.labelHe, textDirection: TextDirection.rtl, style: TextStyle(fontFamily: s.hebrewFont, fontSize: 16)),
              ]),
            ),
          ]),
        );
      case CollapsedSectionItem c:
        return _CollapsedTile(
          icon: Icons.unfold_more,
          title: context.tr('{title} — not said today', {'title': context.prayerTitle(s, c.node.en, c.node.he)}),
          subtitle: conditionLabel(context, s, c.labelEn, c.labelHe),
          he: context.prayerTitleIsHebrew(s) ? null : context.prayerSubtitle(s, c.node.en, c.node.he),
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
        return _SegmentView(item: si, layout: layout, opening: _openers.contains(si.key), roleStart: _openers.contains('role:${si.key}'), centered: _openers.contains('center:${si.key}'));
    }
  }
}

/// Lets the user read the siddur as of another day.
Future<void> pickReaderDate(BuildContext context, WidgetRef ref, HDate current) async {
  final picked = await showDatePicker(
    context: context,
    initialDate: current.greg(),
    firstDate: DateTime(1900),
    lastDate: DateTime(2239),
    helpText: context.tr('Pray as of…'),
  );
  if (picked == null) return;
  ref.read(readerDateProvider.notifier).state = HDate.fromDate(picked);
}

String readerPath(String book, String nodeId, {bool standalone = false}) => standalone
    ? '/read/${Uri.encodeComponent(book)}?node=${Uri.encodeQueryComponent(nodeId)}'
    : '/siddur/book/${Uri.encodeComponent(book)}/read?node=${Uri.encodeQueryComponent(nodeId)}';

/// A section of the default siddur by shortcut key (`shacharit`, `omer`,
/// …), opened standalone from Home.
class SectionReaderScreen extends ConsumerWidget {
  final String section;
  final String? nusach;
  const SectionReaderScreen({super.key, required this.section, this.nusach});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(readerDaytimeDateProvider).abs();
    final key = normalizePrayer(section);
    final found = nusach == null ? ref.watch(sectionRefProvider((key, date))) : ref.watch(nusachSectionRefProvider((nusach!, key, date)));
    if (found.hasError) return Scaffold(appBar: AppBar(), body: Center(child: Text(context.tr('Unable to open this prayer'))));
    if (!found.hasValue) return Scaffold(appBar: AppBar(), body: adaptiveProgress());
    final r = found.value;
    if (r == null && key == 'birkatHaChama') return const HachamaReader();
    if (r == null) return Scaffold(appBar: AppBar(), body: Center(child: Text(context.tr('Not found in this siddur'))));
    return ReaderScreen(key: ValueKey('${r.book}|${r.id}'), book: r.book, nodeId: r.id, standalone: true);
  }
}

/// The reader's date with its special days, and a way back to today
/// when another date is picked.
class DayBanner extends ConsumerWidget {
  final HDate date;
  final bool picked;
  const DayBanner({super.key, required this.date, required this.picked});

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

/// "If: …": a line said only in some circumstance the reader knows.
class _IfChip extends StatelessWidget {
  final String label;
  const _IfChip(this.label);

  @override
  Widget build(BuildContext context) {
    final colors = SiddurColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
          border: Border.all(color: colors.marker.withValues(alpha: 0.6)), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.help_outline, size: 11, color: colors.marker),
        const SizedBox(width: 3),
        Flexible(
          child: Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(height: 1.2, color: colors.marker),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ]),
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

/// A heading set as in print: the Hebrew title centered, the English
/// beneath it in tracked capitals, a section ornament above a new section.
class _PrintHeading extends ConsumerWidget {
  final HeadingItem h;
  const _PrintHeading(this.h);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final ts = TypeScale.of(s);
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final size = (24 - h.level * 3).clamp(15, 24).toDouble() * s.textScale;
    final f = context.titleFormsFor(s);
    // An untitled Hebrew node repeats the English title.
    final showHe = f.he && (h.node.he != h.node.en || !f.en);
    final en = context.term(h.node.en);
    return Padding(
      padding: EdgeInsets.only(top: h.level == 0 ? 4 : ts.sectionGap * (h.level == 1 ? 0.5 : 0.35), bottom: ts.line * 0.22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (h.level == 1) SectionOrnament(height: ts.line * 0.75, color: theme.colorScheme.outline),
        if (showHe)
          Text(h.node.he,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: s.hebrewFont, fontSize: size * (h.level == 0 ? 1.1 : 1), height: 1.3, fontWeight: FontWeight.w700, color: color)),
        if (f.en)
          Text(showHe ? en.toUpperCase() : en,
              textAlign: TextAlign.center,
              style: showHe
                  ? theme.textTheme.labelMedium?.copyWith(
                      fontSize: (size * 0.5).clamp(10.5, 16), letterSpacing: 1.6, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.75))
                  : theme.textTheme.titleMedium?.copyWith(fontSize: size * 0.85, fontWeight: FontWeight.w600, color: color)),
        if (h.applicability == Applicability.today && s.highlightToday && h.labelEn != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(child: _TodayChip(conditionLabel(context, s, h.labelEn, h.labelHe))),
          ),
        if (h.level >= 2) Center(child: Container(margin: const EdgeInsets.only(top: 6), width: 28, height: 0.8, color: color.withValues(alpha: 0.4))),
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
    final s = ref.watch(settingsProvider);
    final tone = theme.colorScheme.outline;
    // Hidden text: a dashed edge, set off from the words around it.
    return ReaderControl(
      icon: icon,
      tone: tone,
      dashed: true,
      gap: TypeScale.of(s).controlGap,
      onTap: onTap,
      title: SplitRow(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title),
          if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: tone.withValues(alpha: 0.85))),
        ]),
        if (he != null) Text(he!, textDirection: TextDirection.rtl, style: TextStyle(fontFamily: s.hebrewFont, color: tone)),
      ]),
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

  /// The first prayer line of its section: starts in bold.
  final bool opening;

  /// Who says it changes here: show the role.
  final bool roleStart;

  /// Centered with the lines around it: a rubric introducing a centered
  /// line (Barchu's "the chazzan says"), or the middle of a responsive run.
  final bool centered;
  const _SegmentView(
      {required this.item,
      required this.layout,
      this.compact = false,
      this.opening = false,
      this.roleStart = false,
      this.centered = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final ts = TypeScale.of(s);
    // What the line is decides its size, leading, spacing and alignment.
    final role = paragraphRole(item, opening: opening);
    // Only the words said get the "today" treatment; a note about today
    // reads as a note.
    final today = item.applicability == Applicability.today && s.highlightToday && item.kind == SegmentKind.prayer;
    final excluded = item.excluded;
    // One of several alternative lines not said today: crossed out beside
    // the one that is, rather than labelled.
    final strike = excluded && item.option;

    TextStyle heBase = TextStyle(
        fontFamily: s.hebrewFont, fontSize: ts.size(role, hebrew: true), height: ts.leading(role, hebrew: true), color: theme.colorScheme.onSurface);
    TextStyle enBase = TextStyle(
        fontFamily: s.latinFont, fontSize: ts.size(role, hebrew: false), height: ts.leading(role, hebrew: false), color: theme.colorScheme.onSurface);
    if (item.kind != SegmentKind.prayer) {
      heBase = heBase.copyWith(color: colors.instruction);
      enBase = enBase.copyWith(fontStyle: FontStyle.italic, color: colors.instruction);
    }
    if (ts.print && (role == ParagraphRole.keystone || role == ParagraphRole.proclamation)) {
      heBase = heBase.copyWith(fontWeight: FontWeight.w600);
      enBase = enBase.copyWith(fontWeight: FontWeight.w600);
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

    // Instructions shown in English alone sit on the right, with the
    // Hebrew column they belong to.
    final rightAligned = item.he == null && item.tr != null && item.kind != SegmentKind.prayer;

    Widget text(ResolvedSegment seg, TextStyle base, bool rtl, {InlineSpan? lead}) {
      String marks(String h) => seg.segment.hebrew ? hebrewMarks(h, teamim: s.showTeamim, nikud: s.showNikud) : h;
      if (seg.segment.hebrew) {
        final all = seg.runs.map((r) => marks(r.html)).join();
        final teamim = hasTeamim(all);
        base = base.copyWith(
            fontFamily: hebrewFamilyFor(s.hebrewFont, teamim: teamim, nikud: hasNikud(all)),
            height: ts.leading(role, hebrew: true, marks: teamim));
      }
      final html = SefariaHtml(base, instructionStyle: TextStyle(color: colors.instruction, fontStyle: FontStyle.italic), onFootnote: footnote);
      // A change of speaker starts a new paragraph: the congregation's
      // "Amen" sits on its own line, on the far side, marked "Cong.". An
      // instruction ("ועונים:") goes with the words after it.
      final runs = seg.runs;
      final roles = List<String?>.filled(runs.length, item.role);
      String? next = item.role;
      for (var i = runs.length - 1; i >= 0; i--) {
        if (!runs[i].marker) next = runs[i].role ?? item.role;
        roles[i] = next;
      }
      // (who says it, its spans, whether it starts a paragraph found inside
      // the line, like Hallel's "מה אשיב").
      final paragraphs = <(String?, List<InlineSpan>, bool)>[(roles.isEmpty ? item.role : roles.first, [?lead], false)];
      var inOptions = false;
      for (final (i, r) in runs.indexed) {
        if (i > 0 && roles[i] != roles[i - 1]) {
          paragraphs.add((roles[i], [], false));
          inOptions = false;
          if (roles[i] != item.role && roles[i] != null) {
            paragraphs.last.$2.add(TextSpan(
                // Isolated, so "Cong." keeps its full stop inside Hebrew text.
                text: '\u2068${readingRoleShort(context, roles[i])}\u2069 ',
                style: base.copyWith(fontSize: (base.fontSize ?? 16) * 0.55, color: colors.marker, fontWeight: FontWeight.w600)));
          }
        }
        final spans = paragraphs.last.$2;
        var h = r.html;
        if (i == 0 && !r.marker && item.kind == SegmentKind.prayer) {
          h = normalizeOpeningBold(h, opening: opening, addIfMissing: seg.segment.hebrew);
        }
        if (seg.segment.hebrew && !r.marker && item.kind == SegmentKind.prayer) h = verseNumbers(h);
        // A phrase that depends on a personal circumstance, where the
        // siddur's own instruction doesn't already say so.
        if (!r.marker &&
            r.applicability == Applicability.unknown &&
            r.labelEn != null &&
            (i == 0 || (!runs[i - 1].marker && runs[i - 1].labelEn != r.labelEn))) {
          spans.add(TextSpan(
              text: '\u2068${conditionLabel(context, s, r.labelEn, r.labelHe)}\u2069 ',
              style: base.copyWith(fontSize: (base.fontSize ?? 16) * 0.55, color: colors.marker, fontWeight: FontWeight.w600)));
        }
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
        // A psalm printed whole breaks into the paragraphs a siddur prints.
        final pieces = seg.segment.hebrew && !r.marker && item.kind == SegmentKind.prayer ? splitParagraphs(h) : [h];
        spans.addAll(html.parse(marks(pieces.first), style: st));
        for (final piece in pieces.skip(1)) {
          final (number, words) = splitLeadingVerse(piece);
          paragraphs.add((roles[i], [
            ...html.parse(marks(number), style: st),
            ...enlargeOpening(html.parse(marks(words), style: st), ts.openingWord, lineHeight: base.height ?? 1.65),
          ], true));
        }
      }
      final dir = rtl ? TextDirection.rtl : TextDirection.ltr;
      Widget paragraph((String?, List<InlineSpan>, bool) p, {required bool first}) {
        var spans = p.$2;
        // A section's first words, set large as in a printed siddur.
        if (first && rtl && role == ParagraphRole.opening) spans = enlargeOpening(spans, ts.openingWord, lineHeight: base.height ?? 1.65);
        final align = centered && ts.print
            ? ParagraphAlign.center
            : isResponse(p.$1) && p.$1 != item.role
                ? ParagraphAlign.end
                : (rightAligned && !rtl ? ParagraphAlign.end : ts.align(role));
        final w = TypesetParagraph(text: TextSpan(children: spans), textDirection: dir, em: base.fontSize ?? 16, align: align, balance: ts.print);
        return p.$3 && !first ? Padding(padding: EdgeInsets.only(top: ts.print ? ts.space(ParagraphRole.opening).top : 4), child: w) : w;
      }
      final shown = [for (final p in paragraphs) if (p.$2.isNotEmpty) p];
      if (shown.length <= 1) return paragraph(shown.isEmpty ? paragraphs.first : shown.single, first: true);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, p) in shown.indexed) paragraph(p, first: i == 0),
      ]);
    }

    final he = item.he;
    final tr = item.tr;
    Widget body;
    // The resolver already applied the prayer-text and notes language choices.
    // "Said only on…" labels sit inline at the start of the text instead
    // of on a line of their own.
    InlineSpan? lead;
    // A personal circumstance ("If: Ten or more ate together"): said or not
    // is the reader's call, so it's labelled rather than judged.
    final ifLine = item.applicability == Applicability.unknown && item.labelEn != null;
    if (ifLine) {
      lead = WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: _IfChip(conditionLabel(context, s, item.labelEn, item.labelHe)),
        ),
      );
    } else if (today || (excluded && !strike && item.labelEn != null)) {
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
        if (heW != null && trW != null) SizedBox(height: ts.print ? ts.line * 0.12 : 4),
        ?trW,
      ]);
    }
    if (heW == null && trW == null) return const SizedBox.shrink();

    final reading = item.kind == SegmentKind.prayer && !excluded
        ? readingLabels(context, item, withRole: roleStart, undertone: isUndertone(item))
        : const <String>[];
    final content = reading.isEmpty
        ? body
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(reading.join(' · '),
                // Over a centered line, the label is centered too.
                textAlign: centered && ts.print || ts.align(role) == ParagraphAlign.center ? TextAlign.center : null,
                style: theme.textTheme.labelSmall?.copyWith(color: colors.marker, fontWeight: FontWeight.w600),
                textDirection: item.he != null && context.uiLanguage != UiLanguage.en ? TextDirection.rtl : null),
            const SizedBox(height: 2),
            body,
          ]);
    final space = ts.space(role, compact: compact);
    if (!today) return Padding(padding: space, child: content);
    // The bar is laid over the fill rather than measured beside it: the
    // paragraphs size themselves from their width (see TypesetParagraph),
    // which an intrinsic-height row can't ask of them.
    return Container(
      margin: ts.print ? space : EdgeInsets.symmetric(vertical: compact ? 2 : 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: colors.todayFill, borderRadius: BorderRadius.circular(10)),
      child: Stack(children: [
        Padding(padding: const EdgeInsetsDirectional.fromSTEB(10, 4, 14, 4), child: content),
        PositionedDirectional(top: 0, bottom: 0, end: 0, width: 4, child: ColoredBox(color: colors.todayBar)),
      ]),
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
  final double gap;
  const _ChazarahHeader({required this.title, required this.open, required this.onTap, this.gap = 6});

  @override
  Widget build(BuildContext context) {
    final colors = SiddurColors.of(context);
    final label = context.term('Chazarat HaShatz');
    return Opacity(
      opacity: open ? 1 : 0.8,
      child: ReaderControl(
        icon: Icons.record_voice_over_outlined,
        tone: colors.chazarah,
        open: open,
        attachedBelow: open,
        gap: gap,
        onTap: onTap,
        title: Text.rich(TextSpan(children: [
          TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (title.isNotEmpty) TextSpan(text: ' · $title'),
        ])),
        trailing: Text(context.tr(open ? 'Hide' : 'Show')),
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
    final s = ref.watch(settingsProvider);
    final gap = TypeScale.of(s).controlGap;
    final seg = item.tr ?? item.he;
    final excerpt = seg == null ? '' : stripHtml(seg.segment.html).replaceAll(RegExp(r'\s+'), ' ').trim();
    final rtl = seg?.segment.hebrew ?? false;
    final header = ReaderControl(
      icon: Icons.menu_book_outlined,
      tone: colors.note,
      open: open,
      attachedBelow: child != null,
      gap: gap,
      onTap: onTap,
      title: Text(context.tr('Halachic note'), style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: open
          ? null
          : Text(excerpt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              style: TextStyle(fontFamily: rtl ? s.hebrewFont : null)),
    );
    if (child == null) return header;
    // The note hangs from its control, inside the same tinted edge.
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        Container(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
          decoration: BoxDecoration(
            color: colors.note.withValues(alpha: 0.04),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
            border: Border.all(color: colors.note.withValues(alpha: 0.35)),
          ),
          child: DefaultTextStyle.merge(style: theme.textTheme.bodyMedium, child: child!),
        ),
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
  final Set<String> openers;
  const _UnitCard({required this.node, required this.items, required this.layout, required this.openers});

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
            child: PrayerTitleText(node.en, node.he,
                crossAxisAlignment: CrossAxisAlignment.center,
                hebrewAtEnd: true,
                enStyle: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700),
                heStyle: TextStyle(fontSize: 18, color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
          ),
        ]),
        const Divider(height: 16),
        for (var i = 0; i < body.length; i++)
          if (!isRedundantRubric(body[i], i + 1 < body.length ? body[i + 1] : null, s))
            _SegmentView(item: body[i], layout: layout, compact: true, opening: openers.contains(body[i].key), roleStart: openers.contains('role:${body[i].key}'), centered: openers.contains('center:${body[i].key}')),
      ]),
    );
  }
}
