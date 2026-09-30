// Port of @hebcal/core CalOptions.ts, TimedEvent.ts, candles.ts,
// getStartAndEnd.ts, calendar.ts, DailyLearning.ts
// Hebcal - A Jewish Calendar Generator
// Copyright (c) 1994-2020 Danny Sadinoff
// Portions copyright Eyal Schachter and Michael J. Radwin
// Dart port licensed under GPL-2.0-or-later.

import 'event.dart';
import 'greg.dart';
import 'hdate.dart';
import 'holidays.dart';
import 'locale.dart';
import 'location.dart';
import 'molad.dart';
import 'omer.dart';
import 'sedra.dart';
import 'zmanim.dart';

/// Options to configure which events are returned by [calendar].
class CalOptions {
  Location? location;
  int? year;
  bool isHebrewYear;
  Object? month;
  int? numYears;
  HDate? start;
  HDate? end;
  bool candlelighting;
  int? candleLightingMins;
  int? havdalahMins;
  double? havdalahDeg;
  double? fastEndDeg;
  int? fastEndMins;
  double? fastStartDeg;
  int? fastStartMins;
  double? tishaBavEndDeg;
  int? tishaBavEndMins;
  bool useElevation;
  bool sedrot;
  bool il;
  bool noMinorFast;
  bool noModern;
  bool noRoshChodesh;
  bool shabbatMevarchim;
  bool noSpecialShabbat;
  bool noHolidays;
  bool omer;
  bool molad;
  bool ashkenazi;
  String? locale;
  bool addHebrewDates;
  bool addHebrewDatesForEvents;
  int? mask;
  bool yomKippurKatan;
  bool behab;
  bool? hour12;

  /// e.g. `{'dafYomi': true, 'mishnaYomi': true, 'yerushalmi': 1}`
  Map<String, Object> dailyLearning;
  bool yizkor;

  CalOptions({
    this.location,
    this.year,
    this.isHebrewYear = false,
    this.month,
    this.numYears,
    this.start,
    this.end,
    this.candlelighting = false,
    this.candleLightingMins,
    this.havdalahMins,
    this.havdalahDeg,
    this.fastEndDeg,
    this.fastEndMins,
    this.fastStartDeg,
    this.fastStartMins,
    this.tishaBavEndDeg,
    this.tishaBavEndMins,
    this.useElevation = false,
    this.sedrot = false,
    this.il = false,
    this.noMinorFast = false,
    this.noModern = false,
    this.noRoshChodesh = false,
    this.shabbatMevarchim = false,
    this.noSpecialShabbat = false,
    this.noHolidays = false,
    this.omer = false,
    this.molad = false,
    this.ashkenazi = false,
    this.locale,
    this.addHebrewDates = false,
    this.addHebrewDatesForEvents = false,
    this.mask,
    this.yomKippurKatan = false,
    this.behab = false,
    this.hour12,
    Map<String, Object>? dailyLearning,
    this.yizkor = false,
  }) : dailyLearning = dailyLearning ?? {};

  CalOptions copy() => CalOptions(
        location: location,
        year: year,
        isHebrewYear: isHebrewYear,
        month: month,
        numYears: numYears,
        start: start,
        end: end,
        candlelighting: candlelighting,
        candleLightingMins: candleLightingMins,
        havdalahMins: havdalahMins,
        havdalahDeg: havdalahDeg,
        fastEndDeg: fastEndDeg,
        fastEndMins: fastEndMins,
        fastStartDeg: fastStartDeg,
        fastStartMins: fastStartMins,
        tishaBavEndDeg: tishaBavEndDeg,
        tishaBavEndMins: tishaBavEndMins,
        useElevation: useElevation,
        sedrot: sedrot,
        il: il,
        noMinorFast: noMinorFast,
        noModern: noModern,
        noRoshChodesh: noRoshChodesh,
        shabbatMevarchim: shabbatMevarchim,
        noSpecialShabbat: noSpecialShabbat,
        noHolidays: noHolidays,
        omer: omer,
        molad: molad,
        ashkenazi: ashkenazi,
        locale: locale,
        addHebrewDates: addHebrewDates,
        addHebrewDatesForEvents: addHebrewDatesForEvents,
        mask: mask,
        yomKippurKatan: yomKippurKatan,
        behab: behab,
        hour12: hour12,
        dailyLearning: Map.of(dailyLearning),
        yizkor: yizkor,
      );
}

// ------------------------------------------------------------ TimedEvent

/// An event that has an `eventTime` and `eventTimeStr`.
class TimedEvent extends Event {
  /// UTC instant, rounded to the nearest minute.
  DateTime eventTime;
  final Location location;

  /// 24-hour "HH:MM" local time.
  String eventTimeStr;
  final String fmtTime;
  final Event? linkedEvent;

  TimedEvent(super.date, super.desc, super.mask, DateTime eventTime, this.location,
      [this.linkedEvent, CalOptions? options])
      : eventTime = Zmanim.roundTime(eventTime),
        eventTimeStr = Zmanim.formatTime(Zmanim.roundTime(eventTime), location.tzLocation),
        fmtTime = reformatTimeStr(
            Zmanim.formatTime(Zmanim.roundTime(eventTime), location.tzLocation), 'pm',
            cc: location.getCountryCode(), il: options?.il ?? location.il, hour12: options?.hour12),
        super();

  @override
  String render([String? locale]) => '${Locale.gettext(getDesc(), locale)}: $fmtTime';

  @override
  String renderBrief([String? locale]) => Locale.gettext(getDesc(), locale);

  @override
  List<String> getCategories() {
    switch (getDesc()) {
      case HolidayDesc.candleLighting:
        return const ['candles'];
      case HolidayDesc.havdalah:
        return const ['havdalah'];
      case HolidayDesc.fastBegins:
      case HolidayDesc.fastEnds:
        return const ['zmanim', 'fast'];
      case HolidayDesc.sofZmanAchilatChametz:
        return const ['zmanim', 'achilasChametz'];
      case HolidayDesc.biurChametz:
        return const ['zmanim', 'biurChametz'];
    }
    return const ['unknown'];
  }
}

/// Candle lighting before Shabbat or holiday.
class CandleLightingEvent extends TimedEvent {
  CandleLightingEvent(HDate date, int mask, DateTime eventTime, Location location,
      [Event? linkedEvent, CalOptions? options])
      : super(date, HolidayDesc.candleLighting, mask, eventTime, location, linkedEvent, options);

  @override
  String getEmoji() => '🕯️';
}

/// Havdalah after Shabbat or holiday.
class HavdalahEvent extends TimedEvent {
  final int? havdalahMins;
  HavdalahEvent(HDate date, int mask, DateTime eventTime, Location location,
      [this.havdalahMins, Event? linkedEvent, CalOptions? options])
      : super(date, HolidayDesc.havdalah, mask, eventTime, location, linkedEvent, options);

  @override
  String render([String? locale]) => '${renderBrief(locale)}: $fmtTime';

  @override
  String renderBrief([String? locale]) {
    var str = Locale.gettext(getDesc(), locale);
    if (havdalahMins != null && havdalahMins != 0) {
      str += ' ($havdalahMins ${Locale.gettext('min', locale)})';
    }
    return str;
  }

  @override
  String getEmoji() => '✨';
}

// ------------------------------------------------------------ candles

TimedEvent? makeCandleEvent(
    Event? ev, HDate hd, CalOptions options, bool isFriday, bool isSaturday) {
  var havdalahTitle = false;
  var useHavdalahOffset = isSaturday;
  var mask = ev?.mask ?? Flags.lightCandles;
  if (ev != null) {
    if (!isFriday) {
      if (ev.hasAnyFlag([Flags.lightCandlesTzeis, Flags.chanukahCandles])) {
        useHavdalahOffset = true;
      } else if (ev.hasFlag(Flags.yomTovEnds)) {
        havdalahTitle = true;
        useHavdalahOffset = true;
      }
    }
  } else if (isSaturday) {
    havdalahTitle = true;
    mask = Flags.lightCandlesTzeis;
  }
  final offset = useHavdalahOffset ? (options.havdalahMins ?? 0) : (options.candleLightingMins ?? 0);
  final location = options.location!;
  final zmanim = Zmanim.forHDate(location, hd, options.useElevation);
  final time = useHavdalahOffset && offset == 0
      ? zmanim.tzeit(options.havdalahDeg ?? 8.5)
      : zmanim.sunsetOffset(offset, true);
  if (time == null) return null;
  if (havdalahTitle) {
    return HavdalahEvent(hd, mask, time, location, options.havdalahMins, ev, options);
  }
  mask |= Flags.lightCandles;
  return CandleLightingEvent(hd, mask, time, location, ev, options);
}

const _tzeitTucazinsky = 6.45;
const _tzeit3MediumStars = 7.0833333;
const _minorFastEndMinutesIl = 15;
const _alot16Point1 = 16.1;

DateTime? _makeFastStartTime(Zmanim zmanim, CalOptions options) {
  final mins = options.fastStartMins;
  if (mins != null && mins != 0) return zmanim.sunriseOffset(-mins.abs(), true);
  final deg = options.fastStartDeg;
  return zmanim.timeAtAngle(deg == null || deg == 0 ? _alot16Point1 : deg.abs(), true);
}

DateTime? _makeFastEndTime(Zmanim zmanim, bool isTishaBav, CalOptions options) {
  if (isTishaBav) {
    final mins = options.tishaBavEndMins;
    if (mins != null && mins != 0) return zmanim.sunsetOffset(mins.abs(), true);
    final deg = options.tishaBavEndDeg;
    return zmanim.tzeit(deg == null || deg == 0 ? _tzeitTucazinsky : deg.abs());
  }
  final mins = options.fastEndMins;
  if (mins != null && mins != 0) return zmanim.sunsetOffset(mins.abs(), true);
  final deg = options.fastEndDeg;
  if (deg != null && deg != 0) return zmanim.tzeit(deg.abs());
  if (options.il) return zmanim.sunsetOffset(_minorFastEndMinutesIl, true);
  return zmanim.tzeit(_tzeit3MediumStars);
}

/// Holiday event representing a fast day with start and end times.
class FastDayEvent extends HolidayEvent {
  final HolidayEvent linkedEvent;
  final TimedEvent? startEvent;
  final TimedEvent? endEvent;
  FastDayEvent(this.linkedEvent, this.startEvent, this.endEvent)
      : super(linkedEvent.getDate(), linkedEvent.getDesc(), linkedEvent.mask,
            linkedEvent.emoji, linkedEvent.cholHaMoedDay, linkedEvent.observed) {
    memo = linkedEvent.memo;
  }

  @override
  String render([String? locale]) => linkedEvent.render(locale);
  @override
  String renderBrief([String? locale]) => linkedEvent.renderBrief(locale);
  @override
  String urlDateSuffix() => linkedEvent.urlDateSuffix();
  @override
  String? url() => linkedEvent.url();
  @override
  String getEmoji() => linkedEvent.getEmoji();
  @override
  List<String> getCategories() => linkedEvent.getCategories();
}

/// Makes a pair of events representing fast start and end times.
FastDayEvent makeFastStartEnd(HolidayEvent ev, CalOptions options) {
  final desc = ev.getDesc();
  if (desc == HolidayDesc.yomKippur) {
    throw ArgumentError('YK does not require this function');
  }
  final hd = ev.getDate();
  final location = options.location!;
  final zmanim = Zmanim.forHDate(location, hd, options.useElevation);
  TimedEvent? startEvent;
  TimedEvent? endEvent;
  TimedEvent mk(DateTime t, String d) => TimedEvent(hd, d, ev.mask, t, location, ev, options);
  if (desc == HolidayDesc.erevTishaBav) {
    final sunset = zmanim.sunset();
    if (sunset != null) startEvent = mk(sunset, HolidayDesc.fastBegins);
  } else if (desc.startsWith(HolidayDesc.tishaBav)) {
    final fastEnd = _makeFastEndTime(zmanim, true, options);
    if (fastEnd != null) endEvent = mk(fastEnd, HolidayDesc.fastEnds);
  } else {
    final fastStart = _makeFastStartTime(zmanim, options);
    if (fastStart != null) startEvent = mk(fastStart, HolidayDesc.fastBegins);
    if (hd.getDay() != 5 && !(hd.getDate() == 14 && hd.getMonth() == Months.nisan)) {
      final fastEnd = _makeFastEndTime(zmanim, false, options);
      if (fastEnd != null) endEvent = mk(fastEnd, HolidayDesc.fastEnds);
    }
  }
  return FastDayEvent(ev, startEvent, endEvent);
}

/// Chanukah event with candle-lighting time.
class TimedChanukahEvent extends ChanukahEvent {
  final Location location;
  String eventTimeStr;
  TimedChanukahEvent(ChanukahEvent ev, DateTime eventTime, this.location)
      : eventTimeStr = Zmanim.formatTime(Zmanim.roundTime(eventTime), location.tzLocation),
        super(ev.getDate(), ev.getDesc(), ev.mask, ev.chanukahDay) {
    this.eventTime = Zmanim.roundTime(eventTime);
    emoji = ev.emoji;
  }
}

TimedChanukahEvent? makeWeekdayChanukahCandleLighting(ChanukahEvent ev, CalOptions options) {
  final hd = ev.getDate();
  final location = options.location!;
  final zmanim = Zmanim.forHDate(location, hd, options.useElevation);
  final t = zmanim.beinHaShmashos();
  if (t == null) return null;
  return TimedChanukahEvent(ev, t, location);
}

// ------------------------------------------------------------ DailyLearning

typedef LearningCalendarFn = Event? Function(HDate hd, bool il);

class _LearningCalendar {
  final LearningCalendarFn fn;
  final HDate? startDate;
  _LearningCalendar(this.fn, this.startDate);
}

/// Plug-ins for daily learning calendars such as Daf Yomi, Mishna Yomi,
/// Nach Yomi, etc. Register via [DailyLearning.addCalendar]; the learning
/// schedules in this package are registered by [registerLearningSchedules].
class DailyLearning {
  DailyLearning._();
  static final Map<String, _LearningCalendar> _cals = {};

  static void addCalendar(String name, LearningCalendarFn calendar, [HDate? startDate]) {
    _cals[name.toLowerCase()] = _LearningCalendar(calendar, startDate);
  }

  static Event? lookup(String name, HDate hd, bool il) =>
      _cals[name.toLowerCase()]?.fn(hd, il);

  static HDate? getStartDate(String name) => _cals[name.toLowerCase()]?.startDate;
  static bool has(String name) => _cals.containsKey(name.toLowerCase());
  static List<String> getCalendars() => _cals.keys.toList();
}

// ------------------------------------------------------------ calendar

const _maxNumYears = 2000;

(int, int) getStartAndEnd(CalOptions options) {
  if ((options.start == null) != (options.end == null)) {
    throw ArgumentError('options.start requires options.end');
  }
  if (options.start != null) {
    final s = options.start!.abs();
    final e = options.end!.abs();
    if (e - s > 365 * _maxNumYears) {
      throw RangeError('Date range exceeds $_maxNumYears years');
    }
    return (s, e);
  }
  final isHebrewYear = options.isHebrewYear;
  final theYear = options.year ??
      (isHebrewYear ? HDate.today().getFullYear() : DateTime.now().year);
  if (isHebrewYear && theYear < 1) throw RangeError('Invalid Hebrew year $theYear');
  int theMonth = 0;
  final m = options.month;
  if (m != null) {
    if (isHebrewYear) {
      theMonth = m is int ? m : monthFromName('$m');
    } else if (m is int) {
      theMonth = m;
    }
  }
  final numYears = options.numYears ?? 1;
  if (numYears > _maxNumYears) throw RangeError('options.numYears exceeds $_maxNumYears');
  if (isHebrewYear) {
    final startDate = HDate(1, theMonth != 0 ? theMonth : Months.tishrei, theYear);
    var startAbs = startDate.abs();
    final endAbs = theMonth != 0
        ? startAbs + startDate.daysInMonth()
        : HDate(1, Months.tishrei, theYear + numYears).abs() - 1;
    if (theMonth == 0 && theYear > 1) startAbs--;
    return (startAbs, endAbs);
  }
  final gregMonth = theMonth != 0 ? theMonth : 1;
  final startAbs = gregYmdToAbs(theYear, gregMonth, 1);
  final endAbs = theMonth != 0
      ? startAbs + daysInGregMonth(theMonth, theYear) - 1
      : gregYmdToAbs(theYear + numYears, 1, 1) - 1;
  return (startAbs, endAbs);
}

const Map<String, int> _israelCityOffset = {
  'Jerusalem': 40,
  'Haifa': 30,
  "Zikhron Ya'aqov": 30,
  "Zikhron Ya'akov": 30,
  'Zikhron Yaakov': 30,
  "Zichron Ya'akov": 30,
  'Zichron Yaakov': 30,
};
const Map<String, int> _geoIdCandleOffset = {'281184': 40, '294801': 30, '293067': 30};
const _tzeit3SmallStars = 8.5;

void _checkCandleOptions(CalOptions options) {
  if (!options.candlelighting) return;
  final location = options.location;
  if (location == null) {
    throw ArgumentError('options.candlelighting requires valid options.location');
  }
  if (options.havdalahMins != null && options.havdalahDeg != null) {
    throw ArgumentError('options.havdalahMins and options.havdalahDeg are mutually exclusive');
  }
  var min = options.candleLightingMins ?? 18;
  if (location.getIsrael() && min.abs() == 18) {
    min = _overrideIsraelCandleMins(location);
  }
  options.candleLightingMins = -min.abs();
  if (options.havdalahMins != null) {
    options.havdalahMins = options.havdalahMins!.abs();
  } else if (options.havdalahDeg != null) {
    options.havdalahDeg = options.havdalahDeg!.abs();
  } else {
    options.havdalahDeg = _tzeit3SmallStars;
  }
}

int _overrideIsraelCandleMins(Location location) {
  final geoid = location.getGeoId();
  if (geoid != null) {
    final o = _geoIdCandleOffset['$geoid'];
    if (o != null) return o;
  }
  final shortName = location.getShortName();
  if (shortName != null) {
    final o = _israelCityOffset[shortName];
    if (o != null) return o;
  }
  return 20;
}

int _getMaskFromOptions(CalOptions options) {
  if (options.mask != null) return _setOptionsFromMask(options);
  final il = options.il || (options.location?.getIsrael() ?? false);
  var mask = 0;
  if (!options.noHolidays) {
    mask |= Flags.roshChodesh |
        Flags.yomTovEnds |
        Flags.minorFast |
        Flags.specialShabbat |
        Flags.modernHoliday |
        Flags.majorFast |
        Flags.minorHoliday |
        Flags.erev |
        Flags.cholHamoed |
        Flags.lightCandles |
        Flags.lightCandlesTzeis |
        Flags.chanukahCandles;
  }
  if (options.candlelighting) {
    mask |= Flags.lightCandles | Flags.lightCandlesTzeis | Flags.yomTovEnds;
  }
  if (options.noRoshChodesh) mask &= ~Flags.roshChodesh;
  if (options.noModern) mask &= ~Flags.modernHoliday;
  if (options.noMinorFast) mask &= ~Flags.minorFast;
  if (options.noSpecialShabbat) {
    mask &= ~Flags.specialShabbat;
    mask &= ~Flags.shabbatMevarchim;
  }
  mask |= il ? Flags.ilOnly : Flags.chulOnly;
  if (options.sedrot) mask |= Flags.parshaHashavua;
  if (options.omer) mask |= Flags.omerCount;
  if (options.shabbatMevarchim) mask |= Flags.shabbatMevarchim;
  if (options.yomKippurKatan) mask |= Flags.yomKippurKatan;
  if (options.behab) mask |= Flags.behab;
  if (options.yizkor) mask |= Flags.yizkor;
  final dl = options.dailyLearning;
  if (_truthy(dl['dafYomi'])) mask |= Flags.dafYomi;
  if (_truthy(dl['mishnaYomi'])) mask |= Flags.mishnaYomi;
  if (_truthy(dl['nachYomi'])) mask |= Flags.nachYomi;
  if (_truthy(dl['yerushalmi'])) mask |= Flags.yerushalmiYomi;
  return mask;
}

bool _truthy(Object? v) =>
    v != null && v != false && v != 0 && v != '';

int _setOptionsFromMask(CalOptions options) {
  final m = options.mask ?? 0;
  if (m & Flags.roshChodesh != 0) options.noRoshChodesh = false;
  if (m & Flags.modernHoliday != 0) options.noModern = false;
  if (m & Flags.minorFast != 0) options.noMinorFast = false;
  if (m & Flags.specialShabbat != 0) options.noSpecialShabbat = false;
  if (m & Flags.parshaHashavua != 0) options.sedrot = true;
  if (m & Flags.dafYomi != 0) options.dailyLearning['dafYomi'] = true;
  if (m & Flags.mishnaYomi != 0) options.dailyLearning['mishnaYomi'] = true;
  if (m & Flags.nachYomi != 0) options.dailyLearning['nachYomi'] = true;
  if (m & Flags.yerushalmiYomi != 0) options.dailyLearning['yerushalmi'] = 1;
  if (m & Flags.omerCount != 0) options.omer = true;
  if (m & Flags.shabbatMevarchim != 0) options.shabbatMevarchim = true;
  if (m & Flags.yomKippurKatan != 0) options.yomKippurKatan = true;
  if (m & Flags.behab != 0) options.behab = true;
  if (m & Flags.yizkor != 0) options.yizkor = true;
  return m;
}

final _defaultLocation = Location(0, 0, false, 'UTC');

/// Calculates holidays and other Hebrew calendar events based on [options].
///
/// Each holiday is represented by an [Event] object which includes a date,
/// a description, flags and optional attributes.
List<Event> calendar([CalOptions? options0]) {
  final options = (options0 ?? CalOptions()).copy();
  _checkCandleOptions(options);
  final location = options.location ??= _defaultLocation;
  final il = options.il = options.il || location.getIsrael();
  final hasUserMask = options.mask != null;
  options.mask = _getMaskFromOptions(options);
  if (options.locale == null) {
    options.locale = options.ashkenazi ? 'ashkenazi' : 'en';
  } else if (!Locale.hasLocale(options.locale!)) {
    throw ArgumentError("Locale '${options.locale}' not found");
  }
  final evts = <Event>[];
  Sedra? sedra;
  HolidayYearMap? holidaysYear;
  var beginOmer = -1;
  var endOmer = -1;
  var currentYear = -1;
  final (startAbs, endAbs) = getStartAndEnd(options);
  final startGregYear = abs2greg(startAbs).year;
  if (startGregYear < 100 || startGregYear > 9999) {
    options.candlelighting = false;
    options.sedrot = false;
    options.dailyLearning = {};
  }
  for (var abs = startAbs; abs <= endAbs; abs++) {
    final hd = HDate.fromAbs(abs);
    final hyear = hd.getFullYear();
    if (hyear != currentYear) {
      currentYear = hyear;
      holidaysYear = getHolidaysForYear(currentYear);
      if (options.sedrot) sedra = getSedra(currentYear, il);
      if (options.omer) {
        beginOmer = hebrew2abs(currentYear, Months.nisan, 16);
        endOmer = hebrew2abs(currentYear, Months.sivan, 5);
      }
    }
    final prevEventsLength = evts.length;
    final dow = hd.getDay();
    final isFriday = dow == 5;
    final isSaturday = dow == 6;
    TimedEvent? candlesEv;
    final holidays =
        (holidaysYear![hd.toString()] ?? const <HolidayEvent>[]).where((ev) => ev.observedIn(il)).toList();
    for (final ev in holidays) {
      candlesEv = _appendHolidayAndRelated(candlesEv, evts, ev, options, isFriday, isSaturday, hasUserMask);
    }
    final mm = hd.getMonth();
    final dd = hd.getDate();
    if (isFriday && options.candlelighting && mm == Months.nisan && dd == 13) {
      final biurEv = _makeBiurChametzEvent(hd, options);
      if (biurEv != null) evts.add(biurEv);
    }
    if (options.sedrot && isSaturday) {
      final parsha0 = sedra!.lookup(abs);
      if (!parsha0.chag) evts.add(ParshaEvent(parsha0));
    }
    if (options.yizkor) {
      if ((mm == Months.tishrei && (dd == 10 || dd == 22)) ||
          (mm == Months.nisan && dd == (il ? 21 : 22)) ||
          (mm == Months.sivan && dd == (il ? 6 : 7))) {
        final ev = Event(hd, HolidayDesc.yizkor, Flags.yizkor, '🕯️');
        if (holidays.isNotEmpty) ev.linkedEventRef = holidays[0];
        evts.add(ev);
      }
    }
    var numDailyLearning = 0;
    for (final entry in options.dailyLearning.entries) {
      if (!_truthy(entry.value)) continue;
      final name = _dailyLearningName(entry.key, entry.value);
      final learningEv = DailyLearning.lookup(name, hd, il);
      if (learningEv != null) {
        evts.add(learningEv);
        numDailyLearning++;
      }
    }
    if (options.omer && abs >= beginOmer && abs <= endOmer) {
      evts.add(_makeOmerEvent(hd, abs - beginOmer + 1, options));
    }
    if (isSaturday && (options.molad || options.shabbatMevarchim)) {
      evts.addAll(_makeMoladAndMevarchimChodesh(hd, options));
    }
    if (candlesEv == null && options.candlelighting && (isFriday || isSaturday)) {
      candlesEv = makeCandleEvent(null, hd, options, isFriday, isSaturday);
      if (isFriday && candlesEv != null && sedra != null) {
        final parsha = sedra.lookup(abs);
        candlesEv.memo = !parsha.chag
            ? ParshaEvent(parsha).render(options.locale)
            : Locale.gettext(parsha.parsha[0], options.locale);
      }
    }
    if (candlesEv is HavdalahEvent && (options.havdalahMins == 0 || options.havdalahDeg == 0)) {
      candlesEv = null;
    }
    if (candlesEv != null) evts.add(candlesEv);
    if (options.addHebrewDates ||
        (options.addHebrewDatesForEvents && prevEventsLength != evts.length - numDailyLearning)) {
      final e2 = HebrewDateEvent(hd);
      if (prevEventsLength == evts.length) {
        evts.add(e2);
      } else {
        evts.insert(prevEventsLength, e2);
      }
    }
  }
  return evts;
}

String _dailyLearningName(String key, Object val) {
  if (key == 'yerushalmi') {
    return val == 2 ? 'yerushalmi-schottenstein' : 'yerushalmi-vilna';
  }
  return key;
}

TimedEvent? _appendHolidayAndRelated(TimedEvent? candlesEv, List<Event> events, HolidayEvent ev0,
    CalOptions options, bool isFriday, bool isSaturday, bool hasUserMask) {
  HolidayEvent ev = ev0;
  final il = options.il;
  if (!ev.observedIn(il)) return candlesEv;
  final eFlags = ev.mask;
  final isYomKippurKatan = ev.hasFlag(Flags.yomKippurKatan);
  final isBehab = ev.hasFlag(Flags.behab);
  if ((!options.yomKippurKatan && isYomKippurKatan) ||
      (!options.behab && isBehab) ||
      (options.noModern && ev.hasFlag(Flags.modernHoliday))) {
    return candlesEv;
  }
  if (options.candlelighting && ev.getDesc() == HolidayDesc.erevPesach) {
    events.addAll(_makeErevPesachChametzEvents(ev, options));
  }
  final isMajorFast = ev.hasFlag(Flags.majorFast);
  final isMinorFast = ev.hasFlag(Flags.minorFast);
  final isChanukah = ev.hasFlag(Flags.chanukahCandles);
  final hasCandles = ev.hasAnyFlag(
      [Flags.lightCandles, Flags.lightCandlesTzeis, Flags.chanukahCandles, Flags.yomTovEnds]);
  FastDayEvent? fastEv;
  if (options.candlelighting && (isMajorFast || isMinorFast) && ev.getDesc() != HolidayDesc.yomKippur) {
    ev = fastEv = makeFastStartEnd(ev, options);
    if (fastEv.startEvent != null && (isMajorFast || (isMinorFast && !options.noMinorFast))) {
      events.add(fastEv.startEvent!);
    }
  }
  if (eFlags & options.mask! != 0 || (eFlags == 0 && !hasUserMask)) {
    if (options.candlelighting && hasCandles) {
      final hd = ev.getDate();
      candlesEv = makeCandleEvent(ev, hd, options, isFriday, isSaturday);
      if (isChanukah && candlesEv != null && !options.noHolidays) {
        final chanukahEv = makeWeekdayChanukahCandleLighting(ev as ChanukahEvent, options);
        if (chanukahEv != null) {
          if (isFriday || isSaturday) {
            chanukahEv.eventTime = candlesEv.eventTime;
            chanukahEv.eventTimeStr = candlesEv.eventTimeStr;
          }
          ev = chanukahEv;
        }
        candlesEv = null;
      }
    }
    if (!options.noHolidays ||
        (options.yomKippurKatan && isYomKippurKatan) ||
        (options.behab && isBehab)) {
      events.add(ev);
    }
  }
  if ((isMajorFast || (isMinorFast && !options.noMinorFast)) && fastEv?.endEvent != null) {
    events.add(fastEv!.endEvent!);
  }
  return candlesEv;
}

List<Event> _makeMoladAndMevarchimChodesh(HDate hd, CalOptions options) {
  final evts = <Event>[];
  final hmonth = hd.getMonth();
  final hdate = hd.getDate();
  if (hmonth != Months.elul && hdate >= 23 && hdate <= 29) {
    final hyear = hd.getFullYear();
    final monNext = hmonth == monthsInYear(hyear) ? Months.nisan : hmonth + 1;
    if (options.molad) {
      evts.add(MoladEvent(hd, hyear, monNext,
          hour12: options.hour12, cc: options.location?.getCountryCode(), il: options.il));
    }
    if (options.shabbatMevarchim) {
      final nextMonthName = getMonthName(monNext, hyear);
      final memo = Molad(hyear, monNext)
          .render(options.locale, options.hour12, options.location?.getCountryCode(), options.il);
      evts.add(MevarchimChodeshEvent(hd, nextMonthName, memo));
    }
  }
  return evts;
}

OmerEvent _makeOmerEvent(HDate hd, int omerDay, CalOptions options) {
  final omerEv = OmerEvent(hd, omerDay);
  if (options.candlelighting) {
    final zmanim = Zmanim.forHDate(options.location!, hd.prev(), false);
    omerEv.alarm = zmanim.tzeit(7.0833);
  }
  return omerEv;
}

List<TimedEvent> _makeErevPesachChametzEvents(Event erevPesachEv, CalOptions options) {
  final location = options.location!;
  final hd = erevPesachEv.getDate();
  final zmanim = Zmanim.forHDate(location, hd, options.useElevation);
  final zmanAchilas = zmanim.sofZmanTfilla();
  if (zmanAchilas == null) return const [];
  final ev = TimedEvent(hd, HolidayDesc.sofZmanAchilatChametz, 0, zmanAchilas, location, null, options)
    ..emoji = '🍞';
  final evts = <TimedEvent>[ev];
  if (hd.getDay() != 6) {
    final biurEv = _makeBiurChametzEvent(hd, options);
    if (biurEv != null) evts.add(biurEv);
  }
  return evts;
}

TimedEvent? _makeBiurChametzEvent(HDate hd, CalOptions options) {
  final location = options.location!;
  final zmanim = Zmanim.forHDate(location, hd, options.useElevation);
  final time = zmanim.sofZmanBiurChametzGRA();
  if (time == null) return null;
  return TimedEvent(hd, HolidayDesc.biurChametz, 0, time, location, null, options)..emoji = '🔥';
}
