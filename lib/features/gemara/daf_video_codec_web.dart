import 'package:web/web.dart' as web;

bool _plays(String type) => web.HTMLVideoElement().canPlayType(type).isNotEmpty;

/// Whether the browser decodes 1080p HEVC (Main profile, level 4.0).
bool webPlaysHevc() => _plays('video/mp4; codecs="hvc1.1.6.L120.90"');

/// Whether the browser plays an HLS playlist in a plain video element
/// (Safari, Chrome on Android), as video_player needs on the web.
bool webPlaysHls() => _plays('application/vnd.apple.mpegurl');
