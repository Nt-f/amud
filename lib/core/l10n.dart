import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Language of the app's own interface (not of the prayer texts).
enum UiLanguage {
  en('English'),
  he('עברית'),
  yi('ייִדיש');

  /// The language's name in itself.
  final String native;
  const UiLanguage(this.native);

  bool get rtl => this != en;
  Locale get locale => Locale(name);
}

/// Interface language and spelling preferences for the widgets below it.
class AppText extends InheritedWidget {
  final UiLanguage lang;

  /// Ashkenazi transliteration of Hebrew terms in English
  /// ("Shabbos", "Sukkos") instead of Sephardi/Israeli ("Shabbat", "Sukkot").
  final bool ashkenazi;

  const AppText({super.key, required this.lang, required this.ashkenazi, required super.child});

  static AppText of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppText>() ?? const AppText(lang: UiLanguage.en, ashkenazi: false, child: SizedBox());

  /// Translates an English UI string; `{name}` placeholders take [args].
  String tr(String en, [Map<String, Object?> args = const {}]) {
    var s = switch (lang) {
      UiLanguage.en => term(en),
      UiLanguage.he => _strings[en]?.$1 ?? term(en),
      UiLanguage.yi => _strings[en]?.$2 ?? _strings[en]?.$1 ?? term(en),
    };
    for (final e in args.entries) {
      s = s.replaceAll('{${e.key}}', '${e.value}');
    }
    return s;
  }

  /// Applies the spelling preference to English content (titles, labels).
  String term(String en) => ashkenazi ? ashkenaziSpelling(en) : en;

  /// Locale for Hebcal's `render()` (dates, holidays, parshiyot).
  String get hebcalLocale => switch (lang) {
        UiLanguage.en => ashkenazi ? 'ashkenazi' : 'en',
        _ => 'he-x-NoNikud',
      };

  @override
  bool updateShouldNotify(AppText old) => old.lang != lang || old.ashkenazi != ashkenazi;
}

extension AppTextContext on BuildContext {
  String tr(String en, [Map<String, Object?> args = const {}]) => AppText.of(this).tr(en, args);
  String term(String en) => AppText.of(this).term(en);
  String get hebcalLocale => AppText.of(this).hebcalLocale;
  UiLanguage get uiLanguage => AppText.of(this).lang;
}

/// Flutter has no Yiddish framework localizations; Yiddish uses the Hebrew
/// ones (right-to-left layout, Hebrew date pickers and dialog buttons).
class YiddishFallbackDelegate<T> extends LocalizationsDelegate<T> {
  final LocalizationsDelegate<T> inner;
  const YiddishFallbackDelegate(this.inner);

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'yi' || inner.isSupported(locale);

  @override
  Future<T> load(Locale locale) => inner.load(locale.languageCode == 'yi' ? const Locale('he') : locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<T> old) => false;
}

const appLocalizationsDelegates = <LocalizationsDelegate<Object?>>[
  YiddishFallbackDelegate<MaterialLocalizations>(GlobalMaterialLocalizations.delegate),
  YiddishFallbackDelegate<WidgetsLocalizations>(GlobalWidgetsLocalizations.delegate),
  YiddishFallbackDelegate<CupertinoLocalizations>(GlobalCupertinoLocalizations.delegate),
];

// --- Ashkenazi spelling -----------------------------------------------------

/// Sephardi/Israeli → Ashkenazi transliterations, matched as whole words
/// (case-insensitive, preserving the original capitalization).
const _ashkenazi = {
  'shabbat': 'Shabbos',
  'shabbatot': 'Shabbosos',
  'shabbaton': 'Shabboson',
  'sukkot': 'Sukkos',
  'shavuot': 'Shavuos',
  'atzeret': 'Atzeres',
  'simchat': 'Simchas',
  'aseret': 'Aseres',
  'teshuva': 'Teshuvah',
  'tevet': 'Teves',
  'shacharit': 'Shacharis',
  'shaharit': 'Shacharis',
  'arvit': 'Arvis',
  'birkat': 'Birchas',
  'birkot': 'Birchos',
  'birchat': 'Birchas',
  'berachot': 'Berachos',
  'brachot': 'Brachos',
  'kabbalat': 'Kabbalas',
  'tefillat': 'Tefillas',
  'keriat': 'Krias',
  'kriat': 'Krias',
  'kriyat': 'Krias',
  "keri'at": 'Krias',
  'sefirat': 'Sefiras',
  'netilat': 'Netilas',
  'hadlakat': 'Hadlakas',
  'chazarat': 'Chazaras',
  'kedushat': 'Kedushas',
  'seudat': 'Seudas',
  'megillat': 'Megillas',
  'bedikat': 'Bedikas',
  'chanukat': 'Chanukas',
  'selichot': 'Selichos',
  'hoshanot': 'Hoshanos',
  "hosha'anot": "Hosha'anos",
  'zemirot': 'Zemiros',
  'avot': 'Avos',
  'gevurot': 'Gevuros',
  'korbanot': 'Korbanos',
  'ketoret': 'Ketores',
  'mitzvot': 'Mitzvos',
  'mitzvat': 'Mitzvas',
  'tallit': 'Tallis',
  'tzitzit': 'Tzitzis',
  'brit': 'Bris',
  'bet': 'Beis',
  'beit': 'Beis',
  'torat': 'Toras',
  'emet': 'Emes',
  'chatzot': 'Chatzos',
  'taanit': "Ta'anis",
  "ta'anit": "Ta'anis",
  'mishnayot': 'Mishnayos',
  'shemot': 'Shemos',
  'bereshit': 'Bereishis',
  'bereishit': 'Bereishis',
  'toldot': 'Toldos',
  'yitro': 'Yisro',
  'ki tisa': 'Ki Sisa',
  'achrei mot': 'Acharei Mos',
  'acharei mot': 'Acharei Mos',
  'bechukotai': 'Bechukosai',
  "beha'alotcha": "Beha'aloscha",
  'chukat': 'Chukas',
  'matot': 'Mattos',
  'matot-masei': 'Mattos-Masei',
  "ki teitzei": 'Ki Seitzei',
  'ki tavo': 'Ki Savo',
  'vezot haberakhah': 'Vezos Haberachah',
  'hashkamat': 'Hashkamas',
  'nishmat': 'Nishmas',
  'kedusha': 'Kedushah',
  'anim zemirot': 'Anim Zemiros',
  'yom haatzmaut': "Yom Ha'atzmaus",
  "yom ha'atzmaut": "Yom Ha'atzmaus",
  'birkat hamazon': 'Birchas Hamazon',
  'alot': 'Alos',
  'tzeit': 'Tzeis',
  'hashmashot': 'HaShmashos',
  'hashemashot': 'HaShemashos',
  'shkiat': 'Shkias',
  'levana': 'Levanah',
  'kiddush levana': 'Kiddush Levanah',
  'chazarat hashatz': 'Chazaras HaShatz',
  'modim derabbanan': 'Modim DeRabbanan',
  'kohanim': 'Kohanim',
  'shaot': 'Shaos',
  'zmaniyot': 'Zmaniyos',
  "v'ten": "V'sein",
  'kinot': 'Kinos',
  'mincha': 'Minchah',
};

final _ashkenaziRe = RegExp(
  '(?<![A-Za-z\'])(${(_ashkenazi.keys.toList()..sort((a, b) => b.length - a.length)).map(RegExp.escape).join('|')})(?![A-Za-z])',
  caseSensitive: false,
);

/// Rewrites Sephardi/Israeli transliterations in [s] to Ashkenazi ones.
String ashkenaziSpelling(String s) => s.replaceAllMapped(_ashkenaziRe, (m) {
      final found = m[0]!;
      final out = _ashkenazi[found.toLowerCase()]!;
      if (found == found.toUpperCase()) return out.toUpperCase();
      if (found[0] == found[0].toLowerCase()) return out[0].toLowerCase() + out.substring(1);
      return out;
    });

// --- Translations -------------------------------------------------------------

/// English → (Hebrew, Yiddish). Missing entries fall back to English.
const Map<String, (String, String)> _strings = {
  // Navigation
  'Home': ('בית', 'היים'),
  'Siddur': ('סידור', 'סידור'),
  'Zmanim': ('זמנים', 'זמנים'),
  'Calendar': ('לוח שנה', 'קאלענדאר'),
  'Torah': ('תורה', 'תורה'),
  'Settings': ('הגדרות', 'איינשטעלונגען'),

  // Settings
  'Location': ('מיקום', 'ארט'),
  'Israel customs': ('מנהגי ארץ ישראל', 'מנהגי ארץ ישראל'),
  "One-day Yom Tov, Israeli parsha schedule, Tal U'Matar from 7 Cheshvan":
      ('יום טוב אחד, סדר הפרשיות של ארץ ישראל, טל ומטר מז׳ חשון', 'איין טאג יום טוב, סדר הפרשיות פון ארץ ישראל, טל ומטר פון ז׳ חשון'),
  'Default opinion': ('שיטה ברירת מחדל', 'שיטה'),
  'Opinion': ('שיטה', 'שיטה'),
  'Elevation-adjusted sunrise/sunset': ('זריחה ושקיעה לפי גובה', 'הנץ און שקיעה לויט דער הייך'),
  'Candle lighting': ('הדלקת נרות', 'ליכט צינדן'),
  '{n} minutes before sunset': ('{n} דקות לפני השקיעה', '{n} מינוט פאר שקיעה'),
  '{n} minutes after sunset': ('{n} דקות אחרי השקיעה', '{n} מינוט נאך שקיעה'),
  '{n} minutes': ('{n} דקות', '{n} מינוט'),
  'Havdalah': ('הבדלה', 'הבדלה'),
  'Nightfall (8.5°)': ('צאת הכוכבים (8.5°)', 'צאת הכוכבים (8.5°)'),
  'Time format': ('תבנית שעה', 'צייט פארמאט'),
  'Automatic': ('אוטומטי', 'אויטאמאטיש'),
  '12-hour': ('12 שעות', '12 שעה'),
  '24-hour': ('24 שעות', '24 שעה'),
  'Default siddur': ('סידור ברירת מחדל', 'דער סידור'),
  'Open-licensed texts only': ('רק טקסטים ברישיון פתוח', 'נאר טעקסטן מיט אן אפענעם ליצענץ'),
  'Only offer versions under public domain / Creative Commons licenses':
      ('הצג רק נוסחים בנחלת הכלל או ברישיון Creative Commons', 'ווייז נאר נוסחאות וואס זענען פרייע (public domain / Creative Commons)'),
  'Show halachic notes': ('הצג הערות הלכתיות', 'ווייז הלכה הערות'),
  'Customs (minhagim)': ('מנהגים', 'מנהגים'),
  'Praying with a minyan': ('תפילה במניין', 'דאווענען מיט א מנין'),
  'Shows Kedusha, Chazarat HaShatz and Kaddish as applicable':
      ('מציג קדושה, חזרת הש״ץ וקדיש לפי העניין', 'ווייזט קדושה, חזרת הש״ץ און קדיש ווען עס פאסט'),
  'LeDavid through Shmini Atzeret': ('לדוד עד שמיני עצרת', 'לדוד ביז שמיני עצרת'),
  'Otherwise until Hoshana Raba': ('אחרת עד הושענא רבה', 'אנדערש ביז הושענא רבה'),
  'Walled city (Shushan Purim)': ('עיר מוקפת חומה (שושן פורים)', 'א שטאט מיט א מויער (שושן פורים)'),
  'Celebrate Purim on the 15th of Adar (e.g. Jerusalem)':
      ('פורים בט״ו באדר (למשל ירושלים)', 'פורים אום ט״ו אדר (למשל ירושלים)'),
  'Kiddush Levana from 3 days': ('קידוש לבנה מ־3 ימים', 'קידוש לבנה פון 3 טעג'),
  'Otherwise from 7 days after the molad': ('אחרת מ־7 ימים אחרי המולד', 'אנדערש פון 7 טעג נאכן מולד'),
  'Mourner (aveil)': ('אבל', 'אבל'),
  'Appearance': ('מראה', 'אויסזען'),
  'Theme': ('ערכת צבעים', 'פארבן'),
  'System': ('לפי המערכת', 'לויט דער סיסטעם'),
  'Light': ('בהיר', 'ליכטיג'),
  'Dark': ('כהה', 'טונקל'),
  'sepia': ('ספיה', 'סעפיע'),
  'Fonts': ('גופנים', 'שריפטן'),
  '{n} fonts to preview': ('{n} גופנים לתצוגה', '{n} שריפטן צו באקוקן'),
  'Interface language': ('שפת הממשק', 'שפראך'),
  'Ashkenazi spelling': ('תעתיק אשכנזי', 'אשכנזישע אויסלייג'),
  'Shabbos, Sukkos, Shacharis in English text': ('Shabbos, Sukkos, Shacharis בטקסט האנגלי', 'Shabbos, Sukkos, Shacharis אויף ענגליש'),
  'Notifications & learning': ('התראות ולימוד', 'מעלדונגען און לערנען'),
  'Zman alerts': ('התראות זמנים', 'זמנים מעלדונגען'),
  'Exact alarms (Android)': ('התראות מדויקות (אנדרואיד)', 'גענויע מעלדונגען (אנדראיד)'),
  'Requires permission; otherwise alerts may be delayed a few minutes':
      ('דורש הרשאה; אחרת ההתראות עלולות להתעכב בכמה דקות', 'פאדערט א דערלויבעניש; אנדערש קענען די מעלדונגען זיך פארשפעטיגן'),
  'Daily learning': ('לימוד יומי', 'טעגליכער לימוד'),
  'Advanced': ('מתקדם', 'פאראויסגעשריטן'),
  'Custom siddur rules': ('כללי סידור מותאמים', 'אייגענע סידור כללים'),
  'Show or hide sections by condition': ('הצג או הסתר קטעים לפי תנאי', 'ווייז אדער באהאלט טיילן לויט א תנאי'),
  'About': ('אודות', 'וועגן'),
  'Licenses & sources': ('רישיונות ומקורות', 'ליצענצן און מקורות'),
  'Sefaria texts, Hebcal (GPL-2.0), fonts (OFL)': ('טקסטים מספריא, Hebcal (GPL-2.0), גופנים (OFL)', 'טעקסטן פון ספריא, Hebcal (GPL-2.0), שריפטן (OFL)'),
  'Custom rules': ('כללים מותאמים', 'אייגענע כללים'),
  'Rules saved': ('הכללים נשמרו', 'די כללים זענען אפגעהיטן'),
  'Save': ('שמירה', 'היטן'),

  // Text display
  'Text': ('טקסט', 'טעקסט'),
  'Prayer text': ('נוסח התפילה', 'נוסח התפילה'),
  'Hebrew': ('עברית', 'לשון קודש'),
  'English': ('אנגלית', 'ענגליש'),
  'Bilingual': ('דו־לשוני', 'צוויי־שפראכיג'),
  'Side by side': ('זה לצד זה', 'זייט ביי זייט'),
  'Hebrew only': ('עברית בלבד', 'נאר לשון קודש'),
  'English only': ('אנגלית בלבד', 'נאר ענגליש'),
  'Hebrew & English': ('עברית ואנגלית', 'לשון קודש און ענגליש'),
  'Instructions & notes': ('הוראות והערות', 'אנווייזונגען און הערות'),
  'Instructions & notes language': ('שפת ההוראות וההערות', 'שפראך פון אנווייזונגען און הערות'),
  'Also used for "said only on…" labels': ('חל גם על תוויות ״נאמר רק ב…״', 'אויך פאר ״מען זאגט נאר…״ צעטלעך'),
  'Hebrew font': ('גופן עברי', 'לשון קודש שריפט'),
  'Today-aware display': ('תצוגה לפי היום', 'ווייזן לויט היינט'),
  'Highlight what applies today': ('הדגש את מה שנאמר היום', 'באצייכן וואס מען זאגט היינט'),
  'Text not said today': ('טקסט שאינו נאמר היום', 'טעקסט וואס מען זאגט נישט היינט'),
  'Text not said today:': ('טקסט שאינו נאמר היום:', 'טעקסט וואס מען זאגט נישט היינט:'),
  'Collapse': ('כיווץ', 'צונויפלייגן'),
  'Dim': ('עמעום', 'בלאס'),
  'Hide completely': ('הסתרה מלאה', 'אינגאנצן באהאלטן'),
  'Hide': ('הסתרה', 'באהאלטן'),
  'Sections, lines and additions not said today are removed. Where one of several options is said, the others stay, crossed out.':
      ('קטעים, שורות ותוספות שאינם נאמרים היום מוסרים. כשאחת מכמה אפשרויות נאמרת, האחרות נשארות מחוקות.',
          'טיילן, שורות און צוגאבן וואס מען זאגט נישט היינט ווערן אראפגענומען. ווען מען זאגט איינע פון עטלעכע ברירות, בלייבן די אנדערע אויסגעשטראכן.'),
  'Short notes': ('הערות קצרות', 'קורצע הערות'),
  "Brief notes only when they apply today, instead of the siddur's full notes":
      ('הערות תמציתיות רק כשהן נוגעות להיום, במקום ההערות המלאות של הסידור', 'קורצע הערות נאר ווען זיי פאסן היינט, אנשטאט דעם סידור׳ס פולע הערות'),
  'Show instructions': ('הצג הוראות', 'ווייז אנווייזונגען'),
  'Text versions': ('נוסחי טקסט', 'נוסחאות'),
  'Choose and order Hebrew text and translations': ('בחירה וסידור של נוסחים ותרגומים', 'קלייבן און סדר׳ן נוסחאות און איבערזעצונגען'),
  'Translations': ('תרגומים', 'איבערזעצונגען'),
  'Available': ('זמינים', 'פאראן'),
  'For each section the first version (top to bottom) that contains it is shown. Drag to reorder.':
      ('בכל קטע מוצג הנוסח הראשון (מלמעלה למטה) שמכיל אותו. גררו כדי לסדר מחדש.', 'ביי יעדן טייל ווערט געוויזן דער ערשטער נוסח (פון אויבן) וואס האט אים. שלעפט כדי איבערצוסדר׳ן.'),

  // Reader
  'Date': ('תאריך', 'דאטום'),
  'Text settings': ('הגדרות טקסט', 'טעקסט איינשטעלונגען'),
  'Pray as of…': ('תפילה לתאריך…', 'דאווענען אויף…'),
  'Today': ('היום', 'היינט'),
  'Added today: {label}': ('נוסף היום: {label}', 'צוגעלייגט היינט: {label}'),
  '{title} — not said today': ('{title} — אינו נאמר היום', '{title} — מען זאגט נישט היינט'),
  '{n} lines not said today': ('{n} שורות שאינן נאמרות היום', '{n} שורות וואס מען זאגט נישט היינט'),
  'Not today · {label}': ('לא היום · {label}', 'נישט היינט · {label}'),
  'Not said today': ('אינו נאמר היום', 'מען זאגט נישט היינט'),
  'Tap to show it anyway': ('הקישו כדי להציג בכל זאת', 'דריקט כדי עס סיי ווי צו ווייזן'),
  'Next: {title}': ('הבא: {title}', 'ווייטער: {title}'),
  "Tonight's count · day {n}": ('ספירת הלילה · יום {n}', 'היינט ביינאכט · טאג {n}'),

  // Library
  'Siddurim': ('סידורים', 'סידורים'),
  'Make default': ('קבע כברירת מחדל', 'מאך עס דער הויפט'),
  'Default': ('ברירת מחדל', 'הויפט'),
  'Read': ('קריאה', 'לייענען'),
  'Today · {book}': ('היום · {book}', 'היינט · {book}'),
  '{he} Hebrew · {en} translation versions': ('{he} נוסחים בעברית · {en} תרגומים', '{he} נוסחאות אין לשון קודש · {en} איבערזעצונגען'),
  "Texts from {source}, bundled for offline use. Each version's license and source are shown under Text versions.":
      ('טקסטים מ־{source}, זמינים ללא חיבור. הרישיון והמקור של כל נוסח מופיעים ב״נוסחי טקסט״.', 'טעקסטן פון {source}, צו ניצן אן אינטערנעט. דער ליצענץ און מקור פון יעדן נוסח שטייען אונטער ״נוסחאות״.'),
  'Shacharit': ('שחרית', 'שחרית'),
  'Mincha': ('מנחה', 'מנחה'),
  'Maariv': ('ערבית', 'מעריב'),
  'Sefirat HaOmer': ('ספירת העומר', 'ספירת העומר'),
  'Hallel': ('הלל', 'הלל'),
  'Kiddush Levana': ('קידוש לבנה', 'קידוש לבנה'),
  'Birkat HaMazon': ('ברכת המזון', 'בענטשן'),
  'Tefillat HaDerech': ('תפילת הדרך', 'תפילת הדרך'),
  'Bedtime Shema': ('קריאת שמע על המיטה', 'קריאת שמע שעל המטה'),
  "Me'ein Shalosh": ('ברכה מעין שלוש', 'ברכה מעין שלש'),
  'Al HaMichya': ('על המחיה', 'על המחיה'),
  'Al HaGefen': ('על הגפן', 'על הגפן'),
  'Al HaEtz': ('על העץ', 'על העץ'),
  'Cake, crackers, pasta · 5 grains': ('עוגה, קרקרים, פסטה · ה׳ מיני דגן', 'קוכן, קרעקערס, לאקשן · ה׳ מיני דגן'),
  'Wine, grape juice': ('יין, מיץ ענבים', 'וויין, ווייַנטרויבן זאפט'),
  'Grapes, figs, pomegranates, olives, dates': ('ענבים, תאנים, רימונים, זיתים, תמרים', 'ווייַנטרויבן, פייגן, מילגרוים, איילבערטן, טייטלען'),
  'Tap what you ate to build the bracha': ('בחרו מה אכלתם כדי להרכיב את הברכה', 'קלאַפּט וואס איר האט געגעסן'),
  'Tap again to show all': ('הקישו שוב כדי להציג הכל', 'קלאַפּט נאכאמאל צו ווייַזן אלץ'),
  'Show all': ('הצג הכל', 'ווייַזן אלץ'),

  // Fonts
  'Hebrew fonts': ('גופנים עבריים', 'לשון קודש שריפטן'),
  'Search fonts': ('חיפוש גופן', 'זוכן א שריפט'),
  'Blessing': ('ברכה', 'ברכה'),
  "Te'amim": ('טעמים', 'טעמים'),
  'Alef-bet': ('אלף־בית', 'אלף־בית'),
  'Unpointed': ('ללא ניקוד', 'אן נקודות'),
  'Or type your own preview text…': ('או הקלידו טקסט לתצוגה…', 'אדער שרייבט אייער אייגענעם טעקסט…'),
  'All ({n})': ('הכול ({n})', 'אלע ({n})'),
  'Bundled fonts work offline. Others download from Google Fonts to preview, and are saved on this device once chosen.':
      ('גופנים מובנים פועלים ללא חיבור. האחרים יורדים מ־Google Fonts לתצוגה, ונשמרים במכשיר לאחר שנבחרו.', 'איינגעבויטע שריפטן ארבעטן אן אינטערנעט. די אנדערע ווערן אראפגעלאדן פון Google Fonts, און ווערן אפגעהיטן ווען מען קלייבט זיי אויס.'),
  'Upload font': ('העלאת גופן', 'ארויפלאדן א שריפט'),
  'Remove': ('הסרה', 'אראפנעמען'),
  'Make compact': ('הקטנה', 'מאך קליין'),
  'Make wide': ('הרחבה', 'מאך ברייט'),
  'Configure': ('הגדרה', 'איינשטעלן'),
  'Wide': ('רחב', 'ברייט'),
  'Compact': ('קומפקטי', 'קליין'),
  'All': ('הכול', 'אלע'),
  'Edit dashboard': ('עריכת לוח הבית', 'רעדאקטירן די היים'),
  'Done': ('סיום', 'פארטיק'),
  'Add card': ('הוספת כרטיס', 'צולייגן א קארטל'),
  'Reset layout': ('איפוס הפריסה', 'צוריקשטעלן'),
  'Reset dashboard?': ('לאפס את לוח הבית?', 'צוריקשטעלן די היים?'),
  'Restore the default cards.': ('החזרת כרטיסי ברירת המחדל.', 'צוריקברענגען די ערשטע קארטלעך.'),
  'Update': ('עדכון', 'דערהײַנטיקן'),
  'Update now': ('עדכון עכשיו', 'דערהײַנטיקן יעצט'),
  'Dismiss': ('סגירה', 'פארמאכן'),
  'Version {v} is available': ('גרסה {v} זמינה', 'ווערסיע {v} איז גרייט'),
  'Updated to {v}': ('עודכן לגרסה {v}', 'דערהײַנטיקט צו {v}'),
  "What's new in {v}": ('מה חדש ב־{v}', 'וואס איז נײַ אין {v}'),
  'Downloading… {p}%': ('מוריד… {p}%', 'לאדט אראפ… {p}%'),
  'Allow Siddur to install apps, then come back here to finish the update.':
      ('אפשרו לסידור להתקין אפליקציות, ואז חזרו לכאן כדי לסיים את העדכון.', 'דערלויבט דעם סידור צו אינסטאלירן אפליקאציעס, און קומט צוריק אהער צו ענדיקן.'),
  'Allow and install': ('אישור והתקנה', 'דערלויבן און אינסטאלירן'),
  'Android asks you to confirm the update. Your settings and data are kept.':
      ('אנדרואיד יבקש לאשר את העדכון. ההגדרות והנתונים שלכם נשמרים.', 'אנדרויד וועט פרעגן צו באשטעטיקן. אייערע איינשטעלונגען בלייבן.'),
  'Retry': ('נסו שוב', 'פרובירט נאכאמאל'),
  "Couldn't load preview": ('לא ניתן לטעון תצוגה', 'מען קען נישט ווייזן'),
  "Couldn't download {font}": ('לא ניתן להוריד את {font}', 'מען קען נישט אראפלאדן {font}'),
  'Offline': ('ללא חיבור', 'אן אינטערנעט'),
  'Download': ('להורדה', 'אראפלאדן'),
  "Siddur & te'amim": ('סידור וטעמים', 'סידור און טעמים'),
  'Serif': ('סריף', 'סעריף'),
  'Sans serif': ('ללא סריף', 'אן סעריף'),
  'Handwriting': ('כתב יד', 'האנטשריפט'),
  'STaM (scribal)': ('סת״ם', 'סת״ם'),
  'Display': ('תצוגה', 'דעקאראטיוו'),
  'Monospace': ('ברוחב קבוע', 'גלייכע ברייט'),
  'Uploaded': ('הועלו', 'ארויפגעלאדן'),

  "Show te'amim (trop)": ('הצג טעמים', 'ווייז טעמים'),
  'Show nikud (vowels)': ('הצג ניקוד', 'ווייז נקודות'),
  "Prefer texts with te'amim": ('העדף נוסחים עם טעמים', 'בעסער נוסחאות מיט טעמים'),
  'e.g. the Shema with cantillation': ('למשל קריאת שמע בטעמים', 'למשל קריאת שמע מיט טעמים'),
  "This font has no te'amim; passages with trop use {font}.": ('בגופן זה אין טעמים; קטעים עם טעמים יוצגו ב־{font}.', 'די שריפט האט נישט קיין טעמים; טיילן מיט טעמים ווערן געוויזן אין {font}.'),
  "With te'amim": ('עם טעמים', 'מיט טעמים'),
  "Te'amim ✓": ('טעמים ✓', 'טעמים ✓'),
  'Nikud only': ('ניקוד בלבד', 'נאר נקודות'),
  'No nikud': ('ללא ניקוד', 'אן נקודות'),

  // Tehillim
  'Tehillim': ('תהלים', 'תהלים'),
  'Chapters': ('פרקים', 'קאפיטלעך'),
  'Lists': ('רשימות', 'רשימות'),
  'By name': ('לפי השם', 'לויטן נאמען'),
  'Search': ('חיפוש', 'זוכן'),
  'Your progress through Sefer Tehillim': ('ההתקדמות שלך בספר תהלים', 'אייער פארשריט אין ספר תהלים'),
  '{n} of 150 chapters read this cycle': ('{n} מתוך 150 פרקים נאמרו בסבב זה', '{n} פון 150 קאפיטלעך געזאגט אין דעם סבב'),
  '{n} completions': ('{n} סיומים', '{n} סיומים'),
  'Continue at Psalm {n}': ('המשך בפרק {n}', 'גייט ווייטער ביי קאפיטל {n}'),
  'Next unread: Psalm {n}': ('הבא שלא נאמר: פרק {n}', 'דער קומענדיגער: קאפיטל {n}'),
  'Start a new cycle?': ('להתחיל סבב חדש?', 'אנהייבן א נייעם סבב?'),
  'Clears the chapters marked as read.': ('מנקה את הסימון של הפרקים שנאמרו.', 'מעקט אויס די באצייכנטע קאפיטלעך.'),
  'Reset': ('איפוס', 'פון אנפאנג'),
  'The five books': ('חמשת הספרים', 'די פינף ספרים'),
  'Weekly cycle': ('סדר שבועי', 'וועכנטליכער סדר'),
  'Book One': ('ספר ראשון', 'ספר ראשון'),
  'Book Two': ('ספר שני', 'ספר שני'),
  'Book Three': ('ספר שלישי', 'ספר שלישי'),
  'Book Four': ('ספר רביעי', 'ספר רביעי'),
  'Book Five': ('ספר חמישי', 'ספר חמישי'),
  'Tap to read · long-press to mark as read': ('הקישו לקריאה · לחיצה ארוכה לסימון כנאמר', 'דריקט צו לייענען · האלט לאנג צו באצייכענען'),
  'My lists': ('הרשימות שלי', 'מיינע רשימות'),
  'Make your own selection, e.g. for someone who needs a refuah.': ('צרו רשימה משלכם, למשל עבור מי שזקוק לרפואה.', 'מאכט אייער אייגענע רשימה, למשל פאר איינעם וואס דארף א רפואה.'),
  'Edit': ('עריכה', 'רעדאגירן'),
  'New list': ('רשימה חדשה', 'נייע רשימה'),
  'For special needs': ('לעניינים מיוחדים', 'פאר באזונדערע צוועקן'),
  'Selections commonly said; customs vary.': ('פרקים שנוהגים לומר; המנהגים שונים.', 'קאפיטלעך וואס מען פלעגט זאגן; מנהגים זענען פארשידן.'),
  'Copy to my lists': ('העתק לרשימות שלי', 'קאפירן צו מיינע רשימות'),
  'Copied to my lists': ('הועתק לרשימות שלי', 'קאפירט צו מיינע רשימות'),
  'My list': ('הרשימה שלי', 'מיין רשימה'),
  'Use chapter numbers 1–150, e.g. 20, 6, 119:1-8': ('השתמשו במספרי פרקים 1–150, למשל 20, 6, 119:1-8', 'שרייבט קאפיטל נומערן 1–150, למשל 20, 6, 119:1-8'),
  'Psalm 119 by name': ('קי״ט לפי אותיות השם', 'קי״ט לויט די אותיות פונעם נאמען'),
  'Psalm 119 has a stanza of eight verses for each Hebrew letter. Say the stanzas that spell a name, e.g. for someone who is ill or in memory of the departed.':
      ('במזמור קי״ט יש שמונה פסוקים לכל אות. אומרים את הפסוקים של אותיות השם, למשל לרפואת חולה או לעילוי נשמה.', 'אין קאפיטל קי״ט זענען דא אכט פסוקים פאר יעדן אות. מען זאגט די פסוקים פון די אותיות פונעם נאמען, למשל פאר א חולה אדער לעילוי נשמה.'),
  'Hebrew name': ('שם בעברית', 'נאמען'),
  'Add נשמה (in memory)': ('הוסף נשמה (לעילוי נשמה)', 'צולייגן נשמה (לעילוי נשמה)'),
  'Read {n} stanzas': ('קריאת {n} קטעים', 'לייענען {n} טיילן'),
  'Save to my lists': ('שמירה ברשימות שלי', 'אפהיטן אין מיינע רשימות'),
  'Your personal psalm': ('המזמור האישי שלך', 'אייער אייגענער קאפיטל'),
  'Many say the psalm matching the year of life they are in: their age plus one.': ('רבים אומרים את המזמור לפי שנת חייהם: הגיל ועוד אחת.', 'אסאך זאגן דעם קאפיטל לויט זייער יאר: די עלטער פלוס איינס.'),
  'Age': ('גיל', 'עלטער'),
  'Search Hebrew or English': ('חיפוש בעברית או באנגלית', 'זוכן אויף לשון קודש אדער ענגליש'),
  'No matches': ('לא נמצאו תוצאות', 'גארנישט געפונען'),
  'Psalm {n}': ('פרק {n}', 'קאפיטל {n}'),
  'Mark as read': ('סמן כנאמר', 'באצייכענען אלס געזאגט'),
  'Mark as unread': ('בטל סימון', 'אראפנעמען דעם צייכן'),
  'Marked as read': ('סומן כנאמר', 'באצייכנט אלס געזאגט'),
  'Mark all as read': ('סמן הכול כנאמר', 'באצייכענען אלעס אלס געזאגט'),
  'Sefer Tehillim completed!': ('ספר תהלים הושלם!', 'ספר תהלים געענדיגט!'),
  'All 150 chapters are read. A new cycle has begun.': ('כל 150 הפרקים נאמרו. סבב חדש התחיל.', 'אלע 150 קאפיטלעך זענען געזאגט. א נייער סבב הייבט זיך אן.'),
  'Amen': ('אמן', 'אמן'),
  'Show ketiv': ('הצג כתיב', 'ווייז כתיב'),
  'The written form beside the one that is read (qere)': ('הכתיב לצד הקרי', 'דער כתיב לעבן דעם קרי'),
  'Verse numbers': ('מספרי פסוקים', 'פסוק נומערן'),
  'One verse per line': ('פסוק בכל שורה', 'יעדער פסוק אויף א באזונדערע שורה'),
  "Read today's Tehillim": ('תהלים של היום', 'היינטיגע תהלים'),

  // Home cards
  'Sefirat HaOmer · tonight': ('ספירת העומר · הלילה', 'ספירת העומר · היינט ביינאכט'),
  'Minyanim near {place}': ('מניינים ליד {place}', 'מנינים נעבן {place}'),
  'A regular weekday.': ('יום חול רגיל.', 'א געווענליכער וואכנטאג.'),

  'Davening': ('תפילות', 'דאווענען'),
  'After meals': ('אחרי האוכל', 'נאכן עסן'),
  'More': ('עוד', 'נאך'),
  'Not found in this siddur': ('לא נמצא בסידור זה', 'נישט געפונען אין דעם סידור'),

  "GitHub couldn't be reached. Check your internet connection.": ('לא ניתן להתחבר ל-GitHub. בדקו את החיבור לאינטרנט.', 'מען קען נישט דערגרייכן GitHub. קוקט איבער אייער אינטערנעט פארבינדונג.'),

  // What's new
  "What's new": ('מה חדש', 'וואס איז נייעס'),
  'Got it': ('הבנתי', 'פארשטאנען'),
  'Focus mode': ('מצב מיקוד', 'פאקוס מאדע'),
  'Double-tap the text while praying to hide the top and bottom bars. Double-tap again to bring them back.':
      ('הקישו פעמיים על הטקסט בזמן התפילה כדי להסתיר את הסרגלים העליון והתחתון. הקישו פעמיים שוב כדי להחזיר אותם.',
       'טאפט צוויי מאל אויפן טעקסט בשעתן דאווענען צו באהאלטן די אויבערשטע און אונטערשטע ליניעס. טאפט נאכאמאל צוויי מאל זיי צוריקצוברענגען.'),

  "The whole day's davening in order, with what's added today, such as Hallel, Musaf or the day's Hoshanot. Open it from Today in the siddur on Home, or from the Siddur tab. Under each section, links lead to what comes next today and to related prayers.":
      ('כל תפילות היום לפי הסדר, עם מה שמוסיפים היום, כמו הלל, מוסף או ההושענא של היום. פותחים מ"היום בסידור" במסך הבית או מלשונית הסידור. מתחת לכל קטע יש קישורים למה שבא אחריו היום ולתפילות קשורות.',
       'אלע תפילות פונעם טאג לויטן סדר, מיט וואס מען לייגט צו היינט, ווי הלל, מוסף אדער די הושענא פון היינט. עפנט עס פון "היינט אינעם סידור" אויף דער היים, אדער פונעם סידור. אונטער יעדן טייל פירן לינקס צו וואס קומט ווייטער היינט און צו שייכותדיקע תפילות.'),
  'Hoshanot, Lulav, Selichot, Chanukah candles and other holiday prayers in one place, with the ones for today marked. Find it in the Siddur tab.':
      ('הושענות, לולב, סליחות, נרות חנוכה ושאר תפילות המועדים במקום אחד, ושל היום מסומנות. בלשונית הסידור.',
       'הושענות, לולב, סליחות, חנוכה ליכט און אנדערע יום טוב תפילות אויף איין ארט, מיט די פון היינט אנגעצייכנט. אינעם סידור.'),
  'Show prayer titles in English, Hebrew or both, whatever the app language. Under Settings → Siddur, or Text settings in the reader.':
      ('הצגת שמות התפילות באנגלית, בעברית או בשתיהן, בלי קשר לשפת הממשק. בהגדרות ← סידור, או בהגדרות הטקסט בקורא.',
       'ווייזט די נעמען פון די תפילות אויף ענגליש, לשון קודש אדער ביידע, אומגעקוקט אויף דער שפראך פון דער אפ. אין איינשטעלונגען ← סידור, אדער טעקסט איינשטעלונגען אינעם לייענער.'),

  // Location
  'Search cities': ('חיפוש עיר', 'זוכן א שטאט'),
  'Use my location': ('המיקום שלי', 'מיין ארט'),
  'Manual': ('ידני', 'מיט דער האנט'),
  'Name': ('שם', 'נאמען'),
  'Latitude': ('קו רוחב', 'ברייט'),
  'Longitude': ('קו אורך', 'לענג'),
  'Elevation (m)': ('גובה (מ׳)', 'הייך (מ׳)'),
  'Time zone': ('אזור זמן', 'צייט זאנע'),

  // Today's davening, Holidays & Seasons, related prayers
  "Today's davening": ('סדר התפילות להיום', 'די היינטיקע תפילות'),
  'Full order': ('הסדר המלא', 'דער גאנצער סדר'),
  "Tap for today's davening, in order": ('הקישו לסדר התפילות של היום', 'טאפט פאר די היינטיקע תפילות לויטן סדר'),
  'Tonight': ('הלילה', 'היינט ביינאכט'),
  'Read all': ('לקריאה ברצף', 'לייענען אלץ'),
  'From {book}': ('מתוך {book}', 'פון {book}'),
  'Not said today: {list}': ('לא אומרים היום: {list}', 'מען זאגט נישט היינט: {list}'),
  'The bundled siddurim have no machzor for Rosh Hashana and Yom Kippur. The order below is the regular Shabbat and Yom Tov one.':
      ('בסידורים שבאפליקציה אין מחזור לראש השנה וליום הכפורים. הסדר שלהלן הוא הסדר הרגיל של שבת ויום טוב.',
       'אין די סידורים פון דער אפ איז נישטא קיין מחזור פאר ראש השנה און יום כיפור. דער סדר דא אונטן איז דער געווענליכער פון שבת און יום טוב.'),
  'Holidays & Seasons': ('מועדים וזמנים', 'יום טובים און צייטן'),
  'Hoshanot, Lulav, Selichot, Chanukah candles and more': ('הושענות, לולב, סליחות, נרות חנוכה ועוד', 'הושענות, לולב, סליחות, חנוכה ליכט און נאך'),
  'Also today': ('גם היום', 'אויך היינט'),
  'Related prayers': ('תפילות קשורות', 'שייכותדיקע תפילות'),
  '{parsha} · Shabbat {date}': ('{parsha} · שבת {date}', '{parsha} · שבת {date}'),

  // Prayer title language
  'Prayer title language': ('שפת שמות התפילות', 'שפראך פון די נעמען פון די תפילות'),
  'Prayer titles': ('שמות התפילות', 'נעמען פון די תפילות'),
  'Same as the app': ('כשפת הממשק', 'ווי די שפראך פון דער אפ'),
  'English & Hebrew': ('אנגלית ועברית', 'ענגליש און לשון קודש'),
  'Auto': ('אוטומטי', 'אויטאמאטיש'),
  'Both': ('שתיהן', 'ביידע'),

  // Screens, cards and setup
  'API': ('API', 'API'),
  'Add a card': ('הוספת כרטיס', 'צולייגן א קארטל'),
  'Add alerts any time from the Zmanim page: tap a zman, then “Notify me”.': ('אפשר להוסיף התראות בכל עת ממסך הזמנים: הקישו על זמן ואז "הזכר לי".', 'מען קען צולייגן מעלדונגען ווען מען וויל פון די זמנים: טאפט א זמן, דערנאך "דערמאן מיר".'),
  'After sunset · the day of {date} has ended': ('אחרי השקיעה · היום של {date} הסתיים', 'נאך שקיעה · דער טאג פון {date} איז פארביי'),
  'Alerts': ('התראות', 'מעלדונגען'),
  'Allow notifications': ('אישור התראות', 'דערלויבן מעלדונגען'),
  'App updates': ('עדכוני האפליקציה', 'דערהײַנטיקונגען פון דער אפ'),
  'Back': ('חזרה', 'צוריק'),
  'Cancel': ('ביטול', 'בטל מאכן'),
  'Change': ('שינוי', 'טוישן'),
  'Check for updates automatically': ('בדיקת עדכונים אוטומטית', 'קוקן אויטאמאטיש נאך דערהײַנטיקונגען'),
  'Check now': ('בדיקה עכשיו', 'קוקן יעצט'),
  'Checking for updates…': ('מחפש עדכונים…', 'מען קוקט נאך דערהײַנטיקונגען…'),
  'Choose zmanim (none selected = defaults for your opinion setting)': ('בחרו זמנים (בלי בחירה = ברירת המחדל לפי השיטה שנבחרה)', 'קלייבט זמנים (אן א ברירה = די געווענליכע לויט אייער שיטה)'),
  'Collapse Chazarat HaShatz': ('קיפול חזרת הש״ץ', 'צונויפלייגן חזרת הש״ץ'),
  'Collapse halachic notes': ('קיפול הערות הלכתיות', 'צונויפלייגן הלכה הערות'),
  'Coming up': ('בקרוב', 'באלד'),
  'Condition variables': ('משתני תנאים', 'תנאי פאראמעטערס'),
  'Configure {card}': ('הגדרת {card}', 'איינשטעלן {card}'),
  'Couldn\'t check for updates: {e}': ('לא ניתן לבדוק עדכונים: {e}', 'מען קען נישט קוקן נאך דערהײַנטיקונגען: {e}'),
  'Custom zman': ('זמן מותאם', 'אייגענער זמן'),
  'Day defined by': ('היום מוגדר לפי', 'דער טאג לויט'),
  'Delete custom zman': ('מחיקת זמן מותאם', 'אויסמעקן אייגענעם זמן'),
  'Edit custom zman': ('עריכת זמן מותאם', 'רעדאגירן אייגענעם זמן'),
  'Halachic note': ('הערה הלכתית', 'הלכה הערה'),
  'Installed: {v}': ('מותקן: {v}', 'אינסטאלירט: {v}'),
  'Kedusha, Birkat Kohanim and Modim DeRabbanan fold into a row': ('קדושה, ברכת כהנים ומודים דרבנן מקופלים לשורה אחת', 'קדושה, ברכת כהנים און מודים דרבנן ווערן צונויפגעלייגט אין איין שורה'),
  'Long-press to star a schedule. Links open the text on Sefaria.': ('לחיצה ארוכה מסמנת לימוד בכוכב. הקישורים פותחים את הטקסט בספריא.', 'האלט געדריקט צו צייכענען א לימוד מיט א שטערן. די לינקס עפענען דעם טעקסט אויף ספריא.'),
  'Minutes before sunset': ('דקות לפני השקיעה', 'מינוט פאר שקיעה'),
  'Minutes: {n} (after)': ('דקות: {n} (אחרי)', 'מינוט: {n} (נאך)'),
  'Minutes: {n} (before)': ('דקות: {n} (לפני)', 'מינוט: {n} (פאר)'),
  'Modim DeRabbanan': ('מודים דרבנן', 'מודים דרבנן'),
  'More fonts': ('גופנים נוספים', 'נאך שריפטן'),
  'My zmanim': ('הזמנים שלי', 'מיינע זמנים'),
  'Neutral': ('ניטרלי', 'נייטראל'),
  'New alert': ('התראה חדשה', 'נייע מעלדונג'),
  'No alerts yet. Tap a zman on the Zmanim page or “New alert”.': ('אין עדיין התראות. הקישו על זמן במסך הזמנים או על "התראה חדשה".', 'נאך קיין מעלדונגען. טאפט א זמן ביי די זמנים אדער "נייע מעלדונג".'),
  'No events': ('אין אירועים', 'קיין געשעענישן'),
  'No upcoming zmanim': ('אין זמנים קרובים', 'קיין קומענדיקע זמנים'),
  'Notifications allowed': ('ההתראות אושרו', 'מעלדונגען דערלויבט'),
  'Notify me': ('הזכר לי', 'דערמאן מיר'),
  'Offset': ('הפרש', 'אונטערשייד'),
  'On this platform alerts fire while the app is open.': ('במכשיר זה ההתראות פועלות כשהאפליקציה פתוחה.', 'אויף דעם מכשיר ארבעטן די מעלדונגען ווען די אפ איז אפן.'),
  'Once a day; you get a notification when a new version is out': ('פעם ביום; תקבלו התראה כשיוצאת גרסה חדשה', 'איינמאל א טאג; איר באקומט א מעלדונג ווען א נייע ווערסיע קומט ארויס'),
  'Permission was not granted. You can allow it later in your device settings.': ('ההרשאה לא ניתנה. אפשר לאשר אותה אחר כך בהגדרות המכשיר.', 'די דערלויבעניש איז נישט געגעבן געווארן. מען קען עס שפעטער דערלויבן אין די איינשטעלונגען פונעם מכשיר.'),
  'Relative to': ('ביחס ל', 'לויט'),
  'Release page': ('דף הגרסה', 'ווערסיע בלאט'),
  'Reschedule now': ('תזמון מחדש', 'איבערשטעלן יעצט'),
  'Run preview': ('הרצת תצוגה מקדימה', 'לויפן א פארשוי'),
  'Save alert': ('שמירת ההתראה', 'אפהיטן די מעלדונג'),
  'Scheduled {n} notifications': ('תוזמנו {n} התראות', '{n} מעלדונגען צוגעשטעלט'),
  'Script': ('סקריפט', 'סקריפט'),
  'Send a test notification': ('שליחת התראת בדיקה', 'שיקן א פרוּוו מעלדונג'),
  'Set a reminder before or after this zman': ('תזכורת לפני הזמן הזה או אחריו', 'א דערמאנונג פאר אדער נאך דעם זמן'),
  'Show a one-line note; tap to read it': ('הצגת שורה אחת; הקישו כדי לקרוא', 'ווייזן איין שורה; טאפט צו לייענען'),
  'Siddur is up to date': ('הסידור מעודכן', 'דער סידור איז דערהײַנטיקט'),
  'Skip': ('דילוג', 'איבערשפרינגען'),
  'Skip this version': ('דילוג על גרסה זו', 'איבערשפרינגען די ווערסיע'),
  'Sun angle': ('זווית השמש', 'זון ווינקל'),
  'Sun {deg}° below the horizon': ('השמש {deg}° מתחת לאופק', 'די זון {deg}° אונטערן האריזאנט'),
  'Title': ('כותרת', 'קעפל'),
  'Today: {time}': ('היום: {time}', 'היינט: {time}'),
  'Tonight: {date}': ('הלילה: {date}', 'היינט ביינאכט: {date}'),
  'Version {v}': ('גרסה {v}', 'ווערסיע {v}'),
  'Warmth': ('חמימות', 'ווארעמקייט'),
  'Your browser will ask for permission to share your location.': ('הדפדפן יבקש רשות לשתף את המיקום שלכם.', 'דער בראוזער וועט בעטן א דערלויבעניש צו טיילן אייער ארט.'),
  'Zman': ('זמן', 'זמן'),
  'A text note or kavanah': ('הערה או כוונה', 'א הערה אדער כוונה'),
  'Choose your nusach, how prayers are shown and the Hebrew typeface.': ('בחרו נוסח, את אופן הצגת התפילות ואת הגופן העברי.', 'קלייבט אייער נוסח, ווי די תפילות ווערן געוויזן און די אותיות.'),
  'Countdown to the next halachic time': ('ספירה לאחור לזמן הבא', 'ווי לאנג ביזן קומענדיקן זמן'),
  'Custom JS card': ('כרטיס JS מותאם', 'אייגענער JS קארטל'),
  'Daf Yomi, Mishna Yomi, Rambam and more (Hebcal)': ('דף יומי, משנה יומית, רמב״ם ועוד (Hebcal)', 'דף יומי, משניות, רמב״ם און נאך (Hebcal)'),
  'Date, parsha and today\'s holidays': ('תאריך, פרשה ומועדי היום', 'דאטום, פרשה און די היינטיקע יום טובים'),
  'Find a minyan': ('חיפוש מניין', 'געפינען א מנין'),
  'Get a reminder before a zman, like the latest time for Shema or candle lighting.': ('קבלו תזכורת לפני זמן, כמו סוף זמן קריאת שמע או הדלקת נרות.', 'באקומט א דערמאנונג פאר א זמן, ווי סוף זמן קריאת שמע אדער ליכט צינדן.'),
  'Hebrew date': ('תאריך עברי', 'אידישע דאטום'),
  'Holidays and special days ahead': ('מועדים וימים מיוחדים שבקרוב', 'יום טובים און באזונדערע טעג וואס קומען'),
  'Let\'s set up your siddur. You can change any of this later in Settings.': ('בואו נגדיר את הסידור. אפשר לשנות הכול אחר כך בהגדרות.', 'לאמיר איינשטעלן אייער סידור. מען קען אלץ שפעטער טוישן אין די איינשטעלונגען.'),
  'My card': ('הכרטיס שלי', 'מיין קארטל'),
  'Next candle lighting and havdalah': ('הדלקת הנרות וההבדלה הבאות', 'דאס קומענדיקע ליכט צינדן און הבדלה'),
  'Next zman': ('הזמן הבא', 'דער קומענדיקער זמן'),
  'Note': ('הערה', 'הערה'),
  'Quick prayers': ('תפילות מהירות', 'שנעלע תפילות'),
  'Search minyanim nearby on GoDaven': ('חיפוש מניינים בסביבה ב־GoDaven', 'זוכן מנינים נעבן אייך אויף GoDaven'),
  'Shabbat & Yom Tov': ('שבת ויום טוב', 'שבת און יום טוב'),
  'Shortcuts into the siddur': ('קיצורי דרך לסידור', 'שנעלע וועגן אינעם סידור'),
  'Sunrise and sunset as seen from your elevation': ('זריחה ושקיעה כפי שנראות מהגובה שלכם', 'הנץ און שקיעה ווי מען זעט פון אייער הייך'),
  'The siddur knows the date and shows what is said today.': ('הסידור יודע את התאריך ומראה מה אומרים היום.', 'דער סידור ווייסט דעם דאטום און ווייזט וואס מען זאגט היינט.'),
  'Today in the siddur': ('היום בסידור', 'היינט אינעם סידור'),
  'Today\'s zmanim at a glance': ('זמני היום במבט אחד', 'די היינטיקע זמנים מיט איין בליק'),
  'Tonight\'s count with sefira (only during the Omer)': ('הספירה של הלילה עם הספירה (רק בימי העומר)', 'די היינטיקע ספירה (נאר אין ספירה)'),
  'Unknown card': ('כרטיס לא מוכר', 'אומבאקאנטער קארטל'),
  'Upcoming': ('בקרוב', 'קומענדיק'),
  'Use elevation': ('שימוש בגובה', 'ניצן די הייך'),
  'Used for zmanim, candle lighting and Israel or diaspora customs.': ('משמש לזמנים, להדלקת נרות ולמנהגי ארץ ישראל או חוץ לארץ.', 'פאר זמנים, ליכט צינדן און מנהגי ארץ ישראל אדער חוץ לארץ.'),
  'Welcome': ('ברוכים הבאים', 'ברוך הבא'),
  'What\'s added or skipped in today\'s prayers': ('מה מוסיפים ומה מדלגים בתפילות היום', 'וואס מען לייגט צו אדער שפרינגט איבער היינט'),
  'Which opinion to show by default. The Zmanim page can show all of them.': ('איזו שיטה להציג כברירת מחדל. מסך הזמנים יכול להציג את כולן.', 'וועלכע שיטה צו ווייזן. ביי די זמנים קען מען זען אלע.'),
  'Write your own card in JavaScript (sandboxed)': ('כתבו כרטיס משלכם ב־JavaScript (בסביבה מבודדת)', 'שרייבט אייער אייגענעם קארטל אין JavaScript (אפגעזונדערט)'),
  'Your siddur': ('הסידור שלך', 'אייער סידור'),
  'in {n}d': ('בעוד {n} ימים', 'אין {n} טעג'),
  'in {time}': ('בעוד {time}', 'אין {time}'),
  'when {condition}': ('כאשר {condition}', 'ווען {condition}'),
  'At {zman}': ('ב{zman}', 'ביי {zman}'),
  '{n} min before {zman}': ('{n} דק׳ לפני {zman}', '{n} מינוט פאר {zman}'),
  '{n} min after {zman}': ('{n} דק׳ אחרי {zman}', '{n} מינוט נאך {zman}'),

  // Torah tab
  'Torah tab': ('לשונית תורה', 'תורה טאב'),
  "Download the Kitzur Shulchan Aruch from Sefaria to learn offline, with today's Kitzur Yomi marked. More books are on the way. The calendar is now a card on Home.":
      ('הורידו את קיצור שולחן ערוך מספריא ללימוד ללא חיבור, עם הקיצור היומי מסומן. ספרים נוספים בדרך. לוח השנה הוא עכשיו כרטיס בדף הבית.',
          'לאדט אראפ דעם קיצור שולחן ערוך פון ספריא צו לערנען אן אינטערנעט, מיטן היינטיגן קיצור יומי אנגעצייכנט. נאך ספרים קומען. דער קאלענדאר איז יעצט א קארטל אויף דער היים.'),
  'Download everything': ('הורדת הכול', 'אראפלאדן אלעס'),
  'Download all of {name}': ('הורדת כל {name}', 'אראפלאדן גאנץ {name}'),
  'Downloaded · {size}': ('הורד · {size}', 'אראפגעלאדן · {size}'),
  'Downloading…': ('מוריד…', 'לאדט אראפ…'),
  '≈ {size} download': ('הורדה של כ־{size}', 'אן ערך {size} אראפצולאדן'),
  'Work in progress': ('בעבודה', 'אין ארבעט'),
  'Downloading from Sefaria…': ('מוריד מספריא…', 'לאדט אראפ פון ספריא…'),
  'Available offline': ('זמין ללא חיבור', 'צוטריטלעך אן אינטערנעט'),
  'Download failed. Check your connection and try again.':
      ('ההורדה נכשלה. בדקו את החיבור ונסו שוב.', 'דאס אראפלאדן איז דורכגעפאלן. קוקט די פארבינדונג און פרובירט נאכאמאל.'),
  'Downloads from Sefaria once, then works offline.': ('יורד מספריא פעם אחת, ואחר כך זמין ללא חיבור.', 'ווערט אראפגעלאדן פון ספריא איין מאל, דערנאך ארבעט עס אן אינטערנעט.'),
  'Kitzur Yomi': ('קיצור יומי', 'קיצור יומי'),
  'Learning text': ('טקסט הלימוד', 'לערן טעקסט'),
  "Separate from the siddur's text settings.": ('נפרד מהגדרות הטקסט של הסידור.', 'באזונדער פון די סידור טעקסט איינשטעלונגען.'),
  'Language': ('שפה', 'שפראך'),
  'Hebrew and English with an English interface; otherwise Hebrew.':
      ('עברית ואנגלית כשהממשק באנגלית; אחרת עברית.', 'לשון קודש און ענגליש ווען די שפראך איז ענגליש; אנדערש לשון קודש.'),
  'English font': ('גופן לאנגלית', 'ענגלישע שריפט'),
  'No English translation of this siman yet.': ('אין עדיין תרגום לאנגלית לסימן זה.', 'נאך נישטא קיין ענגלישע איבערזעצונג פון דעם סימן.'),
  'Hebrew: Torat Emet (public domain). English for this siman: {credit}. Via Sefaria.':
      ('עברית: תורת אמת (נחלת הכלל). אנגלית לסימן זה: {credit}. דרך ספריא.', 'לשון קודש: תורת אמת (public domain). ענגליש פאר דעם סימן: {credit}. דורך ספריא.'),
  'No reading today': ('אין לימוד היום', 'היינט איז נישטא קיין לימוד'),
  'Download to read it here, even offline.': ('הורידו כדי ללמוד כאן, גם ללא חיבור.', 'לאדט אראפ כדי צו לערנען דא, אפילו אן אינטערנעט.'),
  'Siman': ('סימן', 'סימן'),
  'Previous': ('הקודם', 'פריערדיקער'),
  'Next': ('הבא', 'ווייטער'),
  'Open': ('פתיחה', 'עפענען'),
  'Month view with Hebrew dates, holidays and times': ('תצוגת חודש עם תאריכים עבריים, חגים וזמנים', 'א חודש מיט אידישע דאטעס, יום טובים און צייטן'),
  'Hebrew: Torat Emet (public domain). English: trans. Rabbi Avrohom Davis, Metsudah Publications 1996 (CC-BY). Via Sefaria.':
      ('עברית: תורת אמת (נחלת הכלל). אנגלית: תרגום הרב אברהם דייוויס, הוצאת מצודה 1996 (CC-BY). דרך ספריא.',
          'לשון קודש: תורת אמת (public domain). ענגליש: איבערזעצט פון רב אברהם דייוויס, מצודה 1996 (CC-BY). דורך ספריא.'),
};
