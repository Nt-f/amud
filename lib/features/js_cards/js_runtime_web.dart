import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'js_fetch.dart';
import 'js_runtime.dart';

JsCardRuntime createRuntime() => _WorkerJsRuntime();

/// Runs each script in a dedicated Web Worker (no DOM access), terminated
/// when it's done or on timeout. The worker's own network APIs are removed;
/// its fetch requests come back here to [JsFetcher].
class _WorkerJsRuntime implements JsCardRuntime {
  @override
  Future<JsCardResult> render(String script, String contextJson, {Duration timeout = jsCardTimeout}) async {
    final src = 'self.fetch=undefined;self.XMLHttpRequest=undefined;self.WebSocket=undefined;self.importScripts=undefined;'
        'var __amudSend=function(m){postMessage(JSON.stringify(m));};'
        'onmessage=function(e){__amudReceive(JSON.parse(e.data));};'
        '${wrapScript(script, contextJson)}';
    final blob = web.Blob([src.toJS].toJS, web.BlobPropertyBag(type: 'application/javascript'));
    final url = web.URL.createObjectURL(blob);
    final worker = web.Worker(url.toJS);
    final fetcher = JsFetcher();
    final done = Completer<JsCardResult>();
    worker.onmessage = ((web.MessageEvent e) {
      Map<String, Object?> m;
      try {
        m = (jsonDecode((e.data as JSString?)?.toDart ?? '') as Map).cast<String, Object?>();
      } catch (_) {
        return;
      }
      if (m['type'] == 'fetch') {
        fetcher.fetch(m).then((r) {
          if (!done.isCompleted) worker.postMessage(jsonEncode(r).toJS);
        });
      } else if (m['type'] == 'done' && !done.isCompleted) {
        done.complete(m['ok'] == true ? JsCardResult(m['value']) : JsCardResult(null, '${m['error']}'));
      }
    }).toJS;
    worker.onerror = ((web.Event e) {
      if (!done.isCompleted) done.complete(const JsCardResult(null, 'Script error'));
    }).toJS;
    try {
      return await done.future
          .timeout(timeout, onTimeout: () => JsCardResult(null, 'Script timed out after ${timeout.inSeconds} seconds'));
    } finally {
      worker.terminate();
      web.URL.revokeObjectURL(url);
    }
  }
}
