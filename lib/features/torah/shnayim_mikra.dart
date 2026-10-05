import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';
import 'package:http/http.dart' as http;

import '../../core/analytics.dart';
import '../../core/providers.dart';
import '../../core/settings.dart';

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

/// Downloaded text: a book of the Torah, or one parsha of it.
typedef MikraText = ({String name, List<MikraVerse> verses, String enCredit});

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

/// Verses with Onkelos and translation, from Sefaria responses ([mikra] holds the Hebrew and English versions), gzipped for
/// storage.
@visibleForTesting
List<int> packShnayimMikra(({String name, Verse begin, List<int> mikra, List<int> targum}) input) {
  final targum = {for (final (v, t) in sefariaVerses(input.targum, input.begin)) v: t};
  final en = {for (final (v, t) in sefariaVerses(input.mikra, input.begin, lang: 'en')) v: t};
  final enVersion = _version(input.mikra, 'en');
  final title = '${enVersion?['versionTitle'] ?? ''}'.trim();
  final license = '${enVersion?['license'] ?? ''}'.trim();
  return GZipEncoder().encodeBytes(utf8.encode(jsonEncode({
    'name': input.name,
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
    name: j['name'] as String,
    enCredit: '${j['enCredit'] ?? ''}',
    verses: [
      for (final v in (j['verses'] as List).cast<List>())
        (at: (chapter: v[0] as int, verse: v[1] as int), he: v[2] as String, targum: v[3] as String, en: v.length > 4 ? v[4] as String : ''),
    ],
  );
}

String _bookKey(int book) => 'shnayim-mikra:$book';

/// The five books with Onkelos and English, downloaded from Sefaria all at
/// once the first time and kept, so every parsha works offline after that.
typedef ChumashState = ({Set<int> have, int bytes, bool busy, bool failed});

class ChumashDownload extends Notifier<ChumashState> {
  Future<void>? _running;

  @override
  ChumashState build() {
    final storage = ref.watch(storageProvider);
    var bytes = 0;
    final have = <int>{};
    for (var b = 1; b <= 5; b++) {
      if (storage.readBlob(_bookKey(b)) case final blob?) {
        have.add(b);
        bytes += blob.length;
      }
    }
    return (have: have, bytes: bytes, busy: false, failed: false);
  }

  bool get complete => state.have.length == 5;

  /// Downloads the books not yet kept, [first] first, so a reader waiting
  /// for it opens as soon as it's in; one download at a time.
  Future<void> downloadAll({int first = 1}) => _running ??= _download(first).whenComplete(() => _running = null);

  Future<void> _download(int first) async {
    // Called while a reader's text is first loading: change state after.
    await Future<void>.delayed(Duration.zero);
    final storage = ref.read(storageProvider);
    state = (have: state.have, bytes: state.bytes, busy: true, failed: false);
    analytics.event('shnayim_mikra_download', {'status': 'start'});
    final client = http.Client();
    try {
      Future<List<int>> get(String ref, String versions) async {
        final res = await client.get(Uri.parse('https://www.sefaria.org/api/v3/texts/$ref?$versions&return_format=text_only'));
        if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
        return res.bodyBytes;
      }

      for (final b in [first, for (var b = 1; b <= 5; b++) if (b != first) b]) {
        if (state.have.contains(b)) continue;
        final (mikra, targum) = await (
          get(_books[b - 1], 'version=hebrew&version=english'),
          get('Onkelos_${_books[b - 1]}', 'version=hebrew'),
        ).wait;
        final packed = await compute(packShnayimMikra, (name: _books[b - 1], begin: (chapter: 1, verse: 1), mikra: mikra, targum: targum));
        await storage.writeBlob(_bookKey(b), packed);
        ref.invalidate(chumashBookProvider(b));
        state = (have: {...state.have, b}, bytes: state.bytes + packed.length, busy: true, failed: false);
      }
      state = (have: state.have, bytes: state.bytes, busy: false, failed: false);
      analytics.event('shnayim_mikra_download', {'status': 'done', 'kb': state.bytes ~/ 1024});
    } catch (e) {
      state = (have: state.have, bytes: state.bytes, busy: false, failed: true);
      analytics.event('shnayim_mikra_download', {'status': 'failed', 'error': e.runtimeType.toString()});
      rethrow;
    } finally {
      client.close();
    }
  }
}

final chumashDownloadProvider = NotifierProvider<ChumashDownload, ChumashState>(ChumashDownload.new);

/// One book (1 = Bereshit), downloading the Chumash first if needed.
/// Invalidate the family to retry after a failed download.
final chumashBookProvider = FutureProvider.family<MikraText, int>((ref, book) async {
  var blob = ref.read(storageProvider).readBlob(_bookKey(book));
  if (blob == null) {
    await ref.read(chumashDownloadProvider.notifier).downloadAll(first: book);
    blob = ref.read(storageProvider).readBlob(_bookKey(book));
    if (blob == null) throw StateError('${_books[book - 1]} was not downloaded');
  }
  return compute(unpackShnayimMikra, blob);
});

/// A parsha's verses (named as in [ParshaReading.parsha], joined with "-").
final shnayimMikraProvider = FutureProvider.family<MikraText, String>((ref, parsha) async {
  final r = ParshaReading.of(parsha.split('-'))!;
  final book = await ref.watch(chumashBookProvider(r.book).future);
  int key(Verse v) => v.chapter * 1000 + v.verse;
  return (
    name: parsha,
    enCredit: book.enCredit,
    verses: [for (final v in book.verses) if (key(v.at) >= key(r.begin) && key(v.at) <= key(r.end)) v],
  );
});

/// How Shnayim Mikra is shown. Its text style follows the siddur's until
/// [ownStyle] is turned on; then it has its own, starting from the
/// siddur's, and changing either leaves the other alone.
class ShnayimMikraSettings {
  /// Each verse twice, as it's read; once to read it twice by yourself.
  final bool repeatVerse;
  final bool showTargum;
  final bool ownStyle;

  /// The own style; null where it hasn't been set (the siddur's is used).
  final TextLayout? layout;
  final String? hebrewFont;
  final String? latinFont;
  final double? textScale;
  final bool? showTeamim;
  final bool? showNikud;
  final bool? highlightToday;

  const ShnayimMikraSettings({
    this.repeatVerse = true,
    this.showTargum = true,
    this.ownStyle = false,
    this.layout,
    this.hebrewFont,
    this.latinFont,
    this.textScale,
    this.showTeamim,
    this.showNikud,
    this.highlightToday,
  });

  ShnayimMikraSettings copyWith({
    bool? repeatVerse,
    bool? showTargum,
    bool? ownStyle,
    TextLayout? layout,
    String? hebrewFont,
    String? Function()? latinFont,
    double? textScale,
    bool? showTeamim,
    bool? showNikud,
    bool? highlightToday,
  }) =>
      ShnayimMikraSettings(
        repeatVerse: repeatVerse ?? this.repeatVerse,
        showTargum: showTargum ?? this.showTargum,
        ownStyle: ownStyle ?? this.ownStyle,
        layout: layout ?? this.layout,
        hebrewFont: hebrewFont ?? this.hebrewFont,
        latinFont: latinFont != null ? latinFont() : this.latinFont,
        textScale: textScale ?? this.textScale,
        showTeamim: showTeamim ?? this.showTeamim,
        showNikud: showNikud ?? this.showNikud,
        highlightToday: highlightToday ?? this.highlightToday,
      );

  /// Starts an own style from the siddur's current one.
  ShnayimMikraSettings startOwnStyle(AppSettings s) => copyWith(
        ownStyle: true,
        layout: layout ?? s.layout,
        hebrewFont: hebrewFont ?? s.hebrewFont,
        latinFont: () => latinFont ?? s.latinFont,
        textScale: textScale ?? s.textScale,
        showTeamim: showTeamim ?? s.showTeamim,
        showNikud: showNikud ?? s.showNikud,
        highlightToday: highlightToday ?? s.highlightToday,
      );

  /// The style to read with: the siddur's, or the own one.
  MikraStyle style(AppSettings s) => ownStyle
      ? (
          layout: layout ?? s.layout,
          hebrewFont: hebrewFont ?? s.hebrewFont,
          latinFont: latinFont ?? s.latinFont,
          textScale: textScale ?? s.textScale,
          showTeamim: showTeamim ?? s.showTeamim,
          showNikud: showNikud ?? s.showNikud,
          highlightToday: highlightToday ?? s.highlightToday,
        )
      : (
          layout: s.layout,
          hebrewFont: s.hebrewFont,
          latinFont: s.latinFont,
          textScale: s.textScale,
          showTeamim: s.showTeamim,
          showNikud: s.showNikud,
          highlightToday: s.highlightToday,
        );

  Map<String, Object?> toJson() => {
        'repeatVerse': repeatVerse,
        'showTargum': showTargum,
        'ownStyle': ownStyle,
        'layout': layout?.name,
        'hebrewFont': hebrewFont,
        'latinFont': latinFont,
        'textScale': textScale,
        'showTeamim': showTeamim,
        'showNikud': showNikud,
        'highlightToday': highlightToday,
      };

  factory ShnayimMikraSettings.fromJson(Map<String, Object?> j) {
    bool? flag(String k) => j[k] is bool ? j[k] as bool : null;
    return ShnayimMikraSettings(
      repeatVerse: flag('repeatVerse') ?? true,
      showTargum: flag('showTargum') ?? true,
      ownStyle: flag('ownStyle') ?? false,
      layout: TextLayout.values.asNameMap()[j['layout']],
      hebrewFont: j['hebrewFont'] is String ? j['hebrewFont'] as String : null,
      latinFont: j['latinFont'] is String ? j['latinFont'] as String : null,
      textScale: j['textScale'] is num ? (j['textScale'] as num).toDouble() : null,
      showTeamim: flag('showTeamim'),
      showNikud: flag('showNikud'),
      highlightToday: flag('highlightToday'),
    );
  }
}

typedef MikraStyle = ({
  TextLayout layout,
  String hebrewFont,
  String? latinFont,
  double textScale,
  bool showTeamim,
  bool showNikud,
  bool highlightToday,
});

/// The text style Shnayim Mikra reads with.
final mikraStyleProvider = Provider<MikraStyle>((ref) => ref.watch(shnayimMikraSettingsProvider).style(ref.watch(settingsProvider)));

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
