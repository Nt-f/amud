import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/adaptive.dart';
import '../../core/hebrew_text.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import 'tehillim_data.dart';
import 'tehillim_progress.dart';
import 'tehillim_reader.dart';

/// Sefer Tehillim: today's portions, all chapters, selections for special
/// needs, Psalm 119 by name, and search.
class TehillimScreen extends ConsumerWidget {
  const TehillimScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('Tehillim')),
          actions: [
            IconButton(tooltip: context.tr('Text settings'), icon: const Icon(Icons.text_fields), onPressed: () => showTehillimSettings(context)),
          ],
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: context.tr('Today')),
            Tab(text: context.tr('Chapters')),
            Tab(text: context.tr('Lists')),
            Tab(text: context.tr('By name')),
            Tab(text: context.tr('Search')),
          ]),
        ),
        body: const TabBarView(children: [_TodayTab(), _ChaptersTab(), _ListsTab(), _NameTab(), _SearchTab()]),
      ),
    );
  }
}

/// A tappable row for a portion, showing whether its chapters are read.
class PortionTile extends ConsumerWidget {
  final Portion portion;
  final IconData icon;
  final Widget? trailing;
  final bool highlight;
  const PortionTile({super.key, required this.portion, this.icon = Icons.menu_book_outlined, this.trailing, this.highlight = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(tehillimProgressProvider.select((x) => x.read));
    final chapters = {for (final p in portion.passages) if (p.whole) p.chapter};
    final done = chapters.isNotEmpty && chapters.every(read.contains);
    final colors = SiddurColors.of(context);
    final hebrewUi = context.uiLanguage != UiLanguage.en;
    return ListTile(
      leading: Icon(done ? Icons.check_circle : icon, color: done ? colors.todayBar : null),
      title: Text(hebrewUi ? portion.titleHe : context.term(portion.titleEn)),
      subtitle: Text(
        [
          if (!hebrewUi) portion.titleHe,
          '${context.tr('Tehillim')} ${portion.rangeLabel}',
        ].join(' · '),
      ),
      tileColor: highlight ? colors.todayFill : null,
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: () => context.push(tehillimReadPath(portion)),
    );
  }
}

class _TodayTab extends ConsumerWidget {
  const _TodayTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hd = ref.watch(readerDaytimeDateProvider);
    final s = ref.watch(settingsProvider);
    final progress = ref.watch(tehillimProgressProvider);
    final theme = Theme.of(context);
    final weekday = hd.greg().weekday % 7;
    final nextUnread = [for (var c = 1; c <= 150; c++) if (!progress.read.contains(c)) c].firstOrNull;
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(context.tr('Your progress through Sefer Tehillim'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progress.read.length / 150, minHeight: 8, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 6),
            Text(
              context.tr('{n} of 150 chapters read this cycle', {'n': progress.read.length}) +
                  (progress.completions > 0 ? ' · ${context.tr('{n} completions', {'n': progress.completions})}' : ''),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (progress.lastChapter != null)
                FilledButton.icon(
                  onPressed: () => context.push(tehillimReadPath(chapterPortion(progress.lastChapter!))),
                  icon: const Icon(Icons.bookmark_outline),
                  label: Text(context.tr('Continue at Psalm {n}', {'n': progress.lastChapter})),
                ),
              if (nextUnread != null && nextUnread != progress.lastChapter)
                FilledButton.tonalIcon(
                  onPressed: () => context.push(tehillimReadPath(chapterPortion(nextUnread))),
                  icon: const Icon(Icons.skip_next),
                  label: Text(context.tr('Next unread: Psalm {n}', {'n': nextUnread})),
                ),
              if (progress.read.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    if (await showAdaptiveConfirm(context,
                        title: context.tr('Start a new cycle?'), message: context.tr('Clears the chapters marked as read.'))) {
                      ref.read(tehillimProgressProvider.notifier).resetCycle();
                    }
                  },
                  child: Text(context.tr('Reset')),
                ),
            ]),
          ]),
        ),
      ),
      _Header(context.tr('Today')),
      if (ledavidSeason(hd, throughShminiAtzeret: s.minhagim.ledavidThroughShminiAtzeret, il: s.location.il))
        const PortionTile(portion: ledavid, icon: Icons.brightness_5_outlined, highlight: true),
      PortionTile(portion: monthlyPortion(hd), icon: Icons.calendar_month_outlined),
      PortionTile(portion: weeklyPortion(weekday), icon: Icons.view_week_outlined),
      PortionTile(portion: shirShelYom(weekday), icon: Icons.music_note_outlined),
      _Header(context.tr('The five books')),
      for (var b = 1; b <= 5; b++) PortionTile(portion: bookPortion(b), icon: Icons.book_outlined),
      _Header(context.tr('Weekly cycle')),
      for (var d = 0; d < 7; d++) PortionTile(portion: weeklyPortion(d), icon: Icons.view_week_outlined, highlight: d == weekday),
    ]);
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

class _ChaptersTab extends ConsumerWidget {
  const _ChaptersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(tehillimProgressProvider.select((x) => x.read));
    final hebFont = ref.watch(settingsProvider.select((s) => s.hebrewFont));
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text(context.tr('Tap to read · long-press to mark as read'), style: theme.textTheme.bodySmall),
        ),
      ),
      for (var b = 1; b <= 5; b++) ...[
        SliverToBoxAdapter(child: _Header('${bookPortion(b).titleHe} · ${context.tr(bookPortion(b).titleEn)}')),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 64, mainAxisSpacing: 6, crossAxisSpacing: 6),
            itemCount: tehillimBooks[b - 1].$2 - tehillimBooks[b - 1].$1 + 1,
            itemBuilder: (c, i) {
              final ch = tehillimBooks[b - 1].$1 + i;
              final done = read.contains(ch);
              return Material(
                color: done ? colors.todayFill : theme.colorScheme.surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: done ? colors.todayBar : Colors.transparent),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => context.push(tehillimReadPath(chapterPortion(ch))),
                  onLongPress: () {
                    final n = ref.read(tehillimProgressProvider.notifier);
                    done ? n.unmark(ch) : n.markRead([ch]);
                  },
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(hebrewNumeral(ch).replaceAll(RegExp('[׳״]'), ''), style: TextStyle(fontFamily: hebFont, fontSize: 18, fontWeight: FontWeight.w600)),
                    Text('$ch', style: theme.textTheme.labelSmall),
                  ]),
                ),
              );
            },
          ),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ]);
  }
}

class _ListsTab extends ConsumerWidget {
  const _ListsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(tehillimProgressProvider.select((x) => x.lists));
    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
      _Header(context.tr('My lists')),
      if (mine.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Text(context.tr('Make your own selection, e.g. for someone who needs a refuah.'), style: theme.textTheme.bodySmall),
        ),
      for (final l in mine)
        PortionTile(
          portion: l,
          icon: Icons.bookmark_outline,
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') {
                final p = await _editList(context, l);
                if (p != null) ref.read(tehillimProgressProvider.notifier).saveList(p, replacing: l);
              } else {
                ref.read(tehillimProgressProvider.notifier).deleteList(l);
              }
            },
            itemBuilder: (c) => [
              PopupMenuItem(value: 'edit', child: Text(context.tr('Edit'))),
              PopupMenuItem(value: 'delete', child: Text(context.tr('Remove'))),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: OutlinedButton.icon(
          onPressed: () async {
            final p = await _editList(context, null);
            if (p != null) ref.read(tehillimProgressProvider.notifier).saveList(p);
          },
          icon: const Icon(Icons.add),
          label: Text(context.tr('New list')),
        ),
      ),
      _Header(context.tr('For special needs')),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(context.tr('Selections commonly said; customs vary.'), style: theme.textTheme.bodySmall),
      ),
      for (final o in occasions)
        PortionTile(
          portion: o,
          icon: Icons.volunteer_activism_outlined,
          trailing: IconButton(
            tooltip: context.tr('Copy to my lists'),
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () {
              ref.read(tehillimProgressProvider.notifier).saveList(Portion(o.titleEn, o.titleHe, o.passages));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Copied to my lists'))));
            },
          ),
        ),
    ]);
  }
}

Future<Portion?> _editList(BuildContext context, Portion? existing) async {
  final name = TextEditingController(text: existing?.titleEn ?? '');
  final chapters = TextEditingController(text: existing?.passages.join(', ') ?? '');
  String? error;
  return showDialog<Portion>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(c.tr(existing == null ? 'New list' : 'Edit')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: c.tr('Name'))),
          TextField(
            controller: chapters,
            decoration: InputDecoration(labelText: c.tr('Chapters'), hintText: '20, 6, 30, 119:1-8', errorText: error),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(MaterialLocalizations.of(c).cancelButtonLabel)),
          FilledButton(
            onPressed: () {
              try {
                final ps = Portion.decode(chapters.text.replaceAll(' ', '').replaceAll('–', '-'));
                if (ps.isEmpty || ps.any((p) => p.chapter < 1 || p.chapter > 150)) throw const FormatException();
                final title = name.text.trim().isEmpty ? c.tr('My list') : name.text.trim();
                Navigator.pop(c, Portion(title, title, ps));
              } catch (_) {
                setState(() => error = c.tr('Use chapter numbers 1–150, e.g. 20, 6, 119:1-8'));
              }
            },
            child: Text(c.tr('Save')),
          ),
        ],
      ),
    ),
  );
}

class _NameTab extends ConsumerStatefulWidget {
  const _NameTab();

  @override
  ConsumerState<_NameTab> createState() => _NameTabState();
}

class _NameTabState extends ConsumerState<_NameTab> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  bool _neshamah = false;

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hebFont = ref.watch(settingsProvider.select((s) => s.hebrewFont));
    final portion = nameStanzas(_name.text.trim(), neshamah: _neshamah);
    final age = int.tryParse(_age.text.trim());
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
      Text(context.tr('Psalm 119 by name'), style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(context.tr('Psalm 119 has a stanza of eight verses for each Hebrew letter. Say the stanzas that spell a name, e.g. for someone who is ill or in memory of the departed.'),
          style: theme.textTheme.bodySmall),
      const SizedBox(height: 12),
      TextField(
        controller: _name,
        textDirection: TextDirection.rtl,
        style: TextStyle(fontFamily: hebFont, fontSize: 22),
        decoration: InputDecoration(labelText: context.tr('Hebrew name'), hintText: 'משה בן שרה'),
        onChanged: (_) => setState(() {}),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(context.tr('Add נשמה (in memory)')),
        value: _neshamah,
        onChanged: (v) => setState(() => _neshamah = v),
      ),
      if (portion.passages.isNotEmpty) ...[
        Wrap(spacing: 6, runSpacing: 6, textDirection: TextDirection.rtl, children: [
          for (final p in portion.passages)
            Chip(
              label: Text('${stanzaLetter(p)}  ${p.from}–${p.to}', style: TextStyle(fontFamily: hebFont)),
              visualDensity: VisualDensity.compact,
            ),
        ]),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => context.push(tehillimReadPath(portion)),
          icon: const Icon(Icons.menu_book),
          label: Text(context.tr('Read {n} stanzas', {'n': portion.passages.length})),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () {
            ref.read(tehillimProgressProvider.notifier).saveList(portion);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Copied to my lists'))));
          },
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(context.tr('Save to my lists')),
        ),
      ],
      const Divider(height: 40),
      Text(context.tr('Your personal psalm'), style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(context.tr('Many say the psalm matching the year of life they are in: their age plus one.'), style: theme.textTheme.bodySmall),
      TextField(
        controller: _age,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: context.tr('Age')),
        onChanged: (_) => setState(() {}),
      ),
      if (age != null && age >= 0 && age < 150) ...[
        const SizedBox(height: 12),
        PortionTile(portion: chapterPortion(age + 1), icon: Icons.person_outline),
      ],
    ]);
  }
}

class _SearchTab extends ConsumerStatefulWidget {
  const _SearchTab();

  @override
  ConsumerState<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<_SearchTab> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(tehillimProvider);
    final hebFont = ref.watch(settingsProvider.select((s) => s.hebrewFont));
    final theme = Theme.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: context.tr('Search Hebrew or English')),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      Expanded(
        child: data.when(
          loading: adaptiveProgress,
          error: (e, _) => Center(child: Text('$e')),
          data: (t) {
            final hits = searchTehillim(t, _q);
            if (_q.trim().length >= 2 && hits.isEmpty) return Center(child: Text(context.tr('No matches')));
            return ListView.builder(
              itemCount: hits.length,
              itemBuilder: (c, i) {
                final h = hits[i];
                final he = RegExp('[א-ת]').hasMatch(h.text);
                return ListTile(
                  title: Text(h.text,
                      textDirection: he ? TextDirection.rtl : TextDirection.ltr,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: he ? TextStyle(fontFamily: hebFont, fontSize: 18) : null),
                  subtitle: Text('${context.tr('Psalm {n}', {'n': h.chapter})}:${h.verse}', style: theme.textTheme.bodySmall),
                  onTap: () => context.push(tehillimReadPath(Portion('Psalm ${h.chapter}', 'מזמור ${hebrewNumeral(h.chapter)}', [Passage(h.chapter)]))),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}
