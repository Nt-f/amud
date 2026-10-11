import 'package:flutter/widgets.dart';
import 'package:hebcal/hebcal.dart';

import '../../core/l10n.dart';
import 'gemara_data.dart';
import 'gemara_settings.dart';

/// The texts the study reader handles. Each is a set of books made of units,
/// each unit a list of passages:
///
///  * Bavli: tractates of amudim, passages as Sefaria segments them, with
///    Rashi and Tosafot, and the printed page;
///  * Mishnah: masechtos of perakim, a passage per mishnah, with Bartenura;
///  * Kitzur: the Kitzur Shulchan Aruch's simanim, a passage per se'if.
enum StudyKind { bavli, mishnah, kitzur }

/// A book of one kind: its Sefaria title (the id everywhere, unique across
/// kinds), names, order, and units in reading order.
class StudyBook {
  final StudyKind kind;
  final String id;
  final String en;
  final String he;
  final String seder;
  final String sederHe;
  final List<String> units;
  const StudyBook(this.kind, this.id, this.en, this.he, this.seder, this.sederHe, this.units);

  bool contains(String unit) => units.contains(unit);

  /// The unit [delta] away, or null past either end.
  String? neighbor(String unit, int delta) {
    final at = units.indexOf(unit);
    if (at < 0) return null;
    final i = at + delta;
    return i < 0 || i >= units.length ? null : units[i];
  }

  /// "Berakhot", or "ברכות" in a Hebrew interface.
  String name(BuildContext context) => context.uiLanguage == UiLanguage.en ? context.term(en) : he;

  /// "Berakhot 2a" / "ברכות ב.", "Berakhot 3" / "ברכות פרק ג", "Siman 12" /
  /// "סימן יב".
  String unitTitle(BuildContext context, String unit) {
    final en = context.uiLanguage == UiLanguage.en;
    switch (kind) {
      case StudyKind.bavli:
        if (en) return '${context.term(this.en)} $unit';
        final n = amudNumber(unit)!;
        return '$he ${gematriya((n + 1) ~/ 2)}${n.isOdd ? '.' : ':'}';
      case StudyKind.mishnah:
        return en ? '${context.term(this.en)} $unit' : '$he פרק ${gematriya(int.parse(unit))}';
      case StudyKind.kitzur:
        return en ? context.tr('Siman {n}', {'n': unit}) : 'סימן ${gematriya(int.parse(unit))}';
    }
  }

  /// The views this kind can show: the printed page only for the Bavli;
  /// phrase and word views where English is marked literal (Bavli, Mishnah).
  List<GemaraView> get views => switch (kind) {
        StudyKind.bavli => GemaraView.values,
        StudyKind.mishnah => const [GemaraView.elucidated, GemaraView.sideBySide, GemaraView.phrase, GemaraView.interlinear],
        StudyKind.kitzur => const [GemaraView.elucidated, GemaraView.sideBySide],
      };

  /// The interlinear server's spine for this kind.
  String get spine => kind == StudyKind.bavli ? 'bavli' : 'sefaria';

  /// Whether finishing a unit finishes a perek (always for a Mishnah perek
  /// and a Kitzur siman; for the Bavli it depends on the perakim).
  bool get unitIsPerek => kind != StudyKind.bavli;
}

class MishnahMasechta {
  final String id;
  final String en;
  final String he;
  final String seder;
  final String sederHe;
  final int perakim;
  const MishnahMasechta(this.id, this.en, this.he, this.seder, this.sederHe, this.perakim);
}

/// Sefaria's Mishnah, in order, with the number of perakim in each.
const mishnahMasechtos = [
  MishnahMasechta('Mishnah Berakhot', 'Berakhot', 'ברכות', 'Zeraim', 'זרעים', 9),
  MishnahMasechta('Mishnah Peah', 'Peah', 'פאה', 'Zeraim', 'זרעים', 8),
  MishnahMasechta('Mishnah Demai', 'Demai', 'דמאי', 'Zeraim', 'זרעים', 7),
  MishnahMasechta('Mishnah Kilayim', 'Kilayim', 'כלאים', 'Zeraim', 'זרעים', 9),
  MishnahMasechta('Mishnah Sheviit', 'Sheviit', 'שביעית', 'Zeraim', 'זרעים', 10),
  MishnahMasechta('Mishnah Terumot', 'Terumot', 'תרומות', 'Zeraim', 'זרעים', 11),
  MishnahMasechta('Mishnah Maasrot', 'Maasrot', 'מעשרות', 'Zeraim', 'זרעים', 5),
  MishnahMasechta('Mishnah Maaser Sheni', 'Maaser Sheni', 'מעשר שני', 'Zeraim', 'זרעים', 5),
  MishnahMasechta('Mishnah Challah', 'Challah', 'חלה', 'Zeraim', 'זרעים', 4),
  MishnahMasechta('Mishnah Orlah', 'Orlah', 'ערלה', 'Zeraim', 'זרעים', 3),
  MishnahMasechta('Mishnah Bikkurim', 'Bikkurim', 'ביכורים', 'Zeraim', 'זרעים', 4),
  MishnahMasechta('Mishnah Shabbat', 'Shabbat', 'שבת', 'Moed', 'מועד', 24),
  MishnahMasechta('Mishnah Eruvin', 'Eruvin', 'עירובין', 'Moed', 'מועד', 10),
  MishnahMasechta('Mishnah Pesachim', 'Pesachim', 'פסחים', 'Moed', 'מועד', 10),
  MishnahMasechta('Mishnah Shekalim', 'Shekalim', 'שקלים', 'Moed', 'מועד', 8),
  MishnahMasechta('Mishnah Yoma', 'Yoma', 'יומא', 'Moed', 'מועד', 8),
  MishnahMasechta('Mishnah Sukkah', 'Sukkah', 'סוכה', 'Moed', 'מועד', 5),
  MishnahMasechta('Mishnah Beitzah', 'Beitzah', 'ביצה', 'Moed', 'מועד', 5),
  MishnahMasechta('Mishnah Rosh Hashanah', 'Rosh Hashanah', 'ראש השנה', 'Moed', 'מועד', 4),
  MishnahMasechta("Mishnah Ta'anit", "Ta'anit", 'תענית', 'Moed', 'מועד', 4),
  MishnahMasechta('Mishnah Megillah', 'Megillah', 'מגילה', 'Moed', 'מועד', 4),
  MishnahMasechta('Mishnah Moed Katan', 'Moed Katan', 'מועד קטן', 'Moed', 'מועד', 3),
  MishnahMasechta('Mishnah Chagigah', 'Chagigah', 'חגיגה', 'Moed', 'מועד', 3),
  MishnahMasechta('Mishnah Yevamot', 'Yevamot', 'יבמות', 'Nashim', 'נשים', 16),
  MishnahMasechta('Mishnah Ketubot', 'Ketubot', 'כתובות', 'Nashim', 'נשים', 13),
  MishnahMasechta('Mishnah Nedarim', 'Nedarim', 'נדרים', 'Nashim', 'נשים', 11),
  MishnahMasechta('Mishnah Nazir', 'Nazir', 'נזיר', 'Nashim', 'נשים', 9),
  MishnahMasechta('Mishnah Sotah', 'Sotah', 'סוטה', 'Nashim', 'נשים', 9),
  MishnahMasechta('Mishnah Gittin', 'Gittin', 'גיטין', 'Nashim', 'נשים', 9),
  MishnahMasechta('Mishnah Kiddushin', 'Kiddushin', 'קידושין', 'Nashim', 'נשים', 4),
  MishnahMasechta('Mishnah Bava Kamma', 'Bava Kamma', 'בבא קמא', 'Nezikin', 'נזיקין', 10),
  MishnahMasechta('Mishnah Bava Metzia', 'Bava Metzia', 'בבא מציעא', 'Nezikin', 'נזיקין', 10),
  MishnahMasechta('Mishnah Bava Batra', 'Bava Batra', 'בבא בתרא', 'Nezikin', 'נזיקין', 10),
  MishnahMasechta('Mishnah Sanhedrin', 'Sanhedrin', 'סנהדרין', 'Nezikin', 'נזיקין', 11),
  MishnahMasechta('Mishnah Makkot', 'Makkot', 'מכות', 'Nezikin', 'נזיקין', 3),
  MishnahMasechta('Mishnah Shevuot', 'Shevuot', 'שבועות', 'Nezikin', 'נזיקין', 8),
  MishnahMasechta('Mishnah Eduyot', 'Eduyot', 'עדיות', 'Nezikin', 'נזיקין', 8),
  MishnahMasechta('Mishnah Avodah Zarah', 'Avodah Zarah', 'עבודה זרה', 'Nezikin', 'נזיקין', 5),
  MishnahMasechta('Pirkei Avot', 'Avot', 'אבות', 'Nezikin', 'נזיקין', 6),
  MishnahMasechta('Mishnah Horayot', 'Horayot', 'הוריות', 'Nezikin', 'נזיקין', 3),
  MishnahMasechta('Mishnah Zevachim', 'Zevachim', 'זבחים', 'Kodashim', 'קדשים', 14),
  MishnahMasechta('Mishnah Menachot', 'Menachot', 'מנחות', 'Kodashim', 'קדשים', 13),
  MishnahMasechta('Mishnah Chullin', 'Chullin', 'חולין', 'Kodashim', 'קדשים', 12),
  MishnahMasechta('Mishnah Bekhorot', 'Bekhorot', 'בכורות', 'Kodashim', 'קדשים', 9),
  MishnahMasechta('Mishnah Arakhin', 'Arakhin', 'ערכין', 'Kodashim', 'קדשים', 9),
  MishnahMasechta('Mishnah Temurah', 'Temurah', 'תמורה', 'Kodashim', 'קדשים', 7),
  MishnahMasechta('Mishnah Keritot', 'Keritot', 'כריתות', 'Kodashim', 'קדשים', 6),
  MishnahMasechta('Mishnah Meilah', 'Meilah', 'מעילה', 'Kodashim', 'קדשים', 6),
  MishnahMasechta('Mishnah Tamid', 'Tamid', 'תמיד', 'Kodashim', 'קדשים', 7),
  MishnahMasechta('Mishnah Middot', 'Middot', 'מדות', 'Kodashim', 'קדשים', 5),
  MishnahMasechta('Mishnah Kinnim', 'Kinnim', 'קינים', 'Kodashim', 'קדשים', 3),
  MishnahMasechta('Mishnah Kelim', 'Kelim', 'כלים', 'Tahorot', 'טהרות', 30),
  MishnahMasechta('Mishnah Oholot', 'Oholot', 'אהלות', 'Tahorot', 'טהרות', 18),
  MishnahMasechta('Mishnah Negaim', 'Negaim', 'נגעים', 'Tahorot', 'טהרות', 14),
  MishnahMasechta('Mishnah Parah', 'Parah', 'פרה', 'Tahorot', 'טהרות', 12),
  MishnahMasechta('Mishnah Tahorot', 'Tahorot', 'טהרות', 'Tahorot', 'טהרות', 10),
  MishnahMasechta('Mishnah Mikvaot', 'Mikvaot', 'מקואות', 'Tahorot', 'טהרות', 10),
  MishnahMasechta('Mishnah Niddah', 'Niddah', 'נדה', 'Tahorot', 'טהרות', 10),
  MishnahMasechta('Mishnah Makhshirin', 'Makhshirin', 'מכשירין', 'Tahorot', 'טהרות', 6),
  MishnahMasechta('Mishnah Zavim', 'Zavim', 'זבים', 'Tahorot', 'טהרות', 5),
  MishnahMasechta('Mishnah Tevul Yom', 'Tevul Yom', 'טבול יום', 'Tahorot', 'טהרות', 4),
  MishnahMasechta('Mishnah Yadayim', 'Yadayim', 'ידים', 'Tahorot', 'טהרות', 4),
  MishnahMasechta('Mishnah Oktzin', 'Oktzin', 'עוקצים', 'Tahorot', 'טהרות', 3),
];

const kitzurId = 'Kitzur Shulchan Arukh';
const kitzurSimanim = 221;

final _books = <String, StudyBook>{
  for (final t in tractates) t.sefaria: StudyBook(StudyKind.bavli, t.sefaria, t.sefaria, t.he, t.seder, t.sederHe, t.amudim),
  for (final m in mishnahMasechtos)
    m.id: StudyBook(StudyKind.mishnah, m.id, m.en, m.he, m.seder, m.sederHe, [for (var i = 1; i <= m.perakim; i++) '$i']),
  kitzurId: StudyBook(StudyKind.kitzur, kitzurId, 'Kitzur Shulchan Aruch', 'קיצור שולחן ערוך', '', '', [for (var i = 1; i <= kitzurSimanim; i++) '$i']),
};

/// A book by its Sefaria title (or, for the Bavli, any spelling
/// [tractateNamed] knows).
StudyBook? studyBook(String id) => _books[id] ?? switch (tractateNamed(id)) { final t? => _books[t.sefaria], null => null };

List<StudyBook> booksOf(StudyKind kind) => [for (final b in _books.values) if (b.kind == kind) b];

/// A place in a book's text: a unit and the range of passages to mark
/// (0-based, inclusive), as a day's learning is.
typedef YomiPlace = ({String book, String unit, int? from, int? to});

/// Today's Daf Yomi: the amud a of the daf (the page shows both amudim).
YomiPlace? dafYomiPlace(PlainDate date) {
  try {
    final page = DafYomiEvent(HDate.fromAbs(date.abs)).daf;
    final t = tractateNamed(page.getName());
    final amud = '${page.getBlatt()}a';
    if (t == null || !t.contains(amud)) return null;
    return (book: t.sefaria, unit: amud, from: null, to: null);
  } catch (_) {
    return null;
  }
}

/// Hebcal's Mishnah names → Sefaria titles.
String mishnahTitle(String hebcal) => switch (hebcal) {
      'Avot' => 'Pirkei Avot',
      'Taanit' => "Mishnah Ta'anit",
      _ => 'Mishnah $hebcal',
    };

/// Today's Mishnah Yomi: two mishnayos, usually in one perek (when they span
/// two, the first perek, through its end).
YomiPlace? mishnahYomiPlace(PlainDate date) {
  try {
    final m = mishnaYomi(date.abs);
    final (c1, v1) = _cv(m.first.v);
    final (c2, v2) = _cv(m.last.v);
    final book = mishnahTitle(m.first.k);
    if (studyBook(book) == null) return null;
    final sameUnit = m.first.k == m.last.k && c1 == c2;
    return (book: book, unit: '$c1', from: v1 - 1, to: sameUnit ? v2 - 1 : null);
  } catch (_) {
    return null;
  }
}

(int, int) _cv(String s) {
  final p = s.split(':');
  return (int.parse(p[0]), int.parse(p[1]));
}
