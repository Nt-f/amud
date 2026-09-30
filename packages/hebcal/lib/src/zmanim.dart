// Port of @hebcal/core zmanim.ts
// Hebcal - A Jewish Calendar Generator
// Copyright (c) 1994-2020 Danny Sadinoff
// Portions copyright Eyal Schachter and Michael J. Radwin
// Dart port licensed under GPL-2.0-or-later.

import 'package:timezone/timezone.dart' as tz;

import 'greg.dart';
import 'hdate.dart';
import 'molad.dart';
import 'noaa.dart';

const double _geometricZenith = 90;
const double _zenith1Point583 = _geometricZenith + 1.583;
const double _civilZenith = _geometricZenith + 6;

DateTime? _millisToDate(double millis) {
  if (millis.isNaN) return null;
  final ms = millis.toInt();
  return DateTime.fromMillisecondsSinceEpoch(ms - ms % 1000, isUtc: true);
}

double _temporalHourMillis(double startOfDay, double endOfDay) =>
    ((endOfDay - startOfDay) / 12).floorToDouble();

/// Calculate halachic times (zmanim / זְמַנִּים) for a given day and location.
///
/// All returned times are UTC instants (`DateTime.isUtc == true`) or `null`
/// if the zman does not occur (e.g. polar regions). Use [toLocal] or
/// [formatTime] to present them in the location's time zone.
class Zmanim {
  final HDate hdate;
  final PlainDate plainDate;
  final GeoLocation gloc;
  final NOAACalculator noaa;
  bool useElevation;

  Zmanim(this.gloc, PlainDate date, this.useElevation)
      : plainDate = date,
        hdate = HDate.fromAbs(date.abs),
        noaa = NOAACalculator(gloc, date);

  factory Zmanim.forHDate(GeoLocation gloc, HDate hd, bool useElevation) =>
      Zmanim(gloc, hd.plainDate(), useElevation);

  factory Zmanim.forDate(GeoLocation gloc, DateTime dt, bool useElevation) =>
      Zmanim(gloc, PlainDate.fromDateTime(dt), useElevation);

  bool getUseElevation() => useElevation;
  void setUseElevation(bool v) => useElevation = v;

  /// Time at which the sun is [angle] degrees below the horizon.
  DateTime? timeAtAngle(double angle, bool rising) {
    final offsetZenith = _geometricZenith + angle;
    return _millisToDate(rising
        ? _sunriseMillis(offsetZenith, true)
        : _sunsetMillis(offsetZenith, true));
  }

  double _sunriseMillis(double zenith, bool useElevation) {
    final utc = useElevation
        ? noaa.getUTCSunrise0(zenith)
        : noaa.getUTCSeaLevelSunrise(zenith);
    return noaa.getEpochMillisFromTime(utc, true);
  }

  double _sunsetMillis(double zenith, bool useElevation) {
    final utc = useElevation
        ? noaa.getUTCSunset0(zenith)
        : noaa.getUTCSeaLevelSunset(zenith);
    return noaa.getEpochMillisFromTime(utc, false);
  }

  /// Upper edge of the Sun appears over the eastern horizon (elevation-aware
  /// when [useElevation] is set).
  DateTime? sunrise() => _millisToDate(_sunriseMillis(_geometricZenith, useElevation));
  DateTime? seaLevelSunrise() => _millisToDate(_sunriseMillis(_geometricZenith, false));
  DateTime? sunset() => _millisToDate(_sunsetMillis(_geometricZenith, useElevation));
  DateTime? seaLevelSunset() => _millisToDate(_sunsetMillis(_geometricZenith, false));

  /// Civil dawn; Sun is 6° below the horizon in the morning.
  DateTime? dawn() => _millisToDate(_sunriseMillis(_civilZenith, true));

  /// Civil dusk; Sun is 6° below the horizon in the evening.
  DateTime? dusk() => _millisToDate(_sunsetMillis(_civilZenith, true));

  /// Sunset of the previous day.
  DateTime? gregEve() =>
      Zmanim(gloc, plainDate.addDays(-1), useElevation).sunset();

  double nightHour() {
    final sr = sunrise();
    final eve = gregEve();
    if (sr == null || eve == null) return double.nan;
    return (sr.millisecondsSinceEpoch - eve.millisecondsSinceEpoch) / 12;
  }

  /// Midday – Chatzot; Sunrise plus 6 halachic hours.
  DateTime? chatzot() {
    final startOfDay = _sunriseMillis(_geometricZenith, false);
    final endOfDay = _sunsetMillis(_geometricZenith, false);
    return _millisToDate(startOfDay + _temporalHourMillis(startOfDay, endOfDay) * 6);
  }

  /// Midnight – Chatzot; Sunset plus 6 halachic hours.
  DateTime? chatzotNight() {
    final sr = sunrise();
    final nh = nightHour();
    if (sr == null || nh.isNaN) return null;
    return DateTime.fromMillisecondsSinceEpoch(
        (sr.millisecondsSinceEpoch - nh * 6).truncate(),
        isUtc: true);
  }

  /// Dawn – Alot haShachar; Sun is 16.1° below the horizon in the morning.
  DateTime? alotHaShachar() => timeAtAngle(16.1, true);

  /// Dawn – Alot haShachar; calculated as 72 minutes before sunrise.
  DateTime? alotHaShachar72() => sunriseOffset(-72, false, false);

  /// Earliest talis & tefillin – Misheyakir; Sun is 11.5° below the horizon.
  DateTime? misheyakir() => timeAtAngle(11.5, true);

  /// Earliest talis & tefillin – Misheyakir Machmir; Sun is 10.2° below.
  DateTime? misheyakirMachmir() => timeAtAngle(10.2, true);

  double _shaahZmanisBasedZmanMillis(double startOfDay, double endOfDay, double hours) {
    final offset = (_temporalHourMillis(startOfDay, endOfDay) * hours).truncateToDouble();
    return startOfDay + offset;
  }

  DateTime? _shaahZmanisBasedZman(double hours) {
    final startOfDay = _sunriseMillis(_geometricZenith, useElevation);
    final endOfDay = _sunsetMillis(_geometricZenith, useElevation);
    return _millisToDate(_shaahZmanisBasedZmanMillis(startOfDay, endOfDay, hours));
  }

  /// Latest Shema (Gra); Sunrise plus 3 halachic hours.
  DateTime? sofZmanShma() => _shaahZmanisBasedZman(3);

  /// Latest Shacharit (Gra); Sunrise plus 4 halachic hours.
  DateTime? sofZmanTfilla() => _shaahZmanisBasedZman(4);

  /// Latest time to burn chametz; Sunrise plus 5 halachic hours.
  DateTime? sofZmanBiurChametzGRA() => _shaahZmanisBasedZman(5);

  (DateTime?, double) getTemporalHour72(bool forceSeaLevel) {
    final alot72 = sunriseOffset(-72, false, forceSeaLevel);
    final tzeit72 = sunsetOffset(72, false, forceSeaLevel);
    if (alot72 == null || tzeit72 == null) return (null, double.nan);
    return (
      alot72,
      (tzeit72.millisecondsSinceEpoch - alot72.millisecondsSinceEpoch) / 12
    );
  }

  (DateTime?, double) getTemporalHourByDeg(double angle) {
    final alot = timeAtAngle(angle, true);
    final tzeit = timeAtAngle(angle, false);
    if (alot == null || tzeit == null) return (null, double.nan);
    return (alot, (tzeit.millisecondsSinceEpoch - alot.millisecondsSinceEpoch) / 12);
  }

  DateTime? _plus((DateTime?, double) base, double hours) {
    final (start, th) = base;
    if (start == null || th.isNaN) return null;
    return start.add(Duration(milliseconds: (hours * th).floor()));
  }

  /// Latest Shema (MGA); Sunrise plus 3 halachic hours, according to MGA
  /// (72 minutes).
  DateTime? sofZmanShmaMGA() => _plus(getTemporalHour72(true), 3);
  DateTime? sofZmanShmaMGA16Point1() => _plus(getTemporalHourByDeg(16.1), 3);
  DateTime? sofZmanShmaMGA19Point8() => _plus(getTemporalHourByDeg(19.8), 3);
  DateTime? sofZmanTfillaMGA() => _plus(getTemporalHour72(true), 4);
  DateTime? sofZmanTfillaMGA16Point1() => _plus(getTemporalHourByDeg(16.1), 4);
  DateTime? sofZmanTfillaMGA19Point8() => _plus(getTemporalHourByDeg(19.8), 4);

  /// Earliest Mincha – Mincha Gedola; Sunrise plus 6.5 halachic hours.
  DateTime? minchaGedola() => _shaahZmanisBasedZman(6.5);
  DateTime? minchaGedolaMGA() => _plus(getTemporalHour72(false), 6.5);

  /// Preferable earliest time to recite Minchah – Mincha Ketana; Sunrise
  /// plus 9.5 halachic hours.
  DateTime? minchaKetana() => _shaahZmanisBasedZman(9.5);
  DateTime? minchaKetanaMGA() => _plus(getTemporalHour72(false), 9.5);

  /// Plag haMincha; Sunrise plus 10.75 halachic hours.
  DateTime? plagHaMincha() => _shaahZmanisBasedZman(10.75);

  /// Nightfall; Sun is [angle] degrees below the horizon (default 8.5°:
  /// three small stars).
  DateTime? tzeit([double angle = 8.5]) => timeAtAngle(angle, false);

  /// Rabbeinu Tam: 72 minutes after sunset.
  DateTime? tzeit72() {
    final s = useElevation ? noaa.getSunset() : noaa.getSeaLevelSunset();
    return s?.add(const Duration(minutes: 72));
  }

  /// Alias for sunrise.
  DateTime? neitzHaChama() => sunrise();

  /// Alias for sunset.
  DateTime? shkiah() => sunset();

  /// Rabbeinu Tam's bein hashmashos: 13.5 minutes before tzeit 7.083°.
  DateTime? beinHaShmashos() =>
      tzeit(7.083)?.subtract(const Duration(milliseconds: 13 * 60 * 1000 + 30 * 1000));

  DateTime _midnightLastNight() =>
      tz.TZDateTime(gloc.tzLocation, plainDate.year, plainDate.month, plainDate.day).toUtc();
  DateTime _midnightTonight() {
    final n = plainDate.addDays(1);
    return tz.TZDateTime(gloc.tzLocation, n.year, n.month, n.day).toUtc();
  }

  DateTime? _moladBasedTime(
      DateTime moladBasedTime, DateTime? alos, DateTime? tzais, bool techila) {
    if (moladBasedTime.isBefore(_midnightLastNight()) ||
        moladBasedTime.isAfter(_midnightTonight())) {
      return null;
    }
    if (alos == null || tzais == null) return moladBasedTime;
    if (moladBasedTime.isAfter(alos) && moladBasedTime.isBefore(tzais)) {
      return techila ? tzais : alos;
    }
    return moladBasedTime;
  }

  /// Latest Kiddush Levana: halfway between molad and molad.
  DateTime? getSofZmanKidushLevanaBetweenMoldos([DateTime? alos, DateTime? tzais]) {
    final hd = hdate;
    if (hd.getDate() < 11 || hd.getDate() > 16) return null;
    final molad = Molad(hd.getFullYear(), hd.getMonth());
    return _moladBasedTime(molad.getSofZmanKidushLevanaBetweenMoldos(), alos, tzais, false);
  }

  /// Latest Kiddush Levana: 15 days after the molad.
  DateTime? getSofZmanKidushLevana15Days([DateTime? alos, DateTime? tzais]) {
    final hd = hdate;
    if (hd.getDate() < 11 || hd.getDate() > 17) return null;
    final molad = Molad(hd.getFullYear(), hd.getMonth());
    return _moladBasedTime(molad.getSofZmanKidushLevana15Days(), alos, tzais, false);
  }

  /// Earliest Kiddush Levana: 3 days after the molad.
  DateTime? getTchilasZmanKidushLevana3Days([DateTime? alos, DateTime? tzais]) {
    final hd = hdate;
    if (hd.getDate() > 5 && hd.getDate() < 30) return null;
    final molad = Molad(hd.getFullYear(), hd.getMonth());
    var zman = _moladBasedTime(molad.getTchilasZmanKidushLevana3Days(), alos, tzais, true);
    if (zman == null && hd.getDate() == 30) {
      final hd2 = hd.addWeeks(1);
      final molad2 = Molad(hd2.getFullYear(), hd2.getMonth());
      zman = _moladBasedTime(molad2.getTchilasZmanKidushLevana3Days(), null, null, true);
    }
    return zman;
  }

  /// The molad, if it occurs on this civil day.
  DateTime? getZmanMolad() {
    final hd = hdate;
    if (hd.getDate() > 2 && hd.getDate() < 27) return null;
    final molad = Molad(hd.getFullYear(), hd.getMonth());
    var zman = _moladBasedTime(molad.getInstant(), null, null, true);
    if (zman == null && hd.getDate() > 26) {
      final hd2 = hd.addWeeks(1);
      final molad2 = Molad(hd2.getFullYear(), hd2.getMonth());
      zman = _moladBasedTime(molad2.getInstant(), null, null, true);
    }
    return zman;
  }

  /// Earliest Kiddush Levana: 7 days after the molad.
  DateTime? getTchilasZmanKidushLevana7Days([DateTime? alos, DateTime? tzais]) {
    final hd = hdate;
    if (hd.getDate() < 4 || hd.getDate() > 9) return null;
    final molad = Molad(hd.getFullYear(), hd.getMonth());
    return _moladBasedTime(molad.getTchilasZmanKidushLevana7Days(), alos, tzais, true);
  }

  double _sunriseBaalHatanya() => _sunriseMillis(_zenith1Point583, true);
  double _sunsetBaalHatanya() => _sunsetMillis(_zenith1Point583, true);

  /// Alos (dawn) according to the Baal Hatanya: sun 16.9° below the horizon.
  DateTime? alosBaalHatanya() => timeAtAngle(16.9, true);

  DateTime? _shaahZmanisBaalHatanya(double hours) => _millisToDate(
      _shaahZmanisBasedZmanMillis(_sunriseBaalHatanya(), _sunsetBaalHatanya(), hours));

  DateTime? sofZmanShmaBaalHatanya() => _shaahZmanisBaalHatanya(3);
  DateTime? sofZmanTfilaBaalHatanya() => _shaahZmanisBaalHatanya(4);
  DateTime? minchaGedolaBaalHatanya() => _shaahZmanisBaalHatanya(6.5);
  DateTime? minchaKetanaBaalHatanya() => _shaahZmanisBaalHatanya(9.5);
  DateTime? plagHaminchaBaalHatanya() => _shaahZmanisBaalHatanya(10.75);

  /// Tzeit according to the Baal Hatanya: sun 6° below the horizon.
  DateTime? tzaisBaalHatanya() => timeAtAngle(6, false);

  /// Returns sunrise + [offset] minutes (either positive or negative).
  DateTime? sunriseOffset(num offset, [bool roundMinute = true, bool forceSeaLevel = false]) {
    final sr = forceSeaLevel ? seaLevelSunrise() : sunrise();
    return _applyOffset(sr, offset, roundMinute);
  }

  /// Returns sunset + [offset] minutes (either positive or negative).
  DateTime? sunsetOffset(num offset, [bool roundMinute = true, bool forceSeaLevel = false]) {
    final ss = forceSeaLevel ? seaLevelSunset() : sunset();
    return _applyOffset(ss, offset, roundMinute);
  }

  static DateTime? _applyOffset(DateTime? t, num offset, bool roundMinute) {
    if (t == null) return null;
    var off = offset;
    var base = t;
    if (roundMinute) {
      if (off > 0 && t.second >= 30) off++;
      base = DateTime.fromMillisecondsSinceEpoch(
          t.millisecondsSinceEpoch - t.second * 1000 - t.millisecond,
          isUtc: true);
    }
    return base.add(Duration(milliseconds: (off * 60 * 1000).round()));
  }

  /// Converts a UTC instant to wall-clock time in this location's zone.
  tz.TZDateTime toLocal(DateTime instant) => tz.TZDateTime.from(instant, gloc.tzLocation);

  /// Rounds to the nearest minute (30+ seconds round up).
  static DateTime roundTime(DateTime dt) {
    final secAndMillis = dt.second * 1000 + dt.millisecond;
    if (secAndMillis == 0) return dt;
    final delta = secAndMillis >= 30000 ? 60000 - secAndMillis : -secAndMillis;
    return dt.add(Duration(milliseconds: delta));
  }

  /// Formats as 24-hour HH:MM in the time zone of [loc]; 'XX:XX' if null.
  static String formatTime(DateTime? dt, tz.Location loc) {
    if (dt == null) return 'XX:XX';
    final l = tz.TZDateTime.from(dt, loc);
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  /// Formats with an ISO-8601 offset, e.g. `2020-01-02T08:03:00-05:00`.
  static String formatISOWithTimeZone(tz.Location loc, DateTime? date) {
    if (date == null) return '0000-00-00T00:00:00Z';
    final l = tz.TZDateTime.from(date, loc);
    String p2(int n) => n.toString().padLeft(2, '0');
    final off = l.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final oa = off.abs();
    return '${l.year.toString().padLeft(4, '0')}-${p2(l.month)}-${p2(l.day)}T${p2(l.hour)}:${p2(l.minute)}:${p2(l.second)}'
        '$sign${p2(oa.inHours)}:${p2(oa.inMinutes % 60)}';
  }

  /// Uses sunset to determine whether the current instant is after sunset
  /// (and therefore belongs to the next Hebrew date).
  static HDate makeSunsetAwareHDate(GeoLocation gloc, DateTime instant, bool useElevation) {
    final local = tz.TZDateTime.from(instant, gloc.tzLocation);
    final pd = PlainDate(local.year, local.month, local.day);
    final z = Zmanim(gloc, pd, useElevation);
    final ss = z.sunset();
    var hd = HDate.fromAbs(pd.abs);
    if (ss != null && !instant.isBefore(ss)) hd = hd.next();
    return hd;
  }
}
