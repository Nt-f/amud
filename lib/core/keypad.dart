import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n.dart';
import 'providers.dart';
import 'settings.dart';

/// Keypad phones: flip phones and candybar phones with a d-pad, soft keys
/// and a number pad but no touch screen. The app is driven by focus: the
/// d-pad moves it (and scrolls where there's nothing more to move to), the
/// center key presses what's focused, the left soft key opens a menu and
/// the right soft key goes back. A bar along the bottom names the soft keys.

/// The phone has no touch screen, as Android reports it.
final keypadDeviceProvider = FutureProvider<bool>((ref) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    return await const MethodChannel('amud/integrations').invokeMethod<bool>('keypadDevice') ?? false;
  } catch (e) {
    debugPrint('Keypad detection: $e');
    return false;
  }
});

/// Keypad navigation is on: chosen in Settings, or found on a phone with no
/// touch screen.
final keypadModeProvider = Provider<bool>((ref) => switch (ref.watch(settingsProvider.select((s) => s.keypadNav))) {
      KeypadNav.on => true,
      KeypadNav.off => false,
      KeypadNav.auto => ref.watch(keypadDeviceProvider).valueOrNull ?? false,
    });

/// Flip phones send different codes for the soft keys: some send MENU for
/// the left one, some SOFT_LEFT and SOFT_RIGHT (Android key codes 1 and 2,
/// which Flutter has no names for). BACK, on the phones that send it for
/// the right one, goes back on its own.
const keypadMenuKeys = [
  SingleActivator(LogicalKeyboardKey.contextMenu),
  SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.androidPlane | 1)),
];
const keypadBackKeys = [
  SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.androidPlane | 2)),
];

/// Opens the menu of the page that has focus, or the app's own.
class KeypadMenuIntent extends Intent {
  const KeypadMenuIntent();
}

/// The right soft key: back. (Not [DismissIntent]: a page's route claims
/// that one and does nothing with it.)
class KeypadBackIntent extends Intent {
  const KeypadBackIntent();
}

/// What a scroll by key has still to cover, so quick presses add up.
final _targets = Expando<double>();

/// Scrolls [p] a step (a third of the screen) or a [page] up or down.
void keyScroll(ScrollPosition p, AxisDirection direction, {bool page = false}) {
  final pending = _targets[p];
  final from = p.isScrollingNotifier.value && pending != null ? pending : p.pixels;
  final step = p.viewportDimension * (page ? 0.8 : 0.33);
  final to = (from + (direction == AxisDirection.down ? step : -step)).clamp(p.minScrollExtent, p.maxScrollExtent);
  if (to == from) return;
  _targets[p] = to;
  p.animateTo(to, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
}

/// Whether [p] has more to show [direction] (counting presses still going).
bool canKeyScroll(ScrollPosition p, AxisDirection direction) {
  final pending = _targets[p];
  final from = p.isScrollingNotifier.value && pending != null ? pending : p.pixels;
  return switch (direction) {
    AxisDirection.down => from < p.maxScrollExtent,
    AxisDirection.up => from > p.minScrollExtent,
    _ => false,
  };
}

/// Up and down scroll [controller] when there's more to see; otherwise the
/// keys move focus as usual.
class KeyScrollAction extends Action<ScrollIntent> {
  final ScrollController controller;
  KeyScrollAction(this.controller);

  @override
  bool isEnabled(ScrollIntent intent) => controller.hasClients && canKeyScroll(controller.position, intent.direction);

  @override
  void invoke(ScrollIntent intent) => keyScroll(controller.position, intent.direction, page: intent.type == ScrollIncrementType.page);
}

/// The d-pad on a keypad phone. It moves focus as on any keyboard, with
/// what a screen that can't be touched needs besides:
/// - a focused item taller than the screen (a card, a paragraph) scrolls
///   into view a step at a time before focus moves on past it;
/// - where there's nothing to move to (the end of what's built of a long
///   list, or a page of text with nothing to press) the page scrolls;
/// - past the side edges, [onEdge] (the tabs, at a tab's first screen).
class DirectionalOrScrollAction extends DirectionalFocusAction {
  final bool Function(TraversalDirection direction)? onEdge;
  DirectionalOrScrollAction({this.onEdge});

  @override
  void invoke(DirectionalFocusIntent intent) {
    final focus = primaryFocus;
    if (focus == null) return;
    final vertical = intent.direction == TraversalDirection.up || intent.direction == TraversalDirection.down;
    final way = intent.direction == TraversalDirection.down ? AxisDirection.down : AxisDirection.up;
    final scrollable = vertical ? scrollableFor(focus) : null;
    if (scrollable != null && _overhangs(focus, scrollable, way) && canKeyScroll(scrollable.position, way)) {
      return keyScroll(scrollable.position, way);
    }
    // The text of a reader (a selection area around its list) has focus:
    // up and down read on.
    final text = focus is! FocusScopeNode && focus.context?.findAncestorWidgetOfExactType<SelectableRegion>() != null;
    if (text && scrollable != null && Scrollable.maybeOf(focus.context!) == null && canKeyScroll(scrollable.position, way)) {
      return keyScroll(scrollable.position, way);
    }
    final stops = _stopsToward(focus, intent.direction);
    // From outside the page's list (its app bar, a button under it), into
    // the list first: Flutter goes by distance, and would pass over what's
    // in the list but not yet scrolled into view.
    if (vertical && scrollable != null && focus is! FocusScopeNode && Scrollable.maybeOf(focus.context!) == null) {
      final inList = [for (final n in stops) if (Scrollable.maybeOf(n.context!, axis: Axis.vertical) == scrollable) n];
      if (inList.isNotEmpty) {
        final down = way == AxisDirection.down;
        final to = inList.reduce((a, b) => (down ? a.rect.top <= b.rect.top : a.rect.bottom >= b.rect.bottom) ? a : b);
        to.requestFocus();
        Scrollable.ensureVisible(to.context!,
            alignmentPolicy: down ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd : ScrollPositionAlignmentPolicy.keepVisibleAtStart);
        scheduleMicrotask(() => _fromItsStart(way));
        return;
      }
    }
    if (stops.isNotEmpty && focus.focusInDirection(intent.direction)) {
      // Once focus has moved (a microtask), before the frame is drawn.
      if (vertical) scheduleMicrotask(() => _fromItsStart(way));
      return;
    }
    if (scrollable != null && canKeyScroll(scrollable.position, way)) return keyScroll(scrollable.position, way);
    if (!vertical) onEdge?.call(intent.direction);
  }

  /// What there is to move to [direction] from [focus]. Flutter can't be
  /// asked: at the edge of a page it goes round to the other end (or stays
  /// put) and says it moved. Sideways, only what's beside it counts, so at
  /// the side of a list the tabs turn instead.
  static List<FocusNode> _stopsToward(FocusNode focus, TraversalDirection direction) {
    bool focusable(FocusNode n) => n.canRequestFocus && !n.skipTraversal && n.context != null && n.context!.mounted;
    // A page with nothing focused yet: anything on it.
    if (focus is FocusScopeNode) return focus.traversalDescendants.where(focusable).toList();
    final scope = focus.nearestScope;
    if (scope == null) return const [];
    final from = focus.rect;
    return [
      for (final n in scope.traversalDescendants)
        if (n != focus && focusable(n) && !n.ancestors.contains(focus) && !focus.ancestors.contains(n))
          if (_toward(n.rect, from, direction)) n,
    ];
  }

  static bool _toward(Rect r, Rect from, TraversalDirection direction) {
    final beside = r.top < from.bottom && r.bottom > from.top;
    return switch (direction) {
      TraversalDirection.down => r.center.dy > from.center.dy + 1,
      TraversalDirection.up => r.center.dy < from.center.dy - 1,
      TraversalDirection.right => beside && r.center.dx > from.center.dx + 1,
      TraversalDirection.left => beside && r.center.dx < from.center.dx - 1,
    };
  }

  /// Moving down onto an item taller than the screen, Flutter shows its end;
  /// it's read from its start (and up, from its end).
  static void _fromItsStart(AxisDirection way) {
    final f = primaryFocus;
    final c = f?.context;
    if (f == null || c == null || !c.mounted) return;
    final s = Scrollable.maybeOf(c);
    final box = s?.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || f.rect.height <= box.size.height) return;
    Scrollable.ensureVisible(c, alignment: way == AxisDirection.down ? 0 : 1);
  }

  /// [focus] runs past the edge of [scrollable]'s view [way] (only an item,
  /// not a whole page that holds the list).
  static bool _overhangs(FocusNode focus, ScrollableState scrollable, AxisDirection way) {
    final box = scrollable.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return false;
    if (Scrollable.maybeOf(focus.context!) == null) return false;
    final view = box.localToGlobal(Offset.zero) & box.size;
    final r = focus.rect;
    return way == AxisDirection.down ? r.bottom > view.bottom + 1 : r.top < view.top - 1;
  }
}

/// The vertical list [focus] is in, or else the first one that scrolls on
/// the page [focus] holds (a reader whose page has focus, a route with
/// nothing focused yet). Tabs and pages kept out of view are passed over.
ScrollableState? scrollableFor(FocusNode focus) {
  final context = focus.context;
  if (context == null || !context.mounted) return null;
  var s = Scrollable.maybeOf(context);
  while (s != null && s.position.axis != Axis.vertical) {
    s = Scrollable.maybeOf(s.context);
  }
  if (s != null) return s;
  ScrollableState? found;
  // Onstage only: not the tabs out of view, nor the pages under this one.
  void visit(Element e) {
    if (found != null) return;
    if (e is StatefulElement && e.state is ScrollableState) {
      final st = e.state as ScrollableState;
      final p = st.position;
      if (p.axis == Axis.vertical && p.hasContentDimensions && p.maxScrollExtent > p.minScrollExtent) {
        found = st;
        return;
      }
    }
    e.debugVisitOnstageChildren(visit);
  }

  (context as Element).debugVisitOnstageChildren(visit);
  // A button outside the text (the app bar's): the page it's on.
  final page = focus.enclosingScope?.context;
  if (found == null && page != null && page != context && page.mounted) (page as Element).debugVisitOnstageChildren(visit);
  return found;
}

/// Wraps the whole app when keypad navigation is on: the soft keys, the
/// d-pad, a ring around what has focus, and the soft-key bar.
class KeypadLayer extends ConsumerStatefulWidget {
  /// The app's own menu, where the page with focus has none.
  final VoidCallback onMenu;

  /// Back, as the phone's back key goes.
  final VoidCallback onBack;
  final Widget child;
  const KeypadLayer({super.key, required this.onMenu, required this.onBack, required this.child});

  @override
  ConsumerState<KeypadLayer> createState() => _KeypadLayerState();
}

class _KeypadLayerState extends ConsumerState<KeypadLayer> {
  late final _directional = DirectionalOrScrollAction();

  /// The app keeps its state (the pages open) when keypad navigation is
  /// turned on or off around it.
  final _app = GlobalKey();

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_leaveField);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_leaveField);
    super.dispose();
  }

  /// A one-line text field (a search box) would keep up and down for its
  /// caret, and the d-pad would be stuck in it: they move on instead.
  KeyEventResult _leaveField(KeyEvent e) {
    if (e is KeyUpEvent || !mounted || !ref.read(keypadModeProvider)) return KeyEventResult.ignored;
    final direction = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      _ => null,
    };
    final c = primaryFocus?.context;
    if (direction == null || c == null || !c.mounted) return KeyEventResult.ignored;
    if (c.findAncestorWidgetOfExactType<EditableText>()?.maxLines != 1) return KeyEventResult.ignored;
    _directional.invoke(DirectionalFocusIntent(direction));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final on = ref.watch(keypadModeProvider);
    // Focus shows from the first frame, not only after a key is pressed.
    FocusManager.instance.highlightStrategy = on ? FocusHighlightStrategy.alwaysTraditional : FocusHighlightStrategy.automatic;
    final app = KeyedSubtree(key: _app, child: widget.child);
    if (!on) return app;
    final focusMode = ref.watch(focusModeProvider);
    return Shortcuts(
      shortcuts: {
        for (final k in keypadMenuKeys) k: const KeypadMenuIntent(),
        for (final k in keypadBackKeys) k: const KeypadBackIntent(),
        // The d-pad, as on Android (in a browser arrows would scroll).
        const SingleActivator(LogicalKeyboardKey.arrowUp): const DirectionalFocusIntent(TraversalDirection.up),
        const SingleActivator(LogicalKeyboardKey.arrowDown): const DirectionalFocusIntent(TraversalDirection.down),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): const DirectionalFocusIntent(TraversalDirection.left),
        const SingleActivator(LogicalKeyboardKey.arrowRight): const DirectionalFocusIntent(TraversalDirection.right),
        // Escape on a keyboard, as on a computer trying this out.
        const SingleActivator(LogicalKeyboardKey.escape): const KeypadBackIntent(),
      },
      child: Actions(
        actions: {
          DirectionalFocusIntent: _directional,
          KeypadMenuIntent: CallbackAction<KeypadMenuIntent>(onInvoke: (_) {
            widget.onMenu();
            return null;
          }),
          // The right soft key: back, as the phone's own back key would.
          KeypadBackIntent: CallbackAction<KeypadBackIntent>(onInvoke: (_) {
            widget.onBack();
            return null;
          }),
        },
        child: Column(children: [
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: !focusMode,
              child: _FocusRing(child: app),
            ),
          ),
          if (!focusMode) const SoftKeyBar(),
        ]),
      ),
    );
  }
}

/// Names the soft keys along the bottom of the screen: the menu at the left
/// key, OK at the center, back at the right.
class SoftKeyBar extends StatelessWidget {
  const SoftKeyBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface);
    Widget label(String text, AlignmentGeometry at) => Expanded(
          child: Align(
            alignment: at,
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(context.tr(text), maxLines: 1, style: style)),
          ),
        );
    // The keys are where they are on the phone, whatever the language.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 26,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                label('Menu', Alignment.centerLeft),
                label('Select', Alignment.center),
                label('Back', Alignment.centerRight),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A ring around what has focus, drawn over the app, so it shows on any
/// widget, whatever its own focus highlight (most are faint).
class _FocusRing extends StatefulWidget {
  final Widget child;
  const _FocusRing({required this.child});

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing> {
  Rect? _rect;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_changed);
    SchedulerBinding.instance.addPostFrameCallback(_frame);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// After every frame (a scroll, a page turning), the ring follows.
  void _frame(Duration _) {
    if (!mounted) return;
    final r = _measure();
    if (r != _rect) setState(() => _rect = r);
    SchedulerBinding.instance.addPostFrameCallback(_frame);
  }

  Rect? _measure() {
    final f = FocusManager.instance.primaryFocus;
    if (f == null || f is FocusScopeNode) return null;
    final c = f.context;
    if (c == null || !c.mounted) return null;
    final ro = c.findRenderObject();
    final me = context.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize || me is! RenderBox || !me.hasSize) return null;
    final r = f.rect.shift(-me.localToGlobal(Offset.zero));
    final size = me.size;
    // A whole page with focus (a reader): no ring around the screen.
    if (r.left <= 1 && r.top <= 1 && r.right >= size.width - 1 && r.bottom >= size.height - 1) return null;
    if (!r.overlaps(Offset.zero & size)) return null;
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Stack(children: [
      Positioned.fill(child: widget.child),
      if (_rect case final r?)
        Positioned.fromRect(
          rect: r.inflate(1),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 2.5),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// One choice in a [showKeypadMenu].
class KeypadMenuItem {
  final String label;
  final IconData? icon;

  /// The key that does the same from the page ("#", "5"), as a hint.
  final String? key;
  final VoidCallback onSelected;
  const KeypadMenuItem(this.label, this.onSelected, {this.icon, this.key});
}

/// A menu for the left soft key: a list the d-pad moves through, the first
/// item focused. Labels are already translated.
Future<void> showKeypadMenu(BuildContext context, String title, List<KeypadMenuItem> items) async {
  final picked = await showDialog<KeypadMenuItem>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return Dialog(
        insetPadding: const EdgeInsets.all(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 4), children: [
                for (final (i, item) in items.indexed)
                  ListTile(
                    autofocus: i == 0,
                    dense: true,
                    leading: item.icon == null ? null : Icon(item.icon, size: 20),
                    minLeadingWidth: 20,
                    title: Text(item.label),
                    trailing: item.key == null
                        ? null
                        : Text(item.key!, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    onTap: () => Navigator.pop(ctx, item),
                  ),
              ]),
            ),
          ]),
        ),
      );
    },
  );
  picked?.onSelected();
}
