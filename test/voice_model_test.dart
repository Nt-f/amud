import 'package:amud/features/voice/voice_model.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final file = (
    name: 'fixture.onnx',
    size: 3,
    hash: sha256.convert([1, 2, 3]).toString(),
  );

  test('verified model bytes are delivered with download progress', () async {
    final client = MockClient((request) async {
      expect(request.url.path, contains(voiceModelRevision));
      return http.Response.bytes([1, 2, 3], 200);
    });
    addTearDown(client.close);
    final bytes = <int>[];
    final progress = <int>[];
    await downloadVoiceFile(client, file, bytes.addAll, progress.add);
    expect(bytes, [1, 2, 3]);
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
        await expectLater(
          downloadVoiceFile(client, file, (_) {}, (_) {}),
          throwsStateError,
        );
      }
    },
  );

  test('HTTP errors cannot mark a model download successful', () async {
    final client = MockClient((_) async => http.Response('unavailable', 503));
    addTearDown(client.close);
    await expectLater(
      downloadVoiceFile(client, file, (_) {}, (_) {}),
      throwsStateError,
    );
  });
}
