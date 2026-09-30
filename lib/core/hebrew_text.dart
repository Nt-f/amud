/// Helpers for Hebrew diacritics. They operate on Sefaria HTML directly:
/// tags and entities are ASCII, so removing marks never touches markup.
library;

/// Cantillation marks (te'amim), U+0591–U+05AF.
final _teamim = RegExp('[֑-֯]');

/// Paseq / legarmeh stroke, often wrapped in markup and thin spaces.
final _paseq = RegExp(r'(?:&thinsp;|\s)*(?:<(?:b|small)>)?׀(?:</(?:b|small)>)?(?:&thinsp;|\s)*');

/// Vowel points and related marks (incl. meteg, dagesh, shin/sin dots).
final _nikud = RegExp('[ְ-ׇֽֿׁׂׅׄ]');

bool hasTeamim(String s) => _teamim.hasMatch(s);
bool hasNikud(String s) => _nikud.hasMatch(s);

/// Whether the single character [c] is a te'am or a nikud mark.
bool isHebrewMark(String c) => _teamim.hasMatch(c) || _nikud.hasMatch(c);

String stripTeamim(String html) => html.replaceAll(_paseq, ' ').replaceAll(_teamim, '');
String stripNikud(String html) => html.replaceAll(_nikud, '');

/// Applies the reader's diacritics preferences.
String hebrewMarks(String html, {required bool teamim, required bool nikud}) {
  var s = html;
  if (!teamim) s = stripTeamim(s);
  if (!nikud) s = stripNikud(s);
  return s;
}

/// Hebrew numeral (gematria) for 1–999, e.g. 15 → ט״ו, 119 → קי״ט.
String hebrewNumeral(int n) {
  const ones = ['', 'א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז', 'ח', 'ט'];
  const tens = ['', 'י', 'כ', 'ל', 'מ', 'נ', 'ס', 'ע', 'פ', 'צ'];
  const hundreds = ['', 'ק', 'ר', 'ש', 'ת', 'תק', 'תר', 'תש', 'תת', 'תתק'];
  var s = hundreds[n ~/ 100];
  final r = n % 100;
  if (r == 15) {
    s += 'טו';
  } else if (r == 16) {
    s += 'טז';
  } else {
    s += tens[r ~/ 10] + ones[r % 10];
  }
  if (s.length == 1) return '$s׳';
  return '${s.substring(0, s.length - 1)}״${s.substring(s.length - 1)}';
}
