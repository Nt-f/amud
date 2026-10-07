/// Halachic measures (shiurim): the Gemara's units, what each posek holds
/// they come to today, and where each figure comes from.
///
/// Two kinds of data:
/// - [measures]: every unit of length, area, volume, coins and time, in
///   the ratios the Gemara and Shulchan Aruch give, with each posek's size
///   for the measure's base unit (an amah, a beitzah, a perutah). Any unit
///   can be converted to any other this way.
/// - [commonShiurim]: the shiurim people look up most (a kezayis, a
///   revi'is, a techum), as each posek actually ruled. A posek's own
///   ruling isn't always what the ratios give (Rav Chaim Na'eh's kezayis
///   is 27 ml, not half his 57.6 ml beitzah), so these are listed as
///   ruled, each with its source.
///
/// Ratios and many figures follow TorahCalc (torahcalc.com, GPL-3.0),
/// whose sources are cited here; the rest are cited where they're given.
library;

/// A posek's figure for the base unit of a measure, in SI units (metres,
/// square metres, millilitres, grams of silver, seconds).
class Opinion {
  final String id;
  final String en;
  final String he;
  final double value;

  /// A larger figure the posek gives for where more is stricter.
  final double? stringent;
  final String source;
  const Opinion(this.id, this.en, this.he, this.value, {this.stringent, required this.source});
}

/// A unit: biblical ones sized in the measure's base unit, standard ones
/// in SI. A unit with its own [opinions] (the time to walk a mil, say)
/// is sized by those instead.
class ShiurUnit {
  final String id;
  final String en;
  final String he;
  final double size;
  final bool biblical;
  final List<Opinion>? opinions;
  const ShiurUnit(this.id, this.en, this.he, this.size, {this.biblical = true, this.opinions});
  const ShiurUnit.standard(this.id, this.en, this.size)
      : he = en,
        biblical = false,
        opinions = null;
}

/// A kind of measure, its units, and the poskim's sizes for its base unit.
class Measure {
  final String id;
  final String en;
  final String he;
  final List<ShiurUnit> units;

  /// Sizes of the base unit (null where every unit is fixed, as for time).
  final List<Opinion>? opinions;

  /// How the units relate and what the opinions measure, for the sources.
  final String basis;
  const Measure(this.id, this.en, this.he, this.units, {this.opinions, required this.basis});

  ShiurUnit unit(String id) => units.firstWhere((u) => u.id == id);
  Opinion? opinion(String? id) => opinions?.where((o) => o.id == id).firstOrNull ?? opinions?.first;
}

const _inch = 0.0254;
const _flOz = 29.5735295625;

// Length: an amah is 6 tefachim of 4 etzba'os; its size today is the
// machlokes.
const _lengthOpinions = [
  Opinion('naeh', "Rav Chaim Na'eh", 'הגר״ח נאה', 0.48,
      stringent: 0.49,
      source: "Shiurei Torah 3:25, pp. 249–250: an etzba is 2 cm, so an amah is 48 cm; where being stringent, "
          'use 47 or 49 cm, whichever is stricter.'),
  Opinion('feinstein', 'Rav Moshe Feinstein', 'הגר״מ פיינשטיין', 21.25 * _inch,
      stringent: 23 * _inch, source: 'Igros Moshe OC 1:136: an amah is 21¼ inches, and one may be stringent with 23 inches.'),
  Opinion('chazonIsh', 'Chazon Ish', 'חזון איש', 0.0962 * 6,
      stringent: 0.0982 * 6,
      source: 'Shiurin shel Torah (Rav Yaakov Kanievsky, quoting the Chazon Ish), p. 3: a tefach is 9.62 cm '
          '(stringently 9.82 cm).'),
  Opinion('aruchHashulchan', 'Aruch HaShulchan / Mishnah Berurah', 'ערוך השולחן / משנה ברורה', 21 * _inch,
      source: 'Aruch HaShulchan YD 201:3 and 286:21, Mishnah Berurah 358:7: an amah of 21 inches '
          '(as shown by Dr. Gideon Freedman, via TorahCalc).'),
];

const length = Measure(
  'length',
  'Length',
  'אורך',
  [
    ShiurUnit('etzba', 'Etzba (fingerbreadth)', 'אצבע', 1 / 24),
    ShiurUnit('tefach', 'Tefach (handbreadth)', 'טפח', 1 / 6),
    ShiurUnit('zeres', 'Zeres (span)', 'זרת', 1 / 2),
    ShiurUnit('amah', 'Amah (cubit)', 'אמה', 1),
    ShiurUnit('shortAmah', 'Amah of five tefachim', 'אמה בת חמשה', 5 / 6),
    ShiurUnit('kaneh', 'Kaneh (reed)', 'קנה', 6),
    ShiurUnit('ris', 'Ris', 'ריס', 800 / 3),
    ShiurUnit('mil', 'Mil', 'מיל', 2000),
    ShiurUnit('parsah', 'Parsah', 'פרסה', 8000),
    ShiurUnit('derechYom', "Derech yom (a day's walk)", 'דרך יום', 80000),
    ShiurUnit.standard('mm', 'millimetres', 0.001),
    ShiurUnit.standard('cm', 'centimetres', 0.01),
    ShiurUnit.standard('m', 'metres', 1),
    ShiurUnit.standard('km', 'kilometres', 1000),
    ShiurUnit.standard('in', 'inches', _inch),
    ShiurUnit.standard('ft', 'feet', 0.3048),
    ShiurUnit.standard('yd', 'yards', 0.9144),
    ShiurUnit.standard('mi', 'miles', 1609.344),
  ],
  opinions: _lengthOpinions,
  basis: 'An amah is 2 zeres, 6 tefachim or 24 etzba\'os; a kaneh is 6 amos; a mil is 2000 amos (7½ ris); '
      "a parsah is 4 mil, and a day's walk 10 parsaos. The opinions are the size of an amah.",
);

// Area: squares of the length units, and the areas sown with a measure
// of seed.
final area = Measure(
  'area',
  'Area',
  'שטח',
  const [
    ShiurUnit('etzbaSq', 'Square etzba', 'אצבע מרובעת', 1 / 576),
    ShiurUnit('tefachSq', 'Square tefach', 'טפח מרובע', 1 / 36),
    ShiurUnit('amahSq', 'Square amah', 'אמה מרובעת', 1),
    ShiurUnit('beisRova', 'Beis rova', 'בית רובע', 2500 / 24),
    ShiurUnit('beisKav', 'Beis kav', 'בית קב', 2500 / 6),
    ShiurUnit('beisSeah', "Beis se'ah", 'בית סאה', 2500),
    ShiurUnit('beisSeasayim', "Beis se'asayim", 'בית סאתים', 5000),
    ShiurUnit('beisKor', 'Beis kor', 'בית כור', 75000),
    ShiurUnit.standard('cm2', 'square centimetres', 0.0001),
    ShiurUnit.standard('m2', 'square metres', 1),
    ShiurUnit.standard('dunam', 'dunams', 1000),
    ShiurUnit.standard('ha', 'hectares', 10000),
    ShiurUnit.standard('in2', 'square inches', _inch * _inch),
    ShiurUnit.standard('ft2', 'square feet', 0.3048 * 0.3048),
    ShiurUnit.standard('acre', 'acres', 4046.8564224),
  ],
  opinions: [
    for (final o in _lengthOpinions)
      Opinion(o.id, o.en, o.he, o.value * o.value,
          stringent: o.stringent == null ? null : o.stringent! * o.stringent!, source: o.source),
  ],
  basis: "A beis se'asayim is 5000 square amos, the size of the Mishkan's courtyard (Eruvin 23b); a beis se'ah is "
      "half that (50 by 50 amos), a beis kav a sixth of a beis se'ah and a beis rova a quarter of a beis kav; a beis "
      "kor is 30 beis se'ah. The opinions are the size of an amah, squared.",
);

// Volume: the opinions are the size of a beitzah.
const volume = Measure(
  'volume',
  'Volume',
  'נפח',
  [
    ShiurUnit('kortov', 'Kortov', 'קורטוב', 6 / 64),
    ShiurUnit('grogeres', 'Grogeres (dried fig)', 'גרוגרת', 0.3),
    ShiurUnit('kezayis', 'Kezayis (half a beitzah)', 'כזית (חצי ביצה)', 0.5),
    ShiurUnit('kezayisThird', 'Kezayis (a third of a beitzah)', 'כזית (שליש ביצה)', 1 / 3),
    ShiurUnit('beitzah', 'Beitzah (egg)', 'ביצה', 1),
    ShiurUnit('uchlah', 'Uchlah', 'עוכלא', 1.2),
    ShiurUnit('reviis', "Revi'is", 'רביעית', 1.5),
    ShiurUnit('tomen', 'Tomen', 'תומן', 3),
    ShiurUnit('log', 'Log', 'לוג', 6),
    ShiurUnit('kav', 'Kav', 'קב', 24),
    ShiurUnit('omer', 'Omer / Issaron', 'עומר / עשרון', 43.2),
    ShiurUnit('hin', 'Hin / Tarkav', 'הין / תרקב', 72),
    ShiurUnit('seah', "Se'ah", 'סאה', 144),
    ShiurUnit('ephah', 'Ephah / Bat', 'איפה / בת', 432),
    ShiurUnit('lesech', 'Lesech', 'לתך', 2160),
    ShiurUnit('kor', 'Kor', 'כור', 4320),
    ShiurUnit.standard('ml', 'millilitres', 1),
    ShiurUnit.standard('l', 'litres', 1000),
    ShiurUnit.standard('flOz', 'US fluid ounces', _flOz),
    ShiurUnit.standard('cup', 'US cups', _flOz * 8),
    ShiurUnit.standard('qt', 'US quarts', _flOz * 32),
    ShiurUnit.standard('gal', 'US gallons', _flOz * 128),
  ],
  opinions: [
    Opinion('naeh', "Rav Chaim Na'eh", 'הגר״ח נאה', 57.6,
        source: "Shiurei Torah: a beitzah of 57.6 ml, so a revi'is of 86.4 ml (often given as 86 ml)."),
    Opinion('feinstein', 'Rav Moshe Feinstein', 'הגר״מ פיינשטיין', 3.3 * _flOz / 1.5,
        stringent: 4.42 * _flOz / 1.5,
        source: "Haggadah Kol Dodi (Rav Dovid Feinstein), quoting Rav Moshe: a revi'is of 3.3 fl oz, and 4.42 fl oz "
            "for Kiddush on Friday night, which is d'oraisa. The beitzah here is his revi'is divided by 1½."),
    Opinion('chazonIsh', 'Chazon Ish', 'חזון איש', 100,
        source: "Chazon Ish OC 39 (Kuntres HaShiurim), and Shiurin shel Torah: a beitzah of about 100 ml, "
            "so a revi'is of 150 ml."),
  ],
  basis: "A log is 6 beitzim, a revi'is a quarter log (1½ beitzim), a kav 4 lugin, a se'ah 6 kabin, an ephah "
      "3 se'ah and a kor 30 se'ah; an omer is a tenth of an ephah, 43⅕ beitzim (Eruvin 83b; Shulchan Aruch OC 456:1). A kezayis is half a beitzah "
      '(Shulchan Aruch OC 486:1), or a third according to others; both are listed. The opinions are the size of a '
      "beitzah. A posek's own figure for a kezayis may differ from these ratios: see the common shiurim.",
);

// Coins: the opinions are the weight of a perutah in silver.
const coins = Measure(
  'coins',
  'Coins (silver)',
  'מטבעות (כסף)',
  [
    ShiurUnit('perutah', 'Perutah', 'פרוטה', 1),
    ShiurUnit('issar', 'Issar', 'איסר', 8),
    ShiurUnit('pundyon', 'Pundyon', 'פונדיון', 16),
    ShiurUnit('maah', "Ma'ah", 'מעה', 32),
    ShiurUnit('dinar', 'Dinar / Zuz', 'דינר / זוז', 192),
    ShiurUnit('shekel', 'Shekel', 'שקל', 384),
    ShiurUnit('sela', 'Sela', 'סלע', 768),
    ShiurUnit('dinarZahav', 'Dinar zahav (value in silver)', 'דינר זהב', 4800),
    ShiurUnit('maneh', 'Maneh', 'מנה', 19200),
    ShiurUnit.standard('g', 'grams of silver', 1),
    ShiurUnit.standard('ozt', 'troy ounces of silver', 31.1034768),
  ],
  opinions: [
    Opinion('shulchanAruch', 'Shulchan Aruch / Rambam', 'שולחן ערוך / רמב״ם', 0.024,
        source: "Shulchan Aruch CM 88:1; Rambam on Mishnah Shevuos 6:1 and Bava Metzia 4:7, and Hilchos To'en "
            "V'Nit'an 3:1: a perutah is the weight of half a barleycorn of pure silver, about 0.024 g."),
    Opinion('rashi', 'Rashi', 'רש״י', 0.02, source: 'Rashi, Shemos 21:32: a perutah of about 0.02 g of silver (via TorahCalc).'),
    Opinion('others', 'Other authorities', 'פוסקים אחרים', 0.027, source: 'Other authorities: about 0.027 g of silver (via TorahCalc).'),
  ],
  basis: "An issar is 8 perutos, a pundyon 2 issarim, a ma'ah 2 pundyonim, a dinar (zuz) 6 ma'os, a shekel 2 dinarim "
      'and a sela 2 shekalim; a dinar zahav is worth 25 silver dinarim and a maneh 100. The opinions are the weight '
      'of a perutah in silver. Its value in money follows the price of silver, which you can enter.',
);

const hiluchMil = [
  Opinion('18', '18 minutes', '18 דקות', 18 * 60, source: 'Shulchan Aruch HaRav: 18 minutes, the most widely used figure.'),
  Opinion('22.5', '22½ minutes', '22.5 דקות', 22.5 * 60, source: 'Biur HaGra: 22½ minutes.'),
  Opinion('24', '24 minutes', '24 דקות', 24 * 60, source: 'Shulchan Aruch HaRav, stringently: 24 minutes.'),
];

const achilasPras = [
  Opinion('2', '2 minutes (Chasam Sofer)', '2 דקות (חתם סופר)', 120, source: 'Chasam Sofer: 2 minutes.'),
  Opinion('3', '3 minutes (Aruch HaShulchan)', '3 דקות (ערוך השולחן)', 180,
      source: 'Aruch HaShulchan, and Rav Chanoch Henech Eiges: 3 minutes.'),
  Opinion('4', "4 minutes (Rav Chaim Na'eh)", '4 דקות (הגר״ח נאה)', 240,
      source: "Rav Chaim Na'eh, the Aruch HaShulchan stringently, and the Kaf HaChaim: 4 minutes."),
  Opinion('5', '5 minutes (Rav Yitzchak Elchanan)', '5 דקות (רי״א ספקטור)', 300, source: 'Rav Yitzchak Elchanan Spektor: 5 minutes.'),
  Opinion('7', '7 minutes (Kaf HaChaim)', '7 דקות (כף החיים)', 420, source: 'Kaf HaChaim, stringently: 7 minutes.'),
  Opinion('8', '8 minutes (Rav Ovadia Yosef)', '8 דקות (הגר״ע יוסף)', 480, source: 'Rav Ovadia Yosef: 8 minutes.'),
  Opinion('9', "9 minutes (Chasam Sofer, Rav Chaim Na'eh)", '9 דקות (חת״ס, הגר״ח נאה)', 540,
      source: "Chasam Sofer and Rav Chaim Na'eh, stringently: 9 minutes."),
];

const time = Measure(
  'time',
  'Time',
  'זמן',
  [
    ShiurUnit('rega', 'Rega', 'רגע', 3600 / 1080 / 76),
    ShiurUnit('chelek', 'Chelek', 'חלק', 3600 / 1080),
    ShiurUnit('pras', "K'dei achilas pras", 'כדי אכילת פרס', 0, opinions: achilasPras),
    ShiurUnit('mil', 'Hiluch mil (walking a mil)', 'הילוך מיל', 0, opinions: hiluchMil),
    ShiurUnit('shaah', "Sha'ah (hour)", 'שעה', 3600),
    ShiurUnit.standard('s', 'seconds', 1),
    ShiurUnit.standard('min', 'minutes', 60),
    ShiurUnit.standard('h', 'hours', 3600),
  ],
  basis: "An hour has 1080 chalakim and a chelek 76 rega'im (used for the molad). The time to walk a mil, and to eat a "
      'pras (half a loaf of three or four beitzim), are machlokes; each opinion is listed. A sha\'ah zmanis (a '
      'twelfth of the day) is on the Zmanim tab.',
);

final measures = [length, area, volume, coins, time];

/// [amount] of [from] in [to]: biblical units by [opinion] (the measure's
/// size for its base unit), and units with their own opinions by
/// [unitOpinions] (by unit id, else their first).
double convert(Measure m, double amount, ShiurUnit from, ShiurUnit to, {Opinion? opinion, Map<String, String> unitOpinions = const {}}) {
  double si(ShiurUnit u) {
    if (u.opinions case final list?) return (list.where((o) => o.id == unitOpinions[u.id]).firstOrNull ?? list.first).value;
    // Standard units, and biblical ones of a fixed size (an hour's chalakim).
    if (!u.biblical || m.opinions == null) return u.size;
    return u.size * (opinion ?? m.opinions!.first).value;
  }

  return amount * si(from) / si(to);
}

/// A posek's ruling for a common shiur: [value] in [unit] ('ml', 'cm',
/// 'm' or 'min'), with where it comes from.
class Ruling {
  final String opinionId;
  final String en;
  final String he;
  final double value;
  final String unit;
  final String source;

  /// A second figure the same posek (or those quoting him) gives.
  final bool alternative;
  const Ruling(this.opinionId, this.en, this.he, this.value, this.unit, {required this.source, this.alternative = false});
}

class CommonShiur {
  final String id;
  final String en;
  final String he;
  final String use;
  final List<Ruling> rulings;
  const CommonShiur(this.id, this.en, this.he, this.use, this.rulings);
}

List<Ruling> _lengths(double amos, String unit) => [
      for (final o in _lengthOpinions)
        Ruling(o.id, o.en, o.he, amos * o.value * (unit == 'cm' ? 100 : 1), unit, source: o.source),
    ];

final commonShiurim = [
  const CommonShiur('kezayis', 'Kezayis', 'כזית', "Matzah, maror, and a berachah acharonah on food: the smallest amount", [
    Ruling('naeh', "Rav Chaim Na'eh", 'הגר״ח נאה', 27, 'ml',
        source: "Shiurei Tziyon (1949), p. 70: 27 ml. Vezos HaBerachah (Birur Halachah 1) explains that he retracted "
            "the 28.8 ml of Shiurei Torah 3:11."),
    Ruling('naeh', "Rav Chaim Na'eh (Shiurei Torah)", 'הגר״ח נאה (שיעורי תורה)', 28.8, 'ml',
        alternative: true, source: "Shiurei Torah 3:11, p. 193: 28.8 ml, half his beitzah, which he later lowered to 27 ml."),
    Ruling('feinstein', 'Rav Moshe Feinstein', 'הגר״מ פיינשטיין', 31.2, 'ml',
        source: 'Haggadah Kol Dodi, quoted in Vezos HaBerachah (Birur Halachah 1): 31.2 ml.'),
    Ruling('chazonIsh', 'Chazon Ish', 'חזון איש', 33.3, 'ml',
        source: 'Shiurin shel Torah, 2nd ed., pp. 65–66: two thirds of a modern egg, 30–33.3 ml; Vezos HaBerachah '
            '(Birur Halachah 1:3) gives 33.3 ml.'),
    Ruling('chazonIsh', 'Chazon Ish (half his beitzah)', 'חזון איש (חצי ביצה)', 50, 'ml',
        alternative: true, source: 'Some charts give 50 ml, half of the Chazon Ish\'s 100 ml beitzah, for a mitzvah '
            "d'oraisa such as matzah."),
    Ruling('willig', 'Rav Mordechai Willig', 'הגר״מ וויליג', 22.5, 'ml',
        source: 'Pesach To-Go (2011), "How Much Matzah Do You Need to Eat?", p. 60: 22.5 ml, following Rav Hadar Margolin.'),
  ]),
  const CommonShiur('kebeitzah', 'Kebeitzah', 'כביצה', 'Bread for netilas yadayim with a berachah, and other halachos', [
    Ruling('naeh', "Rav Chaim Na'eh", 'הגר״ח נאה', 57.6, 'ml', source: 'Shiurei Torah: 57.6 ml.'),
    Ruling('chazonIsh', 'Chazon Ish', 'חזון איש', 100, 'ml', source: 'Chazon Ish OC 39 (Kuntres HaShiurim): about 100 ml.'),
  ]),
  const CommonShiur('reviis', "Revi'is", 'רביעית', "Kiddush, the four cups, netilas yadayim, and a berachah acharonah on a drink", [
    Ruling('naeh', "Rav Chaim Na'eh", 'הגר״ח נאה', 86, 'ml', source: 'Shiurei Torah: 86 ml (2.9 fl oz).'),
    Ruling('feinstein', 'Rav Moshe Feinstein', 'הגר״מ פיינשטיין', 3.3 * _flOz, 'ml',
        source: 'Haggadah Kol Dodi, quoting Rav Moshe: 3.3 fl oz.'),
    Ruling('feinstein', "Rav Moshe Feinstein (Kiddush on Friday night)", 'הגר״מ פיינשטיין (קידוש ליל שבת)', 4.42 * _flOz, 'ml',
        alternative: true, source: "Haggadah Kol Dodi, quoting Rav Moshe: 4.42 fl oz for Kiddush on Friday night, which is d'oraisa."),
    Ruling('chazonIsh', 'Chazon Ish', 'חזון איש', 150, 'ml', source: 'Chazon Ish OC 39 (Kuntres HaShiurim): 150 ml (5.3 fl oz).'),
  ]),
  CommonShiur('amah', 'Amah', 'אמה', "Eruvin, sukkah walls, the size of a mezuzah's doorway, and more", _lengths(1, 'cm')),
  CommonShiur('tefach', 'Tefach', 'טפח', 'Sukkah, mechitzos, eruvin and more', _lengths(1 / 6, 'cm')),
  CommonShiur('techum', 'Techum Shabbos (2000 amos)', 'תחום שבת (2000 אמה)', 'How far one may walk beyond the town on Shabbos',
      _lengths(2000, 'm')),
  CommonShiur('mil', 'Hiluch mil', 'הילוך מיל', 'Matzah dough, and other time limits', [
    for (final o in hiluchMil) Ruling(o.id, o.en, o.he, o.value / 60, 'min', source: o.source),
  ]),
  CommonShiur('pras', "K'dei achilas pras", 'כדי אכילת פרס', 'How quickly a kezayis must be eaten', [
    for (final o in achilasPras) Ruling(o.id, o.en, o.he, o.value / 60, 'min', source: o.source),
  ]),
];

/// The poskim a user can follow by default, and which opinion id is
/// theirs in each list. Where a list has no opinion of theirs, the list's
/// usual default is used.
const followable = ['naeh', 'feinstein', 'chazonIsh'];

/// The usual default for each list where the posek followed has none.
const usualDefaults = {'mil': '18', 'pras': '4', 'coins': 'shulchanAruch'};

const credits = 'Ratios, and many figures with their sources, follow TorahCalc (torahcalc.com, by Jonah Lawrence and '
    'contributors, GPL-3.0). These are summaries of published opinions for reference; ask your rav how to act.';
