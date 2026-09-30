import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
import 'settings.dart';
import 'storage.dart';

/// Anonymous usage analytics, all in one Google Analytics 4 property:
/// Firebase Analytics on Android, iOS, macOS and the web, and the GA4
/// Measurement Protocol on Windows and Linux (which Firebase doesn't
/// support). Off in debug builds and tests unless built with
/// `--dart-define=ANALYTICS_DEBUG=true`, and off entirely until
/// `flutterfire configure` has written real [DefaultFirebaseOptions].
/// Firebase's native collection is off by default (AndroidManifest.xml,
/// Info.plist) and only turned on by [Analytics.init] if the user allows it.
///
/// Nothing ties the data to a person or links one run to the next: no user
/// id or user properties, no advertising id or signals, and a fresh
/// anonymous id each time the app starts (a session cookie on the web; see
/// web/index.html). Each event carries what it's about instead.
///
/// Active users are counted without an id: each install sends
/// `active_day` once a day and `active_month` once a calendar month (see
/// [checkIn]), so the number of those events in a period is the number of
/// daily or monthly active installs. Only the date of the last check-in is
/// kept on the device.
///
/// Everything goes through the global [analytics], so any widget or
/// notifier can log without a provider. Calls before [Analytics.init] are
/// queued, and calls while the user has turned sharing off are dropped.
final analytics = Analytics._();

/// GA4 limits: event and parameter names up to 40 characters, parameter
/// values up to 100.
const _maxValue = 100;

abstract class _Backend {
  Future<void> event(String name, Map<String, Object> params);
  Future<void> screen(String name, Map<String, Object> params);
  Future<void> enable(bool on);
}

class Analytics {
  Analytics._();

  _Backend? _backend;
  bool _enabled = true;
  bool _started = false;

  /// [init] has finished, with or without a backend.
  bool _settled = false;

  /// Calls made before [init] finished, replayed once it has.
  final _early = <Future<void> Function(_Backend)>[];
  final _pendingSettings = <String, Timer>{};
  int _errors = 0;

  /// Whether events are being sent (configured, and allowed by the user).
  bool get active => _backend != null && _enabled;

  static const _debug = bool.fromEnvironment('ANALYTICS_DEBUG');

  /// Starts the backend for this platform. Never throws and never blocks
  /// startup for long: offline on the web, the Firebase scripts can't load,
  /// so it gives up after a few seconds and stays quiet.
  Future<void> init(AppSettings settings, Storage storage) async {
    _storage = storage;
    if (_started) return;
    _started = true;
    _enabled = settings.shareUsage;
    if (kDebugMode && !_debug) return _drop();
    // With sharing off nothing is started (on the web, starting Firebase
    // alone sends a page view); [setEnabled] starts it if it's turned on.
    if (!_enabled) return _drop();
    await _start();
  }

  bool _starting = false;

  /// Creates and enables the backend, then sends what was queued meanwhile.
  Future<void> _start() async {
    if (_starting || _backend != null) return;
    _starting = true;
    _settled = false;
    try {
      final platform = kIsWeb ? null : defaultTargetPlatform;
      final desktop = platform == TargetPlatform.windows || platform == TargetPlatform.linux;
      _backend = desktop ? _measurementProtocol() : await _firebase();
      final backend = _backend;
      if (backend != null) {
        await backend.enable(_enabled);
        // Calls made before the setting was known are only sent if allowed.
        final early = [..._early];
        _early.clear();
        if (_enabled) {
          for (final call in early) {
            await call(backend);
          }
        }
      }
    } catch (e) {
      debugPrint('Analytics off: $e');
    } finally {
      _starting = false;
    }
    if (_backend == null) return _drop();
    _early.clear();
    _settled = true;
    checkIn();
  }

  Storage? _storage;

  /// Sends the day's and the month's check-in if this install hasn't yet
  /// (at startup and when the app comes back to the foreground). Nothing
  /// is recorded while sharing is off, so turning it back on counts.
  void checkIn() {
    final storage = _storage;
    if (storage == null || !active) return;
    const key = 'analyticsCheckIn';
    final last = storage.readJson(key, (j) => (j as Map).cast<String, Object?>()) ?? const {};
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final month = '${now.year}-${two(now.month)}';
    final day = '$month-${two(now.day)}';
    if (last['day'] == day) return;
    if (last['month'] != month) event('active_month', {'month': month});
    event('active_day', {'day': day, 'new_install': last.isEmpty});
    storage.writeJson(key, {'day': day, 'month': month});
  }

  void _drop() {
    _early.clear();
    _backend = null;
    _settled = true;
  }

  static Future<_Backend> _firebase() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform).timeout(const Duration(seconds: 8));
    final fa = FirebaseAnalytics.instance;
    await fa.setConsent(
      analyticsStorageConsentGranted: true,
      adStorageConsentGranted: false,
      adUserDataConsentGranted: false,
      adPersonalizationSignalsConsentGranted: false,
    );
    await fa.setUserId(id: null);
    // A new anonymous id for this run, so runs aren't linked. (The web
    // uses a session cookie instead.)
    if (!kIsWeb) await fa.resetAnalyticsData();
    return _FirebaseBackend(fa);
  }

  static _Backend? _measurementProtocol() {
    const secret = String.fromEnvironment('GA_API_SECRET');
    final id = DefaultFirebaseOptions.web.measurementId;
    if (secret.isEmpty || id == null || id.isEmpty) return null;
    return _MeasurementProtocolBackend(id, secret);
  }

  void _run(Future<void> Function(_Backend b) call) {
    if (!_enabled) return;
    final b = _backend;
    if (b != null) {
      call(b).catchError((Object e) => debugPrint('Analytics: $e'));
    } else if (!_settled && _early.length < 200) {
      _early.add(call);
    }
  }

  /// Turns sending on or off (the "Share anonymous usage" setting).
  void setEnabled(bool on) {
    if (on == _enabled) return;
    _enabled = on;
    if (!on) {
      _early.clear();
      for (final t in _pendingSettings.values) {
        t.cancel();
      }
      _pendingSettings.clear();
    }
    _backend?.enable(on).catchError((Object e) => debugPrint('Analytics: $e'));
    // Sharing was off at startup, so nothing was started yet.
    if (on && _started && _backend == null && !(kDebugMode && !_debug)) {
      unawaited(_start());
      return;
    }
    if (on) checkIn();
  }

  /// Logs [name] with [params]. Null values are left out, bools become
  /// "true"/"false" and long strings are cut to GA4's limit.
  void event(String name, [Map<String, Object?> params = const {}]) {
    final p = _clean(params);
    _run((b) => b.event(name, p));
  }

  /// A setting changed. Sliders change many times a second, so each
  /// setting is logged once it has stayed put for a moment.
  void settingChanged(String setting, Object? value) {
    if (!_enabled || kDebugMode && !_debug || _settled && _backend == null) return;
    _pendingSettings.remove(setting)?.cancel();
    _pendingSettings[setting] = Timer(const Duration(seconds: 2), () {
      _pendingSettings.remove(setting);
      event('setting_change', {'setting': setting, 'value': value});
    });
  }

  /// An uncaught error: only its type, since messages can hold paths,
  /// names or text. At most a few per run, so a loop of errors doesn't
  /// flood the property.
  void error(Object error, {bool fatal = false}) {
    if (_errors++ >= 5) return;
    event('app_error', {'type': error.runtimeType.toString(), 'fatal': fatal});
  }

  String? _lastScreen;

  /// Logs a screen view for each new location of [router]: the route
  /// pattern ("/siddur/book/:book/read") as the screen, with its path and
  /// query parameters.
  void trackScreens(GoRouter router) {
    void changed() {
      final m = router.routerDelegate.currentConfiguration;
      if (m.isEmpty) return;
      final key = m.uri.toString();
      if (key == _lastScreen) return;
      _lastScreen = key;
      final path = m.fullPath.isEmpty ? '/' : m.fullPath;
      _run((b) => b.screen(screenName(path), _clean({
            'route': path,
            ...m.pathParameters,
            for (final e in m.uri.queryParameters.entries) 'q_${e.key}': e.value,
          })));
    }

    router.routerDelegate.addListener(changed);
    changed();
  }

  /// A readable screen name for a route pattern.
  @visibleForTesting
  static String screenName(String path) {
    if (path == '/') return 'home';
    final parts = [
      for (final p in path.split('/'))
        if (p.isNotEmpty && !p.startsWith(':')) p.replaceAll('-', '_'),
    ];
    return parts.isEmpty ? 'home' : parts.join('_');
  }

  static Map<String, Object> _clean(Map<String, Object?> params) => {
        for (final e in params.entries)
          if (e.value != null)
            _cut(e.key.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_'), 40): switch (e.value) {
              final num n => n,
              final bool b => b ? 'true' : 'false',
              final v => _cut('$v', _maxValue),
            },
      };

  static String _cut(String s, int max) => s.length <= max ? s : s.substring(0, max);
}

class _FirebaseBackend implements _Backend {
  final FirebaseAnalytics fa;
  _FirebaseBackend(this.fa);

  @override
  Future<void> event(String name, Map<String, Object> params) => fa.logEvent(name: name, parameters: params);

  @override
  Future<void> screen(String name, Map<String, Object> params) =>
      fa.logScreenView(screenName: name, screenClass: name, parameters: params);

  @override
  Future<void> enable(bool on) => fa.setAnalyticsCollectionEnabled(on);
}

/// Sends events to GA4 over HTTP in batches (Windows and Linux). The
/// client id is random and new each run; a session is one run of the app,
/// or restarts after half an hour idle.
class _MeasurementProtocolBackend implements _Backend {
  final String _url;
  final String _clientId;
  final _queue = <Map<String, Object>>[];
  Timer? _timer;
  bool _sending = false;
  int _sessionId = _now() ~/ 1000;
  int _last = _now();
  bool _firstEvent = true;

  _MeasurementProtocolBackend(String measurementId, String secret)
      : _url = 'https://www.google-analytics.com/mp/collect?measurement_id=$measurementId&api_secret=$secret',
        _clientId = '${Random.secure().nextInt(1 << 31)}.${_now() ~/ 1000}';

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  @override
  Future<void> event(String name, Map<String, Object> params) async {
    final now = _now();
    if (now - _last > 30 * 60 * 1000) {
      _sessionId = now ~/ 1000;
      _firstEvent = true;
    }
    _queue.add({
      'name': name,
      'timestamp_micros': now * 1000,
      'params': {
        ...params,
        'platform': defaultTargetPlatform.name,
        'session_id': '$_sessionId',
        // Counts toward engaged time; capped so an idle gap isn't counted.
        'engagement_time_msec': _firstEvent ? 1 : min(now - _last, 60 * 1000),
      },
    });
    _firstEvent = false;
    _last = now;
    if (_queue.length > 500) _queue.removeRange(0, _queue.length - 500);
    _timer ??= Timer(const Duration(seconds: 10), _flush);
  }

  @override
  Future<void> screen(String name, Map<String, Object> params) =>
      event('screen_view', {...params, 'screen_name': name});

  @override
  Future<void> enable(bool on) async {
    if (!on) {
      _queue.clear();
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _flush() async {
    _timer = null;
    // A slow post is still going; it sends what's queued when it's done.
    if (_sending) return;
    _sending = true;
    try {
      await _send();
    } finally {
      _sending = false;
    }
  }

  Future<void> _send() async {
    while (_queue.isNotEmpty) {
      // At most 25 events per request.
      final batch = _queue.take(25).toList();
      try {
        final res = await http
            .post(Uri.parse(_url),
                body: jsonEncode({
                  'client_id': _clientId,
                  'events': batch,
                }))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode >= 300) throw 'HTTP ${res.statusCode}';
      } catch (_) {
        // Offline: try again later with what's queued.
        _timer ??= Timer(const Duration(minutes: 2), _flush);
        return;
      }
      // By identity: the queue may have been cleared or trimmed meanwhile.
      final sent = batch.toSet();
      _queue.removeWhere(sent.contains);
    }
  }
}
