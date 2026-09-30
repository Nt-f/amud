import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_js/flutter_js.dart';

import 'js_runtime.dart';

JsCardRuntime createRuntime() => _IsolateJsRuntime();

/// Evaluates each script in a fresh engine inside a short-lived isolate
/// that is killed on timeout, so runaway scripts can't freeze the UI.
class _IsolateJsRuntime implements JsCardRuntime {
  @override
  Future<JsCardResult> render(String script, String contextJson, {Duration timeout = const Duration(seconds: 2)}) async {
    final port = ReceivePort();
    final code = wrapScript(script, contextJson);
    final isolate = await Isolate.spawn(_run, (port.sendPort, code), errorsAreFatal: true);
    try {
      final msg = await port.first.timeout(timeout) as String;
      return _decode(msg);
    } on TimeoutException {
      return const JsCardResult(null, 'Script timed out');
    } catch (e) {
      return JsCardResult(null, '$e');
    } finally {
      isolate.kill(priority: Isolate.immediate);
      port.close();
    }
  }

  static void _run((SendPort, String) args) {
    final (send, code) = args;
    try {
      // xhr:false → no fetch/XMLHttpRequest polyfills are installed.
      final rt = getJavascriptRuntime(xhr: false);
      final r = rt.evaluate(code);
      send.send(r.isError ? jsonEncode({'ok': false, 'error': r.stringResult}) : r.stringResult);
      rt.dispose();
    } catch (e) {
      send.send(jsonEncode({'ok': false, 'error': '$e'}));
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
