import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hebcal/hebcal.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/analytics.dart';
import '../../core/focus_mode.dart';
import '../../core/hebrew_text.dart';
import '../../core/l10n.dart';
import '../../core/page_swipe.dart';
import '../../core/search.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/typeset/typeset.dart';
import '../home/today.dart';
import '../search/search_sources.dart';
import 'torah_library.dart';
import 'torah_settings.dart';

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
          ? ListView(padding: const EdgeInsets.only(bottom: 32), children: [
              SearchResults(query: query.raw, hebrewFont: ref.watch(torahSettingsProvider).hebrewFont, groups: torahResults(context, ref, query)),
            ])
          : ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 32), children: [
        DownloadPanel(works: all, label: context.tr('Download everything')),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(Icons.straighten, color: Theme.of(context).colorScheme.primary),
            title: Text(context.tr('Shiurim')),
            subtitle: Text(context.tr("Kezayis, revi'is, amah and every other measure, by each posek")),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/shiurim'),
          ),
        ),
        for (final c in torahCategories)
          _WorkTile(
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
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 32), children: [
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
        title: Text(title,
            style: available ? null : const TextStyle(decoration: TextDecoration.lineThrough, decorationThickness: 2)),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: available
            ? const Icon(Icons.chevron_right)
            : Chip(
                avatar: const Icon(Icons.construction, size: 16),
                label: Text(context.tr('Work in progress')),
                visualDensity: VisualDensity.compact,
              ),
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
    final theme = Theme.of(context);
    final missing = [for (final w in works) if (states[w.id] is! Downloaded) w];
    final downloading = works.any((w) => states[w.id] is Downloading);
    final failed = [for (final w in works) if (states[w.id] case DownloadFailed(:final error)) error];
    final estimate = missing.fold<int>(0, (n, w) => n + w.estimatedBytes);
    if (missing.isEmpty && !downloading) return const SizedBox.shrink();

    final Widget body;
    if (downloading) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.tr('Downloading from Sefaria…'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 10),
        const LinearProgressIndicator(),
      ]);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20)),
          icon: const Icon(Icons.download),
          label: Text('$label · ≈ ${formatBytes(estimate)}', textAlign: TextAlign.center),
          onPressed: () => lib.downloadAll(missing),
        ),
        const SizedBox(height: 6),
        Text(
          failed.isNotEmpty
              ? context.tr("Download failed. Check your connection and try again.")
              : context.tr('Downloads from Sefaria once, then works offline.'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: failed.isNotEmpty ? theme.colorScheme.error : theme.colorScheme.outline),
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

/// Today's Kitzur Shulchan Aruch Yomi; opens in the downloaded Kitzur, or
/// on Sefaria when it isn't downloaded.
class KitzurYomiTile extends ConsumerWidget {
  const KitzurYomiTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todaySnapshotProvider);
    final il = ref.watch(settingsProvider.select((s) => s.location.il));
    final downloaded = ref.watch(torahLibraryProvider.select((m) => m[kitzur.id] is Downloaded));
    final theme = Theme.of(context);
    KitzurShulchanAruchEvent? ev;
    try {
      ev = DailyLearning.lookup('kitzurShulchanAruch', t.hdate, il) as KitzurShulchanAruchEvent?;
    } catch (_) {}
    final target = ev == null ? null : kitzurTarget(ev);
    final url = ev?.url();
    final inApp = downloaded && target != null;
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
        trailing: ev == null ? null : Icon(inApp ? Icons.chevron_right : Icons.open_in_new, color: theme.colorScheme.onPrimaryContainer),
        onTap: ev == null
            ? null
            : inApp
                ? () => context.push(
                    '/torah/halacha/kitzur/read?siman=${target.siman}&from=${target.from}${target.to == null ? '' : '&to=${target.to}'}')
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
          ? ListView(padding: const EdgeInsets.only(bottom: 32), children: [
              SearchResults(query: query.raw, hebrewFont: s.hebrewFont, groups: torahResults(context, ref, query, only: w.id)),
            ])
          : ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 32), children: [
        DownloadPanel(works: [w], label: context.tr('Download')),
        if (w.id == kitzur.id) const KitzurYomiTile(),
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
  final _firstKey = GlobalKey();
  bool _scrolled = false;

  void _scrollToHighlight() {
    if (_scrolled || widget.from == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _firstKey.currentContext;
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
              onDoubleTap: toggleFocusMode,
              child: PageSwipe(
              onNext: swipeTo(widget.siman + 1, 'next'),
              onPrevious: swipeTo(widget.siman - 1, 'previous'),
              child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: ts.gutter(MediaQuery.sizeOf(context).width, min: 16)).copyWith(top: 8, bottom: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var n = 1; n <= count; n++)
            Container(
              key: n == from ? _firstKey : null,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: from != null && n >= from && n <= to
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
      ]),
    );
  }
}
