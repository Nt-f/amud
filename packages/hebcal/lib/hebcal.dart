/// Dart port of Hebcal — Jewish calendar, holidays, parsha, zmanim, omer,
/// molad, candle-lighting and daily learning schedules.
///
/// Call [initHebcal] once (it loads the IANA time zone database and
/// registers learning schedules) before using zmanim or [calendar].
library;

import 'package:timezone/data/latest_all.dart' as tzdata;

import 'src/learning/learning.dart';

export 'src/calendar.dart';
export 'src/event.dart';
export 'src/greg.dart';
export 'src/halacha.dart';
export 'src/hdate.dart';
export 'src/holidays.dart';
export 'src/learning/learning.dart';
export 'src/leyning.dart';
export 'src/locale.dart';
export 'src/location.dart';
export 'src/molad.dart';
export 'src/noaa.dart';
export 'src/omer.dart';
export 'src/sedra.dart';
export 'src/zmanim.dart';

var _initialized = false;

/// Initializes the time zone database and registers the learning schedules.
/// Safe to call multiple times.
void initHebcal() {
  if (_initialized) return;
  _initialized = true;
  tzdata.initializeTimeZones();
  registerLearningSchedules();
}
