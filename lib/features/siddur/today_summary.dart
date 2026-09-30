import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../home/cards/card_frame.dart';

enum ChangeKind { add, omit, info }

class LiturgyChange {
  final ChangeKind kind;
  final String en;
  final String he;
  final String? detail;
  const LiturgyChange(this.kind, this.en, this.he, [this.detail]);
}

/// Human summary of how today's prayers differ from a plain weekday,
/// derived from the same [DayContext] the reader uses. [omer] includes
/// tonight's count (Home shows it on its own card instead).
List<LiturgyChange> summarizeDay(DayContext shacharit, DayContext mincha, DayContext maariv, {bool omer = true}) {
  final out = <LiturgyChange>[];
  final d = shacharit;
  void add(bool cond, ChangeKind k, String en, String he, [String? detail]) {
    if (cond) out.add(LiturgyChange(k, en, he, detail));
  }

  add(d['roshChodesh'] || d['cholHamoed'], ChangeKind.add, "Ya'aleh VeYavo", 'יעלה ויבוא');
  add(d['chanukah'], ChangeKind.add, 'Al HaNisim (Chanukah)', 'על הניסים', 'Day ${d.number('chanukahDay')} of Chanukah');
  add(d['purim'], ChangeKind.add, 'Al HaNisim (Purim)', 'על הניסים');
  add(d['wholeHallel'], ChangeKind.add, 'Whole Hallel', 'הלל שלם');
  add(d['halfHallel'], ChangeKind.add, 'Half Hallel', 'חצי הלל');
  add(d['aseretYemeiTeshuva'], ChangeKind.add, 'Aseret Yemei Teshuva inserts', 'זכרנו, המלך הקדוש', 'Zochreinu, Mi Chamocha, HaMelech HaKadosh, HaMelech HaMishpat, Uchtov, BeSefer Chaim');
  add(d['avinuMalkeinu'], ChangeKind.add, 'Avinu Malkeinu', 'אבינו מלכנו');
  add(d['publicFast'], ChangeKind.add, 'Aneinu (fast day)', 'עננו');
  add(d['roshChodesh'] || d['cholHamoed'] || d['yomTov'] || d['shabbat'], ChangeKind.add, 'Musaf', 'מוסף');
  add(d['torahReading'] && !d['shabbat'], ChangeKind.info, 'Torah reading', 'קריאת התורה');
  add(!d['shabbat'] && !d['yomTov'] && !d['tachanunShacharit'], ChangeKind.omit, 'No Tachanun at Shacharit', 'אין אומרים תחנון בשחרית');
  add(!d['shabbat'] && !d['yomTov'] && d['tachanunShacharit'] && !mincha['tachanunMincha'], ChangeKind.omit, 'No Tachanun at Mincha', 'אין תחנון במנחה');
  add(d['ledavid'], ChangeKind.add, 'LeDavid Hashem Ori (Psalm 27)', 'לדוד ה׳ אורי');
  add(d['mashivHaruach'], ChangeKind.info, 'Mashiv HaRuach u\'Morid HaGeshem', 'משיב הרוח ומוריד הגשם');
  add(!d['mashivHaruach'], ChangeKind.info, 'Morid HaTal (Sefard/Israel) · none (Ashkenaz, diaspora)', 'מוריד הטל');
  add(d['talUmatar'], ChangeKind.info, 'V\'ten tal u\'matar livracha', 'ותן טל ומטר לברכה');
  add(!d['talUmatar'], ChangeKind.info, 'V\'ten bracha', 'ותן ברכה');
  final omerDay = maariv.number('omerDay').toInt();
  add(omer && omerDay > 0, ChangeKind.add, 'Sefirat HaOmer tonight: day $omerDay', 'ספירת העומר: יום $omerDay');
  add(maariv['motzaeiShabbat'], ChangeKind.add, 'Atah Chonantanu & Havdalah', 'אתה חוננתנו');
  add(d['kiddushLevana'], ChangeKind.info, 'Kiddush Levana window', 'זמן קידוש לבנה');
  add(d['eruvTavshilin'], ChangeKind.add, 'Eruv Tavshilin today', 'עירוב תבשילין');
  add(d['yizkor'], ChangeKind.add, 'Yizkor', 'יזכור');
  add(d['tishaBav'], ChangeKind.info, 'Kinot · Nachem at Mincha', 'קינות · נחם');
  return out;
}

class TodayInSiddurCard extends ConsumerWidget {
  const TodayInSiddurCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hd = ref.watch(readerDaytimeDateProvider);
    ref.watch(settingsProvider);
    final changes = summarizeDay(
      ref.watch(dayContextProvider((hd.abs(), Service.shacharit))),
      ref.watch(dayContextProvider((hd.abs(), Service.mincha))),
      ref.watch(dayContextProvider((hd.abs(), Service.maariv))),
      omer: false,
    );
    final theme = Theme.of(context);
    final colors = SiddurColors.of(context);
    // Just the list: what changes first, then the season's standing wording.
    return CardFrame(
      title: 'Today in the siddur',
      icon: Icons.auto_awesome,
      child: Column(children: [
        for (final c in changes) _row(theme, colors, c),
        if (changes.isEmpty) Text(context.tr('A regular weekday.')),
      ]),
    );
  }

  Widget _row(ThemeData theme, SiddurColors colors, LiturgyChange c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
            switch (c.kind) {
              ChangeKind.add => Icons.add_circle,
              ChangeKind.omit => Icons.remove_circle_outline,
              ChangeKind.info => Icons.info_outline,
            },
            size: 18,
            color: c.kind == ChangeKind.add ? colors.todayBar : theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.en, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: c.kind == ChangeKind.info ? null : FontWeight.w600)),
              if (c.detail != null) Text(c.detail!, style: theme.textTheme.bodySmall),
            ]),
          ),
          Text(c.he, textDirection: TextDirection.rtl, style: theme.textTheme.bodySmall),
        ]),
      );
}
