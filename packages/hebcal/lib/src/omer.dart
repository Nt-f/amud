// Port of @hebcal/core omer.ts
// Hebcal - A Jewish Calendar Generator
// Copyright (c) 1994-2020 Danny Sadinoff
// Portions copyright Eyal Schachter and Michael J. Radwin
// Dart port licensed under GPL-2.0-or-later.

import 'data/core_data.g.dart' as data;
import 'event.dart';
import 'hdate.dart';
import 'locale.dart';

enum OmerLang { en, he, translit }

class _SefiraConfig {
  final String? infix;
  final String? infix26;
  final List<String> words;
  final List<String>? pfxWords;
  const _SefiraConfig(this.infix, this.infix26, this.words, this.pfxWords);
}

const _sefirot = {
  OmerLang.en: _SefiraConfig('within ', 'within ', [
    '', 'Lovingkindness', 'Might', 'Beauty', 'Eternity', 'Splendor', //
    'Foundation', 'Majesty',
  ], null),
  OmerLang.he: _SefiraConfig(null, null, [
    '', 'חֶֽסֶד', 'גְּבוּרָה', 'תִּפְאֶֽרֶת', 'נֶּֽצַח', 'הוֹד', 'יְּסוֹד', 'מַלְכוּת', //
  ], [
    '', 'שֶׁבְּחֶֽסֶד', 'שֶׁבִּגְבוּרָה', 'שֶׁבְּתִפְאֶֽרֶת', 'שֶׁבְּנֶֽצַח', 'שֶׁבְּהוֹד', //
    'שֶׁבִּיְסוֹד', 'שֶׁבְּמַלְכוּת',
  ]),
  OmerLang.translit: _SefiraConfig("sheb'", 'shebi', [
    '', 'Chesed', 'Gevurah', 'Tiferet', 'Netzach', 'Hod', 'Yesod', 'Malkhut', //
  ], null),
};

(int, int) _getWeeks(int omerDay) =>
    ((omerDay - 1) ~/ 7 + 1, omerDay % 7 == 0 ? 7 : omerDay % 7);

String _omerTodayIsEn(int omerDay) {
  final (weekNumber, daysWithinWeeks) = _getWeeks(omerDay);
  var str = 'Today is $omerDay ${omerDay == 1 ? 'day' : 'days'}';
  if (weekNumber > 1 || omerDay == 7) {
    final day7 = daysWithinWeeks == 7;
    final numWeeks = day7 ? weekNumber : weekNumber - 1;
    str += ', which are $numWeeks ${numWeeks == 1 ? 'week' : 'weeks'}';
    if (!day7) {
      str += ' and $daysWithinWeeks ${daysWithinWeeks == 1 ? 'day' : 'days'}';
    }
  }
  return '$str of the Omer';
}

const _tens = ['', 'עֲשָׂרָה', 'עֶשְׂרִים', 'שְׁלוֹשִׁים', 'אַרְבָּעִים'];
const _ones = ['', 'אֶחָד', 'שְׁנַיִם', 'שְׁלוֹשָׁה', 'אַרְבָּעָה', 'חֲמִשָּׁה', 'שִׁשָּׁה', 'שִׁבְעָה', 'שְׁמוֹנָה', 'תִּשְׁעָה'];
const _shnei = 'שְׁנֵי';
const _yamim = 'יָמִים';
const _shneiYamim = '$_shnei $_yamim';
const _shavuot = 'שָׁבוּעוֹת';
const _yom = 'יוֹם';
const _yomEchad = '$_yom אֶחָד';
const _asar = 'עָשָׂר';

String _omerTodayIsHe(int omerDay) {
  final ten = omerDay ~/ 10;
  final one = omerDay % 10;
  var str = 'הַיּוֹם ';
  if (omerDay == 11) {
    str += 'אַחַד $_asar';
  } else if (omerDay == 12) {
    str += 'שְׁנֵים $_asar';
  } else if (12 < omerDay && omerDay < 20) {
    str += '${_ones[one]} $_asar';
  } else if (omerDay > 9) {
    str += _ones[one];
    if (one != 0) {
      str += ' ';
      str += ten == 3 ? 'וּ' : 'וְ';
    }
  }
  if (omerDay > 2) {
    if (omerDay > 20 || omerDay == 10 || omerDay == 20) str += _tens[ten];
    if (omerDay < 11) {
      str += '${_ones[one]} $_yamim ';
    } else {
      str += ' $_yom ';
    }
  } else if (omerDay == 1) {
    str += '$_yomEchad ';
  } else {
    str += '$_shneiYamim ';
  }
  if (omerDay > 6) {
    str = str.trim();
    str += ', שֶׁהֵם ';
    final weeks = omerDay ~/ 7;
    final days = omerDay % 7;
    if (weeks > 2) {
      str += '${_ones[weeks]} $_shavuot ';
    } else if (weeks == 1) {
      str += 'שָׁבֽוּעַ ${_ones[1]} ';
    } else {
      str += '$_shnei $_shavuot ';
    }
    if (days != 0) {
      if (days == 2 || days == 3) {
        str += 'וּ';
      } else if (days == 5) {
        str += 'וַ';
      } else {
        str += 'וְ';
      }
      if (days > 2) {
        str += '${_ones[days]} $_yamim ';
      } else if (days == 1) {
        str += '$_yomEchad ';
      } else {
        str += '$_shneiYamim ';
      }
    }
  }
  return '$strלָעֽוֹמֶר';
}

final List<String> _lamnatzeach =
    data.ps67lines.expand((x) => x.split(RegExp('[ ־]'))).toList();

/// Represents a day 1-49 of Sefirat haOmer.
class OmerEvent extends Event {
  final int omer;
  final int weekNumber;
  final int daysWithinWeeks;

  OmerEvent(HDate date, int omerDay)
      : omer = omerDay,
        weekNumber = (omerDay - 1) ~/ 7 + 1,
        daysWithinWeeks = omerDay % 7 == 0 ? 7 : omerDay % 7,
        super(date, 'Omer $omerDay', Flags.omerCount) {
    if (omerDay < 1 || omerDay > 49) {
      throw RangeError('Invalid Omer day $omerDay');
    }
  }

  /// Sefira, e.g. "Lovingkindness within Might" / "חֶֽסֶד שֶׁבִּגְבוּרָה".
  String sefira([OmerLang lang = OmerLang.en]) {
    final (weekNum, daysWithin) = _getWeeks(omer);
    final config = _sefirot[lang]!;
    final pfx = config.pfxWords;
    final week = pfx != null ? pfx[weekNum] : config.words[weekNum];
    final dayWithinWeek = config.words[daysWithin];
    final infix = pfx != null
        ? ''
        : weekNum == 2 || weekNum == 6
            ? config.infix26!
            : config.infix!;
    return '$dayWithinWeek $infix$week';
  }

  @override
  String render([String? locale]) {
    final nth = Locale.isHebrewLocale(locale)
        ? gematriya(omer)
        : Locale.ordinal(omer, locale);
    return '$nth ${Locale.gettext('day of the Omer', locale)}';
  }

  @override
  String renderBrief([String? locale]) =>
      '${Locale.gettext('Omer', locale)} ${Locale.gettext('day', locale)} $omer';

  @override
  String getEmoji() {
    if (emoji != null) return emoji!;
    int codePoint;
    if (omer <= 20) {
      codePoint = 9312 + omer - 1;
    } else if (omer <= 35) {
      codePoint = 12881 + omer - 21;
    } else {
      codePoint = 12977 + omer - 36;
    }
    return String.fromCharCode(codePoint);
  }

  int getWeeks() => daysWithinWeeks == 7 ? weekNumber : weekNumber - 1;
  int getDaysWithinWeeks() => daysWithinWeeks;

  /// "Today is 10 days, which are 1 week and 3 days of the Omer" or the
  /// full Hebrew counting formula.
  String getTodayIs([String locale = 'en']) {
    final l = locale.toLowerCase();
    final str = Locale.isHebrewLocale(l) ? _omerTodayIsHe(omer) : _omerTodayIsEn(omer);
    if (l == 'he-x-nonikud') return hebrewStripNikkud(str);
    return str;
  }

  @override
  String? url() {
    final year = date.getFullYear();
    if (year < 5000 || year > 6759) return null;
    return 'https://www.hebcal.com/omer/$year/$omer';
  }

  /// The word from Psalm 67 (Lamnatzeach) corresponding to this day.
  String getLamnatzeachWord() => _lamnatzeach[omer - 1];

  /// The letter from Psalm 67:5 corresponding to this day.
  String getLamnatzeachLetter() => data.lamnatzeachLetters.split('')[omer - 1];

  /// The word from Ana BeKoach corresponding to this day.
  String getAnaBekoachWord() => data.anaBekoach[omer - 1];
}

/// Omer day (1-49) for a Hebrew date, or 0 if not during the Omer.
/// Note this is the *daytime* count; the evening before counts the next day.
int omerDay(HDate hd) {
  final beginOmer = hebrew2abs(hd.getFullYear(), Months.nisan, 16);
  final endOmer = hebrew2abs(hd.getFullYear(), Months.sivan, 5);
  final abs = hd.abs();
  if (abs < beginOmer || abs > endOmer) return 0;
  return abs - beginOmer + 1;
}
