import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../core/analytics.dart';

/// A downloadable text in the Torah tab. Texts are fetched from Sefaria on
/// request (nothing here is bundled) and kept for offline reading.
class TorahWork {
  final String id;
  final String en;
  final String he;

  /// Sefaria index title; null while the work is not available yet.
  final String? sefariaTitle;

  /// Approximate download size, shown before downloading.
  final int estimatedBytes;
  const TorahWork(this.id, this.en, this.he, {this.sefariaTitle, this.estimatedBytes = 0});

  bool get available => sefariaTitle != null;
}

class TorahCategory {
  final String id;
  final String en;
  final String he;
  final IconData icon;
  final List<TorahWork> works;
  const TorahCategory(this.id, this.en, this.he, this.icon, this.works);

  bool get available => works.any((w) => w.available);
  List<TorahWork> get availableWorks => [for (final w in works) if (w.available) w];
}

const kitzur = TorahWork('kitzur', 'Kitzur Shulchan Aruch', 'קיצור שולחן ערוך',
    sefariaTitle: 'Kitzur_Shulchan_Arukh', estimatedBytes: 1050000);

const torahCategories = [
  TorahCategory('chumash', 'Chumash', 'חומש', Icons.auto_stories_outlined, [
    TorahWork('chumash', 'Chumash', 'חומש'),
    TorahWork('rashi', 'Rashi', 'רש״י'),
  ]),
  TorahCategory('nach', "Nach", 'נ״ך', Icons.menu_book_outlined, [TorahWork('nach', 'Nevi\'im & Ketuvim', 'נביאים וכתובים')]),
  TorahCategory('mishnah', 'Mishnah', 'משנה', Icons.format_list_numbered, [TorahWork('mishnah', 'Mishnah', 'משנה')]),
  TorahCategory('gemara', 'Gemara', 'גמרא', Icons.library_books_outlined, [TorahWork('bavli', 'Talmud Bavli', 'תלמוד בבלי')]),
  TorahCategory('halacha', 'Halacha', 'הלכה', Icons.gavel_outlined, [
    kitzur,
    TorahWork('mb', 'Mishnah Berurah', 'משנה ברורה'),
    TorahWork('sa', 'Shulchan Aruch', 'שולחן ערוך'),
    TorahWork('rambam', 'Mishneh Torah', 'משנה תורה'),
  ]),
  TorahCategory('mussar', 'Mussar', 'מוסר', Icons.self_improvement, [TorahWork('mussar', 'Mussar', 'מוסר')]),
  TorahCategory('chassidus', 'Chassidus', 'חסידות', Icons.local_fire_department_outlined, [TorahWork('chassidus', 'Chassidus', 'חסידות')]),
];

TorahCategory? torahCategory(String id) => torahCategories.where((c) => c.id == id).firstOrNull;
TorahWork? torahWork(String id) => torahCategories.expand((c) => c.works).where((w) => w.id == id).firstOrNull;

/// "≈ 1.1 MB"
String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// A downloaded book: chapters (simanim) of paragraphs (se'ifim).
class TorahBook {
  final List<String> titlesEn;
  final List<String> titlesHe;
  final List<List<String>> he;
  final List<List<String>> en;

  /// Translator credit for chapters whose English comes from another
  /// translation than the book's main one (by chapter index).
  final Map<int, String> enCredits;
  const TorahBook({required this.titlesEn, required this.titlesHe, required this.he, required this.en, this.enCredits = const {}});

  int get length => he.length;

  static TorahBook fromJson(Map<String, Object?> j) {
    List<List<String>> chapters(Object? o) => [for (final c in (o as List)) [for (final p in (c as List)) '$p']];
    return TorahBook(
      titlesEn: (j['titlesEn'] as List).cast<String>(),
      titlesHe: (j['titlesHe'] as List).cast<String>(),
      he: chapters(j['he']),
      en: chapters(j['en']),
      enCredits: {for (final e in ((j['enCredits'] as Map?) ?? const {}).entries) int.parse('${e.key}'): '${e.value}'},
    );
  }
}

sealed class DownloadState {
  const DownloadState();
}

class NotDownloaded extends DownloadState {
  const NotDownloaded();
}

class Downloading extends DownloadState {
  final int received;
  const Downloading(this.received);
}

class Downloaded extends DownloadState {
  final int bytes;
  const Downloaded(this.bytes);
}

class DownloadFailed extends DownloadState {
  final String error;
  const DownloadFailed(this.error);
}

String _blobKey(TorahWork w) => 'torah:${w.id}';

/// Download state of every available work.
class TorahLibrary extends Notifier<Map<String, DownloadState>> {
  @override
  Map<String, DownloadState> build() {
    final storage = ref.watch(storageProvider);
    return {
      for (final c in torahCategories)
        for (final w in c.availableWorks)
          w.id: switch (storage.readBlob(_blobKey(w))) {
            final b? => Downloaded(b.length),
            null => const NotDownloaded(),
          },
    };
  }

  DownloadState of(TorahWork w) => state[w.id] ?? const NotDownloaded();

  Future<void> downloadAll(Iterable<TorahWork> works) async {
    for (final w in works) {
      if (state[w.id] is! Downloaded) await download(w);
    }
  }

  Future<void> download(TorahWork w) async {
    if (!w.available || state[w.id] is Downloading) return;
    state = {...state, w.id: const Downloading(0)};
    analytics.event('torah_download', {'work': w.id, 'status': 'start'});
    final took = Stopwatch()..start();
    final client = http.Client();
    try {
      final uri = Uri.parse('https://www.sefaria.org/api/v3/texts/${w.sefariaTitle}'
          '?version=hebrew&version=english&return_format=text_only');
      final res = await client.send(http.Request('GET', uri));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final bytes = <int>[];
      await for (final chunk in res.stream) {
        bytes.addAll(chunk);
        state = {...state, w.id: Downloading(bytes.length)};
      }
      // Chapters the main translation skips (Kitzur siman 32) come from
      // another English version, if one is allowed by the license setting.
      final fills = <int, EnglishFill>{};
      final openOnly = ref.read(settingsProvider).openLicensesOnly;
      for (final i in await compute(chaptersMissingEnglish, bytes)) {
        final fill = await _fetchEnglish(client, w, i, openOnly: openOnly);
        if (fill != null) fills[i] = fill;
      }
      final packed = await compute(packSefariaText, (body: bytes, fills: fills));
      await ref.read(storageProvider).writeBlob(_blobKey(w), packed);
      ref.invalidate(torahBookProvider(w.id));
      state = {...state, w.id: Downloaded(packed.length)};
      analytics.event('torah_download', {'work': w.id, 'status': 'done', 'kb': packed.length ~/ 1024, 'seconds': took.elapsed.inSeconds});
    } catch (e) {
      state = {...state, w.id: DownloadFailed('$e')};
      analytics.event('torah_download', {'work': w.id, 'status': 'failed', 'error': e.runtimeType.toString()});
    } finally {
      client.close();
    }
  }

  Future<EnglishFill?> _fetchEnglish(http.Client client, TorahWork w, int chapter, {required bool openOnly}) async {
    try {
      final res = await client.get(Uri.parse('https://www.sefaria.org/api/v3/texts/${w.sefariaTitle}.${chapter + 1}'
          '?version=english|all&return_format=text_only'));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
      for (final v in (j['versions'] as List).cast<Map<String, Object?>>()) {
        final text = [for (final p in (v['text'] as List? ?? const [])) '$p'];
        final license = '${v['license'] ?? ''}';
        if (text.every((p) => p.trim().isEmpty) || (openOnly && !_openLicense(license))) continue;
        final title = '${v['versionTitle'] ?? ''}'.trim().replaceFirst(RegExp(r'\.$'), '');
        return (text: text, credit: license.isEmpty || license == 'unknown' ? title : '$title ($license)');
      }
    } catch (_) {}
    return null;
  }

  Future<void> delete(TorahWork w) async {
    await ref.read(storageProvider).deleteBlob(_blobKey(w));
    ref.invalidate(torahBookProvider(w.id));
    state = {...state, w.id: const NotDownloaded()};
    analytics.event('torah_delete', {'work': w.id});
  }
}

final torahLibraryProvider = NotifierProvider<TorahLibrary, Map<String, DownloadState>>(TorahLibrary.new);

bool _openLicense(String license) =>
    const {'public domain', 'cc0', 'cc-by', 'cc-by-sa', 'cc-by-nc', 'cc-by-nc-sa'}.contains(license.toLowerCase().trim());

/// English for one chapter from another translation, with its credit.
typedef EnglishFill = ({List<String> text, String credit});

List<Object?> _versionText(Map<String, Object?> j, String lang) =>
    (j['versions'] as List).cast<Map<String, Object?>>().where((v) => v['language'] == lang).firstOrNull?['text'] as List? ?? const [];

/// Chapters (by index) that have Hebrew but no English in Sefaria's
/// response.
List<int> chaptersMissingEnglish(List<int> body) {
  final j = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
  final he = _versionText(j, 'he');
  final en = _versionText(j, 'en');
  bool empty(Object? c) => c is! List || c.every((p) => '$p'.trim().isEmpty);
  return [for (var i = 0; i < he.length; i++) if (!empty(he[i]) && (i >= en.length || empty(en[i]))) i];
}

/// Keeps only what the reader needs from Sefaria's response, fills in
/// missing English chapters from [fills], and gzips it.
@visibleForTesting
List<int> packSefariaText(({List<int> body, Map<int, EnglishFill> fills}) input) {
  final j = jsonDecode(utf8.decode(input.body)) as Map<String, Object?>;
  final he = _versionText(j, 'he');
  final en = [..._versionText(j, 'en')];
  for (final MapEntry(key: i, value: f) in input.fills.entries) {
    while (en.length <= i) {
      en.add(const <String>[]);
    }
    en[i] = f.text;
  }
  // Chapter titles come as alt titles: "[סימן א] דיני השכמת הבקר",
  // "Chapter 1 Laws Upon Awakening in the Morning".
  final alts = (j['alts'] as List?) ?? const [];
  String alt(int i, String lang) {
    if (i >= alts.length) return '';
    final a = alts[i];
    final first = a is List && a.isNotEmpty ? a.first : null;
    final t = first is Map ? first[lang] : null;
    return (t is List && t.isNotEmpty ? '${t.first}' : '').trim();
  }

  final out = {
    'titlesHe': [for (var i = 0; i < he.length; i++) alt(i, 'he').replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), '')],
    'titlesEn': [for (var i = 0; i < he.length; i++) alt(i, 'en').replaceFirst(RegExp(r'^Chapter \d+\s*'), '')],
    'he': he,
    'en': en,
    'enCredits': {for (final e in input.fills.entries) '${e.key}': e.value.credit},
  };
  return GZipEncoder().encodeBytes(utf8.encode(jsonEncode(out)));
}

@visibleForTesting
TorahBook unpackTorahBook(List<int> bytes) =>
    TorahBook.fromJson(jsonDecode(utf8.decode(GZipDecoder().decodeBytes(bytes))) as Map<String, Object?>);

/// The downloaded text of a work, or null when it isn't downloaded.
final torahBookProvider = FutureProvider.family<TorahBook?, String>((ref, id) async {
  final bytes = ref.read(storageProvider).readBlob('torah:$id');
  if (bytes == null) return null;
  return compute(unpackTorahBook, bytes);
});
