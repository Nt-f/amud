import 'package:flutter/widgets.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/l10n.dart';

const _roles = {
  'chazzan': 'Chazzan',
  'congregation': 'Cong.',
  'congregation_then_chazzan': 'Cong., then chazzan',
  'chazzan_then_congregation': 'Chazzan, then cong.',
  'together': 'Together with the chazzan',
  'responsive': 'Responsively',
  'kohanim': 'Kohanim',
  'mourner': 'Mourner',
  'oleh': 'The one called up',
  'head_of_household': 'Head of household',
};

const _gestures = {
  'stand': 'Stand',
  'sit': 'Sit',
  'bow': 'Bow',
  'bow_full': 'Bow fully',
  'knees_bend': 'Bend the knees',
  'rise_on_toes': 'Rise on toes',
  'feet_together': 'Feet together',
  'three_steps_back': 'Three steps back',
  'three_steps_forward': 'Three steps forward',
  'cover_eyes': 'Cover the eyes',
  'kiss_tzitzit': 'Kiss the tzitzit',
  'gather_tzitzit': 'Gather the tzitzit',
  'touch_tefillin': 'Touch the tefillin',
  'head_down': 'Head down',
  'face_ark': 'Face the ark',
  'ark_open': 'Ark opened',
  'ark_close': 'Ark closed',
  'hold_torah': 'Hold the Torah',
  'shake_lulav': 'Shake the lulav',
  'hold_cup': 'Hold the cup',
  'look_at_candles': 'Look at the candles',
  'look_at_fingernails': 'Look at the fingernails',
  'strike_chest': 'Strike the chest',
  'look_at_moon': 'Look at the moon',
  'raise_hands': 'Raise the hands',
  'turn_west': 'Turn to the west',
  'bow_left_right_center': 'Bow left, right, center',
};

/// Who says it ("Congregation, then chazzan"); empty for one's own prayer.
String readingRole(BuildContext context, String? role) {
  final l = _roles[role];
  return l == null ? '' : context.tr(l);
}

/// The same, as a short mark inside a line ("Cong.").
String readingRoleShort(BuildContext context, String? role) => readingRole(context, role);

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
List<String> readingLabels(BuildContext context, SegmentItem item, {required bool withRole, bool undertone = false}) => [
      if (withRole && _roles[item.role] != null) readingRole(context, item.role),
      if (item.voice == 'undertone' || undertone) context.tr('In an undertone'),
      for (final g in item.gestures)
        if (_gestures[g] != null) context.tr(_gestures[g]!),
      if (item.repeat != null) context.tr('×{n}', {'n': item.repeat}),
    ];
