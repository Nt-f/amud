import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_js/flutter_js.dart';

import 'js_fetch.dart';
import 'js_runtime.dart';

JsCardRuntime createRuntime() => _IsolateJsRuntime();

/// Evaluates each script in a fresh engine inside a short-lived isolate
/// that is killed when it's done or on timeout, so runaway scripts can't
/// freeze the UI. Its fetch requests come back here to [JsFetcher].
class _IsolateJsRuntime implements JsCardRuntime {
  @override
  Future<JsCardResult> render(String script, String contextJson, {Duration timeout = jsCardTimeout}) async {
    final port = ReceivePort();
    final fetcher = JsFetcher();
    final done = Completer<JsCardResult>();
    SendPort? toScript;
    port.listen((msg) async {
      if (msg is SendPort) {
        toScript = msg;
        return;
      }
      final m = _decodeMessage(msg);
      if (m == null) return;
      if (m['type'] == 'fetch') {
        final r = await fetcher.fetch(m);
        toScript?.send(jsonEncode(r));
      } else if (m['type'] == 'done' && !done.isCompleted) {
        done.complete(m['ok'] == true ? JsCardResult(m['value']) : JsCardResult(null, '${m['error']}'));
      }
    });
    final isolate = await Isolate.spawn(_run, (port.sendPort, wrapScript(script, contextJson)), errorsAreFatal: true);
    try {
      return await done.future.timeout(timeout);
    } on TimeoutException {
      return JsCardResult(null, 'Script timed out after ${timeout.inSeconds} seconds');
    } catch (e) {
      return JsCardResult(null, '$e');
    } finally {
      isolate.kill(priority: Isolate.immediate);
      port.close();
    }
  }

  static void _run((SendPort, String) args) {
    final (send, code) = args;
    final inbox = ReceivePort();
    send.send(inbox.sendPort);
    try {
      // xhr:false → no fetch/XMLHttpRequest polyfills; the wrapper's fetch
      // goes through the 'amud' channel instead.
      final rt = getJavascriptRuntime(xhr: false);
      rt.onMessage('amud', (m) => send.send(jsonEncode(m)));
      rt.evaluate('var __amudSend = function(m) { sendMessage("amud", JSON.stringify(m)); };');
      inbox.listen((msg) {
        rt.evaluate('__amudReceive($msg);');
        rt.executePendingJob();
      });
      final r = rt.evaluate(code);
      if (r.isError) send.send(jsonEncode({'type': 'done', 'ok': false, 'error': r.stringResult}));
      // Runs promise callbacks (async render, awaited fetches) until the
      // isolate is killed.
      Timer.periodic(const Duration(milliseconds: 5), (_) => rt.executePendingJob());
    } catch (e) {
      send.send(jsonEncode({'type': 'done', 'ok': false, 'error': '$e'}));
    }
  }
}

Map<String, Object?>? _decodeMessage(Object? msg) {
  try {
    return (jsonDecode(msg as String) as Map).cast<String, Object?>();
  } catch (_) {
    return null;
  }
}
