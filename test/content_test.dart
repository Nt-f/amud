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
  // A file no build has: a text added between releases.
  const added = 'assets/rules/added.json';

  setUp(() async {
    storage = await Storage.openAt(Directory.systemTemp.createTempSync('content').path, name: '${DateTime.now().microsecondsSinceEpoch}');
  });

  String shaOf(List<int> b) => sha256.convert(b).toString();

  Future<List<int>> bundledBytes() async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// The bundled file's hash, as the site lists it in `replaces` when its
  /// copy is a later version.
  Future<List<String>> laterThanBundled() async => [shaOf(utf8.encode('older')), shaOf(await bundledBytes())];

  /// A content site listing [files] (path → body), each with [replaces]
  /// (null leaves the field out), answering with the bodies (each with its
  /// real hash unless [lie]).
  http.Client site(Map<String, List<int>> files, {List<String>? replaces, bool lie = false, List<String>? asked}) {
    final shas = {for (final MapEntry(:key, :value) in files.entries) key: lie ? shaOf(utf8.encode('other')) : shaOf(value)};
    return MockClient((req) async {
      asked?.add(req.url.path);
      if (req.url.path.endsWith('/manifest.json')) {
        return http.Response(
            jsonEncode({
              'format': 1,
              'version': '1',
              'files': {
                for (final MapEntry(:key, :value) in files.entries)
                  key: {'sha256': shas[key], 'size': value.length, 'replaces': ?replaces},
              },
            }),
            200);
      }
      for (final MapEntry(:key, :value) in files.entries) {
        if (req.url.path.endsWith('/files/${shas[key]}')) return http.Response.bytes(value, 200);
      }
      return http.Response('', 404);
    });
  }

  test('a later version of a bundled file is downloaded and used from the next start', () async {
    final fixed = utf8.encode('{"fixed": true}');
    expect(await updateContent(storage, site({path: fixed}, replaces: await laterThanBundled()), force: true, appBuild: 't'), 1);
    Content.attach(storage);
    expect(await Content.readString(path), '{"fixed": true}');
  });

  test('a file whose hash does not match is ignored', () async {
    expect(await updateContent(storage, site({path: utf8.encode('{"bad": 1}')}, replaces: await laterThanBundled(), lie: true), force: true, appBuild: 't'), 0);
    Content.attach(storage);
    expect(await Content.readString(path), await rootBundle.loadString(path));
  });

  test('the bundled version is not downloaded again', () async {
    final asked = <String>[];
    expect(await updateContent(storage, site({path: await bundledBytes()}, asked: asked), force: true, appBuild: 't'), 0);
    expect(asked.where((p) => p.contains('/files/')), isEmpty);
  });

  test('a site that is behind the build never replaces its text', () async {
    final asked = <String>[];
    // Published before this build: the bundled hash isn't among the
    // versions it replaces, or the site doesn't say.
    for (final replaces in [<String>[shaOf(utf8.encode('older'))], null]) {
      expect(await updateContent(storage, site({path: utf8.encode('{"old": true}')}, replaces: replaces, asked: asked), force: true, appBuild: 't'), 0);
    }
    expect(asked.where((p) => p.contains('/files/')), isEmpty);
    Content.attach(storage);
    expect(await Content.readString(path), await rootBundle.loadString(path));
  });

  test('a file downloaded before is dropped when it turns out not to be newer', () async {
    final body = utf8.encode('{"downloaded": true}');
    expect(await updateContent(storage, site({path: body}, replaces: await laterThanBundled()), force: true, appBuild: 't'), 1);
    // The same file, but the site no longer says it is later than this
    // build's copy (as after an app update that ships newer text).
    expect(await updateContent(storage, site({path: body}, replaces: [shaOf(utf8.encode('older'))]), force: true, appBuild: 't'), 1);
    Content.attach(storage);
    expect(await Content.readString(path), await rootBundle.loadString(path));
  });

  test('a file the build does not have is taken, unless the site is behind', () async {
    final body = utf8.encode('{"new": true}');
    expect(await updateContent(storage, site({added: body}), force: true, appBuild: 't'), 1);
    Content.attach(storage);
    expect(await Content.readString(added), '{"new": true}');

    // Listed beside an older copy of a bundled file: a leftover, dropped.
    expect(await updateContent(storage, site({added: body, path: utf8.encode('{"old": true}')}), force: true, appBuild: 't'), 1);
    Content.attach(storage);
    await expectLater(Content.readString(added), throwsA(anything));
    expect(await Content.readString(path), await rootBundle.loadString(path));
  });

  test('after an app update, downloads wait until this build has checked them', () async {
    final fixed = utf8.encode('{"fixed": true}');
    expect(await updateContent(storage, site({path: fixed}, replaces: await laterThanBundled()), force: true, appBuild: '1.0+1'), 1);
    // The first start of the new build reads its own copy, and keeps the
    // download for the check it makes at once.
    Content.attach(storage, build: '1.1+2');
    expect(await Content.readString(path), await rootBundle.loadString(path));
    await Future<void>.delayed(Duration.zero);
    Content.attach(storage, build: '1.0+1');
    expect(await Content.readString(path), '{"fixed": true}');
    // Checked again under the new build (still newer than its copy): used.
    await updateContent(storage, site({path: fixed}, replaces: await laterThanBundled()), force: true, appBuild: '1.1+2');
    Content.attach(storage, build: '1.1+2');
    expect(await Content.readString(path), '{"fixed": true}');
  });

  test('checks at most every six hours', () async {
    final asked = <String>[];
    await updateContent(storage, site({path: utf8.encode('{}')}, asked: asked), appBuild: 't');
    final first = asked.length;
    await updateContent(storage, site({path: utf8.encode('{}')}, asked: asked), appBuild: 't');
    expect(asked.length, first);
  });

  test('an app update checks at once', () async {
    final asked = <String>[];
    await updateContent(storage, site({path: utf8.encode('{}')}, asked: asked), appBuild: '1.0+1');
    final first = asked.length;
    await updateContent(storage, site({path: utf8.encode('{}')}, asked: asked), appBuild: '1.1+2');
    expect(asked.length, greaterThan(first));
  });
}
