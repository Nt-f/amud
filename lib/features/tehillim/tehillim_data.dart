import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hebcal/hebcal.dart';

/// Sefer Tehillim, bundled by tool/tehillim_sync.dart.
class Tehillim {
  /// 150 chapters of verse HTML (index 0 = Psalm 1).
  final List<List<String>> he;
  final List<List<String>> en;
  final Map<String, Object?> heVersion;
  final Map<String, Object?> enVersion;
  Tehillim(this.he, this.en, this.heVersion, this.enVersion);

  int verses(int chapter) => he[chapter - 1].length;

  static Future<Tehillim> load() async {
    final bytes = await rootBundle.load('assets/tehillim/tehillim.json.gz');
    final j = jsonDecode(utf8.decode(const GZipDecoder().decodeBytes(bytes.buffer.asUint8List()))) as Map<String, dynamic>;
    List<List<String>> chapters(String k) => [for (final c in j[k] as List) (c as List).cast<String>()];
    return Tehillim(chapters('he'), chapters('en'), (j['heVersion'] as Map).cast(), (j['enVersion'] as Map).cast());
  }
}

final tehillimProvider = FutureProvider<Tehillim>((ref) => Tehillim.load());

/// The five books of Tehillim (first and last chapter).
const tehillimBooks = [(1, 41), (42, 72), (73, 89), (90, 106), (107, 150)];

int bookOf(int chapter) => tehillimBooks.indexWhere((b) => chapter >= b.$1 && chapter <= b.$2) + 1;

/// A run of verses within one chapter; [to] null means to the end.
class Passage {
  final int chapter;
  final int from;
  final int? to;
  const Passage(this.chapter, [this.from = 1, this.to]);

  bool get whole => from == 1 && to == null;

  @override
  String toString() => whole ? '$chapter' : '$chapter:$from-${to ?? ''}';

  static Passage parse(String s) {
    final m = RegExp(r'^(\d+)(?::(\d+)-(\d*))?$').firstMatch(s.trim());
    if (m == null) throw FormatException('Bad passage $s');
    final c = int.parse(m[1]!);
    if (m[2] == null) return Passage(c);
    return Passage(c, int.parse(m[2]!), m[3]!.isEmpty ? null : int.parse(m[3]!));
  }
}

/// Something to read: a titled list of passages.
class Portion {
  final String titleEn;
  final String titleHe;
  final List<Passage> passages;
  const Portion(this.titleEn, this.titleHe, this.passages);

  static List<Passage> range(int from, int to) => [for (var c = from; c <= to; c++) Passage(c)];

  String get encoded => passages.join(',');
  static List<Passage> decode(String s) => [for (final p in s.split(',')) if (p.trim().isNotEmpty) Passage.parse(p)];

  /// "1–9", "119:1–96", "20, 6, 30"…
  String get rangeLabel {
    if (passages.isEmpty) return '';
    final whole = passages.every((p) => p.whole);
    final consecutive = whole && [for (var i = 1; i < passages.length; i++) passages[i].chapter == passages[i - 1].chapter + 1].every((b) => b);
    if (consecutive && passages.length > 1) return '${passages.first.chapter}–${passages.last.chapter}';
    if (passages.length == 1 && !passages.first.whole) {
      final p = passages.first;
      return '${p.chapter}:${p.from}–${p.to ?? ''}';
    }
    return passages.map((p) => p.whole ? '${p.chapter}' : '${p.chapter}:${p.from}–${p.to ?? ''}').join(', ');
  }
}

// --- Schedules -----------------------------------------------------------

/// Monthly cycle by day of the Hebrew month (as in Hebcal's daily Psalms);
/// days 25–26 split Psalm 119, and a 29-day month reads 140–150 on the 29th.
const _monthly = [
  (1, 9), (10, 17), (18, 22), (23, 28), (29, 34), (35, 38), (39, 43), (44, 48), (49, 54), (55, 59), //
  (60, 65), (66, 68), (69, 71), (72, 76), (77, 78), (79, 82), (83, 87), (88, 89), (90, 96), (97, 103),
  (104, 105), (106, 107), (108, 112), (113, 118), (119, 119), (119, 119), (120, 134), (135, 139), (140, 144), (145, 150),
];

Portion monthlyPortion(HDate hd) {
  final day = hd.getDate();
  final (a, b) = day == 29 && hd.daysInMonth() == 29 ? (140, 150) : _monthly[day - 1];
  final passages = switch (day) {
    25 => const [Passage(119, 1, 96)],
    26 => const [Passage(119, 97)],
    _ => Portion.range(a, b),
  };
  return Portion('Day $day of the month', 'יום ${hebrewDayHe(day)} לחודש', passages);
}

String hebrewDayHe(int d) => gematriya(d);

/// Weekly cycle, Sunday (0) … Shabbat (6).
const _weekly = [(1, 29), (30, 50), (51, 72), (73, 89), (90, 106), (107, 119), (120, 150)];
const _daysEn = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Shabbat'];
const _daysHe = ['יום ראשון', 'יום שני', 'יום שלישי', 'יום רביעי', 'יום חמישי', 'יום שישי', 'שבת קודש'];

Portion weeklyPortion(int weekday) {
  final (a, b) = _weekly[weekday];
  return Portion(_daysEn[weekday], _daysHe[weekday], Portion.range(a, b));
}

/// Shir shel Yom, the psalm of the day sung by the Levites.
const _shirShelYom = [24, 48, 82, 94, 81, 93, 92];

Portion shirShelYom(int weekday) => Portion(
      'Psalm of the day (${_daysEn[weekday]})',
      'שיר של יום (${_daysHe[weekday]})',
      [Passage(_shirShelYom[weekday]), if (weekday == 3) const Passage(95, 1, 3)],
    );

/// LeDavid Hashem Ori (Psalm 27), from Rosh Chodesh Elul through Hoshana
/// Raba, or Shemini Atzeret by some customs.
bool ledavidSeason(HDate hd, {required bool throughShminiAtzeret, required bool il}) {
  final m = hd.getMonth();
  if (m == Months.elul) return true;
  if (m != Months.tishrei) return false;
  return hd.getDate() <= (throughShminiAtzeret ? (il ? 22 : 23) : 21);
}

const ledavid = Portion('LeDavid Hashem Ori', 'לדוד ה׳ אורי', [Passage(27)]);

Portion bookPortion(int book) {
  final (a, b) = tehillimBooks[book - 1];
  return Portion('Book ${const ['One', 'Two', 'Three', 'Four', 'Five'][book - 1]}', 'ספר ${const ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי'][book - 1]}',
      Portion.range(a, b));
}

// --- Occasions ------------------------------------------------------------

/// Selections customarily said for particular needs.
final occasions = [
  Portion('For recovery of the sick', 'לרפואת חולה', [
    for (final c in const [20, 6, 9, 13, 16, 17, 18, 22, 23, 28, 30, 31, 32, 33, 37, 38, 39, 41, 49, 55, 56, 69, 86, 88, 89, 90, 91, 102, 103, 104, 107, 116, 118, 142, 143, 148]) Passage(c),
  ]),
  Portion('In times of danger / for Israel', 'בעת צרה ולשלום ישראל', [for (final c in const [20, 83, 121, 130, 142]) Passage(c)]),
  Portion('In memory (yahrzeit)', 'לעילוי נשמה', [for (final c in const [33, 16, 17, 72, 91, 104, 130]) Passage(c)]),
  Portion('Safe travel', 'לדרך צלחה', [for (final c in const [91, 121]) Passage(c)]),
  Portion('Thanksgiving', 'הודיה', [for (final c in const [100, 107, 118, 136]) Passage(c)]),
  Portion('For a shidduch', 'לזיווג הגון', [for (final c in const [32, 38, 70, 71, 121, 124]) Passage(c)]),
  Portion('Livelihood (parnassah)', 'לפרנסה', [for (final c in const [23, 145]) Passage(c)]),
  Portion('Repentance', 'לתשובה', [for (final c in const [51, 130]) Passage(c)]),
];

// --- Psalm 119 by name ----------------------------------------------------

const _alephBet = 'אבגדהוזחטיכלמנסעפצקרשת';
const _finals = {'ך': 'כ', 'ם': 'מ', 'ן': 'נ', 'ף': 'פ', 'ץ': 'צ'};

/// The Psalm 119 stanza (8 verses) for each Hebrew letter in [name], plus
/// the letters of נשמה when [neshamah] (said in memory of the departed).
Portion nameStanzas(String name, {bool neshamah = false}) {
  final letters = <String>[];
  for (final ch in (name + (neshamah ? ' נשמה' : '')).split('')) {
    final l = _finals[ch] ?? ch;
    if (_alephBet.contains(l)) letters.add(l);
  }
  return Portion(
    'Psalm 119 by name: $name',
    'קי״ט לפי השם: $name',
    [for (final l in letters) Passage(119, _alephBet.indexOf(l) * 8 + 1, _alephBet.indexOf(l) * 8 + 8)],
  );
}

String stanzaLetter(Passage p) => p.chapter == 119 && (p.from - 1) % 8 == 0 ? _alephBet[(p.from - 1) ~/ 8] : '';

// --- Text preparation -------------------------------------------------------

final _pe = RegExp(r'(?:&nbsp;|\s)*<span class="mam-spi-(?:pe|samekh)">\{[פס]\}</span>(?:<br>)?');
final _kq = RegExp(r'<span class="mam-kq"><span class="mam-kq-k">\((.*?)\)</span> <span class="mam-kq-q">\[(.*?)\]</span></span>');
final _kqTrivial = RegExp(r'<span class="mam-kq-trivial">(.*?)</span>');
final _trailingBr = RegExp(r'(<br>\s*)+$');

/// Cleans Miqra-al-pi-ha-Masorah HTML for reading: drops open/closed
/// paragraph markers and shows the qere (what is read), optionally with
/// the ketiv (what is written) in small parentheses.
String prepareVerse(String html, {bool ketiv = false}) {
  var s = html.replaceAll(_pe, '').replaceAll(_trailingBr, '');
  s = s.replaceAllMapped(_kq, (m) => ketiv ? '${m[2]} <small>(${m[1]})</small>' : m[2]!);
  s = s.replaceAllMapped(_kqTrivial, (m) => m[1]!);
  return s;
}

final _tags = RegExp(r'<[^>]*>');
final _marks = RegExp('[֑-ׇ]');

/// Plain, diacritics-free text for searching.
String searchable(String html) =>
    html.replaceAll(_tags, '').replaceAll(_marks, '').replaceAll('־', ' ').replaceAll(RegExp(r'&[a-z]+;'), ' ').toLowerCase();

class SearchHit {
  final int chapter;
  final int verse;
  final String text;
  const SearchHit(this.chapter, this.verse, this.text);
}

/// Finds verses containing [query] in Hebrew (ignoring vowels and trop)
/// or English.
List<SearchHit> searchTehillim(Tehillim t, String query, {int limit = 200}) {
  final q = searchable(query).trim();
  if (q.length < 2) return const [];
  final hebrew = RegExp('[א-ת]').hasMatch(q);
  final hits = <SearchHit>[];
  for (var c = 0; c < 150 && hits.length < limit; c++) {
    final src = hebrew ? t.he[c] : t.en[c];
    for (var v = 0; v < src.length && hits.length < limit; v++) {
      final plain = searchable(src[v]);
      if (plain.contains(q)) hits.add(SearchHit(c + 1, v + 1, hebrew ? plain : src[v]));
    }
  }
  return hits;
}
