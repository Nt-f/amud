import 'package:hebcal/hebcal.dart';
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

String formatCountdown(Duration d) {
  if (d.isNegative) return 'now';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return '${h}h ${m}m';
  if (d.inMinutes > 0) return '${d.inMinutes} min';
  return '<1 min';
}

const weekdayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Shabbat'];
const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String formatPlainDate(PlainDate d, {bool weekday = true}) =>
    '${weekday ? '${weekdayNames[d.dayOfWeek]}, ' : ''}${monthNames[d.month - 1]} ${d.day}, ${d.year}';
