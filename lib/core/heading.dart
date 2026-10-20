import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'heading_stub.dart' if (dart.library.js_interop) 'heading_web.dart' as web;

/// Which way the device faces, in degrees from north, clockwise: the top
/// of the screen when it lies flat, its back when held upright.
typedef DeviceHeading = ({double degrees, bool calibrate});

/// Phones and tablets, and the web on them; desktops have no compass.
bool get compassPossible =>
    defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

/// Readings from the device's compass. Errors or ends straight away where
/// there is none; on the web, and on desktops, it may simply never emit.
Stream<DeviceHeading> deviceHeadings({required double latitude, required double longitude, double elevation = 0}) {
  if (!compassPossible) return const Stream.empty();
  if (kIsWeb) return web.webHeadings();
  return const EventChannel('amud/heading')
      .receiveBroadcastStream({'lat': latitude, 'lon': longitude, 'alt': elevation})
      .map((e) {
        final m = (e as Map).cast<String, Object?>();
        return (degrees: (m['heading'] as num).toDouble(), calibrate: m['calibrate'] == true);
      });
}
