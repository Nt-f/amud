import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/adaptive.dart';
import '../../core/settings.dart';
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
    final today = ref.watch(todaySnapshotProvider);
    final loc = ref.watch(settingsProvider.select((s) => s.location.name));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              today.afterSunset
                  ? '${today.halachic.render(context.hebcalLocale)} · ${context.tr('night')}'
                  : today.halachic.render(context.hebcalLocale),
              style: theme.textTheme.titleMedium),
          Text(loc, style: theme.textTheme.bodySmall),
        ]),
        actions: [
          if (editing)
            IconButton(
              tooltip: 'Reset layout',
              icon: const Icon(Icons.restart_alt),
              onPressed: () async {
                if (await showAdaptiveConfirm(context, title: 'Reset dashboard?', message: 'Restore the default cards.')) {
                  ref.read(dashboardProvider.notifier).reset();
                }
              },
            ),
          IconButton(
            tooltip: editing ? 'Done' : 'Edit dashboard',
            icon: Icon(editing ? Icons.check : Icons.dashboard_customize_outlined),
            onPressed: () => ref.read(_editingProvider.notifier).state = !editing,
          ),
        ],
      ),
      floatingActionButton: editing
          ? FloatingActionButton.extended(
              onPressed: () => _addCard(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add card'),
            )
          : null,
      body: Column(children: [
        const UpdateBanner(),
        const WhatsNewBanner(),
        Expanded(child: editing ? _EditList(cards: cards, registry: registry) : _Grid(cards: cards, registry: registry)),
      ]),
    );
  }

  Future<void> _addCard(BuildContext context, WidgetRef ref) async {
    final registry = ref.read(cardRegistryProvider);
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
              child: Text('Add a card', style: Theme.of(ctx).textTheme.titleLarge),
            ),
            for (final t in registry.all)
              ListTile(
                leading: CircleAvatar(child: Icon(t.icon)),
                title: Text(context.tr(t.title)),
                subtitle: Text(t.description),
                onTap: () => Navigator.pop(ctx, t),
              ),
          ]),
        ),
      ),
    );
    if (t == null) return;
    ref.read(dashboardProvider.notifier).add(CardConfig(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          type: t.type,
          span: t.defaultSpan,
          settings: Map.of(t.defaults),
        ));
  }
}

class _Grid extends ConsumerWidget {
  final List<CardConfig> cards;
  final CardRegistry registry;
  const _Grid({required this.cards, required this.registry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 12.0;
      final width = c.maxWidth;
      // 2 columns on phones, 4 on tablets, 6 on wide desktop/web.
      final cols = width >= 1400 ? 6 : (width >= 840 ? 4 : 2);
      final pad = width > 1400 ? (width - 1400) / 2 + 16 : 16.0;
      final colW = (width - pad * 2 - gap * (cols - 1)) / cols;
      return RefreshIndicator.adaptive(
        onRefresh: () async => ref.invalidate(todaySnapshotProvider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(pad, 8, pad, 96),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, row) in _rows(ref, cols).indexed)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
                child: _EqualHeightRow(gap: gap, children: [
                  for (final card in row)
                    SizedBox(
                      width: (colW * _span(card, cols) + gap * (_span(card, cols) - 1)),
                      child: _buildCard(context, ref, card),
                    ),
                ]),
              ),
          ]),
        ),
      );
    });
  }

  /// Visible cards packed into rows of at most [cols] columns, in order.
  List<List<CardConfig>> _rows(WidgetRef ref, int cols) {
    final rows = <List<CardConfig>>[];
    var used = cols;
    for (final card in cards) {
      if (!(registry[card.type]?.visible?.call(ref) ?? true)) continue;
      final span = _span(card, cols);
      if (used + span > cols) {
        rows.add([]);
        used = 0;
      }
      rows.last.add(card);
      used += span;
    }
    return rows;
  }

  int _span(CardConfig c, int cols) => (c.span >= 2 ? (cols == 2 ? 2 : c.span.clamp(1, cols)) : 1);

  Widget _buildCard(BuildContext context, WidgetRef ref, CardConfig card) {
    final t = registry[card.type];
    if (t == null) return CardFrame(title: 'Unknown card', child: Text(card.type));
    return t.build(context, ref, card);
  }
}

class _EditList extends ConsumerWidget {
  final List<CardConfig> cards;
  final CardRegistry registry;
  const _EditList({required this.cards, required this.registry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(dashboardProvider.notifier);
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: cards.length,
      onReorder: notifier.reorder,
      itemBuilder: (context, i) {
        final c = cards[i];
        final t = registry[c.type];
        return Card(
          key: ValueKey(c.id),
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: Icon(t?.icon ?? Icons.help_outline),
            title: Text(c.setting<String>('title', '').isNotEmpty ? c.setting<String>('title', '') : (t?.title ?? c.type)),
            subtitle: Text(c.span >= 2 ? 'Wide' : 'Compact'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Toggle width',
                icon: Icon(c.span >= 2 ? Icons.view_agenda_outlined : Icons.grid_view),
                onPressed: () => notifier.replace(c.copyWith(span: c.span >= 2 ? 1 : 2)),
              ),
              if (t?.editor != null)
                IconButton(
                  tooltip: 'Configure',
                  icon: const Icon(Icons.tune),
                  onPressed: () => _configure(context, ref, t!, c),
                ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => notifier.remove(c.id),
              ),
              ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle))),
            ]),
          ),
        );
      },
    );
  }

  Future<void> _configure(BuildContext context, WidgetRef ref, CardType t, CardConfig c) async {
    var draft = c;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Configure ${t.title}', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 12),
                t.editor!(ctx, ref, draft, (v) => setState(() => draft = v)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    ref.read(dashboardProvider.notifier).replace(draft);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
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
    for (var c = firstChild; c != null; c = childAfter(c)) {
      c.layout(BoxConstraints.tightFor(width: c.size.width, height: height), parentUsesSize: true);
      (c.parentData! as _RowParentData).offset = Offset(rtl ? constraints.maxWidth - x - c.size.width : x, 0);
      x += c.size.width + _gap;
    }
    size = constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}
