import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

const _hls = 'application/vnd.apple.mpegurl';

bool _plays(String type) => web.HTMLVideoElement().canPlayType(type).isNotEmpty;

/// Whether Media Source Extensions take [type], which hls.js needs.
bool _mse(String type) => globalContext.has('MediaSource') && web.MediaSource.isTypeSupported(type);

/// Whether the HLS playlist plays natively (Safari, Chrome on Android) and
/// not through hls.js.
bool get _native => _plays(_hls);

/// Whether the browser decodes 1080p HEVC (Main profile, level 4.0).
bool webPlaysHevc() {
  const hevc = 'video/mp4; codecs="hvc1.1.6.L120.90"';
  return _native ? _plays(hevc) : _mse(hevc);
}

/// Whether the browser plays the HLS streams, itself or through hls.js
/// (Firefox, desktop Chrome).
bool webPlaysHls() => _native || _mse('video/mp4; codecs="avc1.4d401f,mp4a.40.2"');

Future<void>? _hlsJs;

/// Where the browser has no HLS of its own, loads hls.js and
/// web/hlsjs/hls_src.js, which plays a video whose src is a playlist
/// through it. Once a run, the first time a video opens.
Future<void> loadHlsJs() {
  if (_native) return Future.value();
  return _hlsJs ??= () async {
    try {
      await _script('hlsjs/hls.light.min.js');
      await _script('hlsjs/hls_src.js');
    } catch (_) {
      _hlsJs = null;
      rethrow;
    }
  }();
}

Future<void> _script(String src) {
  final done = Completer<void>();
  final script = web.HTMLScriptElement()..src = src;
  script.onload = ((web.Event _) => done.complete()).toJS;
  script.onerror = ((web.Event _) => done.completeError(StateError("Couldn't load $src"))).toJS;
  web.document.head!.append(script);
  return done.future;
}
