// Downloads siddur texts from Sefaria for fully-offline bundling.
//
//   dart run tool/sefaria_sync.dart                 # every version of every siddur
//   dart run tool/sefaria_sync.dart --safe-licenses # only PD / CC0 / CC-BY(-SA) / CC-BY-NC
//   dart run tool/sefaria_sync.dart --book "Siddur Ashkenaz" --book "Siddur Sefard"
//
// Output (flat so Flutter only needs one asset directory entry):
//   assets/sefaria/manifest.json
//   assets/sefaria/<bookSlug>__index.json.gz          (schema tree + metadata)
//   assets/sefaria/<bookSlug>__<lang>__<verSlug>.json.gz (one per version)
//
// Every version's license and source are recorded in the manifest and
// shown in-app for attribution. Review licenses before shipping a build:
// versions marked "unknown" may be copyrighted.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _base = 'https://www.sefaria.org';
const _safeLicenses = {
  'public domain',
  'cc0',
  'cc-by',
  'cc-by-sa',
  'cc-by-nc',
  'cc-by-nc-sa',
};

Future<void> main(List<String> args) async {
  final books = <String>[];
  var safeOnly = false;
  var outDir = 'assets/sefaria';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--book':
        books.add(args[++i]);
      case '--safe-licenses':
        safeOnly = true;
      case '--out':
        outDir = args[++i];
      case '-h' || '--help':
        stdout.writeln(File.fromUri(Platform.script).readAsLinesSync().take(14).join('\n'));
        return;
    }
  }
  final client = HttpClient()..userAgent = 'flutter_siddur-sync/1.0';
  final out = Directory(outDir)..createSync(recursive: true);
  if (books.isEmpty) books.addAll(await _discoverSiddurim(client));
  stdout.writeln('Books: ${books.join(', ')}');

  final manifestBooks = <Map<String, Object?>>[];
  for (final title in books) {
    final slug = _slug(title);
    final versions = (await _getJson(client, '/api/texts/versions/${_enc(title)}') as List)
        .cast<Map<String, dynamic>>();
    Map<String, dynamic>? schema;
    Map<String, dynamic>? bookMeta;
    final manVersions = <Map<String, Object?>>[];
    final pool = _Pool(4);
    final futures = <Future<void>>[];
    for (final v in versions) {
      final license = (v['license'] as String?) ?? 'unknown';
      if (safeOnly && !_safeLicenses.contains(license.toLowerCase())) {
        stdout.writeln('  skip (license $license): ${v['versionTitle']}');
        continue;
      }
      futures.add(pool.run(() async {
        final lang = v['language'] as String;
        final vt = v['versionTitle'] as String;
        final path = '/download/version/${_enc('$title - $lang - $vt')}.json';
        try {
          final data = await _getJson(client, path) as Map<String, dynamic>;
          schema ??= data['schema'] as Map<String, dynamic>?;
          bookMeta ??= {
            'heTitle': data['heTitle'],
            'categories': data['categories'],
          };
          final file = '${slug}__${lang}__${_slug(vt)}.json.gz';
          final bytes = gzip.encode(utf8.encode(jsonEncode({'text': data['text']})));
          File('${out.path}/$file').writeAsBytesSync(bytes);
          final segs = _countSegments(data['text']);
          manVersions.add({
            'language': lang,
            'actualLanguage': data['actualLanguage'] ?? lang,
            'versionTitle': vt,
            'versionTitleInHebrew': v['versionTitleInHebrew'],
            'license': license,
            'versionSource': v['versionSource'],
            'isPrimary': data['isPrimary'] ?? false,
            'priority': data['priority'],
            'direction': data['direction'] ?? (lang == 'he' ? 'rtl' : 'ltr'),
            'segments': segs,
            'file': file,
            'bytes': bytes.length,
          });
          stdout.writeln('  ok  $lang  $segs segs  ${bytes.length ~/ 1024}KB  $vt');
        } catch (e) {
          stderr.writeln('  FAIL $lang $vt: $e');
        }
      }));
    }
    await Future.wait(futures);
    if (schema == null) {
      stderr.writeln('No versions downloaded for $title; skipping');
      continue;
    }
    final indexFile = '${slug}__index.json.gz';
    File('${out.path}/$indexFile')
        .writeAsBytesSync(gzip.encode(utf8.encode(jsonEncode({'title': title, 'schema': schema}))));
    // Largest, primary versions first so defaults are sensible.
    manVersions.sort((a, b) {
      final p = ((b['isPrimary'] == true) ? 1 : 0) - ((a['isPrimary'] == true) ? 1 : 0);
      if (p != 0) return p;
      return (b['segments'] as int).compareTo(a['segments'] as int);
    });
    manifestBooks.add({
      'title': title,
      'heTitle': bookMeta?['heTitle'],
      'slug': slug,
      'categories': bookMeta?['categories'],
      'index': indexFile,
      'versions': manVersions,
    });
  }
  final manifest = {
    'source': 'Sefaria (https://www.sefaria.org)',
    'generated': DateTime.now().toUtc().toIso8601String(),
    'safeLicensesOnly': safeOnly,
    'books': manifestBooks,
  };
  File('${out.path}/manifest.json')
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(manifest));
  client.close();
  stdout.writeln('Wrote ${manifestBooks.length} books to ${out.path}');
}

Future<List<String>> _discoverSiddurim(HttpClient client) async {
  final toc = await _getJson(client, '/api/index/') as List;
  final found = <String>[];
  void walk(Map<String, dynamic> n, List<String> path) {
    if (n['contents'] is List) {
      for (final c in n['contents'] as List) {
        walk(c as Map<String, dynamic>, [...path, (n['category'] as String?) ?? '']);
      }
    } else if (n['title'] is String && path.length >= 2 && path[path.length - 2] == 'Liturgy' &&
        path.last == 'Siddur') {
      found.add(n['title'] as String);
    }
  }
  for (final c in toc) {
    walk(c as Map<String, dynamic>, const []);
  }
  return found;
}

int _countSegments(Object? node) {
  if (node is String) return node.trim().isEmpty ? 0 : 1;
  if (node is List) return node.fold(0, (a, b) => a + _countSegments(b));
  if (node is Map) return node.values.fold(0, (a, b) => a + _countSegments(b));
  return 0;
}

String _enc(String s) => Uri.encodeComponent(s).replaceAll('%20', '%20');

String _slug(String s) {
  final base = s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9֐-׿]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final ascii = base.replaceAll(RegExp(r'[^a-z0-9_]'), '');
  final short = ascii.length > 48 ? ascii.substring(0, 48) : ascii;
  // Short stable hash keeps names unique even when titles only differ in
  // punctuation or non-Latin characters.
  var h = 0x811c9dc5;
  for (final c in utf8.encode(s)) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return '${short.isEmpty ? 'v' : short}_${h.toRadixString(16).padLeft(8, '0').substring(0, 6)}';
}

Future<Object?> _getJson(HttpClient client, String path, {int retries = 3}) async {
  for (var attempt = 0;; attempt++) {
    try {
      final req = await client.getUrl(Uri.parse('$_base$path'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      return jsonDecode(body);
    } catch (e) {
      if (attempt >= retries) rethrow;
      await Future<void>.delayed(Duration(seconds: 1 << attempt));
    }
  }
}

class _Pool {
  final int size;
  int _active = 0;
  final _waiters = <Completer<void>>[];
  _Pool(this.size);

  Future<T> run<T>(Future<T> Function() fn) async {
    if (_active >= size) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    _active++;
    try {
      return await fn();
    } finally {
      _active--;
      if (_waiters.isNotEmpty) _waiters.removeAt(0).complete();
    }
  }
}
