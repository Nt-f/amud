/// Google Assistant (App Actions) and voice: what a spoken request means.
///
/// Android passes either a feature id (a shortcut's id, for OPEN_APP_FEATURE)
/// or the user's own words (the `thing.name` of GET_THING). Both end up here.
enum AskTopic { nextZman, date, parsha, omer, candles, sunrise, sunset }

/// Words that pick a topic, in English, Hebrew and Yiddish. Earlier topics win,
/// so "when is sunrise" is sunrise, not the next zman.
const _keywords = <AskTopic, List<String>>{
  AskTopic.candles: ['candle', 'licht', 'הדלקת', 'נרות', 'נר ', 'ליכט', 'בענטש'],
  AskTopic.sunrise: ['sunrise', 'netz', 'neitz', 'הנץ', 'זריחה', 'זריחת', 'זונאויפגאנג'],
  AskTopic.sunset: ['sunset', 'shkia', 'shkiah', 'שקיעה', 'שקיעת', 'שקיעה', 'זונפארגאנג'],
  AskTopic.omer: ['omer', 'עומר', 'עומער', 'ספירה', 'ספירת'],
  AskTopic.parsha: ['parsha', 'parasha', 'parashah', 'portion', 'sidra', 'פרשה', 'פרשת', 'סדרה', 'סידרה', 'פרשע'],
  AskTopic.nextZman: ['zman', 'zmanim', 'next', 'halachic time', 'זמן', 'זמנים', 'הבא', 'הבאה', 'קומענדיקע'],
  AskTopic.date: ['date', 'today', 'day', 'hebrew', 'תאריך', 'היום', 'יום', 'דאטום', 'הײַנט', 'היינט'],
};

/// The topic a spoken request or feature id is about, or null.
AskTopic? matchAskTopic(String words) {
  final text = words
      .toLowerCase()
      .replaceAll(RegExp('[֑-ׇ]'), '') // niqqud and cantillation
      .replaceAll(RegExp(r'[_\-]'), ' ');
  if (text.trim().isEmpty) return null;
  // A feature id names its topic exactly.
  for (final topic in AskTopic.values) {
    if (text.trim() == topic.name.toLowerCase()) return topic;
  }
  for (final entry in _keywords.entries) {
    if (entry.value.any((word) => text.contains(word))) return entry.key;
  }
  return null;
}
