import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:siddur_engine/siddur_engine.dart';

import '../../core/providers.dart';
import 'book_kind.dart';
import 'siddur_providers.dart';

/// A prayer the app knows by name, found in whichever bundled siddur has
/// it: the default siddur first, then others of the same nusach, then any.
class CatalogItem {
  final String key;
  final String en;
  final String he;

  /// Regexes (case-insensitive) matched against node ids, in order.
  final List<String> patterns;

  /// When it's said (a [DayContext] condition), for "today" marks.
  final String? when;

  /// Also check tonight (the next Hebrew day's evening): Chanukah candles,
  /// the Omer, Kiddush Levana, Havdalah.
  final bool evening;
  const CatalogItem(this.key, this.en, this.he, this.patterns, {this.when, this.evening = false});
}

/// A titled group of [CatalogItem]s, e.g. Sukkot.
class CatalogGroup {
  final String en;
  final String he;
  final List<CatalogItem> items;
  const CatalogGroup(this.en, this.he, this.items);
}

const _hallel = CatalogItem('hallel', 'Hallel', 'הלל', [r'(^|/)hallel$'], when: 'hallel');
const _omer = CatalogItem('omer', 'Sefirat HaOmer', 'ספירת העומר', [r'sefirat ha.?omer$', r'counting (?:of )?the omer$'], when: 'omer', evening: true);
const _levana = CatalogItem('kiddushLevana', 'Kiddush Levana', 'קידוש לבנה',
    [r'birkat ha.?levana$', r'kiddush levanah?$', r'blessing of the (?:new )?moon$'],
    when: 'kiddushLevana', evening: true);
const _havdalah = CatalogItem('havdalah', 'Havdalah', 'הבדלה', [r'(^|/)havdalah?$', r'havdala at home$', r'motzaei shabbat/havdala$'],
    when: 'motzaeiShabbat || motzaeiYomTov', evening: true);

/// The holiday and seasonal prayers of the "Holidays & Seasons" siddur.
const catalogGroups = <CatalogGroup>[
  CatalogGroup('Sukkot', 'סוכות', [
    CatalogItem('sukkah', 'Entering the Sukkah', 'כניסה לסוכה',
        [r'entering the sukkah$', r'on entering the sukka$', r'upon entering sukkah$', r'prayers in the sukkah$'],
        when: 'sukkot', evening: true),
    CatalogItem('ushpizin', 'Ushpizin', 'אושפיזין', [r'(^|/)ushpizin$'], when: 'sukkot', evening: true),
    CatalogItem('lulav', 'Blessing on the Lulav', 'נטילת לולב', [r'lulav$'], when: 'sukkot && !shabbat'),
    CatalogItem('hoshanot', 'Hoshanot', 'הושענות', [r'^sukkot$', r'(^|/)hosha(?:.?a)?no[ts]$'], when: 'sukkot'),
    CatalogItem('hoshanaRaba', 'Hoshana Raba', 'הושענא רבה', [r'hosha(?:.a)?na rab+a$'], when: 'hoshanaRaba'),
    CatalogItem('geshem', 'Tefillat Geshem', 'תפילת גשם', [r'prayer for rain$', r'tefillat geshem$'], when: 'shminiAtzeret'),
    CatalogItem('hakafot', 'Hakafot', 'הקפות', [r'hakafo[ts](?: for simhat torah)?$'], when: 'simchatTorah', evening: true),
  ]),
  CatalogGroup('Rosh Chodesh & the month', 'ראש חודש', [
    _hallel,
    CatalogItem('musafRoshChodesh', 'Musaf for Rosh Chodesh', 'מוסף לראש חודש',
        [r'musaf (?:amidah )?for rosh (?:c)?hodesh$', r'^rosh c?hodesh/mussaf$', r'^musaf for rosh chodesh$', r'^rosh chodesh$'],
        when: 'roshChodesh'),
    _levana,
    CatalogItem('birkatHaChama', 'Birkat HaChama', 'ברכת החמה', [r'birkat ha.?chama', r'birkas ha.?chama', r'blessing of the sun']),
    CatalogItem('birkatHachodesh', 'Blessing the New Month', 'ברכת החודש',
        [r'blessing(?:s)? (?:of|the) (?:the )?new month$', r'birkat ha.?chodesh$', r'blessing of new month$'],
        when: 'shabbatMevarchim'),
    CatalogItem('yomKippurKatan', 'Yom Kippur Katan', 'יום כפור קטן', [r'yom kippur katan$'], when: 'yomKippurKatan || erevRoshChodesh'),
  ]),
  CatalogGroup('Yamim Noraim', 'ימים נוראים', [
    CatalogItem('selichot', 'Selichot', 'סליחות', [r'selihot; all days$', r'^selichos$', r'^festivals/selichot$', r'^fast days$'],
        when: 'publicFast || behab'),
    CatalogItem('hatarat', 'Annulment of Vows', 'התרת נדרים', [r'annulment of vows'], when: 'hMonth == 6 && hDay == 29'),
    CatalogItem('tashlich', 'Tashlich', 'תשליך', [r'tashli(?:k)?h$'], when: 'roshHashana'),
    CatalogItem('kaparot', 'Kaparot', 'כפרות', [r'kap+aro[ts]$'], when: 'erevYomKippur || aseretYemeiTeshuva'),
    CatalogItem('avinuMalkeinu', 'Avinu Malkeinu', 'אבינו מלכנו', [r'avinu malk\w*$'], when: 'avinuMalkeinu'),
    CatalogItem('yizkor', 'Yizkor', 'יזכור', [r'(^|/)yizkor$'], when: 'yizkor'),
  ]),
  CatalogGroup('Chanukah & Purim', 'חנוכה ופורים', [
    CatalogItem('chanukah', 'Chanukah candles', 'הדלקת נרות חנוכה',
        [r'service for lighting chanukah candles$', r'candle lighting for hanukk?a$', r'hanukkah/menorah lighting$', r'chanukah/menorah lighting$',
          r'^chanukah service$', r'^chanukah$'],
        when: 'chanukah', evening: true),
    CatalogItem('purim', 'Megillah & Purim', 'מגילה ופורים',
        [r'service for purim$', r'^purim service$', r'purim/megillah reading$', r'^purim$'],
        when: 'purim', evening: true),
  ]),
  CatalogGroup('Pesach, Omer & Shavuot', 'פסח, ספירה ושבועות', [
    CatalogItem('chametz', 'Search for Chametz', 'בדיקת חמץ', [r'search for hametz$', r'removal of hametz$'],
        when: 'hMonth == 1 && hDay >= 12 && hDay <= 14', evening: true),
    CatalogItem('haggadah', 'Pesach Haggadah', 'הגדה של פסח', [r'^pesach haggadah$'], when: 'pesachFirstDays', evening: true),
    CatalogItem('tal', 'Tefillat Tal', 'תפילת טל', [r'prayer for dew$', r'tefillat tal$'], when: 'pesachFirstDays'),
    _omer,
    CatalogItem('akdamut', 'Akdamut', 'אקדמות', [r'akdamu[ts]$'], when: 'shavuot'),
  ]),
  CatalogGroup('Shabbat & Yom Tov', 'שבת ויום טוב', [
    CatalogItem('eruvTavshilin', 'Eruv Tavshilin', 'עירוב תבשילין', [r'e(?:i)?ruv tavshilin$'], when: 'eruvTavshilin'),
    CatalogItem('candles', 'Candle lighting', 'הדלקת נרות',
        [r'^shabbat/candle lighting$', r'^candle lighting$', r'^shabbat candle lighting$'],
        when: 'erevShabbat', evening: true),
    CatalogItem('kiddushYomTov', 'Kiddush for Yom Tov', 'קידוש ליום טוב',
        [r'kiddush for yom tov evenings?$', r'yom tov eve kiddush$'],
        when: 'yomTov', evening: true),
    _havdalah,
  ]),
];

/// Prayers found the same way for Today's davening and related links.
const extraItems = <CatalogItem>[
  CatalogItem('musafFestival', 'Musaf for Chol HaMoed', 'מוסף לחול המועד',
      [r'musaf for chol hamo', r'shalosh regalim/mussaf$', r'^musaf for festivals$', r'yom tov musaf amidah$', r'three festivals/mussaf$',
        r'musaf for yom tov$', r'festivals/musaf for festivals$'],
      when: 'cholHamoed || yomTov'),
  CatalogItem('amidahYomTov', 'Amidah for Yom Tov', 'עמידה ליום טוב',
      [r'amida for maariv, shacharit, mincha$', r'amida for yom tov$', r'maariv, shacharit & mincha amidah$', r'amidah for yom tov',
        r'three festivals/amidah$'],
      when: 'yomTov'),
  CatalogItem('kabbalatShabbat', 'Kabbalat Shabbat', 'קבלת שבת', [r'(^|/)kabbalat shabbat$', r'(^|/)kabbalas shabbos$']),
  CatalogItem('kiddushShabbat', 'Kiddush', 'קידוש',
      [r'^shabbat/shabbat evening/kiddush$', r'shabbat evening/kiddush$', r'kiddush for shabbos eve$', r'shabbat eve kiddush$',
        r'kiddush and zemirot for shabbat evening$']),
  CatalogItem('birkat', 'Birkat HaMazon', 'ברכת המזון',
      [r'(^|/)birkat ha.?mazon$', r'birchat ha.?mazon$', r'birchas? ha.?mazon$', r'birkas ha.?mazon$', r'post meal blessing$', r'grace after meals$']),
  CatalogItem('brachot', 'Blessings on food', 'ברכות הנהנין',
      [r'birkat hanehenin$', r'blessings on pleasures', r'berachos said before eating', r'blessings on enjoyments$', r'blessing on foods$',
        r'various blessings$']),
  CatalogItem('bedtime', 'Bedtime Shema', 'קריאת שמע על המיטה',
      [r"keri.at shema al hamita$", r'bedtime shema$', r'prayer before retiring at night$', r'shema before sleep at night$']),
  CatalogItem('modehAni', 'Modeh Ani', 'מודה אני', [r'(^|/)modeh ani$', r'(^|/)modeh$']),
  CatalogItem('netilat', 'Netilat Yadayim', 'נטילת ידים', [r'(^|/)netilat yadayim$', r'washing (?:the )?hands$']),
  CatalogItem('asherYatzar', 'Asher Yatzar', 'אשר יצר', [r'(^|/)asher yatzar$']),
  CatalogItem('torahBlessings', 'Torah Blessings', 'ברכות התורה', [r'(^|/)torah blessings$', r'birkot ha.?torah$']),
  CatalogItem('tallit', 'Tallit', 'טלית', [r'(^|/)tallit$']),
  CatalogItem('tefillin', 'Tefillin', 'תפילין', [r'(^|/)tefillin$']),
  CatalogItem('adonOlam', 'Adon Olam', 'אדון עולם', [r'(^|/)adon olam$']),
  CatalogItem('yigdal', 'Yigdal', 'יגדל', [r'(^|/)yigdal$']),
  CatalogItem('aleinu', 'Aleinu', 'עלינו', [r'(^|/)aleinu$', r'(^|/)alenu$']),
  CatalogItem('refuah', 'Mi Sheberach for the sick', 'מי שברך לחולה', [r'mi sheberach/for sickness', r'for the sick$', r'prayer for the sick']),
  CatalogItem('blessChildren', 'Blessing the Children', 'ברכת הבנים', [r'blessing the children$', r'birkat ha.?banim$']),
  CatalogItem('derech', 'Tefillat HaDerech', 'תפילת הדרך', [r'tefillat ha.?derech$', r"traveler.?s prayer$"]),
];

final _allItems = {
  for (final g in catalogGroups)
    for (final i in g.items) i.key: i,
  for (final i in extraItems) i.key: i,
};

CatalogItem? catalogItem(String key) => _allItems[key];

/// A section of a particular book.
class PrayerRef {
  final String book;
  final SchemaNode node;
  const PrayerRef(this.book, this.node);

  String get id => node.id;
}

/// The first node whose id matches one of [patterns] (tried in order).
SchemaNode? findByPatterns(SchemaNode root, List<String> patterns) {
  final all = root.descendants.toList();
  for (final p in patterns) {
    final re = RegExp(p, caseSensitive: false);
    for (final n in all) {
      if (re.hasMatch(n.id)) return n;
    }
  }
  return null;
}

enum Nusach { ashkenaz, sefard, mizrach, other }

Nusach nusachOf(String book) {
  final t = book.toLowerCase();
  if (t.contains('ashkenaz')) return Nusach.ashkenaz;
  if (t.contains('sefard') || t.contains('chabad')) return Nusach.sefard;
  if (t.contains('mizrach')) return Nusach.mizrach;
  return Nusach.other;
}

/// Books to look in: [first], then the same nusach, then the rest; Shabbat
/// siddurim last in each. Commentaries aren't siddurim to pray from.
List<String> bookSearchOrder(Manifest m, String first) {
  final books = [for (final b in m.books) if (bookKind(b.title) != BookKind.commentary) b.title];
  final n = nusachOf(first);
  List<String> weekdayFirst(Iterable<String> l) => [
        for (final b in l) if (bookKind(b) != BookKind.shabbat) b,
        for (final b in l) if (bookKind(b) == BookKind.shabbat) b,
      ];
  return [
    if (books.contains(first)) first,
    ...weekdayFirst([for (final b in books) if (b != first && nusachOf(b) == n) b]),
    ...weekdayFirst([for (final b in books) if (b != first && nusachOf(b) != n) b]),
  ];
}

/// Whether the reader will find text for [node] in [book]'s chosen versions.
bool hasText(VersionSelection v, SchemaNode node) =>
    node.leaves.any((l) => v.pick(v.hebrew, l.path).$1 != null || v.pick(v.translation, l.path).$1 != null);

/// Where to read a catalogued prayer, preferring the default siddur; null
/// when no bundled siddur has it.
final prayerRefProvider = FutureProvider.family<PrayerRef?, String>((ref, key) async {
  final item = catalogItem(key);
  if (item == null) return null;
  final m = await ref.watch(manifestProvider.future);
  final first = await ref.watch(defaultBookProvider.future);
  for (final book in bookSearchOrder(m, first)) {
    final root = await ref.watch(bookIndexProvider(book).future);
    final node = findByPatterns(root, item.patterns);
    if (node == null) continue;
    if (hasText(await ref.watch(versionSelectionProvider(book).future), node)) return PrayerRef(book, node);
  }
  return null;
});

/// A service or other shortcut (see [findSection]) for the reader's day,
/// from the default siddur or, when it lacks it (a weekday siddur on
/// Shabbat), the next siddur that has it.
final sectionRefProvider = FutureProvider.family<PrayerRef?, (String, int)>((ref, k) async {
  final (key, dateAbs) = k;
  final m = await ref.watch(manifestProvider.future);
  final first = await ref.watch(defaultBookProvider.future);
  DayContext contexts(Service svc) => ref.watch(dayContextProvider((dateAbs, svc)));
  for (final b in bookSearchOrder(m, first)) {
    final root = await ref.watch(bookIndexProvider(b).future);
    final id = findSectionOn(root, key, contexts);
    final node = id == null ? null : root.find(id);
    if (node != null) return PrayerRef(b, node);
  }
  return null;
});

enum ItemTime { none, today, tonight }

/// Whether [item] is said today ([day]) or tonight ([night], the next
/// Hebrew day's evening).
ItemTime itemTime(CatalogItem item, DayContext day, DayContext night) {
  final when = item.when;
  if (when == null) return ItemTime.none;
  final c = Condition.parse(when);
  if (c.eval(day.env)) return ItemTime.today;
  if (item.evening && c.eval(night.env)) return ItemTime.tonight;
  return ItemTime.none;
}

/// Explicit-nusach links never silently substitute a different nusach.
final nusachSectionRefProvider = FutureProvider.family<PrayerRef?, (String, String, int)>((ref, k) async {
  final (nusachName, key, dateAbs) = k;
  final nusach = Nusach.values.where((n) => n.name == nusachName).firstOrNull;
  if (nusach == null || nusach == Nusach.other) return null;
  final manifest = await ref.watch(manifestProvider.future);
  final first = await ref.watch(defaultBookProvider.future);
  DayContext contexts(Service service) => ref.watch(dayContextProvider((dateAbs, service)));
  for (final book in bookSearchOrder(manifest, first).where((b) => nusachOf(b) == nusach)) {
    final root = await ref.watch(bookIndexProvider(book).future);
    final id = findSectionOn(root, key, contexts);
    final node = id == null ? null : root.find(id);
    if (node != null && hasText(await ref.watch(versionSelectionProvider(book).future), node)) return PrayerRef(book, node);
  }
  return null;
});
