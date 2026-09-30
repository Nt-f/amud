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
  'Sections, lines and inline phrases not said today are removed entirely.':
      ('קטעים, שורות וביטויים שאינם נאמרים היום מוסרים לגמרי.', 'טיילן, שורות און ווערטער וואס מען זאגט נישט היינט ווערן אינגאנצן אראפגענומען.'),
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

  // What's new
  "What's new": ('מה חדש', 'וואס איז נייעס'),
  'Got it': ('הבנתי', 'פארשטאנען'),
  'Focus mode': ('מצב מיקוד', 'פאקוס מאדע'),
  'Double-tap the text while praying to hide the top and bottom bars. Double-tap again to bring them back.':
      ('הקישו פעמיים על הטקסט בזמן התפילה כדי להסתיר את הסרגלים העליון והתחתון. הקישו פעמיים שוב כדי להחזיר אותם.',
       'טאפט צוויי מאל אויפן טעקסט בשעתן דאווענען צו באהאלטן די אויבערשטע און אונטערשטע ליניעס. טאפט נאכאמאל צוויי מאל זיי צוריקצוברענגען.'),

  // Location
  'Search cities': ('חיפוש עיר', 'זוכן א שטאט'),
  'Use my location': ('המיקום שלי', 'מיין ארט'),
  'Manual': ('ידני', 'מיט דער האנט'),
  'Name': ('שם', 'נאמען'),
  'Latitude': ('קו רוחב', 'ברייט'),
  'Longitude': ('קו אורך', 'לענג'),
  'Elevation (m)': ('גובה (מ׳)', 'הייך (מ׳)'),
  'Time zone': ('אזור זמן', 'צייט זאנע'),
};
