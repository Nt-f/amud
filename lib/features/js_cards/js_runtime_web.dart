import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'js_runtime.dart';

JsCardRuntime createRuntime() => _WorkerJsRuntime();

/// Runs each script in a dedicated Web Worker (no DOM access), terminated
/// on completion or timeout.
class _WorkerJsRuntime implements JsCardRuntime {
  @override
  Future<JsCardResult> render(String script, String contextJson, {Duration timeout = const Duration(seconds: 2)}) async {
    final src = 'self.fetch=undefined;self.XMLHttpRequest=undefined;self.WebSocket=undefined;self.importScripts=undefined;'
        'postMessage(${wrapScript(script, contextJson)});';
    final blob = web.Blob([src.toJS].toJS, web.BlobPropertyBag(type: 'application/javascript'));
    final url = web.URL.createObjectURL(blob);
    final worker = web.Worker(url.toJS);
    final done = Completer<JsCardResult>();
    worker.onmessage = ((web.MessageEvent e) {
      final data = (e.data as JSString?)?.toDart ?? '';
      if (!done.isCompleted) done.complete(_decode(data));
    }).toJS;
    worker.onerror = ((web.Event e) {
      if (!done.isCompleted) done.complete(const JsCardResult(null, 'Script error'));
    }).toJS;
    try {
      return await done.future.timeout(timeout, onTimeout: () => const JsCardResult(null, 'Script timed out'));
    } finally {
      worker.terminate();
      web.URL.revokeObjectURL(url);
    }
  }
}

JsCardResult _decode(String msg) {
  try {
    final j = jsonDecode(msg) as Map<String, dynamic>;
    if (j['ok'] == true) return JsCardResult(j['value']);
    return JsCardResult(null, '${j['error']}');
  } catch (_) {
    return JsCardResult(null, msg);
  }
}
