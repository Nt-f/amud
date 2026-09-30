import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n.dart';
import 'settings.dart';
import 'split_row.dart';

/// Which forms of a prayer title to show: English, Hebrew or both, per the
/// title language setting (independent of the interface language).
({bool en, bool he}) titleForms(UiLanguage ui, TitleLanguage t) => switch (t) {
      TitleLanguage.auto => ui == UiLanguage.en ? (en: true, he: true) : (en: false, he: true),
      TitleLanguage.english => (en: true, he: false),
      TitleLanguage.hebrew => (en: false, he: true),
      TitleLanguage.both => (en: true, he: true),
    };

extension PrayerTitles on BuildContext {
  ({bool en, bool he}) titleFormsFor(AppSettings s) => titleForms(uiLanguage, s.titleLanguage);

  /// A prayer title on one line (buttons, app bars): Hebrew when only
  /// Hebrew titles are shown, or when both are and the interface isn't in
  /// English; otherwise English with the spelling preference.
  String prayerTitle(AppSettings s, String en, String he) {
    final f = titleFormsFor(s);
    final hebrew = !f.en || (f.he && uiLanguage != UiLanguage.en);
    return hebrew ? he : term(en);
  }

  /// Whether a one-line [prayerTitle] is in Hebrew (for its font).
  bool prayerTitleIsHebrew(AppSettings s) {
    final f = titleFormsFor(s);
    return !f.en || (f.he && uiLanguage != UiLanguage.en);
  }

  /// The other form of a title shown under a one-line [prayerTitle] (app
  /// bar subtitles), or null when only one form is shown.
  String? prayerSubtitle(AppSettings s, String en, String he) {
    final f = titleFormsFor(s);
    if (!f.en || !f.he || en.trim() == he.trim()) return null;
    return prayerTitleIsHebrew(s) ? term(en) : he;
  }
}

/// A prayer title in English and/or Hebrew, per the title language
/// setting: English at the start and Hebrew at the end when both show.
class PrayerTitleText extends ConsumerWidget {
  final String en;
  final String he;
  final TextStyle? enStyle;

  /// Style for the Hebrew form; the Hebrew font is applied on top.
  final TextStyle? heStyle;
  final double gap;
  final CrossAxisAlignment crossAxisAlignment;
  final int? maxLines;

  /// Hebrew shown alone sits at the end of the line, like the Hebrew text
  /// under a reader heading, rather than at the start.
  final bool hebrewAtEnd;
  const PrayerTitleText(this.en, this.he,
      {super.key,
      this.enStyle,
      this.heStyle,
      this.gap = 8,
      this.crossAxisAlignment = CrossAxisAlignment.end,
      this.maxLines,
      this.hebrewAtEnd = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final f = context.titleFormsFor(s);
    final enW = Text(context.term(en), style: enStyle, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis);
    final heW = Text(he,
        textDirection: TextDirection.rtl,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        style: (heStyle ?? enStyle ?? const TextStyle()).copyWith(fontFamily: s.hebrewFont));
    if (f.en && f.he && en.trim() != he.trim()) {
      return SplitRow(gap: gap, crossAxisAlignment: crossAxisAlignment, children: [enW, heW]);
    }
    if (f.en && !f.he) return enW;
    return Align(
      alignment: hebrewAtEnd ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      widthFactor: hebrewAtEnd ? null : 1,
      child: heW,
    );
  }
}
