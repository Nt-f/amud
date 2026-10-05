import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import '../../core/storage.dart';
import 'voice_model.dart';

/// Persistent browser cache for weights; a worker keeps inference off the UI.
class OfflineVoiceBackend {
  OfflineVoiceBackend(Storage storage);
  http.Client? _download;
  web.Worker? _worker;
  Completer<String>? _pending;
  Future<web.Cache> _cache() =>
      web.window.caches.open('amud-voice-$voiceModelRevision').toDart;
  String _key(String name) =>
      Uri.base.resolve('voice-model/$voiceModelRevision/$name').toString();

  Future<bool> ready() async {
    final cache = await _cache();
    final verified = await cache.match(_key('verified').toJS).toDart;
    if (verified == null) return false;
    for (final file in voiceModelFiles) {
      final response = await cache.match(_key(file.name).toJS).toDart;
      if (response == null ||
          response.headers.get('Content-Length') != '${file.size}') {
        return false;
      }
    }
    return true;
  }

  /// Downloads the files not yet in, continuing any that were cut off.
  Future<void> install(void Function(double) progress) async {
    final cache = await _cache();
    final client = http.Client();
    _download = client;
    var completed = 0;
    try {
      for (final file in voiceModelFiles) {
        // Checked when it was downloaded, before it was stored whole.
        final have = await cache.match(_key(file.name).toJS).toDart;
        if (have != null && have.headers.get('Content-Length') == '${file.size}') {
          completed += file.size;
          progress(completed / voiceModelBytes);
          continue;
        }
        final part = _CachePart(cache, (i) => _key('${file.name}.part$i'));
        await downloadVoiceFile(
          client,
          file,
          part,
          (count) => progress((completed + count) / voiceModelBytes),
        );
        await part.flush();
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in part.read()) {
          bytes.add(chunk);
        }
        await cache
            .put(
              _key(file.name).toJS,
              web.Response(
                bytes.takeBytes().toJS,
                web.ResponseInit(
                  headers: web.Headers()..set('Content-Length', '${file.size}'),
                ),
              ),
            )
            .toDart;
        await part.reset();
        completed += file.size;
      }
      await cache
          .put(_key('verified').toJS, web.Response(voiceModelRevision.toJS))
          .toDart;
      try {
        await web.window.navigator.storage.persist().toDart;
      } catch (_) {}
    } finally {
      client.close();
      _download = null;
    }
  }

  /// Bytes stored: the model, and any download in progress.
  Future<int> size() async {
    final cache = await _cache();
    var bytes = 0;
    for (final request in (await cache.keys().toDart).toDart) {
      final response = await cache.match(request).toDart;
      bytes += int.tryParse(response?.headers.get('Content-Length') ?? '') ?? 0;
    }
    return bytes;
  }

  /// Deletes the model, and any download in progress.
  Future<void> remove() async {
    _download?.close();
    _worker?.terminate();
    _worker = null;
    await web.window.caches.delete('amud-voice-$voiceModelRevision').toDart;
  }

  Future<String> transcribe(Float32List samples, {String language = ''}) async {
    if (!await ready()) throw StateError('Download the voice model first.');
    final cache = await _cache();
    final first = _worker == null;
    if (first) {
      _worker = web.Worker(
        Uri.base
            .resolve('assets/assets/voice/offline_voice_worker.js')
            .toString()
            .toJS,
      );
      _worker!.onmessage = ((web.MessageEvent event) {
        final result = event.data as JSObject;
        final error = result.getProperty<JSString?>('error'.toJS)?.toDart;
        if (error != null) {
          _pending?.completeError(StateError(error));
        } else {
          _pending?.complete(result.getProperty<JSString>('text'.toJS).toDart);
        }
        _pending = null;
      }).toJS;
      _worker!.onerror = ((web.Event event) {
        _pending?.completeError(StateError('Offline voice worker failed.'));
        _pending = null;
        _worker?.terminate();
        _worker = null;
      }).toJS;
    }
    final message = JSObject();
    message.setProperty('language'.toJS, language.toJS);
    final transfers = <JSAny>[];
    if (first) {
      final files = JSObject();
      for (final file in voiceModelFiles) {
        final response = await cache.match(_key(file.name).toJS).toDart;
        final buffer = await response!.arrayBuffer().toDart;
        files.setProperty(file.name.toJS, buffer);
        transfers.add(buffer);
      }
      message.setProperty('files'.toJS, files);
      message.setProperty(
        'runtime'.toJS,
        Uri.base
            .resolve('assets/packages/sherpa_onnx_web/assets/')
            .toString()
            .toJS,
      );
    }
    final audio = samples.toJS;
    message.setProperty('samples'.toJS, audio);
    transfers.add(audio.getProperty<JSArrayBuffer>('buffer'.toJS));
    final pending = Completer<String>();
    _pending = pending;
    _worker!.postMessage(message, transfers.toJS);
    try {
      return await pending.future;
    } catch (_) {
      _worker?.terminate();
      _worker = null;
      rethrow;
    }
  }

  void dispose() {
    _download?.close();
    _worker?.terminate();
    _worker = null;
    _pending?.completeError(StateError('Voice navigation closed.'));
    _pending = null;
  }
}

/// A file being downloaded, kept in the cache in pieces of [_piece] bytes
/// (the cache can't append), so a closed tab loses at most one piece.
class _CachePart implements VoicePart {
  static const _piece = 8 * 1024 * 1024;
  final web.Cache cache;
  final String Function(int) key;
  final _buffer = BytesBuilder(copy: false);
  int? _pieces;
  _CachePart(this.cache, this.key);

  Future<web.Response?> _get(int i) => cache.match(key(i).toJS).toDart;

  /// The pieces kept, counted from the first until one is missing.
  Future<int> _count() async {
    if (_pieces case final n?) return n;
    var n = 0;
    while (await _get(n) != null) {
      n++;
    }
    return _pieces = n;
  }

  @override
  Future<int> length() async {
    var bytes = _buffer.length;
    for (var i = 0; i < await _count(); i++) {
      bytes += int.parse((await _get(i))!.headers.get('Content-Length')!);
    }
    return bytes;
  }

  @override
  Stream<List<int>> read() async* {
    for (var i = 0; i < await _count(); i++) {
      yield (await (await _get(i))!.arrayBuffer().toDart).toDart.asUint8List();
    }
    if (_buffer.isNotEmpty) yield _buffer.toBytes();
  }

  @override
  Future<void> append(List<int> bytes) async {
    _buffer.add(bytes);
    if (_buffer.length >= _piece) await flush();
  }

  /// Stores what's buffered as the next piece.
  Future<void> flush() async {
    if (_buffer.isEmpty) return;
    final n = await _count();
    final bytes = _buffer.takeBytes();
    await cache
        .put(
          key(n).toJS,
          web.Response(
            bytes.toJS,
            web.ResponseInit(headers: web.Headers()..set('Content-Length', '${bytes.length}')),
          ),
        )
        .toDart;
    _pieces = n + 1;
  }

  @override
  Future<void> reset() async {
    _buffer.clear();
    for (var i = 0; i < await _count(); i++) {
      await cache.delete(key(i).toJS).toDart;
    }
    _pieces = 0;
  }
}
