import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'storage.dart';

/// Where content updates and the interlinear texts come from
/// (tool/content_site/build.py builds it).
const contentServer = 'https://text.amud.page';

/// The content format this build reads (the site's content/v1/).
const _format = 1;

const _patchesKey = 'contentPatches';
const _checkedKey = 'contentCheckedAt';
const _checkedBuildKey = 'contentCheckedBuild';
const _bundledKey = 'contentBundledSha';
const _checkEvery = Duration(hours: 6);

String _blobOf(String sha) => 'content:$sha';

/// The app's bundled content (siddurim, Sefaria texts, rules, Tehillim),
/// read from a downloaded update when there is one.
///
/// Updates are downloaded in the background by [updateContent] and take
/// effect the next time the app starts: [attach] takes the list once, so the
/// texts never change under the reader, and files that belong together
/// (a book's manifest and its texts) always come from the same update.
class Content {
  Content._();

  static Storage? _storage;
  static Map<String, String> _active = const {};

  /// Called once at startup, before anything reads content. Also drops
  /// downloads no longer in use.
  ///
  /// With [build] ([contentBuild]), downloads are used only if the last
  /// check was made by this build: after an app update, which may ship newer
  /// text, the app reads its own copies until [updateContent] has checked
  /// them again (it does so at once). The downloads are kept meanwhile.
  static void attach(Storage storage, {String? build}) {
    _storage = storage;
    final patches = _patches(storage);
    final checked = build == null || storage.readJson(_checkedBuildKey, (j) => j as String) == build;
    _active = checked ? patches : const {};
    if (kIsWeb) return;
    final keep = {for (final sha in patches.values) _blobOf(sha)};
    for (final k in storage.blobKeys.toList()) {
      if (k.startsWith('content:') && !keep.contains(k)) unawaited(storage.deleteBlob(k));
    }
  }

  static Future<List<int>> read(String path) async {
    final sha = _active[path];
    if (sha != null) {
      final b = _storage?.readBlob(_blobOf(sha));
      if (b != null) return b;
    }
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static Future<String> readString(String path) async => utf8.decode(await read(path));
}

Map<String, String> _patches(Storage s) =>
    s.readJson(_patchesKey, (j) => (j as Map).cast<String, String>()) ?? <String, String>{};

/// Downloads newer content from [contentServer], at most every six hours
/// unless [force]. Returns how many files changed (in use from the next
/// start). Interlinear texts and printed-page line maps that changed are
/// dropped from the device, so the next time one is opened the new version
/// is fetched.
Future<int> updateContent(Storage s, http.Client client, {bool force = false, String appBuild = ''}) async {
  // The web app is redeployed with its assets; there is nothing to patch.
  if (kIsWeb) return 0;
  final now = DateTime.now().millisecondsSinceEpoch;
  final last = s.readJson(_checkedKey, (j) => j as int);
  // After an app update, check at once: it may ship text newer than a file
  // downloaded for the build before it.
  final sameBuild = s.readJson(_checkedBuildKey, (j) => j as String) == appBuild;
  if (!force && sameBuild && last != null && now - last < _checkEvery.inMilliseconds) return 0;

  var changed = await _updateInterlinear(s, client);
  changed += await _updateDafPrint(s, client);

  final res = await client.get(Uri.parse('$contentServer/content/v$_format/manifest.json')).timeout(const Duration(seconds: 20));
  if (res.statusCode != 200) return changed;
  final manifest = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
  if (manifest['format'] != _format) return changed;
  final files = (manifest['files'] as Map).cast<String, Object?>();

  final patches = _patches(s);
  final take = await _newerThanBundled(files, _BundledShas(s, appBuild));
  // Everything else is read from the app's own copy: a file the site no
  // longer lists, one the app now ships, and one downloaded before that
  // turns out not to be newer.
  for (final path in patches.keys.where((p) => !take.containsKey(p)).toList()) {
    patches.remove(path);
    changed++;
  }
  for (final MapEntry(key: path, value: want) in take.entries) {
    if (patches[path] == want) continue;
    final got = await client.get(Uri.parse('$contentServer/content/v$_format/files/$want')).timeout(const Duration(minutes: 2));
    if (got.statusCode != 200 || sha256.convert(got.bodyBytes).toString() != want) continue;
    await s.writeBlob(_blobOf(want), got.bodyBytes);
    patches[path] = want;
    changed++;
  }
  await s.writeJson(_patchesKey, patches);
  await s.writeJson(_checkedKey, now);
  await s.writeJson(_checkedBuildKey, appBuild);
  return changed;
}

/// The site's files this build should use instead of its own (path → sha256).
///
/// A file replaces the bundled one only when the site says it is a later
/// version of it: its `replaces` lists the hashes of the versions before it
/// (tool/content_site/build.py). Otherwise the site is behind this build (it
/// was published before the release) and its copy would put older text back.
/// A file the build doesn't have is new, and taken unless the site is behind
/// on files the build does have: then it is a leftover the build dropped.
Future<Map<String, String>> _newerThanBundled(Map<String, Object?> files, _BundledShas bundled) async {
  final take = <String, String>{};
  final added = <String, String>{};
  var behind = false;
  for (final MapEntry(key: path, value: info) in files.entries) {
    final want = (info as Map)['sha256'] as String;
    final mine = await bundled.of(path);
    if (mine == null) {
      added[path] = want;
    } else if (mine == want) {
      continue; // The app ships this version.
    } else if (info['replaces'] case final List earlier when earlier.contains(mine)) {
      take[path] = want;
    } else {
      behind = true;
    }
  }
  if (!behind) take.addAll(added);
  return take;
}

/// The hash of each bundled asset, worked out once per app build.
class _BundledShas {
  final Storage s;
  final String key;
  final Map<String, String> known;
  _BundledShas(this.s, String appBuild)
      : key = '$_bundledKey:$appBuild',
        known = s.readJson('$_bundledKey:$appBuild', (j) => (j as Map).cast<String, String>()) ?? <String, String>{};

  Future<String?> of(String path) async {
    if (known[path] case final sha?) return sha;
    try {
      final data = await rootBundle.load(path);
      final sha = sha256.convert(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)).toString();
      known[path] = sha;
      await s.writeJson(key, known);
      return sha;
    } catch (_) {
      return null; // Not in this build: a file added since.
    }
  }
}

/// The interlinear index: each work's bundle and its hash.
Future<Map<String, Map<String, Object?>>?> fetchInterlinearIndex(http.Client client, String server) async {
  final res = await client.get(Uri.parse('${server.replaceAll(RegExp(r'/+$'), '')}/interlinear/v1/index.json')).timeout(const Duration(seconds: 20));
  if (res.statusCode != 200) return null;
  final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
  return {for (final MapEntry(:key, :value) in (j['works'] as Map).cast<String, Object?>().entries) key: (value as Map).cast<String, Object?>()};
}

/// Saved per work: which bundle (by hash) its saved units came from.
String interlinearShaKey(String spine, String work) => 'interlinearSha:$spine/$work';

Future<int> _updateInterlinear(Storage s, http.Client client) async {
  final saved = s.jsonKeys.where((k) => k.startsWith('interlinearSha:')).toList();
  if (saved.isEmpty) return 0;
  final index = await fetchInterlinearIndex(client, contentServer);
  if (index == null) return 0;
  var changed = 0;
  for (final key in saved) {
    final id = key.substring('interlinearSha:'.length);
    final have = s.readJson(key, (j) => j as String);
    if (index[id]?['sha256'] == have) continue;
    final work = id.substring(id.indexOf('/') + 1);
    for (final b in s.blobKeys.where((k) => k.startsWith('interlinear:$work:')).toList()) {
      await s.deleteBlob(b);
    }
    await s.deleteJson(key);
    changed++;
  }
  return changed;
}

/// Where on the content site the printed pages are
/// (lib/features/gemara/daf_print.dart).
const dafPrintPath = 'daf/v2';

/// Saved per tractate: which bundle (by hash) its printed pages came from.
String dafPrintShaKey(String book) => 'dafPrint2Sha:$book';

/// Saved per amud: its printed page, under this and the amud.
String dafPrintBlobPrefix(String book) => 'dafPrint2:$book:';

/// Drops saved printed pages whose tractate's bundle changed on the site,
/// so the next amud opened fetches the new one.
Future<int> _updateDafPrint(Storage s, http.Client client) async {
  final saved = s.jsonKeys.where((k) => k.startsWith('dafPrint2Sha:')).toList();
  if (saved.isEmpty) return 0;
  final res = await client.get(Uri.parse('$contentServer/$dafPrintPath/index.json')).timeout(const Duration(seconds: 20));
  if (res.statusCode != 200) return 0;
  final works = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['works'] as Map?)?.cast<String, Object?>() ?? const {};
  var changed = 0;
  for (final key in saved) {
    final book = key.substring('dafPrint2Sha:'.length);
    if ((works[book] as Map?)?['sha256'] == s.readJson(key, (j) => j as String)) continue;
    for (final b in s.blobKeys.where((k) => k.startsWith(dafPrintBlobPrefix(book))).toList()) {
      await s.deleteBlob(b);
    }
    await s.deleteJson(key);
    changed++;
  }
  return changed;
}

/// This build, as [updateContent] and [Content.attach] name it.
Future<String> contentBuild() async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version}+${info.buildNumber}';
}

/// Runs [updateContent] in the background at startup; failures (offline)
/// are tried again at the next start.
Future<void> checkContentUpdates(Storage s) async {
  final client = http.Client();
  try {
    await updateContent(s, client, appBuild: await contentBuild());
  } catch (_) {
  } finally {
    client.close();
  }
}
