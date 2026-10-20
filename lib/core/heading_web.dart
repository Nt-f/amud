import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

import 'heading.dart';

/// The browser's absolute orientation (Chrome on Android). Desktop browsers
/// never fire it, so the stream stays silent there.
Stream<DeviceHeading> webHeadings() {
  late StreamController<DeviceHeading> out;
  final listener = ((web.DeviceOrientationEvent e) {
    final a = e.alpha, b = e.beta, g = e.gamma;
    if (a == null || b == null || g == null) return;
    // The W3C rotation matrix (Z-X'-Y''); its columns are the phone's
    // axes in east/north/up. Ahead is screen-up less screen-normal.
    final ra = a * pi / 180, rb = b * pi / 180, rg = g * pi / 180;
    final cA = cos(ra), sA = sin(ra), cB = cos(rb), sB = sin(rb), cG = cos(rg), sG = sin(rg);
    final east = -cB * sA - (cG * sA * sB + cA * sG);
    final north = cA * cB - (sA * sG - cA * cG * sB);
    if (east * east + north * north < 1e-4) return;
    out.add((degrees: (atan2(east, north) * 180 / pi + 360) % 360, calibrate: false));
  }).toJS;
  out = StreamController<DeviceHeading>(
    onListen: () => web.window.addEventListener('deviceorientationabsolute', listener),
    onCancel: () => web.window.removeEventListener('deviceorientationabsolute', listener),
  );
  return out.stream;
}
