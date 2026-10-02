import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Transcribe locally rather than translating Hebrew names to English.
String decodeVoice(
  String directory,
  Float32List samples, {
  String language = '',
}) {
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: '$directory/small-encoder.int8.onnx',
          decoder: '$directory/small-decoder.int8.onnx',
          task: 'transcribe',
          language: language,
        ),
        tokens: '$directory/small-tokens.txt',
        modelType: 'whisper',
        numThreads: 2,
        debug: false,
      ),
    ),
  );
  try {
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: 16000);
      recognizer.decode(stream);
      return recognizer.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  } finally {
    recognizer.free();
  }
}
