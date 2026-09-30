import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hebcal/hebcal.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/l10n.dart';
import '../../core/adaptive.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/titles.dart';
import '../tehillim/tehillim_data.dart';
import '../tehillim/tehillim_progress.dart';
import '../tehillim/tehillim_reader.dart';
import 'prayer_catalog.dart';
import 'reader_screen.dart';
import 'siddur_providers.dart';
import 'today_summary.dart';

/// Siddur tab: today's services for the default nusach plus all books.
class LibraryScreen extends ConsumerWidget {
  /// Optional shortcut key (e.g. `shacharit`, `omer`) to jump straight in.
  final String? section;
  const LibraryScreen({super.key, this.section});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manifest = ref.watch(manifestProvider);
    final defaultBook = ref.watch(defaultBookProvider);
    final theme = Theme.of(context);

    if (section != null && defaultBook.hasValue) {
      final root = ref.watch(bookIndexProvider(defaultBook.value!));
      if (root.hasValue) {
        final date = ref.read(readerDaytimeDateProvider).abs();
        final id = findSectionOn(root.value!, section!, (svc) => ref.read(dayContextProvider((date, svc))));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          // Replace the `?section=` history entry, or going back from the
          // reader would land on it and jump straight back in.
          Router.neglect(context, () => context.go('/siddur'));
          if (id != null) context.push(readerPath(defaultBook.value!, id));
        });
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Siddur'))),
      body: manifest.when(
        loading: adaptiveProgress,
        error: (e, _) => Center(child: Text('$e')),
        data: (m) => ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          if (defaultBook.hasValue) _TodayServices(book: defaultBook.value!),
          const _SeasonsCard(),
          const _TehillimCard(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(context.tr('Siddurim'), style: theme.textTheme.titleMedium),
          ),
          for (final b in m.books) _BookTile(book: b, isDefault: b.title == defaultBook.value),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              context.tr("Texts from {source}, bundled for offline use. Each version's license and source are shown under Text versions.", {'source': m.source}),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ]),
      ),
    );
  }
}

class _TodayServices extends ConsumerWidget {
  final String book;
  const _TodayServices({required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final root = ref.watch(bookIndexProvider(book));
    final date = ref.watch(readerDaytimeDateProvider);
    final ctx = ref.watch(dayContextProvider((date.abs(), Service.shacharit)));
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final s = ref.watch(settingsProvider);
    if (!root.hasValue) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator.adaptive()));
    const keys = [
      ('shacharit', 'Shacharit', 'שחרית', Icons.wb_sunny_outlined),
      ('mincha', 'Mincha', 'מנחה', Icons.light_mode_outlined),
      ('maariv', 'Maariv', 'ערבית', Icons.nights_stay_outlined),
      ('omer', 'Sefirat HaOmer', 'ספירת העומר', Icons.filter_7),
      ('hallel', 'Hallel', 'הלל', Icons.celebration_outlined),
      ('kiddushLevana', 'Kiddush Levana', 'קידוש לבנה', Icons.brightness_3_outlined),
      ('birkat', 'Birkat HaMazon', 'ברכת המזון', Icons.restaurant),
      ('bedtime', 'Bedtime Shema', 'קריאת שמע על המיטה', Icons.bedtime_outlined),
    ];
    final show = {
      'omer': ctx['omer'] || ref.watch(dayContextProvider((date.abs(), Service.maariv)))['omer'],
      'hallel': ctx['hallel'],
      'kiddushLevana': ctx['kiddushLevana'],
    };
    final changes = summarizeDay(ctx, ref.watch(dayContextProvider((date.abs(), Service.mincha))), ref.watch(dayContextProvider((date.abs(), Service.maariv))))
        .where((c) => c.kind != ChangeKind.info)
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(context.tr('Today · {book}', {'book': context.prayerTitle(s, book, ref.watch(bookProvider(book)).value?.heTitle ?? book)}), style: theme.textTheme.titleMedium)),
              TextButton.icon(
                onPressed: () => context.push('/today'),
                icon: const Icon(Icons.format_list_numbered, size: 18),
                label: Text(context.tr('Full order')),
              ),
            ]),
            if (ctx.labels.isNotEmpty)
              Text((context.uiLanguage == UiLanguage.en ? ctx.labels.map(context.term) : ctx.labelsHe).join(' · '), style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (key, en, he, icon) in keys)
                if (show[key] ?? true)
                  Consumer(builder: (context, ref, _) {
                    // From another siddur when this one lacks it (Shabbat in a weekday siddur).
                    final found = ref.watch(sectionRefProvider((key, date.abs()))).value;
                    if (found == null) return const SizedBox.shrink();
                    return FilledButton.tonalIcon(
                      onPressed: () => context.push(readerPath(found.book, found.id)),
                      icon: Icon(icon, size: 18),
                      label: Text(context.prayerTitle(s, en, he)),
                      style: show.containsKey(key) ? FilledButton.styleFrom(backgroundColor: colors.chipToday) : null,
                    );
                  }),
            ]),
            if (changes.isNotEmpty) ...[
              const Divider(height: 24),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in changes)
                  Chip(
                    avatar: Icon(c.kind == ChangeKind.add ? Icons.add : Icons.remove, size: 16),
                    label: Text(context.prayerTitle(s, c.en, c.he)),
                    visualDensity: VisualDensity.compact,
                  ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

class _BookTile extends ConsumerWidget {
  final BookInfo book;
  final bool isDefault;
  const _BookTile({required this.book, required this.isDefault});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final he = book.byLanguage('he').length;
    final en = book.byLanguage('en').length;
    final other = context.prayerSubtitle(s, book.title, book.heTitle);
    final versions = context.tr('{he} Hebrew · {en} translation versions', {'he': he, 'en': en});
    return ListTile(
      leading: CircleAvatar(child: Text(book.heTitle.characters.first, style: TextStyle(fontFamily: s.hebrewFont))),
      title: Text(context.prayerTitle(s, book.title, book.heTitle),
          style: context.prayerTitleIsHebrew(s) ? TextStyle(fontFamily: s.hebrewFont) : null),
      // Bidi isolates keep a Hebrew title from reordering the English text.
      subtitle: Text(other == null ? versions : '\u2068$other\u2069 · $versions'),
      trailing: isDefault
          ? Chip(label: Text(context.tr('Default')), visualDensity: VisualDensity.compact)
          : IconButton(
              tooltip: context.tr('Make default'),
              icon: const Icon(Icons.star_outline),
              onPressed: () => ref.read(settingsProvider.notifier).update((s) => s.copyWith(defaultBook: () => book.title)),
            ),
      onTap: () => context.push('/siddur/book/${Uri.encodeComponent(book.title)}'),
    );
  }
}

/// Table of contents with today's applicability marks.
class BookScreen extends ConsumerWidget {
  final String book;
  const BookScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final root = ref.watch(bookIndexProvider(book));
    final resolver = ref.watch(resolverProvider(book));
    final date = ref.watch(readerDaytimeDateProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.prayerTitle(ref.watch(settingsProvider), book, ref.watch(bookProvider(book)).value?.heTitle ?? book)),
        actions: [
          IconButton(
            tooltip: context.tr('Text versions'),
            icon: const Icon(Icons.layers_outlined),
            onPressed: () => context.push('/siddur/book/${Uri.encodeComponent(book)}/versions'),
          ),
        ],
      ),
      body: root.when(
        loading: adaptiveProgress,
        error: (e, _) => Center(child: Text('$e')),
        data: (r) => ListView(children: [
          for (final c in r.children) _TocNode(book: book, node: c, resolver: resolver.value, date: date),
        ]),
      ),
    );
  }
}

class _TocNode extends ConsumerWidget {
  final String book;
  final SchemaNode node;
  final SiddurResolver? resolver;
  final HDate date;
  const _TocNode({required this.book, required this.node, required this.resolver, required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    var ap = Applicability.always;
    String? label;
    final r = resolver;
    if (r != null) {
      // A section without a rule of its own goes by its parts (Selichot).
      final st = sectionStatus(r, node, (svc) => ref.watch(dayContextProvider((date.abs(), svc))));
      ap = st.ap == Applicability.unknown ? Applicability.always : st.ap;
      if (ap != Applicability.always && (st.labelEn != null || st.labelHe != null)) {
        label = conditionLabel(context, ref.watch(settingsProvider), st.labelEn, st.labelHe);
      }
    }
    final titleStyle = ap == Applicability.notToday ? TextStyle(color: colors.excluded) : null;
    final subtitle = switch (ap) {
      Applicability.today => Text(label == null ? context.tr('Today') : '${context.tr('Today')} · $label',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.todayBar)),
      Applicability.notToday => Text(label == null ? context.tr('Not said today') : context.tr('Not today · {label}', {'label': label}),
          style: theme.textTheme.bodySmall?.copyWith(color: colors.excluded)),
      _ => null,
    };
    final read = IconButton(
      tooltip: context.tr('Read'),
      icon: const Icon(Icons.chrome_reader_mode_outlined),
      onPressed: () => context.push(readerPath(book, node.id)),
    );
    final title = PrayerTitleText(node.en, node.he, enStyle: titleStyle, heStyle: TextStyle(fontSize: 17, color: titleStyle?.color));
    if (readsAsOne(node)) {
      return ListTile(
        title: title,
        subtitle: subtitle,
        onTap: () => context.push(readerPath(book, node.id)),
      );
    }
    return ExpansionTile(
      title: title,
      subtitle: subtitle,
      leading: read,
      childrenPadding: const EdgeInsets.only(left: 16),
      children: [for (final c in node.children) _TocNode(book: book, node: c, resolver: resolver, date: date)],
    );
  }
}

/// Whether a section opens as a single continuous text rather than a list
/// of its parts: leaves, and sections whose parts are at most one level
/// deep (e.g. the Amidah with its blessings, including nested ones such as
/// Modim / Al Hanisim).
bool readsAsOne(SchemaNode node) => node.children.every((c) => c.children.every((g) => g.isLeaf));

/// The Holidays & Seasons siddur, with what from it is said today.
class _SeasonsCard extends ConsumerWidget {
  const _SeasonsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final hd = ref.watch(readerDaytimeDateProvider);
    final day = ref.watch(dayContextProvider((hd.abs(), Service.shacharit)));
    final night = ref.watch(dayContextProvider((hd.abs(), Service.maariv)));
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    final now = [
      for (final g in catalogGroups)
        for (final i in g.items)
          if (itemTime(i, day, night) != ItemTime.none) i,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/siddur/seasons'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.event_note, size: 30, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tr('Holidays & Seasons'), style: theme.textTheme.titleMedium),
                  now.isEmpty
                      ? Text(context.tr('Hoshanot, Lulav, Selichot, Chanukah candles and more'), style: theme.textTheme.bodySmall)
                      : Text('${context.tr('Today')}: ${now.map((i) => context.prayerTitle(s, i.en, i.he)).join(' · ')}',
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.todayBar)),
                ]),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TehillimCard extends ConsumerWidget {
  const _TehillimCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hd = ref.watch(readerDaytimeDateProvider);
    final today = monthlyPortion(hd);
    final read = ref.watch(tehillimProgressProvider.select((x) => x.read.length));
    final hebFont = ref.watch(settingsProvider.select((s) => s.hebrewFont));
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/siddur/tehillim'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Text('תהלים', style: TextStyle(fontFamily: hebFont, fontSize: 30, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tr('Tehillim'), style: theme.textTheme.titleMedium),
                  Text(
                    '${context.tr('Today')}: ${today.rangeLabel} · ${context.tr('{n} of 150 chapters read this cycle', {'n': read})}',
                    style: theme.textTheme.bodySmall,
                  ),
                ]),
              ),
              IconButton.filledTonal(
                tooltip: context.tr("Read today's Tehillim"),
                icon: const Icon(Icons.menu_book),
                onPressed: () => context.push(tehillimReadPath(today)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
