// Offline recognition smoke test; also useful for benchmarking mixed commands.
// dart run tool/voice/transcribe.dart MODEL_DIRECTORY RECORDING.wav [LIB_DIRECTORY]
import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'package:amud/features/voice/voice_decode.dart';

void main(List<String> args) {
  if (args.length < 2 || args.length > 4) {
    stderr.writeln(
      'Usage: dart run tool/voice/transcribe.dart MODEL_DIRECTORY RECORDING.wav [LIB_DIRECTORY] [LANGUAGE]',
    );
    exitCode = 64;
    return;
  }
  sherpa.initBindings(args.length >= 3 ? args[2] : null);
  final wave = sherpa.readWave(args[1]);
  if (wave.sampleRate != 16000) {
    throw ArgumentError('Recording must be mono 16 kHz WAV.');
  }
  final watch = Stopwatch()..start();
  stdout.writeln(
    decodeVoice(
      args[0],
      wave.samples,
      language: args.length == 4 ? args[3] : '',
    ),
  );
  stderr.writeln('Local recognition: ${watch.elapsedMilliseconds} ms');
}
