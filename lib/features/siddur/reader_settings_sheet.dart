import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/adaptive.dart';
import '../../core/l10n.dart';
import '../../core/fonts.dart';
import '../../core/settings.dart';
import '../settings/font_gallery_screen.dart';
import '../settings/typesetting_options.dart';
import 'versions_screen.dart';

Future<void> showReaderSettings(BuildContext context, String book) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
          const TypesettingOptions(),
          SwitchListTile.adaptive(contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Keep screen on while reading')), value: s.keepReaderAwake,
            onChanged: (v) => n.update((x) => x.copyWith(keepReaderAwake: v))),
          SwitchListTile.adaptive(contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Full-screen reader')), value: s.fullscreenReader,
            onChanged: (v) => n.update((x) => x.copyWith(fullscreenReader: v))),
          SheetLabel(context.tr('Prayer text')),
          ChoiceBar<TextLayout>(
            options: [
              (TextLayout.hebrewOnly, context.tr('Hebrew'), Icons.format_textdirection_r_to_l),
              (TextLayout.interleaved, context.tr('Bilingual'), Icons.view_stream),
              (TextLayout.sideBySide, context.tr('Side by side'), Icons.view_column),
            ],
            selected: s.layout == TextLayout.translationOnly ? TextLayout.interleaved : s.layout,
            onChanged: (v) => n.update((x) => x.copyWith(layout: v)),
          ),
          SheetLabel(context.tr('Instructions & notes')),
          ChoiceBar<NotesLanguage>(
            options: [
              (NotesLanguage.bilingual, context.tr('Bilingual'), null),
              (NotesLanguage.english, context.tr('English'), null),
              (NotesLanguage.hebrew, context.tr('Hebrew'), null),
            ],
            selected: s.notesLanguage,
            onChanged: (v) => n.update((x) => x.copyWith(notesLanguage: v)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(context.tr('Also used for "said only on…" labels'), style: theme.textTheme.bodySmall),
          ),
          SheetLabel(context.tr('Prayer titles')),
          ChoiceBar<TitleLanguage>(
            options: [
              (TitleLanguage.auto, context.tr('Auto'), null),
              (TitleLanguage.english, context.tr('English'), null),
              (TitleLanguage.hebrew, context.tr('Hebrew'), null),
              (TitleLanguage.both, context.tr('Both'), null),
            ],
            selected: s.titleLanguage,
            onChanged: (v) => n.update((x) => x.copyWith(titleLanguage: v)),
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
          SheetLabel(context.tr('Today-aware display')),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Highlight what applies today')),
            value: s.highlightToday,
            onChanged: (v) => n.update((x) => x.copyWith(highlightToday: v)),
          ),
          SheetLabel(context.tr('Text not said today')),
          ChoiceBar<ExcludedDisplay>(
            options: [
              (ExcludedDisplay.collapse, context.tr('Collapse'), null),
              (ExcludedDisplay.dim, context.tr('Dim'), null),
              (ExcludedDisplay.hide, context.tr('Hide'), null),
            ],
            selected: s.excludedDisplay,
            onChanged: (v) => n.update((x) => x.copyWith(excludedDisplay: v)),
          ),
          if (s.excludedDisplay == ExcludedDisplay.hide)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.tr('Sections, lines and additions not said today are removed. Where one of several options is said, the others stay, crossed out.'), style: theme.textTheme.bodySmall),
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
          if (s.showNotes)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Short notes')),
              subtitle: Text(context.tr("Brief notes only when they apply today, instead of the siddur's full notes")),
              value: s.conciseNotes,
              onChanged: (v) => n.update((x) => x.copyWith(conciseNotes: v)),
            ),
          if (s.showNotes && !s.conciseNotes)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Collapse halachic notes')),
              subtitle: Text(context.tr('Show a one-line note; tap to read it')),
              value: s.collapseNotes,
              onChanged: (v) => n.update((x) => x.copyWith(collapseNotes: v)),
            ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Collapse Chazarat HaShatz')),
            subtitle: Text(context.tr("Kedusha, Birkat Kohanim and Modim DeRabbanan fold into a row")),
            value: s.collapseChazarah,
            onChanged: (v) => n.update((x) => x.copyWith(collapseChazarah: v)),
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
              final nav = Navigator.of(context, rootNavigator: true);
              Navigator.pop(context);
              nav.push(MaterialPageRoute<void>(builder: (_) => VersionsScreen(book: book)));
            },
          ),
        ]),
      ),
    );
  }
}
