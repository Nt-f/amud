import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:geolocator/geolocator.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/settings.dart';

bool significantTravel(
  SavedLocation saved,
  double lat,
  double lon,
  String tzid,
) =>
    saved.tzid != tzid ||
    Geolocator.distanceBetween(saved.latitude, saved.longitude, lat, lon) >=
        50000;

/// Only checks an existing grant. Traveling never starts a permission dialog.
Future<SavedLocation?> travelSuggestion(SavedLocation saved) async {
  final permission = await Geolocator.checkPermission();
  if (permission != LocationPermission.always &&
      permission != LocationPermission.whileInUse) {
    return null;
  }
  if (!await Geolocator.isLocationServiceEnabled()) return null;
  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.medium,
      timeLimit: Duration(seconds: 15),
    ),
  );
  final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
  tz.getLocation(zone); // Reject unknown device zones rather than use UTC.
  if (!significantTravel(saved, position.latitude, position.longitude, zone)) {
    return null;
  }
  return SavedLocation(
    name: 'Current location',
    latitude: position.latitude,
    longitude: position.longitude,
    elevation: position.altitude.clamp(0, 9000).toDouble(),
    tzid: zone,
    il: saved.il,
    countryCode: null,
  );
}
