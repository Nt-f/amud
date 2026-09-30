// Port of @hebcal/learning
// Copyright (c) Michael J. Radwin. BSD-2-Clause.
// Dart port licensed under BSD-2-Clause.

import '../calendar.dart';
import '../data/learning_data.g.dart' as data;
import '../data/learning_tables.g.dart' as tables;
import '../event.dart';
import '../greg.dart';
import '../hdate.dart';
import '../holidays.dart';
import '../locale.dart';

// ------------------------------------------------------------------ common

void _checkTooEarly(int abs, int startAbs, String name) {
  if (abs < startAbs) {
    throw RangeError(
        'Date ${abs2greg(abs).toIso8601String().substring(0, 10)} too early; '
        '$name cycle began on ${abs2greg(startAbs).toIso8601String().substring(0, 10)}');
  }
}

String formatBeginEndRange(String begin, String end) {
  final p1 = begin.split(':');
  final p2 = end.split(':');
  final verse2 = p1[0] == p2[0] && p2.length > 1 ? p2[1] : p2.join(':');
  return '$begin-$verse2';
}

String gematriyaNN(Object num) => gematriya(num).replaceAll(RegExp('[׳״]'), '');

String sefariaUrl(String book, Object chapter) {
  final slug = book.replaceAll(' ', '_').replaceAll(',', '%2C');
  return 'https://www.sefaria.org/$slug.$chapter?lang=bi';
}

String _jsNum(Object v) {
  if (v is double && v == v.truncateToDouble()) return v.toInt().toString();
  return '$v';
}

int _g(int y, int m, int d) => gregYmdToAbs(y, m, d);

/// Base class for all daily learning events.
abstract class DailyLearningEvent extends Event {
  DailyLearningEvent(super.date, super.desc, [super.mask = Flags.dailyLearning]);

  /// Human-readable name of the learning program.
  String? get category => null;
}

// ------------------------------------------------------------------ DafPage

/// A page of Talmud, such as Berachot 34.
class DafPage {
  final String name;
  final Object blatt;
  final int? cycle;
  const DafPage(this.name, this.blatt, [this.cycle]);

  Object getBlatt() => blatt;
  String getName() => name;

  String render([String? locale]) {
    if (Locale.isHebrewLocale(locale)) {
      return '${Locale.gettext(name, locale)} דף ${gematriya(blatt)}';
    }
    return '${Locale.gettext(name, locale)} $blatt';
  }
}

final List<String> _tractateNames = data.bavliJson.keys.toList();
final List<int> _tractateLastDaf = data.bavliJson.values.cast<int>().toList();
const _shekalimIndex = 4;
const Map<int, int> _dafOffsets = {36: 21, 37: 24, 38: 32};
final int dafYomiOldStart = _g(1923, 9, 11);
final int _dafYomiNewStart = _g(1975, 6, 24);
const _oldCycleLength = 2702;
const _newCycleLength = 2711;
const _firstNewCycle = 8;

DafPage calculateDafYomi(int absolute) {
  _checkTooEarly(absolute, dafYomiOldStart, 'Daf Yomi');
  int cycle;
  int dayInCycle;
  if (absolute >= _dafYomiNewStart) {
    final elapsed = absolute - _dafYomiNewStart;
    cycle = _firstNewCycle + elapsed ~/ _newCycleLength;
    dayInCycle = elapsed % _newCycleLength;
  } else {
    final elapsed = absolute - dafYomiOldStart;
    cycle = 1 + elapsed ~/ _oldCycleLength;
    dayInCycle = elapsed % _oldCycleLength;
  }
  final lastDaf = List.of(_tractateLastDaf);
  if (cycle < _firstNewCycle) lastDaf[_shekalimIndex] = 13;
  var daysSoFar = 0;
  for (var index = 0; index < lastDaf.length; index++) {
    daysSoFar += lastDaf[index] - 1;
    if (dayInCycle < daysSoFar) {
      final daf = lastDaf[index] + 1 - (daysSoFar - dayInCycle) + (_dafOffsets[index] ?? 0);
      return DafPage(_tractateNames[index], daf, cycle);
    }
  }
  throw StateError('Daf Yomi calculation fell through');
}

const Map<String, String> _dafYomiSefaria = {
  'Berachot': 'Berakhot',
  'Rosh Hashana': 'Rosh Hashanah',
  'Gitin': 'Gittin',
  'Baba Kamma': 'Bava Kamma',
  'Baba Metzia': 'Bava Metzia',
  'Baba Batra': 'Bava Batra',
  'Bechorot': 'Bekhorot',
  'Arachin': 'Arakhin',
  'Midot': 'Middot',
  'Shekalim': 'Jerusalem_Talmud_Shekalim',
};

abstract class DafPageEvent extends DailyLearningEvent {
  final DafPage daf;
  DafPageEvent(HDate date, this.daf, int mask) : super(date, daf.render('en'), mask);

  @override
  String render([String? locale]) => daf.render(locale);
  @override
  String renderBrief([String? locale]) => daf.render(locale);

  @override
  String? url() {
    final tractate = daf.getName();
    final blatt = daf.getBlatt();
    if (tractate == 'Kinnim' || tractate == 'Midot') {
      return 'https://www.dafyomi.org/index.php?masechta=meilah&daf=${blatt}a';
    }
    if (tractate == 'Shekalim') {
      final aEntry = data.shekalimDafYomiMapJson['${blatt}a'];
      final bEntry = data.shekalimDafYomiMapJson['${blatt}b'];
      if (aEntry == null || bEntry == null) return null;
      final aStart = aEntry.split('-')[0];
      final bEnd = bEntry.contains('-') ? bEntry.split('-')[1] : bEntry;
      return sefariaUrl('Jerusalem Talmud Shekalim', '$aStart-$bEnd'.replaceAll(':', '.'));
    }
    return sefariaUrl(_dafYomiSefaria[tractate] ?? tractate, '${blatt}a');
  }
}

class DafYomiEvent extends DafPageEvent {
  DafYomiEvent(HDate date) : super(date, calculateDafYomi(date.abs()), Flags.dafYomi);
  @override
  String get category => 'Daf Yomi';
  @override
  String render([String? locale]) => '${Locale.gettext('Daf Yomi', locale)}: ${daf.render(locale)}';
  @override
  List<String> getCategories() => const ['dafyomi'];
}

final int dafWeeklyStart = _g(2005, 3, 6);

DafPage dafWeekly(int abs) {
  _checkTooEarly(abs, dafWeeklyStart, 'Daf-a-Week');
  final dayNum = (abs - dafWeeklyStart) % (_newCycleLength * 7);
  final weekNum = dayNum ~/ 7;
  var weeksSoFar = 0;
  for (var index = 0; index < _tractateLastDaf.length; index++) {
    weeksSoFar += _tractateLastDaf[index] - 1;
    if (weekNum < weeksSoFar) {
      final daf = _tractateLastDaf[index] + 1 - (weeksSoFar - weekNum) + (_dafOffsets[index] ?? 0);
      return DafPage(_tractateNames[index], daf);
    }
  }
  throw StateError('dafWeekly calculation fell through');
}

class DafWeeklyEvent extends DafPageEvent {
  DafWeeklyEvent(HDate date, DafPage daf) : super(date, daf, Flags.dailyLearning);
  @override
  String get category => 'Daf Weekly';
  @override
  List<String> getCategories() => const ['dafWeekly'];
}

// ------------------------------------------------------------------ Mishna

class MishnaYomi {
  final String k;
  final String v;
  const MishnaYomi(this.k, this.v);
}

final int mishnaYomiStart = _g(1947, 5, 20);
const _numMishnayot = 4192;
const _numMishnaDays = _numMishnayot ~/ 2;

final List<List<MishnaYomi>> _mishnaDays = () {
  final tmp = <MishnaYomi>[];
  for (final e in data.mishnayotJson.entries) {
    final v = e.value.cast<int>();
    for (var chap = 1; chap <= v.length; chap++) {
      for (var verse = 1; verse <= v[chap - 1]; verse++) {
        tmp.add(MishnaYomi(e.key, '$chap:$verse'));
      }
    }
  }
  return [for (var j = 0; j < _numMishnaDays; j++) [tmp[j * 2], tmp[j * 2 + 1]]];
}();

List<MishnaYomi> mishnaYomi(int abs) {
  _checkTooEarly(abs, mishnaYomiStart, 'Mishna Yomi');
  return _mishnaDays[(abs - mishnaYomiStart) % _numMishnaDays];
}

String _formatMyomi(List<MishnaYomi> m, [String? locale]) {
  final k1 = m[0].k;
  final cv1 = m[0].v;
  final mishna1 = '${Locale.gettext(k1, locale)} $cv1';
  final k2 = m[1].k;
  final cv2 = m[1].v;
  if (k1 != k2) return '$mishna1-${Locale.gettext(k2, locale)} $cv2';
  final p1 = cv1.split(':');
  final p2 = cv2.split(':');
  if (p1[0] == p2[0]) return '$mishna1-${p2[1]}';
  return '$mishna1-$cv2';
}

class MishnaYomiEvent extends DailyLearningEvent {
  final List<MishnaYomi> mishnaYomi;
  MishnaYomiEvent(HDate date, this.mishnaYomi)
      : super(date, _formatMyomi(mishnaYomi), Flags.mishnaYomi);
  @override
  String get category => 'Mishna Yomi';
  @override
  String render([String? locale]) => _formatMyomi(mishnaYomi, locale);
  @override
  String url() {
    final k1 = mishnaYomi[0].k;
    final prefix =
        'https://www.sefaria.org/${k1 == 'Avot' ? 'Pirkei' : 'Mishnah'}_${k1.replaceAll(' ', '_')}';
    final cv1 = mishnaYomi[0].v;
    if (k1 != mishnaYomi[1].k) return '$prefix.${cv1.replaceFirst(':', '.')}?lang=bi';
    final p1 = cv1.split(':');
    final p2 = mishnaYomi[1].v.split(':');
    final verse2 = p1[0] == p2[0] ? p2[1] : p2.join('.');
    return '$prefix.${p1.join('.')}-$verse2?lang=bi';
  }

  @override
  List<String> getCategories() => const ['mishnayomi'];
}

final int perekYomiStart = _g(2002, 2, 9);

(String, int) perekYomi(int abs) {
  _checkTooEarly(abs, perekYomiStart, 'Perek Yomi');
  var total = (abs - perekYomiStart) % 525;
  for (final e in data.mishnayotJson.entries) {
    final numChaps = e.value.length;
    if (total < numChaps) return (e.key, total + 1);
    total -= numChaps;
  }
  throw StateError('unreachable');
}

abstract class DailyChapterEvent extends DailyLearningEvent {
  final String k;
  final int v;
  DailyChapterEvent(HDate date, this.k, this.v, int mask) : super(date, '$k $v', mask);
  @override
  String render([String? locale]) {
    final name = Locale.gettext(k, locale);
    return Locale.isHebrewLocale(locale) ? '$name ${gematriya(v)}' : '$name $v';
  }

  @override
  String url() => sefariaUrl(k, v);
}

class PerekYomiEvent extends DailyChapterEvent {
  PerekYomiEvent(HDate date, (String, int) r) : super(date, r.$1, r.$2, Flags.dailyLearning);
  @override
  String get category => 'Perek Yomi';
  @override
  String url() => sefariaUrl('${k == 'Avot' ? 'Pirkei' : 'Mishnah'} ${k.replaceAll(' ', '_')}', v);
  @override
  List<String> getCategories() => const ['perekYomi'];
}

// ------------------------------------------------------------------ Nach

final int nachYomiStart = _g(2007, 11, 1);
final List<(String, int)> _nachDays = () {
  final out = <(String, int)>[];
  for (final e in data.tanakhNumChapJson.entries.skip(5)) {
    for (var chap = 1; chap <= e.value; chap++) {
      out.add((e.key, chap));
    }
  }
  return out;
}();

(String, int) nachYomi(int abs) {
  _checkTooEarly(abs, nachYomiStart, 'Nach Yomi');
  return _nachDays[(abs - nachYomiStart) % _nachDays.length];
}

class NachYomiEvent extends DailyChapterEvent {
  NachYomiEvent(HDate date, (String, int) r) : super(date, r.$1, r.$2, Flags.nachYomi);
  @override
  String get category => 'Nach Yomi';
  @override
  List<String> getCategories() => const ['nachyomi'];
}

// ------------------------------------------------------------------ Yerushalmi

class YerushalmiYomiConfig {
  final String ed;
  final int startAbs;
  final bool skipYK9Av;
  final List<(String, int)> shas;
  late final int numDapim = shas.fold(0, (a, b) => a + b.$2);
  YerushalmiYomiConfig(this.ed, this.startAbs, this.skipYK9Av, this.shas);
}

final vilna = YerushalmiYomiConfig('vilna', _g(1980, 2, 2), true, const [
  ('Berakhot', 68), ('Peah', 37), ('Demai', 34), ('Kilayim', 44), ('Sheviit', 31), //
  ('Terumot', 59), ('Maasrot', 26), ('Maaser Sheni', 33), ('Challah', 28), ('Orlah', 20),
  ('Bikkurim', 13), ('Shabbat', 92), ('Eruvin', 65), ('Pesachim', 71), ('Beitzah', 22),
  ('Rosh Hashanah', 22), ('Yoma', 42), ('Sukkah', 26), ('Taanit', 26), ('Shekalim', 33),
  ('Megillah', 34), ('Chagigah', 22), ('Moed Katan', 19), ('Yevamot', 85), ('Ketubot', 72),
  ('Sotah', 47), ('Nedarim', 40), ('Nazir', 47), ('Gittin', 54), ('Kiddushin', 48),
  ('Bava Kamma', 44), ('Bava Metzia', 37), ('Bava Batra', 34), ('Shevuot', 44), ('Makkot', 9),
  ('Sanhedrin', 57), ('Avodah Zarah', 37), ('Horayot', 19), ('Niddah', 13),
]);

final schottenstein = YerushalmiYomiConfig('schottenstein', _g(2022, 11, 14), false, const [
  ('Berakhot', 94), ('Peah', 73), ('Demai', 77), ('Kilayim', 84), ('Sheviit', 87), //
  ('Terumot', 107), ('Maasrot', 46), ('Maaser Sheni', 59), ('Challah', 49), ('Orlah', 42),
  ('Bikkurim', 26), ('Shabbat', 113), ('Eruvin', 71), ('Pesachim', 86), ('Shekalim', 61),
  ('Yoma', 57), ('Sukkah', 33), ('Beitzah', 49), ('Rosh Hashanah', 27), ('Taanit', 31),
  ('Megillah', 41), ('Chagigah', 28), ('Moed Katan', 23), ('Yevamot', 88), ('Ketubot', 77),
  ('Nedarim', 42), ('Nazir', 53), ('Sotah', 52), ('Gittin', 53), ('Kiddushin', 53),
  ('Bava Kamma', 40), ('Bava Metzia', 35), ('Bava Batra', 39), ('Sanhedrin', 75), ('Shevuot', 49),
  ('Avodah Zarah', 34), ('Makkot', 11), ('Horayot', 18), ('Niddah', 11),
]);

class YerushalmiReading {
  final String name;
  final int blatt;
  final String ed;
  const YerushalmiReading(this.name, this.blatt, this.ed);
}

int _tishaBavObservedAbs(int year) {
  var av9dt = HDate(9, Months.av, year);
  if (av9dt.getDay() == 6) av9dt = av9dt.next();
  return av9dt.abs();
}

int _skippedDaysBefore(int abs) {
  final year = HDate.fromAbs(abs).getFullYear();
  var n = 2 * year;
  if (hebrew2abs(year, Months.tishrei, 10) < abs) n++;
  if (_tishaBavObservedAbs(year) < abs) n++;
  return n;
}

int _readingsBefore(YerushalmiYomiConfig config, int cday) {
  final elapsed = cday - config.startAbs;
  if (!config.skipYK9Av) return elapsed;
  return elapsed - (_skippedDaysBefore(cday) - _skippedDaysBefore(config.startAbs));
}

bool _yerushalmiSkipDay(HDate hd) =>
    (hd.getMonth() == Months.tishrei && hd.getDate() == 10) ||
    (hd.getMonth() == Months.av &&
        ((hd.getDate() == 9 && hd.getDay() != 6) || (hd.getDate() == 10 && hd.getDay() == 0)));

YerushalmiReading? yerushalmiYomi(int cday, YerushalmiYomiConfig config) {
  _checkTooEarly(cday, config.startAbs, 'Yerushalmi Yomi');
  if (config.skipYK9Av && _yerushalmiSkipDay(HDate.fromAbs(cday))) return null;
  var total = _readingsBefore(config, cday) % config.numDapim;
  for (final (name, dapim) in config.shas) {
    if (total < dapim) return YerushalmiReading(name, total + 1, config.ed);
    total -= dapim;
  }
  throw StateError('unreachable');
}

class YerushalmiYomiEvent extends DailyLearningEvent {
  final YerushalmiReading daf;
  YerushalmiYomiEvent(HDate date, this.daf)
      : super(date, '${daf.name} ${daf.blatt}', Flags.yerushalmiYomi);
  @override
  String get category => 'Yerushalmi Yomi';
  @override
  String render([String? locale]) => '${Locale.gettext('Yerushalmi', locale)} ${renderBrief(locale)}';
  @override
  String renderBrief([String? locale]) {
    final name = Locale.gettext(daf.name, locale);
    if (Locale.isHebrewLocale(locale)) return '$name דף ${gematriyaNN(daf.blatt)}';
    return '$name ${daf.blatt}';
  }

  @override
  String? url() {
    if (daf.ed != 'vilna') return null;
    final pageMap = data.yerushalmiVilnaMapJson[daf.name];
    if (pageMap == null || daf.blatt - 1 >= pageMap.length) return null;
    final verses0 = pageMap[daf.blatt - 1];
    if (verses0 is! String) return null;
    return sefariaUrl('Jerusalem Talmud ${daf.name}', verses0.replaceAll(':', '.'));
  }

  @override
  List<String> getCategories() => ['yerushalmi', daf.ed];
}

// ------------------------------------------------------------------ Psalms

const List<List<Object>> _psalmsSchedule = [
  [0, 0], [1, 9], [10, 17], [18, 22], [23, 28], [29, 34], [35, 38], [39, 43], //
  [44, 48], [49, 54], [55, 59], [60, 65], [66, 68], [69, 71], [72, 76], [77, 78],
  [79, 82], [83, 87], [88, 89], [90, 96], [97, 103], [104, 105], [106, 107],
  [108, 112], [113, 118], ['119:1', '119:96'], ['119:97', '119:176'], [120, 134],
  [135, 139], [140, 144], [145, 150],
];

List<Object> dailyPsalms(HDate hd) {
  final dd = hd.getDate();
  if (dd == 29 && hd.daysInMonth() == 29) return const [140, 150];
  return _psalmsSchedule[dd];
}

class PsalmsEvent extends DailyLearningEvent {
  final List<Object> reading;
  PsalmsEvent(HDate date, this.reading) : super(date, 'Psalms ${reading[0]}-${reading[1]}');
  @override
  String get category => 'Psalms';
  @override
  String render([String? locale]) {
    final book = Locale.gettext('Psalms', locale);
    if (Locale.isHebrewLocale(locale) && reading[0] is int) {
      return '$book ${gematriya(reading[0])}-${gematriya(reading[1])}';
    }
    return '$book ${reading[0]}-${reading[1]}';
  }

  @override
  String url() => sefariaUrl('Psalms', '${reading[0]}-${reading[1]}'.replaceAll(':', '.'));
  @override
  List<String> getCategories() => const ['dailyPsalms'];
}

// ------------------------------------------------------------------ Rambam

class RambamReading {
  final String name;
  Object perek;
  RambamReading(this.name, this.perek);
}

const rambam1cycleLen = 1017;
final int rambam1Start = _g(1984, 4, 29);
final List<(String, int)> _mishnehTorah1 = [
  for (final e in data.mishnehTorahJson.entries) (e.key, e.value),
];
const _first4verses = [
  ['1-21', '22-33', '34-45'],
  ['1-83', '84-166', '167-248'],
  ['1-122', '123-245', '246-365'],
  ['1:1-4:8', '5:1-9:9', '10:1-14:10'],
];

RambamReading _getChap(int idx, List<(String, int)> mt) {
  var total = idx;
  for (var j = 0; j < mt.length; j++) {
    if (total < mt[j].$2) {
      final chapNum = total + 1;
      return RambamReading(mt[j].$1, j < 4 ? _first4verses[j][chapNum - 1] : chapNum);
    }
    total -= mt[j].$2;
  }
  throw StateError('unreachable');
}

RambamReading dailyRambam1(int cday) {
  _checkTooEarly(cday, rambam1Start, 'Daily Rambam 1');
  final reading = _getChap((cday - rambam1Start) % rambam1cycleLen, _mishnehTorah1);
  if (reading.name == 'The Order of Prayer' && reading.perek == 4) reading.perek = '4-5';
  return reading;
}

final List<(String, int)> _mishnehTorah3 = () {
  final l = List.of(_mishnehTorah1);
  l[15] = (l[15].$1, 5);
  l[20] = (l[20].$1, 8);
  return l;
}();

List<RambamReading> dailyRambam3(int cday) {
  _checkTooEarly(cday, rambam1Start, 'Daily Rambam 3');
  final dno = (cday - rambam1Start) % (rambam1cycleLen ~/ 3);
  final idx = dno * 3;
  final r1 = _getChap(idx, _mishnehTorah3);
  if (r1.name == 'Leavened and Unleavened Bread' && r1.perek == 8) r1.perek = '8-9';
  return [r1, _getChap(idx + 1, _mishnehTorah3), _getChap(idx + 2, _mishnehTorah3)];
}

class DailyRambamEvent extends DailyLearningEvent {
  final RambamReading reading;
  DailyRambamEvent(HDate date, this.reading) : super(date, '${reading.name} ${reading.perek}');
  @override
  String get category => 'Daily Rambam';
  @override
  String render([String? locale]) {
    final name = Locale.gettext(reading.name, locale);
    if (Locale.isHebrewLocale(locale)) {
      final perekStr = reading.perek is int ? gematriyaNN(reading.perek) : '${reading.perek}';
      return '$name פרק $perekStr';
    }
    return '$name ${reading.perek}';
  }

  @override
  String url() {
    final name = 'Mishneh Torah, ${reading.name}.${reading.perek}';
    return 'https://www.sefaria.org/${Uri.encodeComponent(name.replaceAll(' ', '_').replaceAll(':', '.'))}?lang=bi';
  }

  @override
  List<String> getCategories() => const ['dailyRambam1'];
}

RambamReading _combinePair(RambamReading r1, RambamReading r2) {
  final perek0 = r1.perek;
  final perek2 = '${r2.perek}';
  if (perek0 is int) return RambamReading(r1.name, '$perek0-$perek2');
  final first = '$perek0'.split('-');
  final last = perek2.split('-');
  return RambamReading(r1.name, '${first[0]}-${last.length > 1 ? last[1] : last[0]}');
}

List<RambamReading> _collapseAdjacent(List<RambamReading> r) {
  if (r[0].name == r[1].name && r[1].name == r[2].name) return [_combinePair(r[0], r[2])];
  if (r[0].name == r[1].name) return [_combinePair(r[0], r[1]), r[2]];
  if (r[1].name == r[2].name) return [r[0], _combinePair(r[1], r[2])];
  return r;
}

class DailyRambam3Event extends DailyLearningEvent {
  final List<RambamReading> readings;
  final List<DailyRambamEvent> events;
  DailyRambam3Event._(HDate date, this.readings)
      : events = readings.map((r) => DailyRambamEvent(date, r)).toList(),
        super(date, readings.map((r) => '${r.name} ${r.perek}').join(', '));
  factory DailyRambam3Event(HDate date, List<RambamReading> readings) =>
      DailyRambam3Event._(date, _collapseAdjacent(readings));
  @override
  String get category => 'Daily Rambam';
  @override
  String render([String? locale]) => events.map((ev) => ev.render(locale)).join(', ');
  @override
  String? url() => events.length == 1 ? events[0].url() : null;
  @override
  List<String> getCategories() => const ['dailyRambam3'];
}

// ------------------------------------------------------------------ Pirkei Avot

/// Pirkei Avot chapter(s) read on a summer Shabbat, or null.
List<int>? pirkeiAvot(HDate hd, bool il) {
  if (hd.getDay() != 6) return null;
  final hyear = hd.getFullYear();
  final pesach7 = HDate(21, Months.nisan, hyear);
  if (hd.abs() <= pesach7.abs()) return null;
  final first = pesach7.after(6);
  var weekDiff = (hd.deltaDays(first) / 7).ceil();
  final holidays = <HDate>[
    if (!il) ...[pesach7.next(), HDate(7, Months.sivan, hyear)],
  ];
  final av8 = HDate(8, Months.av, hyear);
  holidays.addAll([av8, av8.next()]);
  for (final day in holidays) {
    if (day.isSameDate(hd)) return null;
    if (day.deltaDays(hd) <= 0 && day.getDay() == 6) weekDiff -= 1;
  }
  if (weekDiff < 0) return null;
  if (weekDiff < 18) return [(weekDiff % 6) + 1];
  final rh = HDate(1, Months.tishrei, hyear + 1);
  final last = rh.before(6);
  final weeksRemain = (last.deltaDays(hd) / 7).ceil();
  switch (weeksRemain) {
    case 0:
      return [5, 6];
    case 1:
      return [3, 4];
    case 2:
      return weekDiff % 6 == 1 ? [2] : [1, 2];
    case 3:
      return [1];
  }
  return null;
}

class PirkeiAvotSummerEvent extends DailyLearningEvent {
  final List<int> reading;
  PirkeiAvotSummerEvent(HDate date, this.reading) : super(date, 'Pirkei Avot ${reading.join('-')}');
  @override
  String get category => 'Pirkei Avot';
  @override
  String render([String? locale]) {
    final book = Locale.gettext('Pirkei Avot', locale);
    if (Locale.isHebrewLocale(locale)) return '$book ${reading.map(gematriya).join('-')}';
    return '$book ${reading.join('-')}';
  }

  @override
  String url() => sefariaUrl('Pirkei Avot', reading.join('-'));
  @override
  List<String> getCategories() => const ['pirkeiAvotSummer'];
}

// ------------------------------------------------------------------ Chofetz Chaim

final int chofetzChaimStart = HDate(1, Months.tishrei, 5634).abs();

const Map<String, String> _ccEnglishNames = {
  'Hakdamah': 'Preface',
  'Psichah': 'Introduction to the Laws of the Prohibition of Lashon Hara and Rechilut, Opening Comments',
  'Lavin': 'Introduction to the Laws of the Prohibition of Lashon Hara and Rechilut, Negative Commandments',
  'Asin': 'Introduction to the Laws of the Prohibition of Lashon Hara and Rechilut, Positive Commandments',
  'Arurin': 'Introduction to the Laws of the Prohibition of Lashon Hara and Rechilut, Curses',
  'HilchosLH': 'Part One, The Prohibition Against Lashon Hara',
  'HilchosRechilus': 'Part Two, The Prohibition Against Rechilut',
  'Tziyurim': 'Illustrations',
};

class ChofetzChaimReading {
  String k;
  Object? b;
  Object? e;
  String? textBegin;
  String? textEnd;
  ChofetzChaimReading(this.k, this.b, this.e, [this.textBegin, this.textEnd]);
}

ChofetzChaimReading _ccLookup(List<List<Object?>> readings, int day, int month) {
  var k = '';
  Object? b;
  Object? e;
  String? textBegin;
  String? textEnd;
  for (final reading in readings) {
    final dates = (reading[0] as List).cast<int>();
    for (var i = 0; i < dates.length; i += 2) {
      if (dates[i] == day && dates[i + 1] == month) {
        if (k.isEmpty) {
          k = reading[1] as String;
          b = reading.length > 2 ? reading[2] : null;
          if (reading.length > 4 && reading[4] is String) textBegin = reading[4] as String;
        }
        if (e is List) {
          e = e.last;
        } else {
          e = reading.length > 3 ? reading[3] : null;
        }
        if (reading.length > 5 && reading[5] is String) textEnd = reading[5] as String;
      }
    }
  }
  return ChofetzChaimReading(k, b, e, textBegin, textEnd);
}

ChofetzChaimReading chofetzChaim(HDate hdate) {
  if (hdate.abs() < chofetzChaimStart) {
    throw RangeError('Date $hdate too early; Sefer Chofetz Chaim cycle began on 1 Tishrei 5634');
  }
  final readings = hdate.isLeapYear() ? tables.chofetzChaimLeap : tables.chofetzChaimSimple;
  final day = hdate.getDate();
  final month = hdate.getMonth();
  final result = _ccLookup(readings, day, month);
  final year = hdate.getFullYear();
  if (day == 29 &&
      ((month == Months.kislev && shortKislev(year)) ||
          (month == Months.cheshvan && !longCheshvan(year)))) {
    result.e = _ccLookup(readings, 30, month).e;
  }
  return result;
}

String _formatReadingPages(Object? b, Object? e) {
  var str = '';
  if (b != null) {
    str += ' ${_jsNum(b)}';
    if (e is List) {
      str += ', ${e.map((x) => _jsNum(x as Object)).join(', ')}';
    } else if (e != null && _jsNum(e) != _jsNum(b)) {
      str += '-${_jsNum(e)}';
    }
  }
  return str;
}

class ChofetzChaimEvent extends DailyLearningEvent {
  final ChofetzChaimReading reading;
  ChofetzChaimEvent(HDate date, this.reading)
      : super(date, reading.k + _formatReadingPages(reading.b, reading.e)) {
    memo = render('memo');
  }
  @override
  String get category => 'Chofetz Chaim';
  @override
  String renderBrief([String? locale]) {
    final book = reading.k;
    final name = locale == 'memo'
        ? (_ccEnglishNames[book] ?? book)
        : Locale.gettext(book.replaceFirst('Hilchos', 'Hilchos '), locale);
    return name + _formatReadingPages(reading.b, reading.e);
  }

  @override
  String render([String? locale]) {
    final str = renderBrief(locale);
    if (reading.textBegin != null) return '$str ${reading.textBegin} - ${reading.textEnd}';
    return str;
  }

  @override
  String url() {
    final book = reading.k;
    var name = 'Chofetz Chaim, ${_ccEnglishNames[book]}';
    var separator = '.';
    if (book == 'HilchosLH' || book == 'HilchosRechilus') {
      name += ', Principle';
      separator = '_';
    } else if (book == 'Tziyurim') {
      name += ', Illustration';
      separator = '_';
    }
    if (reading.b != null) name += separator + _jsNum(reading.b!);
    return 'https://www.sefaria.org/${Uri.encodeComponent(name.replaceAll(' ', '_'))}?lang=bi';
  }

  @override
  List<String> getCategories() => const ['chofetzChaim'];
}

// ------------------------------------------------------------------ Shemirat HaLashon

final int shemiratHaLashonStart = HDate(21, Months.shvat, 5636).abs();

const Map<String, String?> _shlEnglishNames = {
  'Hakdamah': 'Introduction',
  'Shar_Hazechira': 'The Gate of Remembering',
  'Shar_Hatvuna': 'The Gate of Discerning',
  'Shar_Hatorah': 'The Gate of Torah',
  'Chasimas_Hasefer': 'Epilogue',
  'x': null,
};

class ShemiratHaLashonReading {
  final int bk;
  final String k;
  final Object b;
  Object e;
  ShemiratHaLashonReading(this.bk, this.k, this.b, this.e);
}

ShemiratHaLashonReading _shlLookup(int day, int month, bool isLeap) {
  var bk = 0;
  var k = '';
  Object b = 0;
  Object e = 0;
  for (final reading in tables.shemiratHaLashonSchedule) {
    final dates = (reading[isLeap ? 1 : 0] as List).cast<int>();
    if (dates[0] == day && dates[1] == month) {
      if (k.isEmpty) {
        bk = reading[2] as int;
        k = reading[3] as String;
        b = reading[4]!;
      }
      e = (reading.length > 5 ? reading[5] : null) ?? reading[4]!;
    }
  }
  return ShemiratHaLashonReading(bk, k, b, e);
}

ShemiratHaLashonReading shemiratHaLashon(HDate hdate) {
  if (hdate.abs() < shemiratHaLashonStart) {
    throw RangeError('Date $hdate too early; Sefer Shemirat HaLashon cycle began on 21 Sh\'vat 5636');
  }
  final day = hdate.getDate();
  final month = hdate.getMonth();
  final result = _shlLookup(day, month, hdate.isLeapYear());
  final year = hdate.getFullYear();
  if (day == 29 &&
      ((month == Months.kislev && shortKislev(year)) ||
          (month == Months.cheshvan && !longCheshvan(year)))) {
    result.e = _shlLookup(30, month, hdate.isLeapYear()).e;
  }
  return result;
}

class ShemiratHaLashonEvent extends DailyLearningEvent {
  final ShemiratHaLashonReading reading;
  ShemiratHaLashonEvent(HDate date, this.reading)
      : super(
            date,
            (reading.bk == 1 ? 'Book I' : 'Book II') +
                (reading.k == 'x' ? '' : ', ${reading.k}') +
                _formatReadingPages(reading.b, reading.e)) {
    memo = render('memo');
  }
  @override
  String get category => 'Shemirat HaLashon';
  @override
  String render([String? locale]) => renderPrefix(locale) + _formatReadingPages(reading.b, reading.e);

  String renderPrefix([String? locale]) {
    final book = reading.bk == 1 ? 'Book I' : 'Book II';
    final section = locale == 'memo'
        ? _shlEnglishNames[reading.k.replaceAll(' ', '_')]
        : reading.k == 'x'
            ? null
            : Locale.gettext(reading.k, locale);
    return section != null ? '$book, $section' : book;
  }

  @override
  String url() => sefariaUrl('Shemirat HaLashon, ${renderPrefix('memo')}', _jsNum(reading.b));
  @override
  List<String> getCategories() => const ['shemiratHaLashon'];
}

// ------------------------------------------------------------------ Sefer HaMitzvot

final int seferHaMitzvotStart = _g(1984, 4, 29);
const Map<int, List<int>> _shmNotes = {
  140: [148, 149, 161],
  161: [149, 148, 140],
  258: [296, 295, 259],
  259: [295, 296, 258],
};

class SeferHaMitzvotReading {
  final int day;
  final String reading;
  final String? note;
  const SeferHaMitzvotReading(this.day, this.reading, [this.note]);
}

SeferHaMitzvotReading seferHaMitzvot(int cday) {
  _checkTooEarly(cday, seferHaMitzvotStart, 'Sefer Hamitzvot');
  final list = data.seferHaMitzvotJson;
  final day0 = (cday - seferHaMitzvotStart) % list.length;
  final day = day0 + 1;
  final arr = _shmNotes[day];
  final note = arr == null
      ? null
      : 'In some editions of the Sefer Hamitzvot Schedule, today’s Sefer Hamitzvot (Day $day) has Negative Mitzvah ${arr[0]} listed instead of Negative Mitzvah ${arr[1]} (and Day ${arr[2]} has Negative Mitzvah ${arr[1]} instead of ${arr[0]})';
  return SeferHaMitzvotReading(day, list[day0], note);
}

class SeferHaMitzvotEvent extends DailyLearningEvent {
  final SeferHaMitzvotReading reading;
  SeferHaMitzvotEvent(HDate date, this.reading) : super(date, 'Day ${reading.day}: ${reading.reading}') {
    memo = reading.note;
  }
  @override
  String get category => 'Sefer Hamitzvot';
  @override
  String render([String? locale]) {
    var prev = 0;
    var str = '';
    for (final part in reading.reading.split(', ')) {
      final ch = part.isEmpty ? '' : part[0];
      final isNumber = part.length > 1 && part.codeUnitAt(1) >= 48 && part.codeUnitAt(1) <= 57;
      final type = ch == 'P' && isNumber
          ? 1
          : ch == 'N' && isNumber
              ? 2
              : 0;
      final suffix = part.length > 1 ? part.substring(1) : '';
      if (type == prev && type != 0) {
        str += ', $suffix';
      } else if (type != 0) {
        str += '; ${type == 1 ? 'Positive' : 'Negative'} Commandment $suffix';
      } else {
        str += '; $part';
      }
      prev = type;
    }
    if (reading.note != null) str += '; Note About Varying Customs';
    return 'Day ${reading.day}: ${str.substring(2)}';
  }

  @override
  String renderBrief([String? locale]) => getDesc();
  @override
  String url() {
    final dt = date.greg();
    return 'https://www.chabad.org/dailystudy/seferHamitzvos.asp?tdate=${dt.month}/${dt.day}/${dt.year}';
  }

  @override
  List<String> getCategories() => const ['seferHaMitzvot'];
}

// ------------------------------------------------------------------ Kitzur SA

class KitzurShulchanAruchReading {
  final String b;
  final String? e;
  const KitzurShulchanAruchReading(this.b, this.e);
}

KitzurShulchanAruchReading? kitzurShulchanAruch(HDate hd, [String leapOption = 'A']) {
  final dd = hd.getDate();
  final mm = hd.getMonth();
  if (dd == 30 && (mm == Months.adarI || mm == Months.cheshvan)) return null;
  final monthName = hd.isLeapYear() && mm == Months.adarII
      ? 'Leap Option $leapOption'
      : mm == Months.adarI
          ? 'Adar'
          : hd.getMonthName();
  final list = data.kitzurSaJson[monthName];
  if (list == null || dd - 1 >= list.length) {
    throw StateError('No reading found for $hd');
  }
  final parts = (list[dd - 1] as String).split('-');
  return KitzurShulchanAruchReading(parts[0], parts.length > 1 ? parts[1] : null);
}

String _gematriyaOrSof(String s) => s == 'E' ? 'סוף' : gematriyaNN(s);

String _renderKitzur(KitzurShulchanAruchReading reading, [String? locale]) {
  if (Locale.isHebrewLocale(locale)) {
    if (reading.b == 'Klalim') return Locale.gettext(reading.b, locale);
    final cv1 = reading.b.split(':');
    final begin = cv1.map((s) => s == 'Shmita' ? 'שמיטה' : gematriyaNN(s)).join(':');
    if (reading.e != null) {
      final end = reading.e!.split(':');
      final chap = _gematriyaOrSof(end[0]);
      if (end.length < 2 || end[1].isEmpty) return '$begin-$chap';
      final verse = _gematriyaOrSof(end[1]);
      final chapColon = end[0] == cv1[0] ? '' : '$chap:';
      return '$begin-$chapColon$verse';
    }
    return begin;
  }
  return reading.e != null ? formatBeginEndRange(reading.b, reading.e!) : reading.b;
}

class KitzurShulchanAruchEvent extends DailyLearningEvent {
  final KitzurShulchanAruchReading reading;
  final KitzurShulchanAruchReading? optionB;
  final bool leapAdar2;
  KitzurShulchanAruchEvent(HDate date, this.reading, [this.optionB])
      : leapAdar2 = date.isLeapYear() && date.getMonth() == Months.adarII,
        super(
            date,
            reading.b +
                (reading.e != null ? '-${reading.e}' : '') +
                (optionB != null ? ' / ${optionB.b}-${optionB.e}' : ''));
  @override
  String get category => 'Kitzur Shulchan Arukh';
  @override
  String render([String? locale]) =>
      (leapAdar2 ? '' : '${Locale.gettext('Kitzur Shulchan Arukh', locale)} ') + renderBrief(locale);
  @override
  String renderBrief([String? locale]) {
    var str = '';
    if (leapAdar2) str += "${Locale.gettext("Hilchot Shmita v'Terumah", locale)} ";
    str += _renderKitzur(reading, locale);
    if (optionB != null) {
      str += " / ${Locale.gettext("Hilchot Brachot v'Tefilah", locale)} ${_renderKitzur(optionB!, locale)}";
    }
    return str;
  }

  @override
  String? url() {
    if (leapAdar2) return null;
    const prefix = 'https://www.sefaria.org/Kitzur_Shulchan_Arukh';
    if (reading.e == null || reading.e!.endsWith(':E')) {
      return '$prefix.${reading.b.replaceFirst(':', '.')}?lang=bi';
    }
    return '$prefix.${formatBeginEndRange(reading.b, reading.e!).replaceFirst(':', '.')}?lang=bi';
  }

  @override
  List<String> getCategories() => const ['kitzurShulchanAruch'];
}

// ------------------------------------------------------------------ Arukh HaShulchan

final int ahsyStart = _g(2020, 5, 29);
const _ahsSections = ['', 'Orach Chaim', "Yoreh De'ah", 'Even HaEzer', 'Choshen Mishpat'];

(String, String) arukhHaShulchanYomi(int cday) {
  _checkTooEarly(cday, ahsyStart, 'Arukh HaShulchan Yomi');
  final list = data.arukhHaShulchanYomiJson;
  final entry = list[(cday - ahsyStart) % list.length];
  return (_ahsSections[entry[0] as int], entry[1] as String);
}

class ArukhHaShulchanYomiEvent extends DailyLearningEvent {
  final (String, String) reading;
  ArukhHaShulchanYomiEvent(HDate date, this.reading) : super(date, '${reading.$1} ${reading.$2}');
  @override
  String get category => 'Arukh HaShulchan Yomi';
  @override
  String render([String? locale]) {
    final name = Locale.gettext(reading.$1, locale);
    if (Locale.isHebrewLocale(locale)) {
      final beginEnd = reading.$2
          .split('-')
          .map((x) => x.split('.').map(gematriyaNN).join(':'));
      return '$name ${beginEnd.join('-')}';
    }
    return '$name ${reading.$2.replaceAll('.', ':')}';
  }

  @override
  String url() => sefariaUrl('Arukh HaShulchan, ${reading.$1}', reading.$2);
  @override
  List<String> getCategories() => const ['arukhHaShulchanYomi'];
}

// ------------------------------------------------------------------ Tanakh Yomi

final int tanakhYomiStart = _g(1948, 10, 26);
const _joshua = 'Joshua';
const _jeremiah = 'Jeremiah';
const _ruth = 'Ruth';
const _shirHashirim = 'Song of Songs';
const List<(String, int)> _tanakhBooks = [
  (_joshua, 14), ('Judges', 14), ('Samuel', 34), ('Kings', 35), ('Isaiah', 26), //
  (_jeremiah, 31), ('Ezekiel', 29), ('Minor Prophets', 21), ('Psalms', 19), ('Proverbs', 8),
  ('Job', 8), (_shirHashirim, 1), (_ruth, 1), ('Lamentations', 1), ('Ecclesiastes', 4),
  ('Esther', 5), ('Daniel', 7), ('Ezra and Nehemiah', 10), ('Chronicles', 25), ('Chronicles', 25),
];
const _tanakhToSkip = {'Purim', "Yom HaAtzma'ut", "Tish'a B'Av", "Tish'a B'Av (observed)"};

bool _tanakhSkipDay(HDate hd) {
  if (hd.getDay() == 6) return true;
  for (final ev in getHolidaysOnDate(hd, true)) {
    if (ev.hasFlag(Flags.chag) || _tanakhToSkip.contains(ev.getDesc())) return true;
  }
  return false;
}

final Map<int, (int, List<int>)> _tanakhYearCache = {};

(int, List<int>) _yearReadingDays(int year) => _tanakhYearCache.putIfAbsent(year, () {
      final rh = hebrew2abs(year, Months.tishrei, 1);
      final len = hebrew2abs(year + 1, Months.tishrei, 1) - rh;
      final prefix = List<int>.filled(len + 1, 0);
      var count = 0;
      for (var i = 0; i < len; i++) {
        prefix[i] = count;
        if (!_tanakhSkipDay(HDate.fromAbs(rh + i))) count++;
      }
      prefix[len] = count;
      return (rh, prefix);
    });

int _countReadingDays(int startAbs, int endAbs) {
  var count = 0;
  var abs = startAbs;
  while (abs < endAbs) {
    final (rh, prefix) = _yearReadingDays(HDate.fromAbs(abs).getFullYear());
    final len = prefix.length - 1;
    final stop = endAbs < rh + len ? endAbs : rh + len;
    count += prefix[stop - rh] - prefix[abs - rh];
    abs = stop;
  }
  return count;
}

class _ReadingsForYear {
  final List<(String, int)> table;
  bool longRuth = false, longShirHaShirim = false, longJeremiah = false, longJoshua = false;
  _ReadingsForYear(this.table);
}

_ReadingsForYear _buildReadingTable(int year) {
  final numDays = _countReadingDays(
      hebrew2abs(year, Months.tishrei, 23), hebrew2abs(year + 1, Months.tishrei, 22) + 1);
  final count = isLeapYear(year) ? numDays - 25 : numDays;
  final extra = count - 293;
  final result = _ReadingsForYear(List.of(_tanakhBooks));
  final t = result.table;
  if (extra < 0 || extra > 4) throw StateError('$year => $numDays $count $extra');
  if (extra >= 4) {
    t[0] = (_joshua, 15);
    result.longJoshua = true;
  }
  if (extra >= 3) {
    t[5] = (_jeremiah, 32);
    result.longJeremiah = true;
  }
  if (extra >= 2) {
    t[11] = (_shirHashirim, 2);
    result.longShirHaShirim = true;
  }
  if (extra >= 1) {
    t[12] = (_ruth, 2);
    result.longRuth = true;
  }
  return result;
}

final Map<int, _ReadingsForYear> _readingTableCache = {};

/// A seder of Tanakh Yomi.
class TanakhYomi extends DafPage {
  late final String verses;
  TanakhYomi(super.name, super.blatt) {
    final String? v = blatt is int
        ? (data.masoreticJson['regular'] as Map)[name][(blatt as int) - 1] as String?
        : ((data.masoreticJson['split'] as Map)[name] as Map?)?[blatt] as String?;
    if (v == null) throw StateError('$name $blatt');
    final ch = v.codeUnitAt(0);
    verses = ch >= 48 && ch <= 57 ? '$name $v' : v;
  }

  @override
  String render([String? locale]) {
    final n = Locale.gettext(name, locale);
    if (Locale.isHebrewLocale(locale)) {
      final prefix = '$n ס׳ ';
      if (blatt is String) {
        final s = blatt as String;
        return prefix + gematriyaNN(int.parse(s[0])) + s[2];
      }
      return prefix + gematriyaNN(blatt);
    }
    return '$n Seder $blatt';
  }
}

TanakhYomi? tanakhYomi(HDate hd) {
  if (_tanakhSkipDay(hd)) return null;
  final cday = hd.abs();
  _checkTooEarly(cday, tanakhYomiStart, 'Tanakh Yomi');
  final hyear = hd.getFullYear();
  final rh = hebrew2abs(hyear, Months.tishrei, 1);
  final startAbs = rh + 22;
  if (cday < startAbs) {
    final rhDow = rh % 7;
    var blatt = rhDow == 4
        ? 11
        : rhDow == 6
            ? 10
            : 12;
    blatt += _countReadingDays(rh + 2, cday);
    return TanakhYomi('Chronicles', blatt);
  }
  var total = _countReadingDays(startAbs, cday);
  final rt = _readingTableCache.putIfAbsent(hyear, () => _buildReadingTable(hyear));
  for (final (name, count) in rt.table) {
    if (total < count) {
      final blatt = total + 1;
      if ((rt.longShirHaShirim && name == _shirHashirim) || (rt.longRuth && name == _ruth)) {
        return TanakhYomi(name, '1.$blatt');
      }
      if (rt.longJoshua && name == _joshua && blatt >= 4) {
        if (blatt == 4) return TanakhYomi(name, '4.1');
        if (blatt == 5) return TanakhYomi(name, '4.2');
        return TanakhYomi(name, blatt - 1);
      }
      if (rt.longJeremiah && name == _jeremiah && blatt >= 9) {
        if (blatt == 9) return TanakhYomi(name, '9.1');
        if (blatt == 10) return TanakhYomi(name, '9.2');
        return TanakhYomi(name, blatt - 1);
      }
      return TanakhYomi(name, blatt);
    }
    total -= count;
  }
  throw StateError('Internal error with $hd');
}

class TanakhYomiEvent extends DafPageEvent {
  TanakhYomiEvent(HDate date, TanakhYomi daf) : super(date, daf, Flags.dailyLearning) {
    memo = daf.verses;
  }
  @override
  String get category => 'Tanakh Yomi';
  @override
  String url() {
    final space = memo!.lastIndexOf(' ');
    return sefariaUrl(memo!.substring(0, space), memo!.substring(space + 1).replaceAll(':', '.'));
  }

  @override
  List<String> getCategories() => const ['tanakhYomi'];
}

// ------------------------------------------------------------------ 929

final int nine29Start = _g(2014, 12, 21);
final int _nine29EndCycle1 = _g(2018, 4, 18);
final int _nine29StartCycle2 = _g(2018, 7, 15);
const _lastChapterOffset = 1298;
const _cycleDays = _lastChapterOffset + 4;

class Nine29Reading {
  final int cycleChap;
  final int cycleNum;
  final String book;
  final int bookChap;
  const Nine29Reading(this.cycleChap, this.cycleNum, this.book, this.bookChap);
}

Nine29Reading? calculate929(int abs) {
  _checkTooEarly(abs, nine29Start, '929');
  int cycleNumber;
  int cycleStart;
  if (abs < _nine29StartCycle2) {
    cycleNumber = 1;
    cycleStart = nine29Start;
  } else {
    final elapsed = (abs - _nine29StartCycle2) ~/ _cycleDays;
    cycleNumber = 2 + elapsed;
    cycleStart = _nine29StartCycle2 + elapsed * _cycleDays;
  }
  final dow = abs % 7;
  if (dow == 5 || dow == 6) return null;
  final effectiveEnd = cycleNumber == 1 ? _nine29EndCycle1 : cycleStart + _lastChapterOffset;
  if (abs > effectiveEnd) return null;
  final days = abs - cycleStart;
  final chapterNum = (days ~/ 7) * 5 + (days % 7 < 5 ? days % 7 : 5) + 1;
  var remaining = chapterNum;
  for (final e in data.tanakhNumChapJson.entries) {
    final n = e.value;
    if (remaining <= n) return Nine29Reading(chapterNum, cycleNumber, e.key, remaining);
    remaining -= n;
  }
  throw StateError('Chap $chapterNum out of range');
}

class Nine29Event extends DailyLearningEvent {
  final Nine29Reading reading;
  Nine29Event(HDate date, this.reading)
      : super(date, '${reading.book} ${reading.bookChap} (${reading.cycleChap})');
  @override
  String get category => '929';
  @override
  String render([String? locale]) => '${renderBrief(locale)} (${reading.cycleChap})';
  @override
  String renderBrief([String? locale]) {
    final bookName = Locale.gettext(reading.book, locale);
    final chapStr = Locale.isHebrewLocale(locale) ? gematriya(reading.bookChap) : '${reading.bookChap}';
    return '$bookName $chapStr';
  }

  @override
  String url() => sefariaUrl(reading.book, reading.bookChap);
  @override
  List<String> getCategories() => const ['929'];
}

// ------------------------------------------------------------------ Dirshu

final int dirshuAmudYomiStart = _g(2023, 10, 16);
final List<(String, int)> _amudShas = [
  for (final e in data.amudimJson.entries) (e.key, e.value),
];
final int _totalAmudim = _amudShas.fold(0, (s, a) => s + a.$2);

class DirshuAmudYomi {
  final String name;
  final int amud;
  final String side;
  const DirshuAmudYomi(this.name, this.amud, this.side);
}

DirshuAmudYomi calculateDirshuAmud(int cday) {
  _checkTooEarly(cday, dirshuAmudYomiStart, 'Dirshu Amud HaYomi');
  final dno = (cday - dirshuAmudYomiStart) % _totalAmudim;
  var total = 0;
  for (final (name, amudim) in _amudShas) {
    if (dno < total + amudim) {
      final idx = dno - total;
      return DirshuAmudYomi(name, 2 + idx ~/ 2, idx % 2 == 0 ? 'a' : 'b');
    }
    total += amudim;
  }
  throw StateError('Dirshu Amud HaYomi calculation failed');
}

class DirshuAmudYomiEvent extends DailyLearningEvent {
  final DirshuAmudYomi amud;
  DirshuAmudYomiEvent._(HDate date, this.amud) : super(date, '${amud.name} ${amud.amud}${amud.side}');
  factory DirshuAmudYomiEvent(HDate date) => DirshuAmudYomiEvent._(date, calculateDirshuAmud(date.abs()));
  @override
  String get category => 'Dirshu Amud HaYomi';
  @override
  String render([String? locale]) {
    final name = Locale.gettext(amud.name, locale);
    final amudStr = Locale.isHebrewLocale(locale)
        ? '$name דף ${gematriya(amud.amud)} ${amud.side == 'a' ? 'ע״א' : 'ע״ב'}'
        : '$name ${amud.amud}${amud.side}';
    return '${Locale.gettext('Dirshu Amud HaYomi', locale)}: $amudStr';
  }

  @override
  String renderBrief([String? locale]) {
    final name = Locale.gettext(amud.name, locale);
    if (Locale.isHebrewLocale(locale)) {
      return '$name ${gematriya(amud.amud)} ${amud.side == 'a' ? 'א' : 'ב'}';
    }
    return '$name ${amud.amud}${amud.side}';
  }

  @override
  String? url() {
    if (amud.name == 'Shekalim') {
      final entry = data.shekalimDafYomiMapJson['${amud.amud}${amud.side}'];
      if (entry == null) return null;
      return sefariaUrl('Jerusalem Talmud Shekalim', entry.replaceAll(':', '.'));
    }
    return sefariaUrl(_dafYomiSefaria[amud.name] ?? amud.name, '${amud.amud}${amud.side}');
  }

  @override
  List<String> getCategories() => const ['dirshuAmudYomi'];
}

final int dirshuDafHalachaStart = _g(2022, 2, 20);
final List<String> _dhReadings =
    ((data.dirshuDafHalachaJson['readings'] as List)).cast<String>();
final int _dhAmudFrom = ((data.dirshuDafHalachaJson['amud'] as Map)['from'] as int);
final List<int> _dhAmudVolumes =
    (((data.dirshuDafHalachaJson['amud'] as Map)['volumes'] as List)).cast<int>();
final List<(int, int)> _dhAmudExtra = [
  for (final e in (((data.dirshuDafHalachaJson['amud'] as Map)['extra'] as Map)).entries)
    (int.parse(e.key as String), e.value as int),
];
final int _dhWeek0 = dirshuDafHalachaStart - (dirshuDafHalachaStart % 7);
final int _dhStartOrdinal = dirshuDafHalachaStart - _dhWeek0;

int _dhOrdinal(int abs) {
  final n = abs - _dhWeek0;
  final week = n ~/ 7;
  return week * 5 + (n - week * 7);
}

class DirshuDafHalacha {
  final String b;
  final String? e;
  final bool review;
  final int? daf;
  final String? side;
  const DirshuDafHalacha(this.b, this.e, this.review, [this.daf, this.side]);
}

(String, String?) _splitReading(String str) {
  final idx = str.indexOf('-');
  return idx == -1 ? (str, null) : (str.substring(0, idx), str.substring(idx + 1));
}

DirshuDafHalacha? dirshuDafHalacha(int cday) {
  _checkTooEarly(cday, dirshuDafHalachaStart, "Daf HaYomi B'Halacha");
  final dow = cday % 7;
  if (dow < 5) {
    final idx = _dhOrdinal(cday) - _dhStartOrdinal;
    if (idx >= _dhReadings.length) return null;
    final (b, e) = _splitReading(_dhReadings[idx]);
    if (idx < _dhAmudFrom) return DirshuDafHalacha(b, e, false);
    var volStart = _dhAmudVolumes[0];
    for (final v in _dhAmudVolumes) {
      if (v > idx) break;
      volStart = v;
    }
    var n = idx - volStart;
    for (final (at, count) in _dhAmudExtra) {
      if (at >= volStart && at < idx) n += count;
    }
    return DirshuDafHalacha(b, e, false, 2 + n ~/ 2, n % 2 == 0 ? 'a' : 'b');
  }
  final first = _dhOrdinal(cday - dow) - _dhStartOrdinal;
  final last = first + 4;
  if (first < 0 || last >= _dhReadings.length) return null;
  final (b, _) = _splitReading(_dhReadings[first]);
  final (lastB, lastE) = _splitReading(_dhReadings[last]);
  final e = lastE ?? lastB;
  return DirshuDafHalacha(b, e == b ? null : e, true);
}

class DirshuDafHalachaEvent extends DailyLearningEvent {
  final DirshuDafHalacha reading;
  DirshuDafHalachaEvent(HDate date, this.reading)
      : super(date, '${reading.review ? 'Chazarah ' : ''}Mishnah Berurah ${_dhRange(reading, false)}');
  @override
  String get category => "Daf HaYomi B'Halacha";
  @override
  String render([String? locale]) =>
      "${Locale.gettext("Daf HaYomi B'Halacha", locale)}: ${renderBrief(locale)}";
  @override
  String renderBrief([String? locale]) {
    final prefix = reading.review ? '${Locale.gettext('Chazarah', locale)} ' : '';
    return '$prefix${Locale.gettext('Mishnah Berurah', locale)} ${_dhRange(reading, Locale.isHebrewLocale(locale))}';
  }

  @override
  String url() {
    final b = reading.b;
    final e = reading.e;
    final wholeSiman = !b.contains(':') || (e != null && !e.contains(':'));
    final range = e != null && !wholeSiman ? formatBeginEndRange(b, e) : b;
    return sefariaUrl('Shulchan Arukh, Orach Chayim', range.replaceAll(':', '.'));
  }

  @override
  List<String> getCategories() => const ['dirshuDafHalacha'];
}

String _dhRange(DirshuDafHalacha r, bool hebrew) {
  if (!hebrew) return r.e != null ? formatBeginEndRange(r.b, r.e!) : r.b;
  String gref(String ref) => ref.split(':').map(gematriyaNN).join(':');
  final begin = gref(r.b);
  if (r.e == null) return begin;
  final p1 = r.b.split(':');
  final p2 = r.e!.split(':');
  final end = p1[0] == p2[0] && p2.length > 1 ? gematriyaNN(p2[1]) : gref(r.e!);
  return '$begin-$end';
}

// ------------------------------------------------------------------ registration

void _wrap(String name, int? startAbs, LearningCalendarFn compute) {
  DailyLearning.addCalendar(name, (hd, il) {
    if (startAbs != null && hd.abs() < startAbs) return null;
    return compute(hd, il);
  }, startAbs != null ? HDate.fromAbs(startAbs) : null);
}

var _registered = false;

/// Registers all learning schedules with [DailyLearning]. Idempotent.
void registerLearningSchedules() {
  if (_registered) return;
  _registered = true;
  _wrap('arukhHaShulchanYomi', ahsyStart, (hd, _) => ArukhHaShulchanYomiEvent(hd, arukhHaShulchanYomi(hd.abs())));
  _wrap('dirshuAmudYomi', dirshuAmudYomiStart, (hd, _) => DirshuAmudYomiEvent(hd));
  _wrap('dirshuDafHalacha', dirshuDafHalachaStart, (hd, _) {
    final r = dirshuDafHalacha(hd.abs());
    return r == null ? null : DirshuDafHalachaEvent(hd, r);
  });
  _wrap('chofetzChaim', chofetzChaimStart, (hd, _) => ChofetzChaimEvent(hd, chofetzChaim(hd)));
  _wrap('dafWeekly', dafWeeklyStart, (hd, _) => DafWeeklyEvent(hd, dafWeekly(hd.abs())));
  _wrap('dafWeeklySunday', dafWeeklyStart,
      (hd, _) => hd.getDay() == 0 ? DafWeeklyEvent(hd, dafWeekly(hd.abs())) : null);
  _wrap('dafYomi', dafYomiOldStart, (hd, _) => DafYomiEvent(hd));
  _wrap('kitzurShulchanAruch', null, (hd, _) {
    final reading = kitzurShulchanAruch(hd, 'A');
    if (reading == null) return null;
    final optionB = hd.isLeapYear() && hd.getMonth() == Months.adarII ? kitzurShulchanAruch(hd, 'B') : null;
    return KitzurShulchanAruchEvent(hd, reading, optionB);
  });
  _wrap('mishnaYomi', mishnaYomiStart, (hd, _) => MishnaYomiEvent(hd, mishnaYomi(hd.abs())));
  _wrap('nachYomi', nachYomiStart, (hd, _) => NachYomiEvent(hd, nachYomi(hd.abs())));
  _wrap('pirkeiAvotSummer', null, (hd, il) {
    final r = pirkeiAvot(hd, il);
    return r == null ? null : PirkeiAvotSummerEvent(hd, r);
  });
  _wrap('psalms', null, (hd, _) => PsalmsEvent(hd, dailyPsalms(hd)));
  _wrap('rambam1', rambam1Start, (hd, _) => DailyRambamEvent(hd, dailyRambam1(hd.abs())));
  _wrap('rambam3', rambam1Start, (hd, _) => DailyRambam3Event(hd, dailyRambam3(hd.abs())));
  _wrap('perekYomi', perekYomiStart, (hd, _) => PerekYomiEvent(hd, perekYomi(hd.abs())));
  _wrap('seferHaMitzvot', seferHaMitzvotStart, (hd, _) => SeferHaMitzvotEvent(hd, seferHaMitzvot(hd.abs())));
  _wrap('shemiratHaLashon', shemiratHaLashonStart, (hd, _) => ShemiratHaLashonEvent(hd, shemiratHaLashon(hd)));
  _wrap('tanakhYomi', tanakhYomiStart, (hd, _) {
    final r = tanakhYomi(hd);
    return r == null ? null : TanakhYomiEvent(hd, r);
  });
  _wrap('yerushalmi-vilna', vilna.startAbs, (hd, _) {
    final r = yerushalmiYomi(hd.abs(), vilna);
    return r == null ? null : YerushalmiYomiEvent(hd, r);
  });
  _wrap('yerushalmi-schottenstein', schottenstein.startAbs,
      (hd, _) => YerushalmiYomiEvent(hd, yerushalmiYomi(hd.abs(), schottenstein)!));
  _wrap('929', nine29Start, (hd, _) {
    final r = calculate929(hd.abs());
    return r == null ? null : Nine29Event(hd, r);
  });
}

/// Human-friendly titles for each registered schedule, for UI pickers.
const Map<String, String> learningScheduleTitles = {
  'dafYomi': 'Daf Yomi (Bavli)',
  'mishnaYomi': 'Mishna Yomi',
  'nachYomi': 'Nach Yomi',
  'yerushalmi-vilna': 'Yerushalmi Yomi (Vilna)',
  'yerushalmi-schottenstein': 'Yerushalmi Yomi (Schottenstein)',
  'rambam1': 'Daily Rambam (1 chapter)',
  'rambam3': 'Daily Rambam (3 chapters)',
  'seferHaMitzvot': 'Sefer HaMitzvot',
  'chofetzChaim': 'Chofetz Chaim',
  'shemiratHaLashon': 'Shemirat HaLashon',
  'psalms': 'Daily Tehillim (monthly cycle)',
  'pirkeiAvotSummer': 'Pirkei Avot (summer Shabbatot)',
  'dafWeekly': 'Daf a Week',
  'dafWeeklySunday': 'Daf a Week (Sundays)',
  'kitzurShulchanAruch': 'Kitzur Shulchan Arukh Yomi',
  'arukhHaShulchanYomi': 'Arukh HaShulchan Yomi',
  'perekYomi': 'Perek Yomi (Mishnah)',
  'tanakhYomi': 'Tanakh Yomi',
  '929': '929 (Tanakh chapter a day)',
  'dirshuAmudYomi': 'Dirshu Amud HaYomi',
  'dirshuDafHalacha': "Dirshu Daf HaYomi B'Halacha",
};
