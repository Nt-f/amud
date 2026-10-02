import '../../core/search.dart';

/// Keep the command language independent of the recognition language.
String voiceQuery(String transcript) {
  var text = searchFold(transcript);
  text = text.replaceFirst(RegExp(r'^(?:please\s+|בבקשה\s+)'), '');
  text = text.replaceFirst(
    RegExp(
      r'^(?:open|show|read|go to|take me to|פתח לי|פתחי לי|תפתח לי|תפתחי לי|פתח|פתחי|תפתח|תפתחי|הצג|הציגי|תראה לי|קח אותי אל)\s+',
    ),
    '',
  );
  text = text.replaceFirst(RegExp(r'^(?:את|the)\s+'), '');
  text = text.replaceAllMapped(
    RegExp(r'(^|\s)ב(שחרית|מנחה|ערבית|מעריב|מוסף)(?=\s|$)'),
    (m) => '${m[1]}${m[2]}',
  );
  return text.replaceFirst(RegExp(r'\s+(?:in amud|באמוד)$'), '').trim();
}

const _services = <String, List<String>>{
  'shacharit': ['shacharit', 'shacharis', 'morning prayer', 'שחרית'],
  'mincha': ['mincha', 'minchah', 'afternoon prayer', 'מנחה'],
  'maariv': ['maariv', 'arvit', 'arvis', 'evening prayer', 'ערבית', 'מעריב'],
  'musaf': ['musaf', 'mussaf', 'מוסף'],
  'birkat': [
    'birkat hamazon',
    'birchas hamazon',
    'birkas hamazon',
    'grace after meals',
    'ברכת המזון',
  ],
  'derech': [
    'tefillat haderech',
    'tefillas haderech',
    'travelers prayer',
    'תפילת הדרך',
    'תפלת הדרך',
  ],
  'bedtime': ['bedtime shema', 'קריאת שמע על המיטה', 'קריאת שמע שעל המיטה'],
  'omer': ['omer', 'sefirat haomer', 'ספירת העומר'],
  'hallel': ['hallel', 'הלל'],
  'havdalah': ['havdalah', 'havdala', 'הבדלה'],
};

String? voicePrayer(String query) {
  final folded = searchFold(query);
  for (final entry in _services.entries) {
    if (entry.value.contains(folded)) return entry.key;
  }
  return null;
}

class VoiceReference {
  final int chapter;
  final int? paragraph;
  const VoiceReference(this.chapter, this.paragraph);
}

/// Kitzur is currently the Torah library's available work.
VoiceReference? kitzurVoiceReference(String query) {
  var text = voiceQuery(query);
  final prefix = RegExp(
    r'^(?:kitzur(?: shulchan (?:aruch|arukh))?|קיצור(?: שולחן ערוך| שלחן ערוך)?)\s+',
  );
  if (!prefix.hasMatch(text)) return null;
  text = text.replaceFirst(prefix, '');
  text = text.replaceFirst(RegExp(r'^(?:siman|chapter|סימן|פרק)\s+'), '');
  final parts = text.split(RegExp(r'\s+(?:seif|seifim|paragraph|סעיף)\s+'));
  if (parts.length > 2) return null;
  final chapter = voiceNumber(parts[0]);
  final paragraph = parts.length == 2 ? voiceNumber(parts[1]) : null;
  if (chapter == null ||
      chapter < 1 ||
      (parts.length == 2 && (paragraph == null || paragraph < 1))) {
    return null;
  }
  return VoiceReference(chapter, paragraph);
}

/// Spoken English and Hebrew numbers, and Hebrew numeral notation.
int? voiceNumber(String input) {
  final text = searchFold(input).replaceAll('-', ' ');
  final numeric = int.tryParse(text);
  if (numeric != null) return numeric;
  const words = <String, int>{
    'zero': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
    'אחד': 1,
    'אחת': 1,
    'ראשון': 1,
    'שתיים': 2,
    'שניים': 2,
    'שני': 2,
    'שלוש': 3,
    'שלושה': 3,
    'ארבע': 4,
    'ארבעה': 4,
    'חמש': 5,
    'חמישה': 5,
    'שש': 6,
    'שישה': 6,
    'שבע': 7,
    'שבעה': 7,
    'שמונה': 8,
    'תשע': 9,
    'תשעה': 9,
    'עשר': 10,
    'עשרה': 10,
    'עשרים': 20,
    'שלושים': 30,
    'ארבעים': 40,
    'חמישים': 50,
    'שישים': 60,
    'שבעים': 70,
    'שמונים': 80,
    'תשעים': 90,
  };
  if (text == 'מאה') return 100;
  if (text == 'מאתיים') return 200;
  var value = 0;
  var group = 0;
  var recognized = true;
  for (var word in text.split(' ')) {
    if (word == 'and') continue;
    if (word.startsWith('ו') && words.containsKey(word.substring(1))) {
      word = word.substring(1);
    }
    if (word == 'hundred') {
      group = (group == 0 ? 1 : group) * 100;
    } else if (word == 'מאה' || word == 'מאתיים') {
      value += word == 'מאה' ? 100 : 200;
    } else if (words.containsKey(word)) {
      group += words[word]!;
    } else {
      recognized = false;
      break;
    }
  }
  if (recognized && text.isNotEmpty) return value + group;
  // Restrict numeral notation to short tokens, so an unknown Hebrew word
  // cannot silently become a chapter number.
  if (!RegExp(r'^[א-ת]{1,3}$').hasMatch(text)) return null;
  const letters = {
    'א': 1,
    'ב': 2,
    'ג': 3,
    'ד': 4,
    'ה': 5,
    'ו': 6,
    'ז': 7,
    'ח': 8,
    'ט': 9,
    'י': 10,
    'כ': 20,
    'ל': 30,
    'מ': 40,
    'נ': 50,
    'ס': 60,
    'ע': 70,
    'פ': 80,
    'צ': 90,
    'ק': 100,
    'ר': 200,
    'ש': 300,
    'ת': 400,
  };
  return text.split('').fold<int>(0, (sum, letter) => sum + letters[letter]!);
}
