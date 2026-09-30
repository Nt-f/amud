// Port of @hebcal/core tachanun.ts, hallel.ts, isAveilut.ts, isFastDay.ts,
// isAssurBemlacha.ts and HebrewCalendar.eruvTavshilin
// Hebcal - A Jewish Calendar Generator
// Copyright (c) 1994-2020 Danny Sadinoff
// Portions copyright Eyal Schachter and Michael J. Radwin
// Dart port licensed under GPL-2.0-or-later.

import 'event.dart';
import 'greg.dart';
import 'hdate.dart';
import 'holidays.dart';
import 'location.dart';
import 'zmanim.dart';

/// Result of [tachanun].
class TachanunResult {
  /// Tachanun is said at Shacharit.
  final bool shacharit;

  /// Tachanun is said at Mincha.
  final bool mincha;

  /// All congregations say Tachanun on the day.
  final bool allCongs;
  const TachanunResult(this.shacharit, this.mincha, this.allCongs);

  static const none = TachanunResult(false, false, false);

  @override
  String toString() =>
      'TachanunResult(shacharit: $shacharit, mincha: $mincha, allCongs: $allCongs)';
}

List<int> _range(int start, int end) => [for (var i = start; i <= end; i++) i];

class _TachanunYear {
  final Set<int> none;
  final Set<int> some;
  final Set<int> yesPrev;
  _TachanunYear(this.none, this.some, this.yesPrev);
}

final Map<String, _TachanunYear> _tachanunCache = {};

_TachanunYear _tachanunYear(int year, bool il) {
  return _tachanunCache.putIfAbsent('$year-$il', () {
    final leap = isLeapYear(year);
    final nMonths = monthsInYear(year);
    var av9dt = HDate(9, Months.av, year);
    if (av9dt.getDay() == 6) av9dt = av9dt.next();
    var shushPurim = HDate(15, Months.adarII, year);
    if (shushPurim.getDay() == 6) shushPurim = shushPurim.next();
    final none = <HDate>[
      HDate(2, Months.tishrei, year),
      for (final m in _range(1, nMonths)) HDate(1, m, year),
      for (final m in _range(1, nMonths))
        if (daysInMonth(m, year) == 30) HDate(30, m, year),
      for (final d in _range(1, daysInMonth(Months.nisan, year))) HDate(d, Months.nisan, year),
      HDate(18, Months.iyyar, year),
      for (final d in _range(1, 8 - (il ? 1 : 0))) HDate(d, Months.sivan, year),
      av9dt,
      HDate(15, Months.av, year),
      HDate(29, Months.elul, year),
      for (final d in _range(9, 24 - (il ? 1 : 0))) HDate(d, Months.tishrei, year),
      for (final d in _range(25, 33)) HDate(d, Months.kislev, year),
      HDate(15, Months.shvat, year),
      HDate(14, Months.adarII, year),
      shushPurim,
      if (leap) HDate(14, Months.adarI, year),
    ];
    final some = <HDate>[
      HDate(14, Months.iyyar, year),
      for (final d in _range(1, 13)) HDate(d, Months.sivan, year),
      for (final d in _range(20, 31)) HDate(d, Months.tishrei, year),
      if (year >= 5708) dateYomHaZikaron(year)!.next(),
      if (year >= 5727) HDate(28, Months.iyyar, year),
    ];
    final yesPrev = <HDate>[
      HDate(29, Months.elul, year - 1),
      HDate(9, Months.tishrei, year),
      HDate(14, Months.iyyar, year),
    ];
    return _TachanunYear(
      none.map((h) => h.abs()).toSet(),
      some.map((h) => h.abs()).toSet(),
      yesPrev.map((h) => h.abs()).toSet(),
    );
  });
}

/// Tachanun is not said on Rosh Chodesh, the month of Nisan, Lag Baomer,
/// Rosh Chodesh Sivan through Isru Chag, Tisha B'Av, 15 Av, Erev Rosh
/// Hashanah, Rosh Hashanah, Erev Yom Kippur through Rosh Chodesh Cheshvan,
/// Chanukah, Tu B'shvat, Purim and Shushan Purim, and Purim and Shushan
/// Purim Katan. In some congregations Tachanun is not said all from Rosh
/// Chodesh Sivan until 14th Sivan, Sukkot until Rosh Chodesh Cheshvan,
/// Pesach Sheini, Yom Ha'atzmaut, and Yom Yerushalayim. Tachanun is not
/// said at Minchah on days before it is not said at Shacharit. Tachanun is
/// not said at Shacharit on Shabbat, but is at Minchah, usually.
TachanunResult tachanun(HDate hdate, bool il) => _tachanun0(hdate, il, true);

/// Dart-port extension: true if [hdate] itself is a day on which no
/// congregation says Tachanun (ignores the day of week), e.g. to decide
/// Av HaRachamim or Tzidkatcha on Shabbat.
bool isNoTachanunDay(HDate hdate, bool il) =>
    _tachanunYear(hdate.yy, il).none.contains(hdate.abs());

TachanunResult _tachanun0(HDate hdate, bool il, bool checkNext) {
  final dates = _tachanunYear(hdate.yy, il);
  final abs = hdate.abs();
  if (dates.none.contains(abs)) return TachanunResult.none;
  final dow = hdate.getDay();
  final allCongs = !dates.some.contains(abs);
  final shacharit = dow != 6;
  bool mincha;
  final tomorrow = abs + 1;
  if (checkNext && !dates.yesPrev.contains(tomorrow)) {
    mincha = _tachanun0(HDate.fromAbs(tomorrow), il, false).shacharit;
  } else {
    mincha = dow != 5;
  }
  if (allCongs && !mincha && !shacharit) return TachanunResult.none;
  return TachanunResult(shacharit, mincha, allCongs);
}

/// Hallel types.
enum HallelType { none, half, whole }

HallelType _hallel(List<Event> events, HDate hdate) {
  final abs = hdate.abs();
  for (final ev in events) {
    final hd = ev.getDate();
    if (hd.abs() != abs) continue;
    final desc = ev.getDesc();
    final month = hd.getMonth();
    final mday = hd.getDate();
    if (desc.startsWith('Chanukah') ||
        desc.startsWith('Shavuot') ||
        desc.startsWith('Sukkot') ||
        (month == Months.nisan && (mday == 15 || mday == 16) && ev.hasFlag(Flags.chag)) ||
        desc == HolidayDesc.yomHaatzmaUt ||
        desc == HolidayDesc.yomYerushalayim) {
      return HallelType.whole;
    }
    if (ev.hasFlag(Flags.roshChodesh) ||
        (desc.startsWith('Pesach') &&
            desc != HolidayDesc.pesachI &&
            desc != HolidayDesc.pesachII)) {
      return HallelType.half;
    }
  }
  return HallelType.none;
}

/// Determines if Hallel is said on a given date.
HallelType hallel(HDate hdate, bool il) =>
    _hallel(getHolidaysOnDate(hdate, il), hdate);

/// Returns true if the date is a fast day (major or minor, not Erev).
bool isFastDay(HDate date, [bool? il]) => getHolidaysOnDate(date, il).any(
    (ev) => ev.hasAnyFlag([Flags.majorFast, Flags.minorFast]) && !ev.hasFlag(Flags.erev));

bool _isSefiratHaOmer(HDate hd) {
  final y = hd.getFullYear();
  final abs = hd.abs();
  return abs >= HDate(16, Months.nisan, y).abs() && abs <= HDate(5, Months.sivan, y).abs();
}

bool _isBeinHaMetzarim(HDate hd) {
  final y = hd.getFullYear();
  final begin = HDate(17, Months.tamuz, y).abs();
  final tishaBav = HDate(9, Months.av, y);
  final end = tishaBav.getDay() == 6 ? HDate(10, Months.av, y).abs() : tishaBav.abs();
  final abs = hd.abs();
  return abs >= begin && abs <= end;
}

/// True during Sefirat HaOmer or Bein HaMetzarim (periods of mourning).
bool isAveilut(HDate date) => _isSefiratHaOmer(date) || _isBeinHaMetzarim(date);

bool _isChag(HDate date, bool il) =>
    getHolidaysOnDate(date, il).any((ev) => ev.hasFlag(Flags.chag));

/// Eruv Tavshilin is needed when a Yom Tov falls on Thursday/Friday before
/// Shabbat. Returns true on the Erev Yom Tov (Wednesday or Thursday).
bool eruvTavshilin(HDate date, bool il) {
  final dow = date.getDay();
  if (dow < 3 || dow > 4) return false;
  final friday = date.after(5);
  final tomorrow = date.next();
  if (!_isChag(friday, il) || _isChag(date, il) || !_isChag(tomorrow, il)) {
    return false;
  }
  return true;
}

/// Returns true if the current instant is Shabbat or Yom Tov (after sunset
/// the evening before until tzeit).
bool isAssurBemlacha(DateTime currentTime, Location location, bool useElevation) {
  final local = Zmanim(location, PlainDate(1970, 1, 1), false).toLocal(currentTime);
  final pd = PlainDate(local.year, local.month, local.day);
  final hd = HDate.fromAbs(pd.abs);
  final zmanim = Zmanim(location, pd, useElevation);
  final sunset = zmanim.sunset();
  if (sunset == null) throw StateError('Could not determine sunset');
  final il = location.getIsrael();
  final dow = hd.getDay();
  final events = getHolidaysOnDate(hd, il);
  final tomorrowHoly = dow == 5 ||
      events.any((ev) => ev.hasAnyFlag([Flags.lightCandles, Flags.lightCandlesTzeis]));
  if (tomorrowHoly && !currentTime.isBefore(sunset)) return true;
  final todayHoly = dow == 6 || events.any((ev) => ev.hasFlag(Flags.chag));
  if (todayHoly) {
    final tzais = zmanim.tzeit();
    return tzais != null && !currentTime.isAfter(tzais);
  }
  return false;
}
