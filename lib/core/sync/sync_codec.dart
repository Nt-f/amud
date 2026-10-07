import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Thrown when a mailbox's contents can't be opened with this key (wrong
/// pairing code, or the mailbox was overwritten).
class SyncKeyError implements Exception {
  @override
  String toString() => 'The synced data could not be decrypted with this pairing code.';
}

/// Everything derived from the pairing secret. The secret never leaves the
/// devices; the Worker only ever sees [mailboxId] and [token] (hashed) and
/// ciphertext.
class SyncKeys {
  SyncKeys._(this.secret, this.mailboxId, this.token, this._enc);

  final Uint8List secret;

  /// 32 hex chars naming the mailbox on the Worker.
  final String mailboxId;

  /// Bearer token for the Worker.
  final String token;
  final SecretKey _enc;

  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _aes = AesGcm.with256bits();

  static Uint8List newSecret() {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
  }

  static Future<SyncKeys> derive(Uint8List secret) async {
    Future<List<int>> part(String label) async =>
        (await _hkdf.deriveKey(secretKey: SecretKey(secret), info: utf8.encode('amud-sync/$label'))).extractBytes();
    String hex(List<int> b) => [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
    final id = hex(await part('id')).substring(0, 32);
    final token = base64Url.encode(await part('token')).replaceAll('=', '');
    return SyncKeys._(secret, id, token, SecretKey(await part('enc')));
  }

  /// AES-256-GCM; the result is base64 of nonce ‖ ciphertext ‖ tag, bound to
  /// this mailbox id so a blob can't be replayed into another mailbox.
  Future<String> seal(List<int> plain) async {
    final box = await _aes.encrypt(plain, secretKey: _enc, aad: utf8.encode(mailboxId));
    return base64.encode(box.concatenation());
  }

  Future<List<int>> open(String blob) async {
    try {
      final box = SecretBox.fromConcatenation(base64.decode(blob), nonceLength: 12, macLength: 16);
      return await _aes.decrypt(box, secretKey: _enc, aad: utf8.encode(mailboxId));
    } catch (_) {
      throw SyncKeyError();
    }
  }
}

/// What one device shows and another enters: `amud1:<secret>` for the default
/// Worker, `amud1:<secret>@https://host` for a custom one.
class PairingCode {
  const PairingCode(this.secret, [this.workerUrl]);
  final Uint8List secret;
  final String? workerUrl;

  static const _prefix = 'amud1:';

  @override
  String toString() => '$_prefix${base64Url.encode(secret).replaceAll('=', '')}${workerUrl == null ? '' : '@$workerUrl'}';

  /// Null when [text] isn't a pairing code.
  static PairingCode? parse(String text) {
    final t = text.trim();
    if (!t.startsWith(_prefix)) return null;
    final body = t.substring(_prefix.length);
    final at = body.indexOf('@');
    final secretPart = at < 0 ? body : body.substring(0, at);
    final url = at < 0 ? null : normalizeWorkerUrl(body.substring(at + 1));
    if (at >= 0 && url == null) return null;
    try {
      final secret = base64Url.decode(base64Url.normalize(secretPart));
      return secret.length == 32 ? PairingCode(Uint8List.fromList(secret), url) : null;
    } catch (_) {
      return null;
    }
  }
}

/// A Worker address as `https://host[/path]` with no trailing slash; null if
/// it isn't an https URL (plain http only for localhost, for development).
String? normalizeWorkerUrl(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'https://$s';
  final u = Uri.tryParse(s);
  if (u == null || u.host.isEmpty || u.hasQuery || u.hasFragment) return null;
  final local = u.host == 'localhost' || u.host == '127.0.0.1';
  if (u.scheme != 'https' && !(u.scheme == 'http' && local)) return null;
  return s.replaceAll(RegExp(r'/+$'), '');
}
