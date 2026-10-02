import 'condition.dart';

/// Removes HTML tags and entities.
String stripHtml(String html) => html
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll(RegExp(r'&#?\w+;'), '');

final _nikkud = RegExp('[֑-ׇ]');
final _hebLetter = RegExp('[א-ת]');
final _latin = RegExp('[A-Za-z]');

/// Normalizes Hebrew/English rubric text for matching: strips HTML, niqqud,
/// unifies quote marks, lowercases Latin and collapses whitespace.
String normalizeRubric(String s) => stripHtml(s)
    .replaceAll(_nikkud, '')
    .replaceAll(RegExp('[״”“]'), '"')
    .replaceAll(RegExp("[׳’‘`]"), "'")
    .replaceAll("''", '"')
    .replaceAll(RegExp(r'[ḥḤ]'), 'h')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

/// Fraction of Hebrew letters carrying niqqud — prayer text is vocalized,
/// instructions are not.
double nikkudRatio(String html) {
  final plain = stripHtml(html);
  final letters = _hebLetter.allMatches(plain).length;
  if (letters == 0) return 0;
  return _nikkud.allMatches(plain).length / letters;
}

bool isHebrewText(String html) {
  final p = stripHtml(html);
  return _hebLetter.allMatches(p).length > _latin.allMatches(p).length;
}

enum _Cat { occasion, dow, place, season, service, minyan, other }

class _Entry {
  final RegExp re;
  final String cond;
  final _Cat cat;
  final String en;
  final String he;
  _Entry(String pattern, this.cond, this.cat, this.en, this.he) : re = RegExp(pattern, caseSensitive: false, unicode: true);
}

// Special tokens resolved against the conditioned text.
const _summer = '@summer';
const _winter = '@winter';

// Hebrew prefix letters that may precede a keyword: ב, ל, ו, וב, ול, מ.
const _p = r'(?:^|[\s(\[,.;:\-–])(?:ו?[בלמ]?)';

final List<_Entry> _hebrew = [
  _Entry('$_p(?:עשרת ימי תשובה|עשי"ת|עשית|עשרת ימי תשובה|עשי״ת|שבת שובה|ר"ה ויוה"כ)', 'aseretYemeiTeshuva', _Cat.occasion, 'Aseret Yemei Teshuva', 'עשי"ת'),
  _Entry('$_p(?:ראש חו?דש|ר"ח|ר״ח)', 'roshChodesh', _Cat.occasion, 'Rosh Chodesh', 'ראש חודש'),
  _Entry('$_p(?:חוה"מ|חה"מ|חול המועד|חולו של מועד)\\s*פסח', 'cholHamoedPesach', _Cat.occasion, 'Chol HaMoed Pesach', 'חוה"מ פסח'),
  _Entry('$_p(?:חוה"מ|חה"מ|חול המועד|חולו של מועד)\\s*סוכות', 'cholHamoedSukkot', _Cat.occasion, 'Chol HaMoed Sukkot', 'חוה"מ סוכות'),
  _Entry('$_p(?:חוה"מ|חה"מ|חול המועד|חולו של מועד|ובחוה"מ)', 'cholHamoed', _Cat.occasion, 'Chol HaMoed', 'חול המועד'),
  _Entry('$_p(?:חנוכה)', 'chanukah', _Cat.occasion, 'Chanukah', 'חנוכה'),
  _Entry('$_p(?:פורים המשולש)', 'purim && dow == 0', _Cat.occasion, 'Purim Meshulash', 'פורים המשולש'),
  _Entry('$_p(?:פורים)', 'purim', _Cat.occasion, 'Purim', 'פורים'),
  _Entry('$_p(?:תשעה באב|ט"ב|ת"ב)', 'tishaBav', _Cat.occasion, "Tisha B'Av", 'תשעה באב'),
  _Entry('$_p(?:תענית צי?בור|ת"צ|תעני(?:ו|ת)|צום|ג\' צומות)', 'fastDay', _Cat.occasion, 'Fast day', 'תענית'),
  _Entry('$_p(?:מוצאי שבת|מוצ"ש|מוצש"ק|מוצאי שבת קודש)', 'motzaeiShabbat', _Cat.occasion, "Motza'ei Shabbat", 'מוצאי שבת'),
  _Entry('$_p(?:ערב שבת|עש"ק)', 'erevShabbat', _Cat.occasion, 'Erev Shabbat', 'ערב שבת'),
  _Entry('$_p(?:ראשון|א\') בשבת', 'dow == 0', _Cat.dow, 'Sunday', 'יום ראשון'),
  _Entry('$_p(?:שני|ב\') בשבת', 'dow == 1', _Cat.dow, 'Monday', 'יום שני'),
  _Entry('$_p(?:שלישי|ג\') בשבת', 'dow == 2', _Cat.dow, 'Tuesday', 'יום שלישי'),
  _Entry('$_p(?:רביעי|ד\') בשבת', 'dow == 3', _Cat.dow, 'Wednesday', 'יום רביעי'),
  _Entry('$_p(?:חמישי|ה\') בשבת', 'dow == 4', _Cat.dow, 'Thursday', 'יום חמישי'),
  _Entry('$_p(?:שישי|ששי|ו\') בשבת', 'dow == 5', _Cat.dow, 'Friday', 'יום שישי'),
  _Entry('$_p(?:שני וחמישי|ב\' וה\'|בה"ב)', 'monThu', _Cat.dow, 'Monday & Thursday', 'שני וחמישי'),
  _Entry('$_p(?:ראש השנה|ר"ה)', 'roshHashana', _Cat.occasion, 'Rosh Hashana', 'ראש השנה'),
  _Entry('$_p(?:יום הכפורים|יום כפור|יוה"כ|יוהכ"פ)', 'yomKippur', _Cat.occasion, 'Yom Kippur', 'יום הכפורים'),
  _Entry('$_p(?:הושענא רבה|הוש"ר)', 'hoshanaRaba', _Cat.occasion, 'Hoshana Raba', 'הושענא רבה'),
  _Entry('$_p(?:שמיני עצרת|שמע"צ|ש"ע)', 'shminiAtzeret', _Cat.occasion, 'Shmini Atzeret', 'שמיני עצרת'),
  _Entry('$_p(?:שמחת תורה|שמח"ת)', 'simchatTorah', _Cat.occasion, 'Simchat Torah', 'שמחת תורה'),
  _Entry('$_p(?:סוכות|סכות|חג הסוכות)', 'sukkot', _Cat.occasion, 'Sukkot', 'סוכות'),
  _Entry('$_p(?:פסח)(?!\\s*שני)', 'pesach', _Cat.occasion, 'Pesach', 'פסח'),
  _Entry('$_p(?:שבועות)', 'shavuot', _Cat.occasion, 'Shavuot', 'שבועות'),
  _Entry('$_p(?:יום העצמאות)', 'yomHaatzmaut', _Cat.occasion, "Yom HaAtzma'ut", 'יום העצמאות'),
  _Entry('$_p(?:יום ירושלים)', 'yomYerushalayim', _Cat.occasion, 'Yom Yerushalayim', 'יום ירושלים'),
  _Entry('$_p(?:יו"ט|יום טוב|יום-טוב|ימים טובים|רגלים)', 'yomTov', _Cat.occasion, 'Yom Tov', 'יום טוב'),
  _Entry('$_p(?:שבת|שבתות)(?![\\s]*(?:שובה|חזון|נחמו))', 'shabbat', _Cat.occasion, 'Shabbat', 'שבת'),
  _Entry('$_p(?:קיץ|ימות החמה)', _summer, _Cat.season, 'Summer', 'קיץ'),
  _Entry('$_p(?:חורף|ימות הגשמים)', _winter, _Cat.season, 'Winter', 'חורף'),
  _Entry('$_p(?:ימי הספירה|ספירת העומר)', 'omer', _Cat.occasion, 'Sefirat HaOmer', 'ספירת העומר'),
  _Entry('$_p(?:ר"ח אלול|ראש חודש אלול)', 'ledavid', _Cat.occasion, 'Elul', 'אלול'),
  _Entry('$_p(?:א"י|ארץ ישראל|ארה"ק)', 'il', _Cat.place, 'Israel', 'ארץ ישראל'),
  _Entry('$_p(?:חו"ל|חוץ לארץ|חוצה לארץ)', 'diaspora', _Cat.place, 'Diaspora', 'חוץ לארץ'),
  _Entry('$_p(?:חזרת הש"ץ|חזרת הש״ץ|חזרת השליח צבור|חזרת שליח צבור|כשהש"ץ חוזר|כשהש״ץ חוזר)', 'minyan', _Cat.minyan, 'Chazarat HaShatz', 'חזרת הש"ץ'),
  _Entry('$_p(?:שחרית)', 'shacharit', _Cat.service, 'Shacharit', 'שחרית'),
  _Entry('$_p(?:מנחה)', 'mincha', _Cat.service, 'Mincha', 'מנחה'),
  _Entry('$_p(?:ערבית|מעריב)', 'maariv', _Cat.service, 'Maariv', 'ערבית'),
  _Entry('$_p(?:מוסף)', 'musaf', _Cat.service, 'Musaf', 'מוסף'),
];

final List<_Entry> _english = [
  _Entry(r'ten days of (?:penitence|repentance)|aseres yemei|aseret yemei|between rosh hashana(?:h)? (?:&|and) yom kippur|shabbat shuva|shabbos shuvah', 'aseretYemeiTeshuva', _Cat.occasion, 'Aseret Yemei Teshuva', 'עשי"ת'),
  _Entry(r'rosh (?:c)?hodesh|new moon|new month|rosh chodesh', 'roshChodesh', _Cat.occasion, 'Rosh Chodesh', 'ראש חודש'),
  _Entry(r"(?:c)?hol ?ha ?mo[’']?ed", 'cholHamoed', _Cat.occasion, 'Chol HaMoed', 'חול המועד'),
  _Entry(r'(?:c)?hanuk(?:k)?a', 'chanukah', _Cat.occasion, 'Chanukah', 'חנוכה'),
  _Entry(r'purim', 'purim', _Cat.occasion, 'Purim', 'פורים'),
  _Entry(r"tish[’']?a b[’']?av|9th of av|ninth of av", 'tishaBav', _Cat.occasion, "Tisha B'Av", 'תשעה באב'),
  _Entry(r'fast day|public fast|fast days|on a fast', 'fastDay', _Cat.occasion, 'Fast day', 'תענית'),
  _Entry(r"motza[’']?ei shab|motzoei shab|saturday night|after shabbat ends", 'motzaeiShabbat', _Cat.occasion, "Motza'ei Shabbat", 'מוצאי שבת'),
  _Entry(r'mondays? and thursdays?', 'monThu', _Cat.dow, 'Monday & Thursday', 'שני וחמישי'),
  _Entry(r'on sunday', 'dow == 0', _Cat.dow, 'Sunday', 'יום ראשון'),
  _Entry(r'on monday', 'dow == 1', _Cat.dow, 'Monday', 'יום שני'),
  _Entry(r'on tuesday', 'dow == 2', _Cat.dow, 'Tuesday', 'יום שלישי'),
  _Entry(r'on wednesday', 'dow == 3', _Cat.dow, 'Wednesday', 'יום רביעי'),
  _Entry(r'on thursday', 'dow == 4', _Cat.dow, 'Thursday', 'יום חמישי'),
  _Entry(r'on friday', 'dow == 5', _Cat.dow, 'Friday', 'יום שישי'),
  _Entry(r'rosh hasha(?:n)?a(?:h)?', 'roshHashana', _Cat.occasion, 'Rosh Hashana', 'ראש השנה'),
  _Entry(r'yom kippur', 'yomKippur', _Cat.occasion, 'Yom Kippur', 'יום הכפורים'),
  _Entry(r'hoshana rab', 'hoshanaRaba', _Cat.occasion, 'Hoshana Raba', 'הושענא רבה'),
  _Entry(r'she?mini atzere[st]', 'shminiAtzeret', _Cat.occasion, 'Shmini Atzeret', 'שמיני עצרת'),
  _Entry(r'sim(?:c)?hat torah|simchas torah', 'simchatTorah', _Cat.occasion, 'Simchat Torah', 'שמחת תורה'),
  _Entry(r'suk(?:k)?o[ts]|tabernacles', 'sukkot', _Cat.occasion, 'Sukkot', 'סוכות'),
  _Entry(r'pesa(?:c)?h|passover|matzo[st]|matzah', 'pesach', _Cat.occasion, 'Pesach', 'פסח'),
  _Entry(r'shavuo[ts]|pentecost', 'shavuot', _Cat.occasion, 'Shavuot', 'שבועות'),
  _Entry(r"yom ha-?atzma[’']?ut", 'yomHaatzmaut', _Cat.occasion, "Yom HaAtzma'ut", 'יום העצמאות'),
  _Entry(r'yom yerushalayim|jerusalem day', 'yomYerushalayim', _Cat.occasion, 'Yom Yerushalayim', 'יום ירושלים'),
  _Entry(r'yom tov|festival', 'yomTov', _Cat.occasion, 'Yom Tov', 'יום טוב'),
  _Entry(r'shabbat|shabbos|sabbath', 'shabbat', _Cat.occasion, 'Shabbat', 'שבת'),
  _Entry(r'summer|spring and summer', _summer, _Cat.season, 'Summer', 'קיץ'),
  _Entry(r'winter|fall and winter', _winter, _Cat.season, 'Winter', 'חורף'),
  _Entry(r'outside (?:of )?(?:the land of )?israel|in the diaspora|in (?:the )?galut', 'diaspora', _Cat.place, 'Diaspora', 'חוץ לארץ'),
  _Entry(r'in israel|in eretz yisrael|in the land of israel', 'il', _Cat.place, 'Israel', 'ארץ ישראל'),
  _Entry(r"leader[’']?s repetition|chazzan repeats|repetition of the|when the (?:chazzan|leader|reader) repeats", 'minyan', _Cat.minyan, 'Chazarat HaShatz', 'חזרת הש"ץ'),
];

// Order-sensitive seasonal phrases ("from X until Y").
final List<(RegExp, String, String)> _seasonalRanges = [
  (RegExp(r'from .{0,40}(?:pesa|passover).{0,60}until .{0,40}(?:she?mini|simchat|simhat)', caseSensitive: false), 'moridHatal', 'Summer'),
  (RegExp(r'from .{0,40}(?:she?mini|simchat|simhat).{0,60}until .{0,40}(?:pesa|passover)', caseSensitive: false), 'mashivHaruach', 'Winter'),
  (RegExp(r'from .{0,40}(?:pesa|passover).{0,80}until .{0,60}december', caseSensitive: false), '!talUmatar', 'Summer'),
  (RegExp(r'from .{0,60}december.{0,80}until .{0,40}(?:pesa|passover)', caseSensitive: false), 'talUmatar', 'Winter'),
  (RegExp(r'מפסח עד|מיום (?:א|ראשון) של פסח'), 'moridHatal', 'Summer'),
  (RegExp(r'משמיני עצרת|משמע"צ|מש"ע עד'), 'mashivHaruach', 'Winter'),
];

final _hebNegation = RegExp(r'(?:^|\s)(?:אין אומרים|אינו אומר|אין אומר|לא יאמר|לא יאמרו|לא אומרים|חוץ מ|מלבד|אין מתפללים)');
final _enNegation = RegExp(r"\b(?:do not say|is not said|are not said|omit|except|not recited|don['’]t say|is omitted)\b", caseSensitive: false);
final _hebNoTachanun = RegExp(r'(?:ש|ב)?(?:ימים|יום) ש(?:אין|אינם) אומרים(?: בו| בהם)? תחנון|שאין בו תחנון');
final _enNoTachanun = RegExp(r'days? (?:on which|when) ta(?:c)?h(?:a)?nun is not said', caseSensitive: false);

/// The result of recognizing a rubric (instruction line).
class RubricMatch {
  final String expression;
  final List<String> labelsEn;
  final List<String> labelsHe;

  /// True if the rubric must be resolved against the conditioned text
  /// (summer/winter could mean either Mashiv HaRuach or Tal U'Matar).
  final bool seasonal;
  const RubricMatch(this.expression, this.labelsEn, this.labelsHe, {this.seasonal = false});

  String get labelEn => labelsEn.join(' / ');
  String get labelHe => labelsHe.join(' / ');

  /// Resolves `@summer` / `@winter` against the text they apply to.
  RubricMatch resolveSeason(String conditionedText) {
    if (!seasonal) return this;
    final t = normalizeRubric(conditionedText);
    final String summer;
    final String winter;
    if (RegExp(r'מטר|rain and dew|dew and rain|dew and rain').hasMatch(t) ||
        (RegExp(r'ברכה|blessing').hasMatch(t) && !RegExp(r'הטל|dew to|the dew').hasMatch(t))) {
      summer = '!talUmatar';
      winter = 'talUmatar';
    } else if (RegExp(r'הטל|dew').hasMatch(t)) {
      summer = 'moridHatal';
      winter = 'mashivHaruach';
    } else {
      summer = '!mashivHaruach';
      winter = 'mashivHaruach';
    }
    return RubricMatch(expression.replaceAll(_summer, summer).replaceAll(_winter, winter), labelsEn, labelsHe);
  }

  Condition get condition => Condition.parse(
      expression.replaceAll(_summer, '!mashivHaruach').replaceAll(_winter, 'mashivHaruach'));

  @override
  String toString() => 'RubricMatch($expression, $labelEn)';
}

/// Tries to interpret an instruction as a condition. Returns null if the
/// instruction isn't conditional (e.g. "bow here", "Chazzan:").
RubricMatch? matchRubric(String rubricHtml) {
  var t = normalizeRubric(rubricHtml);
  if (t.isEmpty) return null;
  final hebrew = RegExp('[א-ת]').hasMatch(t) && !RegExp('[a-z]{3,}').hasMatch(t);
  // Only the last sentence governs ("On weekdays continue ... On Rosh
  // Chodesh add:").
  final sentences = t.split(RegExp(r'(?<=[.!?])\s+(?=\S)'));
  if (sentences.length > 1) t = sentences.last;

  for (final (re, cond, label) in _seasonalRanges) {
    if (re.hasMatch(t)) {
      final il = RegExp(r'in israel|בא"י|בארץ ישראל').hasMatch(t);
      return RubricMatch(il ? 'il && $cond' : cond, [if (il) 'Israel', label],
          [if (il) 'ארץ ישראל', label == 'Summer' ? 'קיץ' : 'חורף']);
    }
  }
  if ((hebrew ? _hebNoTachanun : _enNoTachanun).hasMatch(t)) {
    return const RubricMatch('!tachanun', ['No Tachanun'], ['אין תחנון']);
  }

  final entries = hebrew ? _hebrew : _english;
  final byCat = <_Cat, List<(int, _Entry)>>{};
  final consumed = <(int, int)>[];
  for (final e in entries) {
    for (final m in e.re.allMatches(t)) {
      final overlaps = consumed.any((c) => m.start < c.$2 && m.end > c.$1);
      if (overlaps) continue;
      consumed.add((m.start, m.end));
      byCat.putIfAbsent(e.cat, () => []).add((m.start, e));
      break;
    }
  }
  if (byCat.isEmpty) return null;
  // Service words alone ("ואומר ש"ץ", "Mincha") are not conditions.
  if (byCat.keys.every((c) => c == _Cat.service)) return null;

  final parts = <String>[];
  final en = <String>[];
  final he = <String>[];
  var seasonal = false;
  for (final cat in _Cat.values) {
    final list = byCat[cat];
    if (list == null) continue;
    list.sort((a, b) => a.$1.compareTo(b.$1));
    final exprs = <String>[];
    for (final (_, e) in list) {
      exprs.add(e.cond);
      en.add(e.en);
      he.add(e.he);
      if (e.cond.startsWith('@')) seasonal = true;
    }
    parts.add(exprs.length == 1 ? exprs.single : '(${exprs.join(' || ')})');
  }
  var expr = parts.length == 1 ? parts.single : parts.join(' && ');
  if ((hebrew ? _hebNegation : _enNegation).hasMatch(t)) {
    expr = '!($expr)';
    en.insert(0, 'Not on');
    he.insert(0, 'לא ב');
  }
  return RubricMatch(expr, en, he, seasonal: seasonal);
}

/// Short speaker/role labels that are not conditions.
final _speaker = RegExp(
    r'^(?:חזן|קהל|ש"ץ|ש״ץ|שליח צבור|שליח ציבור|קהל וחזן|קהל וש"ץ|קהל וש״ץ|חזן וקהל|קו"ח|חו"ק|יחיד|אבל|קהל ואבל|עולה|המזמן|המסובים|leader|cong\.?|congregation|cong\. then leader|reader|chazzan|all|individual)\s*[:–-]?$',
    caseSensitive: false);

bool isSpeakerLabel(String html) => _speaker.hasMatch(normalizeRubric(html));

/// Short labels ("Rosh Chodesh", "ראש חודש") for a condition written in the
/// corpus, where no instruction in the text names it: from the rubric
/// table, one per identifier, "Not …" for a negated one. Null when none of
/// its identifiers has a label.
RubricMatch? labelsForCondition(String expression) {
  final en = <String>[];
  final he = <String>[];
  // Negation reaches through parentheses: "!(cholHamoed && x)" is "not on
  // Chol HaMoed".
  final negated = <bool>[false];
  var not = false;
  for (final m in RegExp(r'!(?!=)|\(|\)|[A-Za-z_]\w*').allMatches(expression)) {
    final t = m.group(0)!;
    if (t == '!') {
      not = !not;
    } else if (t == '(') {
      negated.add(negated.last != not);
      not = false;
    } else if (t == ')') {
      if (negated.length > 1) negated.removeLast();
    } else {
      final neg = negated.last != not;
      not = false;
      final e = _english.where((x) => x.cond == t).firstOrNull;
      if (e == null) continue;
      final l = (neg ? 'Not on ${e.en}' : e.en, neg ? 'לא ב${e.he}' : e.he);
      if (!en.contains(l.$1)) {
        en.add(l.$1);
        he.add(l.$2);
      }
    }
  }
  return en.isEmpty ? null : RubricMatch(expression, en, he);
}
