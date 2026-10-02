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

  Future<void> install(void Function(double) progress) async {
    final cache = await _cache();
    final client = http.Client();
    _download = client;
    var completed = 0;
    try {
      for (final file in voiceModelFiles) {
        final bytes = BytesBuilder(copy: false);
        await downloadVoiceFile(
          client,
          file,
          bytes.add,
          (count) => progress((completed + count) / voiceModelBytes),
        );
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
