import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/content.dart';
import '../../core/providers.dart';
import '../../core/storage.dart';
import 'daf_layout.dart';
import 'gemara_data.dart';
import 'study_book.dart';

/// Where the line maps come from: the content site, or elsewhere (a local
/// copy, to try new maps) with `--dart-define=DAF_PRINT_BASE=http://…`.
const dafPrintBase = String.fromEnvironment('DAF_PRINT_BASE', defaultValue: contentServer);

/// The printed page's line maps (tool/daf/linemap.py), served a tractate at
/// a time:
///
/// * `daf/v1/index.json`: `{"version", "works": {"<book>": {path, sha256, units}}}`
/// * `daf/v1/<slug>.<sha8>.json`: `{"book", "amudim": {"2a": map, …}}`
///
/// Opening an amud saves its whole tractate, so the rest open offline.
Future<({Map<String, Object?> amudim, String sha})?> fetchDafPrint(http.Client client, String book) async {
  final res = await client.get(Uri.parse('$dafPrintBase/daf/v1/index.json')).timeout(const Duration(seconds: 20));
  if (res.statusCode != 200) return null;
  final works = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['works'] as Map?)?.cast<String, Object?>();
  final entry = (works?[book] as Map?)?.cast<String, Object?>();
  if (entry == null) return null;
  final got = await client.get(Uri.parse('$dafPrintBase/daf/v1/${entry['path']}')).timeout(const Duration(minutes: 2));
  if (got.statusCode != 200) return null;
  final j = jsonDecode(utf8.decode(got.bodyBytes)) as Map<String, Object?>;
  return (amudim: (j['amudim'] as Map).cast<String, Object?>(), sha: '${entry['sha256']}');
}

String _blobKey(String book, String amud) => 'dafPrint:$book:$amud';

/// The line map of an amud, or null where there is none (not a Bavli amud,
/// not made yet, or offline before its tractate was saved).
final dafLineMapProvider = FutureProvider.family<DafLineMap?, DafRef>((ref, r) async {
  final book = studyBook(r.tractate);
  if (book == null || book.kind != StudyKind.bavli) return null;
  final storage = ref.read(storageProvider);
  DafLineMap? read(List<int>? blob) {
    if (blob == null) return null;
    try {
      final j = jsonDecode(utf8.decode(GZipDecoder().decodeBytes(blob)));
      return j is Map ? DafLineMap.fromJson(j.cast<String, Object?>()) : null;
    } catch (_) {
      return null;
    }
  }

  // A tractate already saved has every amud the site had; one it lacked is
  // saved as "none" so it isn't asked for again.
  if (storage.readJson(dafPrintShaKey(book.id), (j) => j as String) != null) {
    return read(storage.readBlob(_blobKey(book.id, r.amud)));
  }
  final amudim = await _saveDafPrint(storage, book.id);
  final j = amudim[r.amud];
  return j is Map ? DafLineMap.fromJson(j.cast<String, Object?>()) : null;
});

final _downloads = <String, Future<Map<String, Object?>>>{};

Future<Map<String, Object?>> _saveDafPrint(Storage storage, String book) => _downloads[book] ??= () async {
      final client = http.Client();
      try {
        final got = await fetchDafPrint(client, book);
        if (got == null) return <String, Object?>{};
        for (final MapEntry(key: amud, value: map) in got.amudim.entries) {
          await storage.writeBlob(_blobKey(book, amud), GZipEncoder().encodeBytes(utf8.encode(jsonEncode(map))));
        }
        // Lets the content check drop these when the site's copy changes.
        await storage.writeJson(dafPrintShaKey(book), got.sha);
        return got.amudim;
      } catch (_) {
        return <String, Object?>{};
      } finally {
        client.close();
        _downloads.remove(book);
      }
    }();
