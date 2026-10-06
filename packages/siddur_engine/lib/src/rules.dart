import 'condition.dart';
import 'day_context.dart';

/// A rule that attaches a condition to a whole section of a siddur, matched
/// by the section's English title (and optionally its ancestors).
///
/// Rules are data so they can be shipped per-book as JSON overrides and
/// edited by users ("custom rules").
class SectionRule {
  /// Regex matched (case-insensitively) against the node's English title.
  final RegExp title;

  /// Optional regex that must match the ' / '-joined ancestor titles.
  final RegExp? within;

  /// Optional regex that must NOT match the ancestor path.
  final RegExp? notWithin;

  /// Condition expression; see [DayContext.variableDocs].
  final String when;
  final String labelEn;
  final String labelHe;

  /// Service implied by this section (used to build the DayContext for
  /// everything inside it). Null = inherit.
  final Service? service;

  SectionRule({
    required String title,
    String? within,
    String? notWithin,
    this.when = 'true',
    this.labelEn = '',
    this.labelHe = '',
    this.service,
  })  : title = RegExp(title, caseSensitive: false),
        within = within == null ? null : RegExp(within, caseSensitive: false),
        notWithin = notWithin == null ? null : RegExp(notWithin, caseSensitive: false);

  Condition get condition => Condition.parse(when);

  bool matches(String enTitle, List<String> ancestors) {
    if (!title.hasMatch(enTitle)) return false;
    final path = ancestors.join(' / ');
    if (within != null && !within!.hasMatch(path)) return false;
    if (notWithin != null && notWithin!.hasMatch(path)) return false;
    return true;
  }

  factory SectionRule.fromJson(Map<String, Object?> j) => SectionRule(
        title: j['title'] as String,
        within: j['within'] as String?,
        notWithin: j['notWithin'] as String?,
        when: (j['when'] as String?) ?? 'true',
        labelEn: (j['labelEn'] as String?) ?? '',
        labelHe: (j['labelHe'] as String?) ?? '',
        service: j['service'] == null ? null : Service.values.byName(j['service'] as String),
      );

  Map<String, Object?> toJson() => {
        'title': title.pattern,
        if (within != null) 'within': within!.pattern,
        if (notWithin != null) 'notWithin': notWithin!.pattern,
        'when': when,
        'labelEn': labelEn,
        'labelHe': labelHe,
        if (service != null) 'service': service!.name,
      };
}

/// Explicit per-segment override, addressed by Sefaria-style ref path
/// (`"Weekday/Shacharit/Amidah/Temple Service"` + segment index).
class SegmentRule {
  final String path;
  final int index;
  final String when;
  final String labelEn;
  final String labelHe;
  const SegmentRule(this.path, this.index, this.when, {this.labelEn = '', this.labelHe = ''});

  factory SegmentRule.fromJson(Map<String, Object?> j) => SegmentRule(
        j['path'] as String,
        (j['index'] as num).toInt(),
        j['when'] as String,
        labelEn: (j['labelEn'] as String?) ?? '',
        labelHe: (j['labelHe'] as String?) ?? '',
      );
}

/// Service detection by section title — applies to all nusachim.
final List<SectionRule> serviceRules = [
  SectionRule(title: r'mussaf|musaf', service: Service.musaf),
  SectionRule(title: r'^(?:weekday |shabbat |shabbos )?(?:shacharit|shacharis|shaharit|morning prayers?|the morning prayers|morning services?)', service: Service.shacharit),
  SectionRule(title: r'minchah?|minha|afternoon', service: Service.mincha),
  SectionRule(title: r'maariv|ma.ariv|arvit|evening service|kabbalat shabbat|kabbalas shabbos', service: Service.maariv),
  SectionRule(title: r'candle lighting|menorah lighting|lighting (?:c)?hanuk|service for lighting', service: Service.maariv),
];

/// Default section rules, applied to every book. Order matters: the first
/// matching rule wins for each node.
final List<SectionRule> defaultSectionRules = [
  SectionRule(title: r'ta(?:c)?h(?:a)?nun|tachnun|nefilat apayim|god of israel|shomer yisrael|vidui and 13', notWithin: r'Yom Kippur|Selich|Selih', when: 'tachanun', labelEn: 'Tachanun', labelHe: 'תחנון'),
  SectionRule(title: r'^(?:for )?monday (?:&|and) thursday|^vehu rachum$', notWithin: r'Maariv|Arvit', when: 'monThu && tachanun', labelEn: 'Monday & Thursday', labelHe: 'שני וחמישי'),
  SectionRule(title: r'avinu malk', when: 'avinuMalkeinu', labelEn: 'Avinu Malkeinu', labelHe: 'אבינו מלכנו'),
  SectionRule(title: r'^hallel$|berakhah before the hallel|psalm 11[3-8]$|berakhah after the hallel', notWithin: r'Haggadah|Seder', when: 'hallel', labelEn: 'Hallel', labelHe: 'הלל'),
  SectionRule(title: r'sefirat ha.?omer|counting (?:of )?the omer', when: 'omer', labelEn: 'Sefirat HaOmer', labelHe: 'ספירת העומר', service: Service.maariv),
  SectionRule(title: r"motza.?ei shab|motzei shabbos|motzaei shabbat|additions for motza|ma.ariv for motza", when: 'dow == 0', labelEn: "Motza'ei Shabbat", labelHe: 'מוצאי שבת', service: Service.maariv),
  SectionRule(title: r'birkat ha.?levana|kiddush levan|blessing of the (?:new )?moon', when: 'kiddushLevana', labelEn: 'Kiddush Levana', labelHe: 'קידוש לבנה'),
  SectionRule(title: r"^(?:le.?david|l.david hashem|psalm from rosh chodesh elul)$", notWithin: r'Shabbat Evening|Zemirot|Songs', when: 'ledavid', labelEn: 'LeDavid (Elul)', labelHe: 'לדוד ה׳ אורי'),
  SectionRule(title: r'prayer for dew|tefillat tal', when: 'pesachFirstDays && musaf', labelEn: 'Tefillat Tal', labelHe: 'תפילת טל'),
  SectionRule(title: r'prayer for rain|tefillat geshem', when: 'shminiAtzeret && musaf', labelEn: 'Tefillat Geshem', labelHe: 'תפילת גשם'),
  // The Hoshanos of one day come before the general rule, since the first
  // matching rule wins.
  SectionRule(title: r'hosha(?:.a)?na rab+a', when: 'hoshanaRaba', labelEn: 'Hoshana Raba', labelHe: 'הושענא רבה'),
  SectionRule(title: r'^hosha(?:.?a)?no[ts] for shabbat', when: 'sukkot && shabbat', labelEn: 'Shabbat Chol HaMoed', labelHe: 'שבת חול המועד'),
  SectionRule(title: r'shabbat chol hamo|shabbat hol hamo|^sabbath$', within: r'hosha(?:.?a)?no[ts]|sukkot', when: 'sukkot && shabbat',
      labelEn: 'Shabbat Chol HaMoed', labelHe: 'שבת חול המועד'),
  for (final (i, (en, he)) in const [
    ('first', 'א׳'),
    ('second', 'ב׳'),
    ('third', 'ג׳'),
    ('fourth', 'ד׳'),
    ('fifth', 'ה׳'),
    ('sixth', 'ו׳'),
  ].indexed)
    SectionRule(title: '^$en day of sukkot\$', within: r'hosha(?:.?a)?no[ts]', when: 'hDay == ${15 + i} && hMonth == 7 && !shabbat',
        labelEn: 'Day ${i + 1} of Sukkot', labelHe: 'יום $he דסוכות'),
  SectionRule(title: r'^first day & chol hamoed$', within: r'sukkot', when: 'sukkot && !shabbat && !hoshanaRaba', labelEn: 'Sukkot', labelHe: 'סוכות'),
  SectionRule(title: r'hosha(?:.?a)?no[ts]', when: 'sukkot', labelEn: 'Hoshanot', labelHe: 'הושענות'),
  SectionRule(title: r'lulav', when: 'sukkot && !shabbat', labelEn: 'Lulav', labelHe: 'לולב'),
  SectionRule(title: r'leaving the sukk', when: 'hoshanaRaba || shminiAtzeret', labelEn: 'Leaving the sukkah', labelHe: 'יציאה מהסוכה'),
  SectionRule(title: r'prayers in the sukk|entering (?:the )?sukk|upon entering sukk|^ushpizin$', when: 'sukkot', labelEn: 'Sukkot', labelHe: 'סוכות'),
  SectionRule(title: r'hakafot|hakafos', when: 'simchatTorah', labelEn: 'Simchat Torah', labelHe: 'שמחת תורה'),
  SectionRule(title: r'^kap+arot$|^kap+aros$', when: 'erevYomKippur || aseretYemeiTeshuva', labelEn: 'Before Yom Kippur', labelHe: 'ערב יום כפור'),
  SectionRule(title: r'^akdamut$|^akdamus$', when: 'shavuot', labelEn: 'Shavuot', labelHe: 'שבועות'),
  SectionRule(title: r'^tashli(?:k)?h$', when: 'roshHashana', labelEn: 'Rosh Hashana', labelHe: 'ראש השנה'),
  SectionRule(title: r'annulment of vows', when: 'hMonth == 6 && hDay == 29', labelEn: 'Erev Rosh Hashana', labelHe: 'ערב ראש השנה'),
  SectionRule(title: r'kiddush for rosh hashana', when: 'roshHashana', labelEn: 'Rosh Hashana', labelHe: 'ראש השנה'),
  SectionRule(title: r'viduy for minha of erev yom kippur', when: 'erevYomKippur', labelEn: 'Erev Yom Kippur', labelHe: 'ערב יום כפור'),
  SectionRule(title: r'removal of hametz|search for hametz|burning hametz|bedikat (?:c)?hametz', when: 'hMonth == 1 && hDay >= 12 && hDay <= 14',
      labelEn: 'Erev Pesach', labelHe: 'ערב פסח'),
  SectionRule(title: r'kiddush for yom tov|yom tov (?:eve|daytime) kiddush', when: 'yomTov', labelEn: 'Yom Tov', labelHe: 'יום טוב'),
  SectionRule(title: r'^amida(?:h)? for yom tov|^amida for maariv, shacharit, mincha$|^maariv, shacharit & mincha amidah$',
      when: 'yomTov', labelEn: 'Yom Tov', labelHe: 'יום טוב'),
  SectionRule(title: r'^mus+af$|^musaf for festivals$|^yom tov musaf amidah$|^musaf for yom tov$',
      within: r'shalosh regalim|festivals|three festivals|holidays|yom tov', when: 'yomTov || cholHamoed',
      labelEn: 'Yom Tov & Chol HaMoed', labelHe: 'יום טוב וחול המועד'),
  SectionRule(title: r'^birkat kohanim$', within: r'^festivals$', when: 'yomTov', labelEn: 'Yom Tov', labelHe: 'יום טוב'),
  SectionRule(title: r'musaf (?:amidah )?for rosh (?:c)?hodesh|musaf for rosh chodesh|rosh hodesh$', when: 'roshChodesh', labelEn: 'Rosh Chodesh', labelHe: 'ראש חודש'),
  SectionRule(title: r'musaf for chol hamo|kedusha for chol hamoed', when: 'cholHamoed', labelEn: 'Chol HaMoed', labelHe: 'חול המועד'),
  SectionRule(title: r'(?:c)?hanuk(?:k)?ah?', notWithin: r'Songs|Zemirot', when: 'chanukah', labelEn: 'Chanukah', labelHe: 'חנוכה'),
  SectionRule(title: r'purim|megill?ah reading', notWithin: r'Katan', when: 'purim || taanitEsther', labelEn: 'Purim', labelHe: 'פורים'),
  SectionRule(title: r'fast of gedal|tzom gedal', when: 'tzomGedaliah', labelEn: 'Tzom Gedaliah', labelHe: 'צום גדליה'),
  SectionRule(title: r'ten(?:th)? of tevet|asara b.?tevet|tenth of teves', when: 'asaraBTevet', labelEn: "Asara B'Tevet", labelHe: 'עשרה בטבת'),
  SectionRule(title: r'fast of esther|taanit esther', when: 'taanitEsther', labelEn: "Ta'anit Esther", labelHe: 'תענית אסתר'),
  SectionRule(title: r'seventeen(?:th)? of tam+uz|17 tam+uz', when: 'tzomTammuz', labelEn: '17 Tammuz', labelHe: 'י״ז בתמוז'),
  SectionRule(title: r'yom kippur katan', when: 'yomKippurKatan || erevRoshChodesh', labelEn: 'Yom Kippur Katan', labelHe: 'יום כפור קטן'),
  SectionRule(title: r'^bahab|behab|monday \(1\)|monday \(2\)|first monday|concluding monday', within: r'Selich|Selih|Fast', when: 'behab', labelEn: 'BeHaB', labelHe: 'בה״ב'),
  SectionRule(title: r'fast day torah reading|torah reading for fast|fast day mincha haftara', when: 'fastDay', labelEn: 'Fast day', labelHe: 'תענית'),
  // Said only on Shabbat, also in the Shabbat services used on Yom Tov.
  SectionRule(title: r'^ve.?sham(?:e)?ru$|^vay.?(?:e)?chulu$|^me.?ein sheva$|^magen avot$|^magein avos$', notWithin: r'Kiddush|Zemir|Meal|Evening$',
      when: 'shabbat', labelEn: 'Shabbat', labelHe: 'שבת'),
  SectionRule(title: r'^torah reading$|^reading of the torah$', when: 'torahReading', labelEn: 'Torah reading', labelHe: 'קריאת התורה'),
  SectionRule(title: r'barchi nafshi|barekhi nafshi|my soul bless', within: r'Shabbat|Shabbos', when: 'barchiNafshiShabbat', labelEn: 'Barchi Nafshi (winter)', labelHe: 'ברכי נפשי'),
  SectionRule(title: r'barchi nafshi|barekhi nafshi|my soul bless', when: 'roshChodesh', labelEn: 'Rosh Chodesh', labelHe: 'ראש חודש'),
  SectionRule(title: r'psalms recited between sukkos and pesach', when: 'barchiNafshiShabbat', labelEn: 'Winter', labelHe: 'חורף'),
  SectionRule(title: r'^pirkei avo[ts]$|ethics of the fathers', within: r'Mincha|Minha', when: 'pirkeiAvot', labelEn: 'Pirkei Avot (summer)', labelHe: 'פרקי אבות'),
  SectionRule(title: r'tzidkat(?:k)?hah? tzedek', when: 'tzidkatcha', labelEn: 'Tzidkatcha', labelHe: 'צדקתך'),
  SectionRule(title: r'av ha.?ra(?:c)?hamim|av horachamim', when: 'avHarachamim', labelEn: 'Av HaRachamim', labelHe: 'אב הרחמים'),
  SectionRule(title: r'blessing(?:s)? (?:of|the) (?:the )?new month|birkat ha.?chodesh|blessing the new month', when: 'shabbatMevarchim', labelEn: 'Shabbat Mevarchim', labelHe: 'ברכת החודש'),
  SectionRule(title: r'yizkor', when: 'yizkor', labelEn: 'Yizkor', labelHe: 'יזכור'),
  SectionRule(title: r'eruv tavshilin|eiruv tavshilin', when: 'eruvTavshilin', labelEn: 'Eruv Tavshilin', labelHe: 'עירוב תבשילין'),
  SectionRule(title: r'additions to (?:ma.ariv|shaharit) for yom haatzma', when: 'yomHaatzmaut', labelEn: "Yom HaAtzma'ut", labelHe: 'יום העצמאות'),
  SectionRule(title: r'additions to shaharit for yom hazikaron', when: 'yomHazikaron', labelEn: 'Yom HaZikaron', labelHe: 'יום הזכרון'),
  SectionRule(title: r'^yom yerushalayim$', when: 'yomYerushalayim', labelEn: 'Yom Yerushalayim', labelHe: 'יום ירושלים'),
  SectionRule(title: r'counting|keri.at shema al hamita|bedtime shema|prayer before retiring', when: 'true', service: Service.maariv),
];

/// Splices another section into a service flow on the days it applies,
/// e.g. Hallel after the weekday Amidah on Rosh Chodesh/Chanukah.
class InsertRule {
  /// Node id after which to insert (or before, if [before] is true).
  final String anchor;
  final bool before;

  /// Node id of the section to insert.
  final String insert;
  final String when;
  final String labelEn;
  final String labelHe;
  const InsertRule(this.anchor, this.insert, this.when,
      {this.before = false, this.labelEn = '', this.labelHe = ''});

  Condition get condition => Condition.parse(when);

  factory InsertRule.fromJson(Map<String, Object?> j) => InsertRule(
        (j['after'] ?? j['before']) as String,
        j['insert'] as String,
        (j['when'] as String?) ?? 'true',
        before: j.containsKey('before'),
        labelEn: (j['labelEn'] as String?) ?? '',
        labelHe: (j['labelHe'] as String?) ?? '',
      );
}

/// Shows an explanatory note at the top of a section on days a condition
/// holds (e.g. "Half Hallel: skip Lo Lanu").
class CalloutRule {
  final RegExp title;
  final RegExp? within;
  final String when;
  final String en;
  final String he;
  CalloutRule({required String title, String? within, required this.when, required this.en, required this.he})
      : title = RegExp(title, caseSensitive: false),
        within = within == null ? null : RegExp(within, caseSensitive: false);

  bool matches(String enTitle, List<String> ancestors) =>
      title.hasMatch(enTitle) && (within == null || within!.hasMatch(ancestors.join(' / ')));
}

final List<CalloutRule> defaultCallouts = [
  CalloutRule(title: r'psalm 115|^lo lanu', within: r'hallel', when: 'halfHallel',
      en: 'Half Hallel today: skip "Lo lanu" through "yevarech yirei Hashem" (verses 1–11).',
      he: 'חצי הלל: מדלגים "לא לנו" עד "יברך יראי ה׳ הקטנים עם הגדולים".'),
  CalloutRule(title: r'psalm 116|^ahavti', within: r'hallel', when: 'halfHallel',
      en: 'Half Hallel today: skip "Ahavti" through "b\'artzot hachayim" (verses 1–11).',
      he: 'חצי הלל: מדלגים "אהבתי" עד "בארצות החיים".'),
  CalloutRule(title: r'^hallel$', when: 'halfHallel',
      en: 'Half Hallel is said today.', he: 'היום אומרים חצי הלל.'),
  CalloutRule(title: r'^hallel$', when: 'wholeHallel',
      en: 'Whole Hallel is said today.', he: 'היום אומרים הלל שלם.'),
];

/// Gives a condition to a well-known passage by its opening words, for
/// versions that print it without any rubric (e.g. Atah Chonantanu set in
/// small type). Only used when the analyzer found no condition itself.
class ContentRule {
  /// Matched against the start of the passage's normalized Hebrew.
  final RegExp opening;

  /// Optional regex the section id must match.
  final RegExp? within;
  final String when;
  final String labelEn;
  final String labelHe;
  ContentRule(String opening, this.when, this.labelEn, this.labelHe, {String? within})
      : opening = RegExp('^(?:$opening)'),
        within = within == null ? null : RegExp(within, caseSensitive: false);
}

const _amidah = r'amid|shemoneh|esrei';
const _mazon = r'mazon|grace after|bentch|birkat hamazon|birkas hamazon';

final List<ContentRule> defaultContentRules = [
  ContentRule('אתה חוננתנו', 'motzaeiShabbat || motzaeiYomTov', "Motza'ei Shabbat", 'מוצאי שבת', within: _amidah),
  ContentRule('ו?על הנסים', 'chanukah || purim', 'Chanukah / Purim', 'חנוכה / פורים', within: '$_amidah|$_mazon'),
  ContentRule('עננו', 'fastDay', 'Fast day', 'תענית', within: _amidah),
  ContentRule('נחם', 'tishaBav', "Tisha B'Av", 'תשעה באב', within: _amidah),
  ContentRule('זכרנו לחיים|מי כמוך אב הרחמ|וכתוב לחיים|בספר חיים', 'aseretYemeiTeshuva', 'Aseret Yemei Teshuva', 'עשי"ת', within: _amidah),
  ContentRule('ותן טל ומטר', 'talUmatar', 'Winter', 'חורף', within: _amidah),
  ContentRule('ותן ברכה', '!talUmatar', 'Summer', 'קיץ', within: _amidah),
  ContentRule('משיב הרוח', 'mashivHaruach', 'Winter', 'חורף', within: _amidah),
  ContentRule('מוריד הטל', 'moridHatal', 'Summer', 'קיץ', within: _amidah),
  ContentRule('רצה והחליצנו', 'shabbat', 'Shabbat', 'שבת', within: _mazon),
  ContentRule('הרחמן הוא ינחילנו יום שכלו שבת', 'shabbat', 'Shabbat', 'שבת', within: _mazon),
  ContentRule('הרחמן הוא ינחילנו יום שכלו טוב', 'yomTov', 'Yom Tov', 'יום טוב', within: _mazon),
  ContentRule('הרחמן הוא יחדש עלינו', 'roshChodesh', 'Rosh Chodesh', 'ראש חודש', within: _mazon),
  ContentRule('הרחמן הוא יקים לנו את סוכת', 'sukkot', 'Sukkot', 'סוכות', within: _mazon),
];

/// A short, to-the-point note the app shows above a passage on the days it
/// matters — what to add and what to do if you forget — in place of the
/// siddur's long halachic notes.
class CuratedNote {
  /// Matched anywhere in the passage's normalized Hebrew.
  final RegExp anchor;
  final RegExp? within;
  final String when;
  final String en;
  final String he;
  CuratedNote(String anchor, this.when, {String? within, required this.en, required this.he})
      : anchor = RegExp(anchor),
        within = within == null ? null : RegExp(within, caseSensitive: false);

  factory CuratedNote.fromJson(Map<String, Object?> j) {
    final within = j['within'] as String?;
    return CuratedNote(j['anchor'] as String, j['when'] as String,
        within: within == null ? null : curatedNoteScopes[within] ?? within, en: j['en'] as String, he: j['he'] as String);
  }
}

/// Named sections for a note's `within` in assets/rules/notes.json.
const curatedNoteScopes = {'amidah': _amidah, 'mazon': _mazon};

/// The notes in assets/rules/notes.json (`{"notes": [...]}`).
List<CuratedNote> curatedNotesFromJson(Map<String, Object?> json) => [
      for (final n in (json['notes'] as List? ?? const [])) CuratedNote.fromJson((n as Map).cast<String, Object?>()),
    ];
