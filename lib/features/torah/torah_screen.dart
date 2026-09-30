import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hebcal/hebcal.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/hebrew_text.dart';
import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../home/today.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Torah'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 32), children: [
        DownloadPanel(works: all, label: context.tr('Download everything')),
        const SizedBox(height: 8),
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
      appBar: AppBar(title: Text(_name(context, c.en, c.he))),
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

/// A prominent download button for [works] showing the estimated size;
/// shows progress while downloading and the stored size afterwards.
class DownloadPanel extends ConsumerWidget {
  final List<TorahWork> works;
  final String label;

  /// Offer to delete the download (on a single book's page).
  final bool allowDelete;
  const DownloadPanel({super.key, required this.works, required this.label, this.allowDelete = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final states = ref.watch(torahLibraryProvider);
    final lib = ref.read(torahLibraryProvider.notifier);
    final theme = Theme.of(context);
    final missing = [for (final w in works) if (states[w.id] is! Downloaded) w];
    final downloading = works.any((w) => states[w.id] is Downloading);
    final failed = [for (final w in works) if (states[w.id] case DownloadFailed(:final error)) error];
    final stored = works.fold<int>(0, (n, w) => n + switch (states[w.id]) { Downloaded(:final bytes) => bytes, _ => 0 });
    final estimate = missing.fold<int>(0, (n, w) => n + w.estimatedBytes);

    final Widget body;
    if (downloading) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.tr('Downloading from Sefaria…'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 10),
        const LinearProgressIndicator(),
      ]);
    } else if (missing.isEmpty) {
      body = Row(children: [
        Icon(Icons.offline_pin, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('Available offline'), style: theme.textTheme.titleSmall),
            Text(formatBytes(stored), style: theme.textTheme.bodySmall),
          ]),
        ),
        if (allowDelete)
          TextButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: Text(context.tr('Remove')),
            onPressed: () async {
              for (final w in works) {
                await lib.delete(w);
              }
            },
          ),
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
      color: theme.colorScheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(Icons.today, color: theme.colorScheme.onTertiaryContainer),
        title: Text(context.tr('Kitzur Yomi'),
            style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onTertiaryContainer, fontWeight: FontWeight.w600)),
        subtitle: Text(ev == null ? context.tr('No reading today') : ev.renderBrief(context.hebcalLocale),
            style: TextStyle(color: theme.colorScheme.onTertiaryContainer)),
        trailing: ev == null ? null : Icon(inApp ? Icons.chevron_right : Icons.open_in_new, color: theme.colorScheme.onTertiaryContainer),
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
    final theme = Theme.of(context);
    final he = context.uiLanguage != UiLanguage.en;
    return Scaffold(
      appBar: AppBar(title: Text(_name(context, w.en, w.he)), actions: [
        IconButton(tooltip: context.tr('Text settings'), icon: const Icon(Icons.text_fields), onPressed: () => showTorahTextSettings(context)),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 32), children: [
        DownloadPanel(works: [w], label: context.tr('Download'), allowDelete: true),
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

class _TorahReaderScreenState extends ConsumerState<TorahReaderScreen> {
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

    void go(int siman) => context.pushReplacement('/torah/${widget.category}/${widget.work}/read?siman=$siman');

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(heUi ? 'סימן ${gematriya(widget.siman)}' : '${context.tr('Siman')} ${widget.siman}'),
          Text(heUi || book.titlesEn[i].isEmpty ? book.titlesHe[i] : book.titlesEn[i],
              style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
        ]),
        actions: [
          IconButton(tooltip: context.tr('Text settings'), icon: const Icon(Icons.text_fields), onPressed: () => showTorahTextSettings(context)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var n = 1; n <= count; n++)
            Container(
              key: n == from ? _firstKey : null,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: from != null && n >= from && n <= to
                  ? BoxDecoration(color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(10))
                  : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // English-only still shows the Hebrew where there's no translation.
                if ((lang != TorahTextLanguage.english || !hasEn(n)) && n <= he.length)
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${gematriya(n)} ', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
                      TextSpan(text: s.showNikud ? he[n - 1] : stripNikud(he[n - 1])),
                    ]),
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontFamily: s.hebrewFont, fontSize: 21 * s.textScale, height: 1.6, color: theme.colorScheme.onSurface),
                  ),
                if (lang != TorahTextLanguage.hebrew && hasEn(n)) ...[
                  if (lang == TorahTextLanguage.both) const SizedBox(height: 6),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '$n. ', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
                      TextSpan(text: en[n - 1]),
                    ]),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontFamily: s.latinFont, fontSize: 16 * s.textScale, height: 1.5, color: theme.colorScheme.onSurface),
                  ),
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
    );
  }
}
