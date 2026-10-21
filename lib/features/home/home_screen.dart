import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/search.dart';
import '../search/search_sources.dart';
import '../../core/adaptive.dart';
import '../setup/whats_new.dart';
import '../update/update_screen.dart';
import 'card_registry.dart';
import 'cards/card_frame.dart';
import 'today.dart';

final _editingProvider = StateProvider<bool>((ref) => false);

/// Home Assistant–style dashboard of configurable cards.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editing = ref.watch(_editingProvider);
    final cards = ref.watch(dashboardProvider);
    final registry = ref.watch(cardRegistryProvider);
    final theme = Theme.of(context);
    final query = SearchQuery(ref.watch(pageSearchProvider('home')));

    // No app bar: the date card already shows the date, and the space goes
    // to the cards. Editing is at the bottom of the dashboard.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: theme.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        floatingActionButton: editing
            ? FloatingActionButton.extended(
                onPressed: () => ref.read(_editingProvider.notifier).state = false,
                icon: const Icon(Icons.check),
                label: Text(context.tr('Done')),
              )
            : null,
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            // Several new features at once make a tall banner: it scrolls
            // within at most half the screen rather than pushing Home off it.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
              child: const SingleChildScrollView(child: Column(children: [UpdateBanner(), WhatsNewBanner()])),
            ),
            // Searches everything: prayers, zmanim, Torah, pages, settings.
            if (!editing)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: PageSearchBar(page: 'home', hint: context.tr('Search prayers, zmanim, Torah…')),
                ),
              ),
            Expanded(
              child: editing || query.isEmpty
                  ? _Grid(cards: cards, registry: registry, editing: editing)
                  : SingleChildScrollView(
                      padding: pagePadding(context, const EdgeInsets.only(bottom: 24)),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: GlobalSearchResults(query: query),
                        ),
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Grid extends ConsumerWidget {
  final List<CardConfig> cards;
  final CardRegistry registry;

  /// Editing shows the same cards, hidden ones too, each with its
  /// controls under it; tapping one opens its settings with a live preview.
  final bool editing;
  const _Grid({required this.cards, required this.registry, this.editing = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 12.0;
      final width = c.maxWidth;
      // 2 columns on phones, 4 on tablets, 6 on wide desktop/web; 1 on
      // phones too narrow for two compact cards side by side at this text
      // size (360dp Samsungs with larger text or Screen zoom), where times
      // and words broke mid-way.
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final cols = width >= 1400 ? 6 : (width >= 840 ? 4 : ((width - 32 - gap) / 2 >= 150 * scale ? 2 : 1));
      final pad = width > 1400 ? (width - 1400) / 2 + 16 : 16.0;
      final colW = (width - pad * 2 - gap * (cols - 1)) / cols;
      double widthOf(int span) => colW * _spanOf(span, cols) + gap * (_spanOf(span, cols) - 1);
      return RefreshIndicator.adaptive(
        onRefresh: () async => ref.invalidate(todaySnapshotProvider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: pagePadding(context, EdgeInsets.fromLTRB(pad, 12, pad, editing ? 96 : 24)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (editing)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(context.tr('Edit dashboard'), style: Theme.of(context).textTheme.titleLarge),
              ),
            for (final (i, row) in _rows(ref, cols).indexed)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
                child: _EqualHeightRow(gap: gap, children: [
                  for (final card in row)
                    SizedBox(
                      width: widthOf(card.span),
                      child: editing
                          ? _EditableCard(card: card, cards: cards, registry: registry, cols: cols, widthOf: widthOf)
                          : _buildCard(context, ref, card),
                    ),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Center(
                child: editing
                    ? Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                        FilledButton.tonalIcon(
                          onPressed: () => _addCard(context, ref, widthOf),
                          icon: const Icon(Icons.add),
                          label: Text(context.tr('Add card')),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            if (await showAdaptiveConfirm(context,
                                title: context.tr('Reset dashboard?'), message: context.tr('Restore the default cards.'))) {
                              ref.read(dashboardProvider.notifier).reset();
                            }
                          },
                          icon: const Icon(Icons.restart_alt),
                          label: Text(context.tr('Reset layout')),
                        ),
                      ])
                    : TextButton.icon(
                        onPressed: () => ref.read(_editingProvider.notifier).state = true,
                        icon: const Icon(Icons.dashboard_customize_outlined),
                        label: Text(context.tr('Edit dashboard')),
                      ),
              ),
            ),
          ]),
        ),
      );
    });
  }

  /// Cards packed into rows of at most [cols] columns, in order: the
  /// visible ones, or all of them while editing.
  List<List<CardConfig>> _rows(WidgetRef ref, int cols) {
    final rows = <List<CardConfig>>[];
    var used = cols;
    for (final card in cards) {
      if (!editing && !(registry[card.type]?.visible?.call(ref, card) ?? true)) continue;
      final span = _spanOf(card.span, cols);
      if (used + span > cols) {
        rows.add([]);
        used = 0;
      }
      rows.last.add(card);
      used += span;
    }
    return rows;
  }

  Widget _buildCard(BuildContext context, WidgetRef ref, CardConfig card) => _cardOf(context, ref, registry, card);

  Future<void> _addCard(BuildContext context, WidgetRef ref, double Function(int span) widthOf) async {
    final t = await showModalBottomSheet<CardType>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(context.tr('Add a card'), style: Theme.of(ctx).textTheme.titleLarge),
            ),
            for (final t in registry.all)
              ListTile(
                leading: CircleAvatar(child: Icon(t.icon)),
                title: Text(context.tr(t.title)),
                subtitle: _ShownWhen(
                    text: context.tr(t.description),
                    when: t.shownWhen?.call(CardConfig(id: '', type: t.type, settings: t.defaults))),
                onTap: () => Navigator.pop(ctx, t),
              ),
          ]),
        ),
      ),
    );
    if (t == null) return;
    final card = CardConfig(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: t.type,
      span: t.defaultSpan,
      settings: Map.of(t.defaults),
    );
    ref.read(dashboardProvider.notifier).add(card);
    // Straight to its settings, so a new card is set up while looking at it.
    if (t.editor != null && context.mounted) await _configure(context, ref, t, card, widthOf);
  }
}

int _spanOf(int span, int cols) => (span >= 2 ? (cols == 2 ? 2 : span.clamp(1, cols)) : 1);

Widget _cardOf(BuildContext context, WidgetRef ref, CardRegistry registry, CardConfig card) {
  final t = registry[card.type];
  if (t == null) return CardFrame(title: 'Unknown card', child: Text(card.type));
  return t.build(context, ref, card);
}

/// A card as it shows on the dashboard, with its controls under it. Its
/// own buttons don't work while editing; tapping it opens its settings.
class _EditableCard extends ConsumerWidget {
  final CardConfig card;
  final List<CardConfig> cards;
  final CardRegistry registry;
  final int cols;
  final double Function(int span) widthOf;
  const _EditableCard({required this.card, required this.cards, required this.registry, required this.cols, required this.widthOf});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(dashboardProvider.notifier);
    final theme = Theme.of(context);
    final t = registry[card.type];
    final i = cards.indexWhere((c) => c.id == card.id);
    final hidden = !(t?.visible?.call(ref, card) ?? true);
    final when = t?.shownWhen?.call(card);
    final configure = t == null ? null : () => _configure(context, ref, t, card, widthOf);
    // Reading order is left to right only with more than one column.
    final across = cols > 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: configure,
            child: Opacity(
              opacity: hidden ? 0.5 : 1,
              child: AbsorbPointer(child: _cardOf(context, ref, registry, card)),
            ),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (when != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: _ShownWhen(when: when, hiddenNow: hidden),
              ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: context.tr('Move earlier'),
                  icon: Icon(across ? Icons.arrow_back : Icons.arrow_upward),
                  onPressed: i > 0 ? () => notifier.reorder(i, i - 1) : null,
                ),
                IconButton(
                  tooltip: context.tr('Move later'),
                  icon: Icon(across ? Icons.arrow_forward : Icons.arrow_downward),
                  onPressed: i < cards.length - 1 ? () => notifier.reorder(i, i + 2) : null,
                ),
                if (configure != null)
                  IconButton(tooltip: context.tr('Configure'), icon: const Icon(Icons.tune), onPressed: configure),
                IconButton(
                  tooltip: context.tr('Remove'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => notifier.remove(card.id),
                ),
              ]),
            ),
          ]),
        ],
      ),
    );
  }
}

/// A card's settings, under a live preview of the card as they'd leave it,
/// at the width it would have on the dashboard.
Future<void> _configure(
    BuildContext context, WidgetRef ref, CardType t, CardConfig c, double Function(int span) widthOf) async {
  var draft = c;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
            // The preview stays in view above the settings, and Save
            // below them; the settings scroll between.
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(context.tr('Configure {card}', {'card': context.tr(t.title)}), style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (ctx, box) => Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ConstrainedBox(
                      // A tall card (the calendar) scrolls rather than
                      // pushing its settings off the sheet.
                      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.35),
                      child: SingleChildScrollView(
                        child: SizedBox(
                          width: widthOf(draft.span).clamp(0, box.maxWidth).toDouble(),
                          child: AbsorbPointer(child: t.build(ctx, ref, draft)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SegmentedButton<int>(
                        segments: [
                          ButtonSegment(value: 1, icon: const Icon(Icons.grid_view), label: Text(context.tr('Compact'))),
                          ButtonSegment(value: 2, icon: const Icon(Icons.view_agenda_outlined), label: Text(context.tr('Wide'))),
                        ],
                        selected: {draft.span >= 2 ? 2 : 1},
                        onSelectionChanged: (v) => setState(() => draft = draft.copyWith(span: v.first)),
                      ),
                      if (t.editor != null) ...[
                        const SizedBox(height: 12),
                        t.editor!(ctx, ref, draft, (v) => setState(() => draft = v)),
                      ],
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    ref.read(dashboardProvider.notifier).replace(draft);
                    Navigator.pop(ctx);
                  },
                  child: Text(context.tr('Save')),
                ),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Lays its children out side by side, all as tall as the tallest, so
/// compact cards sharing a row line up. Children size their own width.
///
/// (IntrinsicHeight would do this too, but cards may use LayoutBuilder,
/// which can't report intrinsic sizes.)
class _EqualHeightRow extends MultiChildRenderObjectWidget {
  final double gap;
  const _EqualHeightRow({required this.gap, required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderEqualHeightRow(gap, Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, _RenderEqualHeightRow renderObject) => renderObject
    ..gap = gap
    ..textDirection = Directionality.of(context);
}

class _RowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderEqualHeightRow extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _RowParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _RowParentData> {
  _RenderEqualHeightRow(this._gap, this._textDirection);

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection v) {
    if (v == _textDirection) return;
    _textDirection = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _RowParentData) child.parentData = _RowParentData();
  }

  @override
  void performLayout() {
    final loose = BoxConstraints(maxWidth: constraints.maxWidth);
    var height = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      c.layout(loose, parentUsesSize: true);
      if (c.size.height > height) height = c.size.height;
    }
    final rtl = _textDirection == TextDirection.rtl;
    var x = 0.0;
    var tallest = height;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      // At least the row's height, not exactly it: tight constraints would
      // make each card a relayout boundary, so a card whose content grows
      // later (data arriving) would overflow without the row hearing of it.
      c.layout(BoxConstraints(minWidth: c.size.width, maxWidth: c.size.width, minHeight: height), parentUsesSize: true);
      (c.parentData! as _RowParentData).offset = Offset(rtl ? constraints.maxWidth - x - c.size.width : x, 0);
      x += c.size.width + _gap;
      if (c.size.height > tallest) tallest = c.size.height;
    }
    size = constraints.constrain(Size(constraints.maxWidth, tallest));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}

/// A card's description with, for a conditional card, when it shows (and
/// whether it is hidden right now), so a card missing from the dashboard
/// isn't a mystery.
class _ShownWhen extends StatelessWidget {
  final String? text;
  final String? when;
  final bool hiddenNow;
  const _ShownWhen({this.text, this.when, this.hiddenNow = false});

  @override
  Widget build(BuildContext context) {
    final w = when;
    if (w == null) return Text(text ?? '');
    final theme = Theme.of(context);
    final color = theme.colorScheme.tertiary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (text != null) ...[Text(text!), const SizedBox(height: 2)],
      Row(children: [
        Icon(Icons.visibility_outlined, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            hiddenNow ? '${context.tr(w)} · ${context.tr('hidden now')}' : context.tr(w),
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ),
      ]),
    ]);
  }
}
