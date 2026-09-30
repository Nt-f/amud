// Port of @hebcal/hdate greg.ts
// Copyright (c) 1994-2020 Danny Sadinoff; Portions copyright Eyal Schachter
// and Michael J. Radwin. Dart port licensed under GPL-2.0-or-later.

const List<int> _lengths = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

int _mod(int x, int y) => x - y * (x / y).floor();
int _quotient(int x, int y) => (x / y).floor();

int _yearFromFixed(int abs) {
  final l0 = abs - 1;
  final n400 = _quotient(l0, 146097);
  final d1 = _mod(l0, 146097);
  final n100 = _quotient(d1, 36524);
  final d2 = _mod(d1, 36524);
  final n4 = _quotient(d2, 1461);
  final d3 = _mod(d2, 1461);
  final n1 = _quotient(d3, 365);
  final year = 400 * n400 + 100 * n100 + 4 * n4 + n1;
  return n100 != 4 && n1 != 4 ? year + 1 : year;
}

/// Returns true if the Gregorian year is a leap year.
bool isGregLeapYear(int year) =>
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

/// Number of days in the Gregorian month (1-based month).
int daysInGregMonth(int month, int year) {
  if (month == 2 && isGregLeapYear(year)) return 29;
  return _lengths[month];
}

int _toFixed(int year, int month, int day) {
  final py = year - 1;
  return 365 * py +
      _quotient(py, 4) -
      _quotient(py, 100) +
      _quotient(py, 400) +
      _quotient(367 * month - 362, 12) +
      (month <= 2
          ? 0
          : isGregLeapYear(year)
              ? -1
              : -2) +
      day;
}

/// Converts a Gregorian calendar date (year/month/day fields only; the time
/// and time zone are ignored) to an R.D. (Rata Die) absolute day number.
int greg2abs(DateTime date) => _toFixed(date.year, date.month, date.day);

/// Converts year/month/day to R.D. without constructing a DateTime.
int gregYmdToAbs(int year, int month, int day) => _toFixed(year, month, day);

/// Converts an R.D. absolute day number to a Gregorian date. The returned
/// DateTime is a local-midnight date; only the y/m/d fields are meaningful.
DateTime abs2greg(int abs) {
  final year = _yearFromFixed(abs);
  final priorDays = abs - _toFixed(year, 1, 1);
  final correction = abs < _toFixed(year, 3, 1)
      ? 0
      : isGregLeapYear(year)
          ? 1
          : 2;
  final month = _quotient(12 * (priorDays + correction) + 373, 367);
  final day = abs - _toFixed(year, month, 1) + 1;
  return DateTime(year, month, day);
}

/// A calendar date with no time or zone (like Temporal.PlainDate).
class PlainDate implements Comparable<PlainDate> {
  final int year;
  final int month;
  final int day;
  const PlainDate(this.year, this.month, this.day);

  factory PlainDate.fromDateTime(DateTime dt) =>
      PlainDate(dt.year, dt.month, dt.day);

  factory PlainDate.fromAbs(int abs) =>
      PlainDate.fromDateTime(abs2greg(abs));

  int get abs => gregYmdToAbs(year, month, day);

  /// 0 = Sunday ... 6 = Saturday
  int get dayOfWeek => _mod(abs, 7);

  PlainDate addDays(int n) => PlainDate.fromAbs(abs + n);

  DateTime toDateTime() => DateTime(year, month, day);

  @override
  int compareTo(PlainDate other) => abs.compareTo(other.abs);

  @override
  bool operator ==(Object other) =>
      other is PlainDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}
