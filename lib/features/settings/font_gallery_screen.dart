import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/fonts.dart';
import '../../core/settings.dart';

const _samples = [
  ('Blessing', 'בָּרוּךְ אַתָּה יְהֹוָה אֱלֹהֵֽינוּ מֶֽלֶךְ הָעוֹלָם'),
  ('Te\'amim', 'שְׁמַ֖ע יִשְׂרָאֵ֑ל יְהֹוָ֥ה אֱלֹהֵ֖ינוּ יְהֹוָ֥ה ׀ אֶחָֽד׃'),
  ('Alef-bet', 'אבגדהוזחטיכךלמםנןסעפףצץקרשת'),
  ('Unpointed', 'ברוך אתה ה׳ אלהינו מלך העולם'),
];

/// Browse, preview and choose among every open-licensed Hebrew font the
/// app knows about. Downloadable fonts load as they scroll into view.
///
/// Chooses the siddur's font unless [selectedFont] and [chooseFont] point
/// it at another setting (the Torah tab's).
class FontGalleryScreen extends ConsumerStatefulWidget {
  final ProviderListenable<String>? selectedFont;
  final void Function(WidgetRef ref, String family)? chooseFont;
  const FontGalleryScreen({super.key, this.selectedFont, this.chooseFont});

  @override
  ConsumerState<FontGalleryScreen> createState() => _FontGalleryScreenState();
}

class _FontGalleryScreenState extends ConsumerState<FontGalleryScreen> {
  FontCategory? _category;
  bool _tropOnly = false;
  String _sample = _samples.first.$2;
  final _custom = TextEditingController();
  String _query = '';
  double _size = 26;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(fontsProvider);
    final selected = _current(watch: true);
    final theme = Theme.of(context);
    final all = [...fontCatalog, for (final f in user) FontEntry(f.family, f.label)];
    final q = _query.toLowerCase();
    final fonts = [
      for (final f in all)
        if ((_category == null || f.category == _category) && (!_tropOnly || f.teamim) && (q.isEmpty || f.label.toLowerCase().contains(q))) f,
    ];
    final sample = _custom.text.trim().isEmpty ? _sample : _custom.text.trim();

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Hebrew fonts'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _upload,
        icon: const Icon(Icons.upload_file),
        label: Text(context.tr('Upload font')),
      ),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: context.tr('Search fonts'), isDense: true),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (label, text) in _samples)
                  ChoiceChip(
                    label: Text(context.tr(label)),
                    selected: _custom.text.trim().isEmpty && _sample == text,
                    onSelected: (_) => setState(() {
                      _custom.clear();
                      _sample = text;
                    }),
                  ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: _custom,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(hintText: context.tr('Or type your own preview text…'), isDense: true),
                onChanged: (_) => setState(() {}),
              ),
              Row(children: [
                const Icon(Icons.format_size, size: 18),
                Expanded(
                  child: Slider.adaptive(value: _size, min: 16, max: 48, onChanged: (v) => setState(() => _size = v)),
                ),
              ]),
              SizedBox(
                height: 40,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(context.tr("With te'amim")),
                      selected: _tropOnly,
                      onSelected: (v) => setState(() => _tropOnly = v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(context.tr('All ({n})', {'n': all.length})),
                      selected: _category == null,
                      onSelected: (_) => setState(() => _category = null),
                    ),
                  ),
                  for (final c in FontCategory.values)
                    if (all.any((f) => f.category == c))
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(context.tr(c.label)),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                        ),
                      ),
                ]),
              ),
              const SizedBox(height: 4),
              Text(
                'Bundled fonts work offline. Others download from Google Fonts to preview, and are saved on this device once chosen.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
          sliver: SliverList.builder(
            itemCount: fonts.length,
            itemBuilder: (c, i) => _FontCard(
              key: ValueKey(fonts[i].family),
              font: fonts[i],
              sample: sample,
              size: _size,
              selected: fonts[i].family == selected,
              onSelect: () => _select(fonts[i]),
              onDelete: fonts[i].category == FontCategory.user ? () => _delete(fonts[i]) : null,
            ),
          ),
        ),
      ]),
    );
  }

  String _current({bool watch = false}) {
    final p = widget.selectedFont ?? settingsProvider.select((s) => s.hebrewFont);
    return watch ? ref.watch(p) : ref.read(p);
  }

  void _choose(String family) => widget.chooseFont != null
      ? widget.chooseFont!(ref, family)
      : ref.read(settingsProvider.notifier).update((x) => x.copyWith(hebrewFont: family));

  Future<void> _select(FontEntry f) async {
    if (f.remote) {
      await ref.read(remoteFontsProvider.notifier).save(f);
      if (ref.read(remoteFontsProvider)[f.family] != FontLoadState.ready) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr("Couldn't download {font}", {'font': f.label}))));
        return;
      }
    }
    _choose(f.family);
  }

  Future<void> _delete(FontEntry f) async {
    final n = ref.read(settingsProvider.notifier);
    if (ref.read(settingsProvider).hebrewFont == f.family) n.update((x) => x.copyWith(hebrewFont: builtInFonts.first.family));
    if (_current() == f.family) _choose(builtInFonts.first.family);
    await ref.read(fontsProvider.notifier).remove(f.family);
  }

  Future<void> _upload() async {
    try {
      final added = await ref.read(fontsProvider.notifier).pickAndImport();
      if (added.isNotEmpty) _choose(added.last.family);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _FontCard extends ConsumerStatefulWidget {
  final FontEntry font;
  final String sample;
  final double size;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onDelete;
  const _FontCard({
    super.key,
    required this.font,
    required this.sample,
    required this.size,
    required this.selected,
    required this.onSelect,
    this.onDelete,
  });

  @override
  ConsumerState<_FontCard> createState() => _FontCardState();
}

class _FontCardState extends ConsumerState<_FontCard> {
  @override
  void initState() {
    super.initState();
    // Built lazily by the list, so only fonts scrolled into view download.
    Future.microtask(() => ref.read(remoteFontsProvider.notifier).ensure(widget.font));
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.font;
    final theme = Theme.of(context);
    final state = f.remote ? ref.watch(remoteFontsProvider)[f.family] : FontLoadState.ready;
    final meta = [
      context.tr(f.category.label),
      if (f.license.isNotEmpty) f.license,
      if (f.designer != null) f.designer!,
      if (f.builtIn) context.tr('Offline') else if (f.remote) context.tr('Download'),
      context.tr(f.teamim ? "Te'amim ✓" : f.nikud ? 'Nikud only' : 'No nikud'),
    ].join(' · ');

    final Widget preview = switch (state) {
      FontLoadState.ready => Text(
          widget.sample,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          style: TextStyle(fontFamily: f.family, fontSize: widget.size, height: 1.6),
        ),
      FontLoadState.error => Row(children: [
          Icon(Icons.cloud_off, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(context.tr('Couldn\'t load preview'))),
          TextButton(
            onPressed: () => ref.read(remoteFontsProvider.notifier).ensure(f),
            child: Text(context.tr('Retry')),
          ),
        ]),
      _ => SizedBox(height: widget.size * 1.6, child: const Center(child: LinearProgressIndicator())),
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: widget.selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant, width: widget.selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onSelect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.label, style: theme.textTheme.titleSmall),
                  Text(meta, style: theme.textTheme.bodySmall),
                  if (f.note != null) Text(context.tr(f.note!), style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                ]),
              ),
              if (widget.selected) Icon(Icons.check_circle, color: theme.colorScheme.primary),
              if (widget.onDelete != null)
                IconButton(tooltip: context.tr('Remove'), icon: const Icon(Icons.delete_outline), onPressed: widget.onDelete),
            ]),
            const SizedBox(height: 6),
            Padding(padding: const EdgeInsets.only(right: 8), child: preview),
          ]),
        ),
      ),
    );
  }
}
