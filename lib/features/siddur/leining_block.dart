import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';

import '../../core/hebrew_text.dart';
import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/typeset/ornaments.dart';
import '../torah/shnayim_mikra.dart';
import 'book_kind.dart';

/// Today's Torah reading, worked out for the day and service by the engine
/// (a `leining` dynamic item): the parsha and what is read from it, from the
/// Chumash the Torah tab keeps offline. Set like a page of the siddur, in a
/// printed frame: each aliyah begins a new line under its name (כהן, לוי…)
/// and its verses run on, justified.
class LeiningBlock extends ConsumerWidget {
  final Map<String, Object?> data;
  const LeiningBlock(this.data, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(readerSettingsProvider);
    final colors = SiddurColors.of(context);
    final theme = Theme.of(context);
    final d = data;
    final parsha = [for (final p in d['parsha'] as List) '$p'];
    final book = d['book'] as int;
    final whole = d['scope'] == 'shabbat';
    final ranges = [
      for (final r in d['ranges'] as List) (begin: (chapter: (r as List)[0] as int, verse: r[1] as int), end: (chapter: r[2] as int, verse: r[3] as int)),
    ];
    final name = renderParshaName(parsha, context.hebcalLocale);
    int key(Verse v) => v.chapter * 1000 + v.verse;
    String where(Verse v) => '${hebrewNumeral(v.chapter)}:${hebrewNumeral(v.verse)}';
    // A range set right to left as one unbroken piece, even inside English.
    String span(Verse b, Verse e) => '\u2067${where(b)}\u2060–\u2060${where(e)}\u2069';
    // The aliyot by the names a Chumash prints over them.
    final names = whole ? _shabbatAliyot : _weekdayAliyot;
    final english = s.layout != TextLayout.hebrewOnly;

    Widget text() {
      final book$ = ref.watch(chumashBookProvider(book));
      return switch (book$) {
        AsyncData(:final value) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, r) in ranges.indexed) ...() {
              final verses = [for (final v in value.verses) if (key(v.at) >= key(r.begin) && key(v.at) <= key(r.end)) v];
              return [
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 4 : 14, bottom: 4),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: i < names.length ? names[i] : hebrewNumeral(i + 1),
                          style: TextStyle(fontFamily: s.hebrewFont, fontSize: 17 * s.textScale, fontWeight: FontWeight.w700)),
                      TextSpan(text: '  ${span(r.begin, r.end)}', style: theme.textTheme.labelMedium?.copyWith(color: colors.marker)),
                    ]),
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.marker),
                  ),
                ),
                // The aliyah's verses as one paragraph, each with its number.
                Text.rich(
                  TextSpan(children: [
                    for (final v in verses) ...[
                      TextSpan(
                          text: '${hebrewNumeral(v.at.verse)} ',
                          style: TextStyle(fontSize: 14 * s.textScale, color: colors.marker, fontWeight: FontWeight.w600)),
                      TextSpan(text: '${hebrewMarks(v.he, teamim: s.showTeamim, nikud: s.showNikud)} '),
                    ],
                  ]),
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.justify,
                  style: TextStyle(fontFamily: s.hebrewFont, fontSize: 22 * s.textScale, height: 1.7, color: theme.colorScheme.onSurface),
                ),
                if (english && verses.any((v) => v.en.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text.rich(
                      TextSpan(children: [
                        for (final v in verses)
                          if (v.en.isNotEmpty) ...[
                            TextSpan(text: '${v.at.verse} ', style: TextStyle(fontSize: 12 * s.textScale, color: colors.marker, fontWeight: FontWeight.w600)),
                            TextSpan(text: '${v.en} '),
                          ],
                      ]),
                      textAlign: TextAlign.justify,
                      style: TextStyle(fontFamily: s.latinFont, fontSize: 16 * s.textScale, height: 1.5, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
              ];
            }(),
          ]),
        AsyncError() => ListTile(
            dense: true,
            leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
            title: Text(context.tr('Download failed. Check your connection and try again.')),
            trailing: TextButton(onPressed: () => ref.invalidate(chumashBookProvider(book)), child: Text(context.tr('Retry'))),
          ),
        _ => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Expanded(child: Text(context.tr('Downloading the Chumash from Sefaria, once. After this it works offline.'), style: theme.textTheme.bodySmall)),
            ]),
          ),
      };
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: OrnateFrame(
        color: colors.marker,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(context.tr("Today's Torah reading"),
              textAlign: TextAlign.center, style: theme.textTheme.labelMedium?.copyWith(color: colors.marker, letterSpacing: 0.6)),
          Text(name, textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          Text(
            [
              whole ? context.tr('The whole parsha, in seven aliyot') : context.tr("The start of the coming Shabbat's parsha"),
              span(ranges.first.begin, ranges.last.end),
            ].join(' · '),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          if (d['special'] == true)
            Text(context.tr("The maftir is today's special reading, printed in the siddur."),
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          SectionOrnament(color: colors.marker, height: 22, small: true),
          text(),
        ]),
      ),
    );
  }
}

const _shabbatAliyot = ['כהן', 'לוי', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שביעי'];
const _weekdayAliyot = ['כהן', 'לוי', 'ישראל'];
