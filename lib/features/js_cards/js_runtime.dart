import 'js_runtime_stub.dart'
    if (dart.library.io) 'js_runtime_io.dart'
    if (dart.library.js_interop) 'js_runtime_web.dart';

/// Result of running a card script.
class JsCardResult {
  final Object? value;
  final String? error;
  /// One of the script's requests couldn't reach the network.
  final bool fetchFailed;
  const JsCardResult(this.value, [this.error, this.fetchFailed = false]);
  bool get ok => error == null;
}

/// How long a script may take in all, network requests included.
const jsCardTimeout = Duration(seconds: 15);

/// Sandboxed evaluation of user-authored card scripts.
///
/// Scripts are authored or explicitly installed by the user and run in the
/// platform's own engine (JavaScriptCore on
/// iOS/macOS, QuickJS on Android/desktop, a Web Worker on web; no bundled
/// V8 or JIT) with no native bridges, and can only return declarative JSON
/// that the app renders with native widgets. Their only way out is `fetch()`,
/// which the app carries out itself (see JsFetcher): https only, limited in
/// count, size and time. XMLHttpRequest, WebSocket and importScripts are gone.
abstract class JsCardRuntime {
  /// Runs [script] and calls its global `render(ctx)` (which may be async)
  /// with [contextJson]. The return value is JSON-serialized. Gives up after
  /// [timeout].
  Future<JsCardResult> render(String script, String contextJson, {Duration timeout = jsCardTimeout});
}

JsCardRuntime createJsCardRuntime() => createRuntime();

/// Wrapper executed around the user's script. The host provides
/// `__amudSend(message)` and calls `__amudReceive(message)` with fetch
/// results; the script's result goes back as a `done` message.
String wrapScript(String script, String contextJson) => '''
(function(){
  var __g = (typeof globalThis !== 'undefined') ? globalThis : this;
  var __send = __amudSend;
  var __waiting = {}, __count = 0;
  var XMLHttpRequest = undefined, WebSocket = undefined, importScripts = undefined;

  function __response(m) {
    var h = m.headers || {};
    return {
      ok: m.status >= 200 && m.status < 300,
      status: m.status,
      statusText: m.statusText || '',
      url: m.url,
      headers: { get: function(n) { var v = h[String(n).toLowerCase()]; return v === undefined ? null : v; } },
      text: function() { return Promise.resolve(m.body); },
      json: function() { return Promise.resolve().then(function() { return JSON.parse(m.body); }); }
    };
  }

  __g.__amudReceive = function(m) {
    var w = __waiting[m.id];
    if (!w) return;
    delete __waiting[m.id];
    if (m.error) w.reject(new Error(m.error)); else w.resolve(__response(m));
  };

  var fetch = __g.fetch = function(url, opts) {
    opts = opts || {};
    return new Promise(function(resolve, reject) {
      var id = String(++__count);
      __waiting[id] = {resolve: resolve, reject: reject};
      __send({
        type: 'fetch', id: id, url: String(url),
        method: String(opts.method || 'GET').toUpperCase(),
        headers: opts.headers || {},
        body: opts.body == null ? null : String(opts.body)
      });
    });
  };

  function __fail(e) {
    // "Error: message", then where it happened (some engines' stacks
    // leave the message out).
    var stack = e && e.stack ? String(e.stack) : '';
    __send({type: 'done', ok: false, error: String(e) + (stack && stack.indexOf(String(e)) < 0 ? '\\n' + stack : '')});
  }
  try {
    $script
    ;
    if (typeof render !== 'function') { throw new Error('Define a function render(ctx) that returns a card object'); }
    var __ctx = $contextJson;
    Promise.resolve(render(__ctx)).then(function(v) {
      try { __send({type: 'done', ok: true, value: v}); } catch (e) { __fail(e); }
    }, __fail);
  } catch (e) {
    __fail(e);
  }
})();
''';
