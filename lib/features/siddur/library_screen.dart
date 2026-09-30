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
import '../../core/split_row.dart';
import '../tehillim/tehillim_data.dart';
import '../tehillim/tehillim_progress.dart';
import '../tehillim/tehillim_reader.dart';
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
        final shabbat = ref.watch(dayContextProvider((ref.read(readerDaytimeDateProvider).abs(), Service.shacharit)))['shabbat'];
        final id = findSection(root.value!, section!, shabbat: shabbat);
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
    if (!root.hasValue) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator.adaptive()));
    final r = root.value!;
    final shabbat = ctx['shabbat'];
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
            Text(context.tr('Today · {book}', {'book': context.term(book)}), style: theme.textTheme.titleMedium),
            if (ctx.labels.isNotEmpty)
              Text((context.uiLanguage == UiLanguage.en ? ctx.labels.map(context.term) : ctx.labelsHe).join(' · '), style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (key, en, _, icon) in keys)
                if (show[key] ?? true)
                  Builder(builder: (context) {
                    final id = findSection(r, key, shabbat: shabbat);
                    if (id == null) return const SizedBox.shrink();
                    return FilledButton.tonalIcon(
                      onPressed: () => context.push(readerPath(book, id)),
                      icon: Icon(icon, size: 18),
                      label: Text(context.tr(en)),
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
                    label: Text(context.term(c.en)),
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
    final hebFont = ref.watch(settingsProvider.select((s) => s.hebrewFont));
    final he = book.byLanguage('he').length;
    final en = book.byLanguage('en').length;
    return ListTile(
      leading: CircleAvatar(child: Text(book.heTitle.characters.first, style: TextStyle(fontFamily: hebFont))),
      title: Text(context.uiLanguage == UiLanguage.en ? context.term(book.title) : book.heTitle),
      // Bidi isolates keep the Hebrew title from reordering the English text.
      subtitle: Text('\u2067${book.heTitle}\u2069 · ${context.tr('{he} Hebrew · {en} translation versions', {'he': he, 'en': en})}'),
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
        title: Text(context.uiLanguage == UiLanguage.en ? context.term(book) : (ref.watch(bookProvider(book)).value?.heTitle ?? book)),
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
    final hebFont = ref.watch(settingsProvider.select((s) => s.hebrewFont));
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    Applicability ap = Applicability.always;
    String? label;
    final rule = resolver?.sectionRuleFor(node);
    if (rule != null && rule.when != 'true') {
      final svc = SiddurResolver.serviceFor(node, Service.shacharit);
      final ok = Condition.parse(rule.when).eval(ref.watch(dayContextProvider((date.abs(), svc))).env);
      ap = ok ? Applicability.today : Applicability.notToday;
      label = conditionLabel(context, ref.watch(settingsProvider), rule.labelEn, rule.labelHe);
    }
    final titleStyle = ap == Applicability.notToday ? TextStyle(color: colors.excluded) : null;
    final hebrewUi = context.uiLanguage != UiLanguage.en;
    final trailingHe = Text(node.he, textDirection: TextDirection.rtl, style: TextStyle(fontFamily: hebFont, fontSize: 17, color: titleStyle?.color));
    final subtitle = label == null
        ? null
        : Text(ap == Applicability.today ? '${context.tr('Today')} · $label' : context.tr('Not today · {label}', {'label': label}),
            style: theme.textTheme.bodySmall?.copyWith(color: ap == Applicability.today ? colors.todayBar : colors.excluded));
    final read = IconButton(
      tooltip: context.tr('Read'),
      icon: const Icon(Icons.chrome_reader_mode_outlined),
      onPressed: () => context.push(readerPath(book, node.id)),
    );
    final title = hebrewUi ? trailingHe : SplitRow(children: [Text(context.term(node.en), style: titleStyle), trailingHe]);
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
