import 'package:siddur_engine/siddur_engine.dart';

import '../../core/hebrew_text.dart';
import '../../core/typeset/type_scale.dart';
import 'reading_marks.dart';

/// Lines a printed siddur sets apart, by their opening words (letters
/// only), with the most words such a line has: a longer paragraph that
/// merely starts the same way is ordinary text.
/// The Shema's first verse (see [ParagraphRole.proclamation]).
const _proclamation = ('שמע ישראל ה אלהינו ה אחד', 8);

const _keystones = [
  ('ברכו את', 8), // Barchu
  ('ברוך ה המברך', 8), // and its response, spelled either way
  ('ברוך ה המבורך', 8),
  ('קדוש קדוש קדוש', 20), // Kedushah
  ('ברוך כבוד', 10),
  ('ימלך ה לעולם', 12),
];

const _undertones = ['ברוך שם כבוד מלכותו'];

/// Paragraphs that open with a large word though they don't start their
/// section: the Shema's three paragraphs, and the places the congregation
/// pauses to finish with the chazzan (עזרת אבותינו, צור ישראל).
const _paragraphStarts = [
  'ואהבת את ה אלהיך',
  'והיה אם שמע תשמעו',
  'ויאמר ה אל משה לאמר דבר אל בני ישראל ואמרת',
  'עזרת אבותינו',
  'צור ישראל קומה',
  'אמת ואמונה כל זאת',
  'השכיבנו',
  'ויברך דויד',
  'ויברך דוד',
  'אתה הוא ה לבדך',
  'ויושע ה ביום ההוא',
  'על כן נקוה לך',
  ..._hallel,
];

/// Hallel's paragraphs, which some versions print a whole psalm to a
/// line: where half Hallel resumes (ה זכרנו, מה אשיב) and the verses of
/// Psalm 118 that are said responsively or repeated.
const _hallel = [
  'לא לנו ה לא לנו',
  'ה זכרנו יברך',
  'אהבתי כי ישמע',
  'מה אשיב',
  'מן המצר קראתי',
  'אודך כי עניתני',
  'אנא ה הושיעה נא',
  'ברוך הבא בשם ה',
  'אל ה ויאר לנו',
  'אלי אתה ואודך',
];

/// A verse said before a prayer rather than as its opening (the Amidah's
/// "אדני שפתי תפתח", said with feet together): it takes no large word,
/// and the line after it opens the section instead.
const _preambles = ['אדני שפתי תפתח'];
const _responses = ['אמן יהא שמה רבא', 'יהא שמה רבא'];

/// A blessing's closing line said on its own ("ברוך אתה ה׳ מגן אברהם").
const _blessing = ('ברוך אתה', 16);

final _letters = Expando<String>('hebrewLetters');

/// A segment's Hebrew as bare words: no markup, vowels, te'amim or
/// punctuation, and the divine name however it's spelled (יהוה, ה׳, ד׳,
/// יי) as ה. Cached on the segment.
String hebrewWords(Segment s) => _letters[s] ??= normalizeHebrewWords(stripHtml(s.html));

final _name = RegExp(r'(?<=^| )(?:יהוה|ידוד|יי|ד)(?= |$)');

String normalizeHebrewWords(String text) => stripTeamim(stripNikud(text))
    .replaceAll('־', ' ')
    .replaceAll(RegExp(r'[^א-ת\s]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .replaceAll(_name, 'ה');

bool _leads(String words, String prefix, int maxWords) =>
    words.startsWith(prefix) && words.split(' ').length <= maxWords;

String _words(SegmentItem item) {
  final he = item.he?.segment;
  return he != null && he.hebrew ? hebrewWords(he) : '';
}

final _splitters = [for (final p in _paragraphStarts) _phrase(p)];

/// A pattern matching [words] (as [normalizeHebrewWords] gives them) in
/// pointed HTML: vowels and te'amim after any letter, tags and maqaf
/// between words, the divine name in any of its spellings. It matches
/// only at the start of a verse, after a full stop, sof pasuk or verse
/// number.
RegExp _phrase(String words) {
  const marks = r'[֑-ׇ]*';
  const gap = r'(?:\s|&nbsp;|&thinsp;|־|׀|<[^>]*>)+';
  String letters(String w) => [for (final c in w.split('')) '$c$marks'].join();
  final name = "(?:${letters('יהוה')}|${letters('ידוד')}|${letters('יי')}|[הד]$marks['׳])";
  final body = [for (final w in words.split(' ')) w == 'ה' ? name : letters(w)].join(gap);
  return RegExp(r'(?<=(?:[.:׃]|</sup>)(?:\s|<[^>]*>)*)' '$body' r'(?![א-ת])');
}

final _leadingVerse = RegExp(r'<sup class="verse">[^<]*</sup>\s*$');

/// Splits a line's HTML where a paragraph in [_paragraphStarts] begins
/// inside it (a psalm printed whole, the Shema in one line). Each piece
/// after the first starts a paragraph, its verse number with it.
List<String> splitParagraphs(String html) {
  final cuts = <int>{};
  for (final r in _splitters) {
    for (final m in r.allMatches(html)) {
      final before = _leadingVerse.firstMatch(html.substring(0, m.start));
      final cut = before?.start ?? m.start;
      // Already the start of the line.
      if (html.substring(0, cut).replaceAll(RegExp(r'<[^>]*>'), '').trim().isEmpty) continue;
      cuts.add(cut);
    }
  }
  if (cuts.isEmpty) return [html];
  final at = cuts.toList()..sort();
  return [
    for (var i = 0; i <= at.length; i++) html.substring(i == 0 ? 0 : at[i - 1], i == at.length ? html.length : at[i]),
  ];
}

/// See [_preambles].
bool isPreamble(SegmentItem item) {
  final words = _words(item);
  return words.isNotEmpty && _preambles.any(words.startsWith);
}

/// Said in an undertone, whether or not the corpus tags it so.
bool isUndertone(SegmentItem item) {
  if (item.voice == 'undertone') return true;
  final words = _words(item);
  return words.isNotEmpty && _undertones.any(words.startsWith);
}

/// How the reader sets [item] (see [ParagraphRole]). The corpus's own
/// tags (who says it, in what voice) come first; the words decide the
/// rest.
ParagraphRole paragraphRole(SegmentItem item, {required bool opening}) {
  switch (item.kind) {
    case SegmentKind.instruction:
      return ParagraphRole.instruction;
    case SegmentKind.note:
      return ParagraphRole.note;
    case SegmentKind.speaker:
      return ParagraphRole.speaker;
    case SegmentKind.prayer:
      break;
  }
  if (isUndertone(item)) return ParagraphRole.undertone;
  if (item.option) return ParagraphRole.option;
  final words = _words(item);
  if (_leads(words, _proclamation.$1, _proclamation.$2)) return ParagraphRole.proclamation;
  if (words.isNotEmpty && _keystones.any((k) => _leads(words, k.$1, k.$2))) return ParagraphRole.keystone;
  if (item.chazarah) return ParagraphRole.chazarah;
  if (isResponse(item.role) || _responses.any(words.startsWith)) return ParagraphRole.response;
  if (opening || _paragraphStarts.any(words.startsWith)) return ParagraphRole.opening;
  if (_leads(words, _blessing.$1, _blessing.$2)) return ParagraphRole.blessing;
  return ParagraphRole.body;
}

final _verseLead = RegExp(r'^\s*<sup class="verse">[^<]*</sup>\s*');

/// A piece from [splitParagraphs] as its verse number (if any) and its
/// words, so the words can open large and the number stay small.
(String, String) splitLeadingVerse(String piece) {
  final m = _verseLead.firstMatch(piece);
  return m == null ? ('', piece) : (m[0]!, piece.substring(m.end));
}
