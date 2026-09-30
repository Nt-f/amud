// Port of @hebcal/core location.ts
// Hebcal - A Jewish Calendar Generator
// Copyright (c) 1994-2020 Danny Sadinoff
// Portions copyright Eyal Schachter and Michael J. Radwin
// Dart port licensed under GPL-2.0-or-later.

import 'data/core_data.g.dart';
import 'noaa.dart';

const Map<String, String> _zipcodesTzMap = {
  '0': 'UTC',
  '4': 'America/Puerto_Rico',
  '5': 'America/New_York',
  '6': 'America/Chicago',
  '7': 'America/Denver',
  '8': 'America/Los_Angeles',
  '9': 'America/Anchorage',
  '10': 'Pacific/Honolulu',
  '11': 'Pacific/Pago_Pago',
  '13': 'Pacific/Funafuti',
  '14': 'Pacific/Guam',
  '15': 'Pacific/Palau',
  '16': 'Pacific/Chuuk',
};

final Map<String, Location> _classicCities = {};

/// Class representing a Location: [GeoLocation] plus Israel/Diaspora and
/// other metadata.
class Location extends GeoLocation {
  final bool il;
  final String? cc;
  final Object? geoid;
  String? admin1;
  String? stateName;
  int? population;

  Location(double latitude, double longitude, bool il, String tzid,
      {String? cityName, String? countryCode, this.geoid, double elevation = 0})
      : il = il || countryCode == 'IL',
        cc = countryCode,
        super(cityName, latitude, longitude, elevation > 0 ? elevation : 0, tzid);

  bool getIsrael() => il;
  String? getName() => getLocationName();
  String? getCountryCode() => cc;
  String getTzid() => getTimeZone();
  Object? getGeoId() => geoid;

  /// Returns the location name up to the first comma (or null).
  String? getShortName() {
    final name = getLocationName();
    if (name == null) return name;
    final comma = name.indexOf(', ');
    if (comma == -1) return name;
    if (cc == 'US' && name.length > comma + 2 && name[comma + 2] == 'D') {
      if (name.length > comma + 3 && name[comma + 3] == 'C') {
        return name.substring(0, comma + 4);
      }
      if (name.length > comma + 4 && name[comma + 3] == '.' && name[comma + 4] == 'C') {
        return name.substring(0, comma + 6);
      }
    }
    return name.substring(0, comma);
  }

  static void _initClassicCities() {
    for (final entry in citiesData) {
      final p = entry.split('|');
      final loc = Location(double.parse(p[2]), double.parse(p[3]), p[1] == 'IL', p[4],
          cityName: p[0], countryCode: p[1], elevation: double.tryParse(p[5]) ?? 0);
      addLocation(p[0], loc);
    }
  }

  /// Looks up one of the ~60 built-in "classic" cities (case-insensitive).
  static Location? lookup(String name) {
    if (_classicCities.isEmpty) _initClassicCities();
    return _classicCities[name.toLowerCase()];
  }

  /// All built-in classic cities.
  static List<Location> classicCities() {
    if (_classicCities.isEmpty) _initClassicCities();
    return _classicCities.values.toList();
  }

  static bool addLocation(String cityName, Location location) {
    final name = cityName.toLowerCase();
    if (_classicCities.containsKey(name)) return false;
    _classicCities[name] = location;
    return true;
  }

  static String? legacyTzToTzid(int tz, String dst) {
    if (dst == 'none') {
      if (tz == 0) return 'UTC';
      final plus = tz > 0 ? '+' : '';
      return 'Etc/GMT$plus$tz';
    }
    if (tz == 2 && dst == 'israel') return 'Asia/Jerusalem';
    if (dst == 'eu') {
      switch (tz) {
        case -2:
          return 'Atlantic/Cape_Verde';
        case -1:
          return 'Atlantic/Azores';
        case 0:
          return 'Europe/London';
        case 1:
          return 'Europe/Paris';
        case 2:
          return 'Europe/Athens';
      }
    }
    if (dst == 'usa') return _zipcodesTzMap['${tz * -1}'];
    return null;
  }

  static String? getUsaTzid(String state, int tz, String dst) {
    if (tz == 10 && state == 'AK') return 'America/Adak';
    if (tz == 7 && state == 'AZ') {
      return dst == 'Y' ? 'America/Denver' : 'America/Phoenix';
    }
    return _zipcodesTzMap['$tz'];
  }

  Map<String, Object?> toJson() => {
        'name': locationName,
        'latitude': latitude,
        'longitude': longitude,
        'elevation': elevation,
        'tzid': timeZoneId,
        'il': il,
        'cc': cc,
        'geoid': geoid,
      };

  static Location fromJson(Map<String, Object?> j) => Location(
        (j['latitude'] as num).toDouble(),
        (j['longitude'] as num).toDouble(),
        j['il'] as bool? ?? false,
        j['tzid'] as String,
        cityName: j['name'] as String?,
        countryCode: j['cc'] as String?,
        geoid: j['geoid'],
        elevation: (j['elevation'] as num?)?.toDouble() ?? 0,
      );

  @override
  String toString() => 'Location(${toJson()})';
}
