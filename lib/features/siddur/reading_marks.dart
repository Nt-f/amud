import 'package:flutter/widgets.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/l10n.dart';
import '../../core/settings.dart';

// How a prayer is read (who says it, what one does), as English and Hebrew
// like any instruction: shown in the language(s) chosen for instructions and
// notes (see [conditionLabel]).
const _roles = {
  'chazzan': ('Chazzan', 'שליח ציבור'),
  'congregation': ('Cong.', 'קהל'),
  'congregation_then_chazzan': ('Cong., then chazzan', 'קהל, ואחריו שליח הציבור'),
  'chazzan_then_congregation': ('Chazzan, then cong.', 'שליח הציבור, ואחריו הקהל'),
  'together': ('Together with the chazzan', 'יחד עם שליח הציבור'),
  'responsive': ('Responsively', 'בקריאה לסירוגין'),
  'kohanim': ('Kohanim', 'כהנים'),
  'mourner': ('Mourner', 'אבל'),
  'oleh': ('The one called up', 'העולה לתורה'),
  'head_of_household': ('Head of household', 'בעל הבית'),
};

const _gestures = {
  'stand': ('Stand', 'עומדים'),
  'sit': ('Sit', 'יושבים'),
  'bow_full': ('Bow fully', 'כורעים'),
  'knees_bend': ('Bend the knees', 'כורעים ברכיים'),
  'rise_on_toes': ('Rise on toes', 'עולים על קצות האצבעות'),
  'feet_together': ('Feet together', 'רגליים צמודות'),
  'three_steps_back': ('Three steps back', 'שלוש פסיעות לאחור'),
  'three_steps_forward': ('Three steps forward', 'שלוש פסיעות לפנים'),
  'cover_eyes': ('Cover the eyes', 'מכסים את העיניים'),
  'kiss_tzitzit': ('Kiss the tzitzit', 'מנשקים את הציצית'),
  'gather_tzitzit': ('Gather the tzitzit', 'אוספים את הציציות'),
  'touch_tefillin': ('Touch the tefillin', 'נוגעים בתפילין'),
  'head_down': ('Head down', 'מרכינים ראש'),
  'face_ark': ('Face the ark', 'פונים לארון הקודש'),
  'ark_open': ('Ark opened', 'ארון הקודש פתוח'),
  'ark_close': ('Ark closed', 'ארון הקודש סגור'),
  'hold_torah': ('Hold the Torah', 'אוחזים את ספר התורה'),
  'shake_lulav': ('Shake the lulav', 'מנענעים את הלולב'),
  'hold_cup': ('Hold the cup', 'אוחזים את הכוס'),
  'look_at_candles': ('Look at the candles', 'מביטים בנרות'),
  'look_at_fingernails': ('Look at the fingernails', 'מביטים בצפורניים'),
  'strike_chest': ('Strike the chest', 'מכים על החזה'),
  'look_at_moon': ('Look at the moon', 'מביטים בלבנה'),
  'raise_hands': ('Raise the hands', 'נושאים כפיים'),
  'turn_west': ('Turn to the west', 'פונים מערבה'),
  'bow_left_right_center': ('Bow left, right, center', 'משתחווים שמאלה, ימינה ואמצע'),
};

/// A gesture's label in the instruction languages; null for one the reader
/// doesn't label (a plain bow, which every blessing would repeat).
String? gestureLabel(AppSettings s, String gesture) {
  final l = _gestures[gesture];
  return l == null ? null : _instruction(s, l);
}

const _undertone = ('In an undertone', 'בלחש');

/// [en] and [he] as the instruction languages say, like [conditionLabel].
String _instruction(AppSettings s, (String, String) label) {
  final parts = [if (s.showEnglishNotes) label.$1, if (s.showHebrewNotes) label.$2];
  return parts.join(' · ');
}

/// Who says it ("Congregation, then chazzan"); empty for one's own prayer.
String readingRole(BuildContext context, AppSettings s, String? role) {
  final l = _roles[role];
  return l == null ? '' : _instruction(s, l);
}

/// The same, as a short mark inside a line ("Cong.").
String readingRoleShort(BuildContext context, AppSettings s, String? role) => readingRole(context, s, role);

/// The congregation's responses: set on the far side of the line.
bool isResponse(String? role) => role == 'congregation';

final _verse = RegExp(r'(^|[.:׃]\s+|<br>\s*)([\u05d0-\u05ea]{1,3})\s+(?=[\u05d0-\u05ea][^\s<]*[\u0591-\u05c7])');

/// A verse number run into its verse with no space ("יבמָה אָשִׁיב"): a
/// numeral's unpointed letters straight before a pointed one.
///
/// Plenty of ordinary words look the same (סומֵךְ, נוטֶה, עלַת: a first
/// letter with no vowel of its own), so a glued numeral is only believed
/// when it continues a sequence: it is the verse after the one before it.
final _gluedVerse = RegExp(r'(^|[.:׃]\s+|<br>\s*)((?:[קרשת]?[יכלמנסעפצ]?[א-ט]|[קרשת]?[יכלמנסעפצ]|[קרשת]|ט[וז]))(?=[א-ת][֑-ׇ])');

const _numerals = {
  'א': 1, 'ב': 2, 'ג': 3, 'ד': 4, 'ה': 5, 'ו': 6, 'ז': 7, 'ח': 8, 'ט': 9, 'י': 10, 'כ': 20, 'ל': 30, 'מ': 40,
  'נ': 50, 'ס': 60, 'ע': 70, 'פ': 80, 'צ': 90, 'ק': 100, 'ר': 200, 'ש': 300, 'ת': 400,
};

/// The value of Hebrew numeral letters (טו is 15), or null for anything else.
int? _numeralValue(String s) {
  var n = 0;
  for (final c in s.split('')) {
    final v = _numerals[c];
    if (v == null) return null;
    n += v;
  }
  return n;
}

/// Verse numbers printed in the text ("א הַלְלוּ יָהּ… ב יְהִי…"): small and
/// faint, so the psalm reads as verses. A number has no vowels; the word
/// after it does. A spaced number is taken as it stands; one run into its
/// word must follow the number before it (see [_gluedVerse]).
String verseNumbers(String html) {
  final hits = <(Match, bool)>[
    for (final m in _verse.allMatches(html)) (m, false),
    for (final m in _gluedVerse.allMatches(html)) (m, true),
  ]..sort((a, b) => a.$1.start.compareTo(b.$1.start));
  final out = StringBuffer();
  var at = 0;
  int? last;
  for (final (m, glued) in hits) {
    if (m.start < at) continue;
    final n = _numeralValue(m[2]!);
    if (glued && (n == null || last == null || n != last + 1)) continue;
    out
      ..write(html.substring(at, m.start))
      ..write('${m[1]}<sup class="verse">${m[2]}</sup> ');
    at = m.end;
    last = n;
  }
  return out.toString() + html.substring(at);
}

/// The small line above a prayer saying how it is read, from the corpus:
/// who says it (where that changes), in an undertone, what one does, how
/// many times.
///
/// [undertone] marks lines known to be said quietly that the corpus
/// doesn't tag (Baruch shem outside the morning Shema).
List<String> readingLabels(BuildContext context, AppSettings s, SegmentItem item, {required bool withRole, bool undertone = false}) => [
      if (withRole && _roles[item.role] != null) readingRole(context, s, item.role),
      if (item.voice == 'undertone' || undertone) _instruction(s, _undertone),
      for (final g in item.gestures.toSet())
        if (_gestures[g] != null) _instruction(s, _gestures[g]!),
      if (item.repeat != null) context.tr('×{n}', {'n': item.repeat}),
    ];
