// Port of @hebcal/noaa (itself a port of KosherJava's NOAACalculator)
// Copyright (C) 2004-2023 Eliyahu Hershfeld; TypeScript port by Michael J. Radwin.
// LGPL-2.1. Dart port licensed under LGPL-2.1-or-later.

import 'dart:math' as math;

import 'package:timezone/timezone.dart' as tz;

import 'greg.dart';

double _degToRad(double degrees) => degrees * math.pi / 180;
double _radToDeg(double radians) => radians * 180 / math.pi;

/// A class that contains location information such as latitude and
/// longitude required for astronomical calculations.
class GeoLocation {
  String? locationName;
  final double latitude;
  final double longitude;

  /// Elevation in meters above sea level.
  final double elevation;
  final String timeZoneId;
  tz.Location? _tzLoc;

  GeoLocation(this.locationName, this.latitude, this.longitude,
      double elevation, this.timeZoneId)
      : elevation = elevation < 0 ? 0 : elevation {
    if (latitude < -90 || latitude > 90) {
      throw RangeError('Latitude $latitude out of range [-90,90]');
    }
    if (longitude < -180 || longitude > 180) {
      throw RangeError('Longitude $longitude out of range [-180,180]');
    }
    if (timeZoneId.isEmpty) throw ArgumentError('Invalid timeZoneId');
  }

  double getLatitude() => latitude;
  double getLongitude() => longitude;
  double getElevation() => elevation;
  String? getLocationName() => locationName;
  String getTimeZone() => timeZoneId;

  /// The IANA time zone (requires timezone database to be initialized).
  tz.Location get tzLocation =>
      _tzLoc ??= timeZoneId == 'UTC' ? tz.UTC : tz.getLocation(timeZoneId);

  /// Offset of the zone from UTC at [instant], in milliseconds.
  int tzOffsetMillis(DateTime instant) => tz.TZDateTime.from(instant, tzLocation)
      .timeZoneOffset
      .inMilliseconds;

  /// Local mean time offset for the location, in milliseconds.
  double getLocalMeanTimeOffset(DateTime instant) =>
      longitude * 4 * 60 * 1000 - tzOffsetMillis(instant);

  /// Adjustment to the date for locations crossing the antimeridian.
  int getAntimeridianAdjustment(PlainDate date) {
    if (longitude > -90 && longitude < 120) return 0;
    final midnight = tz.TZDateTime(tzLocation, date.year, date.month, date.day);
    final localHoursOffset =
        getLocalMeanTimeOffset(midnight.toUtc()) / 3600000;
    if (localHoursOffset >= 20) return 1;
    if (localHoursOffset <= -20) return -1;
    return 0;
  }
}

const double _refraction = 34 / 60;
const double _solarRadius = 16 / 60;
const double _earthRadius = 6356.9;

/// Implementation of sunrise and sunset methods to calculate astronomical
/// times based on the NOAA algorithm.
class NOAACalculator {
  static const double geometricZenith = 90;
  static const double civilZenith = 96;
  static const double nauticalZenith = 102;
  static const double astronomicalZenith = 108;
  static const double _julianDayJan1_2000 = 2451545;
  static const double _julianDaysPerCentury = 36525;

  final GeoLocation geoLocation;
  final PlainDate date;
  PlainDate? _adjustedDate;

  NOAACalculator(this.geoLocation, this.date);

  DateTime? getSunrise() => _fromUtcTime(getUTCSunrise0(geometricZenith), true);
  DateTime? getSeaLevelSunrise() =>
      _fromUtcTime(getUTCSeaLevelSunrise(geometricZenith), true);
  DateTime? getSunset() => _fromUtcTime(getUTCSunset0(geometricZenith), false);
  DateTime? getSeaLevelSunset() =>
      _fromUtcTime(getUTCSeaLevelSunset(geometricZenith), false);
  DateTime? getBeginCivilTwilight() => getSunriseOffsetByDegrees(civilZenith);
  DateTime? getBeginNauticalTwilight() => getSunriseOffsetByDegrees(nauticalZenith);
  DateTime? getBeginAstronomicalTwilight() =>
      getSunriseOffsetByDegrees(astronomicalZenith);
  DateTime? getEndCivilTwilight() => getSunsetOffsetByDegrees(civilZenith);
  DateTime? getEndNauticalTwilight() => getSunsetOffsetByDegrees(nauticalZenith);
  DateTime? getEndAstronomicalTwilight() =>
      getSunsetOffsetByDegrees(astronomicalZenith);

  DateTime? getSunriseOffsetByDegrees(double offsetZenith) =>
      _fromUtcTime(getUTCSunrise0(offsetZenith), true);
  DateTime? getSunsetOffsetByDegrees(double offsetZenith) =>
      _fromUtcTime(getUTCSunset0(offsetZenith), false);

  double getUTCSunrise0(double zenith) =>
      getUTCSunrise(_getAdjustedDate(), geoLocation, zenith, true);
  double getUTCSeaLevelSunrise(double zenith) =>
      getUTCSunrise(_getAdjustedDate(), geoLocation, zenith, false);
  double getUTCSunset0(double zenith) =>
      getUTCSunset(_getAdjustedDate(), geoLocation, zenith, true);
  double getUTCSeaLevelSunset(double zenith) =>
      getUTCSunset(_getAdjustedDate(), geoLocation, zenith, false);

  PlainDate _getAdjustedDate() {
    if (_adjustedDate == null) {
      final offset = geoLocation.getAntimeridianAdjustment(date);
      _adjustedDate = offset == 0 ? date : date.addDays(offset);
    }
    return _adjustedDate!;
  }

  double getElevationAdjustment(double elevation) =>
      _radToDeg(math.acos(_earthRadius / (_earthRadius + elevation / 1000)));

  double adjustZenith(double zenith, double elevation) {
    if (zenith == geometricZenith) {
      return zenith + (_solarRadius + _refraction + getElevationAdjustment(elevation));
    }
    return zenith;
  }

  double getUTCSunrise(PlainDate date, GeoLocation geoLocation, double zenith,
      bool adjustForElevation) {
    final elevation = adjustForElevation ? geoLocation.elevation : 0.0;
    final adjustedZenith = adjustZenith(zenith, elevation);
    var sunrise = _getSunriseUTC(_getJulianDay(date), geoLocation.latitude,
            -geoLocation.longitude, adjustedZenith) /
        60;
    if (sunrise.isNaN) return double.nan;
    while (sunrise < 0) {
      sunrise += 24;
    }
    while (sunrise >= 24) {
      sunrise -= 24;
    }
    return sunrise;
  }

  double getUTCSunset(PlainDate date, GeoLocation geoLocation, double zenith,
      bool adjustForElevation) {
    final elevation = adjustForElevation ? geoLocation.elevation : 0.0;
    final adjustedZenith = adjustZenith(zenith, elevation);
    var sunset = _getSunsetUTC(_getJulianDay(date), geoLocation.latitude,
            -geoLocation.longitude, adjustedZenith) /
        60;
    if (sunset.isNaN) return double.nan;
    while (sunset < 0) {
      sunset += 24;
    }
    while (sunset >= 24) {
      sunset -= 24;
    }
    return sunset;
  }

  /// Length of a temporal (solar) hour in milliseconds.
  double getTemporalHour([DateTime? startOfDay, DateTime? endOfDay]) {
    startOfDay ??= getSeaLevelSunrise();
    endOfDay ??= getSeaLevelSunset();
    if (startOfDay == null || endOfDay == null) return double.nan;
    final delta = endOfDay.millisecondsSinceEpoch - startOfDay.millisecondsSinceEpoch;
    return (delta / 12).floorToDouble();
  }

  /// Solar transit (noon) between the given times.
  DateTime? getSunTransit([DateTime? startOfDay, DateTime? endOfDay]) {
    startOfDay ??= getSeaLevelSunrise();
    endOfDay ??= getSeaLevelSunset();
    final th = getTemporalHour(startOfDay, endOfDay);
    if (startOfDay == null || th.isNaN) return null;
    return startOfDay.add(Duration(milliseconds: (th * 6).round()));
  }

  DateTime? _fromUtcTime(double time, bool isSunrise) {
    final ms = getEpochMillisFromTime(time, isSunrise);
    if (ms.isNaN) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true);
  }

  /// Converts a UTC fractional-hours time to epoch milliseconds.
  double getEpochMillisFromTime(double time, bool isSunrise) {
    if (time.isNaN) return double.nan;
    var calculatedTime = time;
    final cal = _getAdjustedDate();
    final hours = calculatedTime.truncate();
    calculatedTime -= hours;
    calculatedTime *= 60;
    final minutes = calculatedTime.truncate();
    calculatedTime -= minutes;
    calculatedTime *= 60;
    final seconds = calculatedTime.truncate();
    calculatedTime -= seconds;
    final localTimeHours = (geoLocation.longitude / 15).truncate();
    var dayOffset = 0;
    if (isSunrise && localTimeHours + hours > 18) {
      dayOffset = -1;
    } else if (!isSunrise && localTimeHours + hours < 6) {
      dayOffset = 1;
    }
    final millis = DateTime.utc(cal.year, cal.month, cal.day, hours, minutes,
            seconds, (calculatedTime * 1000).truncate())
        .millisecondsSinceEpoch;
    return (millis + dayOffset * 86400000).toDouble();
  }

  static double _getJulianDay(PlainDate date) {
    var year = date.year;
    var month = date.month;
    final day = date.day;
    if (month <= 2) {
      year -= 1;
      month += 12;
    }
    final a = year ~/ 100;
    final b = 2 - a + a ~/ 4;
    return (365.25 * (year + 4716)).floorToDouble() +
        (30.6001 * (month + 1)).floorToDouble() +
        day +
        b -
        1524.5;
  }

  static double _jcFromJD(double jd) =>
      (jd - _julianDayJan1_2000) / _julianDaysPerCentury;
  static double _jdFromJC(double jc) =>
      jc * _julianDaysPerCentury + _julianDayJan1_2000;

  static double _sunGeometricMeanLongitude(double jc) {
    var longitude = 280.46646 + jc * (36000.76983 + 0.0003032 * jc);
    while (longitude > 360) {
      longitude -= 360;
    }
    while (longitude < 0) {
      longitude += 360;
    }
    return longitude;
  }

  static double _sunGeometricMeanAnomaly(double jc) =>
      357.52911 + jc * (35999.05029 - 0.0001537 * jc);

  static double _earthOrbitEccentricity(double jc) =>
      0.016708634 - jc * (0.000042037 + 0.0000001267 * jc);

  static double _sunEquationOfCenter(double jc) {
    final mrad = _degToRad(_sunGeometricMeanAnomaly(jc));
    final sinm = math.sin(mrad);
    final sin2m = math.sin(mrad + mrad);
    final sin3m = math.sin(mrad + mrad + mrad);
    return sinm * (1.914602 - jc * (0.004817 + 0.000014 * jc)) +
        sin2m * (0.019993 - 0.000101 * jc) +
        sin3m * 0.000289;
  }

  static double _sunTrueLongitude(double jc) =>
      _sunGeometricMeanLongitude(jc) + _sunEquationOfCenter(jc);

  static double _sunApparentLongitude(double jc) {
    final omega = 125.04 - 1934.136 * jc;
    return _sunTrueLongitude(jc) - 0.00569 - 0.00478 * math.sin(_degToRad(omega));
  }

  static double _meanObliquityOfEcliptic(double jc) {
    final seconds = 21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813));
    return 23 + (26 + seconds / 60) / 60;
  }

  static double _obliquityCorrection(double jc) {
    final omega = 125.04 - 1934.136 * jc;
    return _meanObliquityOfEcliptic(jc) + 0.00256 * math.cos(_degToRad(omega));
  }

  static double _sunDeclination(double jc) {
    final sint = math.sin(_degToRad(_obliquityCorrection(jc))) *
        math.sin(_degToRad(_sunApparentLongitude(jc)));
    return _radToDeg(math.asin(sint));
  }

  static double _equationOfTime(double jc) {
    final epsilon = _obliquityCorrection(jc);
    final geomMeanLongSun = _sunGeometricMeanLongitude(jc);
    final e = _earthOrbitEccentricity(jc);
    final geomMeanAnomalySun = _sunGeometricMeanAnomaly(jc);
    var y = math.tan(_degToRad(epsilon) / 2);
    y *= y;
    final sin2l0 = math.sin(2 * _degToRad(geomMeanLongSun));
    final sinm = math.sin(_degToRad(geomMeanAnomalySun));
    final cos2l0 = math.cos(2 * _degToRad(geomMeanLongSun));
    final sin4l0 = math.sin(4 * _degToRad(geomMeanLongSun));
    final sin2m = math.sin(2 * _degToRad(geomMeanAnomalySun));
    final eot = y * sin2l0 -
        2 * e * sinm +
        4 * e * y * sinm * cos2l0 -
        0.5 * y * y * sin4l0 -
        1.25 * e * e * sin2m;
    return _radToDeg(eot) * 4;
  }

  static double _hourAngle(double lat, double solarDec, double zenith) {
    final latRad = _degToRad(lat);
    final sdRad = _degToRad(solarDec);
    return math.acos(math.cos(_degToRad(zenith)) / (math.cos(latRad) * math.cos(sdRad)) -
        math.tan(latRad) * math.tan(sdRad));
  }

  /// Solar elevation in degrees for an instant at a location.
  static double getSolarElevation(DateTime utc, double lat, double lon) {
    final jc = _jcFromJD(_getJulianDay(PlainDate(utc.year, utc.month, utc.day)));
    final eot = _equationOfTime(jc);
    var longitude = utc.hour + 12 + (utc.minute + eot + utc.second / 60) / 60;
    longitude = -((longitude * 360) / 24).remainder(360);
    final hourAngleRad = _degToRad(lon - longitude);
    final decRad = _degToRad(_sunDeclination(jc));
    final latRad = _degToRad(lat);
    return _radToDeg(math.asin(math.sin(latRad) * math.sin(decRad) +
        math.cos(latRad) * math.cos(decRad) * math.cos(hourAngleRad)));
  }

  /// Solar azimuth in degrees for an instant at a location.
  static double getSolarAzimuth(DateTime utc, double latitude, double lon) {
    final jc = _jcFromJD(_getJulianDay(PlainDate(utc.year, utc.month, utc.day)));
    final eot = _equationOfTime(jc);
    var longitude = utc.hour + 12 + (utc.minute + eot + utc.second / 60) / 60;
    longitude = -((longitude * 360) / 24).remainder(360);
    final hourAngleRad = _degToRad(lon - longitude);
    final decRad = _degToRad(_sunDeclination(jc));
    final latRad = _degToRad(latitude);
    return _radToDeg(math.atan(math.sin(hourAngleRad) /
            (math.cos(hourAngleRad) * math.sin(latRad) -
                math.tan(decRad) * math.cos(latRad)))) +
        180;
  }

  static double _getSunriseUTC(double julianDay, double latitude, double longitude, double zenith) {
    final jc = _jcFromJD(julianDay);
    final noonmin = _getSolarNoonUTC(jc, longitude);
    final tnoon = _jcFromJD(julianDay + noonmin / 1440);
    var eqTime = _equationOfTime(tnoon);
    var solarDec = _sunDeclination(tnoon);
    var hourAngle = _hourAngle(latitude, solarDec, zenith);
    var delta = longitude - _radToDeg(hourAngle);
    var timeUTC = 720 + 4 * delta - eqTime;
    final newt = _jcFromJD(_jdFromJC(jc) + timeUTC / 1440);
    eqTime = _equationOfTime(newt);
    solarDec = _sunDeclination(newt);
    hourAngle = _hourAngle(latitude, solarDec, zenith);
    delta = longitude - _radToDeg(hourAngle);
    timeUTC = 720 + 4 * delta - eqTime;
    return timeUTC;
  }

  static double _getSolarNoonUTC(double jc, double longitude) {
    final tnoon = _jcFromJD(_jdFromJC(jc) + longitude / 360);
    var eqTime = _equationOfTime(tnoon);
    final solNoonUTC = 720 + longitude * 4 - eqTime;
    final newt = _jcFromJD(_jdFromJC(jc) - 0.5 + solNoonUTC / 1440);
    eqTime = _equationOfTime(newt);
    return 720 + longitude * 4 - eqTime;
  }

  static double _getSunsetUTC(double julianDay, double latitude, double longitude, double zenith) {
    final jc = _jcFromJD(julianDay);
    final noonmin = _getSolarNoonUTC(jc, longitude);
    final tnoon = _jcFromJD(julianDay + noonmin / 1440);
    var eqTime = _equationOfTime(tnoon);
    var solarDec = _sunDeclination(tnoon);
    var hourAngle = -_hourAngle(latitude, solarDec, zenith);
    var delta = longitude - _radToDeg(hourAngle);
    var timeUTC = 720 + 4 * delta - eqTime;
    final newt = _jcFromJD(_jdFromJC(jc) + timeUTC / 1440);
    eqTime = _equationOfTime(newt);
    solarDec = _sunDeclination(newt);
    hourAngle = -_hourAngle(latitude, solarDec, zenith);
    delta = longitude - _radToDeg(hourAngle);
    timeUTC = 720 + 4 * delta - eqTime;
    return timeUTC;
  }
}
