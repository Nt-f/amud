import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const voiceModelRevision = '8f3c18b358db4d1f2fc1eae49d75cd20989e4309';
const voiceModelFiles = <({String name, int size, String hash})>[
  (
    name: 'small-encoder.int8.onnx',
    size: 112442483,
    hash: '4cbe7b22fa9026b843b60a68640c747de05bafb1a11b57edc0e66c232d9f33a9',
  ),
  (
    name: 'small-decoder.int8.onnx',
    size: 262226114,
    hash: 'acad50b5c782696e91b55914cc5ab4f756f1532f76e22aa6fc615f39fb69a8ee',
  ),
  (
    name: 'small-tokens.txt',
    size: 816730,
    hash: 'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
  ),
];
final voiceModelBytes = voiceModelFiles.fold<int>(
  0,
  (sum, file) => sum + file.size,
);

/// What's kept of a model file while it downloads, so an interrupted
/// download picks up where it stopped instead of starting over.
abstract class VoicePart {
  /// Bytes kept so far.
  Future<int> length();

  /// The bytes kept so far, to check the whole file once it's in.
  Stream<List<int>> read();

  Future<void> append(List<int> bytes);

  /// Throws away what's kept, to start the file over.
  Future<void> reset();
}

/// Download only public model weights, never recordings or transcripts.
/// Continues from what [part] already has where the server allows it; the
/// whole file is checked against its hash when it's in.
Future<void> downloadVoiceFile(
  http.Client client,
  ({String name, int size, String hash}) file,
  VoicePart part,
  void Function(int) progress,
) async {
  var have = await part.length();
  if (have > file.size) {
    await part.reset();
    have = 0;
  }
  http.StreamedResponse? response;
  if (have < file.size) {
    final uri = Uri.parse(
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/$voiceModelRevision/${file.name}',
    );
    final request = http.Request('GET', uri);
    if (have > 0) request.headers['Range'] = 'bytes=$have-';
    response = await client.send(request).timeout(const Duration(seconds: 30));
    if (have > 0 && response.statusCode == 200) {
      // The server sent the whole file instead: start it over.
      await part.reset();
      have = 0;
    } else if (response.statusCode != (have > 0 ? 206 : 200)) {
      throw StateError('Model download failed (${response.statusCode}).');
    }
  }
  final digest = _DigestSink();
  final hash = sha256.startChunkedConversion(digest);
  var received = 0;
  try {
    if (have > 0) {
      await for (final chunk in part.read()) {
        received += chunk.length;
        hash.add(chunk);
      }
      if (received != have) throw StateError('Model download failed (partial file changed).');
      progress(received);
    }
    if (response != null) {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        received += chunk.length;
        if (received > file.size) throw StateError('Unexpected model file size.');
        hash.add(chunk);
        await part.append(chunk);
        progress(received);
      }
    }
  } finally {
    hash.close();
  }
  if (received != file.size || digest.value.toString() != file.hash) {
    // Whatever was kept is bad: the next try starts this file over.
    await part.reset();
    throw StateError('Model verification failed. Retry the download.');
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

Float32List voicePcmSamples(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final samples = Float32List(bytes.length ~/ 2);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little) / 32768;
  }
  return samples;
}
