// Port of @hebcal/core event.ts, HolidayEvent.ts, YomKippurKatanEvent.ts,
// HebrewDateEvent.ts, ParshaEvent.ts, parshaName.ts, string.ts
// Hebcal - A Jewish Calendar Generator
// Copyright (c) 1994-2020 Danny Sadinoff
// Portions copyright Eyal Schachter and Michael J. Radwin
// Dart port licensed under GPL-2.0-or-later.

import 'hdate.dart';
import 'locale.dart';
import 'sedra.dart';

/// Holiday flags for Event.
abstract final class Flags {
  static const int chag = 0x000001;
  static const int lightCandles = 0x000002;
  static const int yomTovEnds = 0x000004;
  static const int chulOnly = 0x000008;
  static const int ilOnly = 0x000010;
  static const int lightCandlesTzeis = 0x000020;
  static const int chanukahCandles = 0x000040;
  static const int roshChodesh = 0x000080;
  static const int minorFast = 0x000100;
  static const int specialShabbat = 0x000200;
  static const int parshaHashavua = 0x000400;
  static const int dafYomi = 0x000800;
  static const int omerCount = 0x001000;
  static const int modernHoliday = 0x002000;
  static const int majorFast = 0x004000;
  static const int shabbatMevarchim = 0x008000;
  static const int molad = 0x010000;
  static const int userEvent = 0x020000;
  static const int hebrewDate = 0x040000;
  static const int minorHoliday = 0x080000;
  static const int erev = 0x100000;
  static const int cholHamoed = 0x200000;
  static const int mishnaYomi = 0x400000;
  static const int yomKippurKatan = 0x800000;
  static const int yerushalmiYomi = 0x1000000;
  static const int nachYomi = 0x2000000;
  static const int dailyLearning = 0x4000000;
  static const int yizkor = 0x8000000;
  static const int behab = 0x10000000;

  static const Map<String, int> byName = {
    'CHAG': chag,
    'LIGHT_CANDLES': lightCandles,
    'YOM_TOV_ENDS': yomTovEnds,
    'CHUL_ONLY': chulOnly,
    'IL_ONLY': ilOnly,
    'LIGHT_CANDLES_TZEIS': lightCandlesTzeis,
    'CHANUKAH_CANDLES': chanukahCandles,
    'ROSH_CHODESH': roshChodesh,
    'MINOR_FAST': minorFast,
    'SPECIAL_SHABBAT': specialShabbat,
    'PARSHA_HASHAVUA': parshaHashavua,
    'DAF_YOMI': dafYomi,
    'OMER_COUNT': omerCount,
    'MODERN_HOLIDAY': modernHoliday,
    'MAJOR_FAST': majorFast,
    'SHABBAT_MEVARCHIM': shabbatMevarchim,
    'MOLAD': molad,
    'USER_EVENT': userEvent,
    'HEBREW_DATE': hebrewDate,
    'MINOR_HOLIDAY': minorHoliday,
    'EREV': erev,
    'CHOL_HAMOED': cholHamoed,
    'MISHNA_YOMI': mishnaYomi,
    'YOM_KIPPUR_KATAN': yomKippurKatan,
    'YERUSHALMI_YOMI': yerushalmiYomi,
    'NACH_YOMI': nachYomi,
    'DAILY_LEARNING': dailyLearning,
    'YIZKOR': yizkor,
    'BEHAB': behab,
  };
}

const _flagToCategory = <(int, List<String>)>[
  (Flags.majorFast, ['holiday', 'major', 'fast']),
  (Flags.chanukahCandles, ['holiday', 'minor']),
  (Flags.hebrewDate, ['hebdate']),
  (Flags.minorFast, ['holiday', 'fast']),
  (Flags.minorHoliday, ['holiday', 'minor']),
  (Flags.modernHoliday, ['holiday', 'modern']),
  (Flags.molad, ['molad']),
  (Flags.omerCount, ['omer']),
  (Flags.parshaHashavua, ['parashat']),
  (Flags.roshChodesh, ['roshchodesh']),
  (Flags.shabbatMevarchim, ['mevarchim']),
  (Flags.specialShabbat, ['holiday', 'shabbat']),
  (Flags.userEvent, ['user']),
  (Flags.yizkor, ['yizkor']),
];

String smartApostrophe(String str) => str.replaceAll("'", '’');
String urlFriendly(String str) =>
    str.toLowerCase().replaceAll("'", '').replaceAll(' ', '-');

/// Represents an Event with a title, date, and flags.
class Event {
  final HDate date;
  final String desc;
  int mask;
  String? emoji;
  String? memo;

  /// Optional alarm time.
  DateTime? alarm;

  /// For events such as Yizkor, the holiday this is attached to.
  Event? linkedEventRef;

  Event(this.date, this.desc, [this.mask = 0, this.emoji]);

  HDate getDate() => date;
  DateTime greg() => date.greg();
  String getDesc() => desc;
  int getFlags() => mask;

  bool hasFlag(int flag) => (mask & flag) != 0;
  bool hasAnyFlag(List<int> flags) =>
      (mask & flags.fold<int>(0, (a, b) => a | b)) != 0;

  List<String> flagNames() => [
        for (final e in Flags.byName.entries)
          if (mask & e.value != 0) e.key,
      ];

  String render([String? locale]) => Locale.gettext(desc, locale);
  String renderBrief([String? locale]) => render(locale);
  String? getEmoji() => emoji;
  String basename() => getDesc();
  String? url() => null;

  bool observedInIsrael() => !hasFlag(Flags.chulOnly);
  bool observedInDiaspora() => !hasFlag(Flags.ilOnly);
  bool observedIn(bool il) => il ? observedInIsrael() : observedInDiaspora();

  List<String> getCategories() {
    for (final (bit, cats) in _flagToCategory) {
      if (mask & bit != 0) return cats;
    }
    return const ['unknown'];
  }

  @override
  String toString() => '${date.greg().toIso8601String().substring(0, 10)} $desc';
}

/// Represents a built-in holiday like Pesach, Purim or Tu BiShvat.
class HolidayEvent extends Event {
  /// During Sukkot or Pesach, the day of Chol HaMoed (-1 for Hoshana Raba).
  int? cholHaMoedDay;

  /// True if the fast day was postponed a day to avoid Shabbat.
  bool observed;

  HolidayEvent(super.date, super.desc,
      [super.mask = 0, super.emoji, this.cholHaMoedDay, this.observed = false]);

  @override
  String basename() => getDesc()
      .replaceFirst(RegExp(r' \d{4}$'), '')
      .replaceFirst(RegExp(r" \(CH''M\)$"), '')
      .replaceFirst(RegExp(r' \(observed\)$'), '')
      .replaceFirst(RegExp(r' \(Hoshana Raba\)$'), '')
      .replaceFirst(RegExp(r' [IV]+$'), '')
      .replaceFirst(RegExp(r': \d Candles?$'), '')
      .replaceFirst(RegExp(r': 8th Day$'), '')
      .replaceFirst(RegExp(r'^Erev '), '');

  @override
  String? url() {
    final year = greg().year;
    if (year < 100 || year > 2999) return null;
    final url =
        'https://www.hebcal.com/holidays/${urlFriendly(basename())}-${urlDateSuffix()}';
    return hasFlag(Flags.ilOnly) ? '$url?i=on' : url;
  }

  String urlDateSuffix() => '${greg().year}';

  @override
  String getEmoji() {
    if (emoji != null) return emoji!;
    if (hasFlag(Flags.specialShabbat)) return '🕍';
    return '✡️';
  }

  @override
  List<String> getCategories() {
    if (cholHaMoedDay != null) return const ['holiday', 'major', 'cholhamoed'];
    final cats = super.getCategories();
    if (cats[0] != 'unknown') return cats;
    switch (getDesc()) {
      case HolidayDesc.lagBaOmer:
      case HolidayDesc.leilSelichot:
      case HolidayDesc.pesachSheni:
      case HolidayDesc.erevPurim:
      case HolidayDesc.purimKatan:
      case HolidayDesc.shushanPurim:
      case HolidayDesc.tuBav:
      case HolidayDesc.tuBishvat:
      case HolidayDesc.roshHashanaLabehemot:
        return const ['holiday', 'minor'];
    }
    return const ['holiday', 'major'];
  }

  @override
  String render([String? locale]) => smartApostrophe(super.render(locale));

  @override
  String renderBrief([String? locale]) =>
      smartApostrophe(super.renderBrief(locale));
}

class AsaraBTevetEvent extends HolidayEvent {
  AsaraBTevetEvent(super.date, super.desc, [super.mask]);

  @override
  String urlDateSuffix() {
    final d = greg();
    return '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  }
}

const _keycapDigits = ['0️⃣', '1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣', '6️⃣', '7️⃣', '8️⃣', '9️⃣'];

/// Because Chanukah sometimes starts in December and ends in January,
/// this class is used for URL suffixes.
class ChanukahEvent extends HolidayEvent {
  /// Number of days since first night (null for first candle).
  final int? chanukahDay;

  /// When candle-lighting times are computed, the time for this night.
  DateTime? eventTime;

  ChanukahEvent(super.date, super.desc, super.mask, this.chanukahDay) {
    emoji = '🕎';
    if (chanukahDay != 8) {
      final candles = chanukahDay != null ? chanukahDay! + 1 : 1;
      emoji = emoji! + _keycapDigits[candles];
    }
  }

  @override
  String urlDateSuffix() {
    final dt = greg();
    return '${dt.month == 1 ? dt.year - 1 : dt.year}';
  }
}

class RoshHashanaEvent extends HolidayEvent {
  final int hyear;
  RoshHashanaEvent(HDate date, this.hyear, int mask)
      : super(date, 'Rosh Hashana $hyear', mask);

  @override
  String render([String? locale]) =>
      '${Locale.gettext('Rosh Hashana', locale)} $hyear';

  @override
  String getEmoji() => '🍏🍯';
}

const _roshChodeshStr = 'Rosh Chodesh';

class RoshChodeshEvent extends HolidayEvent {
  RoshChodeshEvent(HDate date, String monthName)
      : super(date, '$_roshChodeshStr $monthName', Flags.roshChodesh);

  @override
  String render([String? locale]) {
    final monthName = getDesc().substring(_roshChodeshStr.length + 1);
    return '${Locale.gettext(_roshChodeshStr, locale)} ${smartApostrophe(Locale.gettext(monthName, locale))}';
  }

  @override
  String basename() => getDesc();

  @override
  String getEmoji() => emoji ?? '🌒';
}

const _ykk = 'Yom Kippur Katan';

class YomKippurKatanEvent extends HolidayEvent {
  final String nextMonthName;
  YomKippurKatanEvent(HDate date, this.nextMonthName)
      : super(date, '$_ykk $nextMonthName', Flags.minorFast | Flags.yomKippurKatan) {
    memo = 'Minor Day of Atonement on the day preceeding Rosh Chodesh $nextMonthName';
  }

  @override
  String basename() => getDesc();

  @override
  String render([String? locale]) =>
      '${Locale.gettext(_ykk, locale)} ${smartApostrophe(Locale.gettext(nextMonthName, locale))}';

  @override
  String renderBrief([String? locale]) => Locale.gettext(_ykk, locale);

  @override
  String? url() => null;
}

/// Daily Hebrew date ("11th of Sivan, 5780").
class HebrewDateEvent extends Event {
  HebrewDateEvent(HDate date) : super(date, date.toString(), Flags.hebrewDate);

  @override
  String render([String? locale]) {
    final l = (locale ?? 'en').toLowerCase();
    switch (l) {
      case 'h':
      case 'he':
        return date.renderGematriya(false);
      case 'he-x-nonikud':
        return date.renderGematriya(true);
      default:
        return date.render(l, true);
    }
  }

  @override
  String renderBrief([String? locale]) {
    final l = (locale ?? 'en').toLowerCase();
    if (date.getMonth() == Months.tishrei && date.getDate() == 1) {
      return render(l);
    }
    switch (l) {
      case 'h':
      case 'he':
      case 'he-x-nonikud':
        return '${gematriya(date.getDate())} ${Locale.gettext(date.getMonthName(), l)}';
      default:
        return date.render(l, false);
    }
  }
}

/// Renders "Parashat X" or "Parashat X-Y" in the given locale.
String renderParshaName(List<String> parsha, [String? locale]) {
  var name = Locale.gettext(parsha[0], locale);
  if (parsha.length == 2) {
    final hyphen = Locale.isHebrewLocale(locale) ? '־' : '-';
    name += hyphen + Locale.gettext(parsha[1], locale);
  }
  return '${Locale.gettext('Parashat', locale)} ${smartApostrophe(name)}';
}

/// Represents one of 54 weekly Torah portions, always on a Saturday.
class ParshaEvent extends Event {
  final SedraResult p;
  ParshaEvent(this.p)
      : super(p.hdate, 'Parashat ${p.parsha.join('-')}', Flags.parshaHashavua);

  List<String> get parsha => p.parsha;

  @override
  String render([String? locale]) => renderParshaName(p.parsha, locale);

  @override
  String basename() => p.parsha.join('-');

  @override
  String? url() {
    final d = greg();
    if (d.year < 100 || d.year > 2999) return null;
    final ymd =
        '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    final url = 'https://www.hebcal.com/sedrot/${urlFriendly(basename())}-$ymd';
    return p.il ? '$url?i=on' : url;
  }
}

/// Transliterated names of holidays, used by [Event.getDesc].
abstract final class HolidayDesc {
  static const asaraBtevet = "Asara B'Tevet";
  static const birkatHachamah = 'Birkat Hachamah';
  static const chagHabanot = 'Chag HaBanot';
  static const chanukah8thDay = 'Chanukah: 8th Day';
  static const erevTishaBav = "Erev Tish'a B'Av";
  static const leilSelichot = 'Leil Selichot';
  static const purimKatan = 'Purim Katan';
  static const purimMeshulash = 'Purim Meshulash';
  static const shabbatChazon = 'Shabbat Chazon';
  static const shabbatHachodesh = 'Shabbat HaChodesh';
  static const shabbatHagadol = 'Shabbat HaGadol';
  static const shabbatNachamu = 'Shabbat Nachamu';
  static const shabbatParah = 'Shabbat Parah';
  static const shabbatShekalim = 'Shabbat Shekalim';
  static const shabbatShirah = 'Shabbat Shirah';
  static const shabbatShuva = 'Shabbat Shuva';
  static const shabbatZachor = 'Shabbat Zachor';
  static const shushanPurimKatan = 'Shushan Purim Katan';
  static const taanitBechorot = "Ta'anit Bechorot";
  static const taanitBehab = "Ta'anit BeHaB";
  static const taanitEsther = "Ta'anit Esther";
  static const tishaBav = "Tish'a B'Av";
  static const tzomGedaliah = 'Tzom Gedaliah';
  static const tzomTammuz = 'Tzom Tammuz';
  static const yomHaatzmaUt = "Yom HaAtzma'ut";
  static const yomHashoah = 'Yom HaShoah';
  static const yomHazikaron = 'Yom HaZikaron';
  static const roshHashanaII = 'Rosh Hashana II';
  static const erevYomKippur = 'Erev Yom Kippur';
  static const yomKippur = 'Yom Kippur';
  static const erevSukkot = 'Erev Sukkot';
  static const sukkotI = 'Sukkot I';
  static const sukkotII = 'Sukkot II';
  static const sukkotIIIChm = "Sukkot III (CH''M)";
  static const sukkotIVChm = "Sukkot IV (CH''M)";
  static const sukkotVChm = "Sukkot V (CH''M)";
  static const sukkotVIChm = "Sukkot VI (CH''M)";
  static const shminiAtzeret = 'Shmini Atzeret';
  static const simchatTorah = 'Simchat Torah';
  static const sukkotIIChm = "Sukkot II (CH''M)";
  static const sukkotVIIHoshanaRaba = 'Sukkot VII (Hoshana Raba)';
  static const chanukah1Candle = 'Chanukah: 1 Candle';
  static const tuBishvat = 'Tu BiShvat';
  static const erevPurim = 'Erev Purim';
  static const purim = 'Purim';
  static const shushanPurim = 'Shushan Purim';
  static const erevPesach = 'Erev Pesach';
  static const pesachI = 'Pesach I';
  static const pesachII = 'Pesach II';
  static const pesachIIChm = "Pesach II (CH''M)";
  static const pesachIIIChm = "Pesach III (CH''M)";
  static const pesachIVChm = "Pesach IV (CH''M)";
  static const pesachVChm = "Pesach V (CH''M)";
  static const pesachVIChm = "Pesach VI (CH''M)";
  static const pesachVII = 'Pesach VII';
  static const pesachVIII = 'Pesach VIII';
  static const pesachSheni = 'Pesach Sheni';
  static const lagBaOmer = 'Lag BaOmer';
  static const erevShavuot = 'Erev Shavuot';
  static const shavuot = 'Shavuot';
  static const shavuotI = 'Shavuot I';
  static const shavuotII = 'Shavuot II';
  static const tuBav = "Tu B'Av";
  static const roshHashanaLabehemot = 'Rosh Hashana LaBehemot';
  static const erevRoshHashana = 'Erev Rosh Hashana';
  static const yomYerushalayim = 'Yom Yerushalayim';
  static const benGurionDay = 'Ben-Gurion Day';
  static const familyDay = 'Family Day';
  static const yitzhakRabinMemorialDay = 'Yitzhak Rabin Memorial Day';
  static const herzlDay = 'Herzl Day';
  static const jabotinskyDay = 'Jabotinsky Day';
  static const sigd = 'Sigd';
  static const yomHaaliyah = 'Yom HaAliyah';
  static const yomHaaliyahSchoolObservance = 'Yom HaAliyah School Observance';
  static const hebrewLanguageDay = 'Hebrew Language Day';
  static const candleLighting = 'Candle lighting';
  static const havdalah = 'Havdalah';
  static const fastBegins = 'Fast begins';
  static const fastEnds = 'Fast ends';
  static const biurChametz = 'Biur Chametz';
  static const sofZmanAchilatChametz = 'Finish eating chametz';
  static const yizkor = 'Yizkor';
}
