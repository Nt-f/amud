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

/// Download only public model weights, never recordings or transcripts.
Future<void> downloadVoiceFile(
  http.Client client,
  ({String name, int size, String hash}) file,
  void Function(List<int>) write,
  void Function(int) progress,
) async {
  final uri = Uri.parse(
    'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/$voiceModelRevision/${file.name}',
  );
  final response = await client
      .send(http.Request('GET', uri))
      .timeout(const Duration(seconds: 30));
  if (response.statusCode != 200) {
    throw StateError('Model download failed (${response.statusCode}).');
  }
  final digest = _DigestSink();
  final hash = sha256.startChunkedConversion(digest);
  var received = 0;
  try {
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 30),
    )) {
      received += chunk.length;
      if (received > file.size) throw StateError('Unexpected model file size.');
      hash.add(chunk);
      write(chunk);
      progress(received);
    }
  } finally {
    hash.close();
  }
  if (received != file.size || digest.value.toString() != file.hash) {
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
