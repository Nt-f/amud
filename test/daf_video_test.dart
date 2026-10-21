import 'dart:async';

import 'package:amud/features/gemara/daf_video.dart';
import 'package:amud/features/gemara/gemara_home_screen.dart' show dafOfAmud;
import 'package:amud/features/gemara/study_book.dart' show kitzurId;
import 'package:amud/features/integrations/reader_device.dart' show videoFullscreen, videoPlaying;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Plays any stream but those in [broken], which fail to load.
class _FakeVideos extends VideoPlayerPlatform {
  final Set<String> broken;
  _FakeVideos({this.broken = const {}});

  final opened = <String>[];
  final _events = <int, StreamController<VideoEvent>>{};

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    opened.add(options.dataSource.uri!);
    final id = opened.length;
    final events = _events[id] = StreamController<VideoEvent>();
    scheduleMicrotask(() {
      if (broken.any(options.dataSource.uri!.contains)) {
        events.addError(PlatformException(code: 'VideoError', message: 'cannot decode'));
      } else {
        events.add(VideoEvent(eventType: VideoEventType.initialized, duration: const Duration(minutes: 40), size: const Size(1920, 1080)));
      }
    });
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    unawaited(_events.remove(playerId)?.close());
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox.expand();
}

void main() {
  const base = 'https://video.example.com';

  /// The device's answer to "does a hardware decoder play HEVC?".
  void hevcDecoder(bool has) => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('amud/integrations'), (call) async => call.method == 'hevcDecoder' ? has : null);

  Future<_FakeVideos> play(WidgetTester tester,
      {required bool hevc, Set<String> broken = const {}, String tractate = 'Bava Metzia', String unit = '59'}) async {
    final videos = _FakeVideos(broken: broken);
    VideoPlayerPlatform.instance = videos;
    hevcDecoder(hevc);
    await tester.pumpWidget(MaterialApp(home: DafVideoScreen(tractate: tractate, unit: unit, base: base)));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    return videos;
  }

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('amud/integrations'), null));

  testWidgets('a device that decodes HEVC plays the 1080p HEVC stream', (tester) async {
    final videos = await play(tester, hevc: true);
    expect(videos.opened, ['$base/bava-metzia/59/hevc/index.m3u8']);
    expect(find.text('1080p HEVC'), findsOneWidget);
    expect(find.text('Bava Metzia 59'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('one without HEVC plays the 720p stream', (tester) async {
    final videos = await play(tester, hevc: false);
    expect(videos.opened, ['$base/bava-metzia/59/avc/index.m3u8']);
    expect(find.text('720p'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('if the HEVC stream will not start, the 720p one plays instead', (tester) async {
    final videos = await play(tester, hevc: true, broken: {'/hevc/'});
    expect(videos.opened, ['$base/bava-metzia/59/hevc/index.m3u8', '$base/bava-metzia/59/avc/index.m3u8']);
    expect(find.text('720p'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a Kitzur Yomi day's video plays the same way, titled by where it starts", (tester) async {
    final videos = await play(tester, hevc: true, tractate: kitzurId, unit: '2-4');
    expect(videos.opened, ['$base/kitzur-shulchan-arukh/2-4/hevc/index.m3u8']);
    expect(find.text('Kitzur Shulchan Aruch 2:4'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('when neither plays, it says so and can retry', (tester) async {
    final videos = await play(tester, hevc: true, broken: {'/hevc/', '/avc/'});
    expect(videos.opened, hasLength(2));
    expect(find.textContaining("couldn't be loaded"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('while it plays the screen stays on, and not after', (tester) async {
    await play(tester, hevc: false);
    expect(videoPlaying.value, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(videoPlaying.value, isFalse);
  });

  group('on a phone', () {
    void screen(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('in landscape the video fills the screen, the app bar over it', (tester) async {
      screen(tester, const Size(800, 360));
      await play(tester, hevc: false);
      await tester.pump();
      expect(videoFullscreen.value, isTrue);
      expect(tester.getSize(find.byType(AspectRatio)).height, 360);
      expect(find.text('Bava Metzia 59'), findsOneWidget);
      expect(tester.getRect(find.byType(AppBar)).top, 0);
      await tester.pumpWidget(const SizedBox());
      expect(videoFullscreen.value, isFalse);
    });

    testWidgets('in portrait it sits under the app bar, the screen wide', (tester) async {
      screen(tester, const Size(360, 800));
      await play(tester, hevc: false);
      await tester.pump();
      expect(videoFullscreen.value, isFalse);
      final video = tester.getRect(find.byType(AspectRatio));
      expect(video.width, 360);
      expect(video.top, greaterThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom));
      await tester.pumpWidget(const SizedBox());
    });
  });

  test("a daf's video goes by the daf of either amud", () {
    expect([dafOfAmud('2a'), dafOfAmud('50b'), dafOfAmud('176b')], [2, 50, 176]);
    // A Mishnah perek or a Kitzur siman isn't a daf.
    expect([dafOfAmud('3'), dafOfAmud('a'), dafOfAmud('')], [null, null, null]);
  });

  group('the index of published videos', () {
    test("reads book folders, dafim and Kitzur Yomi days, skipping anything malformed", () {
      expect(parseDafVideoIndex('{"bekhorot":[30,31],"bava-metzia":[59],"kitzur-shulchan-arukh":["2-4","10-1"]}'), {
        'bekhorot': {'30', '31'},
        'bava-metzia': {'59'},
        'kitzur-shulchan-arukh': {'2-4', '10-1'},
      });
      expect(parseDafVideoIndex('{"bekhorot":[30,"31",null],"nazir":"14","kitzur-shulchan-arukh":["2:4","2-",3]}'), {
        'bekhorot': {'30'},
        'kitzur-shulchan-arukh': {'3'},
      });
      expect(parseDafVideoIndex('[30]'), isEmpty);
    });

    test("finds a Kitzur Yomi day's video, and the first one in a siman", () async {
      final index = DafVideoIndex(
          base: base, client: MockClient((r) async => http.Response('{"kitzur-shulchan-arukh":["12-7","2-4","12-3","120-1"]}', 200)));
      await index.load();
      expect(index.hasUnit(kitzurId, '2-4'), isTrue);
      expect(index.hasUnit(kitzurId, '2-5'), isFalse);
      expect(index.kitzurIn(12), '12-3');
      expect(index.kitzurIn(2), '2-4');
      expect(index.kitzurIn(1), isNull);
      expect(index.kitzurIn(20), isNull);
    });

    test('lights up only the dafim it lists', () async {
      final asked = <Uri>[];
      final index = DafVideoIndex(
          base: '$base/',
          client: MockClient((r) async {
            asked.add(r.url);
            return http.Response('{"bekhorot":[30],"bava-metzia":[59]}', 200);
          }));
      expect(index.has('Bekhorot', 30), isFalse);
      await index.load();
      await index.load();
      expect(asked, [Uri.parse('$base/index.json')]);
      expect(index.has('Bekhorot', 30), isTrue);
      expect(index.has('Bava Metzia', 59), isTrue);
      expect(index.has('Bekhorot', 31), isFalse);
      expect(index.has('Nazir', 14), isFalse);
    });

    test('after a failed read it stays empty and tries again', () async {
      var calls = 0;
      final index = DafVideoIndex(
          base: base,
          client: MockClient((r) async => ++calls == 1 ? http.Response('down', 503) : http.Response('{"bekhorot":[30]}', 200)));
      await index.load();
      expect(index.has('Bekhorot', 30), isFalse);
      await index.load();
      expect(calls, 2);
      expect(index.has('Bekhorot', 30), isTrue);
    });

    test('with videos turned off it reads nothing', () async {
      var calls = 0;
      final index = DafVideoIndex(
          base: '',
          client: MockClient((r) async {
            calls++;
            return http.Response('{}', 200);
          }));
      await index.load();
      expect(calls, 0);
      expect(dafVideoUri('Bekhorot', 30, DafStream.avc, ''), isNull);
    });
  });
}
