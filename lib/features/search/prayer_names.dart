import '../../core/search.dart';

/// Other names people know a prayer by: the Ashkenazi, Sefardi and modern
/// Hebrew transliterations, the English names siddurim translate it as,
/// and the Hebrew. Search looks for them alongside a section's own title,
/// so "Hataras Nedarim" finds Chabad's "Annulment of Vows" and "Grace after
/// Meals" finds Birkat HaMazon.
///
/// Transliterations of a section's Hebrew title are matched without this
/// list (see [searchKey]); this is for names that can't be worked out from
/// the title.
class PrayerNames {
  /// Identifies the prayer across siddurim, whatever each calls it.
  final String key;

  /// Matched against a section's English and Hebrew titles, folded (see
  /// [searchFold]: lower case, no nikud, apostrophes dropped).
  final RegExp title;
  final List<String> names;
  PrayerNames(this.key, String title, this.names) : title = RegExp(title);
}

/// What [prayerNamesFor] found for a title: the other names, and the key
/// when the title is the prayer itself rather than a variant of it
/// ("Birkat HaMazon" rather than "Birkat HaMazon for a Circumcision").
typedef PrayerNameMatch = ({List<String> names, String? key});

PrayerNameMatch prayerNamesFor(String en, String he) {
  final titles = [searchFold(en), searchFold(he)].where((t) => t.isNotEmpty);
  final names = <String>[];
  String? key;
  for (final p in prayerNames) {
    for (final t in titles) {
      if (!p.title.hasMatch(t)) continue;
      names.addAll(p.names);
      // The whole title, give or take "the", "order of" or "סדר", or two
      // names for it ("Birkat HaMazon; Grace after Meals").
      final rest = t.replaceAll(p.title, ' ').replaceAll(_filler, ' ').trim();
      if (rest.isEmpty) key ??= p.key;
      break;
    }
  }
  return (names: names, key: key);
}

final _filler = RegExp(r'\b(?:the|order|of|for|service|prayer|seder|סדר|תפלת|תפילת)\b');

// Patterns are written for folded text: lower case, no apostrophes ("maariv",
// "shemoneh esrei"), Hebrew without nikud. Spellings vary a lot, so they
// allow the common ones: k/kh/ch/h, t/s/th, single or doubled letters.
final prayerNames = <PrayerNames>[
  // Services
  PrayerNames('shacharit', r'^(?:weekday |shabbat |shabbos )?(?:shacharit|shacharis|shaharit|shaharis|morning prayers?|morning service)$|^שחרית',
      ['Shacharit', 'Shacharis', 'Shaharit', 'Morning service', 'Morning prayers', 'שחרית']),
  PrayerNames('mincha', r'^(?:weekday |shabbat |shabbos )?(?:mincha|minchah|minha|minhah)(?: for weekdays| service)?$|^מנחה',
      ['Mincha', 'Minchah', 'Minha', 'Afternoon service', 'Afternoon prayers', 'מנחה']),
  PrayerNames('maariv', r'^(?:weekday |shabbat |shabbos )?(?:maariv|arvit|arvis)(?: for weekdays| service)?$|^(?:ערבית|מעריב)',
      ['Maariv', 'Arvit', 'Arvis', 'Evening service', 'Evening prayers', 'ערבית', 'מעריב']),
  PrayerNames('musaf', r'^(?:musaf|mussaf)(?: service)?$|^מוסף', ['Musaf', 'Mussaf', 'Additional service', 'מוסף']),
  PrayerNames('amidah', r'^(?:the )?(?:amidah?|shemoneh esrei?|shmoneh esrei?|shemone esre)$|^(?:עמידה|שמונה עשרה)',
      ['Amidah', 'Amida', 'Shemoneh Esrei', 'Shmoneh Esrei', 'Shemona Esrei', 'Silent prayer', 'Standing prayer', 'Eighteen blessings', 'Tefillah', 'עמידה', 'שמונה עשרה']),
  // Morning
  PrayerNames('modehAni', r'modeh ani|(?:upon|on) (?:arising|waking)|מודה אני', ['Modeh Ani', 'Modah Ani', 'Upon waking', 'מודה אני']),
  PrayerNames('netilat', r'netilat yadayim|netilas yadayim|washing (?:the )?hands|נטילת ידים', ['Netilat Yadayim', 'Netilas Yadayim', 'Washing hands', 'נטילת ידיים']),
  PrayerNames('asherYatzar', r'^asher yatzar$|^אשר יצר$', ['Asher Yatzar', 'Asher Yotzar', 'Bathroom blessing', 'אשר יצר']),
  PrayerNames('elokaiNeshama', r'elo[hk]ai neshama|אלהי נשמה', ['Elokai Neshama', 'Elohai Neshamah', 'My God the soul', 'אלקי נשמה']),
  PrayerNames('birchotHashachar', r'morning blessings|blessings upon arising|birch[oa][ts] ha ?shach[ae]r|birkhot hashahar|ברכות השחר',
      ['Birchot HaShachar', 'Birchos Hashachar', 'Birkhot HaShahar', 'Morning blessings', 'ברכות השחר']),
  PrayerNames('birchotHatorah', r'(?:blessings? (?:over|on|of) (?:the )?torah|torah blessings|birkat hatorah|birchos hatorah)$|^ברכות התורה',
      ['Birchot HaTorah', 'Birchos HaTorah', 'Birkat HaTorah', 'Torah blessings', 'ברכות התורה']),
  PrayerNames('tallit', r'^(?:tallit|tallis|talit|putting on the tallis|order of talit|tzitzit and tallit)$|טלית',
      ['Tallit', 'Tallis', 'Talis', 'Prayer shawl', 'Atifat Tallit', 'טלית']),
  PrayerNames('tefillin', r'^(?:tefillin|tefilin|order of tefillin|putting on (?:the )?tefillin)$|תפלין|תפילין',
      ['Tefillin', 'Tfilin', 'Phylacteries', 'Hanachat Tefillin', 'תפילין']),
  PrayerNames('tzitzit', r'^(?:tzitzit|tzitzis|tsitsit)$|^ציצית$', ['Tzitzit', 'Tzitzis', 'Fringes', 'ציצית']),
  PrayerNames('maTovu', r'^ma ?tovu$|^מה טבו', ['Mah Tovu', 'Ma Tovu', 'מה טובו']),
  PrayerNames('adonOlam', r'^adon olam$|^אדון עולם', ['Adon Olam', 'Lord of the world', 'אדון עולם']),
  PrayerNames('yigdal', r'^yigdal$|^יגדל', ['Yigdal', 'יגדל']),
  PrayerNames('akeidah', r'akeidah|akedah|binding of isaac|עקדה', ['Akeidah', 'Akeidas Yitzchak', 'Binding of Isaac', 'עקידה']),
  PrayerNames('korbanot', r'^(?:korbanot|korbanos|offerings|sacrifices)\b|^קרבנות', ['Korbanot', 'Korbanos', 'Offerings', 'Sacrifices', 'קרבנות']),
  PrayerNames('ketoret', r'ketoret|ketores|incense|פטום הקטרת|קטורת', ['Ketoret', 'Ketores', 'Pitum HaKetoret', 'Incense', 'פטום הקטורת']),
  PrayerNames('rabbiYishmael', r'rabbi yishmael|rabi yishmael|ר ישמעאל|רבי ישמעאל', ['Rabbi Yishmael', 'Braita of Rabbi Yishmael', 'Thirteen principles of interpretation', 'רבי ישמעאל']),
  PrayerNames('pesukeiDezimra', r'pesukei ?de? ?zimrah?|psukei|verses of praise|פסוקי דזמרה', ['Pesukei DeZimra', 'Psukei Dezimra', 'Verses of praise', 'פסוקי דזמרה']),
  PrayerNames('hodu', r'^hodu$|^הודו', ['Hodu', 'הודו']),
  PrayerNames('baruchSheamar', r'baruch sheamar|barukh sheamar|ברוך שאמר', ['Baruch Sheamar', 'Barukh SheAmar', 'ברוך שאמר']),
  PrayerNames('ashrei', r'^ashrei\b|^אשרי', ['Ashrei', 'Ashray', 'Tehillah LeDavid', 'Psalm 145', 'אשרי']),
  PrayerNames('azYashir', r'az yashir|shirat hayam|shiras hayam|song (?:at|of) the sea|אז ישיר|שירת הים',
      ['Az Yashir', 'Shirat HaYam', 'Shiras Hayam', 'Song of the Sea', 'אז ישיר']),
  PrayerNames('nishmat', r'^nishma[ts]|^נשמת', ['Nishmat', 'Nishmas', 'Nishmat Kol Chai', 'נשמת כל חי']),
  PrayerNames('yishtabach', r'^yishtabach$|^ישתבח', ['Yishtabach', 'Yishtabah', 'ישתבח']),
  PrayerNames('barchu', r'^(?:barchu|borechu|barekhu)$|^ברכו$', ['Barchu', 'Borchu', 'Barechu', 'ברכו']),
  PrayerNames('shema', r'^(?:the )?shema$|recitation of shema|^(?:keriat|kriat|krias) shema$|^קריאת שמע$|^שמע$',
      ['Shema', 'Shema Yisrael', 'Kriat Shema', 'Krias Shema', 'Hear O Israel', 'קריאת שמע']),
  PrayerNames('blessingsShema', r'blessings of (?:the )?shema|shema (?:and|&) blessings|berachos (?:preceding|following) shema|ברכות קריאת שמע',
      ['Birchot Kriat Shema', 'Blessings of the Shema', 'ברכות קריאת שמע']),
  PrayerNames('tachanun', r'^(?:tachanun|tachnun|tahanun)$|nefilat app?ayim|^תחנון', ['Tachanun', 'Tachnun', 'Tahanun', 'Nefilat Apayim', 'Supplication', 'תחנון']),
  PrayerNames('avinuMalkeinu', r'avinu malk[ae]i?nu|אבינו מלכנו', ['Avinu Malkeinu', 'Avinu Malkenu', 'Our Father our King', 'אבינו מלכנו']),
  PrayerNames('torahReading', r'^(?:reading of the torah|torah reading|keriat hatorah|krias hatorah)$|^קריאת התורה',
      ['Torah reading', 'Kriat HaTorah', 'Krias HaTorah', 'Leining', 'קריאת התורה']),
  PrayerNames('uvaLetzion', r'uv?a ?le? ?t?[zs]i?on|ובא לציון', ['Uva LeTzion', 'Uva LTzion', 'ובא לציון']),
  PrayerNames('aleinu', r'^a?le[iy]?nu$|^עלינו', ['Aleinu', 'Alenu', 'Aleinu Leshabeach', 'עלינו']),
  PrayerNames('shirShelYom', r'song of the day|psalm of the day|daily psalm|shir shel yom|שיר של יום', ['Shir Shel Yom', 'Song of the day', 'Psalm of the day', 'שיר של יום']),
  PrayerNames('einKeloheinu', r'ein ?k[ae]i?lo[hk]einu|ein kelohenu|אין כאלהינו', ['Ein Keloheinu', 'Ein Kelokeinu', 'אין כאלוקינו']),
  PrayerNames('anaBekoach', r'ana bekoach|אנא בכח', ['Ana Bekoach', 'אנא בכח']),
  PrayerNames('ledavid', r'^(?:le ?david|l ?david hashem)|psalm from rosh chodesh elul|לדוד ה אורי', ['LeDavid Hashem Ori', 'Psalm 27', 'לדוד ה׳ אורי']),
  PrayerNames('barchiNafshi', r'barchi nafshi|barekhi nafshi|my soul bless|ברכי נפשי', ['Barchi Nafshi', 'Borchi Nafshi', 'Psalm 104', 'ברכי נפשי']),
  PrayerNames('thirteenPrinciples', r'thirteen principles|13 principles|י ג עקרים|שלשה עשר עקרים', ['Ani Maamin', 'Thirteen principles of faith', 'אני מאמין']),
  PrayerNames('sixRemembrances', r'six (?:remembrances|rememberances|verses of remembrance)|shesh zechirot|שש זכירות', ['Shesh Zechirot', 'Six remembrances', 'שש זכירות']),
  // Kaddish
  PrayerNames('kaddish', r'\bkaddish\b|\bkadish\b|קדיש', ['Kaddish', 'Kadish', 'קדיש']),
  PrayerNames('mournersKaddish', r'mourners kaddish|kaddish yatom|קדיש יתום', ['Kaddish Yatom', 'Mourners Kaddish', 'קדיש יתום']),
  PrayerNames('kaddishDerabbanan', r'(?:rabbis|rabbanan|rabanan|derabbanan) kaddish|kaddish (?:de ?|d )?rab+anan|קדיש דרבנן',
      ['Kaddish DeRabbanan', 'Rabbis Kaddish', 'קדיש דרבנן']),
  PrayerNames('halfKaddish', r'half kaddish|chatzi kaddish|חצי קדיש', ['Chatzi Kaddish', 'Half Kaddish', 'חצי קדיש']),
  PrayerNames('kaddishShalem', r'kaddish shalem|full kaddish|kaddish titkabal|קדיש שלם|קדיש תתקבל', ['Kaddish Shalem', 'Kaddish Titkabal', 'Full Kaddish', 'קדיש שלם']),
  PrayerNames('kedusha', r'^ke?dush[ah]+$|^keduasha$|^קדושה$', ['Kedusha', 'Kedushah', 'קדושה']),
  PrayerNames('birkatKohanim', r'(?:birkat|birkas|birchas|birchat) (?:ha)?[kc]oh?anim|priestly blessing|נשיאת כפים|ברכת כהנים',
      ['Birkat Kohanim', 'Birkas Kohanim', 'Birchas Kohanim', 'Duchenen', 'Duchaning', 'Nesiat Kapayim', 'Priestly blessing', 'ברכת כהנים']),
  PrayerNames('modim', r'^modim(?: derabbanan)?$|^מודים', ['Modim', 'Modim DeRabbanan', 'מודים']),
  // Shabbat
  PrayerNames('candles', r'candle ?lighting|hadlakat nerot|הדלקת נרות', ['Candle lighting', 'Hadlakat Nerot', 'Hadlakas Neiros', 'הדלקת נרות']),
  PrayerNames('kabbalatShabbat', r'kab+alat shab+at|kab+alas shab+os|welcoming (?:the )?shabbat|קבלת שבת', ['Kabbalat Shabbat', 'Kabbalas Shabbos', 'Welcoming Shabbat', 'קבלת שבת']),
  PrayerNames('lechaDodi', r'le[ck]h?a dodi|לכה דודי', ['Lecha Dodi', 'Lekha Dodi', 'לכה דודי']),
  PrayerNames('shalomAleichem', r'^s[hc]?[oa]lom ale[iy]?[ck]h?em$|^שלום עליכם', ['Shalom Aleichem', 'Sholom Aleichem', 'שלום עליכם']),
  PrayerNames('eshetChayil', r'[ae]i?she[st] cha?yil|eshet hayil|woman of valou?r|אשת חיל', ['Eshet Chayil', 'Eishes Chayil', 'Woman of valor', 'אשת חיל']),
  PrayerNames('kiddush', r'^kiddush(?! levan)|^קידוש(?! לבנה)|^קדוש(?! לבנה)', ['Kiddush', 'קידוש']),
  PrayerNames('zemirot', r'zemirot|zemiros|songs for shab|shabbat songs|זמירות', ['Zemirot', 'Zemiros', 'Shabbat songs', 'זמירות']),
  PrayerNames('seudaShlishit', r'(?:seuda|seudah|seudas|seudat) (?:she|sh)lishi[ts]|third meal|סעודה שלישית', ['Seudah Shlishit', 'Shalosh Seudos', 'Third meal', 'סעודה שלישית']),
  PrayerNames('pirkeiAvot', r'pirkei avo[ts]|ethics of the fathers|פרקי אבות', ['Pirkei Avot', 'Pirkei Avos', 'Ethics of the Fathers', 'פרקי אבות']),
  PrayerNames('havdalah', r'^havdal|^הבדלה', ['Havdalah', 'Havdala', 'הבדלה']),
  PrayerNames('melaveMalka', r'melav[ea] malk|fourth meal|motza?e?i shab+(?:at|os) songs|songs for motz', ['Melave Malka', 'Melaveh Malkah', 'Motzei Shabbat songs', 'מלוה מלכה']),
  PrayerNames('veyitenLecha', r've ?yiten le[ck]h?a|ויתן לך', ['Veyiten Lecha', 'ויתן לך']),
  PrayerNames('birkatHachodesh', r'blessing(?:s)? (?:of |the )?(?:the )?new month|birkat ha ?chodesh|ברכת החדש|ברכת החודש',
      ['Birkat HaChodesh', 'Blessing the new month', 'Shabbat Mevarchim', 'ברכת החודש']),
  PrayerNames('yekumPurkan', r'yekum purk[ao]n|יקום פרקן', ['Yekum Purkan', 'יקום פורקן']),
  PrayerNames('avHarachamim', r'av ha ?r[ae]ch[ae]mim|אב הרחמים', ['Av HaRachamim', 'אב הרחמים']),
  PrayerNames('animZemirot', r'shir hakavod|hymn of glory|anim zemiro[ts]|שיר הכבוד', ['Anim Zemirot', 'Shir HaKavod', 'Hymn of Glory', 'אנעים זמירות']),
  PrayerNames('governmentPrayer', r'prayer for the (?:welfare of the )?government|הנותן תשועה', ['Prayer for the government', 'Hanoten Teshua', 'הנותן תשועה']),
  PrayerNames('statePrayer', r'prayer (?:for|of) the state of israel|לשלום המדינה', ['Prayer for the State of Israel', 'Tefillah LeShlom HaMedinah', 'תפילה לשלום המדינה']),
  PrayerNames('soldiersPrayer', r'prayer for (?:israels defense forces|israeli soldiers)|idf|לחיילי צה ל', ['Prayer for IDF soldiers', 'Mi Sheberach for soldiers', 'מי שברך לחיילי צה״ל']),
  PrayerNames('misheberach', r'mi sheberach|prayer on behalf|prayer for (?:the )?(?:oleh|sick)|for sickness|מי שברך', ['Mi Sheberach', 'Mi Shebeirach', 'מי שברך']),
  PrayerNames('gomel', r'(?:birkat|birchas|birkas) ha ?gomel|^ha ?gomel$|thanksgiving blessing|ברכת הגומל', ['Birkat HaGomel', 'HaGomel', 'Thanksgiving blessing', 'ברכת הגומל']),
  PrayerNames('haftarah', r'haftar', ['Haftarah', 'Haftorah', 'Haftara blessings', 'הפטרה']),
  // Meals and blessings
  PrayerNames('birkatHamazon', r'(?:birkat|birkas|birchat|birchas|birkhat) ha ?m[ao]z[ao]n|birkas hamzon|grace after meals|post meal blessing|ברכת המזון',
      ['Birkat HaMazon', 'Birchas Hamazon', 'Bentching', 'Benching', 'Bensching', 'Grace after Meals', 'Grace', 'ברכת המזון']),
  PrayerNames('meeinShalosh', r'me ?ein shalosh|al ha ?mich?h?yah?|berakha acharona|brachot achronot|concluding blessings|מעין שלש|על המחיה',
      ['Al HaMichya', 'Meein Shalosh', 'Bracha Achrona', 'Blessing after food', 'מעין שלוש', 'על המחיה']),
  PrayerNames('boreiNefashot', r'borei nefasho[ts]|בורא נפשות', ['Borei Nefashot', 'Borei Nefashos', 'בורא נפשות']),
  PrayerNames('brachot', r'blessings? (?:on|over|before) (?:foods?|eating)|berachos said before eating|birkat hanehenin|blessings on (?:pleasures|enjoyments)|ברכות הנהנין',
      ['Brachot', 'Brachos', 'Berachot', 'Blessings on food', 'Birkot HaNehenin', 'ברכות הנהנין']),
  PrayerNames('shehecheyanu', r'she ?he ?che ?ya?nu|שהחינו|שהחיינו', ['Shehecheyanu', 'Shehechiyanu', 'שהחיינו']),
  PrayerNames('derech', r'tefill?[ao][ts] ha ?derech|travell?ers prayer|ד?תפלת הדרך|תפילת הדרך', ['Tefillat HaDerech', 'Tefilas Haderech', 'Travelers prayer', 'Wayfarers prayer', 'תפילת הדרך']),
  PrayerNames('bedtime', r'bedtime shema|shema before sleep|prayer before retiring|(?:keriat|kriat|krias) shema al ha ?mit|קריאת שמע על המטה|קריאת שמע שעל המטה',
      ['Kriat Shema al HaMita', 'Krias Shema al Hamita', 'Bedtime Shema', 'Shema before sleep', 'קריאת שמע על המיטה']),
  PrayerNames('mezuzah', r'^mezuzah?$|^מזוזה', ['Mezuzah', 'Mezuza', 'מזוזה']),
  PrayerNames('challah', r'separating (?:c)?hall?ah|hafrashat challah|הפרשת חלה', ['Hafrashat Challah', 'Separating challah', 'הפרשת חלה']),
  PrayerNames('tevilatKelim', r'tev[i]?llat kelim|immersing utensils|טבילת כלים', ['Tevilat Kelim', 'Immersing utensils', 'Toiveling', 'טבילת כלים']),
  PrayerNames('chatzot', r'midnight rite|tikkun chatzot|tikun chatzos|tikkun (?:rachel|leah)|תקון חצות|תיקון חצות', ['Tikkun Chatzot', 'Tikun Chatzos', 'Midnight lament', 'תיקון חצות']),
  // The month and the year
  PrayerNames('hallel', r'^hallel$|^הלל$', ['Hallel', 'הלל']),
  PrayerNames('levana', r'kiddush levanah?|birkat ha ?levana|blessing of the (?:new )?moon|קידוש לבנה|קדוש לבנה|ברכת הלבנה',
      ['Kiddush Levana', 'Kiddush Levanah', 'Birkat HaLevana', 'Blessing of the moon', 'קידוש לבנה']),
  PrayerNames('roshChodesh', r'^rosh (?:c)?hodesh$|^ראש חדש', ['Rosh Chodesh', 'New month', 'ראש חודש']),
  PrayerNames('yomKippurKatan', r'yom kippur katan|יום כפור קטן', ['Yom Kippur Katan', 'יום כיפור קטן']),
  PrayerNames('omer', r'(?:sefirat|sefiras|sfirat) ha ?omer|counting (?:of )?the omer|ספירת העמר|ספירת העומר',
      ['Sefirat HaOmer', 'Sefiras Haomer', 'Counting the Omer', 'Omer', 'ספירת העומר']),
  PrayerNames('hatarat', r'annulment of vows|hatar[ao][ts] nedarim|התרת נדרים', ['Hatarat Nedarim', 'Hataras Nedarim', 'Annulment of vows', 'Annulling vows', 'התרת נדרים']),
  PrayerNames('selichot', r'^seli[ck]?h?o[ts]\b|^סליחות', ['Selichot', 'Selichos', 'Slichos', 'Penitential prayers', 'סליחות']),
  PrayerNames('tashlich', r'tashli[ck]?h|תשליך', ['Tashlich', 'Tashlikh', 'תשליך']),
  PrayerNames('kaparot', r'kap+aro[ts]|כפרות', ['Kaparot', 'Kapparos', 'Kaporos', 'כפרות']),
  PrayerNames('vidui', r'^vid?u?y|confession|^וידוי', ['Vidui', 'Viduy', 'Confession', 'Ashamnu', 'וידוי']),
  PrayerNames('yizkor', r'^yizkor$|^יזכור', ['Yizkor', 'Memorial prayer', 'יזכור']),
  PrayerNames('elMaleh', r'el male|אל מלא', ['El Maleh Rachamim', 'Memorial prayer', 'אל מלא רחמים']),
  PrayerNames('lulav', r'lulav|לולב', ['Lulav', 'Netilat Lulav', 'Four species', 'Arba Minim', 'נטילת לולב']),
  PrayerNames('sukkah', r'(?:entering|leaving) the sukk?ah?|on entering the sukka|prayers in the sukkah|לישב בסוכה', ['Leishev BaSukkah', 'Entering the Sukkah', 'לישב בסוכה']),
  PrayerNames('ushpizin', r'ushpizin|אושפיזין', ['Ushpizin', 'Ushpizen', 'אושפיזין']),
  PrayerNames('hoshanot', r'hosha ?a?no[ts]|הושענות', ['Hoshanot', 'Hoshanos', 'Hoshanas', 'הושענות']),
  PrayerNames('hoshanaRaba', r'hosha ?a?na rab+ah?|הושענא רבה', ['Hoshana Rabbah', 'Hoshana Raba', 'הושענא רבה']),
  PrayerNames('geshem', r'prayer for rain|tefill?at geshem|תפלת גשם|תפילת גשם', ['Tefillat Geshem', 'Tefilas Geshem', 'Prayer for rain', 'תפילת גשם']),
  PrayerNames('tal', r'prayer for dew|tefill?at tal|תפלת טל|תפילת טל', ['Tefillat Tal', 'Tefilas Tal', 'Prayer for dew', 'תפילת טל']),
  PrayerNames('hakafot', r'hakafo[ts]|הקפות', ['Hakafot', 'Hakafos', 'הקפות']),
  PrayerNames('chanukah', r'(?:c)?hanuk+ah?|menorah lighting|hanerot hal+alu|maoz tzur|חנוכה', ['Chanukah', 'Hanukkah', 'Chanuka', 'Menorah lighting', 'Chanukah candles', 'חנוכה']),
  PrayerNames('alHanisim', r'al ha ?nis+im|על הנסים', ['Al HaNissim', 'Al Hanisim', 'על הניסים']),
  PrayerNames('purim', r'^purim|megill?ah reading|מגילה|פורים', ['Purim', 'Megillah', 'Megilla reading', 'פורים']),
  PrayerNames('chametz', r'(?:search for|removal of|burning) (?:c)?hametz|bedikat chametz|biur chametz|בדיקת חמץ|ביעור חמץ', ['Bedikat Chametz', 'Bedikas Chometz', 'Search for chametz', 'Biur Chametz', 'בדיקת חמץ']),
  PrayerNames('haggadah', r'hag+adah?|seder|הגדה', ['Haggadah', 'Hagada', 'Seder', 'הגדה של פסח']),
  PrayerNames('eruvTavshilin', r'e[i]?ruv tavshilin|עירוב תבשילין|ערוב תבשילין', ['Eruv Tavshilin', 'Eiruv Tavshilin', 'עירוב תבשילין']),
  PrayerNames('eruv', r'e[i]?ruv(?:ei|e)? (?:chatzeiros|chatzerot|techumin)|^eiruvin$|עירובי|ערובי', ['Eruv Chatzerot', 'Eruv', 'Eiruvin', 'עירוב']),
  PrayerNames('akdamut', r'akdamu[ts]|אקדמות', ['Akdamut', 'Akdamus', 'אקדמות']),
  PrayerNames('shirHashirim', r'shir ha ?shirim|song of songs|שיר השירים', ['Shir HaShirim', 'Song of Songs', 'Song of Solomon', 'שיר השירים']),
  PrayerNames('fastDays', r'fast (?:of|day)|ta?anit|tzom|תענית|צום', ['Fast day', 'Taanit', 'Tzom', 'תענית']),
  // Life cycle
  PrayerNames('britMilah', r'(?:brit|bris) mil+ah?|circumcision|ברית מילה', ['Brit Milah', 'Bris Milah', 'Bris', 'Circumcision', 'ברית מילה']),
  PrayerNames('pidyonHaben', r'pidyon ha ?ben|redemption of the first ?born|redeeming (?:the )?first ?born|פדיון הבן', ['Pidyon HaBen', 'Redemption of the firstborn', 'פדיון הבן']),
  PrayerNames('shevaBrachot', r'sheva bera?[ck]h?o[ts]|seven marriage blessings|marriage blessings|blessings of marriage|שבע ברכות', ['Sheva Brachot', 'Sheva Brachos', 'Seven blessings', 'Wedding blessings', 'שבע ברכות']),
  PrayerNames('wedding', r'marriage (?:service|ceremony)|^marriage$|חופה|קדושין', ['Wedding', 'Chuppah', 'Kiddushin', 'Marriage ceremony', 'חופה']),
  PrayerNames('barMitzvah', r'bar mitzvah?|baruch shepetarani', ['Bar Mitzvah', 'Baruch Shepetarani', 'ברוך שפטרני']),
  PrayerNames('mourning', r'house of (?:a )?mourn|mourner|funeral|אבל|לויה', ['Shiva', 'Mourners prayers', 'Funeral', 'אבלות']),
];
