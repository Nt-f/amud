import 'package:hebcal/hebcal.dart';

import 'condition.dart';

/// Which service the text is being said for. Affects seasonal switches
/// that change mid-day (e.g. Mashiv HaRuach begins at Musaf of Shmini
/// Atzeret) and which Hebrew day the evening service belongs to.
enum Service { shacharit, musaf, mincha, maariv, other }

/// User customs that affect which texts are shown.
class Minhagim {
  /// Say LeDavid (Psalm 27) from Rosh Chodesh Elul until Shmini Atzeret
  /// (true) or until Hoshana Raba (false, the more common Ashkenazi custom).
  final bool ledavidThroughShminiAtzeret;

  /// Walled city (e.g. Jerusalem): Purim is celebrated on the 15th.
  final bool walledCity;

  /// Praying with a minyan (enables chazarat hashatz / kedusha /
  /// kaddish-dependent parts).
  final bool withMinyan;

  /// User is a mourner (aveil) — shows Mourner's Kaddish emphasis etc.
  final bool mourner;

  /// Kiddush Levana may begin 3 days after the molad (Sefard/Chabad) instead
  /// of 7 (common Ashkenazi / Kabbalistic practice).
  final bool kiddushLevana3Days;

  /// Sefardi/Edot HaMizrach practice: say "Barechenu" in summer.
  final bool sefardi;

  /// Davening in a shiva house (no Tachanun, no Birkat Kohanim, …).
  final bool houseOfMourning;

  /// Wears tefillin on Chol HaMoed (most don't).
  final bool tefillinCholHamoed;

  /// A bris or a chatan in the congregation today (no Tachanun).
  final bool bris;
  final bool chatan;

  const Minhagim({
    this.ledavidThroughShminiAtzeret = false,
    this.walledCity = false,
    this.withMinyan = true,
    this.mourner = false,
    this.kiddushLevana3Days = false,
    this.sefardi = false,
    this.houseOfMourning = false,
    this.tefillinCholHamoed = false,
    this.bris = false,
    this.chatan = false,
  });

  Map<String, Object?> toJson() => {
        'ledavidThroughShminiAtzeret': ledavidThroughShminiAtzeret,
        'walledCity': walledCity,
        'withMinyan': withMinyan,
        'mourner': mourner,
        'kiddushLevana3Days': kiddushLevana3Days,
        'sefardi': sefardi,
        'houseOfMourning': houseOfMourning,
        'tefillinCholHamoed': tefillinCholHamoed,
        'bris': bris,
        'chatan': chatan,
      };

  factory Minhagim.fromJson(Map<String, Object?> j) => Minhagim(
        ledavidThroughShminiAtzeret: j['ledavidThroughShminiAtzeret'] == true,
        walledCity: j['walledCity'] == true,
        withMinyan: j['withMinyan'] != false,
        mourner: j['mourner'] == true,
        kiddushLevana3Days: j['kiddushLevana3Days'] == true,
        sefardi: j['sefardi'] == true,
        houseOfMourning: j['houseOfMourning'] == true,
        tefillinCholHamoed: j['tefillinCholHamoed'] == true,
        bris: j['bris'] == true,
        chatan: j['chatan'] == true,
      );

  Minhagim copyWith({
    bool? ledavidThroughShminiAtzeret,
    bool? walledCity,
    bool? withMinyan,
    bool? mourner,
    bool? kiddushLevana3Days,
    bool? sefardi,
    bool? houseOfMourning,
    bool? tefillinCholHamoed,
    bool? bris,
    bool? chatan,
  }) =>
      Minhagim(
        ledavidThroughShminiAtzeret: ledavidThroughShminiAtzeret ?? this.ledavidThroughShminiAtzeret,
        walledCity: walledCity ?? this.walledCity,
        withMinyan: withMinyan ?? this.withMinyan,
        mourner: mourner ?? this.mourner,
        kiddushLevana3Days: kiddushLevana3Days ?? this.kiddushLevana3Days,
        sefardi: sefardi ?? this.sefardi,
        houseOfMourning: houseOfMourning ?? this.houseOfMourning,
        tefillinCholHamoed: tefillinCholHamoed ?? this.tefillinCholHamoed,
        bris: bris ?? this.bris,
        chatan: chatan ?? this.chatan,
      );
}

/// Everything the liturgy depends on for a particular Hebrew day and service.
///
/// The Hebrew date is the *halachic* day: Maariv on Tuesday evening belongs
/// to Wednesday's Hebrew date. Use [DayContext.forService] to have that
/// shift applied automatically from a daytime date.
class DayContext {
  final HDate hdate;
  final bool il;
  final Service service;
  final Minhagim minhagim;

  /// Condition variables. See [variableDocs] for the list.
  final ConditionEnv env;

  /// Human-readable labels for today's special days (for the header chips).
  final List<String> labels;
  final List<String> labelsHe;

  DayContext._(this.hdate, this.il, this.service, this.minhagim, this.env, this.labels,
      this.labelsHe);

  /// Builds a context for [hdate] (already the halachic day of the service).
  factory DayContext(HDate hdate,
      {required bool il, Service service = Service.shacharit, Minhagim minhagim = const Minhagim(), DateTime? now}) {
    final b = _Builder(hdate, il, service, minhagim);
    b.build();
    return DayContext._(hdate, il, service, minhagim, Map.unmodifiable(b.env), b.labels, b.labelsHe);
  }

  /// Given the *civil daytime* Hebrew date (i.e. the date before any sunset
  /// shift), returns the context for [service]; Maariv is shifted to the
  /// next Hebrew day.
  factory DayContext.forService(HDate daytimeDate, Service service,
          {required bool il, Minhagim minhagim = const Minhagim()}) =>
      DayContext(service == Service.maariv ? daytimeDate.next() : daytimeDate,
          il: il, service: service, minhagim: minhagim);

  bool operator [](String name) {
    final v = env[name];
    return v is bool ? v : (v is num ? v != 0 : false);
  }

  num number(String name) => (env[name] as num?) ?? 0;

  bool test(String expression) => Condition.parse(expression).eval(env);

  /// Documentation for every variable exposed to rules and JS cards.
  static const Map<String, String> variableDocs = {
    'dow': 'Day of week, 0=Sunday … 6=Shabbat',
    'hDay': 'Day of Hebrew month',
    'hMonth': 'Hebrew month number (Nisan=1 … Adar II=13)',
    'hYear': 'Hebrew year',
    'il': 'Israel customs (vs diaspora)',
    'diaspora': 'Diaspora customs',
    'shacharit': 'Service is Shacharit',
    'musaf': 'Service is Musaf',
    'mincha': 'Service is Mincha',
    'maariv': 'Service is Maariv/Arvit',
    'weekday': 'Not Shabbat and not Yom Tov',
    'shabbat': 'Shabbat',
    'erevShabbat': 'Friday',
    'motzaeiShabbat': 'Saturday night (Maariv after Shabbat)',
    'yomTov': 'Yom Tov (including Rosh Hashana, Yom Kippur)',
    'motzaeiYomTov': 'Night after Yom Tov',
    'cholHamoed': 'Chol HaMoed (Pesach or Sukkot)',
    'cholHamoedPesach': 'Chol HaMoed Pesach',
    'cholHamoedSukkot': 'Chol HaMoed Sukkot (incl. Hoshana Raba)',
    'roshChodesh': 'Rosh Chodesh',
    'roshChodeshDay': 'Which day of a 2-day Rosh Chodesh (1 or 2)',
    'erevRoshChodesh': 'Day before Rosh Chodesh',
    'roshHashana': 'Rosh Hashana',
    'yomKippur': 'Yom Kippur',
    'erevYomKippur': 'Erev Yom Kippur',
    'aseretYemeiTeshuva': 'Rosh Hashana through Yom Kippur',
    'shabbatShuva': 'Shabbat between RH and YK',
    'sukkot': 'Sukkot (1st day through Hoshana Raba)',
    'hoshanaRaba': 'Hoshana Raba',
    'shminiAtzeret': 'Shmini Atzeret',
    'simchatTorah': 'Simchat Torah (Shmini Atzeret in Israel)',
    'pesach': 'Pesach (all days)',
    'pesachFirstDays': 'First day(s) of Pesach',
    'pesachLastDays': 'Last day(s) of Pesach',
    'shavuot': 'Shavuot',
    'chanukah': 'Chanukah',
    'chanukahDay': 'Day of Chanukah 1-8 (0 if not Chanukah)',
    'purim': 'Purim (14 Adar, or 15 in a walled city)',
    'shushanPurim': '15 Adar',
    'purimKatan': 'Purim Katan (14/15 Adar I)',
    'publicFast': 'Public fast day (not Yom Kippur/Tisha B\'Av)',
    'fastDay': 'Any fast day (incl. Tisha B\'Av, not Yom Kippur)',
    'tishaBav': 'Tisha B\'Av',
    'tzomGedaliah': 'Tzom Gedaliah',
    'asaraBTevet': 'Asara B\'Tevet',
    'taanitEsther': 'Ta\'anit Esther',
    'tzomTammuz': '17 Tammuz',
    'yomKippurKatan': 'Yom Kippur Katan',
    'behab': 'Ta\'anit BeHaB',
    'threeWeeks': 'Bein HaMetzarim',
    'nineDays': 'Rosh Chodesh Av – Tisha B\'Av',
    'elul': 'Month of Elul',
    'ledavid': 'LeDavid (Psalm 27) season',
    'mashivHaruach': 'Say Mashiv HaRuach (winter)',
    'moridHatal': 'Say Morid HaTal (summer, Sefard/Israel)',
    'talUmatar': 'Say V\'ten tal u\'matar',
    'omer': 'During Sefirat HaOmer (day count > 0)',
    'omerDay': 'Omer day 1-49 for this Hebrew date (0 if none)',
    'hallel': 'Hallel said (half or whole)',
    'wholeHallel': 'Whole Hallel',
    'halfHallel': 'Half Hallel',
    'tachanun': 'Tachanun said at this service',
    'tachanunShacharit': 'Tachanun said at Shacharit',
    'tachanunMincha': 'Tachanun said at Mincha',
    'monThu': 'Monday or Thursday',
    'torahReading': 'Torah reading at this service',
    'avinuMalkeinu': 'Avinu Malkeinu said',
    'tzidkatcha': 'Tzidkatcha Tzedek said (Shabbat Mincha)',
    'avHarachamim': 'Av HaRachamim said',
    'barchiNafshiShabbat': 'Barchi Nafshi at Shabbat Mincha (winter)',
    'pirkeiAvot': 'Pirkei Avot at Shabbat Mincha (summer)',
    'shabbatMevarchim': 'Shabbat before Rosh Chodesh (not Tishrei)',
    'yomHaatzmaut': 'Yom HaAtzma\'ut',
    'yomYerushalayim': 'Yom Yerushalayim',
    'yomHazikaron': 'Yom HaZikaron',
    'isruChag': 'Day after a Pilgrimage festival',
    'kiddushLevana': 'Within the Kiddush Levana window (by day)',
    'eruvTavshilin': 'Eruv Tavshilin needed today',
    'yizkor': 'Yizkor day',
    'minyan': 'Praying with a minyan',
    'mourner': 'User is a mourner',
    'aveilut': 'Sefira or Three Weeks mourning period',
    'kohanim': 'Kohanim say Birkat Kohanim at this service (Israel daily; diaspora on Yom Tov)',
    'birkatKohanimChazzan': "Chazzan says Elokeinu ve'Elokei avoteinu (no kohanim, not a house of mourning, not Tisha B'Av morning)",
    'hoshanaDay': 'Day of Sukkot for Hoshanot 1-7 (0 if none)',
    'erevPesach': 'Erev Pesach',
    'houseOfMourning': 'Davening in a shiva house',
    'noTefillinCholHamoed': 'Custom of not wearing tefillin on Chol HaMoed',
    'yomTovDay': 'Which day of a Yom Tov (1 or 2; 0 if not Yom Tov)',
    'firstDayRoshHashana': '1 Tishrei',
    'secondDayRoshHashana': '2 Tishrei',
    'shabbatShekalim': 'Shabbat Shekalim',
    'shabbatZachor': 'Shabbat Zachor',
    'shabbatParah': 'Shabbat Parah',
    'shabbatHachodesh': 'Shabbat HaChodesh',
    'shabbatHagadol': 'Shabbat HaGadol',
    'shabbatChazon': 'Shabbat Chazon',
    'shabbatNachamu': 'Shabbat Nachamu',
    'erevTishaBav': "Day before Tisha B'Av (as observed)",
    'tuBishvat': 'Tu BiShvat',
    'tuBav': "Tu B'Av",
    'lagBaomer': 'Lag BaOmer',
    'pesachSheni': 'Pesach Sheni',
    'bris': 'A bris in the congregation today (no Tachanun)',
    'chatan': 'A chatan in the congregation (no Tachanun)',
    'leapYear': 'Hebrew leap year',
  };
}

class _Builder {
  final HDate hd;
  final bool il;
  final Service service;
  final Minhagim m;
  final ConditionEnv env = {};
  final List<String> labels = [];
  final List<String> labelsHe = [];

  _Builder(this.hd, this.il, this.service, this.m);

  void set(String k, Object v) => env[k] = v;

  void build() {
    final dow = hd.getDay();
    final day = hd.getDate();
    final month = hd.getMonth();
    final year = hd.getFullYear();
    final events = getHolidaysOnDate(hd, il);
    bool has(bool Function(HolidayEvent e) f) => events.any(f);
    bool desc(String d) => has((e) => e.getDesc() == d);
    bool descStarts(String d) => has((e) => e.getDesc().startsWith(d));

    set('dow', dow);
    set('hDay', day);
    set('hMonth', month);
    set('hYear', year);
    set('il', il);
    set('diaspora', !il);
    set('leapYear', isLeapYear(year));
    set('shacharit', service == Service.shacharit);
    set('musaf', service == Service.musaf);
    set('mincha', service == Service.mincha);
    set('maariv', service == Service.maariv);
    set('minyan', m.withMinyan);
    set('mourner', m.mourner);

    final shabbat = dow == 6;
    final yomTov = has((e) => e.hasFlag(Flags.chag));
    final prevHd = hd.prev();
    final prevYomTov = getHolidaysOnDate(prevHd, il).any((e) => e.hasFlag(Flags.chag));
    set('shabbat', shabbat);
    set('erevShabbat', dow == 5);
    set('motzaeiShabbat', dow == 0 && service == Service.maariv);
    set('yomTov', yomTov);
    set('motzaeiYomTov', prevYomTov && !yomTov && service == Service.maariv);
    set('weekday', !shabbat && !yomTov);

    final cholHamoed = has((e) => e.hasFlag(Flags.cholHamoed));
    final pesach = month == Months.nisan && day >= 15 && day <= (il ? 21 : 22);
    final sukkot = month == Months.tishrei && day >= 15 && day <= 21;
    set('cholHamoed', cholHamoed);
    set('cholHamoedPesach', cholHamoed && month == Months.nisan);
    set('cholHamoedSukkot', cholHamoed && month == Months.tishrei);
    set('pesach', pesach);
    set('pesachFirstDays', month == Months.nisan && (day == 15 || (!il && day == 16)));
    set('pesachLastDays', month == Months.nisan && (day == 21 || (!il && day == 22)));
    set('sukkot', sukkot);
    set('hoshanaRaba', month == Months.tishrei && day == 21);
    set('shminiAtzeret', month == Months.tishrei && day == 22);
    set('simchatTorah', month == Months.tishrei && day == (il ? 22 : 23));
    set('shavuot', month == Months.sivan && (day == 6 || (!il && day == 7)));

    final rc = has((e) => e.hasFlag(Flags.roshChodesh));
    set('roshChodesh', rc);
    set('roshChodeshDay', rc ? (day == 1 && hd.prev().getDate() == 30 ? 2 : 1) : 0);
    set('erevRoshChodesh', getHolidaysOnDate(hd.next(), il).any((e) => e.hasFlag(Flags.roshChodesh)) && !rc);

    final rh = month == Months.tishrei && (day == 1 || day == 2);
    final yk = month == Months.tishrei && day == 10;
    set('roshHashana', rh);
    set('yomKippur', yk);
    set('erevYomKippur', month == Months.tishrei && day == 9);
    set('aseretYemeiTeshuva', month == Months.tishrei && day <= 10);
    set('shabbatShuva', month == Months.tishrei && day <= 10 && shabbat);

    final chanukahEv = events.whereType<ChanukahEvent>().toList();
    var chanukahDay = 0;
    // Chanukah daytime days are 25 Kislev .. 2/3 Tevet. The "1 Candle" event
    // is on erev (24 Kislev) so daytime day = candles-1.
    for (final e in chanukahEv) {
      final d = e.chanukahDay ?? 0;
      if (d > chanukahDay) chanukahDay = d;
    }
    set('chanukah', chanukahDay > 0);
    set('chanukahDay', chanukahDay);

    final isPurim14 = desc(HolidayDesc.purim);
    final isShushan = desc(HolidayDesc.shushanPurim);
    set('purim', m.walledCity ? isShushan : isPurim14);
    set('shushanPurim', isShushan);
    set('purimKatan', desc(HolidayDesc.purimKatan) || desc(HolidayDesc.shushanPurimKatan));

    final tishaBav = descStarts(HolidayDesc.tishaBav);
    final minorFast = has((e) => e.hasFlag(Flags.minorFast) && !e.hasFlag(Flags.yomKippurKatan) && !e.hasFlag(Flags.behab));
    set('tishaBav', tishaBav);
    set('publicFast', minorFast);
    set('fastDay', minorFast || tishaBav);
    set('tzomGedaliah', desc(HolidayDesc.tzomGedaliah));
    set('asaraBTevet', desc(HolidayDesc.asaraBtevet));
    set('taanitEsther', desc(HolidayDesc.taanitEsther));
    set('tzomTammuz', desc(HolidayDesc.tzomTammuz));
    set('yomKippurKatan', has((e) => e.hasFlag(Flags.yomKippurKatan)));
    set('behab', has((e) => e.hasFlag(Flags.behab)));

    final tammuz17 = HDate(17, Months.tamuz, year).abs();
    var av9 = HDate(9, Months.av, year);
    if (av9.getDay() == 6) av9 = av9.next();
    final abs = hd.abs();
    set('threeWeeks', abs >= tammuz17 && abs <= av9.abs());
    set('nineDays', month == Months.av && abs <= av9.abs());
    set('aveilut', isAveilut(hd));

    set('elul', month == Months.elul);
    final ledavidEnd = m.ledavidThroughShminiAtzeret ? 22 : 21;
    set('ledavid', month == Months.elul || (month == Months.tishrei && day <= ledavidEnd));

    // Mashiv HaRuach from Musaf of Shmini Atzeret to Shacharit of 1st day Pesach.
    final afterSA = day > 22 || (day == 22 && service != Service.shacharit);
    bool winterGevurot() {
      if (month == Months.tishrei) return afterSA;
      if (month >= Months.cheshvan) return true; // Cheshvan..Adar II
      if (month == Months.nisan) return day < 15 || (day == 15 && service == Service.shacharit);
      return false; // Iyyar..Elul
    }

    final winter = winterGevurot();
    set('mashivHaruach', winter);
    // Ashkenaz in the diaspora says nothing in its place.
    set('moridHatal', !winter && (il || m.sefardi));
    set('talUmatar', _talUmatar(month, day, year));

    final omerDay = _omerDay();
    set('omerDay', omerDay);
    set('omer', omerDay > 0);

    final hallelType = hallel(hd, il);
    // Chanukah hallel is included by hebcal; Rosh Chodesh is half.
    set('hallel', hallelType != HallelType.none);
    set('wholeHallel', hallelType == HallelType.whole);
    set('halfHallel', hallelType == HallelType.half);

    final t = tachanun(hd, il);
    set('tachanunShacharit', t.shacharit);
    set('tachanunMincha', t.mincha);
    set('tachanun', service == Service.mincha ? t.mincha : (service == Service.shacharit ? t.shacharit : false));
    set('monThu', dow == 1 || dow == 4);
    // At Mincha the Torah is read only on Shabbat, fast days and Yom Kippur.
    set('torahReading', service == Service.mincha
        ? shabbat || minorFast || tishaBav || yk
        : shabbat || yomTov || rc || cholHamoed || (dow == 1 || dow == 4) && service == Service.shacharit ||
            chanukahDay > 0 || isPurim14 || minorFast || tishaBav);

    final ayt = month == Months.tishrei && day <= 10;
    set('avinuMalkeinu', !shabbat && (ayt || minorFast) && service != Service.maariv &&
        !(month == Months.tishrei && day == 9 && service == Service.mincha) &&
        !(dow == 5 && service == Service.mincha));
    set('tzidkatcha', shabbat && service == Service.mincha && t.mincha);
    final shabbatMevarchim = shabbat && month != Months.elul && day >= 23 && day <= 29;
    set('shabbatMevarchim', shabbatMevarchim);
    set('avHarachamim', shabbat && !isNoTachanunDay(hd, il) &&
        (!shabbatMevarchim || isAveilut(hd)));
    // Barchi Nafshi at Shabbat Mincha: Shabbat Bereshit until Shabbat HaGadol.
    final winterShabbat = shabbat &&
        ((month == Months.tishrei && day > 22) || month >= Months.cheshvan || (month == Months.nisan && day < 15));
    set('barchiNafshiShabbat', winterShabbat && service == Service.mincha);
    set('pirkeiAvot', shabbat && !winterShabbat && service == Service.mincha && !(month == Months.tishrei));

    set('yomHaatzmaut', desc(HolidayDesc.yomHaatzmaUt));
    set('yomYerushalayim', desc(HolidayDesc.yomYerushalayim));
    set('yomHazikaron', desc(HolidayDesc.yomHazikaron));
    final prevDesc = getHolidaysOnDate(prevHd, il).map((e) => e.getDesc()).toList();
    set('isruChag', !yomTov && prevDesc.any((d) =>
        d == HolidayDesc.pesachVII || d == HolidayDesc.pesachVIII || d == HolidayDesc.shavuot ||
        d == HolidayDesc.shavuotII || d == HolidayDesc.shminiAtzeret || d == HolidayDesc.simchatTorah));
    set('kiddushLevana', day >= (m.kiddushLevana3Days ? 3 : 7) && day <= 15 && !(month == Months.av && day < 10) &&
        !(month == Months.tishrei && day < 10));
    set('eruvTavshilin', eruvTavshilin(hd, il));
    set('erevPesach', month == Months.nisan && day == 14);
    set('firstDayRoshHashana', month == Months.tishrei && day == 1);
    set('secondDayRoshHashana', month == Months.tishrei && day == 2);
    set('shabbatShekalim', desc(HolidayDesc.shabbatShekalim));
    set('shabbatZachor', desc(HolidayDesc.shabbatZachor));
    set('shabbatParah', desc(HolidayDesc.shabbatParah));
    set('shabbatHachodesh', desc(HolidayDesc.shabbatHachodesh));
    set('shabbatHagadol', desc(HolidayDesc.shabbatHagadol));
    set('shabbatChazon', desc(HolidayDesc.shabbatChazon));
    set('shabbatNachamu', desc(HolidayDesc.shabbatNachamu));
    set('erevTishaBav', abs == av9.abs() - 1);
    set('tuBishvat', month == Months.shvat && day == 15);
    set('tuBav', month == Months.av && day == 15);
    set('lagBaomer', omerDay == 33);
    set('pesachSheni', month == Months.iyyar && day == 14);
    set('bris', m.bris);
    set('chatan', m.chatan);
    set('hoshanaDay', sukkot ? day - 14 : 0);
    set('yomTovDay', yomTov ? (prevYomTov ? 2 : 1) : 0);
    set('houseOfMourning', m.houseOfMourning);
    set('noTefillinCholHamoed', !m.tefillinCholHamoed);
    // Birkat Kohanim: the kohanim's own in Israel at every Shacharit and
    // Musaf (and Mincha of a fast), in the diaspora only at Musaf of a
    // weekday Yom Tov; otherwise the chazzan says it in the repetition. Not
    // on Tisha B'Av morning or in a house of mourning.
    final bkService = (service == Service.shacharit && !tishaBav) || service == Service.musaf ||
        (service == Service.mincha && (minorFast || tishaBav));
    final kohanim = m.withMinyan && !m.houseOfMourning && bkService &&
        (il || (service == Service.musaf && yomTov && !shabbat));
    set('kohanim', kohanim);
    set('birkatKohanimChazzan', m.withMinyan && !m.houseOfMourning && bkService && !kohanim);
    set('yizkor', (month == Months.tishrei && (day == 10 || day == 22)) ||
        (month == Months.nisan && day == (il ? 21 : 22)) ||
        (month == Months.sivan && day == (il ? 6 : 7)));

    for (final e in events) {
      if (e.hasFlag(Flags.yomKippurKatan) || e.hasFlag(Flags.behab)) continue;
      labels.add(e.render('en'));
      labelsHe.add(e.render('he-x-NoNikud'));
    }
    if (omerDay > 0) {
      labels.add('Omer day $omerDay');
      labelsHe.add('${gematriya(omerDay)} בעומר');
    }
    if (shabbat && !yomTov) {
      final p = getSedra(year, il).lookup(hd);
      if (!p.chag) {
        labels.add(renderParshaName(p.parsha, 'en'));
        labelsHe.add(renderParshaName(p.parsha, 'he-x-NoNikud'));
      }
    }
  }

  int _omerDay() => omerDay(hd);

  bool _talUmatar(int month, int day, int year) {
    if (month == Months.nisan && day >= 15) return false;
    if (month < Months.tishrei) return month == Months.nisan; // Nisan 1-14
    if (il) {
      return month > Months.cheshvan || (month == Months.cheshvan && day >= 7);
    }
    // Diaspora: begins at Maariv of the 60th day after tekufat Tishrei
    // (Dec 4 evening, Dec 5 before a Gregorian leap year, in 1900–2099).
    final gy = year - 3761;
    final diff = (gy ~/ 100) - (gy ~/ 400) - 2; // Julian/Gregorian gap
    final leapAdj = isGregLeapYear(gy + 1) ? 1 : 0;
    final eveningDay = 4 + (diff - 13) + leapAdj;
    final startDaytime = HDate.fromAbs(gregYmdToAbs(gy, 12, eveningDay) + 1);
    return hd.abs() >= startDaytime.abs();
  }
}
