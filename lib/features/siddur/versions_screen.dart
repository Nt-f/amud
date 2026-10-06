import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:siddur_engine/siddur_engine.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../core/adaptive.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import 'siddur_providers.dart';

class VersionsScreen extends ConsumerWidget {
  final String book;
  const VersionsScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(bookProvider(book));
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('Text versions')),
          bottom: TabBar(tabs: [Tab(text: context.tr('Hebrew')), Tab(text: context.tr('Translations'))]),
        ),
        body: b.when(
          loading: adaptiveProgress,
          error: (e, _) => Center(child: Text('$e')),
          data: (info) => TabBarView(children: [
            _VersionList(book: info, lang: 'he'),
            _VersionList(book: info, lang: 'en'),
          ]),
        ),
      ),
    );
  }
}

class _VersionList extends ConsumerWidget {
  final BookInfo book;
  final String lang;
  const _VersionList({required this.book, required this.lang});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(versionOrderProvider((book.title, lang)));
    final s = ref.watch(settingsProvider);
    final avail = availableVersions(book, lang, s);
    final sources = ref.watch(corpusProvider(book.title)).value?.editions[lang]?.sources ?? const <CorpusSource>[];
    final theme = Theme.of(context);
    return order.when(
      loading: adaptiveProgress,
      error: (e, _) => Text('$e'),
      data: (selected) {
        void save(List<String> list) => ref.read(settingsProvider.notifier).update((x) {
              final key = lang == 'he' ? x.hebrewVersions : x.translationVersions;
              final m = {...key, book.title: list};
              return lang == 'he' ? x.copyWith(hebrewVersions: m) : x.copyWith(translationVersions: m);
            });
        final byTitle = {for (final v in avail) v.versionTitle: v};
        final unselected = avail.where((v) => !selected.contains(v.versionTitle)).toList();
        return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'For each section the first version (top to bottom) that contains it is shown. Drag to reorder.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (a, b) {
              final l = [...selected];
              if (b > a) b--;
              l.insert(b, l.removeAt(a));
              save(l);
            },
            children: [
              for (var i = 0; i < selected.length; i++)
                if (byTitle[selected[i]] != null)
                  _VersionTile(
                    key: ValueKey(selected[i]),
                    v: byTitle[selected[i]]!,
                    sources: sources,
                    selected: true,
                    index: i,
                    onToggle: () => save([...selected]..remove(selected[i])),
                  ),
            ],
          ),
          if (unselected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(context.tr('Available'), style: theme.textTheme.titleSmall),
            ),
          for (final v in unselected)
            _VersionTile(key: ValueKey(v.versionTitle), v: v, sources: sources, selected: false, onToggle: () => save([...selected, v.versionTitle])),
        ]);
      },
    );
  }
}

class _VersionTile extends StatelessWidget {
  final VersionInfo v;

  /// What Amud's own text was edited from, credited on its tile.
  final List<CorpusSource> sources;
  final bool selected;
  final int? index;
  final VoidCallback onToggle;
  const _VersionTile(
      {super.key, required this.v, this.sources = const [], required this.selected, this.index, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final licenseColor = v.openLicense ? Colors.green : Colors.orange;
    return ListTile(
      leading: Checkbox.adaptive(value: selected, onChanged: (_) => onToggle()),
      title: Text(v.versionTitle.trim(), maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (v.isCorpus && sources.isNotEmpty)
          Text(
            context.tr('Edited by Amud from {sources}', {
              'sources': sources.map((x) => '${x.version.trim()} (${x.license})').join('; '),
            }),
            style: theme.textTheme.bodySmall,
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(border: Border.all(color: licenseColor), borderRadius: BorderRadius.circular(6)),
          child: Text(v.license, style: theme.textTheme.labelSmall?.copyWith(color: licenseColor)),
        ),
        Text('${v.segments} segments', style: theme.textTheme.bodySmall),
        if (v.languageTag != null) Text('[${v.languageTag}]', style: theme.textTheme.bodySmall),
        if (v.source != null && v.source!.startsWith('http'))
          InkWell(
            onTap: () => launchUrl(Uri.parse(v.source!)),
            child: Text('source', style: theme.textTheme.bodySmall?.copyWith(decoration: TextDecoration.underline)),
          ),
      ]),
      trailing: index != null ? ReorderableDragStartListener(index: index!, child: const Icon(Icons.drag_handle)) : null,
    );
  }
}
