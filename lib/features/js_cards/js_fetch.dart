import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Carries out a card script's `fetch()` requests on the app's side, so
/// every platform gets the same limits: https only, a handful of requests
/// per update, capped response size and time, and a short cache for GETs
/// (cards re-run every minute).
class JsFetcher {
  static const maxRequests = 10;
  static const maxBytes = 2 * 1024 * 1024;
  static const requestTimeout = Duration(seconds: 10);
  static const cacheFor = Duration(minutes: 5);
  static const methods = {'GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE'};

  /// GET responses by URL and headers, shared by all cards.
  static final _cache = <String, (DateTime, Map<String, Object?>)>{};

  final http.Client Function() _client;
  int _count = 0;

  /// A request couldn't be made (no connection, or it timed out), so the
  /// card's result may be missing its data.
  bool failed = false;
  JsFetcher({http.Client Function()? client}) : _client = client ?? http.Client.new;

  /// Answers a `{type: 'fetch', id, url, method, headers, body}` message from
  /// a script with `{type: 'fetch', id, status, statusText, url, headers,
  /// body}`, or `{type: 'fetch', id, error}`.
  Future<Map<String, Object?>> fetch(Map<String, Object?> m) async {
    final id = m['id'];
    Map<String, Object?> fail(String error) => {'type': 'fetch', 'id': id, 'error': error};

    if (++_count > maxRequests) return fail('Too many requests: at most $maxRequests each time the card updates');
    final uri = Uri.tryParse('${m['url']}');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return fail('Only https:// URLs can be fetched');
    final method = '${m['method'] ?? 'GET'}'.toUpperCase();
    if (!methods.contains(method)) return fail('Unsupported method $method');
    final headers = <String, String>{
      if (m['headers'] is Map)
        for (final e in (m['headers'] as Map).entries) '${e.key}': '${e.value}',
    };
    final body = m['body'] is String ? m['body'] as String : null;

    final key = method == 'GET' ? '$uri ${jsonEncode(headers)}' : null;
    final hit = key == null ? null : _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1) < cacheFor) return {...hit.$2, 'id': id};

    final client = _client();
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null && method != 'GET' && method != 'HEAD') req.body = body;
      final res = await client.send(req).timeout(requestTimeout);
      final bytes = <int>[];
      await for (final chunk in res.stream.timeout(requestTimeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) return fail('Response too large (over ${maxBytes ~/ (1024 * 1024)} MB)');
      }
      final result = <String, Object?>{
        'type': 'fetch',
        'id': id,
        'status': res.statusCode,
        'statusText': res.reasonPhrase ?? '',
        'url': (res.request?.url ?? uri).toString(),
        'headers': res.headers,
        'body': utf8.decode(bytes, allowMalformed: true),
      };
      if (key != null && res.statusCode == 200) _cache[key] = (DateTime.now(), result);
      return result;
    } on TimeoutException {
      failed = true;
      return fail('Request timed out after ${requestTimeout.inSeconds} seconds');
    } catch (e) {
      failed = true;
      return fail('$e');
    } finally {
      client.close();
    }
  }
}
