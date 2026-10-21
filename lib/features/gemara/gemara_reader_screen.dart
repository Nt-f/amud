import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/adaptive.dart';
import '../../core/analytics.dart';
import '../../core/celebration.dart';
import '../../core/focus_mode.dart';
import '../../core/l10n.dart';
import '../../core/page_swipe.dart';
import '../../core/portion_progress.dart';
import '../../core/providers.dart';
import '../../core/reader_mode.dart';
import '../../core/settings.dart';
import '../../core/typeset/type_scale.dart';
import '../integrations/prayer_links.dart' show shareTorahLink;
import '../torah/torah_settings.dart';
import 'daf_layout.dart';
import 'daf_page.dart';
import 'daf_print.dart';
import 'daf_video.dart';
import 'gemara_data.dart';
import 'gemara_home_screen.dart' show DafVideoButton, dafOfAmud, studyPath;
import 'gemara_perakim.dart';
import 'gemara_settings.dart';
import 'gemara_settings_sheet.dart';
import 'gemara_text.dart';
import 'gemara_user.dart';
import 'gemara_views.dart';
import 'interlinear.dart';
import 'study_book.dart';

/// Labels for the views, in the order the switcher shows them.
List<(GemaraView, IconData, String)> gemaraViews(BuildContext context) => [
      (GemaraView.daf, Icons.auto_stories_outlined, context.tr('Page (tzurat hadaf)')),
      (GemaraView.elucidated, Icons.notes, context.tr('Elucidated')),
      (GemaraView.sideBySide, Icons.view_column_outlined, context.tr('Side by side')),
      (GemaraView.phrase, Icons.short_text, context.tr('Phrase by phrase')),
      (GemaraView.interlinear, Icons.format_line_spacing, context.tr('Word by word')),
    ];

/// One unit of a study text (an amud, a Mishnah perek, a Kitzur siman), in
/// the reader's chosen view for that kind of text.
class GemaraReaderScreen extends ConsumerStatefulWidget {
  /// The book's Sefaria title and the unit.
  final String tractate;
  final String amud;

  /// A passage to open at (from a bookmark or the history).
  final int? segment;

  /// A day's portion to mark (0-based passages, inclusive): Mishnah Yomi,
  /// Kitzur Yomi. Reaching its end brings confetti.
  final int? from;
  final int? to;
  const GemaraReaderScreen({super.key, required this.tractate, required this.amud, this.segment, this.from, this.to});

  @override
  ConsumerState<GemaraReaderScreen> createState() => _GemaraReaderScreenState();
}

class _GemaraReaderScreenState extends ConsumerState<GemaraReaderScreen> with FocusModeReader {
  final _items = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  final _zoom = TransformationController();
  int? _selected;

  /// The passage whose details are open in place, and one to scroll to when
  /// the list is next built (from the page's tooltip).
  int? _expanded;
  int? _jump;

  /// The tooltip on the printed page: the tapped word and where it was.
  ({PlacedWord word, Offset global})? _tip;
  final _pageStack = GlobalKey();
  int? _wordSegment;
  int? _word;
  Timer? _saveTimer;
  int _visible = 0;
  bool _zoomed = false;

  /// Reader mode: taps step passage by passage (see [ReaderModeLayer]).
  bool _readerMode = false;

  /// This unit's place in the day's learning, as a share of the bar along
  /// the top: a marked portion (Mishnah, Kitzur Yomi) fills all of it, each
  /// amud of today's Daf Yomi its half. Null when it isn't a day's learning.
  ({double start, double share})? _share;

  /// How far through the day's learning, for that bar.
  final _progress = ValueNotifier<double?>(null);
  final _tracker = PortionTracker();
  bool _pageQueued = false;

  /// Passages on the amud, for stepping.
  int _count = 0;

  /// The printed page's layout and where it sits, for bringing a passage
  /// into view in reader mode.
  DafLayout? _dafLayout;
  final _dafKey = GlobalKey();
  final _viewerKey = GlobalKey();

  DafRef get _ref => (tractate: widget.tractate, amud: widget.amud);

  @override
  void initState() {
    super.initState();
    _selected = widget.segment;
    _visible = widget.segment ?? widget.from ?? 0;
    _positions.itemPositions.addListener(_onScroll);
    _zoom.addListener(() {
      // The tooltip stays put on screen, so it goes when the page moves.
      if (_tip != null) setState(() => _tip = null);
      final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
      _queuePageProgress();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _remember());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _positions.itemPositions.removeListener(_onScroll);
    _zoom.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _remember() {
    if (!mounted) return;
    ref.read(gemaraMarksProvider.notifier).visit(DafPlace(widget.tractate, widget.amud, _selected ?? _visible));
  }

  bool _yomiDone = false;

  /// The day's portion is read: confetti, once.
  void _finishYomi() {
    if (_yomiDone || widget.from == null || !mounted) return;
    _yomiDone = true;
    celebrate(context, Celebration.confetti);
  }

  // Item 0 is the header; segment n is item n + 1.
  void _onScroll() {
    final shown = _positions.itemPositions.value;
    final share = _share;
    final from = widget.from ?? 0;
    if (share != null && from < _count) {
      final to = (widget.to ?? _count - 1).clamp(from, _count - 1);
      if (_tracker.progress(shown, from + 1, to + 1) case final p?) _progress.value = share.start + share.share * p;
    }
    // Scrolled to the end of the unit with a day's portion in it.
    if (shown.any((p) => p.index == _count + 1 && p.itemLeadingEdge < 0.95)) _finishYomi();
    final first = shown.where((p) => p.itemTrailingEdge > 0.05).map((p) => p.index).fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    if (first == null) return;
    final seg = (first - 1).clamp(0, 9999);
    if (seg == _visible) return;
    _visible = seg;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _remember);
  }

  StudyBook get _book => studyBook(widget.tractate)!;
  String get _kind => _book.kind.name;
  GemaraView get _view => ref.read(gemaraSettingsProvider).viewFor(_kind, _book.views);

  String? _neighbor(int delta) => _book.neighbor(widget.amud, delta);

  void _go(String unit) => context.pushReplacement(studyPath(widget.tractate, unit));

  VoidCallback? _swipe(int delta) {
    final a = _neighbor(delta);
    if (a == null) return null;
    return () {
      analytics.event('page_swipe', {'reader': _kind, 'way': delta > 0 ? 'next' : 'previous'});
      _go(a);
    };
  }

  /// The amudim of today's Daf Yomi, when it's in this tractate.
  List<String> _dafYomiAmudim() {
    final yomi = dafYomiPlace(ref.read(todayProvider));
    if (yomi == null || yomi.book != widget.tractate) return const [];
    final daf = yomi.unit.substring(0, yomi.unit.length - 1);
    return ['${daf}a', '${daf}b'].where(_book.contains).toList();
  }

  ({double start, double share})? _portionShare() {
    if (widget.from != null) return (start: 0.0, share: 1.0);
    final amudim = _dafYomiAmudim();
    final at = amudim.indexOf(widget.amud);
    return at < 0 ? null : (start: at / amudim.length, share: 1 / amudim.length);
  }

  /// On the printed page, the day's progress follows the page as it pans,
  /// measured once it has been drawn.
  void _queuePageProgress() {
    if (_pageQueued || _share == null) return;
    _pageQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageQueued = false;
      final share = _share;
      final daf = _dafKey.currentContext?.findRenderObject() as RenderBox?;
      final viewer = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
      if (!mounted || !_onPage || share == null || daf == null || viewer == null || !daf.hasSize || !viewer.hasSize) return;
      final top = viewer.localToGlobal(Offset.zero).dy;
      double at(double y) => (daf.localToGlobal(Offset(0, y)).dy - top) / viewer.size.height;
      _progress.value = share.start + share.share * portionProgress(at(0), at(daf.size.height));
    });
  }

  GemaraStyle _style(BuildContext context) {
    final s = ref.watch(torahSettingsProvider);
    final g = ref.watch(gemaraSettingsProvider);
    final theme = Theme.of(context);
    final ts = TypeScale.of(ref.watch(settingsProvider), hebrewSize: 21 * s.textScale, latinSize: 16 * s.textScale);
    final ink = theme.colorScheme.onSurface;
    return GemaraStyle(
      he: TextStyle(fontFamily: s.hebrewFont, fontSize: 21 * s.textScale, height: 1.6, color: ink),
      en: TextStyle(fontFamily: s.latinFont, fontSize: 16 * s.textScale, height: ts.leading(ParagraphRole.body, hebrew: false), color: ink),
      rashi: TextStyle(fontFamily: 'NotoRashiHebrew', fontSize: 16 * s.textScale, height: 1.55, color: ink),
      small: TextStyle(fontFamily: s.latinFont, fontSize: 13 * s.textScale, height: 1.35, color: ink),
      accent: theme.colorScheme.primary,
      muted: theme.colorScheme.outline,
      nikud: s.showNikud,
      elucidation: g.elucidation,
    );
  }

  /// From the printed page: the passage in the elucidated view, with its
  /// details open.
  void _openPassage(int i) {
    setState(() {
      _selected = i;
      _expanded = i;
      _jump = i;
      _tip = null;
    });
    ref.read(gemaraSettingsProvider.notifier).update((x) => x.withView(_kind, GemaraView.elucidated));
    _remember();
  }

  bool get _onPage => _view == GemaraView.daf;

  void _startReader(int from) {
    setState(() {
      _readerMode = true;
      _selected = from;
      _expanded = null;
      _word = null;
      _tip = null;
    });
    if (_onPage) {
      _showOnPage(from);
    } else {
      _items.scrollTo(index: from + 1, duration: const Duration(milliseconds: 140), alignment: 0.12);
    }
    analytics.event('reader_mode', {'reader': _kind, 'on': true});
  }

  /// Moves the reader-mode passage by [delta]. Forward is animated briefly;
  /// back jumps (it follows a forward step already taken).
  void _step(int delta) {
    if (_count == 0) return;
    final target = ((_selected ?? _visible) + delta).clamp(0, _count);
    final end = widget.to ?? (widget.from != null ? _count - 1 : null);
    if (end != null && delta > 0 && target > end) _finishYomi();
    setState(() => _selected = target < _count ? target : _count - 1);
    if (_onPage) {
      _showOnPage(_selected!);
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(seconds: 2), _remember);
      return;
    }
    // Past the last passage: the end of the amud, with its button.
    final item = target < _count ? target + 1 : _count + 1;
    if (!_items.isAttached) return;
    if (delta > 0) {
      _items.scrollTo(index: item, duration: const Duration(milliseconds: 140), alignment: 0.12);
    } else {
      _items.jumpTo(index: item, alignment: 0.12);
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _remember);
  }

  /// Pans the printed page so a passage's first line sits near the top of
  /// the view, keeping the zoom.
  void _showOnPage(int segment) {
    final layout = _dafLayout;
    final daf = _dafKey.currentContext?.findRenderObject() as RenderBox?;
    final viewer = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (layout == null || daf == null || viewer == null) return;
    final ys = [for (final w in layout.words) if (w.column == DafColumn.main && w.word.segment == segment) w.y];
    if (ys.isEmpty) return;
    final top = ys.reduce((a, b) => a < b ? a : b);
    final now = daf.localToGlobal(Offset(0, top)).dy;
    final want = viewer.localToGlobal(Offset.zero).dy + viewer.size.height * 0.15;
    final m = Matrix4.translationValues(0, want - now, 0)..multiply(_zoom.value);
    // Never above the top of the page.
    if (m.getTranslation().y > 0) m.setTranslationRaw(m.getTranslation().x, 0, 0);
    _zoom.value = m;
  }

  /// Marks the amud complete (or not). Finishing a perek brings fireworks,
  /// finishing today's daf brings confetti.
  void _setComplete(bool done) {
    final marks = ref.read(gemaraMarksProvider.notifier);
    marks.setComplete(widget.tractate, widget.amud, done);
    analytics.event('study_complete', {'kind': _kind, 'book': widget.tractate, 'unit': widget.amud, 'done': done});
    if (!done) return;
    // A Mishnah perek or a Kitzur siman is a perek in itself.
    final perakim = _book.unitIsPerek ? const <Perek>[] : ref.read(perakimProvider(widget.tractate)).value ?? const [];
    if (_book.unitIsPerek || perekEndingOn(perakim, widget.amud) != null) {
      celebrate(context, Celebration.fireworks);
      return;
    }
    final amudim = _dafYomiAmudim();
    final now = ref.read(gemaraMarksProvider);
    if (amudim.contains(widget.amud) && amudim.every((a) => now.isComplete(widget.tractate, a))) {
      celebrate(context, Celebration.confetti);
    }
  }

  void _tapWord(int segment, int token) => setState(() {
        _wordSegment = segment;
        _word = token;
        _selected = segment;
      });

  void _stepWord(InterlinearUnit words, int delta) {
    final seg = words.at(_wordSegment!);
    if (seg == null) return;
    final next = _word! + delta;
    if (next >= 0 && next < seg.tokens.length) {
      setState(() => _word = next);
      return;
    }
    // Into the neighboring segment that has words.
    for (var s = _wordSegment! + delta; s >= 0 && s < words.segments.length; s += delta) {
      final n = words.at(s);
      if (n != null && n.hasWords) {
        setState(() {
          _wordSegment = s;
          _word = delta > 0 ? 0 : n.tokens.length - 1;
        });
        _items.scrollTo(index: s + 1, duration: const Duration(milliseconds: 250), alignment: 0.2);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = studyBook(widget.tractate);
    if (t == null || !t.contains(widget.amud)) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(context.tr('No such page.'))));
    }
    final daf = ref.watch(dafTextProvider(_ref));
    final words = ref.watch(interlinearProvider(_ref)).value;
    final g = ref.watch(gemaraSettingsProvider);
    final view = g.viewFor(_kind, t.views);
    final views = [for (final v in gemaraViews(context)) if (t.views.contains(v.$1)) v];
    final marks = ref.watch(gemaraMarksProvider);
    final st = _style(context);
    final theme = Theme.of(context);
    final bookmarked = marks.isBookmarked(DafPlace(widget.tractate, widget.amud));
    // Loaded early so finishing the amud knows whether a perek ends here.
    if (t.kind == StudyKind.bavli) ref.watch(perakimProvider(widget.tractate));
    readingText({'work': _kind, 'book': widget.tractate, 'unit': widget.amud, 'view': view.name});
    ref.watch(todayProvider);
    _share = _portionShare();
    if (_share != null) _progress.value ??= _share!.start;

    // The daf's video, or a Kitzur Yomi day's (or the first in the siman).
    final video = switch (t.kind) {
      StudyKind.bavli when dafOfAmud(widget.amud) != null => DafVideoButton(tractate: widget.tractate, daf: dafOfAmud(widget.amud)!),
      StudyKind.kitzur => DafVideoButton.kitzur(siman: int.parse(widget.amud), seif: widget.from == null ? null : widget.from! + 1),
      _ => null,
    };
    if (video != null) dafVideoIndex.load();
    final title = t.unitTitle(context, widget.amud);
    final bar = ValueListenableBuilder(
      valueListenable: dafVideoIndex,
      builder: (context, _, _) {
        final videoUnit = video?.readyUnit;
        return AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title),
            Text(views.firstWhere((v) => v.$1 == view).$3, style: theme.textTheme.bodySmall),
          ]),
          // On a narrow phone the link, then Reader mode, the bookmark, text
          // settings and the video wait in a menu.
          actions: fitBarActions(context, title, spare: [if (videoUnit != null) ...[5, 4, 2, 3, 1] else ...[4, 3, 1, 2]], [
            BarTool.custom(PopupMenuButton<GemaraView>(
              tooltip: context.tr('View'),
              icon: Icon(views.firstWhere((v) => v.$1 == view).$2),
              onSelected: (v) {
                ref.read(gemaraSettingsProvider.notifier).update((x) => x.withView(_kind, v));
                setState(() => _word = null);
              },
              itemBuilder: (context) => [
                for (final (v, icon, label) in views)
                  CheckedPopupMenuItem(value: v, checked: v == view, child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)])),
              ],
            )),
            if (videoUnit != null)
              BarTool(
                tooltip: context.tr('Watch the shiur'),
                icon: const Icon(Icons.movie_outlined),
                onPressed: () => context.push(dafVideoPath(video!.tractate, videoUnit)),
              ),
            BarTool(
              tooltip: bookmarked ? context.tr('Remove bookmark') : context.tr('Bookmark'),
              isSelected: bookmarked,
              icon: const Icon(Icons.bookmark_border),
              selectedIcon: const Icon(Icons.bookmark),
              onPressed: () => ref.read(gemaraMarksProvider.notifier).toggleBookmark(DafPlace(widget.tractate, widget.amud, _selected ?? _visible)),
            ),
            BarTool(tooltip: context.tr('Text settings'), icon: const Icon(Icons.text_fields), onPressed: () => showGemaraSettings(context, book: t)),
            BarTool(
              tooltip: context.tr('Reader mode'),
              isSelected: _readerMode,
              icon: const Icon(Icons.chrome_reader_mode_outlined),
              selectedIcon: const Icon(Icons.chrome_reader_mode),
              onPressed: () => _readerMode ? setState(() => _readerMode = false) : _startReader(_selected ?? _visible),
            ),
            BarTool(
              tooltip: context.tr('Copy link'),
              icon: const Icon(Icons.link),
              onPressed: () async {
                // This unit, at the marked passage if there is one.
                final link = shareTorahLink(studyPath(widget.tractate, widget.amud, segment: _selected));
                await Clipboard.setData(ClipboardData(text: link.toString()));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Link copied'))));
              },
            ),
          ]),
        );
      },
    );

    final body = switch (daf) {
      AsyncData(value: final d?) => view == GemaraView.daf
          ? ReaderModeLayer(
              active: _readerMode,
              onNext: () => _step(1),
              onBackTwo: () => _step(-2),
              onExit: () => setState(() => _readerMode = false),
              child: _page(d, words, st),
            )
          : ReaderModeLayer(
              active: _readerMode,
              onNext: () => _step(1),
              onBackTwo: () => _step(-2),
              onExit: () => setState(() => _readerMode = false),
              child: _reading(d, words, view, st),
            ),
      AsyncData() || AsyncError() => _failed(context),
      _ => const Center(child: CircularProgressIndicator()),
    };

    final wordSeg = _word == null || _wordSegment == null ? null : words?.at(_wordSegment!);
    return Scaffold(
      body: Column(children: [
        FocusModeBars(child: bar),
        Expanded(
          child: FocusModeBody(
            child: Stack(fit: StackFit.expand, children: [
              DoubleTapListener(
                // In reader mode a double tap steps back instead.
                onDoubleTap: _readerMode ? () {} : toggleFocusMode,
                child: PageSwipe(
                  // While the page is zoomed, sideways drags pan it instead.
                  onNext: _zoomed || _readerMode ? null : _swipe(1),
                  onPrevious: _zoomed || _readerMode ? null : _swipe(-1),
                  child: body,
                ),
              ),
              if (_share != null) Positioned(top: 0, left: 0, right: 0, child: PortionProgressBar(progress: _progress)),
            ]),
          ),
        ),
        if (wordSeg != null && wordSeg.hasWords && _word! < wordSeg.tokens.length && view != GemaraView.daf)
          WordCard(
            segment: wordSeg,
            token: _word!,
            style: st,
            onClose: () => setState(() => _word = null),
            onPrevious: () => _stepWord(words!, -1),
            onNext: () => _stepWord(words!, 1),
          ),
      ]),
    );
  }

  Widget _failed(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(context.tr('Couldn\'t load this amud. Check the connection and try again.'), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: () => ref.invalidate(dafTextProvider(_ref)), child: Text(context.tr('Try again'))),
          ]),
        ),
      );

  /// The printed page, pinch to zoom. Tapping a word marks its passage
  /// (Gemara, Rashi and Tosafot) and shows the translation in a tooltip over
  /// the text; the tooltip opens the full passage.
  Widget _page(DafText d, InterlinearUnit? words, GemaraStyle st) {
    final g = ref.watch(gemaraSettingsProvider);
    final marks = ref.watch(gemaraMarksProvider);
    final theme = Theme.of(context);
    final highlights = <int, Color>{
      for (var i = 0; i < d.length; i++)
        if (marks.highlights[DafPlace(d.tractate, d.amud, i).key] case final c?) i: highlightColors[c % highlightColors.length],
    };
    final tip = _tip;
    final tapMarks = tip == null ? null : _pageMarks(d, words, tip.word, g.dafTip, g.dafPhrase);
    _count = d.length;
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth - 16;
      return Stack(key: _pageStack, children: [
        InteractiveViewer(
          key: _viewerKey,
          transformationController: _zoom,
          constrained: false,
          minScale: 1,
          maxScale: 5,
          boundaryMargin: const EdgeInsets.only(bottom: 48),
          child: Padding(
            padding: pagePadding(context, const EdgeInsets.fromLTRB(8, 8, 8, 32)),
            child: SizedBox(
              width: width,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(_book.unitTitle(context, d.amud),
                    textAlign: TextAlign.center, style: theme.textTheme.titleSmall?.copyWith(fontFamily: 'FrankRuehlCLM')),
                const SizedBox(height: 6),
                DafPage(
                  key: _dafKey,
                  text: d,
                  printed: ref.watch(dafLineMapProvider((tractate: d.tractate, amud: d.amud))).valueOrNull,
                  onLayout: (l) {
                    _dafLayout = l;
                    _queuePageProgress();
                  },
                  onHoldWord: (w) => _startReader(w.word.segment),
                  selected: _selected,
                  markedComments: tapMarks?.comments ?? const {},
                  wordMarks: tapMarks?.words,
                  highlights: highlights,
                  scale: g.dafScale,
                  onTapWord: (w, global) {
                    // Anchor the tooltip to the word's top edge, not the tap,
                    // so it sits above the text rather than on it.
                    final daf = _dafKey.currentContext?.findRenderObject() as RenderBox?;
                    final anchor = w == null || daf == null ? global : daf.localToGlobal(Offset(w.x + w.width / 2, w.y));
                    setState(() {
                      _tip = w == null ? null : (word: w, global: anchor);
                      if (w != null) _selected = w.word.segment;
                    });
                    if (w != null) _remember();
                  },
                ),
                const SizedBox(height: 16),
                _endOfAmud(),
                _credits(d, words),
              ]),
            ),
          ),
        ),
        if (tip != null) _tooltip(d, words, st, tip, c),
      ]);
    });
  }

  /// What to mark on the page for a tapped word.
  ///
  ///  * A Rashi or Tosafot word: the comment, and the Gemara words it quotes
  ///    (its dibur hamatchil, placed by [commentAnchors]); the whole
  ///    passage when the quote can't be placed.
  ///  * A Gemara word: the passage, or the word (and phrase) with word-by-word
  ///    tooltips; and, more strongly, every comment that quotes that word.
  ({({Set<int> strong, Set<int> light})? words, Set<(DafColumn, int)> comments}) _pageMarks(
    DafText d,
    InterlinearUnit? words,
    PlacedWord tapped,
    DafTip mode,
    bool withPhrase,
  ) {
    final seg = tapped.word.segment;
    final page = [for (final w in wordsOfHtml(d.vilnaAt(seg), segment: seg)) w.text];
    final anchors = commentAnchors(d, seg, page);
    DafColumn columnOf(String id) => commentaryInfo(id).inner ? DafColumn.inner : DafColumn.outer;
    // A comment's number on the page: its place in its margin.
    final margins = {for (final inner in [true, false]) inner: d.margin(inner: inner)};
    int onPage(String id, int local) =>
        margins[commentaryInfo(id).inner]!.indexWhere((c) => c.id == id && c.segment == seg && c.index == local);

    if (tapped.column != DafColumn.main) {
      final m = margins[tapped.column == DafColumn.inner]!;
      final at = tapped.word.comment >= 0 && tapped.word.comment < m.length ? m[tapped.word.comment] : null;
      final a = at == null ? null : anchors.where((x) => x.id == at.id && x.index == at.index && at.segment == seg).firstOrNull;
      return (
        words: a == null ? null : (strong: {for (var i = a.from; i <= a.to; i++) i}, light: const <int>{}),
        comments: {(tapped.column, tapped.word.comment)},
      );
    }
    final at = tapped.word.position;
    return (
      words: _wordMarks(d, words, tapped, mode, withPhrase),
      comments: {
        for (final a in anchors)
          if (a.from <= at && at <= a.to) (columnOf(a.id), onPage(a.id, a.index)),
      },
    );
  }

  /// With word-by-word or phrase-by-phrase tooltips, what to mark on the
  /// page: the tapped Gemara word (or its phrase) rather than the whole
  /// passage. Each printed word of the passage is matched to its word in the
  /// word layer (by position, then spelling) to find which belong to the
  /// tapped word's phrase. Null keeps passage-level marking.
  ({Set<int> strong, Set<int> light})? _wordMarks(DafText d, InterlinearUnit? words, PlacedWord tapped, DafTip mode, bool withPhrase) {
    if (mode == DafTip.translation) return null;
    final seg = tapped.word.segment;
    final ws = words?.at(seg);
    if (ws == null || !ws.hasWords) return null;
    final page = wordsOfHtml(d.vilnaAt(seg), segment: seg);
    int? tokenOf(DafWord w) => matchWord(tapped: w.text, position: w.position, pageWords: page.length, tokens: ws.tokens);
    final k = tokenOf(tapped.word);
    final link = k == null ? -1 : ws.linkAt(k);
    final phrase = <int>{
      if (link >= 0)
        for (final w in page)
          if (tokenOf(w) case final t? when ws.linkAt(t) == link) w.position,
    };
    return mode == DafTip.phrases
        ? (strong: {tapped.word.position, ...phrase}, light: const <int>{})
        : (strong: {tapped.word.position}, light: withPhrase ? phrase : const <int>{});
  }

  /// The translation of what was tapped, just above it (below, near the top).
  Widget _tooltip(DafText d, InterlinearUnit? words, GemaraStyle st, ({PlacedWord word, Offset global}) tip, BoxConstraints c) {
    final theme = Theme.of(context);
    final box = _pageStack.currentContext?.findRenderObject() as RenderBox?;
    final at = box == null ? Offset(c.maxWidth / 2, c.maxHeight / 2) : box.globalToLocal(tip.global);
    final w = tip.word;
    final seg = w.word.segment;
    final marks = dafMarkColors(theme);
    final (label, color) = switch (w.column) {
      DafColumn.main => (context.tr('Gemara'), marks.main),
      DafColumn.inner => (context.tr('Rashi'), marks.inner),
      DafColumn.outer => (context.tr('Tosafot'), marks.outer),
    };
    final small = st.en.copyWith(fontSize: (st.en.fontSize ?? 16) * 0.82, height: 1.35);
    final tipStyle = GemaraStyle(
      en: small,
      he: st.he.copyWith(fontSize: (st.he.fontSize ?? 21) * 0.85),
      rashi: st.rashi.copyWith(fontSize: (st.rashi.fontSize ?? 16) * 0.85),
      small: st.small,
      accent: st.accent,
      muted: st.muted,
      nikud: st.nikud,
      elucidation: st.elucidation,
    );
    Widget body;
    final mode = ref.read(gemaraSettingsProvider).dafTip;
    final ws = words?.at(seg);
    final hasWords = ws != null && ws.hasWords;
    Widget translation() => Text.rich(TextSpan(children: runSpans(davidsonRuns(d.englishAt(seg)), tipStyle)), style: small);
    if (w.column == DafColumn.main && mode == DafTip.phrases && hasWords) {
      body = PhraseText(segment: ws, style: tipStyle, onWord: (_) {}, selected: const {}, number: '');
    } else if (w.column == DafColumn.main && mode == DafTip.words && hasWords) {
      // Just the word: itself and its English.
      final k = matchWord(
        tapped: w.word.text,
        position: w.word.position,
        pageWords: wordsOfHtml(d.vilnaAt(seg), segment: seg).length,
        tokens: ws.tokens,
      );
      body = k == null
          ? Text(context.tr('This word isn\'t in the word-by-word English.'), style: small.copyWith(color: st.muted, fontStyle: FontStyle.italic))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(st.hebrew(ws.tokens[k]), style: tipStyle.heBold, textDirection: TextDirection.rtl),
              Text(ws.glossAt(k) ?? '', style: tipStyle.literal),
            ]);
    } else if (w.column == DafColumn.main) {
      body = mode == DafTip.translation || hasWords
          ? translation()
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              translation(),
              const SizedBox(height: 6),
              Text(context.tr('Word-by-word English isn\'t ready for this amud yet.'), style: st.small.copyWith(color: st.muted)),
            ]);
    } else {
      final all = d.margin(inner: w.column == DafColumn.inner);
      final comment = w.word.comment >= 0 && w.word.comment < all.length ? all[w.word.comment].comment : null;
      final en = comment == null ? '' : plainText(comment.en);
      final (head, _) = comment?.split ?? ('', '');
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (head.isNotEmpty) Text(plainText(head), style: tipStyle.rashi.copyWith(fontWeight: FontWeight.w700), textDirection: TextDirection.rtl),
        Text(en.isNotEmpty ? en : context.tr('No English translation of this comment yet.'),
            style: en.isNotEmpty ? small : small.copyWith(color: st.muted, fontStyle: FontStyle.italic)),
      ]);
    }
    // Small, and above the word unless there's no room there.
    final wordOnly = w.column == DafColumn.main && mode == DafTip.words && hasWords;
    final tipWidth = (c.maxWidth - 24).clamp(0.0, wordOnly ? 210.0 : 300.0);
    final left = (at.dx - tipWidth / 2).clamp(12.0, c.maxWidth - tipWidth - 12);
    final above = at.dy > 130;
    final room = above ? at.dy - 16 : c.maxHeight - at.dy - w.height - 16;
    return Positioned(
      left: left,
      width: tipWidth,
      top: above ? null : at.dy + w.height + 8,
      bottom: above ? c.maxHeight - at.dy + 8 : null,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surfaceContainerHighest,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: room.clamp(70.0, 240.0)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 2, 8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color.withValues(alpha: 1), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('$label · ${segmentLabel(context, seg)}',
                      style: st.small.copyWith(fontWeight: FontWeight.w700, fontSize: (st.small.fontSize ?? 13) * 0.9)),
                ),
                for (final (icon, tip, action) in [
                  (Icons.open_in_full, context.tr('Open the passage'), () => _openPassage(seg)),
                  (Icons.close, context.tr('Close'), () => setState(() => _tip = null)),
                ])
                  IconButton(
                    tooltip: tip,
                    icon: Icon(icon, size: 15),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                    onPressed: action,
                  ),
              ]),
              Flexible(child: SingleChildScrollView(padding: const EdgeInsets.only(right: 8), child: body)),
            ]),
          ),
        ),
      ),
    );
  }

  /// The reading views: a list of segments.
  Widget _reading(DafText d, InterlinearUnit? words, GemaraView view, GemaraStyle st) {
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width > 900 ? (width - 860) / 2 : 12.0;
    _count = d.length;
    return ScrollablePositionedList.builder(
      itemScrollController: _items,
      itemPositionsListener: _positions,
      initialScrollIndex: (_jump ?? widget.segment ?? widget.from ?? -1) + 1,
      padding: pagePadding(context, EdgeInsets.fromLTRB(gutter, 8, gutter, 24)),
      itemCount: d.length + 2,
      itemBuilder: (context, n) {
        if (n == 0) {
          final pending = (view == GemaraView.phrase || view == GemaraView.interlinear) && (words == null || !words.segments.any((s) => s.hasWords));
          return pending
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.hourglass_empty),
                      title: Text(context.tr('Word-by-word English isn\'t ready for this amud yet.')),
                      subtitle: Text(context.tr('Showing the elucidated translation meanwhile.')),
                    ),
                  ),
                )
              : const SizedBox.shrink();
        }
        if (n == d.length + 1) return Column(children: [_endOfAmud(), _credits(d, words)]);
        final i = n - 1;
        return SegmentView(
          key: ValueKey(i),
          daf: d,
          index: i,
          words: words?.at(i),
          view: view,
          style: st,
          selected: _selected == i,
          today: _portionMark(i),
          selectedWord: _wordSegment == i ? _word : null,
          onWord: (k) => _tapWord(i, k),
          expanded: _expanded == i,
          onHold: () => _startReader(i),
          onSelect: () {
            setState(() {
              _expanded = _expanded == i ? null : i;
              _selected = i;
            });
            _remember();
          },
        );
      },
    );
  }

  /// Where passage [i] sits in the day's marked portion, if it's in it.
  ({bool first, bool last})? _portionMark(int i) {
    final from = widget.from;
    if (from == null) return null;
    final to = (widget.to ?? _count - 1).clamp(0, _count - 1);
    if (i < from || i > to) return null;
    return (first: i == from, last: i == to);
  }

  /// The end of the amud: the button that marks it complete, then the way
  /// on. An amud counts as complete only through this button.
  Widget _endOfAmud() {
    final done = ref.watch(gemaraMarksProvider).isComplete(widget.tractate, widget.amud);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      done
          ? OutlinedButton.icon(
              onPressed: () => _setComplete(false),
              icon: const Icon(Icons.check_circle),
              label: Text(context.tr('Completed · tap to undo')),
            )
          : FilledButton.icon(
              onPressed: () => _setComplete(true),
              icon: const Icon(Icons.check),
              label: Text(switch (_book.kind) {
                StudyKind.bavli => context.tr('Mark this amud complete'),
                StudyKind.mishnah => context.tr('Mark this perek complete'),
                StudyKind.kitzur => context.tr('Mark this siman complete'),
              }),
            ),
      _navigation(),
    ]);
  }

  Widget _navigation() {
    final prev = _neighbor(-1);
    final next = _neighbor(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        if (prev != null)
          Flexible(
            child: OutlinedButton.icon(
              onPressed: () => _go(prev),
              icon: const Icon(Icons.chevron_left),
              label: Text(_book.unitTitle(context, prev), overflow: TextOverflow.ellipsis),
            ),
          ),
        const Spacer(),
        if (next != null)
          Flexible(
            child: FilledButton.tonalIcon(
              onPressed: () => _go(next),
              icon: const Icon(Icons.chevron_right),
              label: Text(_book.unitTitle(context, next), overflow: TextOverflow.ellipsis),
              iconAlignment: IconAlignment.end,
            ),
          ),
      ]),
    );
  }

  Widget _credits(DafText daf, InterlinearUnit? words) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Column(children: [
        // Who made each text on the page, as Sefaria names it.
        if (daf.heCredit.isNotEmpty || daf.enCredit.isNotEmpty)
          Text(
            context.tr('Hebrew: {he}. English: {en}. Via Sefaria.', {
              'he': daf.heCredit.isEmpty ? '—' : daf.heCredit,
              'en': daf.enCredit.isEmpty ? '—' : daf.enCredit,
            }),
            textAlign: TextAlign.center,
            style: style,
          ),
        if (daf.vilna.isNotEmpty) Text(context.tr('Page text: Wikisource, CC-BY-SA.'), textAlign: TextAlign.center, style: style),
        for (final c in daf.commentaries)
          if (c.count > 0)
            Text(
              c.credit.isEmpty
                  ? context.tr('{name}: Hebrew via Sefaria.', {'name': context.tr(c.info.en)})
                  : context.tr('{name}: Hebrew via Sefaria; English: {credit}.', {'name': context.tr(c.info.en), 'credit': c.credit}),
              textAlign: TextAlign.center,
              style: style,
            ),
        if (words != null)
          Text(context.tr('Word-by-word English is machine-made from that translation; check it against the text.'),
              textAlign: TextAlign.center, style: style),
      ]),
    );
  }
}
