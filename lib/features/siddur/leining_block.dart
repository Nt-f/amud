import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';

import '../../core/hebrew_text.dart';
import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../torah/shnayim_mikra.dart';

/// Today's Torah reading, worked out for the day and service by the engine
/// (a `leining` dynamic item): the parsha and what is read from it, with
/// the text one tap away, from the Chumash the Torah tab keeps offline.
class LeiningBlock extends ConsumerStatefulWidget {
  final Map<String, Object?> data;
  const LeiningBlock(this.data, {super.key});

  @override
  ConsumerState<LeiningBlock> createState() => _LeiningBlockState();
}

class _LeiningBlockState extends ConsumerState<LeiningBlock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final colors = SiddurColors.of(context);
    final theme = Theme.of(context);
    final d = widget.data;
    final parsha = [for (final p in d['parsha'] as List) '$p'];
    final book = d['book'] as int;
    final whole = d['scope'] == 'shabbat';
    final ranges = [
      for (final r in d['ranges'] as List) (begin: (chapter: (r as List)[0] as int, verse: r[1] as int), end: (chapter: r[2] as int, verse: r[3] as int)),
    ];
    final name = renderParshaName(parsha, context.hebcalLocale);
    int key(Verse v) => v.chapter * 1000 + v.verse;
    String where(Verse v) => '${hebrewNumeral(v.chapter)}:${hebrewNumeral(v.verse)}';

    Widget text() {
      final book$ = ref.watch(chumashBookProvider(book));
      return switch (book$) {
        AsyncData(:final value) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, r) in ranges.indexed) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  '${whole ? context.tr('Aliyah {n}', {'n': i + 1}) : context.tr('First aliyah')} · ${where(r.begin)}–${where(r.end)}',
                  style: theme.textTheme.labelMedium?.copyWith(color: colors.marker, fontWeight: FontWeight.w600),
                ),
              ),
              for (final v in value.verses.where((v) => key(v.at) >= key(r.begin) && key(v.at) <= key(r.end))) ...[
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: '${hebrewNumeral(v.at.verse)} ',
                        style: TextStyle(fontSize: 14 * s.textScale, color: colors.marker, fontWeight: FontWeight.w600)),
                    TextSpan(text: hebrewMarks(v.he, teamim: s.showTeamim, nikud: s.showNikud)),
                  ]),
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontFamily: s.hebrewFont, fontSize: 22 * s.textScale, height: 1.7, color: theme.colorScheme.onSurface),
                ),
                if (s.layout != TextLayout.hebrewOnly && v.en.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(v.en,
                        style: TextStyle(fontFamily: s.latinFont, fontSize: 16 * s.textScale, height: 1.5, color: theme.colorScheme.onSurfaceVariant)),
                  ),
              ],
            ],
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

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colors.todayFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.todayBar.withValues(alpha: 0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Row(children: [
            Icon(Icons.menu_book_outlined, color: colors.todayBar),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr("Today's Torah reading"), style: theme.textTheme.labelMedium?.copyWith(color: colors.marker)),
                Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  [
                    whole ? context.tr('The whole parsha, in seven aliyot') : context.tr("The start of the coming Shabbat's parsha"),
                    '${where(ranges.first.begin)}–${where(ranges.last.end)}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                if (d['special'] == true)
                  Text(context.tr("The maftir is today's special reading, printed in the siddur."), style: theme.textTheme.bodySmall),
              ]),
            ),
            Icon(_open ? Icons.expand_less : Icons.expand_more),
          ]),
        ),
        if (_open) text(),
      ]),
    );
  }
}
