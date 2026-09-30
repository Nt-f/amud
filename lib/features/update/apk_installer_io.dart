import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const _channel = MethodChannel('siddur/installer');

Future<Directory> _dir() async => Directory((await _channel.invokeMethod<String>('updatesDir'))!);

Future<String> download(String url, String version, {int? size, String? sha256, void Function(double)? onProgress}) async {
  final dir = await _dir();
  final file = File('${dir.path}/siddur-$version.apk');
  if (await file.exists() && (size == null || await file.length() == size) && await _hashOk(file, sha256)) {
    return file.path;
  }
  // Only the newest download is kept.
  await clear();
  await dir.create(recursive: true);
  final part = File('${file.path}.part');
  final client = http.Client();
  try {
    final res = await client.send(http.Request('GET', Uri.parse(url)));
    if (res.statusCode != 200) throw 'GitHub returned ${res.statusCode}';
    final total = res.contentLength ?? size;
    final sink = part.openWrite();
    var got = 0;
    var last = -1.0;
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total != null && total > 0) {
          final p = got / total;
          if (p - last >= 0.01 || p >= 1) {
            last = p;
            onProgress?.call(p.clamp(0, 1));
          }
        }
      }
    } finally {
      await sink.close();
    }
    if (size != null && got != size) throw 'The download was incomplete';
    if (!await _hashOk(part, sha256)) throw "The download didn't match the release";
    await part.rename(file.path);
    return file.path;
  } catch (_) {
    if (await part.exists()) await part.delete();
    rethrow;
  } finally {
    client.close();
  }
}

Future<bool> _hashOk(File f, String? sha256) async =>
    sha256 == null || (await crypto.sha256.bind(f.openRead()).first).toString() == sha256.toLowerCase();

Future<bool> canInstall() async => await _channel.invokeMethod<bool>('canInstall') ?? false;

Future<void> openInstallSettings() => _channel.invokeMethod<void>('openInstallSettings');

Future<void> install(String path) => _channel.invokeMethod<void>('install', {'path': path});

Future<void> clear() async {
  final dir = await _dir();
  if (!await dir.exists()) return;
  await for (final f in dir.list()) {
    try {
      await f.delete(recursive: true);
    } catch (_) {}
  }
}
