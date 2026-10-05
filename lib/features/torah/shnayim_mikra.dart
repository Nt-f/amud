import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';
import 'package:http/http.dart' as http;

import '../../core/analytics.dart';
import '../../core/providers.dart';

/// This week's Shnayim Mikra: the parsha of the coming Shabbat (or of the
/// next Shabbat without a holiday reading) and today's aliyah, one a day
/// from the first on Sunday to the seventh on Shabbat.
({ParshaReading reading, HDate shabbat, int aliyah})? shnayimMikraWeek(HDate hd, bool il) {
  var shabbat = hd.onOrAfter(6);
  for (var i = 0; i < 8; i++) {
    final p = getSedra(shabbat.getFullYear(), il).lookup(shabbat);
    if (!p.chag && p.parsha.isNotEmpty) {
      final r = ParshaReading.of(p.parsha);
      return r == null ? null : (reading: r, shabbat: shabbat, aliyah: hd.getDay() + 1);
    }
    shabbat = shabbat.addDays(7);
  }
  return null;
}

/// The parshiyot read on the Shabbatot of Hebrew [year], in order, with
/// the Shabbat each is read.
List<(ParshaReading, HDate)> parshiyotOfYear(int year, bool il) {
  final sedra = getSedra(year, il);
  return [
    for (var d = HDate(1, Months.tishrei, year).onOrAfter(6); d.getFullYear() == year; d = d.addDays(7))
      if (sedra.lookup(d) case final p when !p.chag && p.parsha.isNotEmpty)
        if (ParshaReading.of(p.parsha) case final r?) (r, d),
  ];
}

/// A verse with its Targum Onkelos and translation ('' where missing).
typedef MikraVerse = ({Verse at, String he, String targum, String en});

/// A downloaded parsha.
typedef MikraText = ({String parsha, List<MikraVerse> verses, String enCredit});

const _books = ['Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy'];

/// Sefaria's ref for [r]'s verses, in the Torah or in Targum Onkelos.
String sefariaRange(ParshaReading r, {bool onkelos = false}) =>
    '${onkelos ? 'Onkelos_' : ''}${_books[r.book - 1]}.${r.begin.chapter}.${r.begin.verse}-${r.end.chapter}.${r.end.verse}';

Map<String, Object?>? _version(List<int> body, String lang) {
  final j = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
  return (j['versions'] as List).cast<Map<String, Object?>>().where((v) => v['language'] == lang).firstOrNull;
}

/// The verses in [lang] of a Sefaria text response for a range starting at
/// [begin]: a list of verses within one chapter, or a list of chapters
/// across several.
@visibleForTesting
List<(Verse, String)> sefariaVerses(List<int> body, Verse begin, {String lang = 'he'}) {
  final text = _version(body, lang)?['text'];
  final chapters = text is List && text.isNotEmpty && text.first is List ? text : [text is List ? text : const []];
  return [
    for (var c = 0; c < chapters.length; c++)
      for (final (v, t) in (chapters[c] as List).indexed)
        // Paragraph marks ({פ}, {ס}) are left out; the verses are shown apart.
        ((chapter: begin.chapter + c, verse: (c == 0 ? begin.verse : 1) + v), '$t'.replaceAll(RegExp(r'\s*\{[פס]\}\s*'), ' ').trim()),
  ];
}

/// The text of a parsha with Onkelos and translation, from Sefaria
/// responses ([mikra] holds the Hebrew and English versions), gzipped for
/// storage.
@visibleForTesting
List<int> packShnayimMikra(({String parsha, Verse begin, List<int> mikra, List<int> targum}) input) {
  final targum = {for (final (v, t) in sefariaVerses(input.targum, input.begin)) v: t};
  final en = {for (final (v, t) in sefariaVerses(input.mikra, input.begin, lang: 'en')) v: t};
  final enVersion = _version(input.mikra, 'en');
  final title = '${enVersion?['versionTitle'] ?? ''}'.trim();
  final license = '${enVersion?['license'] ?? ''}'.trim();
  return GZipEncoder().encodeBytes(utf8.encode(jsonEncode({
    'parsha': input.parsha,
    'enCredit': license.isEmpty || license == 'unknown' ? title : '$title ($license)',
    'verses': [
      for (final (v, t) in sefariaVerses(input.mikra, input.begin)) [v.chapter, v.verse, t, targum[v] ?? '', en[v] ?? ''],
    ],
  })));
}

@visibleForTesting
MikraText unpackShnayimMikra(List<int> bytes) {
  final j = jsonDecode(utf8.decode(GZipDecoder().decodeBytes(bytes))) as Map<String, Object?>;
  return (
    parsha: j['parsha'] as String,
    enCredit: '${j['enCredit'] ?? ''}',
    verses: [
      for (final v in (j['verses'] as List).cast<List>())
        (at: (chapter: v[0] as int, verse: v[1] as int), he: v[2] as String, targum: v[3] as String, en: v.length > 4 ? v[4] as String : ''),
    ],
  );
}

/// Only the latest parsha is kept: one download covers the week.
const _blobKey = 'shnayim-mikra';

/// A parsha (named as in [ParshaReading.parsha], joined with "-"),
/// downloaded from Sefaria the first time.
final shnayimMikraProvider = FutureProvider.family<MikraText, String>((ref, parsha) async {
  final storage = ref.read(storageProvider);
  final stored = storage.readBlob(_blobKey);
  if (stored != null) {
    final s = await compute(unpackShnayimMikra, stored);
    if (s.parsha == parsha) return s;
  }
  final r = ParshaReading.of(parsha.split('-'))!;
  final client = http.Client();
  try {
    Future<List<int>> get(String ref, String versions) async {
      final res = await client.get(Uri.parse('https://www.sefaria.org/api/v3/texts/$ref?$versions&return_format=text_only'));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      return res.bodyBytes;
    }

    final (mikra, targum) = await (
      get(sefariaRange(r), 'version=hebrew&version=english'),
      get(sefariaRange(r, onkelos: true), 'version=hebrew'),
    ).wait;
    final packed = await compute(packShnayimMikra, (parsha: parsha, begin: r.begin, mikra: mikra, targum: targum));
    await storage.writeBlob(_blobKey, packed);
    analytics.event('shnayim_mikra_download', {'parsha': parsha});
    return compute(unpackShnayimMikra, packed);
  } finally {
    client.close();
  }
});

/// What Shnayim Mikra shows besides the siddur's text settings, which it
/// follows (layout, fonts, te'amim, nikud).
class ShnayimMikraSettings {
  /// Each verse twice, as it's read; once to read it twice by yourself.
  final bool repeatVerse;
  final bool showTargum;
  const ShnayimMikraSettings({this.repeatVerse = true, this.showTargum = true});

  ShnayimMikraSettings copyWith({bool? repeatVerse, bool? showTargum}) =>
      ShnayimMikraSettings(repeatVerse: repeatVerse ?? this.repeatVerse, showTargum: showTargum ?? this.showTargum);

  Map<String, Object?> toJson() => {'repeatVerse': repeatVerse, 'showTargum': showTargum};

  factory ShnayimMikraSettings.fromJson(Map<String, Object?> j) => ShnayimMikraSettings(
        repeatVerse: j['repeatVerse'] is bool ? j['repeatVerse'] as bool : true,
        showTargum: j['showTargum'] is bool ? j['showTargum'] as bool : true,
      );
}

class ShnayimMikraSettingsNotifier extends Notifier<ShnayimMikraSettings> {
  static const _key = 'shnayimMikraSettings';

  @override
  ShnayimMikraSettings build() =>
      ref.watch(storageProvider).readJson(_key, (j) => ShnayimMikraSettings.fromJson((j as Map).cast<String, Object?>())) ??
      const ShnayimMikraSettings();

  void update(ShnayimMikraSettings Function(ShnayimMikraSettings) f) {
    state = f(state);
    ref.read(storageProvider).writeJson(_key, state.toJson());
  }
}

final shnayimMikraSettingsProvider =
    NotifierProvider<ShnayimMikraSettingsNotifier, ShnayimMikraSettings>(ShnayimMikraSettingsNotifier.new);

/// The aliyot finished, by Hebrew year: "Noach:3", "Matot-Masei:7".
class ShnayimMikraProgress extends Notifier<Map<int, Set<String>>> {
  static const _key = 'shnayimMikraDone';

  static String entry(String parsha, int aliyah) => '$parsha:$aliyah';

  @override
  Map<int, Set<String>> build() =>
      ref.watch(storageProvider).readJson(_key, (j) => {
            for (final e in (j as Map).entries)
              ?int.tryParse('${e.key}'): {for (final x in e.value as List) '$x'},
          }) ??
      const {};

  bool done(int year, String parsha, int aliyah) => state[year]?.contains(entry(parsha, aliyah)) ?? false;

  void toggle(int year, String parsha, int aliyah) {
    final set = {...?state[year]};
    final e = entry(parsha, aliyah);
    final on = set.add(e);
    if (!on) set.remove(e);
    state = {...state, year: set};
    ref.read(storageProvider).writeJson(_key, {for (final y in state.entries) '${y.key}': [...y.value]..sort()});
    analytics.event('shnayim_mikra_mark', {'done': on});
  }
}

final shnayimMikraProgressProvider = NotifierProvider<ShnayimMikraProgress, Map<int, Set<String>>>(ShnayimMikraProgress.new);
