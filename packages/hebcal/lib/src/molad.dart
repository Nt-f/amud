// Port of @hebcal/core moladBase.ts, moladDate.ts, molad.ts,
// MevarchimChodeshEvent.ts, reformatTimeStr.ts
// Hebcal - A Jewish Calendar Generator
// Copyright (c) 1994-2020 Danny Sadinoff
// Portions copyright Eyal Schachter and Michael J. Radwin
// Dart port licensed under GPL-2.0-or-later.

import 'event.dart';
import 'hdate.dart';
import 'hdate.dart' as hd show getMonthName;
import 'locale.dart';

const _jewishEpoch = -1373429;
const _chalakimPerMinute = 18;
const _chalakimPerHour = 1080;
const _chalakimPerDay = 25920;
const _chalakimPerMonth = 765433;
const _chalakimMoladTohu = 31524;

int _jewishMonthOfYear(int year, int month) {
  final leap = isLeapYear(year);
  return ((month + (leap ? 6 : 5)) % (leap ? 13 : 12)) + 1;
}

int _chalakimSinceMoladTohu(int year, int month) {
  final monthOfYear = _jewishMonthOfYear(year, month);
  final monthsElapsed = 235 * ((year - 1) ~/ 19) +
      12 * ((year - 1) % 19) +
      ((7 * ((year - 1) % 19) + 1) ~/ 19) +
      (monthOfYear - 1);
  return _chalakimMoladTohu + _chalakimPerMonth * monthsElapsed;
}

/// The raw molad: Hebrew date plus Jerusalem-mean-time hour/minute/chalakim.
class MoladBase {
  final HDate hdate;
  final int hour;
  final int minutes;
  final int chalakim;
  const MoladBase(this.hdate, this.hour, this.minutes, this.chalakim);
}

/// Calculates the molad for a Hebrew month.
MoladBase calculateMolad(int year, int month) {
  final chalakim = _chalakimSinceMoladTohu(year, month);
  final absDate = chalakim ~/ _chalakimPerDay + _jewishEpoch;
  var hd = HDate.fromAbs(absDate);
  final conjunctionDay = chalakim ~/ _chalakimPerDay;
  var adjusted = chalakim - conjunctionDay * _chalakimPerDay;
  var hour = adjusted ~/ _chalakimPerHour;
  adjusted = adjusted - hour * _chalakimPerHour;
  final minutes = adjusted ~/ _chalakimPerMinute;
  if (hour >= 6) hd = hd.next();
  hour = (hour + 18) % 24;
  return MoladBase(hd, hour, minutes, adjusted - minutes * _chalakimPerMinute);
}

/// Returns the molad as an instant (UTC). Jerusalem Mean Time is based on
/// the longitude of Har HaBayis (35.2354°E).
DateTime getMoladAsDate(MoladBase molad) {
  final moladSeconds = molad.chalakim * 10 / 3;
  final millis = (1000 * (moladSeconds - moladSeconds.truncate())).truncate();
  final dt = molad.hdate.greg();
  final wall = DateTime.utc(dt.year, dt.month, dt.day, molad.hour, molad.minutes,
      moladSeconds.truncate(), millis);
  const longitude = 35.2354;
  final lmtOffsetMs = (longitude * 4 * 60 * 1000).truncate();
  return wall.subtract(Duration(milliseconds: lmtOffsetMs));
}

const _hour12cc = {'US', 'CA', 'BR', 'AU', 'NZ', 'DO', 'PR', 'GR', 'IN', 'KR', 'NP', 'ZA'};

/// Formats "HH:MM" into 12-hour format with suffix when appropriate for the
/// country (or when [hour12] is true).
String reformatTimeStr(String timeStr, String suffix,
    {String? cc, bool il = false, bool? hour12}) {
  final cc0 = cc ?? (il ? 'IL' : 'US');
  if (hour12 != null && !hour12) return timeStr;
  if (hour12 != true && !_hour12cc.contains(cc0)) return timeStr;
  final hm = timeStr.split(':');
  Object hour = int.parse(hm[0]);
  final h = hour as int;
  if (h < 12 && suffix.isNotEmpty) {
    suffix = suffix.replaceFirst('p', 'a').replaceFirst('P', 'A');
    if (h == 0) hour = 12;
  } else if (h > 12) {
    hour = h % 12;
  } else if (h == 0) {
    hour = '00';
  }
  return '$hour:${hm[1]}$suffix';
}

const _enDoW = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const _heDayNames = ['רִאשׁוֹן', 'שֵׁנִי', 'שְׁלִישִׁי', 'רְבִיעִי', 'חֲמִישִׁי', 'שִׁישִּׁי', 'שַׁבָּת'];
const _frDoW = ['Dimanche', 'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];
const _night = 'בַּלַּ֥יְלָה';

String _hebrewTimeOfDay(int hour) {
  if (hour < 5) return _night;
  if (hour < 12) return 'בַּבֹּקֶר';
  if (hour < 17) return 'בַּצׇּהֳרַיִים';
  if (hour < 21) return 'בָּעֶרֶב';
  return _night;
}

/// Represents a molad, the moment when the new moon is "born".
class Molad {
  final int year;
  final int month;
  final MoladBase m;
  DateTime? _instant;

  Molad(this.year, this.month) : m = calculateMolad(year, month);

  HDate getMoladDate() => m.hdate;
  int getYear() => year;
  int getMonth() => month;
  String getMonthName() => hd.getMonthName(month, year);
  int getDow() => m.hdate.getDay();
  int getHour() => m.hour;
  int getMinutes() => m.minutes;
  int getChalakim() => m.chalakim;

  /// The molad as an instant in time (UTC).
  DateTime getInstant() => _instant ??= getMoladAsDate(m);

  DateTime getTchilasZmanKidushLevana3Days() =>
      getInstant().add(const Duration(hours: 72));
  DateTime getTchilasZmanKidushLevana7Days() =>
      getInstant().add(const Duration(hours: 168));
  DateTime getSofZmanKidushLevanaBetweenMoldos() => getInstant().add(
      const Duration(hours: 24 * 14 + 18, minutes: 22, seconds: 1, milliseconds: 666));
  DateTime getSofZmanKidushLevana15Days() =>
      getInstant().add(const Duration(hours: 24 * 15));

  String render([String? locale, bool? hour12, String? cc, bool il = false]) {
    final monthName = Locale.gettext(getMonthName(), locale);
    final dayNames = Locale.isHebrewLocale(locale)
        ? _heDayNames
        : locale == 'fr'
            ? _frDoW
            : _enDoW;
    final dow = dayNames[getDow()];
    final minutes = getMinutes();
    final hour = getHour();
    final chalakim = getChalakim();
    final moladStr = Locale.gettext('Molad', locale);
    final minutesStr = Locale.lookupTranslation('min', locale) ?? 'minutes';
    final chalakimStr = Locale.gettext('chalakim', locale);
    final and = Locale.gettext('and', locale);
    if (Locale.isHebrewLocale(locale)) {
      var result = '$moladStr $monthName יִהְיֶה בַּיּוֹם $dow בשָׁבוּעַ, '
          'בְּשָׁעָה $hour ${_hebrewTimeOfDay(hour)}, '
          'ו-$minutes $minutesStr';
      if (chalakim != 0) result += ' ו-$chalakim $chalakimStr';
      if (locale!.toLowerCase() == 'he-x-nonikud') {
        return hebrewStripNikkud(result);
      }
      return result;
    }
    final fmtTime = reformatTimeStr(
        '$hour:${minutes.toString().padLeft(2, '0')}', 'pm',
        cc: cc, il: il, hour12: hour12);
    final result = '$moladStr ${smartApostrophe(monthName)}: $dow, $fmtTime';
    if (chalakim == 0) return result;
    return '$result $and $chalakim $chalakimStr';
  }
}

/// Represents a Molad announcement on Shabbat Mevarchim.
class MoladEvent extends Event {
  final Molad molad;
  final bool? hour12;
  final String? cc;
  final bool il;
  MoladEvent(HDate date, int hyear, int hmonth, {this.hour12, this.cc, this.il = false})
      : molad = Molad(hyear, hmonth),
        super(date, 'Molad ${getMonthName(hmonth, hyear)} $hyear', Flags.molad);

  @override
  String render([String? locale]) => molad.render(locale, hour12, cc, il);
}

const _mevarchimChodeshStr = 'Shabbat Mevarchim Chodesh';

/// Represents Shabbat Mevarchim, the Shabbat before Rosh Chodesh.
class MevarchimChodeshEvent extends Event {
  final String monthName;
  MevarchimChodeshEvent(HDate date, this.monthName, [String? memo0])
      : super(date, '$_mevarchimChodeshStr $monthName', Flags.shabbatMevarchim) {
    if (memo0 != null && memo0.isNotEmpty) {
      memo = memo0;
    } else {
      final hyear = date.getFullYear();
      final hmonth = date.getMonth();
      final monNext = hmonth == monthsInYear(hyear) ? Months.nisan : hmonth + 1;
      memo = Molad(hyear, monNext).render('en', false);
    }
  }

  @override
  String basename() => getDesc();

  @override
  String render([String? locale]) =>
      '${Locale.gettext(_mevarchimChodeshStr, locale)} ${smartApostrophe(Locale.gettext(monthName, locale))}';

  @override
  String renderBrief([String? locale]) {
    final str = render(locale);
    return str.substring(str.indexOf(' ') + 1);
  }
}
