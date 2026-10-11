import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:amud/core/content.dart';
import 'package:amud/core/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Storage storage;
  const path = 'assets/rules/notes.json';

  setUp(() async {
    storage = await Storage.openAt(Directory.systemTemp.createTempSync('content').path, name: '${DateTime.now().microsecondsSinceEpoch}');
  });

  /// A content site whose manifest lists [path] as [served], answering with
  /// [body] for the file (its real hash unless [lie]).
  http.Client site(List<int> body, {bool lie = false, List<String>? asked}) {
    final sha = lie ? sha256.convert(utf8.encode('other')).toString() : sha256.convert(body).toString();
    return MockClient((req) async {
      asked?.add(req.url.path);
      if (req.url.path.endsWith('/manifest.json')) {
        return http.Response(jsonEncode({'format': 1, 'version': '1', 'files': {path: {'sha256': sha, 'size': body.length}}}), 200);
      }
      if (req.url.path.endsWith('/files/$sha')) return http.Response.bytes(body, 200);
      return http.Response('', 404);
    });
  }

  test('a changed file is downloaded and used from the next start', () async {
    final fixed = utf8.encode('{"fixed": true}');
    expect(await updateContent(storage, site(fixed), force: true, appBuild: 't'), 1);
    // Not before the next start.
    Content.attach(storage);
    expect(await Content.readString(path), '{"fixed": true}');
  });

  test('a file whose hash does not match is ignored', () async {
    expect(await updateContent(storage, site(utf8.encode('{"bad": 1}'), lie: true), force: true, appBuild: 't'), 0);
    Content.attach(storage);
    final bundled = await rootBundle.loadString(path);
    expect(await Content.readString(path), bundled);
  });

  test('the bundled version is not downloaded again', () async {
    final data = await rootBundle.load(path);
    final asked = <String>[];
    final client = site(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), asked: asked);
    expect(await updateContent(storage, client, force: true, appBuild: 't'), 0);
    expect(asked.where((p) => p.contains('/files/')), isEmpty);
  });

  test('checks at most every six hours', () async {
    final asked = <String>[];
    await updateContent(storage, site(utf8.encode('{}'), asked: asked), appBuild: 't');
    final first = asked.length;
    await updateContent(storage, site(utf8.encode('{}'), asked: asked), appBuild: 't');
    expect(asked.length, first);
  });
}
