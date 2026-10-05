import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adaptive.dart';
import '../../core/fonts.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../settings/font_gallery_screen.dart';
import '../settings/typesetting_options.dart';
import '../../core/analytics.dart';

enum TorahTextLanguage { auto, hebrew, both, english }

/// How Torah tab texts are shown. Kept apart from the siddur's text
/// settings, so learning and davening can look different.
class TorahSettings {
  /// [TorahTextLanguage.auto]: both languages with an English interface,
  /// Hebrew otherwise.
  final TorahTextLanguage language;
  final String hebrewFont;

  /// Null = the app's default Latin font.
  final String? latinFont;
  final double textScale;
  final bool showNikud;

  /// Settle on a verse when scrolling stops (see VerseSnap).
  final bool snapToVerse;
  const TorahSettings({
    this.language = TorahTextLanguage.auto,
    this.hebrewFont = 'FrankRuehlCLM',
    this.latinFont,
    this.textScale = 1,
    this.showNikud = true,
    this.snapToVerse = true,
  });

  TorahTextLanguage resolvedLanguage(UiLanguage ui) =>
      language != TorahTextLanguage.auto ? language : (ui == UiLanguage.en ? TorahTextLanguage.both : TorahTextLanguage.hebrew);

  TorahSettings copyWith({TorahTextLanguage? language, String? hebrewFont, String? Function()? latinFont, double? textScale, bool? showNikud, bool? snapToVerse}) =>
      TorahSettings(
        language: language ?? this.language,
        hebrewFont: hebrewFont ?? this.hebrewFont,
        latinFont: latinFont != null ? latinFont() : this.latinFont,
        textScale: textScale ?? this.textScale,
        showNikud: showNikud ?? this.showNikud,
        snapToVerse: snapToVerse ?? this.snapToVerse,
      );

  Map<String, Object?> toJson() =>
      {'language': language.name, 'hebrewFont': hebrewFont, 'latinFont': latinFont, 'textScale': textScale, 'showNikud': showNikud, 'snapToVerse': snapToVerse};

  factory TorahSettings.fromJson(Map<String, Object?> j) {
    const d = TorahSettings();
    return TorahSettings(
      language: TorahTextLanguage.values.asNameMap()[j['language']] ?? d.language,
      hebrewFont: j['hebrewFont'] is String ? j['hebrewFont'] as String : d.hebrewFont,
      latinFont: j['latinFont'] is String ? j['latinFont'] as String : null,
      textScale: j['textScale'] is num ? (j['textScale'] as num).toDouble() : d.textScale,
      showNikud: j['showNikud'] is bool ? j['showNikud'] as bool : d.showNikud,
      snapToVerse: j['snapToVerse'] is bool ? j['snapToVerse'] as bool : d.snapToVerse,
    );
  }
}

class TorahSettingsNotifier extends Notifier<TorahSettings> {
  static const _key = 'torahSettings';

  @override
  TorahSettings build() =>
      ref.watch(storageProvider).readJson(_key, (j) => TorahSettings.fromJson((j as Map).cast<String, Object?>())) ?? const TorahSettings();

  void update(TorahSettings Function(TorahSettings) f) {
    final old = state.toJson();
    state = f(state);
    final now = state.toJson();
    ref.read(storageProvider).writeJson(_key, now);
    for (final k in now.keys) {
      if (old[k] != now[k]) analytics.settingChanged('torah_$k', now[k]);
    }
  }
}

final torahSettingsProvider = NotifierProvider<TorahSettingsNotifier, TorahSettings>(TorahSettingsNotifier.new);

/// Bundled fonts with Latin letters, for the English text.
const latinFontChoices = [
  (null, 'Default'),
  ('FrankRuhlLibre', 'Frank Ruhl Libre'),
  ('DavidLibre', 'David Libre'),
  ('EzraSIL', 'Ezra SIL'),
];

Future<void> showTorahTextSettings(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _TorahTextSettings(),
    );

class _TorahTextSettings extends ConsumerWidget {
  const _TorahTextSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(torahSettingsProvider);
    final n = ref.read(torahSettingsProvider.notifier);
    final userFonts = ref.watch(fontsProvider);
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
          Text(context.tr('Learning text'), style: theme.textTheme.titleLarge),
          Text(context.tr('Separate from the siddur\'s text settings.'), style: theme.textTheme.bodySmall),
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
          Text(s.showNikud ? 'שִׁוִיתִי ה\' לְנֶגְדִּי תָמִיד' : 'שויתי ה\' לנגדי תמיד',
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: s.hebrewFont, fontSize: 21 * s.textScale, height: 1.6)),
          Text('"I have set Hashem before me always."',
              textAlign: TextAlign.center, style: TextStyle(fontFamily: s.latinFont, fontSize: 16 * s.textScale, height: 1.5)),
          SheetLabel(context.tr('Language')),
          ChoiceBar<TorahTextLanguage>(
            options: [
              (TorahTextLanguage.auto, context.tr('Auto'), null),
              (TorahTextLanguage.hebrew, context.tr('Hebrew'), null),
              (TorahTextLanguage.both, context.tr('Both'), null),
              (TorahTextLanguage.english, context.tr('English'), null),
            ],
            selected: s.language,
            onChanged: (v) => n.update((x) => x.copyWith(language: v)),
          ),
          if (s.language == TorahTextLanguage.auto)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(context.tr('Hebrew and English with an English interface; otherwise Hebrew.'), style: theme.textTheme.bodySmall),
            ),
          // Shared with the siddur, unlike the rest of this sheet.
          const TypesettingOptions(),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.font_download_outlined),
            title: Text(context.tr('Hebrew font')),
            subtitle: Text(fontLabel(s.hebrewFont, userFonts)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
                builder: (_) => FontGalleryScreen(
                      selectedFont: torahSettingsProvider.select((x) => x.hebrewFont),
                      chooseFont: (ref, family) => ref.read(torahSettingsProvider.notifier).update((x) => x.copyWith(hebrewFont: family)),
                    ))),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Show nikud (vowels)')),
            value: s.showNikud,
            onChanged: (v) => n.update((x) => x.copyWith(showNikud: v)),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Snap to each verse')),
            subtitle: Text(context.tr('When you stop scrolling near the end of a verse, the next one moves to the top.')),
            value: s.snapToVerse,
            onChanged: (v) => n.update((x) => x.copyWith(snapToVerse: v)),
          ),
          SheetLabel(context.tr('English font')),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (family, label) in latinFontChoices)
              ChoiceChip(
                label: Text(family == null ? context.tr(label) : label, style: TextStyle(fontFamily: family)),
                selected: s.latinFont == family,
                onSelected: (_) => n.update((x) => x.copyWith(latinFont: () => family)),
              ),
          ]),
        ]),
      ),
    );
  }
}
