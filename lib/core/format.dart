import 'package:hebcal/hebcal.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

/// Formats an instant as wall-clock time at [loc].
String formatTime(DateTime? t, Location loc, {bool? hour12, bool seconds = false}) {
  if (t == null) return '—';
  final l = tz.TZDateTime.from(t, loc.tzLocation);
  final h12 = hour12 ?? const {'US', 'CA', 'AU', 'NZ', 'IN', 'PH'}.contains(loc.getCountryCode());
  final mm = l.minute.toString().padLeft(2, '0');
  final ss = seconds ? ':${l.second.toString().padLeft(2, '0')}' : '';
  if (!h12) return '${l.hour.toString().padLeft(2, '0')}:$mm$ss';
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  return '$h:$mm$ss ${l.hour < 12 ? 'AM' : 'PM'}';
}

/// Language of formatted dates and countdowns: 'en', or 'he' for the
/// Hebrew and Yiddish interfaces. Set from the interface language.
String dateLocale = 'en';

String formatCountdown(Duration d) {
  final he = dateLocale != 'en';
  if (d.isNegative) return he ? 'עכשיו' : 'now';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return he ? '$h שע׳ $m דק׳' : '${h}h ${m}m';
  if (d.inMinutes > 0) return he ? '${d.inMinutes} דק׳' : '${d.inMinutes} min';
  return he ? 'פחות מדקה' : '<1 min';
}

const weekdayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Shabbat'];
const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// Spelling of the seventh day in formatted dates; set from the Ashkenazi
/// spelling preference.
String shabbatName = 'Shabbat';

String formatPlainDate(PlainDate d, {bool weekday = true, bool year = true}) {
  if (dateLocale != 'en') {
    try {
      final f = switch ((weekday, year)) {
        (true, true) => DateFormat.yMMMMEEEEd(dateLocale),
        (true, false) => DateFormat.MMMMEEEEd(dateLocale),
        (false, true) => DateFormat.yMMMMd(dateLocale),
        (false, false) => DateFormat.MMMMd(dateLocale),
      };
      return f.format(DateTime(d.year, d.month, d.day));
    } catch (_) {
      // Date symbols not loaded (outside the app): English below.
    }
  }
  return '${weekday ? '${d.dayOfWeek == 6 ? shabbatName : weekdayNames[d.dayOfWeek]}, ' : ''}${monthNames[d.month - 1]} ${d.day}${year ? ', ${d.year}' : ''}';
}

/// A month and year, e.g. "October 2026".
String formatMonth(int year, int month) {
  if (dateLocale != 'en') {
    try {
      return DateFormat.yMMMM(dateLocale).format(DateTime(year, month));
    } catch (_) {}
  }
  return '${monthNames[month - 1]} $year';
}
