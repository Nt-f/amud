import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/content.dart';
import '../../core/providers.dart';
import '../../core/storage.dart';
import '../torah/torah_library.dart';
import 'gemara_settings.dart';
import 'gemara_text.dart';
import 'interlinear.dart';
import 'study_book.dart';

/// A tractate of the Babylonian Talmud as Sefaria names it, with its first
/// and last amud (Vilna pagination: daf N side a or b).
class Tractate {
  final String sefaria;
  final String he;
  final String seder;
  final String sederHe;
  final String first;
  final String last;
  const Tractate(this.sefaria, this.he, this.seder, this.sederHe, this.last, {this.first = '2a'});

  int get firstNumber => amudNumber(first)!;
  int get lastNumber => amudNumber(last)!;
  int get amudCount => lastNumber - firstNumber + 1;

  /// Dafim, counting a daf with only one side in this tractate.
  int get dafCount => (lastNumber + 1) ~/ 2 - (firstNumber + 1) ~/ 2 + 1;

  /// Every amud in order: 2a, 2b, 3a, …
  List<String> get amudim => [for (var n = firstNumber; n <= lastNumber; n++) amudName(n)];

  bool contains(String amud) {
    final n = amudNumber(amud);
    return n != null && n >= firstNumber && n <= lastNumber;
  }
}

/// Sefaria's Bavli, in Shas order. Shekalim is left out: the Vilna Shas
/// prints the Yerushalmi there, and Sefaria files it under Yerushalmi.
const tractates = [
  Tractate('Berakhot', 'ברכות', 'Zeraim', 'זרעים', '64a'),
  Tractate('Shabbat', 'שבת', 'Moed', 'מועד', '157b'),
  Tractate('Eruvin', 'עירובין', 'Moed', 'מועד', '105a'),
  Tractate('Pesachim', 'פסחים', 'Moed', 'מועד', '121b'),
  Tractate('Rosh Hashanah', 'ראש השנה', 'Moed', 'מועד', '35a'),
  Tractate('Yoma', 'יומא', 'Moed', 'מועד', '88a'),
  Tractate('Sukkah', 'סוכה', 'Moed', 'מועד', '56b'),
  Tractate('Beitzah', 'ביצה', 'Moed', 'מועד', '40b'),
  Tractate('Taanit', 'תענית', 'Moed', 'מועד', '31a'),
  Tractate('Megillah', 'מגילה', 'Moed', 'מועד', '32a'),
  Tractate('Moed Katan', 'מועד קטן', 'Moed', 'מועד', '29a'),
  Tractate('Chagigah', 'חגיגה', 'Moed', 'מועד', '27a'),
  Tractate('Yevamot', 'יבמות', 'Nashim', 'נשים', '122b'),
  Tractate('Ketubot', 'כתובות', 'Nashim', 'נשים', '112b'),
  Tractate('Nedarim', 'נדרים', 'Nashim', 'נשים', '91b'),
  Tractate('Nazir', 'נזיר', 'Nashim', 'נשים', '66b'),
  Tractate('Sotah', 'סוטה', 'Nashim', 'נשים', '49b'),
  Tractate('Gittin', 'גיטין', 'Nashim', 'נשים', '90b'),
  Tractate('Kiddushin', 'קידושין', 'Nashim', 'נשים', '82b'),
  Tractate('Bava Kamma', 'בבא קמא', 'Nezikin', 'נזיקין', '119b'),
  Tractate('Bava Metzia', 'בבא מציעא', 'Nezikin', 'נזיקין', '119a'),
  Tractate('Bava Batra', 'בבא בתרא', 'Nezikin', 'נזיקין', '176b'),
  Tractate('Sanhedrin', 'סנהדרין', 'Nezikin', 'נזיקין', '113b'),
  Tractate('Makkot', 'מכות', 'Nezikin', 'נזיקין', '24b'),
  Tractate('Shevuot', 'שבועות', 'Nezikin', 'נזיקין', '49b'),
  Tractate('Avodah Zarah', 'עבודה זרה', 'Nezikin', 'נזיקין', '76b'),
  Tractate('Horayot', 'הוריות', 'Nezikin', 'נזיקין', '14a'),
  Tractate('Zevachim', 'זבחים', 'Kodashim', 'קדשים', '120b'),
  Tractate('Menachot', 'מנחות', 'Kodashim', 'קדשים', '110a'),
  Tractate('Chullin', 'חולין', 'Kodashim', 'קדשים', '142a'),
  Tractate('Bekhorot', 'בכורות', 'Kodashim', 'קדשים', '61a'),
  Tractate('Arakhin', 'ערכין', 'Kodashim', 'קדשים', '34a'),
  Tractate('Temurah', 'תמורה', 'Kodashim', 'קדשים', '34a'),
  Tractate('Keritot', 'כריתות', 'Kodashim', 'קדשים', '28b'),
  Tractate('Meilah', 'מעילה', 'Kodashim', 'קדשים', '22a'),
  Tractate('Tamid', 'תמיד', 'Kodashim', 'קדשים', '33b', first: '25b'),
  Tractate('Niddah', 'נדה', 'Tahorot', 'טהרות', '73a'),
];

Tractate? tractateNamed(String name) {
  final key = name.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  for (final t in tractates) {
    if (t.sefaria.toLowerCase().replaceAll(' ', '') == key) return t;
  }
  return _hebcalNames[key];
}

/// Hebcal's spellings of tractate names (Daf Yomi), where they differ.
final _hebcalNames = <String, Tractate>{
  for (final (alias, sefaria) in const [
    ('berachot', 'Berakhot'),
    ('gitin', 'Gittin'),
    ('babakamma', 'Bava Kamma'),
    ('babametzia', 'Bava Metzia'),
    ('bababatra', 'Bava Batra'),
    ('roshhashana', 'Rosh Hashanah'),
    ('bechorot', 'Bekhorot'),
    ('arachin', 'Arakhin'),
  ])
    alias: tractates.firstWhere((t) => t.sefaria == sefaria),
};

/// "2a" → 3, "2b" → 4 (Sefaria's numbering: daf N side a = 2N-1).
int? amudNumber(String amud) {
  final m = RegExp(r'^(\d+)([ab])$').firstMatch(amud.trim().toLowerCase());
  if (m == null) return null;
  return int.parse(m.group(1)!) * 2 - (m.group(2) == 'a' ? 1 : 0);
}

String amudName(int n) => '${(n + 1) ~/ 2}${n.isOdd ? 'a' : 'b'}';

/// One unit of a study text (an amud, a Mishnah perek, a Kitzur siman):
/// what every view needs, passage by passage. Every list is indexed by the
/// same passage number (Sefaria's segmentation).
class DafText {
  /// The book's Sefaria title ("Berakhot", "Mishnah Berakhot",
  /// "Kitzur Shulchan Arukh") and the unit ("2a", "3", "12").
  final String tractate;
  final String amud;

  /// The Bavli page text without vowels (Wikisource), for the printed page;
  /// empty for other texts.
  final List<String> vilna;

  /// The text to read (vowelled where the edition has vowels).
  final List<String> vocalized;

  /// The English. In the William Davidson edition (Bavli, Mishnah), <b> is
  /// the literal translation and the rest is explanation; other English is
  /// plain.
  final List<String> english;

  /// Commentaries on the passages (Rashi and Tosafot, Bartenura), in order.
  final List<Commentary> commentaries;

  /// Who made the text and the English, as Sefaria reports it ("title
  /// (license)").
  final String heCredit;
  final String enCredit;

  const DafText({
    required this.tractate,
    required this.amud,
    this.vilna = const [],
    required this.vocalized,
    required this.english,
    this.commentaries = const [],
    this.heCredit = '',
    this.enCredit = '',
  });

  int get length => [vilna.length, vocalized.length, english.length].reduce((a, b) => a > b ? a : b);

  String vilnaAt(int i) => i < vilna.length ? vilna[i] : '';
  String vocalizedAt(int i) => i < vocalized.length ? vocalized[i] : vilnaAt(i);
  String englishAt(int i) => i < english.length ? english[i] : '';

  Commentary? commentary(String id) => commentaries.where((c) => c.id == id).firstOrNull;
  List<Comment> rashiAt(int i) => commentary('rashi')?.at(i) ?? const [];
  List<Comment> tosafotAt(int i) => commentary('tosafot')?.at(i) ?? const [];

  Map<String, Object?> toJson() => {
        'tractate': tractate,
        'amud': amud,
        'vilna': vilna,
        'vocalized': vocalized,
        'english': english,
        'commentaries': [for (final c in commentaries) c.toJson()],
        'heCredit': heCredit,
        'enCredit': enCredit,
      };

  factory DafText.fromJson(Map<String, Object?> j) {
    List<String> strings(Object? o) => [for (final x in (o as List? ?? const [])) '$x'];
    return DafText(
      tractate: '${j['tractate']}',
      amud: '${j['amud']}',
      vilna: strings(j['vilna']),
      vocalized: strings(j['vocalized']),
      english: strings(j['english']),
      commentaries: [for (final c in (j['commentaries'] as List? ?? const [])) Commentary.fromJson((c as Map).cast<String, Object?>())],
      heCredit: '${j['heCredit'] ?? ''}',
      enCredit: '${j['enCredit'] ?? ''}',
    );
  }
}

/// How a commentary is named and colored. [inner] picks the page's inner
/// (amber) or outer (teal) color.
typedef CommentaryInfo = ({String en, String mark, bool inner});

CommentaryInfo commentaryInfo(String id) => switch (id) {
      'rashi' => (en: 'Rashi', mark: 'רש״י', inner: true),
      'tosafot' => (en: 'Tosafot', mark: 'תוס׳', inner: false),
      'bartenura' => (en: 'Bartenura', mark: 'ברטנורא', inner: true),
      _ => (en: id, mark: id, inner: true),
    };

/// One commentary on a unit: per passage, its comments; and who translated
/// its English.
class Commentary {
  final String id;
  final List<List<Comment>> comments;
  final String credit;
  const Commentary(this.id, this.comments, {this.credit = ''});

  CommentaryInfo get info => commentaryInfo(id);
  List<Comment> at(int i) => i < comments.length ? comments[i] : const [];
  int get count => comments.fold(0, (n, c) => n + c.length);

  Map<String, Object?> toJson() => {
        'id': id,
        'comments': [for (final s in comments) [for (final c in s) c.toJson()]],
        'credit': credit,
      };

  factory Commentary.fromJson(Map<String, Object?> j) => Commentary(
        '${j['id']}',
        [
          for (final s in (j['comments'] as List? ?? const []))
            [for (final c in (s as List)) Comment.fromJson((c as Map).cast<String, Object?>())],
        ],
        credit: '${j['credit'] ?? ''}',
      );
}

/// One comment: the opening words (dibur hamatchil), the rest, and an
/// English translation where there is a published one.
class Comment {
  final String he;
  final String en;
  const Comment(this.he, this.en);

  /// "מאימתי קורין – כהנים שנטמאו…" → ("מאימתי קורין", "כהנים שנטמאו…").
  /// Opening words are in bold (Bartenura), or end at a dash or a period.
  (String, String) get split {
    final plain = he.trim();
    final bold = RegExp(r'^<b>(.*?)</b>\.?', dotAll: true).firstMatch(plain);
    if (bold != null) return (bold.group(1)!.trim(), plain.substring(bold.end).trim());
    final dash = RegExp(r'\s[–\-—]\s').firstMatch(plain);
    if (dash != null && dash.start < 120) return (plain.substring(0, dash.start).trim(), plain.substring(dash.end).trim());
    final dot = plain.indexOf('.');
    if (dot > 0 && dot < 80) return (plain.substring(0, dot + 1).trim(), plain.substring(dot + 1).trim());
    return ('', plain);
  }

  Map<String, Object?> toJson() => {'he': he, 'en': en};
  factory Comment.fromJson(Map<String, Object?> j) => Comment('${j['he'] ?? ''}', '${j['en'] ?? ''}');
}

// ------------------------------------------------------------------ Sefaria

const _davidsonHe = 'William Davidson Edition - Vocalized Aramaic';
const _davidsonEn = 'William Davidson Edition - English';
const _wikisource = 'Wikisource Talmud Bavli';
const _api = 'https://www.sefaria.org/api/v3/texts';

String _slug(String title) => title.replaceAll(' ', '_');
String _q(String version) => 'version=${Uri.encodeQueryComponent(version)}';

/// The main text of a ref (one unit or a whole book), by kind.
Uri mainUri(StudyKind kind, String ref) => Uri.parse('$_api/${Uri.encodeComponent(_slug(ref))}?${switch (kind) {
      StudyKind.bavli => '${_q('hebrew|$_wikisource')}&${_q('hebrew|$_davidsonHe')}&${_q('english|$_davidsonEn')}',
      // The Davidson English where it exists, and Sefaria's default English
      // for masechtos it doesn't cover (Avot).
      StudyKind.mishnah => '${_q('hebrew')}&${_q('english|$_davidsonEn')}&${_q('english')}',
      StudyKind.kitzur => '${_q('hebrew')}&${_q('english')}',
    }}');

Uri commentaryUri(String commentator, String ref) =>
    Uri.parse('$_api/${Uri.encodeComponent('${commentator}_on_${_slug(ref)}')}?version=hebrew&version=english|all');

/// Commentaries of a kind, by id and Sefaria name.
List<(String, String)> commentatorsOf(StudyKind kind) => switch (kind) {
      StudyKind.bavli => const [('rashi', 'Rashi'), ('tosafot', 'Tosafot')],
      StudyKind.mishnah => const [('bartenura', 'Bartenura')],
      StudyKind.kitzur => const [],
    };

List<Map<String, Object?>> _versions(Map<String, Object?> j) => ((j['versions'] as List?) ?? const []).cast<Map<String, Object?>>();

Map<String, Object?>? _byTitle(Map<String, Object?> j, String title) => _versions(j).where((v) => v['versionTitle'] == title).firstOrNull;
Map<String, Object?>? _byLang(Map<String, Object?> j, String lang) => _versions(j).where((v) => v['language'] == lang).firstOrNull;

/// A published English translation of a commentary; Sefaria's crowd-sourced
/// community translation is left out.
Map<String, Object?>? _publishedEnglish(Map<String, Object?> j) => _versions(j)
    .where((v) => v['language'] == 'en' && !'${v['versionTitle'] ?? ''}'.toLowerCase().contains('community'))
    .firstOrNull;

/// "Sefaria Community Translation (CC0)".
String _credit(Map<String, Object?>? v) {
  if (v == null || !'${v['text']}'.contains(RegExp(r'[A-Za-zא-ת]'))) return '';
  final title = '${v['versionTitle'] ?? ''}'.trim().replaceFirst(RegExp(r'\.$'), '');
  final license = '${v['license'] ?? ''}'.trim();
  return license.isEmpty || license.toLowerCase() == 'unknown' ? title : '$title ($license)';
}

List<String> _strings(Object? l) => l is List ? [for (final x in l) x is String ? x : ''] : const [];

/// Comments per passage, pairing each Hebrew comment with the English at
/// the same place.
List<List<Comment>> _comments(Object? he, Object? en) {
  final h = he is List ? he : const [];
  final e = en is List ? en : const [];
  return [
    for (var i = 0; i < h.length; i++)
      [
        for (var k = 0; k < (h[i] is List ? (h[i] as List).length : 0); k++)
          Comment('${(h[i] as List)[k]}', i < e.length && e[i] is List && k < (e[i] as List).length ? '${(e[i] as List)[k]}' : ''),
      ],
  ];
}

/// The text of one unit, from the decoded Sefaria responses for that unit
/// ([main], and per commentator id its response). For a whole book, pass
/// each version's text at the unit's index instead (see [_splitBook]).
DafText _unit({
  required StudyKind kind,
  required String book,
  required String unit,
  required Map<String, Object?> main,
  required Map<String, Map<String, Object?>> commentaries,
  Object? Function(Object? text)? pick,
}) {
  Object? at(Map<String, Object?>? v) {
    final text = v?['text'];
    return pick == null ? text : pick(text);
  }
  final he = kind == StudyKind.bavli ? _byTitle(main, _davidsonHe) : _byLang(main, 'he');
  final en = kind == StudyKind.kitzur ? _byLang(main, 'en') : _byTitle(main, _davidsonEn) ?? (kind == StudyKind.mishnah ? _byLang(main, 'en') : null);
  return DafText(
    tractate: book,
    amud: unit,
    vilna: kind == StudyKind.bavli ? _strings(at(_byTitle(main, _wikisource))) : const [],
    vocalized: _strings(at(he)),
    english: _strings(at(en)),
    commentaries: [
      for (final MapEntry(key: id, value: j) in commentaries.entries)
        Commentary(id, _comments(at(_byLang(j, 'he')), at(_publishedEnglish(j))), credit: _credit(_publishedEnglish(j))),
    ],
    heCredit: _credit(he),
    enCredit: _credit(en),
  );
}

/// One Bavli amud from Sefaria's responses, as strings. Pure (runs in an
/// isolate, and in tests).
@visibleForTesting
DafText parseDaf(({String tractate, String amud, String main, String? rashi, String? tosafot}) r) => _unit(
      kind: StudyKind.bavli,
      book: r.tractate,
      unit: r.amud,
      main: jsonDecode(r.main) as Map<String, Object?>,
      commentaries: {
        if (r.rashi != null) 'rashi': jsonDecode(r.rashi!) as Map<String, Object?>,
        if (r.tosafot != null) 'tosafot': jsonDecode(r.tosafot!) as Map<String, Object?>,
      },
    );

/// One unit from strings: main text and commentaries by id.
DafText _parseUnit(({StudyKind kind, String book, String unit, String main, Map<String, String> commentaries}) r) => _unit(
      kind: r.kind,
      book: r.book,
      unit: r.unit,
      main: jsonDecode(r.main) as Map<String, Object?>,
      commentaries: {for (final e in r.commentaries.entries) e.key: jsonDecode(e.value) as Map<String, Object?>},
    );

/// Every unit of a book from whole-book responses: each version's text is a
/// list with an entry per unit (Bavli: per amud number, from 1 = 1a).
@visibleForTesting
List<(String, List<int>)> splitBook(({StudyKind kind, String book, String main, Map<String, String> commentaries}) r) {
  final b = studyBook(r.book)!;
  final main = jsonDecode(r.main) as Map<String, Object?>;
  final comms = {for (final e in r.commentaries.entries) e.key: jsonDecode(e.value) as Map<String, Object?>};
  final out = <(String, List<int>)>[];
  for (final unit in b.units) {
    final i = r.kind == StudyKind.bavli ? amudNumber(unit)! - 1 : int.parse(unit) - 1;
    Object? pick(Object? text) => text is List && i < text.length ? text[i] : const [];
    final d = _unit(kind: r.kind, book: r.book, unit: unit, main: main, commentaries: comms, pick: pick);
    if (d.vocalized.any((s) => s.trim().isNotEmpty) || d.vilna.any((s) => s.trim().isNotEmpty)) {
      out.add((unit, _pack(d)));
    }
  }
  return out;
}

/// Saved units. The version moves when what is saved changes (v2: no
/// crowd-sourced commentary English; v3: any study text), so old copies are
/// fetched again.
const _blobPrefix = 'study3';

String dafBlobKey(String book, String unit) => '$_blobPrefix:$book:$unit';
String _blobKey(String book, String unit) => dafBlobKey(book, unit);

List<int> _pack(DafText d) => GZipEncoder().encodeBytes(utf8.encode(jsonEncode(d.toJson())));
@visibleForTesting
DafText unpackUnit(List<int> b) => _unpack(b);

DafText _unpack(List<int> b) => DafText.fromJson(jsonDecode(utf8.decode(GZipDecoder().decodeBytes(b))) as Map<String, Object?>);

Future<String?> _get(http.Client client, Uri u) async {
  final res = await client.get(u);
  if (res.statusCode != 200) return null;
  return utf8.decode(res.bodyBytes);
}

/// One unit from Sefaria, or null when Sefaria has no text for it.
Future<DafText?> fetchUnit(http.Client client, StudyKind kind, String book, String unit) async {
  final ref = '$book.$unit';
  final comms = commentatorsOf(kind);
  final results = await Future.wait([_get(client, mainUri(kind, ref)), for (final (_, name) in comms) _get(client, commentaryUri(name, ref))]);
  final main = results[0];
  if (main == null) return null;
  final d = await compute(_parseUnit, (
    kind: kind,
    book: book,
    unit: unit,
    main: main,
    commentaries: {for (var k = 0; k < comms.length; k++) if (results[k + 1] != null) comms[k].$1: results[k + 1]!},
  ));
  return d.length == 0 ? null : d;
}

/// Where a daf's video shiur will stream from: an HLS playlist per daf on
/// Cloudflare R2 ("{base}/{tractate}/{daf}/index.m3u8"). Null until the
/// streams exist; the daf tiles show a disabled video mark meanwhile.
const String? dafVideoBase = null;

Uri? dafVideoUri(String tractate, int daf) =>
    dafVideoBase == null ? null : Uri.parse('$dafVideoBase/${Uri.encodeComponent(tractate.toLowerCase().replaceAll(' ', '-'))}/$daf/index.m3u8');

/// A reference to one unit of a book, used as a provider key.
typedef DafRef = ({String tractate, String amud});

/// The Kitzur siman from the Torah tab's downloaded Kitzur, if it is there.
Future<DafText?> _kitzurFromLibrary(Ref ref, String unit) async {
  final book = await ref.read(torahBookProvider(kitzur.id).future);
  final i = int.tryParse(unit);
  if (book == null || i == null || i < 1 || i > book.length) return null;
  return DafText(
    tractate: kitzurId,
    amud: unit,
    vocalized: book.he[i - 1],
    english: i - 1 < book.en.length ? book.en[i - 1] : const [],
    heCredit: 'Torat Emet (Public Domain)',
    enCredit: book.enCredits[i - 1] ?? 'trans. Rabbi Avrohom Davis, Metsudah Publications 1996 (CC-BY)',
  );
}

/// The text of a unit: from the device when saved before, else from Sefaria
/// (and saved, so it reads offline next time).
final dafTextProvider = FutureProvider.family<DafText?, DafRef>((ref, r) async {
  final book = studyBook(r.tractate);
  if (book == null) return null;
  if (book.kind == StudyKind.kitzur) {
    final fromLibrary = await _kitzurFromLibrary(ref, r.amud);
    if (fromLibrary != null) return fromLibrary;
  }
  final storage = ref.read(storageProvider);
  final saved = storage.readBlob(_blobKey(book.id, r.amud));
  if (saved != null) {
    try {
      return await compute(_unpack, saved);
    } catch (_) {}
  }
  final client = http.Client();
  try {
    final d = await fetchUnit(client, book.kind, book.id, r.amud);
    if (d != null) await storage.writeBlob(_blobKey(book.id, r.amud), await compute(_pack, d));
    return d;
  } finally {
    client.close();
  }
});

/// The word-by-word layer for a unit, when the interlinear server has it.
final interlinearProvider = FutureProvider.family<InterlinearUnit?, DafRef>((ref, r) async {
  final book = studyBook(r.tractate);
  if (book == null || !book.views.contains(GemaraView.interlinear)) return null;
  final storage = ref.read(storageProvider);
  final key = 'interlinear:${r.tractate}:${r.amud}';
  final saved = storage.readBlob(key);
  if (saved != null) {
    try {
      return InterlinearUnit.fromJson(jsonDecode(utf8.decode(GZipDecoder().decodeBytes(saved))) as Map<String, Object?>);
    } catch (_) {}
  }
  // Watched, so changing the server in settings fetches again. Opening one
  // amud saves its whole tractate (a few MB at most), so the rest open offline.
  final base = ref.watch(interlinearServerProvider);
  final units = await _saveInterlinearWork(storage, base, book);
  return units[r.amud];
});

/// Downloads and saves a work's whole word-by-word layer, by unit. Two amudim
/// opened together share one download.
final _interlinearDownloads = <String, Future<Map<String, InterlinearUnit>>>{};

Future<Map<String, InterlinearUnit>> _saveInterlinearWork(Storage storage, String base, StudyBook book) =>
    _interlinearDownloads[book.id] ??= () async {
      final client = http.Client();
      try {
        final got = await fetchInterlinearWork(client, base, book.spine, book.id);
        if (got == null) return <String, InterlinearUnit>{};
        for (final u in got.units) {
          await storage.writeBlob('interlinear:${book.id}:${u.unit}', GZipEncoder().encodeBytes(utf8.encode(jsonEncode(u.toJson()))));
        }
        // Lets the content check drop these when the server's copy changes.
        await storage.writeJson(interlinearShaKey(book.spine, book.id), got.sha);
        return {for (final u in got.units) u.unit: u};
      } catch (_) {
        return <String, InterlinearUnit>{};
      } finally {
        client.close();
        _interlinearDownloads.remove(book.id);
      }
    }();

/// Downloads a whole book for offline reading (a request per text, not per
/// unit), reporting progress as (done, total) books.
class BookDownload extends FamilyNotifier<(int, int)?, String> {
  bool _cancel = false;

  @override
  (int, int)? build(String books) => null;

  /// [arg] is one book id, or several joined by '|' (all of Shas).
  List<StudyBook> get _books => [for (final id in arg.split('|')) ?studyBook(id)];

  Future<void> start() async {
    if (state != null) return;
    _cancel = false;
    final books = _books;
    state = (0, books.length);
    final storage = ref.read(storageProvider);
    final client = http.Client();
    try {
      for (var n = 0; n < books.length && !_cancel; n++) {
        final b = books[n];
        final comms = commentatorsOf(b.kind);
        final results = await Future.wait([
          _get(client, mainUri(b.kind, b.id)),
          for (final (_, name) in comms) _get(client, commentaryUri(name, b.id)),
        ]);
        if (results[0] != null) {
          final units = await compute(splitBook, (
            kind: b.kind,
            book: b.id,
            main: results[0]!,
            commentaries: {for (var k = 0; k < comms.length; k++) if (results[k + 1] != null) comms[k].$1: results[k + 1]!},
          ));
          for (final (unit, bytes) in units) {
            await storage.writeBlob(_blobKey(b.id, unit), bytes);
          }
        }
        // The word-by-word layer, where the server has it.
        if (b.views.contains(GemaraView.interlinear)) {
          await _saveInterlinearWork(storage, ref.read(interlinearServerProvider), b);
        }
        state = (n + 1, books.length);
        for (final one in [b.id, arg]) {
          ref.invalidate(savedUnitsProvider(one));
        }
      }
    } catch (_) {
      // Whatever was saved stays saved; the rest loads when opened.
    } finally {
      client.close();
      state = null;
      ref.invalidate(savedUnitsProvider(arg));
    }
  }

  void cancel() => _cancel = true;
}

final bookDownloadProvider = NotifierProvider.family<BookDownload, (int, int)?, String>(BookDownload.new);

/// How many units of a book (or of several, joined by '|') are saved.
final savedUnitsProvider = Provider.family<int, String>((ref, books) {
  final keys = ref.read(storageProvider).blobKeys.toSet();
  var n = 0;
  for (final id in books.split('|')) {
    final b = studyBook(id);
    if (b == null) continue;
    n += b.units.where((u) => keys.contains(_blobKey(b.id, u))).length;
  }
  return n;
});

/// Removes a book's saved units and word-by-word layer (older saved
/// versions too).
Future<void> deleteBook(WidgetRef ref, String book) async {
  final storage = ref.read(storageProvider);
  final escaped = RegExp.escape(book);
  for (final k in storage.blobKeys.toList()) {
    if (RegExp('^(gemara\\d*|study\\d*):$escaped:').hasMatch(k) || k.startsWith('interlinear:$book:')) await storage.deleteBlob(k);
  }
  ref.invalidate(savedUnitsProvider(book));
}

/// A comment placed on the words it quotes: its commentary, its place among
/// that commentary's comments on the passage, and the token range.
typedef CommentAnchor = ({String id, int index, int from, int to});

/// The comments on passage [seg] that can be placed on its words, among
/// [tokens] (the page's words or the vowelled ones; anchored separately).
List<CommentAnchor> commentAnchors(DafText d, int seg, List<String> tokens) => [
      for (final c in d.commentaries)
        for (var k = 0; k < c.at(seg).length; k++)
          if (anchorQuote(c.at(seg)[k].split.$1, tokens) case (final from, final to)) (id: c.id, index: k, from: from, to: to),
    ];
