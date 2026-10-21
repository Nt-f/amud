import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hebcal/hebcal.dart' show gematriya;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/analytics.dart';
import '../../core/l10n.dart';
import '../integrations/reader_device.dart' show videoFullscreen, videoPlaying;
import 'daf_video_codec_stub.dart' if (dart.library.js_interop) 'daf_video_codec_web.dart' as web;
import 'gemara_data.dart';
import 'study_book.dart';

/// Where the video shiurim stream from: HLS in the amud-video R2 bucket,
/// published with tool/publish_daf_video.sh. A build can point elsewhere with
/// `--dart-define=DAF_VIDEO_BASE=https://…`, or turn videos off with an
/// empty value.
const dafVideoBase = String.fromEnvironment('DAF_VIDEO_BASE', defaultValue: 'https://video.amud.page/daf');

/// The two encodings of each daf: 1080p HEVC where the device decodes HEVC
/// in hardware, and a 720p H.264 stream for every other device.
enum DafStream {
  hevc('hevc', '1080p HEVC'),
  avc('avc', '720p');

  /// The folder of this encoding's playlist.
  final String path;
  final String label;
  const DafStream(this.path, this.label);
}

/// A book's folder in the bucket: its Sefaria name, lower case with dashes
/// ("bava-metzia", "kitzur-shulchan-arukh").
String dafVideoFolder(String tractate) => tractate.toLowerCase().replaceAll(' ', '-');

/// A Kitzur Yomi day's video goes by where the day's portion starts: siman
/// 2, se'if 4 is "2-4". (A daf's goes by the daf, "59".)
String kitzurVideoUnit(int siman, int seif) => '$siman-$seif';

final _kitzurUnit = RegExp(r'^(\d+)-(\d+)$');

String _trimmed(String base) => base.replaceFirst(RegExp(r'/+$'), '');

/// A video's playlist in [stream]: `{base}/{book}/{unit}/{hevc|avc}/index.m3u8`,
/// the book as Sefaria names it (see [dafVideoFolder]) and the unit a daf
/// or a Kitzur Yomi day (see [kitzurVideoUnit]). Null when [dafVideoBase]
/// is empty.
Uri? studyVideoUri(String book, String unit, [DafStream stream = DafStream.avc, String base = dafVideoBase]) => base.isEmpty
    ? null
    : Uri.parse('${_trimmed(base)}/${Uri.encodeComponent(dafVideoFolder(book))}/$unit/${stream.path}/index.m3u8');

/// A daf's playlist (see [studyVideoUri]).
Uri? dafVideoUri(String tractate, int daf, [DafStream stream = DafStream.avc, String base = dafVideoBase]) =>
    studyVideoUri(tractate, '$daf', stream, base);

/// The videos in an `index.json` (`{"bekhorot": [30], "kitzur-shulchan-arukh":
/// ["2-4"], …}`, by [dafVideoFolder]): dafim as numbers, Kitzur Yomi days as
/// "siman-se'if". Anything else is skipped.
Map<String, Set<String>> parseDafVideoIndex(String json) {
  final data = jsonDecode(json);
  if (data is! Map) return const {};
  return {
    for (final MapEntry(:key, :value) in data.entries)
      if (key is String && value is List)
        key: {
          for (final unit in value)
            if (unit is int) '$unit' else if (unit is String && _kitzurUnit.hasMatch(unit)) unit,
        },
  };
}

/// Which dafim and Kitzur Yomi days have a video shiur, from
/// `{base}/index.json`, which tool/publish_daf_video.sh adds each to. Empty
/// until [load] reads it.
class DafVideoIndex extends ValueNotifier<Map<String, Set<String>>> {
  final String base;
  final http.Client? _client;
  Future<void>? _loading;
  DafVideoIndex({this.base = dafVideoBase, http.Client? client})
      : _client = client,
        super(const {});

  bool has(String tractate, int daf) => hasUnit(tractate, '$daf');

  bool hasUnit(String book, String unit) => value[dafVideoFolder(book)]?.contains(unit) ?? false;

  /// The first Kitzur Yomi day with a video that starts in [siman], or null.
  String? kitzurIn(int siman) {
    final seifim = [
      for (final unit in value[dafVideoFolder(kitzurId)] ?? const <String>{})
        if (_kitzurUnit.firstMatch(unit) case final m? when int.parse(m[1]!) == siman) int.parse(m[2]!),
    ]..sort();
    return seifim.isEmpty ? null : kitzurVideoUnit(siman, seifim.first);
  }

  /// Reads the list once a run; after a failure the next call tries again.
  Future<void> load() => _loading ??= _fetch();

  Future<void> _fetch() async {
    if (base.isEmpty) return;
    final client = _client ?? http.Client();
    try {
      final r = await client.get(Uri.parse('${_trimmed(base)}/index.json')).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw http.ClientException('HTTP ${r.statusCode}');
      value = parseDafVideoIndex(r.body);
    } catch (e) {
      debugPrint('Daf video index: $e');
      _loading = null;
    } finally {
      if (_client == null) client.close();
    }
  }
}

/// The app's [DafVideoIndex].
final dafVideoIndex = DafVideoIndex();

/// Whether this device plays the HEVC stream: a hardware HEVC decoder on
/// Android and iOS, HEVC in the browser on the web; elsewhere the 720p one.
Future<bool> canPlayHevc() async {
  if (kIsWeb) return web.webPlaysHevc();
  if (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS) return false;
  try {
    return await const MethodChannel('amud/integrations').invokeMethod<bool>('hevcDecoder') ?? false;
  } catch (_) {
    return false;
  }
}

/// Where the video plays in the app: on Linux and Windows through fvp
/// (packages/fvp), and on the web where the browser plays HLS itself or
/// through hls.js (see web/hlsjs).
bool get playsInApp => kIsWeb
    ? web.webPlaysHls()
    : const {TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.macOS, TargetPlatform.linux, TargetPlatform.windows}
        .contains(defaultTargetPlatform);

/// The app's link to a video shiur (see [DafVideoScreen]): a daf ("59") or
/// a Kitzur Yomi day ("2-4").
String dafVideoPath(String tractate, String unit) => Uri(path: '/daf-video', queryParameters: {'t': tractate, 'd': unit}).toString();

/// Plays a daf's video shiur, or a Kitzur Yomi day's, choosing its stream
/// (see [DafStream]).
class DafVideoScreen extends StatefulWidget {
  /// The tractate (or the Kitzur) as Sefaria names it.
  final String tractate;

  /// The daf, or the Kitzur Yomi day (see [kitzurVideoUnit]).
  final String unit;

  /// Where the streams are (see [dafVideoBase]).
  final String base;
  const DafVideoScreen({super.key, required this.tractate, required this.unit, this.base = dafVideoBase});

  @override
  State<DafVideoScreen> createState() => _DafVideoScreenState();
}

class _DafVideoScreenState extends State<DafVideoScreen> {
  VideoPlayerController? _video;
  DafStream? _stream;
  bool _failed = false;
  bool _controls = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    if (playsInApp) _open();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _video?.removeListener(_changed);
    _video?.dispose();
    videoPlaying.value = false;
    videoFullscreen.value = false;
    super.dispose();
  }

  /// The HEVC stream where it plays, falling back to 720p if it won't start.
  Future<void> _open() async {
    try {
      await web.loadHlsJs();
    } catch (e) {
      debugPrint('Daf video: $e');
      if (mounted) setState(() => _failed = true);
      return;
    }
    final order = [if (await canPlayHevc()) DafStream.hevc, DafStream.avc];
    for (final stream in order) {
      final uri = studyVideoUri(widget.tractate, widget.unit, stream, widget.base);
      if (uri == null || !mounted) return;
      final video = VideoPlayerController.networkUrl(uri, formatHint: VideoFormat.hls);
      try {
        await video.initialize();
      } catch (e) {
        debugPrint('Daf video: ${stream.label} failed: $e');
        await video.dispose();
        continue;
      }
      if (!mounted) {
        await video.dispose();
        return;
      }
      video.addListener(_changed);
      setState(() {
        _video = video;
        _stream = stream;
      });
      analytics.event('daf_video', {
        'tractate': widget.tractate,
        if (int.tryParse(widget.unit) case final daf?) 'daf': daf else 'unit': widget.unit,
        'stream': stream.path,
      });
      await video.play();
      _later();
      return;
    }
    if (mounted) setState(() => _failed = true);
  }

  void _changed() {
    // Keeps the screen on while playing.
    videoPlaying.value = _video?.value.isPlaying ?? false;
    if (mounted) setState(() {});
  }

  /// Hides the controls a few seconds after the last touch, while playing.
  void _later() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && (_video?.value.isPlaying ?? false)) setState(() => _controls = false);
    });
  }

  void _touch() {
    setState(() => _controls = !_controls);
    if (_controls) _later();
  }

  void _seek(int seconds) {
    final v = _video;
    if (v == null) return;
    final to = v.value.position + Duration(seconds: seconds);
    v.seekTo(to < Duration.zero ? Duration.zero : (to > v.value.duration ? v.value.duration : to));
    _later();
  }

  static String _time(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  /// A phone in landscape: the video fills the screen with the system bars
  /// hidden, and the app bar shows over it with the other controls.
  bool _fullscreen(BuildContext context) =>
      _video != null && MediaQuery.orientationOf(context) == Orientation.landscape && MediaQuery.sizeOf(context).shortestSide < 600;

  @override
  Widget build(BuildContext context) {
    final video = _video;
    final full = _fullscreen(context);
    if (videoFullscreen.value != full) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) videoFullscreen.value = _fullscreen(context);
      });
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: full ? null : _bar(context),
      body: SafeArea(
        child: Center(
          child: switch (video) {
            _ when !playsInApp => _elsewhere(context),
            _ when _failed => _message(context, context.tr("This shiur couldn't be loaded. Check your connection and try again."),
                action: FilledButton(
                    onPressed: () {
                      setState(() => _failed = false);
                      _open();
                    },
                    child: Text(context.tr('Retry')))),
            null => const CircularProgressIndicator(color: Colors.white),
            final v => _player(context, v, full),
          },
        ),
      ),
    );
  }

  AppBar _bar(BuildContext context, {bool over = false}) => AppBar(
        backgroundColor: over ? Colors.transparent : Colors.black,
        foregroundColor: Colors.white,
        // Over the video the app bar leaves the system bars to the screen.
        primary: !over,
        title: Text(_title(context)),
        actions: [
          if (_video case final video?)
            PopupMenuButton<double>(
              tooltip: context.tr('Playback speed'),
              icon: const Icon(Icons.speed),
              initialValue: video.value.playbackSpeed,
              onSelected: (r) {
                video.setPlaybackSpeed(r);
                _later();
              },
              itemBuilder: (_) => [
                for (final r in const [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]) PopupMenuItem(value: r, child: Text('$r×')),
              ],
            ),
        ],
      );

  /// The video with its controls. In [full] screen they spread to the
  /// screen's edges, and the app bar shows with them at the top.
  Widget _player(BuildContext context, VideoPlayerController v, bool full) {
    // In full screen the stack spreads to the screen; otherwise it's the
    // video's size, and its other children center on it.
    Widget center(Widget child) => full ? Center(child: child) : child;
    // Keeps the bars readable over a bright picture.
    Widget shade(Alignment from, Widget child) => DecoratedBox(
        decoration: BoxDecoration(
            gradient: LinearGradient(begin: from, end: -from, colors: const [Colors.black54, Colors.transparent])),
        child: child);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _touch,
      child: Stack(alignment: Alignment.center, fit: full ? StackFit.expand : StackFit.loose, children: [
        // On the web the video is an HTML element that would take
        // the taps meant for the controls.
        center(AspectRatio(aspectRatio: v.value.aspectRatio, child: IgnorePointer(child: VideoPlayer(v)))),
        if (v.value.isBuffering) center(const CircularProgressIndicator(color: Colors.white)),
        if (_controls) ...[
          if (full) Positioned(left: 0, right: 0, top: 0, child: shade(Alignment.topCenter, _bar(context, over: true))),
          center(
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  tooltip: context.tr('Back 10 seconds'),
                  iconSize: 36,
                  color: Colors.white,
                  icon: const Icon(Icons.replay_10),
                  onPressed: () => _seek(-10)),
              const SizedBox(width: 24),
              IconButton.filled(
                tooltip: context.tr(v.value.isPlaying ? 'Pause' : 'Play'),
                iconSize: 48,
                icon: Icon(v.value.isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: () {
                  v.value.isPlaying ? v.pause() : v.play();
                  _later();
                },
              ),
              const SizedBox(width: 24),
              IconButton(
                  tooltip: context.tr('Forward 10 seconds'),
                  iconSize: 36,
                  color: Colors.white,
                  icon: const Icon(Icons.forward_10),
                  onPressed: () => _seek(10)),
            ]),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: shade(
              Alignment.bottomCenter,
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  VideoProgressIndicator(v,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      colors: VideoProgressColors(
                          playedColor: Theme.of(context).colorScheme.primary,
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white12)),
                  DefaultTextStyle(
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    child: Row(children: [
                      Text('${_time(v.value.position)} / ${_time(v.value.duration)}'),
                      const Spacer(),
                      // Which stream plays, for checking the HEVC one is chosen.
                      if (_stream case final s?) Text(s.label),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  /// "Bava Metzia 59" / "בבא מציעא נט", "Kitzur Shulchan Aruch 2:4" /
  /// "קיצור שולחן ערוך ב:ד".
  String _title(BuildContext context) {
    final en = context.uiLanguage == UiLanguage.en;
    if (_kitzurUnit.firstMatch(widget.unit) case final m? when widget.tractate == kitzurId) {
      final name = studyBook(kitzurId)!.name(context);
      return en ? '$name ${m[1]}:${m[2]}' : '$name ${gematriya(int.parse(m[1]!))}:${gematriya(int.parse(m[2]!))}';
    }
    final daf = int.tryParse(widget.unit);
    if (en || daf == null) return '${context.term(widget.tractate)} ${widget.unit}';
    return '${tractateNamed(widget.tractate)?.he ?? widget.tractate} ${gematriya(daf)}';
  }

  /// Linux, Windows, and browsers without HLS: the stream opens outside.
  Widget _elsewhere(BuildContext context) {
    final uri = studyVideoUri(widget.tractate, widget.unit, DafStream.avc, widget.base);
    return _message(context, context.tr("Video can't play here yet. Open it in another player."),
        action: uri == null
            ? null
            : FilledButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: Text(context.tr('Open the video')),
                onPressed: () => launchUrl(uri, mode: LaunchMode.externalApplication)));
  }

  Widget _message(BuildContext context, String text, {Widget? action}) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
          if (action != null) ...[const SizedBox(height: 16), action],
        ]),
      );
}
