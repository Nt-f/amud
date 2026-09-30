// Port of @hebcal/hdate (hdateBase.ts, hdate.ts, gematriya.ts, anniversary.ts)
// Hebcal - A Jewish Calendar Generator
// Copyright (c) 1994-2020 Danny Sadinoff
// Portions copyright Eyal Schachter and Michael J. Radwin
// Dart port licensed under GPL-2.0-or-later.

import 'greg.dart';
import 'locale.dart';

/// Hebrew month numbers (Nisan = 1).
abstract final class Months {
  static const int nisan = 1;
  static const int iyyar = 2;
  static const int sivan = 3;
  static const int tamuz = 4;
  static const int av = 5;
  static const int elul = 6;
  static const int tishrei = 7;
  static const int cheshvan = 8;
  static const int kislev = 9;
  static const int tevet = 10;
  static const int shvat = 11;
  static const int adarI = 12;
  static const int adarII = 13;
}

const _monthNames0 = [
  '',
  'Nisan',
  'Iyyar',
  'Sivan',
  'Tamuz',
  'Av',
  'Elul',
  'Tishrei',
  'Cheshvan',
  'Kislev',
  'Tevet',
  "Sh'vat",
];
const _monthNames = [
  [..._monthNames0, 'Adar', 'Nisan'],
  [..._monthNames0, 'Adar I', 'Adar II', 'Nisan'],
];

const int _epoch = -1373428;
const double _avgHebYearDays = 365.24682220597794;
final Map<int, int> _edCache = {};

int _mod(int x, int y) => x - y * (x / y).floor();

/// Converts Hebrew date to R.D. (Rata Die) fixed days.
int hebrew2abs(int year, int month, int day) {
  if (year < 1) throw RangeError('hebrew2abs: invalid year $year');
  var tempabs = day;
  if (month < Months.tishrei) {
    final endMonth = monthsInYear(year);
    for (var m = Months.tishrei; m <= endMonth; m++) {
      tempabs += daysInMonth(m, year);
    }
    for (var m = Months.nisan; m < month; m++) {
      tempabs += daysInMonth(m, year);
    }
  } else {
    for (var m = Months.tishrei; m < month; m++) {
      tempabs += daysInMonth(m, year);
    }
  }
  return _epoch + elapsedDays(year) + tempabs - 1;
}

int _newYear(int year) => _epoch + elapsedDays(year);

/// A plain year/month/day Hebrew date.
class SimpleHebrewDate {
  int yy;
  int mm;
  int dd;
  SimpleHebrewDate(this.yy, this.mm, this.dd);
}

/// Converts absolute R.D. days to Hebrew date.
SimpleHebrewDate abs2hebrew(int abs) {
  if (abs <= _epoch) throw RangeError('abs2hebrew: $abs is before epoch');
  var year = ((abs - _epoch) / _avgHebYearDays).floor();
  while (_newYear(year) <= abs) {
    ++year;
  }
  --year;
  var month = abs < hebrew2abs(year, 1, 1) ? 7 : 1;
  while (abs > hebrew2abs(year, month, daysInMonth(month, year))) {
    ++month;
  }
  final day = 1 + abs - hebrew2abs(year, month, 1);
  return SimpleHebrewDate(year, month, day);
}

bool isLeapYear(int year) => (1 + year * 7) % 19 < 7;

int monthsInYear(int year) => 12 + (isLeapYear(year) ? 1 : 0);

const _staticDaysInMonth = [0, 30, 29, 30, 29, 30, 29, 30, 0, 0, 29, 30, 0, 29];

int daysInMonth(int month, int year) {
  final d = _staticDaysInMonth[month];
  if (d != 0) return d;
  if (month == Months.adarI) return isLeapYear(year) ? 30 : 29;
  if (month == Months.cheshvan) return longCheshvan(year) ? 30 : 29;
  return shortKislev(year) ? 29 : 30;
}

String getMonthName(int month, int year) {
  if (month < 1 || month > 14) throw ArgumentError('bad monthNum: $month');
  return _monthNames[isLeapYear(year) ? 1 : 0][month];
}

/// Days from sunday prior to start of Hebrew calendar to mean conjunction of
/// Tishrei in Hebrew year.
int elapsedDays(int year) => _edCache.putIfAbsent(year, () => _elapsedDays0(year));

int _elapsedDays0(int year) {
  final prevYear = year - 1;
  final mElapsed = 235 * (prevYear ~/ 19) +
      12 * (prevYear % 19) +
      (((prevYear % 19) * 7 + 1) ~/ 19);
  final pElapsed = 204 + 793 * (mElapsed % 1080);
  final hElapsed =
      5 + 12 * mElapsed + 793 * (mElapsed ~/ 1080) + (pElapsed ~/ 1080);
  final parts = (pElapsed % 1080) + 1080 * (hElapsed % 24);
  final day = 1 + 29 * mElapsed + (hElapsed ~/ 24);
  var altDay = day;
  if (parts >= 19440 ||
      (2 == day % 7 && parts >= 9924 && !isLeapYear(year)) ||
      (1 == day % 7 && parts >= 16789 && isLeapYear(prevYear))) {
    altDay++;
  }
  if (altDay % 7 == 0 || altDay % 7 == 3 || altDay % 7 == 5) {
    return altDay + 1;
  }
  return altDay;
}

int daysInYear(int year) => elapsedDays(year + 1) - elapsedDays(year);
bool longCheshvan(int year) => daysInYear(year) % 10 == 5;
bool shortKislev(int year) => daysInYear(year) % 10 == 3;

int _adarFromName(String c) {
  final suffix = c
      .replaceFirst(RegExp(r'^(adar|אדר)'), '')
      .replaceAll(RegExp("[\\s.'`\\-׳״]"), '');
  if (suffix == '1' ||
      suffix == 'i' ||
      suffix == 'a' ||
      suffix == 'א' ||
      suffix.startsWith('alef') ||
      suffix.startsWith('aleph') ||
      suffix.startsWith('alaph') ||
      suffix.startsWith('rish') ||
      suffix.startsWith('ראש') ||
      suffix.startsWith('אל')) {
    return Months.adarI;
  }
  return Months.adarII;
}

/// Converts a Hebrew or transliterated month name to a month number.
int monthFromName(String monthName) {
  var c = hebrewStripNikkud(monthName.trim().toLowerCase())
      .replaceFirst(RegExp('׳\$'), '');
  if (c.startsWith('ב')) c = c.substring(1);
  String at(int i) => i < c.length ? c[i] : '';
  switch (at(0)) {
    case 'n':
    case 'נ':
      if (at(1) == 'o') break;
      return Months.nisan;
    case 'i':
      return Months.iyyar;
    case 'e':
      return Months.elul;
    case 'c':
    case 'ח':
      return Months.cheshvan;
    case 'k':
    case 'כ':
      return Months.kislev;
    case 's':
      switch (at(1)) {
        case 'i':
          return Months.sivan;
        case 'h':
          return Months.shvat;
      }
      break;
    case 't':
      switch (at(1)) {
        case 'a':
          return Months.tamuz;
        case 'i':
          return Months.tishrei;
        case 'e':
          return Months.tevet;
      }
      break;
    case 'a':
      switch (at(1)) {
        case 'v':
          return Months.av;
        case 'd':
          return _adarFromName(c);
      }
      break;
    case 'ס':
      return Months.sivan;
    case 'ט':
      return Months.tevet;
    case 'ש':
      return Months.shvat;
    case 'א':
      switch (at(1)) {
        case 'ב':
          return Months.av;
        case 'ד':
          return _adarFromName(c);
        case 'י':
          return Months.iyyar;
        case 'ל':
          return Months.elul;
      }
      break;
    case 'ת':
      switch (at(1)) {
        case 'מ':
          return Months.tamuz;
        case 'ש':
          return Months.tishrei;
      }
      break;
  }
  throw ArgumentError('bad monthName: $monthName');
}

// ---------------------------------------------------------------- gematriya

const _geresh = '׳';
const _gershayim = '״';
const Map<String, int> _heb2num = {
  'א': 1, 'ב': 2, 'ג': 3, 'ד': 4, 'ה': 5, 'ו': 6, 'ז': 7, 'ח': 8, 'ט': 9, //
  'י': 10, 'כ': 20, 'ל': 30, 'מ': 40, 'נ': 50, 'ס': 60, 'ע': 70, 'פ': 80,
  'צ': 90, 'ק': 100, 'ר': 200, 'ש': 300, 'ת': 400,
};
final Map<int, String> _num2heb = {
  for (final e in _heb2num.entries) e.value: e.key,
};
const Map<String, int> _sofit2num = {'ך': 20, 'ם': 40, 'ן': 50, 'ף': 80, 'ץ': 90};

List<int> _num2digits(int num) {
  final digits = <int>[];
  while (num > 0) {
    if (num == 15 || num == 16) {
      digits.addAll([9, num - 9]);
      break;
    }
    var incr = 100;
    int i;
    for (i = 400; i > num; i -= incr) {
      if (i == incr) incr = incr ~/ 10;
    }
    digits.add(i);
    num -= i;
  }
  return digits;
}

/// Converts a numerical value to a string of Hebrew letters (with geresh /
/// gershayim).
String gematriya(Object num) {
  final num1 = num is int ? num : int.tryParse('$num') ?? 0;
  if (num1 <= 0) throw ArgumentError('invalid number: $num');
  var str = '';
  final thousands = num1 ~/ 1000;
  if (thousands > 0 && thousands != 5) {
    for (final tdig in _num2digits(thousands)) {
      str += _num2heb[tdig]!;
    }
    str += _geresh;
  }
  final digits = _num2digits(num1 % 1000);
  if (digits.length == 1) return str + _num2heb[digits[0]]! + _geresh;
  for (var i = 0; i < digits.length; i++) {
    if (i + 1 == digits.length) str += _gershayim;
    str += _num2heb[digits[i]]!;
  }
  return str;
}

/// Parses a Hebrew gematriya string into a number.
int gematriyaStrToNum(String str) {
  var num = 0;
  final gereshIdx = str.indexOf(_geresh);
  if (gereshIdx != -1 && gereshIdx != str.length - 1) {
    num += gematriyaStrToNum(str.substring(0, gereshIdx)) * 1000;
    str = str.substring(gereshIdx);
  }
  for (final ch in str.split('')) {
    final n = _heb2num[ch] ?? _sofit2num[ch];
    if (n != null) num += n;
  }
  return num;
}

// ---------------------------------------------------------------- HDate

const _topIsLeapYear = isLeapYear;
const _topDaysInMonth = daysInMonth;
const _topGetMonthName = getMonthName;

/// A Hebrew date. Immutable.
class HDate implements Comparable<HDate> {
  late final int yy;
  late final int mm;
  late final int dd;
  int? _rd;

  /// Creates a Hebrew date from day, month (number or name) and year.
  HDate(int day, Object month, int year) {
    final d = SimpleHebrewDate(year, 1, 1);
    d.mm = month is int ? _monthNum(month) : monthFromName('$month');
    _fix(d);
    d.dd = day;
    _fix(d);
    yy = d.yy;
    mm = d.mm;
    dd = d.dd;
  }

  /// Creates a Hebrew date from an R.D. absolute day number.
  HDate.fromAbs(int abs) {
    final d = abs2hebrew(abs);
    yy = d.yy;
    mm = d.mm;
    dd = d.dd;
    _rd = abs;
  }

  /// Creates a Hebrew date from the Gregorian y/m/d fields of [dt].
  factory HDate.fromDate(DateTime dt) => HDate.fromAbs(greg2abs(dt));

  /// Today's Hebrew date (by local Gregorian date; does not account for
  /// sunset — see [Zmanim.makeSunsetAwareHDate]).
  factory HDate.today() => HDate.fromDate(DateTime.now());

  int getFullYear() => yy;
  bool isLeapYear() => _isLeap(yy);
  int getMonth() => mm;

  int getTishreiMonth() {
    final n = monthsInYear(yy);
    final r = (mm + n - 6) % n;
    return r == 0 ? n : r;
  }

  int daysInMonth() => _daysInMonth(mm, yy);
  int getDate() => dd;

  /// Day of week, 0 = Sunday.
  int getDay() => _mod(abs(), 7);

  DateTime greg() => abs2greg(abs());
  PlainDate plainDate() => PlainDate.fromAbs(abs());

  int abs() => _rd ??= hebrew2abs(yy, mm, dd);

  String getMonthName() => _getMonthName(mm, yy);

  String render([String? locale, bool showYear = true]) {
    final locale0 = locale ?? 'en';
    final monthName = Locale.gettext(getMonthName(), locale0).replaceAll("'", '’');
    final nth = Locale.ordinal(dd, locale0);
    final dayOf = _getDayOfTranslation(locale0);
    final dateStr = '$nth$dayOf $monthName';
    return showYear ? '$dateStr, $yy' : dateStr;
  }

  String renderGematriya([bool suppressNikud = false, bool suppressYear = false]) {
    final locale = suppressNikud ? 'he-x-NoNikud' : 'he';
    final m = Locale.gettext(getMonthName(), locale);
    final prefix = '${gematriya(dd)} $m';
    if (suppressYear) return prefix;
    return '$prefix ${gematriya(yy)}';
  }

  HDate before(int dayOfWeek) => _onOrBefore(dayOfWeek, this, -1);
  HDate onOrBefore(int dayOfWeek) => _onOrBefore(dayOfWeek, this, 0);
  HDate nearest(int dayOfWeek) => _onOrBefore(dayOfWeek, this, 3);
  HDate onOrAfter(int dayOfWeek) => _onOrBefore(dayOfWeek, this, 6);
  HDate after(int dayOfWeek) => _onOrBefore(dayOfWeek, this, 7);

  HDate next() => HDate.fromAbs(abs() + 1);
  HDate prev() => HDate.fromAbs(abs() - 1);

  HDate addDays(int n) => HDate.fromAbs(abs() + n);
  HDate addWeeks(int n) => HDate.fromAbs(abs() + 7 * n);
  HDate addYears(int n) => HDate(dd, mm, yy + n);
  HDate addMonths(int amount) {
    var hd = this;
    final sign = amount > 0 ? 1 : -1;
    for (var i = 0; i < amount.abs(); i++) {
      hd = HDate.fromAbs(hd.abs() + sign * hd.daysInMonth());
    }
    return hd;
  }

  int deltaDays(HDate other) => abs() - other.abs();

  bool isSameDate(HDate other) =>
      yy == other.yy && mm == other.mm && dd == other.dd;

  @override
  bool operator ==(Object other) => other is HDate && isSameDate(other);

  @override
  int get hashCode => Object.hash(yy, mm, dd);

  @override
  int compareTo(HDate other) => abs().compareTo(other.abs());

  @override
  String toString() => '$dd ${getMonthName()} $yy';

  static bool _isLeap(int y) => _topIsLeapYear(y);
  static int _daysInMonth(int m, int y) => _topDaysInMonth(m, y);
  static String _getMonthName(int m, int y) => _topGetMonthName(m, y);

  static int dayOnOrBefore(int dayOfWeek, int absdate) =>
      absdate - _mod(absdate - dayOfWeek, 7);

  static int _monthNum(int month) {
    if (month > 14) throw RangeError('bad monthNum: $month');
    return month;
  }

  static HDate fromGematriyaString(String str, [int currentThousands = 5000]) {
    final parts = str.split(' ').where((x) => x.isNotEmpty).toList();
    if (parts.length != 3 && parts.length != 4) {
      throw ArgumentError('cannot parse gematriya str: "$str"');
    }
    final day = gematriyaStrToNum(parts[0]);
    final monthStr = parts.length == 3 ? parts[1] : '${parts[1]} ${parts[2]}';
    final month = monthFromName(monthStr);
    var year = gematriyaStrToNum(parts.length == 3 ? parts[2] : parts[3]);
    if (year < 1000) year += currentThousands;
    return HDate(day, month, year);
  }
}

String _getDayOfTranslation(String locale) {
  switch (locale) {
    case 'en':
    case 's':
    case 'a':
    case 'ashkenazi':
      return ' of';
  }
  final ofStr = Locale.lookupTranslation('of', locale);
  if (ofStr != null) return ' $ofStr';
  if (locale.startsWith('ashkenazi')) return ' of';
  return '';
}

void _fix(SimpleHebrewDate hd) {
  _fixMonth(hd);
  _fixDate(hd);
}

void _fixDate(SimpleHebrewDate hd) {
  if (hd.dd < 1) {
    if (hd.mm == Months.tishrei) hd.yy -= 1;
    hd.dd += daysInMonth(hd.mm, hd.yy);
    hd.mm -= 1;
    _fix(hd);
  }
  if (hd.dd > daysInMonth(hd.mm, hd.yy)) {
    if (hd.mm == Months.elul) hd.yy += 1;
    hd.dd -= daysInMonth(hd.mm, hd.yy);
    if (hd.mm == monthsInYear(hd.yy)) {
      hd.mm = 1;
    } else {
      hd.mm += 1;
    }
    _fix(hd);
  }
  _fixMonth(hd);
}

void _fixMonth(SimpleHebrewDate hd) {
  if (hd.mm == Months.adarII && !isLeapYear(hd.yy)) {
    hd.mm -= 1;
    _fix(hd);
  } else if (hd.mm < 1) {
    hd.mm += monthsInYear(hd.yy);
    hd.yy -= 1;
    _fix(hd);
  } else if (hd.mm > monthsInYear(hd.yy)) {
    hd.mm -= monthsInYear(hd.yy);
    hd.yy += 1;
    _fix(hd);
  }
}

HDate _onOrBefore(int day, HDate t, int offset) =>
    HDate.fromAbs(HDate.dayOnOrBefore(day, t.abs() + offset));

// ---------------------------------------------------------------- anniversary

/// Calculates yahrzeit for [hyear] given the Hebrew date of death.
/// Returns null if [hyear] is not after the year of death.
HDate? getYahrzeit(int hyear, HDate date) {
  var hDeath = SimpleHebrewDate(date.yy, date.mm, date.dd);
  if (hyear <= hDeath.yy) return null;
  if (hDeath.mm == Months.cheshvan && hDeath.dd == 30 && !longCheshvan(hDeath.yy + 1)) {
    hDeath = abs2hebrew(hebrew2abs(hyear, Months.kislev, 1) - 1);
  } else if (hDeath.mm == Months.kislev && hDeath.dd == 30 && shortKislev(hDeath.yy + 1)) {
    hDeath = abs2hebrew(hebrew2abs(hyear, Months.tevet, 1) - 1);
  } else if (hDeath.mm == Months.adarII) {
    hDeath.mm = monthsInYear(hyear);
  } else if (hDeath.mm == Months.adarI && hDeath.dd == 30 && !isLeapYear(hyear)) {
    hDeath.dd = 30;
    hDeath.mm = Months.shvat;
  }
  if (hDeath.mm == Months.cheshvan && hDeath.dd == 30 && !longCheshvan(hyear)) {
    hDeath.mm = Months.kislev;
    hDeath.dd = 1;
  } else if (hDeath.mm == Months.kislev && hDeath.dd == 30 && shortKislev(hyear)) {
    hDeath.mm = Months.tevet;
    hDeath.dd = 1;
  }
  hDeath.yy = hyear;
  return HDate.fromAbs(hebrew2abs(hDeath.yy, hDeath.mm, hDeath.dd));
}

/// Calculates a birthday or anniversary (non-yahrzeit) in [hyear].
HDate? getBirthdayOrAnniversary(int hyear, HDate date) {
  final origYear = date.yy;
  if (hyear == origYear) return date;
  if (hyear < origYear) return null;
  final isOrigLeap = isLeapYear(origYear);
  var month = date.mm;
  var day = date.dd;
  if ((month == Months.adarI && !isOrigLeap) || (month == Months.adarII && isOrigLeap)) {
    month = monthsInYear(hyear);
  } else if (month == Months.cheshvan && day == 30 && !longCheshvan(hyear)) {
    month = Months.kislev;
    day = 1;
  } else if (month == Months.kislev && day == 30 && shortKislev(hyear)) {
    month = Months.tevet;
    day = 1;
  } else if (month == Months.adarI && day == 30 && isOrigLeap && !isLeapYear(hyear)) {
    month = Months.nisan;
    day = 1;
  }
  return HDate.fromAbs(hebrew2abs(hyear, month, day));
}
