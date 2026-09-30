// Port of @hebcal/core holidays.ts, staticHolidays.ts, modern.ts
// Hebcal - A Jewish Calendar Generator
// Copyright (c) 1994-2020 Danny Sadinoff
// Portions copyright Eyal Schachter and Michael J. Radwin
// Dart port licensed under GPL-2.0-or-later.

import 'event.dart';
import 'hdate.dart';
import 'sedra.dart';

typedef H = HolidayDesc;

const _sun = 0;
const _tue = 2;
const _thu = 4;
const _fri = 5;
const _sat = 6;

class _StaticHoliday {
  final int mm;
  final int dd;
  final String desc;
  final int flags;
  final int? chmDay;
  final String? emoji;
  const _StaticHoliday(this.mm, this.dd, this.desc, this.flags, {this.chmDay, this.emoji});
}

const _emojiPesach = '🫓';
const _emojiSukkot = '🌿🍋';
const _chag = Flags.chag;
const _lc = Flags.lightCandles;
const _yte = Flags.yomTovEnds;
const _chul = Flags.chulOnly;
const _il = Flags.ilOnly;
const _lct = Flags.lightCandlesTzeis;
const _majorFast = Flags.majorFast;
const _minorHoliday = Flags.minorHoliday;
const _erev = Flags.erev;
const _chm = Flags.cholHamoed;

const List<_StaticHoliday> _staticHolidays = [
  _StaticHoliday(Months.tishrei, 2, H.roshHashanaII, _chag | _yte, emoji: '🍏🍯'),
  _StaticHoliday(Months.tishrei, 9, H.erevYomKippur, _erev | _lc),
  _StaticHoliday(Months.tishrei, 10, H.yomKippur, _chag | _majorFast | _yte),
  _StaticHoliday(Months.tishrei, 14, H.erevSukkot, _chul | _erev | _lc, emoji: _emojiSukkot),
  _StaticHoliday(Months.tishrei, 15, H.sukkotI, _chul | _chag | _lct, emoji: _emojiSukkot),
  _StaticHoliday(Months.tishrei, 16, H.sukkotII, _chul | _chag | _yte, emoji: _emojiSukkot),
  _StaticHoliday(Months.tishrei, 17, H.sukkotIIIChm, _chul | _chm, chmDay: 1, emoji: _emojiSukkot),
  _StaticHoliday(Months.tishrei, 18, H.sukkotIVChm, _chul | _chm, chmDay: 2, emoji: _emojiSukkot),
  _StaticHoliday(Months.tishrei, 19, H.sukkotVChm, _chul | _chm, chmDay: 3, emoji: _emojiSukkot),
  _StaticHoliday(Months.tishrei, 20, H.sukkotVIChm, _chul | _chm, chmDay: 4, emoji: _emojiSukkot),
  _StaticHoliday(Months.tishrei, 22, H.shminiAtzeret, _chul | _chag | _lct),
  _StaticHoliday(Months.tishrei, 23, H.simchatTorah, _chul | _chag | _yte),
  _StaticHoliday(Months.tishrei, 14, H.erevSukkot, _il | _erev | _lc, emoji: _emojiSukkot),
  _StaticHoliday(Months.tishrei, 15, H.sukkotI, _il | _chag | _yte, emoji: _emojiSukkot),
  _StaticHoliday(Months.tishrei, 16, H.sukkotIIChm, _il | _chm, chmDay: 1, emoji: _emojiSukkot),
  _StaticHoliday(Months.tishrei, 17, H.sukkotIIIChm, _il | _chm, chmDay: 2, emoji: _emojiSukkot),
  _StaticHoliday(Months.tishrei, 18, H.sukkotIVChm, _il | _chm, chmDay: 3, emoji: _emojiSukkot),
  _StaticHoliday(Months.tishrei, 19, H.sukkotVChm, _il | _chm, chmDay: 4, emoji: _emojiSukkot),
  _StaticHoliday(Months.tishrei, 20, H.sukkotVIChm, _il | _chm, chmDay: 5, emoji: _emojiSukkot),
  _StaticHoliday(Months.tishrei, 22, H.shminiAtzeret, _il | _chag | _yte),
  _StaticHoliday(Months.tishrei, 21, H.sukkotVIIHoshanaRaba, _lc | _chm, chmDay: -1, emoji: _emojiSukkot),
  _StaticHoliday(Months.shvat, 15, H.tuBishvat, _minorHoliday, emoji: '🌳'),
  _StaticHoliday(Months.adarII, 13, H.erevPurim, _erev | _minorHoliday, emoji: '🎭️📜'),
  _StaticHoliday(Months.adarII, 14, H.purim, _minorHoliday, emoji: '🎭️📜'),
  _StaticHoliday(Months.adarII, 15, H.shushanPurim, _minorHoliday, emoji: '🎭️📜'),
  _StaticHoliday(Months.nisan, 14, H.erevPesach, _il | _erev | _lc, emoji: '🫓🍷'),
  _StaticHoliday(Months.nisan, 15, H.pesachI, _il | _chag | _yte, emoji: _emojiPesach),
  _StaticHoliday(Months.nisan, 16, H.pesachIIChm, _il | _chm, chmDay: 1, emoji: _emojiPesach),
  _StaticHoliday(Months.nisan, 17, H.pesachIIIChm, _il | _chm, chmDay: 2, emoji: _emojiPesach),
  _StaticHoliday(Months.nisan, 18, H.pesachIVChm, _il | _chm, chmDay: 3, emoji: _emojiPesach),
  _StaticHoliday(Months.nisan, 19, H.pesachVChm, _il | _chm, chmDay: 4, emoji: _emojiPesach),
  _StaticHoliday(Months.nisan, 20, H.pesachVIChm, _il | _chm | _lc, chmDay: 5, emoji: _emojiPesach),
  _StaticHoliday(Months.nisan, 21, H.pesachVII, _il | _chag | _yte, emoji: _emojiPesach),
  _StaticHoliday(Months.nisan, 14, H.erevPesach, _chul | _erev | _lc, emoji: '🫓🍷'),
  _StaticHoliday(Months.nisan, 15, H.pesachI, _chul | _chag | _lct, emoji: '🫓🍷'),
  _StaticHoliday(Months.nisan, 16, H.pesachII, _chul | _chag | _yte, emoji: _emojiPesach),
  _StaticHoliday(Months.nisan, 17, H.pesachIIIChm, _chul | _chm, chmDay: 1, emoji: _emojiPesach),
  _StaticHoliday(Months.nisan, 18, H.pesachIVChm, _chul | _chm, chmDay: 2, emoji: _emojiPesach),
  _StaticHoliday(Months.nisan, 19, H.pesachVChm, _chul | _chm, chmDay: 3, emoji: _emojiPesach),
  _StaticHoliday(Months.nisan, 20, H.pesachVIChm, _chul | _chm | _lc, chmDay: 4, emoji: _emojiPesach),
  _StaticHoliday(Months.nisan, 21, H.pesachVII, _chul | _chag | _lct, emoji: _emojiPesach),
  _StaticHoliday(Months.nisan, 22, H.pesachVIII, _chul | _chag | _yte, emoji: _emojiPesach),
  _StaticHoliday(Months.iyyar, 14, H.pesachSheni, _minorHoliday),
  _StaticHoliday(Months.iyyar, 18, H.lagBaOmer, _minorHoliday, emoji: '🔥'),
  _StaticHoliday(Months.sivan, 5, H.erevShavuot, _erev | _lc, emoji: '⛰️🌸'),
  _StaticHoliday(Months.sivan, 6, H.shavuot, _il | _chag | _yte, emoji: '⛰️🌸'),
  _StaticHoliday(Months.sivan, 6, H.shavuotI, _chul | _chag | _lct, emoji: '⛰️🌸'),
  _StaticHoliday(Months.sivan, 7, H.shavuotII, _chul | _chag | _yte, emoji: '⛰️🌸'),
  _StaticHoliday(Months.av, 15, H.tuBav, _minorHoliday, emoji: '❤️'),
  _StaticHoliday(Months.elul, 1, H.roshHashanaLabehemot, _minorHoliday, emoji: '🐑'),
  _StaticHoliday(Months.elul, 29, H.erevRoshHashana, _erev | _lc, emoji: '🍏🍯'),
];

class _ModernHoliday {
  final int firstYear;
  final int mm;
  final int dd;
  final String desc;
  final bool chul;
  final bool suppressEmoji;
  final bool satPostponeToSun;
  final bool friPostponeToSun;
  final bool friSatMovetoThu;
  const _ModernHoliday(this.firstYear, this.mm, this.dd, this.desc,
      {this.chul = false,
      this.suppressEmoji = false,
      this.satPostponeToSun = false,
      this.friPostponeToSun = false,
      this.friSatMovetoThu = false});
}

const List<_ModernHoliday> _staticModernHolidays = [
  _ModernHoliday(5727, Months.iyyar, 28, H.yomYerushalayim, chul: true),
  _ModernHoliday(5737, Months.kislev, 6, H.benGurionDay, satPostponeToSun: true, friPostponeToSun: true),
  _ModernHoliday(5750, Months.shvat, 30, H.familyDay),
  _ModernHoliday(5758, Months.cheshvan, 12, H.yitzhakRabinMemorialDay, friSatMovetoThu: true),
  _ModernHoliday(5764, Months.iyyar, 10, H.herzlDay, satPostponeToSun: true),
  _ModernHoliday(5765, Months.tamuz, 29, H.jabotinskyDay, satPostponeToSun: true),
  _ModernHoliday(5769, Months.cheshvan, 29, H.sigd, chul: true, suppressEmoji: true, friSatMovetoThu: true),
  _ModernHoliday(5777, Months.nisan, 10, H.yomHaaliyah, chul: true),
  _ModernHoliday(5777, Months.cheshvan, 7, H.yomHaaliyahSchoolObservance),
  _ModernHoliday(5773, Months.tevet, 21, H.hebrewLanguageDay, friSatMovetoThu: true),
];

/// Yom HaShoah first observed in 1951; returns null for earlier years.
HDate? dateYomHaShoah(int year) {
  if (year < 5711) return null;
  var nisan27dt = HDate(27, Months.nisan, year);
  if (nisan27dt.getDay() == _fri) {
    nisan27dt = HDate(26, Months.nisan, year);
  } else if (nisan27dt.getDay() == _sun) {
    nisan27dt = HDate(28, Months.nisan, year);
  }
  return nisan27dt;
}

/// Yom HaAtzma'ut only celebrated after 1948; returns null for earlier.
HDate? dateYomHaZikaron(int year) {
  if (year < 5708) return null;
  int day;
  final pdow = HDate(15, Months.nisan, year).getDay();
  if (pdow == _sun) {
    day = 2;
  } else if (pdow == _sat) {
    day = 3;
  } else if (year < 5764) {
    day = 4;
  } else if (pdow == _tue) {
    day = 5;
  } else {
    day = 4;
  }
  return HDate(day, Months.iyyar, year);
}

/// Map from `HDate.toString()` to holidays on that day.
typedef HolidayYearMap = Map<String, List<HolidayEvent>>;

final Map<int, HolidayYearMap> _yearCache = {};

/// Lower-level holidays interface: all holidays for a Hebrew year, keyed
/// by `HDate.toString()`.
HolidayYearMap getHolidaysForYear(int year) {
  if (year < 1 || year > 32658) {
    throw RangeError('Hebrew year $year out of range 1-32658');
  }
  final cached = _yearCache[year];
  if (cached != null) return cached;

  final rh = HDate(1, Months.tishrei, year);
  final pesach = HDate(15, Months.nisan, year);
  final map = <String, List<HolidayEvent>>{};

  void add(List<HolidayEvent> events) {
    for (final ev in events) {
      final key = ev.date.toString();
      final arr = map[key];
      if (arr != null) {
        if (arr[0].hasFlag(Flags.erev)) {
          arr.insert(0, ev);
        } else {
          arr.add(ev);
        }
      } else {
        map[key] = [ev];
      }
    }
  }

  for (final h in _staticHolidays) {
    add([HolidayEvent(HDate(h.dd, h.mm, year), h.desc, h.flags, h.emoji, h.chmDay)]);
  }

  add([RoshHashanaEvent(rh, year, _chag | _lct)]);

  final tzomGedaliahDay = rh.getDay() == _thu ? 4 : 3;
  add([HolidayEvent(HDate(tzomGedaliahDay, Months.tishrei, year), H.tzomGedaliah, Flags.minorFast)]);
  add([HolidayEvent(HDate.fromAbs(HDate.dayOnOrBefore(_sat, 7 + rh.abs())), H.shabbatShuva, Flags.specialShabbat)]);

  final rchTevet = shortKislev(year)
      ? HDate(1, Months.tevet, year)
      : HDate(30, Months.kislev, year);
  add([HolidayEvent(rchTevet, H.chagHabanot, _minorHoliday)]);

  add([ChanukahEvent(HDate(24, Months.kislev, year), H.chanukah1Candle,
      _erev | _minorHoliday | Flags.chanukahCandles, null)]);
  for (var candles = 2; candles <= 8; candles++) {
    add([ChanukahEvent(HDate(23 + candles, Months.kislev, year),
        'Chanukah: $candles Candles', _minorHoliday | Flags.chanukahCandles, candles - 1)]);
  }
  add([ChanukahEvent(HDate(32, Months.kislev, year), H.chanukah8thDay, _minorHoliday, 8)]);

  add([AsaraBTevetEvent(HDate(10, Months.tevet, year), H.asaraBtevet, Flags.minorFast)]);

  final pesachAbs = pesach.abs();
  add([
    HolidayEvent(HDate.fromAbs(HDate.dayOnOrBefore(_sat, pesachAbs - 43)), H.shabbatShekalim, Flags.specialShabbat),
    HolidayEvent(HDate.fromAbs(HDate.dayOnOrBefore(_sat, pesachAbs - 30)), H.shabbatZachor, Flags.specialShabbat),
    HolidayEvent(HDate.fromAbs(pesachAbs - (pesach.getDay() == _tue ? 33 : 31)), H.taanitEsther, Flags.minorFast),
  ]);

  final haChodeshAbs = HDate.dayOnOrBefore(_sat, pesachAbs - 14);
  add([
    HolidayEvent(HDate.fromAbs(haChodeshAbs - 7), H.shabbatParah, Flags.specialShabbat),
    HolidayEvent(HDate.fromAbs(haChodeshAbs), H.shabbatHachodesh, Flags.specialShabbat),
    HolidayEvent(HDate.fromAbs(HDate.dayOnOrBefore(_sat, pesachAbs - 1)), H.shabbatHagadol, Flags.specialShabbat),
    HolidayEvent(
        pesach.prev().getDay() == _sat ? pesach.onOrBefore(_thu) : HDate(14, Months.nisan, year),
        H.taanitBechorot,
        Flags.minorFast),
  ]);

  add([
    HolidayEvent(
        HDate.fromAbs(HDate.dayOnOrBefore(_sat, HDate(1, Months.tishrei, year + 1).abs() - 4)),
        H.leilSelichot,
        _minorHoliday,
        '🕍'),
  ]);

  if (pesach.getDay() == _sun) {
    add([HolidayEvent(HDate(16, Months.adarII, year), H.purimMeshulash, _minorHoliday)]);
  }

  if (isLeapYear(year)) {
    add([HolidayEvent(HDate(14, Months.adarI, year), H.purimKatan, _minorHoliday, '🎭️')]);
    add([HolidayEvent(HDate(15, Months.adarI, year), H.shushanPurimKatan, _minorHoliday, '🎭️')]);
  }

  final nisan27dt = dateYomHaShoah(year);
  if (nisan27dt != null) {
    add([HolidayEvent(nisan27dt, H.yomHashoah, Flags.modernHoliday)]);
  }

  final yomHaZikaronDt = dateYomHaZikaron(year);
  if (yomHaZikaronDt != null) {
    add([
      HolidayEvent(yomHaZikaronDt, H.yomHazikaron, Flags.modernHoliday, '🇮🇱'),
      HolidayEvent(yomHaZikaronDt.next(), H.yomHaatzmaUt, Flags.modernHoliday, '🇮🇱'),
    ]);
  }

  for (final h in _staticModernHolidays) {
    if (year >= h.firstYear) {
      var hd = HDate(h.dd, h.mm, year);
      final dow = hd.getDay();
      if (h.friSatMovetoThu && (dow == _fri || dow == _sat)) {
        hd = hd.onOrBefore(_thu);
      } else if (h.friPostponeToSun && dow == _fri) {
        hd = HDate.fromAbs(hd.abs() + 2);
      } else if (h.satPostponeToSun && dow == _sat) {
        hd = hd.next();
      }
      final mask = h.chul ? Flags.modernHoliday : Flags.modernHoliday | _il;
      add([HolidayEvent(hd, h.desc, mask, h.suppressEmoji ? null : '🇮🇱')]);
    }
  }

  var tamuz17 = HDate(17, Months.tamuz, year);
  var tamuz17observed = false;
  if (tamuz17.getDay() == _sat) {
    tamuz17 = HDate(18, Months.tamuz, year);
    tamuz17observed = true;
  }
  add([HolidayEvent(tamuz17, H.tzomTammuz, Flags.minorFast, null, null, tamuz17observed)]);

  var av9dt = HDate(9, Months.av, year);
  var av9title = H.tishaBav;
  var av9observed = false;
  if (av9dt.getDay() == _sat) {
    av9dt = av9dt.next();
    av9observed = true;
    av9title += ' (observed)';
  }
  final av9abs = av9dt.abs();
  add([
    HolidayEvent(HDate.fromAbs(HDate.dayOnOrBefore(_sat, av9abs)), H.shabbatChazon, Flags.specialShabbat),
    HolidayEvent(av9dt.prev(), H.erevTishaBav, _erev | _majorFast, null, null, av9observed),
    HolidayEvent(av9dt, av9title, _majorFast, null, null, av9observed),
    HolidayEvent(HDate.fromAbs(HDate.dayOnOrBefore(_sat, av9abs + 7)), H.shabbatNachamu, Flags.specialShabbat),
  ]);

  final nMonths = monthsInYear(year);
  for (var month = 1; month <= nMonths; month++) {
    final monthName = getMonthName(month, year);
    final prevLen = month == Months.nisan
        ? daysInMonth(monthsInYear(year - 1), year - 1)
        : daysInMonth(month - 1, year);
    if (prevLen == 30) {
      add([RoshChodeshEvent(HDate(1, month, year), monthName)]);
      add([RoshChodeshEvent(HDate(30, month - 1, year), monthName)]);
    } else if (month != Months.tishrei) {
      add([RoshChodeshEvent(HDate(1, month, year), monthName)]);
    }
  }

  // Begin: Yom Kippur Katan
  for (var month = Months.iyyar; month <= nMonths; month++) {
    final nextMonth = month + 1;
    if (nextMonth == Months.tishrei || nextMonth == Months.cheshvan || nextMonth == Months.tevet) {
      continue;
    }
    var ykk = HDate(29, month, year);
    final dow = ykk.getDay();
    if (dow == _fri || dow == _sat) ykk = ykk.onOrBefore(_thu);
    add([YomKippurKatanEvent(ykk, getMonthName(nextMonth, year))]);
  }

  // BeHaB: Monday-Thursday-Monday after first Shabbat of Cheshvan/Iyyar
  for (final month in [Months.cheshvan, Months.iyyar]) {
    final roshChodesh = HDate(1, month, year);
    var shabbos = HDate.fromAbs(HDate.dayOnOrBefore(_sat, roshChodesh.abs() + 6));
    if (shabbos.abs() == roshChodesh.abs()) {
      shabbos = HDate.fromAbs(shabbos.abs() + 7);
    }
    final fastDays = [2, 5, 9].map((o) => HDate.fromAbs(shabbos.abs() + o)).toList();
    if (month == Months.iyyar && fastDays[2].getDate() == 14) {
      fastDays[2] = HDate(17, Months.iyyar, year);
    }
    for (final hd in fastDays) {
      add([HolidayEvent(hd, H.taanitBehab, Flags.minorFast | Flags.behab)]);
    }
  }

  final sedra = getSedra(year, false);
  final beshalachHd = sedra.find(15)!;
  add([HolidayEvent(beshalachHd, H.shabbatShirah, Flags.specialShabbat)]);

  final birkatHaChama = _getBirkatHaChama(year);
  if (birkatHaChama != 0) {
    add([HolidayEvent(HDate.fromAbs(birkatHaChama), H.birkatHachamah, _minorHoliday, '☀️')]);
  }

  if (_yearCache.length > 120) _yearCache.clear();
  _yearCache[year] = map;
  return map;
}

int _getBirkatHaChama(int year) {
  final leap = isLeapYear(year);
  final startMonth = leap ? Months.adarII : Months.nisan;
  final startDay = leap ? 20 : 1;
  final baseRd = hebrew2abs(year, startMonth, startDay);
  for (var day = 0; day <= 40; day++) {
    final abs = baseRd + day;
    final elapsed = abs + 1373429;
    if (elapsed % 10227 == 172) return abs;
  }
  return 0;
}

/// Returns an array of holidays for the Hebrew year, filtered by [il].
List<HolidayEvent> getHolidaysForYearArray(int year, bool il) {
  final yearMap = getHolidaysForYear(year);
  final startAbs = hebrew2abs(year, Months.tishrei, 1);
  final endAbs = hebrew2abs(year + 1, Months.tishrei, 1) - 1;
  final events = <HolidayEvent>[];
  for (var absDt = startAbs; absDt <= endAbs; absDt++) {
    final holidays = yearMap[HDate.fromAbs(absDt).toString()];
    if (holidays != null) {
      events.addAll(holidays.where((ev) => ev.observedIn(il)));
    }
  }
  return events;
}

/// Returns holidays on [hd]. If [il] is given, filters by Israel/Diaspora.
List<HolidayEvent> getHolidaysOnDate(HDate hd, [bool? il]) {
  final events = getHolidaysForYear(hd.getFullYear())[hd.toString()];
  if (events == null) return const [];
  if (il == null) return events;
  return events.where((ev) => ev.observedIn(il)).toList();
}
