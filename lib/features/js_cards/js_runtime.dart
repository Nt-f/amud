import 'js_runtime_stub.dart'
    if (dart.library.io) 'js_runtime_io.dart'
    if (dart.library.js_interop) 'js_runtime_web.dart';

/// Result of running a card script.
class JsCardResult {
  final Object? value;
  final String? error;
  const JsCardResult(this.value, [this.error]);
  bool get ok => error == null;
}

/// Sandboxed evaluation of user-authored card scripts.
///
/// App Store compliance: scripts are authored by the user on-device (not
/// downloaded from us), run in the platform's own engine (JavaScriptCore on
/// iOS/macOS, QuickJS on Android/desktop, the browser engine on web — no
/// bundled V8 or JIT), without network access or native bridges, and can
/// only return declarative JSON that the app renders with native widgets.
abstract class JsCardRuntime {
  /// Runs [script] and calls its global `render(ctx)` with [contextJson].
  /// The return value is JSON-serialized. Times out after [timeout].
  Future<JsCardResult> render(String script, String contextJson, {Duration timeout = const Duration(seconds: 2)});
}

JsCardRuntime createJsCardRuntime() => createRuntime();

/// Wrapper executed around the user's script: removes network globals,
/// invokes render(ctx) and serializes the result.
String wrapScript(String script, String contextJson) => '''
(function(){
  var fetch = undefined, XMLHttpRequest = undefined, WebSocket = undefined, importScripts = undefined;
  var __out;
  try {
    $script
    ;
    if (typeof render !== 'function') { throw new Error('Define a function render(ctx) that returns a card object'); }
    var __ctx = $contextJson;
    __out = JSON.stringify({ok: true, value: render(__ctx)});
  } catch (e) {
    __out = JSON.stringify({ok: false, error: String(e && e.stack ? e.stack : e)});
  }
  return __out;
})()
''';
