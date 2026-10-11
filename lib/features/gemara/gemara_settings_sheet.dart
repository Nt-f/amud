import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adaptive.dart';
import '../../core/l10n.dart';
import '../torah/torah_settings.dart';
import 'gemara_reader_screen.dart';
import 'gemara_settings.dart';
import 'study_book.dart';

/// A server address as typed, with http:// added when no scheme was given
/// ("localhost:8787" → "http://localhost:8787").
String serverAddress(String typed) {
  final v = typed.trim();
  if (v.isEmpty || v.contains('://')) return v;
  return 'http://$v';
}

/// The study reader's settings for a kind of text (from [book], or [kind]).
/// Only what applies to it shows: the printed page and its taps are the
/// Bavli's, the word-by-word server isn't the Kitzur's. Font, size and
/// vowels are shared with the rest of the Torah tab (one tap away).
Future<void> showGemaraSettings(BuildContext context, {StudyBook? book, StudyKind? kind}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _GemaraSettingsSheet(kind: book?.kind ?? kind ?? StudyKind.bavli),
    );

class _GemaraSettingsSheet extends ConsumerStatefulWidget {
  final StudyKind kind;
  const _GemaraSettingsSheet({required this.kind});

  @override
  ConsumerState<_GemaraSettingsSheet> createState() => _GemaraSettingsSheetState();
}

class _GemaraSettingsSheetState extends ConsumerState<_GemaraSettingsSheet> {
  late final TextEditingController _server = TextEditingController(text: ref.read(gemaraSettingsProvider).interlinearServer);

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(gemaraSettingsProvider);
    final n = ref.read(gemaraSettingsProvider.notifier);
    final theme = Theme.of(context);
    final kind = widget.kind;
    final bavli = kind == StudyKind.bavli;
    final supported = booksOf(kind).first.views;
    final current = s.viewFor(kind.name, supported);
    final commentators = switch (kind) {
      StudyKind.bavli => context.tr('Rashi and Tosafot under each passage'),
      StudyKind.mishnah => context.tr('Bartenura under each mishnah'),
      StudyKind.kitzur => null,
    };
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
          Text(switch (kind) {
            StudyKind.bavli => context.tr('Gemara'),
            StudyKind.mishnah => context.tr('Mishnah'),
            StudyKind.kitzur => context.tr('Kitzur Shulchan Aruch'),
          }, style: theme.textTheme.titleLarge),
          SheetLabel(context.tr('View')),
          for (final (v, icon, label) in gemaraViews(context))
            if (supported.contains(v))
            ListTile(
              contentPadding: EdgeInsets.zero,
              selected: v == current,
              leading: Icon(icon),
              title: Text(label),
              subtitle: Text(switch (v) {
                GemaraView.daf => context.tr('The printed page, with Rashi and Tosafot around the Gemara'),
                GemaraView.elucidated => context.tr('Each passage, then its English with the explanation'),
                GemaraView.sideBySide => context.tr('Hebrew and English in two columns'),
                GemaraView.phrase => context.tr('Each Hebrew phrase followed by its English'),
                GemaraView.interlinear => context.tr('Every word with its English under it'),
              }),
              trailing: v == current ? const Icon(Icons.check) : null,
              onTap: () => n.update((x) => x.withView(kind.name, v)),
            ),
          if (bavli) ...[
          SheetLabel(context.tr('Tapping the page shows')),
          ChoiceBar<DafTip>(
            options: [
              (DafTip.translation, context.tr('Translation'), null),
              (DafTip.phrases, context.tr('Phrase by phrase'), null),
              (DafTip.words, context.tr('Word by word'), null),
            ],
            selected: s.dafTip,
            onChanged: (v) => n.update((x) => x.copyWith(dafTip: v)),
          ),
          if (s.dafTip == DafTip.words)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Also mark the word\'s phrase')),
              value: s.dafPhrase,
              onChanged: (v) => n.update((x) => x.copyWith(dafPhrase: v)),
            ),
          ],
          // The Kitzur's English isn't marked literal, so there's nothing to hide.
          if (kind != StudyKind.kitzur)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Show the explanation')),
            subtitle: Text(context.tr('Off: only the literal translation (the bold words)')),
            value: s.elucidation,
            onChanged: (v) => n.update((x) => x.copyWith(elucidation: v)),
          ),
          if (commentators != null)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(commentators),
            value: s.inlineCommentary,
            onChanged: (v) => n.update((x) => x.copyWith(inlineCommentary: v)),
          ),
          if (bavli) ...[
          SheetLabel(context.tr('Page size')),
          Row(children: [
            const Icon(Icons.text_decrease, size: 18),
            Expanded(
              child: Slider.adaptive(
                value: s.dafScale,
                min: 0.8,
                max: 1.6,
                divisions: 16,
                label: '${(s.dafScale * 100).round()}%',
                onChanged: (v) => n.update((x) => x.copyWith(dafScale: v)),
              ),
            ),
            const Icon(Icons.text_increase, size: 18),
          ]),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.text_fields),
            title: Text(context.tr('Font, size and vowels')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showTorahTextSettings(context),
          ),
          if (kind != StudyKind.kitzur) ...[
          SheetLabel(context.tr('Word-by-word English')),
          TextField(
            controller: _server,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: context.tr('Server'),
              helperText: context.tr('Where the word-by-word English comes from. Leave empty to turn it off.'),
            ),
            // Saved as it is typed: closing the sheet must not lose it.
            onChanged: (v) => n.update((x) => x.copyWith(interlinearServer: serverAddress(v))),
          ),
          ],
        ]),
      ),
    );
  }
}
