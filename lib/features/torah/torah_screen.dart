import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hebcal/hebcal.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/adaptive.dart';
import '../../core/analytics.dart';
import '../../core/celebration.dart';
import '../../core/focus_mode.dart';
import '../../core/hebrew_text.dart';
import '../../core/l10n.dart';
import '../../core/split_row.dart';
import '../../core/page_swipe.dart';
import '../../core/reader_mode.dart';
import '../../core/search.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/typeset/typeset.dart';
import '../home/today.dart';
import '../search/search_sources.dart';
import '../tehillim/tehillim_card.dart';
import 'shnayim_mikra.dart';
import 'shnayim_mikra_screen.dart';
import 'torah_library.dart';
import 'torah_settings.dart';
import '../gemara/gemara_data.dart' show bookDownloadProvider, estimatedUnitBytes, savedUnitsProvider;
import '../gemara/gemara_home_screen.dart' show DafVideoButton, studyPath;
import '../gemara/gemara_user.dart';
import '../gemara/study_book.dart';

String _name(BuildContext context, String en, String he) => context.uiLanguage == UiLanguage.en ? context.term(en) : he;

/// The Torah tab: categories of texts to download from Sefaria and read
/// offline. Only some are ready; the rest are shown crossed out.
class TorahScreen extends ConsumerWidget {
  const TorahScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = [for (final c in torahCategories) ...c.availableWorks];
    final query = SearchQuery(ref.watch(pageSearchProvider('torah')));
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Torah')),
        actions: [OfflineStatus(works: all)],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(PageSearchBar.height),
          child: PageSearchBar(page: 'torah', hint: context.tr('Search books and texts')),
        ),
      ),
      body: !query.isEmpty
          ? ListView(padding: pagePadding(context, const EdgeInsets.only(bottom: 32)), children: [
              SearchResults(query: query.raw, hebrewFont: ref.watch(torahSettingsProvider).hebrewFont, groups: torahResults(context, ref, query)),
            ])
          : ListView(padding: pagePadding(context, const EdgeInsets.fromLTRB(12, 4, 12, 32)), children: [
        const EverythingDownloadPanel(),
        const ShnayimMikraTile(),
        const TehillimCard(),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(Icons.straighten, color: Theme.of(context).colorScheme.primary),
            title: Text(context.tr('Shiurim')),
            subtitle: Text(context.tr("Kezayis, revi'is, amah and every other measure, by each posek")),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/torah/shiurim'),
          ),
        ),
        for (final c in torahCategories)
          // The Gemara has its own reader (page by page from Sefaria) rather
          // than a downloaded book.
          c.id == 'gemara' || c.id == 'mishnah'
              ? _WorkTile(
                  icon: c.icon,
                  title: _name(context, c.en, c.he),
                  subtitle: c.id == 'gemara'
                      ? context.tr('The page, Rashi and Tosafot, with English phrase by phrase')
                      : context.tr('Every masechta with Bartenura, Mishnah Yomi, English phrase by phrase'),
                  available: true,
                  onTap: () => context.go('/torah/${c.id}'),
                )
              : _WorkTile(
                  icon: c.icon,
                  title: _name(context, c.en, c.he),
                  subtitle: c.available ? [for (final w in c.availableWorks) _name(context, w.en, w.he)].join(' · ') : null,
                  available: c.available,
                  onTap: () => context.go('/torah/${c.id}'),
                ),
      ]),
    );
  }
}

class TorahCategoryScreen extends ConsumerWidget {
  final String category;
  const TorahCategoryScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = torahCategory(category);
    if (c == null) return Scaffold(appBar: AppBar());
    final states = ref.watch(torahLibraryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_name(context, c.en, c.he)), actions: [OfflineStatus(works: c.availableWorks)]),
      body: ListView(padding: pagePadding(context, const EdgeInsets.fromLTRB(12, 4, 12, 32)), children: [
        if (c.available) DownloadPanel(works: c.availableWorks, label: context.tr('Download all of {name}', {'name': _name(context, c.en, c.he)})),
        if (c.id == 'halacha') const KitzurYomiTile(),
        const SizedBox(height: 8),
        for (final w in c.works)
          _WorkTile(
            icon: switch (states[w.id]) {
              Downloaded() => Icons.offline_pin,
              _ => Icons.menu_book_outlined,
            },
            title: _name(context, w.en, w.he),
            subtitle: switch (states[w.id]) {
              Downloaded(:final bytes) => context.tr('Downloaded · {size}', {'size': formatBytes(bytes)}),
              Downloading() => context.tr('Downloading…'),
              _ when w.available => context.tr('≈ {size} download', {'size': formatBytes(w.estimatedBytes)}),
              _ => null,
            },
            available: w.available,
            onTap: () => context.go('/torah/${c.id}/${w.id}'),
          ),
      ]),
    );
  }
}

/// A category or book; unavailable ones are greyed and crossed out.
class _WorkTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool available;
  final VoidCallback onTap;
  const _WorkTile({required this.icon, required this.title, required this.subtitle, required this.available, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = Card(
      child: ListTile(
        enabled: available,
        leading: Icon(icon, color: available ? theme.colorScheme.primary : null),
        // The chip beside the name, or under it on a narrow phone, where as
        // the trailing widget it squeezed the name to a letter a line.
        title: available
            ? Text(title)
            : SplitRow(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Text(title, style: const TextStyle(decoration: TextDecoration.lineThrough, decorationThickness: 2)),
                Chip(
                  avatar: const Icon(Icons.construction, size: 16),
                  label: Text(context.tr('Work in progress')),
                  visualDensity: VisualDensity.compact,
                ),
              ]),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: available ? const Icon(Icons.chevron_right) : null,
        onTap: available ? onTap : null,
      ),
    );
    return available ? tile : Opacity(opacity: 0.55, child: tile);
  }
}

/// A prominent download button for [works] showing the estimated size,
/// and progress while downloading. Once everything is downloaded it's
/// gone; [OfflineStatus] in the top bar says so instead.
class DownloadPanel extends ConsumerWidget {
  final List<TorahWork> works;
  final String label;
  const DownloadPanel({super.key, required this.works, required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final states = ref.watch(torahLibraryProvider);
    final lib = ref.read(torahLibraryProvider.notifier);
    final missing = [for (final w in works) if (states[w.id] is! Downloaded) w];
    final downloading = works.any((w) => states[w.id] is Downloading);
    if (missing.isEmpty && !downloading) return const SizedBox.shrink();
    return _DownloadCard(
      label: label,
      estimate: missing.fold<int>(0, (n, w) => n + w.estimatedBytes),
      busy: downloading,
      failed: works.any((w) => states[w.id] is DownloadFailed),
      onPressed: () => lib.downloadAll(missing),
    );
  }
}

/// The Torah tab's "Download everything": its books, Shnayim Mikra with
/// Rashi, the Mishnah and Shas, with the size of what isn't saved yet.
class EverythingDownloadPanel extends ConsumerWidget {
  const EverythingDownloadPanel({super.key});

  /// Set by Cancel; the books still to come aren't started.
  static var _stop = false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final works = [for (final c in torahCategories) ...c.availableWorks];
    final states = ref.watch(torahLibraryProvider);
    final chumash = ref.watch(chumashDownloadProvider);
    final rashi = ref.watch(rashiDownloadProvider);
    final fiveBooks = [ref.read(chumashDownloadProvider.notifier), ref.read(rashiDownloadProvider.notifier)];
    final study = [
      for (final kind in [StudyKind.mishnah, StudyKind.bavli])
        (kind: kind, key: [for (final b in booksOf(kind)) b.id].join('|'), units: booksOf(kind).fold<int>(0, (n, b) => n + b.units.length)),
    ];
    final missing = [for (final w in works) if (states[w.id] is! Downloaded) w];
    var estimate = missing.fold<int>(0, (n, w) => n + w.estimatedBytes) + fiveBooks.fold<int>(0, (n, b) => n + b.missingBytes);
    (int, int)? progress;
    for (final s in study) {
      estimate += (s.units - ref.watch(savedUnitsProvider(s.key))).clamp(0, s.units).toInt() * estimatedUnitBytes(s.kind);
      progress ??= ref.watch(bookDownloadProvider(s.key));
    }
    final busy = works.any((w) => states[w.id] is Downloading) || chumash.busy || rashi.busy || progress != null;
    if (estimate == 0 && !busy) return const SizedBox.shrink();

    Future<void> downloadAll() async {
      _stop = false;
      final studyDownloads = [for (final s in study) ref.read(bookDownloadProvider(s.key).notifier)];
      await ref.read(torahLibraryProvider.notifier).downloadAll(missing);
      for (final b in fiveBooks) {
        if (_stop) return;
        await b.downloadAll().catchError((_) {});
      }
      for (final d in studyDownloads) {
        if (_stop) return;
        await d.start();
      }
    }

    return _DownloadCard(
      label: context.tr('Download everything'),
      estimate: estimate,
      busy: busy,
      progress: progress == null ? null : context.tr('Downloading from Sefaria… {done} of {total}', {'done': progress.$1, 'total': progress.$2}),
      onCancel: progress == null
          ? null
          : () {
              _stop = true;
              for (final s in study) {
                ref.read(bookDownloadProvider(s.key).notifier).cancel();
              }
            },
      failed: chumash.failed || rashi.failed || works.any((w) => states[w.id] is DownloadFailed),
      onPressed: downloadAll,
    );
  }
}

/// A download banner: one big button with the rough size, progress while
/// it runs.
class _DownloadCard extends StatelessWidget {
  final String label;
  final int estimate;
  final bool busy;
  final bool failed;
  final VoidCallback onPressed;

  /// What's being downloaded, and a way to stop it, when known.
  final String? progress;
  final VoidCallback? onCancel;
  const _DownloadCard(
      {required this.label, required this.estimate, required this.busy, required this.failed, required this.onPressed, this.progress, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget body;
    if (busy) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(progress ?? context.tr('Downloading from Sefaria…'), style: theme.textTheme.titleSmall)),
          if (onCancel != null) IconButton(tooltip: context.tr('Cancel'), icon: const Icon(Icons.close), onPressed: onCancel),
        ]),
        const SizedBox(height: 10),
        const LinearProgressIndicator(),
      ]);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20)),
          icon: const Icon(Icons.download),
          label: Text('$label · ≈ ${formatBytes(estimate)}', textAlign: TextAlign.center),
          onPressed: onPressed,
        ),
        const SizedBox(height: 6),
        Text(
          failed
              ? context.tr("Download failed. Check your connection and try again.")
              : context.tr('Downloads from Sefaria once, then works offline.'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: failed ? theme.colorScheme.error : theme.colorScheme.outline),
        ),
      ]);
    }
    return Card(
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
      child: Padding(padding: const EdgeInsets.all(14), child: body),
    );
  }
}

/// A small "available offline" mark for the top bar once all of [works]
/// is downloaded. Tapping it shows the space used and, when [allowDelete],
/// offers to remove the download.
class OfflineStatus extends ConsumerWidget {
  final List<TorahWork> works;
  final bool allowDelete;
  const OfflineStatus({super.key, required this.works, this.allowDelete = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final states = ref.watch(torahLibraryProvider);
    if (works.isEmpty || works.any((w) => states[w.id] is! Downloaded)) return const SizedBox.shrink();
    final stored = works.fold<int>(0, (n, w) => n + switch (states[w.id]) { Downloaded(:final bytes) => bytes, _ => 0 });
    final theme = Theme.of(context);
    final label = context.tr('Available offline · {size}', {'size': formatBytes(stored)});
    return PopupMenuButton<void>(
      tooltip: label,
      icon: Icon(Icons.offline_pin_outlined, color: theme.colorScheme.primary),
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.offline_pin, color: theme.colorScheme.primary),
            title: Text(label, style: theme.textTheme.bodyMedium),
          ),
        ),
        if (allowDelete)
          PopupMenuItem(
            onTap: () async {
              for (final w in works) {
                await ref.read(torahLibraryProvider.notifier).delete(w);
              }
            },
            child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.delete_outline), title: Text(context.tr('Remove download'))),
          ),
      ],
    );
  }
}

/// Where today's Kitzur Yomi starts and ends (se'if numbers within
/// [siman]; [to] null = to the end of the siman).
typedef KitzurTarget = ({int siman, int from, int? to});

KitzurTarget? kitzurTarget(KitzurShulchanAruchEvent ev) {
  final b = RegExp(r'^(\d+):(\d+)$').firstMatch(ev.reading.b);
  if (b == null) return null;
  final siman = int.parse(b[1]!);
  final e = RegExp(r'^(\d+):(\d+)$').firstMatch(ev.reading.e ?? '');
  final to = e != null && int.parse(e[1]!) == siman ? int.parse(e[2]!) : null;
  return (siman: siman, from: int.parse(b[2]!), to: to);
}

String heUiName(BuildContext context, int siman) =>
    context.uiLanguage == UiLanguage.en ? '${context.tr('Siman')} $siman' : 'סימן ${gematriya(siman)}';

/// Today's Kitzur Shulchan Aruch Yomi; opens in the study reader with the
/// day's se'ifim marked.
class KitzurYomiTile extends ConsumerWidget {
  const KitzurYomiTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todaySnapshotProvider);
    final il = ref.watch(settingsProvider.select((s) => s.location.il));
    final theme = Theme.of(context);
    KitzurShulchanAruchEvent? ev;
    try {
      ev = DailyLearning.lookup('kitzurShulchanAruch', t.hdate, il) as KitzurShulchanAruchEvent?;
    } catch (_) {}
    final target = ev == null ? null : kitzurTarget(ev);
    final url = ev?.url();
    // The study reader fetches a siman from Sefaria when the Kitzur isn't
    // downloaded, so today's portion always opens in the app.
    final inApp = target != null;
    return Card(
      // The primary container (the theme's blue), not the tertiary one,
      // which Material derives as pink from the default seed color.
      color: theme.colorScheme.primaryContainer,
      child: ListTile(
        leading: Icon(Icons.today, color: theme.colorScheme.onPrimaryContainer),
        title: Text(context.tr('Kitzur Yomi'),
            style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
        subtitle: Text(ev == null ? context.tr('No reading today') : ev.renderBrief(context.hebcalLocale),
            style: TextStyle(color: theme.colorScheme.onPrimaryContainer)),
        trailing: ev == null
            ? null
            : Row(mainAxisSize: MainAxisSize.min, children: [
                // The day's video shiur, as beside Daf Yomi.
                if (target != null) DafVideoButton.kitzur(siman: target.siman, seif: target.from),
                Icon(inApp ? Icons.chevron_right : Icons.open_in_new, color: theme.colorScheme.onPrimaryContainer),
              ]),
        onTap: ev == null
            ? null
            : inApp
                ? () => context.push(studyPath(kitzurId, '${target.siman}', from: target.from - 1, to: target.to == null ? null : target.to! - 1))
                : url == null
                    ? null
                    : () => launchUrl(Uri.parse(url)),
      ),
    );
  }
}

/// A book's page: download button and its chapters.
class TorahWorkScreen extends ConsumerWidget {
  final String category;
  final String work;
  const TorahWorkScreen({super.key, required this.category, required this.work});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = torahWork(work);
    if (w == null) return Scaffold(appBar: AppBar());
    final s = ref.watch(torahSettingsProvider);
    final book = ref.watch(torahBookProvider(w.id));
    final query = SearchQuery(ref.watch(pageSearchProvider('torah:${w.id}')));
    final theme = Theme.of(context);
    final he = context.uiLanguage != UiLanguage.en;
    return Scaffold(
      appBar: AppBar(
        title: Text(_name(context, w.en, w.he)),
        actions: [
          OfflineStatus(works: [w], allowDelete: true),
          IconButton(tooltip: context.tr('Text settings'), icon: const Icon(Icons.text_fields), onPressed: () => showTorahTextSettings(context)),
        ],
        bottom: book.value == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(PageSearchBar.height),
                child: PageSearchBar(page: 'torah:${w.id}', hint: context.tr('Search {book}', {'book': _name(context, w.en, w.he)})),
              ),
      ),
      body: !query.isEmpty && book.value != null
          ? ListView(padding: pagePadding(context, const EdgeInsets.only(bottom: 32)), children: [
              SearchResults(query: query.raw, hebrewFont: s.hebrewFont, groups: torahResults(context, ref, query, only: w.id)),
            ])
          : ListView(padding: pagePadding(context, const EdgeInsets.fromLTRB(12, 4, 12, 32)), children: [
        DownloadPanel(works: [w], label: context.tr('Download')),
        if (w.id == kitzur.id) ...[
          const KitzurYomiTile(),
          if (ref.watch(gemaraMarksProvider).history.where((h) => h.tractate == kitzurId).firstOrNull case final r?)
            Card(
              child: ListTile(
                leading: Icon(Icons.play_circle_outline, color: theme.colorScheme.primary),
                title: Text(context.tr('Continue')),
                subtitle: Text(heUiName(context, int.parse(r.amud))),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(studyPath(kitzurId, r.amud, segment: r.segment)),
              ),
            ),
        ],
        const SizedBox(height: 8),
        ...switch (book) {
          AsyncData(value: final b?) => [
              for (var i = 0; i < b.length; i++)
                ListTile(
                  leading: SizedBox(
                    width: 40,
                    child: Text(he ? gematriya(i + 1) : '${i + 1}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary, fontFamily: he ? s.hebrewFont : null)),
                  ),
                  title: Text(he || b.titlesEn[i].isEmpty ? b.titlesHe[i] : b.titlesEn[i],
                      style: he ? TextStyle(fontFamily: s.hebrewFont, fontSize: 17) : null),
                  subtitle: he || b.titlesHe[i].isEmpty
                      ? null
                      : Text(b.titlesHe[i], textDirection: TextDirection.rtl, style: TextStyle(fontFamily: s.hebrewFont)),
                  // A check for a siman marked complete in the reader.
                  trailing: w.id == kitzur.id && ref.watch(gemaraMarksProvider).isComplete(kitzurId, '${i + 1}')
                      ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                      : null,
                  onTap: () => context.push('/torah/$category/$work/read?siman=${i + 1}'),
                ),
            ],
          AsyncLoading() => [const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))],
          _ => [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(context.tr('Download to read it here, even offline.'),
                    textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
              ),
            ],
        },
      ]),
    );
  }
}

/// One siman of a downloaded book, with an optional highlighted range
/// (today's Kitzur Yomi) scrolled into view.
class TorahReaderScreen extends ConsumerStatefulWidget {
  final String category;
  final String work;
  final int siman;
  final int? from;
  final int? to;
  const TorahReaderScreen({super.key, required this.category, required this.work, required this.siman, this.from, this.to});

  @override
  ConsumerState<TorahReaderScreen> createState() => _TorahReaderScreenState();
}

class _TorahReaderScreenState extends ConsumerState<TorahReaderScreen> with FocusModeReader {
  /// One per se'if, for scrolling to today's portion.
  final _keys = <GlobalKey>[];
  bool _scrolled = false;

  /// The highlighted se'if (0-based), and reader mode stepping from it.
  int? _current;
  bool _readerMode = false;
  int _count = 0;
  final _scroll = ScrollController();
  bool _celebrated = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_atEnd);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Reaching the end: confetti for today's portion, fireworks for a whole
  /// siman.
  void _finish() {
    if (_celebrated || !mounted) return;
    _celebrated = true;
    celebrate(context, widget.from != null ? Celebration.confetti : Celebration.fireworks);
  }

  void _atEnd() {
    if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0 && _scroll.position.extentAfter < 24) _finish();
  }

  void _showSeif(int i, {required bool animate}) {
    if (i < 0 || i >= _keys.length) return;
    final ctx = _keys[i].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, alignment: 0.12, duration: animate ? const Duration(milliseconds: 140) : Duration.zero);
  }

  void _startReader(int from) {
    setState(() {
      _current = from;
      _readerMode = true;
    });
    _showSeif(from, animate: true);
    analytics.event('reader_mode', {'reader': 'torah', 'on': true});
  }

  /// Steps the reader-mode se'if by [delta]; past the portion's end (or the
  /// siman's) celebrates.
  void _step(int delta) {
    if (_count == 0) return;
    final end = widget.to != null && widget.from != null ? widget.to!.clamp(1, _count) : _count;
    final target = (_current ?? 0) + delta;
    if (target >= end) {
      setState(() => _current = end - 1);
      _showSeif(end - 1, animate: true);
      _finish();
      return;
    }
    final i = target.clamp(0, _count - 1);
    setState(() => _current = i);
    _showSeif(i, animate: delta > 0);
  }

  void _scrollToHighlight() {
    final from = widget.from;
    if (_scrolled || from == null || from > _keys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[from - 1].currentContext;
      if (ctx == null) return;
      _scrolled = true;
      Scrollable.ensureVisible(ctx, alignment: 0.05, duration: const Duration(milliseconds: 300));
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = torahWork(widget.work);
    final book = w == null ? null : ref.watch(torahBookProvider(w.id)).value;
    final s = ref.watch(torahSettingsProvider);
    final lang = s.resolvedLanguage(context.uiLanguage);
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    // The library keeps its own sizes but follows the app's typesetting.
    final ts = TypeScale.of(ref.watch(settingsProvider), hebrewSize: 21 * s.textScale, latinSize: 16 * s.textScale);
    final heStyle = TextStyle(
        fontFamily: s.hebrewFont, fontSize: 21 * s.textScale, height: ts.print ? ts.leading(ParagraphRole.body, hebrew: true) : 1.6, color: theme.colorScheme.onSurface);
    final enStyle = TextStyle(
        fontFamily: s.latinFont, fontSize: 16 * s.textScale, height: ts.leading(ParagraphRole.body, hebrew: false), color: theme.colorScheme.onSurface);
    Widget paragraph(List<InlineSpan> spans, TextStyle style, TextDirection dir) => ts.print
        ? TypesetParagraph(text: TextSpan(style: style, children: spans), textDirection: dir, em: style.fontSize!, align: ts.align(ParagraphRole.body))
        : Text.rich(TextSpan(children: spans), textDirection: dir, style: style);
    final heUi = context.uiLanguage != UiLanguage.en;
    if (w == null || book == null || widget.siman < 1 || widget.siman > book.length) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final i = widget.siman - 1;
    final he = book.he[i];
    final en = i < book.en.length ? book.en[i] : const <String>[];
    final count = he.length > en.length ? he.length : en.length;
    bool hasEn(int n) => n <= en.length && en[n - 1].trim().isNotEmpty;
    final from = widget.from;
    final to = widget.to ?? count;
    while (_keys.length < count) {
      _keys.add(GlobalKey());
    }
    _count = count;
    _scrollToHighlight();
    readingText({
      'work': w.id,
      'siman': widget.siman,
      'title': book.titlesEn[i].isEmpty ? book.titlesHe[i] : book.titlesEn[i],
      'language': lang.name,
      'daily_portion': from != null,
    });

    void go(int siman) => context.pushReplacement('/torah/${widget.category}/${widget.work}/read?siman=$siman');
    VoidCallback? swipeTo(int siman, String way) => siman < 1 || siman > book.length
        ? null
        : () {
            analytics.event('page_swipe', {'reader': 'torah', 'way': way});
            go(siman);
          };

    final bar = AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(heUi ? 'סימן ${gematriya(widget.siman)}' : '${context.tr('Siman')} ${widget.siman}'),
          Text(heUi || book.titlesEn[i].isEmpty ? book.titlesHe[i] : book.titlesEn[i],
              style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
        ]),
        actions: [
          IconButton(
            tooltip: context.tr('Reader mode'),
            isSelected: _readerMode,
            icon: const Icon(Icons.chrome_reader_mode_outlined),
            selectedIcon: const Icon(Icons.chrome_reader_mode),
            onPressed: () => _readerMode ? setState(() => _readerMode = false) : _startReader(_current ?? (from ?? 1) - 1),
          ),
          IconButton(tooltip: context.tr('Text settings'), icon: const Icon(Icons.text_fields), onPressed: () => showTorahTextSettings(context)),
        ],
    );

    // Double-tap for focus mode, as in the siddur: the bars slide away.
    return Scaffold(
      body: Column(children: [
        FocusModeBars(child: bar),
        Expanded(
          child: FocusModeBody(
            child: DoubleTapListener(
              // In reader mode a double tap steps back instead.
              onDoubleTap: _readerMode ? () {} : toggleFocusMode,
              child: PageSwipe(
              onNext: _readerMode ? null : swipeTo(widget.siman + 1, 'next'),
              onPrevious: _readerMode ? null : swipeTo(widget.siman - 1, 'previous'),
              child: ReaderModeLayer(
              active: _readerMode,
              onNext: () => _step(1),
              onBackTwo: () => _step(-2),
              onExit: () => setState(() => _readerMode = false),
              child: SingleChildScrollView(
        controller: _scroll,
        padding: pagePadding(context, EdgeInsets.symmetric(horizontal: ts.gutter(MediaQuery.sizeOf(context).width, min: 16)).copyWith(top: 8, bottom: 24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var n = 1; n <= count; n++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Tap marks a se'if; holding it starts reader mode from there.
              onTap: () => setState(() => _current = _current == n - 1 ? null : n - 1),
              onLongPress: () => _startReader(n - 1),
              child: Container(
              key: _keys[n - 1],
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: _current == n - 1
                  ? BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: BorderDirectional(start: BorderSide(color: theme.colorScheme.primary, width: 3)),
                    )
                  : from != null && n >= from && n <= to
                  // The siddur's "said today" colors, for today's portion.
                  ? BoxDecoration(
                      color: colors.todayFill,
                      borderRadius: BorderRadius.circular(10),
                      border: BorderDirectional(start: BorderSide(color: colors.todayBar, width: 3)),
                    )
                  : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // English-only still shows the Hebrew where there's no translation.
                if ((lang != TorahTextLanguage.english || !hasEn(n)) && n <= he.length)
                  paragraph([
                    TextSpan(text: '${gematriya(n)} ', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
                    TextSpan(text: s.showNikud ? he[n - 1] : stripNikud(he[n - 1])),
                  ], heStyle, TextDirection.rtl),
                if (lang != TorahTextLanguage.hebrew && hasEn(n)) ...[
                  if (lang == TorahTextLanguage.both) const SizedBox(height: 6),
                  paragraph([
                    TextSpan(text: '$n. ', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
                    TextSpan(text: en[n - 1]),
                  ], enStyle, TextDirection.ltr),
                ],
              ]),
            ),
            ),
          const SizedBox(height: 8),
          Row(children: [
            if (widget.siman > 1)
              Flexible(
                child: OutlinedButton.icon(
                  onPressed: () => go(widget.siman - 1),
                  icon: const Icon(Icons.chevron_left),
                  label: Text(context.tr('Previous'), overflow: TextOverflow.ellipsis),
                ),
              ),
            const Spacer(),
            if (widget.siman < book.length)
              Flexible(
                child: FilledButton.tonalIcon(
                  onPressed: () => go(widget.siman + 1),
                  icon: const Icon(Icons.chevron_right),
                  label: Text(context.tr('Next'), overflow: TextOverflow.ellipsis),
                  iconAlignment: IconAlignment.end,
                ),
              ),
          ]),
          if (lang != TorahTextLanguage.hebrew && !hasEn(1) && count > 0)
            Text(context.tr('No English translation of this siman yet.'),
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          if (w.id == kitzur.id) ...[
            const SizedBox(height: 12),
            Text(
                book.enCredits[i] != null
                    ? context.tr('Hebrew: Torat Emet (public domain). English for this siman: {credit}. Via Sefaria.', {'credit': book.enCredits[i]})
                    : context.tr('Hebrew: Torat Emet (public domain). English: trans. Rabbi Avrohom Davis, Metsudah Publications 1996 (CC-BY). Via Sefaria.'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ],
        ]),
              ),
              ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
