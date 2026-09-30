// Port of @hebcal/core sedra.ts / parshaYear.ts
// Hebcal - A Jewish Calendar Generator
// Copyright (c) 1994-2020 Danny Sadinoff
// Portions copyright Eyal Schachter and Michael J. Radwin
// Dart port licensed under GPL-2.0-or-later.

import 'hdate.dart';

const _incomplete = 0;
const _regular = 1;
const _complete = 2;

int _yearType(int hyear) {
  final longC = longCheshvan(hyear);
  final shortK = shortKislev(hyear);
  if (longC && !shortK) return _complete;
  if (!longC && shortK) return _incomplete;
  return _regular;
}

/// Result of [Sedra.lookup].
class SedraResult {
  /// Name of the parsha (or parshiyot), e.g. `['Noach']` or `['Matot', 'Masei']`.
  final List<String> parsha;

  /// True if it's a special holiday reading.
  final bool chag;

  /// Parsha number (1=Bereshit) or two numbers for doubled parsha; 0 for chag.
  final List<int> num;
  final HDate hdate;
  final bool il;
  const SedraResult(this.parsha, this.chag, this.num, this.hdate, this.il);
}

/// The 54 parshiyot of the Torah as transliterated strings.
const List<String> parshiot = [
  'Bereshit', 'Noach', 'Lech-Lecha', 'Vayera', 'Chayei Sara', 'Toldot', //
  'Vayetzei', 'Vayishlach', 'Vayeshev', 'Miketz', 'Vayigash', 'Vayechi',
  'Shemot', 'Vaera', 'Bo', 'Beshalach', 'Yitro', 'Mishpatim', 'Terumah',
  'Tetzaveh', 'Ki Tisa', 'Vayakhel', 'Pekudei', 'Vayikra', 'Tzav', 'Shmini',
  'Tazria', 'Metzora', 'Achrei Mot', 'Kedoshim', 'Emor', 'Behar', 'Bechukotai',
  'Bamidbar', 'Nasso', "Beha'alotcha", "Sh'lach", 'Korach', 'Chukat', 'Balak',
  'Pinchas', 'Matot', 'Masei', 'Devarim', 'Vaetchanan', 'Eikev', "Re'eh",
  'Shoftim', 'Ki Teitzei', 'Ki Tavo', 'Nitzavim', 'Vayeilech', "Ha'azinu",
  'Vezot Haberakhah',
];

final Map<String, int> _parsha2id = {
  for (var i = 0; i < parshiot.length; i++) parshiot[i]: i,
};

const _doubles = {21, 26, 28, 31, 38, 41, 50};
bool _isValidDouble(int id) => _doubles.contains(-id);
int _d(int p) => -p;

const _rh = 'Rosh Hashana';
const _yk = 'Yom Kippur';
const _sukkot = 'Sukkot';
const _chmSukot = 'Sukkot Shabbat Chol ha-Moed';
const _shmini = 'Shmini Atzeret';
const _pesach = 'Pesach';
const _pesach1 = 'Pesach I';
const _chmPesach = 'Pesach Shabbat Chol ha-Moed';
const _pesach7 = 'Pesach VII';
const _pesach8 = 'Pesach VIII';
const _shavuot = 'Shavuot';

List<int> _range(int start, int stop) =>
    [for (var k = start; k <= stop; k++) k];

List<Object> _cat(List<Object> start, List<Object> items) {
  final out = <Object>[...start];
  for (final x in items) {
    if (x is List) {
      out.addAll(x.cast<Object>());
    } else {
      out.add(x);
    }
  }
  return List.unmodifiable(out);
}

final Map<String, List<Object>> _types = _buildTypes();

Map<String, List<Object>> _buildTypes() {
  const yearStartVayeilech = <Object>[51, 52, _chmSukot];
  const yearStartHaazinu = <Object>[52, _yk, _chmSukot];
  const yearStartRH = <Object>[_rh, 52, _sukkot, _shmini];
  final r020 = _range(0, 20);
  final r027 = _range(0, 27);
  final r3340 = _range(33, 40);
  final r4349 = _range(43, 49);
  final r4350 = _range(43, 50);

  final t = <String, List<Object>>{
    '020': _cat(yearStartVayeilech, [r020, _d(21), 23, 24, _chmPesach, 25, _d(26), _d(28), 30, _d(31), r3340, _d(41), r4349, _d(50)]),
    '0220': _cat(yearStartVayeilech, [r020, _d(21), 23, 24, _chmPesach, 25, _d(26), _d(28), 30, _d(31), 33, _shavuot, _range(34, 37), _d(38), 40, _d(41), r4349, _d(50)]),
    '0510': _cat(yearStartHaazinu, [r020, _d(21), 23, 24, _pesach1, _pesach8, 25, _d(26), _d(28), 30, _d(31), r3340, _d(41), r4350]),
    '0511': _cat(yearStartHaazinu, [r020, _d(21), 23, 24, _pesach, 25, _d(26), _d(28), _range(30, 40), _d(41), r4350]),
    '052': _cat(yearStartHaazinu, [_range(0, 24), _pesach7, 25, _d(26), _d(28), 30, _d(31), r3340, _d(41), r4350]),
    '070': _cat(yearStartRH, [r020, _d(21), 23, 24, _pesach7, 25, _d(26), _d(28), 30, _d(31), r3340, _d(41), r4350]),
    '072': _cat(yearStartRH, [r020, _d(21), 23, 24, _chmPesach, 25, _d(26), _d(28), 30, _d(31), r3340, _d(41), r4349, _d(50)]),
    '1200': _cat(yearStartVayeilech, [r027, _chmPesach, _range(28, 33), _shavuot, _range(34, 37), _d(38), 40, _d(41), r4349, _d(50)]),
    '1201': _cat(yearStartVayeilech, [r027, _chmPesach, _range(28, 40), _d(41), r4349, _d(50)]),
    '1220': _cat(yearStartVayeilech, [r027, _pesach1, _pesach8, _range(28, 40), _d(41), r4350]),
    '1221': _cat(yearStartVayeilech, [r027, _pesach, _range(28, 50)]),
    '150': _cat(yearStartHaazinu, [_range(0, 28), _pesach7, _range(29, 50)]),
    '152': _cat(yearStartHaazinu, [_range(0, 28), _chmPesach, _range(29, 49), _d(50)]),
    '170': _cat(yearStartRH, [r027, _chmPesach, _range(28, 40), _d(41), r4349, _d(50)]),
    '1720': _cat(yearStartRH, [r027, _chmPesach, _range(28, 33), _shavuot, _range(34, 37), _d(38), 40, _d(41), r4349, _d(50)]),
  };
  t['0221'] = t['020']!;
  t['0310'] = t['0220']!;
  t['0311'] = t['020']!;
  t['1310'] = t['1220']!;
  t['1311'] = t['1221']!;
  t['1721'] = t['170']!;
  return t;
}

/// Represents Parashah HaShavua for an entire Hebrew year.
class Sedra {
  final int year;
  final bool il;
  late final int _rhAbs;
  late final int firstSaturday;
  late final List<Object> _sedraArray;
  late final String yearKey;

  Sedra(this.year, this.il) {
    final rh0 = HDate(1, Months.tishrei, year);
    _rhAbs = rh0.abs();
    final rhDay = rh0.getDay() + 1;
    firstSaturday = HDate.dayOnOrBefore(6, _rhAbs + 6);
    final leap = isLeapYear(year) ? 1 : 0;
    final type = _yearType(year);
    var key = '$leap$rhDay$type';
    var arr = _types[key];
    if (arr == null) {
      key = '$key${il ? 1 : 0}';
      arr = _types[key];
    }
    if (arr == null) {
      throw StateError('improper sedra year type $key calculated for $year');
    }
    _sedraArray = arr;
    yearKey = key;
  }

  List<Object> getSedraArray() => _sedraArray;
  int getFirstSaturday() => firstSaturday;

  /// Returns the date that a parsha (by number, name or 'X-Y' name) occurs,
  /// or null if it doesn't occur this year.
  HDate? find(Object parsha) {
    if (parsha is int) {
      if (parsha >= parshiot.length || (parsha < 0 && !_isValidDouble(parsha))) {
        throw RangeError('Invalid parsha number: $parsha');
      }
      return _findInternal(parsha);
    }
    if (parsha is String) {
      final num = _parsha2id[parsha];
      if (num != null) return find(num);
      if (parsha.contains('-')) {
        if (parsha == _chmPesach || parsha == _chmSukot) {
          return _findInternal(parsha);
        }
        return find(parsha.split('-'));
      }
      return _findInternal(parsha);
    }
    if (parsha is List<String>) {
      if (parsha.length == 1) return find(parsha[0]);
      if (parsha.length != 2) throw ArgumentError('Invalid parsha argument');
      final num1 = _parsha2id[parsha[0]];
      final num2 = _parsha2id[parsha[1]];
      if (num1 == null || num2 == null || num2 != num1 + 1 || !_isValidDouble(-num1)) {
        throw RangeError('Unrecognized parsha name: ${parsha.join('-')}');
      }
      return find(-num1);
    }
    return null;
  }

  HDate? _findInternal(Object parsha) {
    final idx = _sedraArray.indexOf(parsha);
    if (idx == -1) return null;
    return HDate.fromAbs(firstSaturday + idx * 7);
  }

  /// Like [find] but also matches when the parsha is read as part of a double.
  HDate? findContaining(Object parsha) {
    final hdate = find(parsha);
    if (hdate != null) return hdate;
    int? num = parsha is int ? parsha : _parsha2id[parsha as String];
    if (num != null) {
      final p1 = -num;
      return _isValidDouble(p1) ? find(p1) : find(p1 + 1);
    }
    return find((parsha as String).split('-')[0]);
  }

  /// Returns the parsha (or holiday reading) for the Shabbat on or after [hd].
  SedraResult lookup(Object hd) {
    final abs = hd is int ? hd : (hd as HDate).abs();
    if (abs < _rhAbs) {
      throw RangeError('Date $hd before start of Hebrew year $year');
    }
    final saturday = HDate.dayOnOrBefore(6, abs + 6);
    final weekNum = (saturday - firstSaturday) ~/ 7;
    if (weekNum >= _sedraArray.length) {
      return getSedra(year + 1, il).lookup(saturday);
    }
    final index = _sedraArray[weekNum];
    final hdate = HDate.fromAbs(saturday);
    if (index is String) {
      return SedraResult([index], true, const [0], hdate, il);
    }
    final i = index as int;
    if (i >= 0) {
      return SedraResult([parshiot[i]], false, [i + 1], hdate, il);
    }
    final p1 = -i;
    return SedraResult([parshiot[p1], parshiot[p1 + 1]], false, [p1 + 1, p1 + 2], hdate, il);
  }

  /// Returns the parsha read on a Monday or Thursday (null for other days).
  SedraResult? lookupWeekday(Object hd) {
    final abs = hd is int ? hd : (hd as HDate).abs();
    if (abs < _rhAbs) {
      throw RangeError('Date $hd before start of Hebrew year $year');
    }
    final day = HDate.fromAbs(abs).getDay();
    if (day != 1 && day != 4) return null;
    final saturday = HDate.fromAbs(HDate.dayOnOrBefore(6, abs + 6));
    final parsha = lookup(saturday);
    if (!parsha.chag) return parsha;
    return _findWeekdayParsha(saturday);
  }

  SedraResult _findWeekdayParsha(HDate saturday) {
    final hyear = saturday.getFullYear();
    if (saturday.getMonth() == Months.tishrei) {
      final dd = saturday.getDate();
      final simchatTorah = il ? 22 : 23;
      if (dd > 2 && dd <= simchatTorah) {
        return SedraResult(const ['Vezot Haberakhah'], false, const [54], saturday, il);
      }
    }
    final sedra = hyear == year ? this : getSedra(hyear, il);
    final endOfYear = HDate(1, Months.tishrei, hyear + 1).abs() - 1;
    final endAbs = endOfYear + 30;
    for (var sat2 = saturday.abs() + 7; sat2 <= endAbs; sat2 += 7) {
      final sedra2 = sat2 > endOfYear ? getSedra(hyear + 1, il) : sedra;
      final parsha2 = sedra2.lookup(sat2);
      if (!parsha2.chag) return parsha2;
    }
    throw StateError("can't find weekday parsha for $saturday/$il");
  }
}

final Map<String, Sedra> _sedraCache = {};

/// Convenience function to create an instance of Sedra or reuse a cached one.
Sedra getSedra(int hyear, bool il) {
  final key = '$hyear-${il ? 1 : 0}';
  if (_sedraCache.length > 120) _sedraCache.clear();
  return _sedraCache.putIfAbsent(key, () => Sedra(hyear, il));
}
