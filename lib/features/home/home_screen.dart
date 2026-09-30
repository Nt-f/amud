import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
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
            const UpdateBanner(),
            const WhatsNewBanner(),
            Expanded(
              child: editing
                  ? _EditList(cards: cards, registry: registry, onAdd: () => _addCard(context, ref))
                  : _Grid(cards: cards, registry: registry),
            ),
          ]),
        ),
      ),
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
              child: Text(context.tr('Add a card'), style: Theme.of(ctx).textTheme.titleLarge),
            ),
            for (final t in registry.all)
              ListTile(
                leading: CircleAvatar(child: Icon(t.icon)),
                title: Text(context.tr(t.title)),
                subtitle: Text(context.tr(t.description)),
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
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 24),
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
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Center(
                child: TextButton.icon(
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
  final VoidCallback onAdd;
  const _EditList({required this.cards, required this.registry, required this.onAdd});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(dashboardProvider.notifier);
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: cards.length,
      onReorder: notifier.reorder,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(context.tr('Edit dashboard'), style: Theme.of(context).textTheme.titleLarge),
      ),
      footer: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(context.tr('Add card'))),
          TextButton.icon(
            onPressed: () async {
              if (await showAdaptiveConfirm(context,
                  title: context.tr('Reset dashboard?'), message: context.tr('Restore the default cards.'))) {
                notifier.reset();
              }
            },
            icon: const Icon(Icons.restart_alt),
            label: Text(context.tr('Reset layout')),
          ),
        ]),
      ),
      itemBuilder: (context, i) {
        final c = cards[i];
        final t = registry[c.type];
        return Card(
          key: ValueKey(c.id),
          margin: const EdgeInsets.symmetric(vertical: 4),
          // Actions live in a menu so the card's name keeps the width on
          // narrow phones and with large text.
          child: ListTile(
            contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 4),
            leading: Icon(t?.icon ?? Icons.help_outline),
            title: Text(c.setting<String>('title', '').isNotEmpty ? c.setting<String>('title', '') : context.tr(t?.title ?? c.type)),
            subtitle: Text(context.tr(c.span >= 2 ? 'Wide' : 'Compact')),
            onTap: t?.editor == null ? null : () => _configure(context, ref, t!, c),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              PopupMenuButton<VoidCallback>(
                tooltip: context.tr('More'),
                onSelected: (f) => f(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: () => notifier.replace(c.copyWith(span: c.span >= 2 ? 1 : 2)),
                    child: ListTile(
                      leading: Icon(c.span >= 2 ? Icons.grid_view : Icons.view_agenda_outlined),
                      title: Text(context.tr(c.span >= 2 ? 'Make compact' : 'Make wide')),
                    ),
                  ),
                  if (t?.editor != null)
                    PopupMenuItem(
                      value: () => _configure(context, ref, t!, c),
                      child: ListTile(leading: const Icon(Icons.tune), title: Text(context.tr('Configure'))),
                    ),
                  PopupMenuItem(
                    value: () => notifier.remove(c.id),
                    child: ListTile(leading: const Icon(Icons.delete_outline), title: Text(context.tr('Remove'))),
                  ),
                ],
              ),
              ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.drag_handle))),
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
                Text(context.tr('Configure {card}', {'card': context.tr(t.title)}), style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 12),
                t.editor!(ctx, ref, draft, (v) => setState(() => draft = v)),
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
