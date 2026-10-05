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

  /// Downloads the files not yet in, continuing any that were cut off.
  Future<void> install(void Function(double) progress) async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final client = http.Client();
    _download = client;
    var completed = 0;
    try {
      for (final file in voiceModelFiles) {
        final target = File('${directory.path}/${file.name}');
        // Checked when it was downloaded, before it got its name.
        if (await target.exists() && await target.length() == file.size) {
          completed += file.size;
          progress(completed / voiceModelBytes);
          continue;
        }
        final part = _FilePart(File('${target.path}.part'));
        try {
          await downloadVoiceFile(
            client,
            file,
            part,
            (bytes) => progress((completed + bytes) / voiceModelBytes),
          );
        } finally {
          await part.close();
        }
        await part.file.rename(target.path);
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

  /// Bytes on the device: the model, and any download in progress.
  Future<int> size() async {
    final directory = await _directory();
    if (!await directory.exists()) return 0;
    var bytes = 0;
    await for (final f in directory.list()) {
      if (f is File) bytes += await f.length();
    }
    return bytes;
  }

  /// Deletes the model, and any download in progress.
  Future<void> remove() async {
    _download?.close();
    final directory = await _directory();
    if (await directory.exists()) await directory.delete(recursive: true);
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

/// A file being downloaded, kept as `<name>.part` until it's checked.
class _FilePart implements VoicePart {
  final File file;
  IOSink? _sink;
  _FilePart(this.file);

  @override
  Future<int> length() async => await file.exists() ? file.length() : 0;

  @override
  Stream<List<int>> read() => file.openRead();

  @override
  Future<void> append(List<int> bytes) async => (_sink ??= file.openWrite(mode: FileMode.append)).add(bytes);

  @override
  Future<void> reset() async {
    await close();
    if (await file.exists()) await file.delete();
  }

  Future<void> close() async {
    final sink = _sink;
    _sink = null;
    if (sink != null) {
      await sink.flush();
      await sink.close();
    }
  }
}
