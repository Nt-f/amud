import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/l10n.dart';
import '../../core/fonts.dart';
import '../../core/settings.dart';
import '../settings/font_gallery_screen.dart';

Future<void> showReaderSettings(BuildContext context, String book) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ReaderSettings(book: book),
    );

class _ReaderSettings extends ConsumerWidget {
  final String book;
  const _ReaderSettings({required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final userFonts = ref.watch(fontsProvider);
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
          Text(context.tr('Text'), style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.text_decrease, size: 18),
            Expanded(
              child: Slider.adaptive(
                value: s.textScale,
                min: 0.7,
                max: 2.2,
                divisions: 30,
                label: '${(s.textScale * 100).round()}%',
                onChanged: (v) => n.update((x) => x.copyWith(textScale: v)),
              ),
            ),
            const Icon(Icons.text_increase, size: 18),
          ]),
          Text('בָּרוּךְ אַתָּה יְהֹוָה אֱלֹהֵֽינוּ מֶֽלֶךְ הָעוֹלָם',
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: s.hebrewFont, fontSize: 22 * s.textScale, height: 1.6)),
          const SizedBox(height: 12),
          Text(context.tr('Prayer text'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<TextLayout>(
            segments: [
              ButtonSegment(value: TextLayout.hebrewOnly, label: Text(context.tr('Hebrew')), icon: Icon(Icons.format_textdirection_r_to_l)),
              ButtonSegment(value: TextLayout.interleaved, label: Text(context.tr('Bilingual')), icon: Icon(Icons.view_stream)),
              ButtonSegment(value: TextLayout.sideBySide, label: Text(context.tr('Side by side')), icon: Icon(Icons.view_column)),
            ],
            selected: {s.layout == TextLayout.translationOnly ? TextLayout.interleaved : s.layout},
            onSelectionChanged: (v) => n.update((x) => x.copyWith(layout: v.first)),
          ),
          const SizedBox(height: 12),
          Text(context.tr('Instructions & notes'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<NotesLanguage>(
            segments: [
              ButtonSegment(value: NotesLanguage.bilingual, label: Text(context.tr('Bilingual'))),
              ButtonSegment(value: NotesLanguage.english, label: Text(context.tr('English'))),
              ButtonSegment(value: NotesLanguage.hebrew, label: Text(context.tr('Hebrew'))),
            ],
            selected: {s.notesLanguage},
            onSelectionChanged: (v) => n.update((x) => x.copyWith(notesLanguage: v.first)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(context.tr('Also used for "said only on…" labels'), style: theme.textTheme.bodySmall),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.font_download_outlined),
            title: Text(context.tr('Hebrew font')),
            subtitle: Text(fontLabel(s.hebrewFont, userFonts)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const FontGalleryScreen())),
          ),
          if (catalogFont(s.hebrewFont)?.teamim == false && s.showTeamim)
            Text(
              context.tr('This font has no te\'amim; passages with trop use {font}.',
                  {'font': fontLabel(hebrewFamilyFor(s.hebrewFont, teamim: true, nikud: true), const [])}),
              style: theme.textTheme.bodySmall,
            ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr("Show te'amim (trop)")),
            value: s.showTeamim,
            onChanged: (v) => n.update((x) => x.copyWith(showTeamim: v)),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Show nikud (vowels)')),
            value: s.showNikud,
            onChanged: (v) => n.update((x) => x.copyWith(showNikud: v)),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr("Prefer texts with te'amim")),
            subtitle: Text(context.tr('e.g. the Shema with cantillation')),
            value: s.preferTrop,
            onChanged: (v) => n.update((x) => x.copyWith(preferTrop: v)),
          ),
          const SizedBox(height: 8),
          Text(context.tr('Today-aware display'), style: theme.textTheme.titleSmall),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Highlight what applies today')),
            value: s.highlightToday,
            onChanged: (v) => n.update((x) => x.copyWith(highlightToday: v)),
          ),
          Text(context.tr('Text not said today:')),
          const SizedBox(height: 6),
          SegmentedButton<ExcludedDisplay>(
            segments: [
              ButtonSegment(value: ExcludedDisplay.collapse, label: Text(context.tr('Collapse'))),
              ButtonSegment(value: ExcludedDisplay.dim, label: Text(context.tr('Dim'))),
              ButtonSegment(value: ExcludedDisplay.hide, label: Text(context.tr('Hide'))),
            ],
            selected: {s.excludedDisplay},
            onSelectionChanged: (v) => n.update((x) => x.copyWith(excludedDisplay: v.first)),
          ),
          if (s.excludedDisplay == ExcludedDisplay.hide)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.tr('Sections, lines and inline phrases not said today are removed entirely.'), style: theme.textTheme.bodySmall),
            ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Show instructions')),
            value: s.showInstructions,
            onChanged: (v) => n.update((x) => x.copyWith(showInstructions: v)),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Show halachic notes')),
            value: s.showNotes,
            onChanged: (v) => n.update((x) => x.copyWith(showNotes: v)),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Praying with a minyan')),
            subtitle: Text(context.tr('Shows Kedusha, Chazarat HaShatz and Kaddish as applicable')),
            value: s.minhagim.withMinyan,
            onChanged: (v) => n.update((x) => x.copyWith(minhagim: x.minhagim.copyWith(withMinyan: v))),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.layers_outlined),
            title: Text(context.tr('Text versions')),
            subtitle: Text(context.tr('Choose and order Hebrew text and translations')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(context);
              context.push('/siddur/book/${Uri.encodeComponent(book)}/versions');
            },
          ),
        ]),
      ),
    );
  }
}
