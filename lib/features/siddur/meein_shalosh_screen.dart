import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/fonts.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';

/// The three foods Me'ein Shalosh covers, in the order they're combined.
enum _Food { grain, wine, fruit }

/// Per-food text and styling. [open] is said after "Baruch… ha'olam",
/// [close] after "al ha'aretz" (twice); [closeIl] replaces it for produce of
/// Eretz Yisrael.
class _FoodInfo {
  final String en, he, foods, open, close;
  final String? closeIl;
  final IconData icon;
  final Color light, dark;
  const _FoodInfo(this.en, this.he, this.foods, this.open, this.close, this.closeIl, this.icon, this.light, this.dark);

  Color color(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

const _info = {
  _Food.grain: _FoodInfo(
    'Al HaMichya',
    'עַל הַמִּחְיָה',
    'Cake, crackers, pasta · 5 grains',
    'עַל הַמִּחְיָה וְעַל הַכַּלְכָּלָה',
    'וְעַל הַמִּחְיָה',
    null,
    Icons.bakery_dining,
    Color(0xFFA86A12),
    Color(0xFFF2C46D),
  ),
  _Food.wine: _FoodInfo(
    'Al HaGefen',
    'עַל הַגֶּפֶן',
    'Wine, grape juice',
    'עַל הַגֶּפֶן וְעַל פְּרִי הַגֶּפֶן',
    'וְעַל פְּרִי הַגָּפֶן',
    'וְעַל פְּרִי גַפְנָהּ',
    Icons.wine_bar,
    Color(0xFF8E2C5E),
    Color(0xFFE59ACB),
  ),
  _Food.fruit: _FoodInfo(
    'Al HaEtz',
    'עַל הָעֵץ',
    'Grapes, figs, pomegranates, olives, dates',
    'עַל הָעֵץ וְעַל פְּרִי הָעֵץ',
    'וְעַל הַפֵּרוֹת',
    'וְעַל פֵּרוֹתֶיהָ',
    Icons.park,
    Color(0xFF2E7D4F),
    Color(0xFF8FD6A8),
  ),
};

const _opening = 'בָּרוּךְ אַתָּה יְיָ אֱלֹהֵינוּ מֶלֶךְ הָעוֹלָם';
const _body =
    'וְעַל תְּנוּבַת הַשָּׂדֶה וְעַל אֶרֶץ חֶמְדָּה טוֹבָה וּרְחָבָה שֶׁרָצִיתָ וְהִנְחַלְתָּ לַאֲבוֹתֵינוּ לֶאֱכֹל מִפִּרְיָהּ '
    'וְלִשְׂבֹּֽעַ מִטּוּבָהּ. רַחֶם נָא יְיָ אֱלֹהֵינוּ עַל יִשְׂרָאֵל עַמֶּֽךָ וְעַל יְרוּשָׁלַֽיִם עִירֶֽךָ וְעַל צִיּוֹן מִשְׁכַּן כְּבוֹדֶֽךָ '
    'וְעַל מִזְבְּחֶֽךָ וְעַל הֵיכָלֶֽךָ, וּבְנֵה יְרוּשָׁלַֽיִם עִיר הַקֹּֽדֶשׁ בִּמְהֵרָה בְיָמֵֽינוּ, וְהַעֲלֵֽנוּ לְתוֹכָהּ וְשַׂמְּחֵֽנוּ '
    'בְּבִנְיָנָהּ, וְנֹאכַל מִפִּרְיָהּ וְנִשְׂבַּע מִטּוּבָהּ, וּנְבָרֶכְךָ עָלֶֽיהָ בִּקְדֻשָּׁה וּבְטָהֳרָה.';
const _kiAta = 'כִּי אַתָּה יְיָ טוֹב וּמֵטִיב לַכֹּל, וְנֽוֹדֶה לְּךָ עַל הָאָֽרֶץ';
const _chatima = 'בָּרוּךְ אַתָּה יְיָ, עַל הָאָֽרֶץ';

/// Today's additions, keyed by day-context flag: (Hebrew label, text).
const _seasonal = [
  ('shabbat', 'בְּשַׁבָּת', 'וּרְצֵה וְהַחֲלִיצֵֽנוּ בְּיוֹם הַשַּׁבָּת הַזֶּה.'),
  ('roshChodesh', 'בְּרֹאשׁ חֹֽדֶשׁ', 'וְזָכְרֵֽנוּ לְטוֹבָה בְּיוֹם רֹאשׁ הַחֹֽדֶשׁ הַזֶּה.'),
  ('roshHashana', 'בְּרֹאשׁ הַשָּׁנָה', 'וְזָכְרֵֽנוּ לְטוֹבָה בְּיוֹם הַזִּכָּרוֹן הַזֶּה.'),
  ('pesach', 'בְּפֶֽסַח', 'וְשַׂמְּחֵֽנוּ בְּיוֹם חַג הַמַּצּוֹת הַזֶּה.'),
  ('shavuot', 'בְּשָׁבוּעוֹת', 'וְשַׂמְּחֵֽנוּ בְּיוֹם חַג הַשָּׁבוּעוֹת הַזֶּה.'),
  ('sukkot', 'בְּסֻכּוֹת', 'וְשַׂמְּחֵֽנוּ בְּיוֹם חַג הַסֻּכּוֹת הַזֶּה.'),
  ('shminiAtzeret', 'בִּשְׁמִינִי עֲצֶֽרֶת', 'וְשַׂמְּחֵֽנוּ בְּיוֹם הַשְּׁמִינִי חַג הָעֲצֶֽרֶת הַזֶּה.'),
];

/// Bracha Me'ein Shalosh on a single screen: pick what you ate and the
/// matching phrases are woven in, color-coded. The whole text is scaled to
/// fit the screen, but never below a readable size. On a screen too short
/// for that (a flip phone) it's set at the reader's text size and the page
/// scrolls, by touch or with the keypad's up and down keys.
class MeeinShaloshScreen extends ConsumerStatefulWidget {
  const MeeinShaloshScreen({super.key});

  @override
  ConsumerState<MeeinShaloshScreen> createState() => _MeeinShaloshScreenState();
}

class _MeeinShaloshScreenState extends ConsumerState<MeeinShaloshScreen> {
  /// The foods picked; empty shows all three options. Always combined in
  /// [_Food] order (grain, wine, fruit), which is the order of the bracha.
  final Set<_Food> _ate = {};

  final _scroll = ScrollController();
  late final _keyScroll = _KeyScrollAction(_scroll);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(readerDaytimeDateProvider);
    // Past sunset (before dawn), tonight's additions: Shabbat's on Friday
    // night, none for a Rosh Chodesh that has ended.
    final night = ref.watch(readerDateProvider) == null && ref.watch(halachicTodayProvider.select((d) => d.abs())) != date.abs();
    final ctx = ref.watch(dayContextProvider(((night ? date.next() : date).abs(), Service.shacharit)));
    final today = [
      for (final s in _seasonal)
        if (ctx[s.$1]) s,
    ];
    // A flip phone, a phone's cover screen or a phone on its side: too
    // short to fit the bracha at a size worth reading, so it's set at the
    // reader's text size and scrolls, under a title bar that scrolls away.
    final compact = MediaQuery.sizeOf(context).height < 480;
    final readerScale = ref.watch(settingsProvider.select((s) => s.textScale));
    return Scaffold(
      body: SafeArea(
        top: false,
        // Up and down scroll when there's more to see; otherwise they move
        // focus as usual.
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowDown): ScrollIntent(direction: AxisDirection.down),
            SingleActivator(LogicalKeyboardKey.arrowUp): ScrollIntent(direction: AxisDirection.up),
            SingleActivator(LogicalKeyboardKey.pageDown): ScrollIntent(direction: AxisDirection.down, type: ScrollIncrementType.page),
            SingleActivator(LogicalKeyboardKey.pageUp): ScrollIntent(direction: AxisDirection.up, type: ScrollIncrementType.page),
          },
          child: Actions(
            actions: {ScrollIntent: _keyScroll},
            child: Focus(
              autofocus: true,
              skipTraversal: true,
              child: Scrollbar(
                controller: _scroll,
                child: LayoutBuilder(
                  builder: (context, c) => CustomScrollView(
                    controller: _scroll,
                    slivers: [
                      SliverAppBar(
                        floating: true,
                        snap: true,
                        title: Text(context.tr("Me'ein Shalosh")),
                        actions: [
                          if (_ate.isNotEmpty)
                            IconButton(tooltip: context.tr('Show all'), icon: const Icon(Icons.restart_alt), onPressed: () => setState(_ate.clear)),
                        ],
                      ),
                      SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: ((c.maxWidth - 760) / 2).clamp(0, double.infinity)),
                        // Fills the screen when the text fits; taller than
                        // it (and so scrolling) when not.
                        sliver: SliverFillRemaining(
                          hasScrollBody: false,
                          child: _page(context, today, compact: compact, minScale: compact ? readerScale : _RenderScaleToFit.readableScale),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The food buttons and the bracha under them, which is scaled to fit
  /// what's left of the screen but no smaller than [minScale].
  Widget _page(BuildContext context, List<(String, String, String)> today, {required bool compact, required double minScale}) {
    final gap = compact ? 6.0 : 12.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(gap, 4, gap, gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in _Food.values) ...[
                  if (f != _Food.grain) SizedBox(width: compact ? 6 : 8),
                  Expanded(
                    child: _FoodToggle(
                      food: f,
                      selected: _ate.contains(f),
                      compact: compact,
                      onTap: () => setState(() => _ate.contains(f) ? _ate.remove(f) : _ate.add(f)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: compact ? 4 : 6),
            child: Text(
              context.tr(_ate.isEmpty ? 'Tap what you ate to build the bracha' : 'Tap again to deselect, or pick more'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Card(
              margin: compact ? EdgeInsets.zero : null,
              child: Padding(
                padding: EdgeInsets.all(compact ? 8 : 12),
                child: _ScaleToFit(
                  minScale: minScale,
                  child: _BrachaText(ate: _ate, seasonal: today),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrolls the bracha with the keypad: a third of the screen per arrow, most
/// of it per page. Disabled at either end, so the key moves focus instead.
class _KeyScrollAction extends Action<ScrollIntent> {
  final ScrollController controller;
  _KeyScrollAction(this.controller);

  /// Where the last press is still scrolling to, so quick presses add up.
  double? _target;

  double get _from {
    final p = controller.position;
    return p.isScrollingNotifier.value && _target != null ? _target! : p.pixels;
  }

  @override
  bool isEnabled(ScrollIntent intent) {
    if (!controller.hasClients) return false;
    final p = controller.position;
    return switch (intent.direction) {
      AxisDirection.down => _from < p.maxScrollExtent,
      AxisDirection.up => _from > p.minScrollExtent,
      _ => false,
    };
  }

  @override
  void invoke(ScrollIntent intent) {
    final p = controller.position;
    final step = p.viewportDimension * (intent.type == ScrollIncrementType.page ? 0.8 : 0.33);
    final to = (_from + (intent.direction == AxisDirection.down ? step : -step)).clamp(p.minScrollExtent, p.maxScrollExtent);
    _target = to;
    controller.animateTo(to, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
  }
}

class _FoodToggle extends ConsumerWidget {
  final _Food food;
  final bool selected;

  /// On a small screen: shorter, without the examples of what it's for.
  final bool compact;
  final VoidCallback onTap;
  const _FoodToggle({required this.food, required this.selected, required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = _info[food]!;
    final color = info.color(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected ? (dark ? Colors.black : Colors.white) : color;
    final hebFont = ref.watch(settingsProvider.select((s) => s.hebrewFont));
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? color : color.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: compact ? 4 : 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(info.icon, color: fg, size: 22),
                    if (selected) Icon(Icons.check, color: fg, size: 16),
                  ],
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    info.he,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontFamily: hebFont, fontSize: 18, fontWeight: FontWeight.w700, color: fg),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    context.term(info.en),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
                  ),
                ),
                if (!compact)
                  Text(
                    context.tr(info.foods),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, height: 1.2, color: fg.withValues(alpha: 0.85)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The bracha itself (picked foods are always joined in [_Food] order). With nothing picked, each insertion point lists all
/// three options as color-coded rows; once foods are picked they're joined
/// inline so the text reads straight through.
class _BrachaText extends ConsumerWidget {
  final Set<_Food> ate;
  final List<(String, String, String)> seasonal;
  const _BrachaText({required this.ate, required this.seasonal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final base = TextStyle(
      fontFamily: hebrewFamilyFor(s.hebrewFont, teamim: false, nikud: true),
      fontSize: 22,
      height: 1.6,
      color: theme.colorScheme.onSurface,
    );
    final foods = [
      for (final f in _Food.values)
        if (ate.contains(f)) f,
    ];

    TextStyle foodStyle(_Food f) => base.copyWith(color: _info[f]!.color(context), fontWeight: FontWeight.w700);
    InlineSpan icon(_Food f) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Icon(_info[f]!.icon, size: 18, color: _info[f]!.color(context)),
      ),
    );
    InlineSpan ilNote(_Food f) {
      final il = _info[f]!.closeIl;
      if (il == null) return const TextSpan();
      return TextSpan(
        text: ' (פֵּרוֹת א״י: $il)',
        style: foodStyle(f).copyWith(fontSize: 14, fontWeight: FontWeight.w400),
      );
    }

    /// Inline join of the picked foods: "על המחיה… וְעַל הגפן…".
    List<InlineSpan> joined({required bool opening}) => [
      for (final (i, f) in foods.indexed) ...[
        const TextSpan(text: ' '),
        icon(f),
        TextSpan(text: opening ? (i == 0 ? _info[f]!.open : 'וְ${_info[f]!.open}') : _info[f]!.close, style: foodStyle(f)),
      ],
    ];

    /// All three options stacked, for when nothing is picked yet.
    Widget options({required bool opening}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in _Food.values)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 0),
            decoration: BoxDecoration(
              color: _info[f]!.color(context).withValues(alpha: 0.12),
              border: BorderDirectional(start: BorderSide(color: _info[f]!.color(context), width: 5)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  icon(f),
                  TextSpan(text: opening ? _info[f]!.open : _info[f]!.close, style: foodStyle(f)),
                  if (!opening) ilNote(f),
                ],
              ),
            ),
          ),
      ],
    );

    Widget para(List<InlineSpan> spans) => Text.rich(
      TextSpan(style: base, children: spans),
      textAlign: TextAlign.justify,
    );

    final seasonalBlocks = [
      for (final (_, label, text) in seasonal)
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsetsDirectional.fromSTEB(8, 2, 8, 2),
          decoration: BoxDecoration(
            color: colors.todayFill,
            border: BorderDirectional(start: BorderSide(color: colors.todayBar, width: 5)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text.rich(
            TextSpan(
              style: base,
              children: [
                TextSpan(
                  text: '$label: ',
                  style: base.copyWith(fontSize: 15, color: colors.instruction, fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: text,
                  style: base.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: foods.isEmpty
            ? [
                para([const TextSpan(text: '$_opening,')]),
                options(opening: true),
                para([const TextSpan(text: _body)]),
                ...seasonalBlocks,
                para([const TextSpan(text: _kiAta)]),
                options(opening: false),
                para([
                  const TextSpan(
                    text: _chatima,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ]),
                options(opening: false),
              ]
            : [
                para([const TextSpan(text: _opening), ...joined(opening: true), const TextSpan(text: ' '), const TextSpan(text: _body)]),
                ...seasonalBlocks,
                para([const TextSpan(text: _kiAta), ...joined(opening: false), const TextSpan(text: '.')]),
                para([
                  const TextSpan(
                    text: _chatima,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  ...joined(opening: false),
                  const TextSpan(text: '.'),
                ]),
                if (foods.any((f) => _info[f]!.closeIl != null))
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'פֵּרוֹת אֶרֶץ יִשְׂרָאֵל: ',
                          style: base.copyWith(fontSize: 14, color: colors.instruction),
                        ),
                        for (final (i, f) in foods.where((f) => _info[f]!.closeIl != null).indexed) ...[
                          if (i > 0) TextSpan(text: ' · ', style: base.copyWith(fontSize: 14)),
                          TextSpan(
                            text: '${_info[f]!.closeIl} (בִּמְקוֹם ${_info[f]!.close})',
                            style: foodStyle(f).copyWith(fontSize: 14, fontWeight: FontWeight.w400),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
      ),
    );
  }
}

/// Scales its child uniformly so it fills the available height without
/// overflowing: the child is laid out at a wider (or narrower) virtual width
/// and then scaled to the real width, so text reflows instead of just
/// shrinking. It never shrinks below [minScale]: its intrinsic height is what
/// the child needs at that scale, so in a [SliverFillRemaining] it grows past
/// the screen (and scrolls) rather than shrink further.
class _ScaleToFit extends SingleChildRenderObjectWidget {
  final double minScale;
  const _ScaleToFit({required this.minScale, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderScaleToFit(minScale);

  @override
  void updateRenderObject(BuildContext context, _RenderScaleToFit renderObject) => renderObject.minScale = minScale;
}

class _RenderScaleToFit extends RenderProxyBox {
  _RenderScaleToFit(this._minScale);

  /// The smallest the bracha is worth reading at, about 10px (times the
  /// system text size). Ordinary phones fit it above this.
  static const readableScale = 0.45;
  static const _maxScale = 1.6;

  double _minScale;
  set minScale(double v) {
    if (v == _minScale) return;
    _minScale = v;
    markNeedsLayout();
  }

  double _scale = 1;
  double _dy = 0;

  Matrix4 get _transform => Matrix4.translationValues(0, _dy, 0)..multiply(Matrix4.diagonal3Values(_scale, _scale, 1));

  /// The height the child needs at [_minScale].
  double _readableHeight(double width) => child == null ? 0 : child!.getMaxIntrinsicHeight(width / _minScale) * _minScale;

  @override
  double computeMinIntrinsicHeight(double width) => _readableHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _readableHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.hasBoundedHeight ? constraints.biggest : Size(constraints.maxWidth, _readableHeight(constraints.maxWidth));

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
    final child = this.child;
    if (child == null) return;
    // Height (in real pixels) the content needs at a given scale.
    double needed(double scale) {
      child.layout(BoxConstraints.tightFor(width: size.width / scale), parentUsesSize: true);
      return child.size.height * scale;
    }

    // needed() only grows with scale, so binary search the largest that fits.
    var lo = _minScale, hi = _maxScale < _minScale ? _minScale : _maxScale;
    if (needed(hi) <= size.height) {
      lo = hi;
    } else {
      for (var i = 0; i < 12; i++) {
        final mid = (lo + hi) / 2;
        if (needed(mid) <= size.height) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
    }
    _scale = lo;
    final h = needed(_scale);
    _dy = ((size.height - h) / 2).clamp(0, double.infinity);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      (c, o) => c.paintChild(child!, o),
      oldLayer: layer is TransformLayer ? layer as TransformLayer : null,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => result.addWithPaintTransform(
    transform: _transform,
    position: position,
    hitTest: (r, p) => child?.hitTest(r, position: p) ?? false,
  );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.multiply(_transform);
}
