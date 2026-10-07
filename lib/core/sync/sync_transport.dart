import 'dart:convert';

import 'package:http/http.dart' as http;

/// What the mailbox holds: a revision and an encrypted blob.
class RemoteBlob {
  const RemoteBlob(this.rev, this.blob);
  final int rev;
  final String? blob;
}

class PushResult {
  const PushResult.ok(this.rev) : conflict = null;
  const PushResult.conflict(this.conflict) : rev = null;
  final int? rev;

  /// The mailbox's current contents when someone else wrote first.
  final RemoteBlob? conflict;
}

class SyncTransportError implements Exception {
  SyncTransportError(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Where the encrypted blob lives. The Worker is one implementation; the
/// engine only needs these three calls.
abstract class SyncTransport {
  /// Null when nothing has ever been written.
  Future<RemoteBlob?> pull();

  /// Replaces the blob if the mailbox is still at [ifRev] (0 to create).
  Future<PushResult> push(String blob, int ifRev);

  Future<void> deleteAll();
}

/// Talks to the sync Worker (worker/sync, protocol in its README).
class WorkerTransport implements SyncTransport {
  WorkerTransport({required this.baseUrl, required this.mailboxId, required this.token, http.Client? client})
      : _http = client ?? http.Client();

  final String baseUrl;
  final String mailboxId;
  final String token;
  final http.Client _http;

  Uri get _uri => Uri.parse('$baseUrl/v1/$mailboxId');
  Map<String, String> get _auth => {'authorization': 'Bearer $token'};

  static const _timeout = Duration(seconds: 20);

  Never _fail(http.Response r) {
    String? detail;
    try {
      detail = (jsonDecode(r.body) as Map)['error'] as String?;
    } catch (_) {}
    throw SyncTransportError(switch (r.statusCode) {
      401 || 403 => 'The sync server refused this pairing code (it belongs to a different mailbox).',
      413 => 'The synced data is too large for the server.',
      _ => 'The sync server answered ${r.statusCode}${detail == null ? '' : ' ($detail)'}.',
    }, r.statusCode);
  }

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on SyncTransportError {
      rethrow;
    } catch (e) {
      throw SyncTransportError('Could not reach the sync server ($e).');
    }
  }

  @override
  Future<RemoteBlob?> pull() => _guard(() async {
        final r = await _http.get(_uri, headers: _auth).timeout(_timeout);
        if (r.statusCode == 404) return null;
        if (r.statusCode != 200) _fail(r);
        final j = jsonDecode(r.body) as Map;
        return RemoteBlob(j['rev'] as int, j['blob'] as String?);
      });

  @override
  Future<PushResult> push(String blob, int ifRev) => _guard(() async {
        final r = await _http
            .put(_uri, headers: {..._auth, 'content-type': 'application/json', 'if-match': '$ifRev'}, body: jsonEncode({'blob': blob}))
            .timeout(_timeout);
        if (r.statusCode == 409) {
          final j = jsonDecode(r.body) as Map;
          return PushResult.conflict(RemoteBlob(j['rev'] as int, j['blob'] as String?));
        }
        if (r.statusCode != 200) _fail(r);
        return PushResult.ok((jsonDecode(r.body) as Map)['rev'] as int);
      });

  @override
  Future<void> deleteAll() => _guard(() async {
        final r = await _http.delete(_uri, headers: _auth).timeout(_timeout);
        if (r.statusCode != 200 && r.statusCode != 404) _fail(r);
      });

  /// Whether [baseUrl] is an Amud sync Worker (for validating a custom URL).
  static Future<bool> check(String baseUrl, {http.Client? client}) async {
    try {
      final r = await (client ?? http.Client()).get(Uri.parse('$baseUrl/v1/health')).timeout(const Duration(seconds: 10));
      final j = jsonDecode(r.body);
      return r.statusCode == 200 && j is Map && j['app'] == 'amud-sync';
    } catch (_) {
      return false;
    }
  }
}
