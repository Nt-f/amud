import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/storage.dart';
import 'voice_model.dart';
import 'voice_decode.dart';

class OfflineVoiceBackend {
  OfflineVoiceBackend(Storage storage);
  http.Client? _download;

  Future<Directory> _directory() async {
    final root = await getApplicationSupportDirectory();
    return Directory('${root.path}/voice/whisper-small-$voiceModelRevision');
  }

  Future<bool> ready() async {
    final directory = await _directory();
    if (!await File('${directory.path}/verified').exists()) return false;
    for (final file in voiceModelFiles) {
      final local = File('${directory.path}/${file.name}');
      if (!await local.exists() || await local.length() != file.size) {
        return false;
      }
    }
    return true;
  }

  Future<void> install(void Function(double) progress) async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final client = http.Client();
    _download = client;
    var completed = 0;
    try {
      for (final file in voiceModelFiles) {
        final target = File('${directory.path}/${file.name}');
        final temporary = File('${target.path}.part');
        final sink = temporary.openWrite();
        try {
          await downloadVoiceFile(
            client,
            file,
            sink.add,
            (bytes) => progress((completed + bytes) / voiceModelBytes),
          );
          await sink.flush();
        } finally {
          await sink.close();
        }
        await temporary.rename(target.path);
        completed += file.size;
      }
      await File(
        '${directory.path}/verified',
      ).writeAsString(voiceModelRevision, flush: true);
    } finally {
      client.close();
      _download = null;
    }
  }

  Future<String> transcribe(Float32List samples, {String language = ''}) async {
    if (!await ready()) throw StateError('Download the voice model first.');
    final path = (await _directory()).path;
    return Isolate.run(() {
      sherpa.initBindings();
      return decodeVoice(path, samples, language: language);
    });
  }

  void dispose() => _download?.close();
}
