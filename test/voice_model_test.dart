import 'dart:async';

import 'package:amud/features/voice/voice_model.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A download kept in memory.
class _MemoryPart implements VoicePart {
  final bytes = <int>[];
  int resets = 0;
  _MemoryPart([List<int> start = const []]) {
    bytes.addAll(start);
  }

  @override
  Future<int> length() async => bytes.length;
  @override
  Stream<List<int>> read() => Stream.value([...bytes]);
  @override
  Future<void> append(List<int> b) async => bytes.addAll(b);
  @override
  Future<void> reset() async {
    resets++;
    bytes.clear();
  }
}

void main() {
  final file = (
    name: 'fixture.onnx',
    size: 3,
    hash: sha256.convert([1, 2, 3]).toString(),
  );

  test('verified model bytes are delivered with download progress', () async {
    final client = MockClient((request) async {
      expect(request.url.path, contains(voiceModelRevision));
      expect(request.headers['Range'], isNull);
      return http.Response.bytes([1, 2, 3], 200);
    });
    addTearDown(client.close);
    final part = _MemoryPart();
    final progress = <int>[];
    await downloadVoiceFile(client, file, part, progress.add);
    expect(part.bytes, [1, 2, 3]);
    expect(progress.last, 3);
  });

  test(
    'corrupt, incomplete and oversized model downloads are rejected',
    () async {
      for (final bytes in [
        [4, 5, 6],
        [1, 2],
        [1, 2, 3, 4],
      ]) {
        final client = MockClient((_) async => http.Response.bytes(bytes, 200));
        addTearDown(client.close);
        final part = _MemoryPart();
        await expectLater(
          downloadVoiceFile(client, file, part, (_) {}),
          throwsStateError,
        );
        // Nothing bad is kept for the next try.
        expect(part.bytes, isEmpty);
      }
    },
  );

  test('HTTP errors cannot mark a model download successful', () async {
    final client = MockClient((_) async => http.Response('unavailable', 503));
    addTearDown(client.close);
    await expectLater(
      downloadVoiceFile(client, file, _MemoryPart(), (_) {}),
      throwsStateError,
    );
  });

  test('a download cut off midway continues where it stopped', () async {
    final part = _MemoryPart();
    // The connection drops after the first byte.
    final dropping = MockClient.streaming((request, _) async {
      final stream = StreamController<List<int>>();
      stream.add([1]);
      stream.addError(http.ClientException('Connection closed'));
      unawaited(stream.close());
      return http.StreamedResponse(stream.stream, 200);
    });
    addTearDown(dropping.close);
    await expectLater(downloadVoiceFile(dropping, file, part, (_) {}), throwsA(isA<http.ClientException>()));
    expect(part.bytes, [1]);

    // The next try asks only for the rest.
    final ranges = <String?>[];
    final resuming = MockClient((request) async {
      ranges.add(request.headers['Range']);
      return http.Response.bytes([2, 3], 206);
    });
    addTearDown(resuming.close);
    final progress = <int>[];
    await downloadVoiceFile(resuming, file, part, progress.add);
    expect(ranges, ['bytes=1-']);
    expect(part.bytes, [1, 2, 3]);
    // Progress counts what was already in.
    expect(progress, [1, 3]);
  });

  test('a server that ignores the range sends the whole file again', () async {
    final part = _MemoryPart([1]);
    final client = MockClient((_) async => http.Response.bytes([1, 2, 3], 200));
    addTearDown(client.close);
    await downloadVoiceFile(client, file, part, (_) {});
    expect(part.bytes, [1, 2, 3]);
    expect(part.resets, 1);
  });

  test('a bad partial file is thrown away, so the next try starts over', () async {
    final part = _MemoryPart([9]);
    final client = MockClient((_) async => http.Response.bytes([2, 3], 206));
    addTearDown(client.close);
    await expectLater(downloadVoiceFile(client, file, part, (_) {}), throwsStateError);
    expect(part.bytes, isEmpty);
  });

  test('a file that was all in already is checked without downloading', () async {
    var asked = 0;
    final client = MockClient((_) async {
      asked++;
      return http.Response('', 416);
    });
    addTearDown(client.close);
    final part = _MemoryPart([1, 2, 3]);
    await downloadVoiceFile(client, file, part, (_) {});
    expect(asked, 0);
    expect(part.bytes, [1, 2, 3]);
  });
}
